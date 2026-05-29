-- ============================================================================
-- CardDefs.lua - 卡牌定义与工具函数
-- "五！四！三！二十一点！" 卡牌系统
-- ============================================================================

local CardDefs = {}

-- 花色定义
CardDefs.SUITS = { "diamond", "club", "heart", "spade" }
CardDefs.SUIT_NAMES = {
    diamond = "方片",
    club = "梅花",
    heart = "红桃",
    spade = "黑桃",
}
CardDefs.SUIT_SYMBOLS = {
    diamond = "♦",
    club = "♣",
    heart = "♥",
    spade = "♠",
}
CardDefs.SUIT_COLORS = {
    diamond = { 220, 50, 50, 255 },
    club = { 40, 40, 40, 255 },
    heart = { 220, 50, 50, 255 },
    spade = { 40, 40, 40, 255 },
}

-- 点数显示
CardDefs.RANK_NAMES = {
    [1] = "A", [2] = "2", [3] = "3", [4] = "4", [5] = "5",
    [6] = "6", [7] = "7", [8] = "8", [9] = "9", [10] = "10",
    [11] = "J", [12] = "Q", [13] = "K",
}

-- 卡牌分类
CardDefs.CATEGORY = {
    ACE = "ace",         -- A: 翻倍对方同花色
    NORMAL = "normal",   -- 2~6: 普通牌
    SEVEN = "seven",     -- 7: 特殊规则
    RARE = "rare",       -- 8~10: 稀有牌
    FACE = "face",       -- J~K: 罕见牌
    JOKER = "joker",     -- 鬼牌
}

--- 获取卡牌分类
---@param rank number 点数 (1-13, 14=小王, 15=大王)
---@return string
function CardDefs.GetCategory(rank)
    if rank == 1 then return CardDefs.CATEGORY.ACE end
    if rank >= 2 and rank <= 6 then return CardDefs.CATEGORY.NORMAL end
    if rank == 7 then return CardDefs.CATEGORY.SEVEN end
    if rank >= 8 and rank <= 10 then return CardDefs.CATEGORY.RARE end
    if rank >= 11 and rank <= 13 then return CardDefs.CATEGORY.FACE end
    if rank == 14 or rank == 15 then return CardDefs.CATEGORY.JOKER end
    return "unknown"
end

--- 创建一张牌
---@param rank number 1-13 普通, 14=小王, 15=大王
---@param suit string|nil 花色 (鬼牌无花色)
---@return table
function CardDefs.CreateCard(rank, suit)
    local card = {
        rank = rank,
        suit = suit,
        category = CardDefs.GetCategory(rank),
        id = math.random(100000, 999999), -- 唯一ID
    }
    -- 鬼牌额外属性
    if rank == 14 then
        card.isSmallJoker = true
        card.jokerValue = nil -- 结算时选择的点数
    elseif rank == 15 then
        card.isBigJoker = true
        card.jokerValue = nil
    end
    return card
end

--- 创建一副完整54张牌组
---@return table[] 牌组数组
function CardDefs.CreateFullDeck()
    local deck = {}
    for _, suit in ipairs(CardDefs.SUITS) do
        for rank = 1, 13 do
            table.insert(deck, CardDefs.CreateCard(rank, suit))
        end
    end
    -- 两张鬼牌
    table.insert(deck, CardDefs.CreateCard(14, nil)) -- 小王
    table.insert(deck, CardDefs.CreateCard(15, nil)) -- 大王
    return deck
end

--- 洗牌 (Fisher-Yates)
---@param deck table[]
function CardDefs.Shuffle(deck)
    for i = #deck, 2, -1 do
        local j = math.random(1, i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

--- 获取卡牌的基础点数 (不含特效修正)
---@param card table
---@return number
function CardDefs.GetBasePoints(card)
    if card.category == CardDefs.CATEGORY.JOKER then
        return card.jokerValue or 0
    end
    return card.rank
end

--- 获取卡牌显示名
---@param card table
---@return string
function CardDefs.GetCardName(card)
    if card.rank == 14 then return "小王" end
    if card.rank == 15 then return "大王" end
    local suitName = CardDefs.SUIT_NAMES[card.suit] or ""
    local rankName = CardDefs.RANK_NAMES[card.rank] or tostring(card.rank)
    return suitName .. rankName
end

--- 获取卡牌简短显示
---@param card table
---@return string
function CardDefs.GetCardShort(card)
    if card.rank == 14 then return "🃏小" end
    if card.rank == 15 then return "🃏大" end
    local symbol = CardDefs.SUIT_SYMBOLS[card.suit] or "?"
    local rankName = CardDefs.RANK_NAMES[card.rank] or "?"
    return symbol .. rankName
end

--- 判断是否为鬼牌
---@param card table
---@return boolean
function CardDefs.IsJoker(card)
    return card.rank == 14 or card.rank == 15
end

--- 判断是否为普通牌(2~6)
---@param card table
---@return boolean
function CardDefs.IsNormal(card)
    return card.category == CardDefs.CATEGORY.NORMAL
end

--- 判断一张牌是否可以被视为点数7
---@param card table
---@return boolean
function CardDefs.CanCountAsSeven(card)
    if card.rank == 7 then return true end
    -- 鬼牌设为7时也可以视为7
    if CardDefs.IsJoker(card) and card.jokerValue == 7 then return true end
    return false
end

return CardDefs
