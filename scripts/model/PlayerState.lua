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
    self.discardPile = {}       -- 弃牌堆(各自独立)
    self.keepCard = nil         -- 保留到下一局的牌

    return self
end

--- 重置手牌(新一局)
function PlayerState:ResetHand()
    -- 清除所有牌上的大王改值效果(仅单局生效)
    self:ClearJokerOverrides()
    self.hand = {}
end

--- 清除所有牌上的 jokerOverride(大王改值效果仅当局有效)
function PlayerState:ClearJokerOverrides()
    for _, card in ipairs(self.hand) do
        card.jokerOverride = nil
    end
    for _, card in ipairs(self.deck) do
        card.jokerOverride = nil
    end
    for _, card in ipairs(self.discardPile) do
        card.jokerOverride = nil
    end
end

--- 花色排序: 方块 < 梅花 < 红桃 < 黑桃
local SUIT_ORDER = { diamond = 1, club = 2, heart = 3, spade = 4 }

--- 排序键: 2-13升序, A(1)排在K后, 小王(14)再后, 大王(15)最后
--- 同rank按花色排序
---@param card table
---@return number rankKey
---@return number suitKey
local function cardSortKeys(card)
    local r = card.rank
    local rankKey
    if r >= 2 and r <= 13 then rankKey = r        -- 2-13 → 2-13
    elseif r == 1 then rankKey = 14               -- A → 14
    elseif r == 14 then rankKey = 15              -- 小王 → 15
    else rankKey = 16 end                         -- 大王 → 16
    local suitKey = SUIT_ORDER[card.suit] or 0
    return rankKey, suitKey
end

--- 添加牌到手中(自动保持排序: 2-K A 小王 大王, 同rank按方块/梅花/红桃/黑桃)
---@param card table
function PlayerState:AddToHand(card)
    table.insert(self.hand, card)
    table.sort(self.hand, function(a, b)
        local ar, as = cardSortKeys(a)
        local br, bs = cardSortKeys(b)
        if ar ~= br then return ar < br end
        return as < bs
    end)
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

--- 添加牌到弃牌堆
---@param card table
function PlayerState:AddToDiscard(card)
    table.insert(self.discardPile, card)
end

--- 从弃牌堆随机取一张
---@return table|nil
function PlayerState:DrawRandomFromDiscard()
    if #self.discardPile == 0 then return nil end
    local idx = math.random(1, #self.discardPile)
    return table.remove(self.discardPile, idx)
end

--- 获取弃牌堆数量
---@return number
function PlayerState:GetDiscardCount()
    return #self.discardPile
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
