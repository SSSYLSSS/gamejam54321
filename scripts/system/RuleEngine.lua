-- ============================================================================
-- system/RuleEngine.lua - 规则引擎 (v3)
-- 新规则:
--   A: 对方同花色牌点数翻倍(×2)
--   8: 己方普通牌(2-7)各-2, 对方普通牌各+2
--   9: 点数可视为0或9(自动优化)
--   10: 己方稀有牌(8-10)+罕见牌(J/Q/K)各-9点
--   J: 己方普通牌(2-7)点数全部视为0
--   Q: 对方点数最高的普通牌×2, 己方最终点数取至十位
--   K: 对方普通牌(2-7)+稀有牌(8-10)点数×2
--   小王: 点数0~13
--   大王: 结算前改一张牌点数, 自身0~13
--   结算顺序: 基础点 → 加减(8) → 乘算(A,K,J→0) → 最终修正(10,Q)
-- ============================================================================

local Card = require("core.Card")
local Constant = require("core.Constant")
local GameConfig = require("core.GameConfig")

local RuleEngine = {}

--- 获取牌的基础点数(考虑jokerOverride和jokerValue)
---@param card table
---@return number
local function getBasePoints(card)
    -- 大王覆盖了某张牌的点数
    if card.jokerOverride then
        return card.jokerOverride
    end
    -- 小王/大王自身选择的点数
    if card.jokerValue then
        return card.jokerValue
    end
    return Card.GetBasePoints(card)
end

--- 计算一手牌的最终点数(含特效)
--- @param hand table[] 自己的手牌
--- @param opponentHand table[] 对手的手牌
--- @param playerState table|nil PlayerState
--- @param opponentState table|nil 对手的 PlayerState
--- @return number finalPoints
--- @return table details
function RuleEngine.CalculatePoints(hand, opponentHand, playerState, opponentState)
    local details = {
        basePoints = 0,
        aceEffects = {},         -- 被对方A翻倍的花色列表
        eightEffects = 0,        -- 己方8的数量
        opponentEightCount = 0,  -- 对方8的数量
        nineFlexSaved = 0,       -- 9灵活节省的点数
        tenReduce = 0,           -- 10效果减少的点数
        jackActive = false,      -- J效果是否生效
        queenTriple = 0,         -- Q效果对对方的加成
        queenFloor = false,      -- Q效果使己方取整
        kingActive = false,      -- K效果是否生效
        finalPoints = 0,
        cardBreakdown = {},      -- 每张牌的计算过程 {name, base, effects={}, final}
    }

    -- =======================================================================
    -- Step 1: 收集各效果触发情况 (nullified 的牌不触发效果)
    -- =======================================================================

    -- 对手的 Ace 花色 (翻倍我方同花色牌)
    local aceDoubledSuits = {}
    for _, card in ipairs(opponentHand) do
        if card.rank == 1 and not card.nullified then
            aceDoubledSuits[card.suit] = (aceDoubledSuits[card.suit] or 0) + 1
            table.insert(details.aceEffects, card.suit)
        end
    end

    -- 己方8数量 (己方普通牌各-2)
    local myEightCount = 0
    for _, card in ipairs(hand) do
        if card.rank == 8 and not card.nullified then
            myEightCount = myEightCount + 1
        end
    end
    -- 对方8数量 (己方普通牌各+2)
    local opponentEightCount = 0
    for _, card in ipairs(opponentHand) do
        if card.rank == 8 and not card.nullified then
            opponentEightCount = opponentEightCount + 1
        end
    end
    details.eightEffects = myEightCount
    details.opponentEightCount = opponentEightCount

    -- 己方J数量 (己方普通牌→0)
    local myJackCount = 0
    for _, card in ipairs(hand) do
        if card.rank == 11 and not card.nullified then
            myJackCount = myJackCount + 1
        end
    end
    if myJackCount > 0 then
        details.jackActive = true
    end

    -- 对方K数量 (己方普通牌+稀有牌×2)
    local opponentKingCount = 0
    for _, card in ipairs(opponentHand) do
        if card.rank == 13 and not card.nullified then
            opponentKingCount = opponentKingCount + 1
        end
    end
    if opponentKingCount > 0 then
        details.kingActive = true
    end

    -- 己方10数量 (己方稀有牌+罕见牌各-9)
    local myTenCount = 0
    for _, card in ipairs(hand) do
        if card.rank == 10 and not card.nullified then
            myTenCount = myTenCount + 1
        end
    end

    -- =======================================================================
    -- Step 2: 逐张计算点数 (按结算顺序: 基础 → 加减8 → 乘算A/K/J→0 → 最终修正10)
    -- =======================================================================
    local totalPoints = 0

    for i, card in ipairs(hand) do
        local basePoints = getBasePoints(card)
        local points = basePoints
        local breakdown = { name = Card.GetName(card), base = basePoints, effects = {}, final = 0 }
        local isNormal = Card.IsNormal(card)
        local isFace = Card.IsFace(card)

        -- nullified 的牌: 只算基础点数, 不参与任何效果加成
        if card.nullified then
            breakdown.final = points
            table.insert(details.cardBreakdown, breakdown)
            totalPoints = totalPoints + points
            goto continue
        end

        -- ----- Step 2b: 加减效果 (8) -----
        -- 8 对普通牌(2-7)的加减: 己方每张8使-2, 对方每张8使+2
        if isNormal and (myEightCount > 0 or opponentEightCount > 0) then
            local delta = -myEightCount * 2 + opponentEightCount * 2
            points = math.max(0, points + delta)
            local parts = {}
            if myEightCount > 0 then
                table.insert(parts, string.format("己8(-%d)", myEightCount * 2))
            end
            if opponentEightCount > 0 then
                table.insert(parts, string.format("对8(+%d)", opponentEightCount * 2))
            end
            table.insert(breakdown.effects, table.concat(parts, ","))
        end

        -- ----- Step 2c: 乘算效果 (A, K, J→0) -----
        -- J 效果: 己方有J时, 己方普通牌(2-7)点数全部视为0
        if isNormal and myJackCount > 0 then
            points = 0
            table.insert(breakdown.effects, "J→0")
        end

        -- K 效果 (对方K使己方普通牌+稀有牌×2, 叠加多张K)
        local isNormalOrRare = isNormal or (card.rank >= 8 and card.rank <= 10)
        if isNormalOrRare and opponentKingCount > 0 then
            for _ = 1, opponentKingCount do
                points = points * 2
            end
            table.insert(breakdown.effects, string.format("K×%d", 2 ^ opponentKingCount))
        end

        -- A 翻倍效果: 对方A使己方同花色牌点数翻倍
        if card.suit and aceDoubledSuits[card.suit] then
            local aceCount = aceDoubledSuits[card.suit]
            for _ = 1, aceCount do
                points = points * 2
            end
            table.insert(breakdown.effects, string.format("A×%d", 2 ^ aceCount))
        end

        -- ----- Step 2d: 最终修正 (10: 己方稀有牌+罕见牌-9) -----
        -- 10 效果: 己方每张10使己方稀有牌(8-10)和罕见牌(J/Q/K)各-9
        local isRareOrFace = (card.rank >= 8 and card.rank <= 10) or isFace
        if isRareOrFace and myTenCount > 0 then
            local reduce = myTenCount * 9
            points = points - reduce
            -- 可以为负数
            table.insert(breakdown.effects, string.format("10(-%d)", reduce))
            details.tenReduce = details.tenReduce + reduce
        end

        breakdown.final = points
        table.insert(details.cardBreakdown, breakdown)
        totalPoints = totalPoints + points
        ::continue::
    end

    -- =======================================================================
    -- Step 3: 9 的灵活选择优化: 如果总点 > 21, 尝试把 9 变为 0
    -- =======================================================================
    if totalPoints > GameConfig.TARGET_POINTS then
        for i, card in ipairs(hand) do
            if card.rank == 9 and not card.nullified then
                -- 当前 9 贡献了多少点
                local nineContribution = details.cardBreakdown[i] and details.cardBreakdown[i].final or 9
                if nineContribution > 0 then
                    local withoutNine = totalPoints - nineContribution
                    if math.abs(withoutNine - GameConfig.TARGET_POINTS) < math.abs(totalPoints - GameConfig.TARGET_POINTS) then
                        totalPoints = withoutNine
                        details.nineFlexSaved = details.nineFlexSaved + nineContribution
                        if details.cardBreakdown[i] then
                            details.cardBreakdown[i].final = 0
                            table.insert(details.cardBreakdown[i].effects, "灵活→0")
                        end
                    end
                end
            end
        end
    end

    details.basePoints = totalPoints
    details.finalPoints = totalPoints
    return totalPoints, details
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
    }

    -- 正常结算
    local playerPts, playerDetails = RuleEngine.CalculatePoints(playerHand, aiHand, playerState, aiState)
    local aiPts, aiDetails = RuleEngine.CalculatePoints(aiHand, playerHand, aiState, playerState)

    -- =======================================================================
    -- Q 效果 (在Settle中处理, 因为涉及双方最终点数的交叉影响)
    -- Q: 对方点数最高的一张普通牌×3, 己方最终点数向下取整
    -- =======================================================================
    local playerQueenCount = 0
    for _, card in ipairs(playerHand) do
        if card.rank == 12 and not card.nullified then playerQueenCount = playerQueenCount + 1 end
    end
    local aiQueenCount = 0
    for _, card in ipairs(aiHand) do
        if card.rank == 12 and not card.nullified then aiQueenCount = aiQueenCount + 1 end
    end

    -- 玩家Q效果: 对方(AI)点数最高的普通牌×2, 己方点数取至十位
    if playerQueenCount > 0 then
        -- 找AI手牌中点数最高的普通牌的当前最终点数
        local maxNormalPts = 0
        local maxNormalIdx = nil
        for i, card in ipairs(aiHand) do
            if Card.IsNormal(card) and not card.nullified then
                local cardFinal = aiDetails.cardBreakdown[i] and aiDetails.cardBreakdown[i].final or 0
                if cardFinal > maxNormalPts then
                    maxNormalPts = cardFinal
                    maxNormalIdx = i
                end
            end
        end
        if maxNormalIdx and maxNormalPts > 0 then
            -- ×2 意味着额外增加 (2-1)*点数 = 1倍的点数
            local queenBonus = maxNormalPts * 1 * playerQueenCount
            aiPts = aiPts + queenBonus
            playerDetails.queenTriple = queenBonus
            -- 更新AI breakdown
            if aiDetails.cardBreakdown[maxNormalIdx] then
                aiDetails.cardBreakdown[maxNormalIdx].final = aiDetails.cardBreakdown[maxNormalIdx].final + queenBonus
                table.insert(aiDetails.cardBreakdown[maxNormalIdx].effects, string.format("Q×2(+%d)", queenBonus))
            end
        end
        -- 取至十位: 向下取整到最近的10的倍数
        playerPts = math.floor(playerPts / 10) * 10
        playerDetails.queenFloor = true
    end

    -- AI的Q效果: 对方(玩家)点数最高的普通牌×2, AI点数取至十位
    if aiQueenCount > 0 then
        local maxNormalPts = 0
        local maxNormalIdx = nil
        for i, card in ipairs(playerHand) do
            if Card.IsNormal(card) and not card.nullified then
                local cardFinal = playerDetails.cardBreakdown[i] and playerDetails.cardBreakdown[i].final or 0
                if cardFinal > maxNormalPts then
                    maxNormalPts = cardFinal
                    maxNormalIdx = i
                end
            end
        end
        if maxNormalIdx and maxNormalPts > 0 then
            local queenBonus = maxNormalPts * 1 * aiQueenCount
            playerPts = playerPts + queenBonus
            aiDetails.queenTriple = queenBonus
            if playerDetails.cardBreakdown[maxNormalIdx] then
                playerDetails.cardBreakdown[maxNormalIdx].final = playerDetails.cardBreakdown[maxNormalIdx].final + queenBonus
                table.insert(playerDetails.cardBreakdown[maxNormalIdx].effects, string.format("Q×2(+%d)", queenBonus))
            end
        end
        -- 取至十位: 向下取整到最近的10的倍数
        aiPts = math.floor(aiPts / 10) * 10
        aiDetails.queenFloor = true
    end

    result.playerPoints = playerPts
    result.aiPoints = aiPts
    result.playerDetails = playerDetails
    result.aiDetails = aiDetails

    -- 胜负判定: 超21爆牌优先
    local playerOver = playerPts > GameConfig.TARGET_POINTS
    local aiOver = aiPts > GameConfig.TARGET_POINTS

    if playerOver and not aiOver then
        result.winner = "ai"
    elseif aiOver and not playerOver then
        result.winner = "player"
    else
        -- 双方都没爆 或 双方都爆了 → 比较谁更接近21
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
