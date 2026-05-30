-- ============================================================================
-- system/EffectSystem.lua - 卡牌效果系统
-- 管理所有卡牌效果的触发与执行
-- ============================================================================

local Card = require("core.Card")
local Constant = require("core.Constant")
local GameConfig = require("core.GameConfig")

local EffectSystem = {}

-- ============================================================================
-- 鬼牌效果: 结算前阶段处理
-- 小王: 仅选择点数(0-13), 无抽牌效果
-- 大王: 选择自身点数(0-13) + 修改一张牌点数
-- ============================================================================

--- 自动设置鬼牌最优点数(让总和尽量接近21)
---@param hand table[]
function EffectSystem.AutoSetJokerValues(hand)
    local nonJokerPts = 0
    local jokerCount = 0
    for _, card in ipairs(hand) do
        if Card.IsJoker(card) then
            jokerCount = jokerCount + 1
        else
            nonJokerPts = nonJokerPts + Card.GetBasePoints(card)
        end
    end

    if jokerCount == 0 then return end

    local remaining = math.max(0, GameConfig.TARGET_POINTS - nonJokerPts)
    local perJoker = math.floor(remaining / jokerCount)
    perJoker = math.max(GameConfig.JOKER_MIN_VALUE, math.min(GameConfig.JOKER_MAX_VALUE, perJoker))
    local extra = remaining - perJoker * jokerCount

    local first = true
    for _, card in ipairs(hand) do
        if Card.IsJoker(card) then
            if first and extra > 0 then
                card.jokerValue = math.min(GameConfig.JOKER_MAX_VALUE, perJoker + extra)
                first = false
            else
                card.jokerValue = perJoker
                first = false
            end
        end
    end
end

--- 处理AI的鬼牌效果（AI自动决策部分）
--- 玩家的鬼牌效果由 UI 层驱动，不在这里处理
---@param gameState table GameState
function EffectSystem.ProcessJokerPhase(gameState)
    local aiHand = gameState.ai.hand

    -- AI大王: 自动设置最优点数 (包含大王自身和小王)
    EffectSystem.AutoSetJokerValues(aiHand)

    -- AI大王: 如果有大王, 自动选择覆盖一张牌让点数最接近21
    for _, card in ipairs(aiHand) do
        if card.rank == 15 then
            -- 找到最优的覆盖目标
            local bestIdx = nil
            local bestValue = 0
            local bestDist = math.huge

            -- 计算当前总点数(不含被覆盖的牌)
            for i, target in ipairs(aiHand) do
                if i ~= _ and not Card.IsJoker(target) then
                    -- 尝试将此牌改为不同值
                    local otherPts = 0
                    for j, c in ipairs(aiHand) do
                        if j ~= i then
                            if c.jokerValue then
                                otherPts = otherPts + c.jokerValue
                            else
                                otherPts = otherPts + Card.GetBasePoints(c)
                            end
                        end
                    end
                    -- 最优值 = 21 - otherPts
                    local idealValue = GameConfig.TARGET_POINTS - otherPts
                    idealValue = math.max(GameConfig.JOKER_MIN_VALUE, math.min(GameConfig.JOKER_MAX_VALUE, idealValue))
                    local dist = math.abs(otherPts + idealValue - GameConfig.TARGET_POINTS)
                    if dist < bestDist then
                        bestDist = dist
                        bestIdx = i
                        bestValue = idealValue
                    end
                end
            end

            if bestIdx then
                aiHand[bestIdx].jokerOverride = bestValue
                gameState:AddLog(string.format("AI大王效果: 将 %s 点数设为 %d",
                    Card.GetName(aiHand[bestIdx]), bestValue))
            end
            break
        end
    end
end

--- 设置玩家大王效果: 将指定手牌的点数覆盖为任意值
---@param gameState table GameState
---@param targetIdx number 要修改的手牌索引
---@param value number 玩家选择的点数(0-13)
function EffectSystem.PlayerSetBigJokerValue(gameState, targetIdx, value)
    value = math.max(GameConfig.JOKER_MIN_VALUE, math.min(GameConfig.JOKER_MAX_VALUE, value))
    local hand = gameState.player.hand
    if targetIdx and targetIdx >= 1 and targetIdx <= #hand then
        local card = hand[targetIdx]
        card.jokerOverride = value
        gameState:AddLog(string.format("大王效果: 将 %s 的点数设为 %d", Card.GetName(card), value))
    end
end

--- 设置玩家大王自身的点数
---@param gameState table GameState
---@param value number 玩家选择的点数(0-13)
function EffectSystem.PlayerSetBigJokerSelfValue(gameState, value)
    value = math.max(GameConfig.JOKER_MIN_VALUE, math.min(GameConfig.JOKER_MAX_VALUE, value))
    local hand = gameState.player.hand
    for _, card in ipairs(hand) do
        if card.rank == 15 then
            card.jokerValue = value
            gameState:AddLog(string.format("大王自身点数: %d", value))
            return
        end
    end
end

--- 设置玩家小王的点数
---@param gameState table GameState
---@param value number 玩家选择的点数(0-13)
function EffectSystem.PlayerSetSmallJokerValue(gameState, value)
    value = math.max(GameConfig.JOKER_MIN_VALUE, math.min(GameConfig.JOKER_MAX_VALUE, value))
    local hand = gameState.player.hand
    for _, card in ipairs(hand) do
        if card.rank == 14 then
            card.jokerValue = value
            gameState:AddLog(string.format("小王点数: %d", value))
            return
        end
    end
end

--- 检查手牌中是否有鬼牌
---@param hand table[]
---@return boolean hasBigJoker, boolean hasSmallJoker
function EffectSystem.HasJoker(hand)
    local hasBig = false
    local hasSmall = false
    for _, card in ipairs(hand) do
        if card.rank == 15 then hasBig = true end
        if card.rank == 14 then hasSmall = true end
    end
    return hasBig, hasSmall
end

return EffectSystem
