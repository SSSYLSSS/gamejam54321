-- ============================================================================
-- system/PhaseManager.lua - 游戏阶段管理器(状态机)
-- 驱动完整的游戏流程
-- ============================================================================

local Constant = require("core.Constant")
local GameConfig = require("core.GameConfig")
local Card = require("core.Card")
local DeckSystem = require("system.DeckSystem")
local RuleEngine = require("system.RuleEngine")
local EffectSystem = require("system.EffectSystem")
local AISystem = require("system.AISystem")
local RoundState = require("model.RoundState")

local PhaseManager = {}

-- ============================================================================
-- 开局 / 新一局
-- ============================================================================

--- 开始新一局
---@param gameState table GameState
function PhaseManager.StartNewRound(gameState)
    gameState:NextRound()
    gameState.round = RoundState.New()

    -- 第一局时创建牌组
    if gameState.roundNumber == 1 then
        gameState.player.deck = DeckSystem.CreateFullDeck()
        gameState.ai.deck = DeckSystem.CreateFullDeck()
        DeckSystem.Shuffle(gameState.player.deck)
        DeckSystem.Shuffle(gameState.ai.deck)
    end

    -- 重置手牌
    gameState.player:ResetHand()
    gameState.ai:ResetHand()

    -- 保留牌放入手牌
    local keepCard = gameState.player:TakeKeepCard()
    if keepCard then
        gameState.player:AddToHand(keepCard)
    end
    local aiKeep = gameState.ai:TakeKeepCard()
    if aiKeep then
        gameState.ai:AddToHand(aiKeep)
    end

    -- 补满5张手牌
    DeckSystem.DealToHand(gameState.player, gameState.round, GameConfig.HAND_SIZE)
    DeckSystem.DealToHand(gameState.ai, gameState.round, GameConfig.HAND_SIZE)

    gameState:AddLog(string.format("=== 第 %d 局开始 ===", gameState.roundNumber))
    gameState:AddLog(string.format("比分: 玩家 %d - AI %d", gameState.playerWins, gameState.aiWins))

    -- 进入第一回合
    PhaseManager.NextTurn(gameState)
end

--- 进入下一个回合
---@param gameState table GameState
function PhaseManager.NextTurn(gameState)
    local advanced = gameState.round:AdvanceTurn()
    if advanced then
        local maxDiscard = gameState.round:GetMaxDiscard()
        gameState:AddLog(string.format("第 %d 回合: 可弃置至多 %d 张牌",
            gameState.round.turnIndex, maxDiscard))
    else
        gameState:AddLog("三回合结束，进入结算前效果阶段")
    end
    gameState.round.subPhase = Constant.SUB_PHASE.PLAYER_TURN
end

-- ============================================================================
-- 弃牌阶段
-- ============================================================================

--- 玩家执行弃牌
---@param gameState table GameState
---@param discardIndices number[] 要弃置的手牌索引
---@return boolean success
---@return string|nil errMsg
function PhaseManager.PlayerDiscard(gameState, discardIndices)
    local round = gameState.round
    local player = gameState.player
    local maxDiscard = round:GetMaxDiscard()

    if #discardIndices > maxDiscard then
        return false, string.format("最多弃置 %d 张牌", maxDiscard)
    end

    -- 按索引从大到小排序
    table.sort(discardIndices, function(a, b) return a > b end)

    local discarded = {}
    local jackCount = 0
    for _, idx in ipairs(discardIndices) do
        local card = player:RemoveFromHand(idx)
        if card then
            table.insert(discarded, card)
            if card.rank == 11 then
                jackCount = jackCount + 1
            end
            -- 追踪弃置的10和J
            if card.rank == 10 then
                player.discardedTenCount = player.discardedTenCount + 1
            end
        end
    end

    -- 弃牌放入弃牌堆
    for _, card in ipairs(discarded) do
        round:AddToDiscardPile(card)
    end

    -- 记录J待处理 + 追踪J弃牌数
    player.pendingJackPicks = jackCount
    player.discardedJackCount = player.discardedJackCount + jackCount

    -- 非J弃牌正常补牌
    local normalDrawCount = #discarded - jackCount
    for _ = 1, normalDrawCount do
        local card = DeckSystem.Draw(player.deck, round)
        if card then
            player:AddToHand(card)
        end
    end

    gameState:AddLog(string.format("弃置 %d 张, 正常补牌 %d 张", #discarded, normalDrawCount))
    if jackCount > 0 then
        gameState:AddLog(string.format("J 弃置效果: 需从弃牌堆随机抽牌 %d 次", jackCount))
        round.subPhase = Constant.SUB_PHASE.JACK_PICK
    end

    return true, nil
end

--- AI 执行弃牌回合
---@param gameState table GameState
function PhaseManager.AITurn(gameState)
    local round = gameState.round
    local ai = gameState.ai

    local aiIndices = AISystem.DecideDiscard(ai.hand, round.turnIndex)

    -- 限制数量
    local validIndices = {}
    for _, idx in ipairs(aiIndices) do
        local card = ai.hand[idx]
        if card then
            table.insert(validIndices, idx)
        end
    end
    local maxDiscard = round:GetMaxDiscard()
    while #validIndices > maxDiscard do
        table.remove(validIndices)
    end

    table.sort(validIndices, function(a, b) return a > b end)

    local discarded = {}
    local jackCount = 0
    for _, idx in ipairs(validIndices) do
        local card = ai:RemoveFromHand(idx)
        if card then
            table.insert(discarded, card)
            if card.rank == 11 then
                jackCount = jackCount + 1
            end
            -- 追踪弃置的10和J
            if card.rank == 10 then
                ai.discardedTenCount = ai.discardedTenCount + 1
            end
        end
    end

    -- 弃牌放入弃牌堆
    for _, card in ipairs(discarded) do
        round:AddToDiscardPile(card)
    end

    -- J 效果 + 追踪J弃牌数
    ai.pendingJackPicks = jackCount
    ai.discardedJackCount = ai.discardedJackCount + jackCount
    EffectSystem.AIJackPick(ai, round)

    -- 非J正常补牌
    local normalDrawCount = #discarded - jackCount
    for _ = 1, normalDrawCount do
        local card = DeckSystem.Draw(ai.deck, round)
        if card then
            ai:AddToHand(card)
        end
    end

    gameState:AddLog(string.format("AI 弃置 %d 张, 补牌 %d 张", #discarded, normalDrawCount))
end

--- 玩家弃牌后完成回合(AI行动 + 推进)
---@param gameState table GameState
function PhaseManager.FinishPlayerTurn(gameState)
    PhaseManager.AITurn(gameState)
    PhaseManager.NextTurn(gameState)
end

-- ============================================================================
-- 鬼牌效果阶段
-- ============================================================================

--- 处理鬼牌效果 + 执行结算
---@param gameState table GameState
---@return table result 结算结果
function PhaseManager.DoJokerAndSettle(gameState)
    EffectSystem.ProcessJokerPhase(gameState)
    return PhaseManager.DoSettlement(gameState)
end

-- ============================================================================
-- 结算阶段
-- ============================================================================

--- 执行结算
---@param gameState table GameState
---@return table result
function PhaseManager.DoSettlement(gameState)
    local result = RuleEngine.Settle(gameState.player.hand, gameState.ai.hand, gameState.player, gameState.ai)

    -- 更新胜场
    if result.winner == "player" then
        gameState:RecordWin("player")
        gameState:AddLog(">>> 玩家赢得本局! <<<")
    elseif result.winner == "ai" then
        gameState:RecordWin("ai")
        gameState:AddLog(">>> AI赢得本局! <<<")
    else
        gameState:AddLog(">>> 平局! <<<")
    end

    if result.sevenRuleTriggered then
        gameState:AddLog("三7特殊规则触发!")
    else
        gameState:AddLog(string.format("结算: 玩家 %d点 vs AI %d点",
            result.playerPoints, result.aiPoints))
    end

    gameState.round.lastResult = result
    gameState.round.phase = Constant.PHASE.SETTLEMENT
    return result
end

-- ============================================================================
-- 结算后阶段 (二! 一!)
-- ============================================================================

--- 玩家结算后弃牌 (二!)
---@param gameState table GameState
---@param discardIndices number[]
function PhaseManager.PlayerPostDiscard(gameState, discardIndices)
    local player = gameState.player
    local round = gameState.round

    -- 强制弃置鬼牌
    local i = 1
    while i <= #player.hand do
        if Card.IsJoker(player.hand[i]) then
            local card = table.remove(player.hand, i)
            round:AddToDiscardPile(card)
            gameState:AddLog("强制弃置鬼牌: " .. Card.GetName(card))
        else
            i = i + 1
        end
    end

    -- 弃置选中的牌到抽牌堆
    local count = math.min(#discardIndices, GameConfig.POST_DISCARD_MAX)
    table.sort(discardIndices, function(a, b) return a > b end)
    for j = 1, count do
        local idx = discardIndices[j]
        if idx >= 1 and idx <= #player.hand then
            local card = table.remove(player.hand, idx)
            player:AddToDeck(card)
            gameState:AddLog("弃置至牌堆: " .. Card.GetName(card))
        end
    end
end

--- 玩家结算后保留 (一!)
---@param gameState table GameState
---@param keepIndex number|nil
function PhaseManager.PlayerPostKeep(gameState, keepIndex)
    local player = gameState.player
    local round = gameState.round

    if keepIndex and keepIndex >= 1 and keepIndex <= #player.hand then
        local card = table.remove(player.hand, keepIndex)
        player:SetKeepCard(card)
        gameState:AddLog("保留至下局: " .. Card.GetName(card))
    end

    -- 剩余手牌放入弃牌堆
    for _, card in ipairs(player.hand) do
        round:AddToDiscardPile(card)
    end
    player.hand = {}
end

--- AI 结算后选择
---@param gameState table GameState
function PhaseManager.AIPostGame(gameState)
    local ai = gameState.ai
    local round = gameState.round

    -- 强制弃置鬼牌
    local i = 1
    while i <= #ai.hand do
        if Card.IsJoker(ai.hand[i]) then
            local card = table.remove(ai.hand, i)
            round:AddToDiscardPile(card)
        else
            i = i + 1
        end
    end

    -- AI 决策
    local discardIndices, keepIndex = AISystem.DecidePostGame(ai.hand)

    -- 保留一张
    if keepIndex and keepIndex >= 1 and keepIndex <= #ai.hand then
        local card = table.remove(ai.hand, keepIndex)
        ai:SetKeepCard(card)
    end

    -- 弃置到抽牌堆(注意保留牌已移除，重新计算索引)
    table.sort(discardIndices, function(a, b) return a > b end)
    local discardCount = math.min(GameConfig.POST_DISCARD_MAX, #ai.hand)
    local removed = 0
    for _, idx in ipairs(discardIndices) do
        if removed >= discardCount then break end
        if idx >= 1 and idx <= #ai.hand then
            local card = table.remove(ai.hand, idx)
            ai:AddToDeck(card)
            removed = removed + 1
        end
    end

    -- 剩余放入弃牌堆
    for _, card in ipairs(ai.hand) do
        round:AddToDiscardPile(card)
    end
    ai.hand = {}
end

--- 完成本局后续处理，判断游戏是否结束
---@param gameState table GameState
function PhaseManager.FinishRound(gameState)
    if gameState:IsGameOver() then
        gameState.round.phase = Constant.PHASE.GAME_OVER
    else
        gameState.round.phase = Constant.PHASE.ROUND_END
    end
end

return PhaseManager
