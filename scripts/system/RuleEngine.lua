-- ============================================================================
-- system/RuleEngine.lua - 规则引擎
-- 负责点数计算、7规则判定、胜负判定
-- ============================================================================

local Card = require("core.Card")
local Constant = require("core.Constant")
local GameConfig = require("core.GameConfig")

local RuleEngine = {}

--- 计算一手牌的最终点数(含特效)
---@param hand table[] 自己的手牌
---@param opponentHand table[] 对手的手牌
---@return number finalPoints
---@return table details
function RuleEngine.CalculatePoints(hand, opponentHand)
    local details = {
        basePoints = 0,
        aceEffects = {},
        eightEffects = 0,
        sevenCount = 0,
        finalPoints = 0,
    }

    -- 1. 收集对手的 Ace 花色 (翻倍我方同花色)
    local aceDoubledSuits = {}
    for _, card in ipairs(opponentHand) do
        if card.rank == 1 then
            aceDoubledSuits[card.suit] = true
            table.insert(details.aceEffects, card.suit)
        end
    end

    -- 2. 统计自己手中 8 的数量 (降低自己普通牌1点)
    local myEightCount = 0
    for _, card in ipairs(hand) do
        if card.rank == 8 then
            myEightCount = myEightCount + 1
        end
    end
    details.eightEffects = myEightCount

    -- 3. 逐张计算点数
    local totalPoints = 0
    for _, card in ipairs(hand) do
        local points = Card.GetBasePoints(card)

        -- Ace 翻倍效果
        if card.suit and aceDoubledSuits[card.suit] then
            points = points * 2
        end

        -- 8 效果: 自己的普通牌(2~6) 每张8降1点
        if Card.IsNormal(card) and myEightCount > 0 then
            points = math.max(0, points - myEightCount)
        end

        totalPoints = totalPoints + points
    end

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
---@return table result {winner, playerPoints, aiPoints, ...}
function RuleEngine.Settle(playerHand, aiHand)
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
        local playerPts, playerDetails = RuleEngine.CalculatePoints(playerHand, aiHand)
        local aiPts, aiDetails = RuleEngine.CalculatePoints(aiHand, playerHand)

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
