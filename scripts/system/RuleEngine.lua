-- ============================================================================
-- system/RuleEngine.lua - 规则引擎
-- 负责点数计算、7规则判定、胜负判定
-- 新规则: 9(0或9) / 10(弃置过+1) / J(翻倍对方普通牌) / Q(对方最小变0) / K(+1)
-- ============================================================================

local Card = require("core.Card")
local Constant = require("core.Constant")
local GameConfig = require("core.GameConfig")

local RuleEngine = {}

--- 计算一手牌的最终点数(含特效)
--- @param hand table[] 自己的手牌
--- @param opponentHand table[] 对手的手牌
--- @param playerState table|nil PlayerState (用于读取 discardedTenCount/discardedJackCount)
--- @param opponentState table|nil 对手的 PlayerState
--- @return number finalPoints
--- @return table details
function RuleEngine.CalculatePoints(hand, opponentHand, playerState, opponentState)
    local details = {
        basePoints = 0,
        aceEffects = {},
        eightEffects = 0,
        sevenCount = 0,
        nineFlexSaved = 0,
        tenBonus = 0,
        jackDoubleEffect = false,
        queenNullified = false,
        kingBonus = 0,
        finalPoints = 0,
    }

    -- =======================================================================
    -- 0. 对方 J 效果: 若对方弃置过 J, 则我方普通牌(2-6)点数翻倍
    -- =======================================================================
    local opponentJackDouble = false
    if opponentState and opponentState.discardedJackCount > 0 then
        opponentJackDouble = true
        details.jackDoubleEffect = true
    end

    -- =======================================================================
    -- 1. 对方 Q 效果: 使我方手牌中点数最小的一张牌变为 0
    -- =======================================================================
    local queenNullifiedIdx = nil
    local opponentQueenCount = 0
    for _, card in ipairs(opponentHand) do
        if card.rank == 12 then
            opponentQueenCount = opponentQueenCount + 1
        end
    end
    if opponentQueenCount > 0 then
        -- 找我方点数最小的非0牌(排除鬼牌、Q/K等本身就是0的)
        local minPts = math.huge
        local minIdx = nil
        for i, card in ipairs(hand) do
            local pts = Card.GetBasePoints(card)
            -- 7不可被修改
            if pts > 0 and card.rank ~= 7 then
                if pts < minPts then
                    minPts = pts
                    minIdx = i
                end
            end
        end
        if minIdx then
            queenNullifiedIdx = minIdx
            details.queenNullified = true
        end
    end

    -- =======================================================================
    -- 2. 收集对手的 Ace 花色 (翻倍我方同花色)
    -- =======================================================================
    local aceDoubledSuits = {}
    for _, card in ipairs(opponentHand) do
        if card.rank == 1 then
            aceDoubledSuits[card.suit] = true
            table.insert(details.aceEffects, card.suit)
        end
    end

    -- =======================================================================
    -- 3. 统计自己手中 8 的数量 (降低自己普通牌1点)
    -- =======================================================================
    local myEightCount = 0
    for _, card in ipairs(hand) do
        if card.rank == 8 then
            myEightCount = myEightCount + 1
        end
    end
    details.eightEffects = myEightCount

    -- =======================================================================
    -- 4. 逐张计算点数
    -- =======================================================================
    local totalPoints = 0
    for i, card in ipairs(hand) do
        local points = Card.GetBasePoints(card)

        -- Q 效果: 被 nullify 的牌变为 0
        if i == queenNullifiedIdx then
            points = 0
        else
            -- 9 的灵活选择: 可视为0或9, 根据接近21最优化选择
            -- (先按 9 计算, 后续再优化)
            if card.rank == 9 then
                -- 暂时保持原值, 后面做全局优化
            end

            -- 7 不可被改变点数, 跳过其他效果
            if card.rank == 7 then
                totalPoints = totalPoints + points
                goto continue
            end

            -- J 翻倍效果: 对方弃置过 J, 我方普通牌(2-6)翻倍
            if opponentJackDouble and Card.IsNormal(card) then
                points = points * 2
            end

            -- Ace 翻倍效果
            if card.suit and aceDoubledSuits[card.suit] then
                points = points * 2
            end

            -- 8 效果: 自己的普通牌(2~6) 每张8降1点
            if Card.IsNormal(card) and myEightCount > 0 then
                points = math.max(0, points - myEightCount)
            end
        end

        totalPoints = totalPoints + points
        ::continue::
    end

    -- =======================================================================
    -- 5. 9 的灵活选择优化: 如果总点 > 21, 尝试把 9 变为 0
    -- =======================================================================
    if totalPoints > GameConfig.TARGET_POINTS then
        for i, card in ipairs(hand) do
            if card.rank == 9 and i ~= queenNullifiedIdx then
                -- 当前 9 贡献了多少点? 重新计算
                local nineContribution = 9
                -- 应用可能的翻倍效果
                if opponentJackDouble then
                    -- 9 不是 normal(2-6), 不受 J 翻倍
                end
                if card.suit and aceDoubledSuits[card.suit] then
                    nineContribution = nineContribution * 2
                end
                -- 如果变为 0 能让结果更接近 21
                local withoutNine = totalPoints - nineContribution
                if math.abs(withoutNine - GameConfig.TARGET_POINTS) < math.abs(totalPoints - GameConfig.TARGET_POINTS) then
                    totalPoints = withoutNine
                    details.nineFlexSaved = details.nineFlexSaved + nineContribution
                end
            end
        end
    end

    -- =======================================================================
    -- 6. K 效果: 在 Settle 中统一处理(对方取整+自己-5取整)
    -- =======================================================================
    local kingCount = 0
    for _, card in ipairs(hand) do
        if card.rank == 13 then
            kingCount = kingCount + 1
        end
    end
    details.kingCount = kingCount

    -- =======================================================================
    -- 7. 10 效果: 每张弃置过的 10 给最终点数 +1
    -- =======================================================================
    local tenBonus = 0
    if playerState then
        tenBonus = playerState.discardedTenCount
    end
    totalPoints = totalPoints + tenBonus
    details.tenBonus = tenBonus

    details.basePoints = totalPoints
    details.finalPoints = totalPoints
    return totalPoints, details
end

--- 检查7的特殊胜利条件
---@param hand table[]
---@param opponentHand table[]
---@return string|nil "win" / "lose" / nil
function RuleEngine.CheckSevenRule(hand, opponentHand)
    local mySevenCount = 0
    for _, card in ipairs(hand) do
        if Card.CanCountAsSeven(card) then
            mySevenCount = mySevenCount + 1
        end
    end

    if mySevenCount < 3 then return nil end

    -- 有3张7，检查对方是否有可视为7的牌
    local opponentSevenCount = 0
    for _, card in ipairs(opponentHand) do
        if Card.CanCountAsSeven(card) then
            opponentSevenCount = opponentSevenCount + 1
        end
    end

    if opponentSevenCount == 0 then
        return "win"   -- 对方无7，胜利
    elseif opponentSevenCount >= 2 then
        return "lose"  -- 对方有2+张7，失败
    end

    return nil  -- 对方有1张7，无特殊效果
end

--- 执行结算判定
---@param playerHand table[]
---@param aiHand table[]
---@param playerState table|nil PlayerState
---@param aiState table|nil AI PlayerState
---@return table result {winner, playerPoints, aiPoints, ...}
function RuleEngine.Settle(playerHand, aiHand, playerState, aiState)
    local result = {
        winner = nil,
        playerPoints = 0,
        aiPoints = 0,
        playerDetails = nil,
        aiDetails = nil,
        sevenRuleTriggered = false,
    }

    -- 先检查7特殊规则
    local playerSeven = RuleEngine.CheckSevenRule(playerHand, aiHand)
    local aiSeven = RuleEngine.CheckSevenRule(aiHand, playerHand)

    if playerSeven == "win" and aiSeven == "win" then
        result.winner = "tie"
        result.sevenRuleTriggered = true
    elseif playerSeven == "win" then
        result.winner = "player"
        result.sevenRuleTriggered = true
    elseif playerSeven == "lose" then
        result.winner = "ai"
        result.sevenRuleTriggered = true
    elseif aiSeven == "win" then
        result.winner = "ai"
        result.sevenRuleTriggered = true
    elseif aiSeven == "lose" then
        result.winner = "player"
        result.sevenRuleTriggered = true
    end

    if not result.sevenRuleTriggered then
        -- 正常结算: 比较谁更接近21
        local playerPts, playerDetails = RuleEngine.CalculatePoints(playerHand, aiHand, playerState, aiState)
        local aiPts, aiDetails = RuleEngine.CalculatePoints(aiHand, playerHand, aiState, playerState)

        -- K 效果: 持有K时，对方点数向上取整，自己点数-5后向下取整
        local playerKings = playerDetails.kingCount or 0
        local aiKings = aiDetails.kingCount or 0

        if playerKings > 0 then
            aiPts = math.ceil(aiPts)         -- 对方向上取整
            playerPts = math.floor(playerPts - 5)  -- 自己-5后向下取整
            playerDetails.kingApplied = true
        end
        if aiKings > 0 then
            playerPts = math.ceil(playerPts)  -- 对方向上取整
            aiPts = math.floor(aiPts - 5)     -- 自己-5后向下取整
            aiDetails.kingApplied = true
        end

        result.playerPoints = playerPts
        result.aiPoints = aiPts
        result.playerDetails = playerDetails
        result.aiDetails = aiDetails

        local playerDist = math.abs(GameConfig.TARGET_POINTS - playerPts)
        local aiDist = math.abs(GameConfig.TARGET_POINTS - aiPts)

        if playerDist < aiDist then
            result.winner = "player"
        elseif aiDist < playerDist then
            result.winner = "ai"
        else
            result.winner = "tie"
        end
    end

    return result
end

return RuleEngine
