-- ============================================================================
-- network/Shared.lua - 多人游戏共享定义
-- 事件名、卡牌编解码、常量
-- ============================================================================

local Card = require("core.Card")
local Constant = require("core.Constant")

local Shared = {}

-- ============================================================================
-- 远程事件名
-- ============================================================================

Shared.EVENTS = {
    -- 握手
    CLIENT_READY       = "ClientReady",
    ASSIGN_PLAYER      = "AssignPlayer",

    -- 游戏流程 (Server → Client)
    ROUND_START        = "RoundStart",
    TURN_START         = "TurnStart",
    WAIT_OPPONENT      = "WaitOpponent",
    TURN_RESULT        = "TurnResult",
    SETTLEMENT_RESULT  = "SettlementResult",
    POST_PHASE_START   = "PostPhaseStart",
    ROUND_END          = "RoundEnd",
    GAME_OVER          = "GameOverResult",
    OPPONENT_DISCONNECTED = "OpponentDisconnected",

    -- 玩家操作 (Client → Server)
    PLAYER_DISCARD     = "PlayerDiscard",
    PLAYER_SKIP        = "PlayerSkip",
    PLAYER_JACK_PICK   = "PlayerJackPick",
    PLAYER_POST_DISCARD = "PlayerPostDiscard",
    PLAYER_POST_KEEP   = "PlayerPostKeep",
    PLAYER_CONTINUE    = "PlayerContinue",
}

-- ============================================================================
-- 卡牌编码/解码 (用于网络传输)
-- 花色索引: spade=1, heart=2, club=3, diamond=4, joker=5
-- 编码: suitIndex * 100 + rank
-- ============================================================================

local SUIT_TO_IDX = {
    spade = 1, heart = 2, club = 3, diamond = 4,
}
local IDX_TO_SUIT = {
    [1] = "spade", [2] = "heart", [3] = "club", [4] = "diamond",
}

--- 编码一张牌为整数
---@param card table
---@return number
function Shared.EncodeCard(card)
    if card.rank >= 14 then
        return 500 + card.rank  -- 514=小王, 515=大王
    end
    local suitIdx = SUIT_TO_IDX[card.suit] or 1
    return suitIdx * 100 + card.rank
end

--- 解码整数为卡牌
---@param code number
---@return table card
function Shared.DecodeCard(code)
    if code >= 514 then
        return Card.Create(code - 500, nil)  -- 鬼牌
    end
    local suitIdx = math.floor(code / 100)
    local rank = code % 100
    local suit = IDX_TO_SUIT[suitIdx] or "spade"
    return Card.Create(rank, suit)
end

--- 将手牌编码写入 VariantMap
---@param data userdata VariantMap
---@param prefix string 前缀 (如 "Hand")
---@param hand table[] 手牌数组
function Shared.EncodeHand(data, prefix, hand)
    data[prefix .. "Count"] = Variant(#hand)
    for i, card in ipairs(hand) do
        data[prefix .. i] = Variant(Shared.EncodeCard(card))
    end
end

--- 从 eventData 解码手牌
---@param eventData userdata
---@param prefix string
---@return table[] hand
function Shared.DecodeHand(eventData, prefix)
    local count = eventData[prefix .. "Count"]:GetInt()
    local hand = {}
    for i = 1, count do
        local code = eventData[prefix .. i]:GetInt()
        table.insert(hand, Shared.DecodeCard(code))
    end
    return hand
end

--- 将索引数组编码写入 VariantMap
---@param data userdata VariantMap
---@param prefix string
---@param indices number[]
function Shared.EncodeIndices(data, prefix, indices)
    data[prefix .. "Count"] = Variant(#indices)
    for i, idx in ipairs(indices) do
        data[prefix .. i] = Variant(idx)
    end
end

--- 从 eventData 解码索引数组
---@param eventData userdata
---@param prefix string
---@return number[]
function Shared.DecodeIndices(eventData, prefix)
    local count = eventData[prefix .. "Count"]:GetInt()
    local indices = {}
    for i = 1, count do
        table.insert(indices, eventData[prefix .. i]:GetInt())
    end
    return indices
end

return Shared
