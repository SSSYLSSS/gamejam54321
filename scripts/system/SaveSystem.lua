-- ============================================================================
-- system/SaveSystem.lua - 游戏存档系统
-- 保存/恢复进行中的游戏状态
-- ============================================================================

local GameConfig = require("core.GameConfig")
local Constant = require("core.Constant")

local SaveSystem = {}

local SAVE_FILE = "gamesave.json"

--- 序列化玩家状态
---@param playerState table
---@return table
local function serializePlayerState(playerState)
    return {
        isAI = playerState.isAI,
        hand = playerState.hand,
        deck = playerState.deck,
        discardPile = playerState.discardPile,
        keepCard = playerState.keepCard,
        pendingJackPicks = playerState.pendingJackPicks,
        discardedTenCount = playerState.discardedTenCount,
        discardedJackCount = playerState.discardedJackCount,
    }
end

--- 序列化回合状态
---@param roundState table
---@return table
local function serializeRoundState(roundState)
    return {
        phase = roundState.phase,
        subPhase = roundState.subPhase,
        turnIndex = roundState.turnIndex,
        discardPile = roundState.discardPile,
        lastResult = roundState.lastResult,
        postPhase = roundState.postPhase,
        jokerPhase = roundState.jokerPhase,
    }
end

--- 保存游戏状态
---@param gameState table GameState 实例
---@param difficulty string 当前难度
---@return boolean success
function SaveSystem.Save(gameState, difficulty)
    if not gameState then return false end

    local saveData = {
        version = 1,
        difficulty = difficulty or "normal",
        playerWins = gameState.playerWins,
        aiWins = gameState.aiWins,
        roundNumber = gameState.roundNumber,
        player = serializePlayerState(gameState.player),
        ai = serializePlayerState(gameState.ai),
        round = serializeRoundState(gameState.round),
    }

    local ok, json = pcall(cjson.encode, saveData)
    if not ok then
        print("[SaveSystem] Encode error: " .. tostring(json))
        return false
    end

    local file = File(SAVE_FILE, FILE_WRITE)
    if not file:IsOpen() then
        print("[SaveSystem] Cannot open save file for writing")
        return false
    end
    file:WriteString(json)
    file:Close()
    return true
end

--- 检查是否存在存档
---@return boolean
function SaveSystem.HasSave()
    return fileSystem:FileExists(SAVE_FILE)
end

--- 加载存档数据(原始 table)
---@return table|nil saveData
function SaveSystem.Load()
    if not fileSystem:FileExists(SAVE_FILE) then
        return nil
    end

    local file = File(SAVE_FILE, FILE_READ)
    if not file:IsOpen() then return nil end
    local content = file:ReadString()
    file:Close()

    if not content or content == "" then return nil end

    local ok, data = pcall(cjson.decode, content)
    if not ok or type(data) ~= "table" then
        print("[SaveSystem] Decode error")
        return nil
    end

    return data
end

--- 恢复 GameState 从存档数据
---@param saveData table
---@param GameState table GameState 模块(用于 New)
---@param PlayerState table PlayerState 模块(用于恢复)
---@param RoundState table RoundState 模块(用于恢复)
---@return table|nil gameState 恢复的 GameState 实例
function SaveSystem.RestoreGameState(saveData, GameState, PlayerState, RoundState)
    if not saveData then return nil end

    local gs = GameState.New()
    gs.playerWins = saveData.playerWins or 0
    gs.aiWins = saveData.aiWins or 0
    gs.roundNumber = saveData.roundNumber or 1

    -- 恢复玩家状态
    if saveData.player then
        gs.player.hand = saveData.player.hand or {}
        gs.player.deck = saveData.player.deck or {}
        gs.player.discardPile = saveData.player.discardPile or {}
        gs.player.keepCard = saveData.player.keepCard
        gs.player.pendingJackPicks = saveData.player.pendingJackPicks or 0
        gs.player.discardedTenCount = saveData.player.discardedTenCount or 0
        gs.player.discardedJackCount = saveData.player.discardedJackCount or 0
    end

    -- 恢复AI状态
    if saveData.ai then
        gs.ai.hand = saveData.ai.hand or {}
        gs.ai.deck = saveData.ai.deck or {}
        gs.ai.discardPile = saveData.ai.discardPile or {}
        gs.ai.keepCard = saveData.ai.keepCard
        gs.ai.pendingJackPicks = saveData.ai.pendingJackPicks or 0
        gs.ai.discardedTenCount = saveData.ai.discardedTenCount or 0
        gs.ai.discardedJackCount = saveData.ai.discardedJackCount or 0
    end

    -- 恢复回合状态
    if saveData.round then
        gs.round.phase = saveData.round.phase or Constant.PHASE.INIT
        gs.round.subPhase = saveData.round.subPhase or Constant.SUB_PHASE.PLAYER_TURN
        gs.round.turnIndex = saveData.round.turnIndex or 1
        gs.round.discardPile = saveData.round.discardPile or {}
        gs.round.lastResult = saveData.round.lastResult
        gs.round.postPhase = saveData.round.postPhase or "discard"
        gs.round.jokerPhase = saveData.round.jokerPhase or "pending"
    end

    return gs
end

--- 删除存档
function SaveSystem.Delete()
    if fileSystem:FileExists(SAVE_FILE) then
        fileSystem:Delete(SAVE_FILE)
    end
end

return SaveSystem
