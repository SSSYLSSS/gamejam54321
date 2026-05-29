-- ============================================================================
-- model/RoundState.lua - 单局状态模型
-- ============================================================================

local Constant = require("core.Constant")
local GameConfig = require("core.GameConfig")

local RoundState = {}
RoundState.__index = RoundState

--- 创建新的单局状态
---@return table
function RoundState.New()
    local self = setmetatable({}, RoundState)
    self.phase = Constant.PHASE.INIT
    self.subPhase = Constant.SUB_PHASE.PLAYER_TURN
    self.turnIndex = 0              -- 当前回合 (1,2,3)
    self.discardPile = {}           -- 共享弃牌堆
    self.lastResult = nil           -- 结算结果
    self.postPhase = "discard"      -- 结算后子阶段: discard / keep
    self.jokerPhase = "pending"     -- 鬼牌阶段: pending / done
    return self
end

--- 获取当前回合最大弃牌数
---@return number
function RoundState:GetMaxDiscard()
    if self.turnIndex >= 1 and self.turnIndex <= #GameConfig.MAX_DISCARD then
        return GameConfig.MAX_DISCARD[self.turnIndex]
    end
    return 0
end

--- 进入下一回合
---@return boolean 是否进入了新回合(false表示三回合已结束)
function RoundState:AdvanceTurn()
    self.turnIndex = self.turnIndex + 1
    if self.turnIndex > 3 then
        self.phase = Constant.PHASE.JOKER_EFFECT
        return false
    end
    self.phase = Constant.ROUND_PHASES[self.turnIndex]
    return true
end

--- 添加牌到弃牌堆
---@param card table
function RoundState:AddToDiscardPile(card)
    table.insert(self.discardPile, card)
end

--- 从弃牌堆随机取一张
---@return table|nil
function RoundState:DrawRandomFromDiscard()
    if #self.discardPile == 0 then return nil end
    local idx = math.random(1, #self.discardPile)
    return table.remove(self.discardPile, idx)
end

--- 获取弃牌堆数量
---@return number
function RoundState:GetDiscardCount()
    return #self.discardPile
end

--- 清空弃牌堆(洗入牌堆时)
---@return table[] 返回所有弃牌
function RoundState:TakeAllDiscards()
    local cards = self.discardPile
    self.discardPile = {}
    return cards
end

return RoundState
