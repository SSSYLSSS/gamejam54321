-- ============================================================================
-- core/Card.lua - 卡牌数据定义
-- ============================================================================

local Constant = require("core.Constant")

local Card = {}

--- 获取卡牌类别
---@param rank number
---@return string category
local function getCategory(rank)
    if rank == 1 then return Constant.CATEGORY.ACE
    elseif rank >= 2 and rank <= 7 then return Constant.CATEGORY.NORMAL
    elseif rank >= 8 and rank <= 10 then return Constant.CATEGORY.RARE
    elseif rank >= 11 and rank <= 13 then return Constant.CATEGORY.FACE
    elseif rank >= 14 then return Constant.CATEGORY.JOKER
    end
    return Constant.CATEGORY.NORMAL
end

--- 获取卡牌效果ID
---@param rank number
---@param isJoker boolean
---@return string effectId
local function getEffectId(rank, isJoker)
    if isJoker then
        return rank == 14 and Constant.EFFECT.JOKER_SMALL or Constant.EFFECT.JOKER_BIG
    end
    if rank == 1 then return Constant.EFFECT.ACE_DOUBLE end
    if rank == 8 then return Constant.EFFECT.EIGHT_REDUCE end
    if rank == 9 then return Constant.EFFECT.NINE_FLEX end
    if rank == 10 then return Constant.EFFECT.TEN_REDUCE end
    if rank == 11 then return Constant.EFFECT.JACK_ZERO end
    if rank == 12 then return Constant.EFFECT.QUEEN_TRIPLE end
    if rank == 13 then return Constant.EFFECT.KING_DOUBLE end
    return Constant.EFFECT.NONE
end

--- 创建一张卡牌
---@param rank number 1-13 或 14(小王)/15(大王)
---@param suit string|nil 花色(鬼牌为nil)
---@return table card
function Card.Create(rank, suit)
    local isJoker = (rank >= 14)
    local card = {
        rank = rank,
        suit = suit,
        category = getCategory(rank),
        effectId = getEffectId(rank, isJoker),
        jokerValue = nil,   -- 鬼牌结算时设定的点数
    }
    return card
end

--- 获取卡牌基础点数
---@param card table
---@return number
function Card.GetBasePoints(card)
    -- 大王效果覆盖: 任意牌可被设为指定点数
    if card.jokerOverride ~= nil then
        return card.jokerOverride
    end
    if card.category == Constant.CATEGORY.JOKER then
        return card.jokerValue or 0
    end
    -- J=11, Q=12, K=13, A=1, 2-10=面值
    return card.rank
end

--- 获取卡牌显示名
---@param card table
---@return string
function Card.GetName(card)
    if Card.IsJoker(card) then
        return card.rank == 14 and "小王" or "大王"
    end
    local suitName = Constant.SUIT_SYMBOLS[card.suit] or "?"
    local rankName = Constant.RANK_NAMES[card.rank] or "?"
    return suitName .. rankName
end

--- 是否为鬼牌
---@param card table
---@return boolean
function Card.IsJoker(card)
    return card.category == Constant.CATEGORY.JOKER
end

--- 是否为普通牌(2-7)
---@param card table
---@return boolean
function Card.IsNormal(card)
    return card.category == Constant.CATEGORY.NORMAL
end

--- 是否为罕见牌(J/Q/K, rank 11-13)
---@param card table
---@return boolean
function Card.IsFace(card)
    return card.category == Constant.CATEGORY.FACE
end

return Card
