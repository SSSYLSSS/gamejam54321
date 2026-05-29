-- ============================================================================
-- system/DeckSystem.lua - 牌组管理系统
-- 负责牌组创建、洗牌、抽牌、弃牌堆回收
-- ============================================================================

local Card = require("core.Card")
local Constant = require("core.Constant")

local DeckSystem = {}

--- 创建一副完整54张牌组
---@return table[]
function DeckSystem.CreateFullDeck()
    local deck = {}
    local suits = { Constant.SUIT.SPADE, Constant.SUIT.HEART, Constant.SUIT.CLUB, Constant.SUIT.DIAMOND }
    for _, suit in ipairs(suits) do
        for rank = 1, 13 do
            table.insert(deck, Card.Create(rank, suit))
        end
    end
    table.insert(deck, Card.Create(14, nil)) -- 小王
    table.insert(deck, Card.Create(15, nil)) -- 大王
    return deck
end

--- Fisher-Yates 洗牌
---@param deck table[]
function DeckSystem.Shuffle(deck)
    for i = #deck, 2, -1 do
        local j = math.random(1, i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

--- 从牌堆顶抽一张牌; 牌堆空时用弃牌堆回收
---@param deck table[] 抽牌堆
---@param roundState table RoundState (持有弃牌堆)
---@return table|nil card
function DeckSystem.Draw(deck, roundState)
    if #deck == 0 then
        -- 将弃牌堆洗入
        local discards = roundState:TakeAllDiscards()
        if #discards > 0 then
            for _, card in ipairs(discards) do
                table.insert(deck, card)
            end
            DeckSystem.Shuffle(deck)
        end
    end
    if #deck == 0 then return nil end
    return table.remove(deck)
end

--- 从牌堆随机抽一张
---@param deck table[]
---@return table|nil card
function DeckSystem.DrawRandom(deck)
    if #deck == 0 then return nil end
    local idx = math.random(1, #deck)
    return table.remove(deck, idx)
end

--- 发初始手牌(补满 HAND_SIZE)
---@param playerState table PlayerState
---@param roundState table RoundState
---@param handSize number
function DeckSystem.DealToHand(playerState, roundState, handSize)
    local need = handSize - playerState:GetHandSize()
    for _ = 1, need do
        local card = DeckSystem.Draw(playerState.deck, roundState)
        if card then
            playerState:AddToHand(card)
        end
    end
end

return DeckSystem
