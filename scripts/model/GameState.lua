-- ============================================================================
-- model/GameState.lua - 全局游戏状态模型
-- ============================================================================

local GameConfig = require("core.GameConfig")
local PlayerState = require("model.PlayerState")
local RoundState = require("model.RoundState")

local GameState = {}
GameState.__index = GameState

--- 创建新的游戏状态
---@return table
function GameState.New()
    local self = setmetatable({}, GameState)
    self.player = PlayerState.New(false)
    self.ai = PlayerState.New(true)
    self.round = RoundState.New()
    self.playerWins = 0
    self.aiWins = 0
    self.roundNumber = 0
    self.log = {}
    return self
end

--- 增加局数
function GameState:NextRound()
    self.roundNumber = self.roundNumber + 1
end

--- 记录胜局
---@param winner string "player" / "ai"
function GameState:RecordWin(winner)
    if winner == "player" then
        self.playerWins = self.playerWins + 1
    elseif winner == "ai" then
        self.aiWins = self.aiWins + 1
    end
end

--- 判断大局是否结束
---@return boolean
function GameState:IsGameOver()
    return self.playerWins >= GameConfig.WINS_NEEDED
        or self.aiWins >= GameConfig.WINS_NEEDED
end

--- 获取游戏胜者
---@return string|nil "player" / "ai" / nil
function GameState:GetGameWinner()
    if self.playerWins >= GameConfig.WINS_NEEDED then return "player" end
    if self.aiWins >= GameConfig.WINS_NEEDED then return "ai" end
    return nil
end

--- 添加日志
---@param msg string
function GameState:AddLog(msg)
    table.insert(self.log, msg)
    print("[Game] " .. msg)
end

return GameState
