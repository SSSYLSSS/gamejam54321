-- ============================================================================
-- service/GameController.lua - 游戏控制器(UI-逻辑桥梁)
-- 为UI层提供统一接口，隐藏底层状态和系统细节
-- ============================================================================

local Constant = require("core.Constant")
local GameConfig = require("core.GameConfig")
local Card = require("core.Card")
local GameState = require("model.GameState")
local PhaseManager = require("system.PhaseManager")
local EffectSystem = require("system.EffectSystem")

local GameController = {}

---@type table|nil
local state = nil  -- GameState 实例

-- ============================================================================
-- 生命周期
-- ============================================================================

--- 创建新游戏
function GameController.NewGame()
    math.randomseed(os.time())
    state = GameState.New()
    PhaseManager.StartNewRound(state)
end

--- 从存档恢复游戏(直接设置 state)
---@param restoredState table 已恢复的 GameState 实例
function GameController.RestoreGame(restoredState)
    state = restoredState
end

--- 获取当前 GameState (只读查询用)
---@return table|nil
function GameController.GetState()
    return state
end

-- ============================================================================
-- 查询接口
-- ============================================================================

--- 获取当前阶段
---@return string phase
function GameController.GetPhase()
    if not state then return Constant.PHASE.INIT end
    return state.round.phase
end

--- 获取子阶段
---@return string
function GameController.GetSubPhase()
    if not state then return Constant.SUB_PHASE.WAITING end
    return state.round.subPhase
end

--- 获取当前回合最大弃牌数
---@return number
function GameController.GetMaxDiscard()
    if not state then return 0 end
    return state.round:GetMaxDiscard()
end

--- 获取玩家手牌
---@return table[]
function GameController.GetPlayerHand()
    if not state then return {} end
    return state.player.hand
end

--- 获取AI手牌
---@return table[]
function GameController.GetAIHand()
    if not state then return {} end
    return state.ai.hand
end

--- 获取玩家当前手牌总点数
---@return number
function GameController.GetPlayerPoints()
    if not state then return 0 end
    local pts = 0
    for _, card in ipairs(state.player.hand) do
        pts = pts + Card.GetBasePoints(card)
    end
    return pts
end

--- 获取比分
---@return number playerWins
---@return number aiWins
function GameController.GetScore()
    if not state then return 0, 0 end
    return state.playerWins, state.aiWins
end

--- 获取当前局数
---@return number
function GameController.GetRoundNumber()
    if not state then return 0 end
    return state.roundNumber
end

--- 获取当前回合索引
---@return number
function GameController.GetTurnIndex()
    if not state then return 0 end
    return state.round.turnIndex
end

--- 获取玩家弃牌堆
---@return table[]
function GameController.GetPlayerDiscardPile()
    if not state then return {} end
    return state.player.discardPile
end

--- 获取AI弃牌堆
---@return table[]
function GameController.GetAIDiscardPile()
    if not state then return {} end
    return state.ai.discardPile
end

--- 获取玩家抽牌堆
---@return table[]
function GameController.GetPlayerDeck()
    if not state then return {} end
    return state.player.deck
end

--- 获取AI抽牌堆数量
---@return number
function GameController.GetAIDeckCount()
    if not state then return 0 end
    return #state.ai.deck
end

--- 获取 pendingJackPicks 数量
---@return number
function GameController.GetPendingJackPicks()
    if not state then return 0 end
    return state.player.pendingJackPicks
end

--- 获取结算结果
---@return table|nil
function GameController.GetLastResult()
    if not state then return nil end
    return state.round.lastResult
end

--- 游戏是否结束
---@return boolean
function GameController.IsGameOver()
    if not state then return false end
    return state:IsGameOver()
end

--- 获取游戏胜者
---@return string|nil
function GameController.GetGameWinner()
    if not state then return nil end
    return state:GetGameWinner()
end

--- 获取玩家保留牌(用于ROUND_END阶段展示)
---@return table|nil card
function GameController.GetPlayerKeepCard()
    if not state then return nil end
    return state.player.keepCard
end

--- 玩家手中是否有鬼牌
---@return boolean
function GameController.PlayerHasJoker()
    if not state then return false end
    return EffectSystem.HasJoker(state.player.hand)
end

--- 获取各牌堆数量
---@return number playerDeckCount
---@return number playerDiscardCount
---@return number aiDeckCount
---@return number aiDiscardCount
function GameController.GetPileCounts()
    if not state then return 0, 0, 0, 0 end
    return #state.player.deck, state.player:GetDiscardCount(),
           #state.ai.deck, state.ai:GetDiscardCount()
end

-- ============================================================================
-- 操作接口
-- ============================================================================

--- 玩家弃牌
---@param indices number[]
---@return boolean success
---@return string|nil errMsg
function GameController.PlayerDiscard(indices)
    if not state then return false, "游戏未初始化" end
    return PhaseManager.PlayerDiscard(state, indices)
end

--- 玩家J效果: 从弃牌堆或抽牌堆抽牌
---@param source string "discard" 或 "deck"
---@return boolean success
---@return string|nil errMsg
---@return table|nil card
function GameController.PlayerJackPick(source)
    if not state then return false, "游戏未初始化", nil end
    local success, err, card = EffectSystem.PlayerJackPick(state.player, state.round, source)
    if success and state.player.pendingJackPicks <= 0 then
        -- J效果全部处理完，恢复正常子阶段
        state.round.subPhase = Constant.SUB_PHASE.PLAYER_TURN
    end
    return success, err, card
end

--- 玩家弃牌后完成回合(触发AI行动 + 推进回合)
function GameController.FinishPlayerTurn()
    if not state then return end
    PhaseManager.FinishPlayerTurn(state)
end

--- 跳过弃牌(不弃牌直接结束回合)
function GameController.SkipDiscard()
    if not state then return end
    state:AddLog("玩家选择不弃牌")
    PhaseManager.FinishPlayerTurn(state)
end

--- 处理鬼牌效果并结算
---@return table|nil result
function GameController.DoJokerAndSettle()
    if not state then return nil end
    return PhaseManager.DoJokerAndSettle(state)
end

--- 玩家有小王?
---@return boolean
function GameController.PlayerHasSmallJoker()
    if not state then return false end
    for _, card in ipairs(state.player.hand) do
        if card.rank == 14 then return true end
    end
    return false
end

--- 玩家有大王?
---@return boolean
function GameController.PlayerHasBigJoker()
    if not state then return false end
    for _, card in ipairs(state.player.hand) do
        if card.rank == 15 then return true end
    end
    return false
end

--- 玩家小王效果: 移除AI指定索引的牌
---@param targetIdx number
---@return table|nil removedCard
function GameController.PlayerSmallJokerEffect(targetIdx)
    if not state then return nil end
    return EffectSystem.PlayerSmallJokerEffect(state, targetIdx)
end

--- 玩家大王: 设置目标牌点数
---@param targetIdx number 要修改的手牌索引
---@param value number 0-13
function GameController.PlayerSetBigJokerValue(targetIdx, value)
    if not state then return end
    EffectSystem.PlayerSetBigJokerValue(state, targetIdx, value)
end

--- 玩家大王: 设置大王自身点数
---@param value number 0-13
function GameController.PlayerSetBigJokerSelfValue(value)
    if not state then return end
    EffectSystem.PlayerSetBigJokerSelfValue(state, value)
end

--- 设置玩家小王点数(自动最优)
function GameController.PlayerSetSmallJokerValue()
    if not state then return end
    EffectSystem.PlayerSetSmallJokerValue(state)
end

--- 获取AI小王移除的玩家牌信息(供翻牌动画延迟展示)
---@return table|nil removedCard
function GameController.GetAISmallJokerRemoved()
    if not state or not state.round then return nil end
    return state.round.aiSmallJokerRemoved
end

--- 进入结算后阶段
function GameController.EnterPostGame()
    if not state then return end
    state.round.phase = Constant.PHASE.POST_DISCARD
    state.round.subPhase = Constant.SUB_PHASE.PLAYER_TURN
end

--- 比分已达胜利条件时直接跳到游戏结束(跳过二!/一!)
function GameController.SkipToGameOver()
    if not state then return end
    state.round.phase = Constant.PHASE.GAME_OVER
end

--- 玩家结算后弃牌 (二!)
---@param indices number[]
function GameController.PlayerPostDiscard(indices)
    if not state then return end
    PhaseManager.PlayerPostDiscard(state, indices)
    state.round.phase = Constant.PHASE.POST_KEEP
end

--- 跳过结算后弃牌
function GameController.SkipPostDiscard()
    if not state then return end
    -- 仍然需要强制弃鬼牌
    PhaseManager.PlayerPostDiscard(state, {})
    state.round.phase = Constant.PHASE.POST_KEEP
end

--- 玩家结算后保留 (一!)
---@param keepIndex number|nil
function GameController.PlayerPostKeep(keepIndex)
    if not state then return end
    PhaseManager.PlayerPostKeep(state, keepIndex)
    PhaseManager.AIPostGame(state)
    PhaseManager.FinishRound(state)
end

--- 跳过保留
function GameController.SkipPostKeep()
    if not state then return end
    PhaseManager.PlayerPostKeep(state, nil)
    PhaseManager.AIPostGame(state)
    PhaseManager.FinishRound(state)
end

--- 开始下一局
function GameController.StartNextRound()
    if not state then return end
    PhaseManager.StartNewRound(state)
end

--- 获取游戏日志
---@return table log
function GameController.GetLog()
    if not state then return {} end
    return state.log
end

return GameController
