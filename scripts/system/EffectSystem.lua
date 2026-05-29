-- ============================================================================
-- system/EffectSystem.lua - 卡牌效果系统
-- 管理所有卡牌效果的触发与执行
-- ============================================================================

local Card = require("core.Card")
local Constant = require("core.Constant")
local GameConfig = require("core.GameConfig")
local DeckSystem = require("system.DeckSystem")

local EffectSystem = {}

-- ============================================================================
-- J 效果: 弃置时从选定牌堆随机抽牌
-- ============================================================================

--- 执行玩家 J 效果: 从指定牌堆随机抽一张
---@param playerState table PlayerState
---@param roundState table RoundState
---@param source string "discard" / "deck"
---@return boolean success
---@return string|nil errMsg
---@return table|nil drawnCard
function EffectSystem.PlayerJackPick(playerState, roundState, source)
    if playerState.pendingJackPicks <= 0 then
        return false, "没有待处理的J效果", nil
    end

    local card
    if source == "discard" then
        card = roundState:DrawRandomFromDiscard()
    elseif source == "deck" then
        card = DeckSystem.DrawRandom(playerState.deck)
    else
        return false, "无效来源", nil
    end

    if not card then
        return false, "该牌堆为空", nil
    end

    playerState:AddToHand(card)
    playerState.pendingJackPicks = playerState.pendingJackPicks - 1
    return true, nil, card
end

--- AI 的 J 效果处理(弃置时自动随机选牌堆抽牌)
---@param aiState table PlayerState
---@param roundState table RoundState
function EffectSystem.AIJackPick(aiState, roundState)
    while aiState.pendingJackPicks > 0 do
        -- AI 策略: 优先从弃牌堆抽(信息更确定)
        local card
        if roundState:GetDiscardCount() > 0 then
            card = roundState:DrawRandomFromDiscard()
        elseif #aiState.deck > 0 then
            card = DeckSystem.DrawRandom(aiState.deck)
        end
        if card then
            aiState:AddToHand(card)
        end
        aiState.pendingJackPicks = aiState.pendingJackPicks - 1
    end
end

-- ============================================================================
-- 鬼牌效果: 结算前阶段处理
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

--- 小王效果: 移除对方一张点数最高的牌
---@param ownerHand table[] 拥有小王的手牌
---@param targetHand table[] 对方手牌
---@param roundState table RoundState
---@return table|nil removedCard
function EffectSystem.SmallJokerEffect(ownerHand, targetHand, roundState)
    -- 检查 ownerHand 是否含有小王
    local hasSmallJoker = false
    for _, card in ipairs(ownerHand) do
        if card.rank == 14 then
            hasSmallJoker = true
            break
        end
    end
    if not hasSmallJoker then return nil end

    -- 找对方点数最高且非7的牌
    local bestIdx, bestPts = nil, -1
    for i, card in ipairs(targetHand) do
        local pts = Card.GetBasePoints(card)
        if pts > bestPts and card.rank ~= 7 then
            bestPts = pts
            bestIdx = i
        end
    end

    if bestIdx then
        local removed = table.remove(targetHand, bestIdx)
        roundState:AddToDiscardPile(removed)
        return removed
    end
    return nil
end

--- 处理所有鬼牌效果（结算前阶段）
---@param gameState table GameState
function EffectSystem.ProcessJokerPhase(gameState)
    local playerHand = gameState.player.hand
    local aiHand = gameState.ai.hand
    local round = gameState.round

    -- 设置鬼牌点数
    EffectSystem.AutoSetJokerValues(playerHand)
    EffectSystem.AutoSetJokerValues(aiHand)

    -- 玩家小王效果
    local removedByPlayer = EffectSystem.SmallJokerEffect(playerHand, aiHand, round)
    if removedByPlayer then
        gameState:AddLog("小王效果: 移除AI的 " .. Card.GetName(removedByPlayer))
    end

    -- AI小王效果
    local removedByAI = EffectSystem.SmallJokerEffect(aiHand, playerHand, round)
    if removedByAI then
        gameState:AddLog("AI小王效果: 移除玩家的 " .. Card.GetName(removedByAI))
    end
end

--- 检查手牌中是否有鬼牌
---@param hand table[]
---@return boolean
function EffectSystem.HasJoker(hand)
    for _, card in ipairs(hand) do
        if Card.IsJoker(card) then
            return true
        end
    end
    return false
end

return EffectSystem
