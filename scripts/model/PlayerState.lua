-- ============================================================================
-- model/PlayerState.lua - 玩家状态模型
-- ============================================================================

local PlayerState = {}
PlayerState.__index = PlayerState

--- 创建新的玩家状态
---@param isAI boolean
---@return table
function PlayerState.New(isAI)
    local self = setmetatable({}, PlayerState)
    self.isAI = isAI or false
    self.hand = {}              -- 当前手牌
    self.deck = {}              -- 抽牌堆(各自独立)
    self.keepCard = nil         -- 保留到下一局的牌
    self.pendingJackPicks = 0   -- J效果待处理次数
    return self
end

--- 重置手牌(新一局)
function PlayerState:ResetHand()
    self.hand = {}
    self.pendingJackPicks = 0
end

--- 添加牌到手中
---@param card table
function PlayerState:AddToHand(card)
    table.insert(self.hand, card)
end

--- 从手中移除指定索引的牌
---@param index number
---@return table|nil card
function PlayerState:RemoveFromHand(index)
    if index >= 1 and index <= #self.hand then
        return table.remove(self.hand, index)
    end
    return nil
end

--- 获取手牌数量
---@return number
function PlayerState:GetHandSize()
    return #self.hand
end

--- 添加牌到抽牌堆
---@param card table
function PlayerState:AddToDeck(card)
    table.insert(self.deck, card)
end

--- 设置保留牌
---@param card table|nil
function PlayerState:SetKeepCard(card)
    self.keepCard = card
end

--- 取出保留牌(清空)
---@return table|nil
function PlayerState:TakeKeepCard()
    local card = self.keepCard
    self.keepCard = nil
    return card
end

return PlayerState
