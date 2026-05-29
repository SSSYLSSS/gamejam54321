-- ============================================================================
-- system/AISystem.lua - AI 决策系统
-- ============================================================================

local Card = require("core.Card")
local Constant = require("core.Constant")
local GameConfig = require("core.GameConfig")

local AISystem = {}

--- AI决策: 选择要弃置的牌索引
---@param hand table[] AI手牌
---@param turnIndex number 当前回合(1,2,3)
---@return number[]
function AISystem.DecideDiscard(hand, turnIndex)
    local maxDiscard = GameConfig.MAX_DISCARD[turnIndex]
    local discardIndices = {}

    -- 计算当前手牌总点数
    local totalPoints = 0
    for _, card in ipairs(hand) do
        totalPoints = totalPoints + Card.GetBasePoints(card)
    end

    local target = GameConfig.TARGET_POINTS
    local distance = totalPoints - target

    if math.abs(distance) <= 2 then
        -- 已经很接近21了，不弃牌
        return {}
    end

    if distance > 0 then
        -- 点数超过21，弃掉最大的牌(非7)
        local sortedCards = {}
        for idx, card in ipairs(hand) do
            if card.rank ~= 7 then
                table.insert(sortedCards, { idx = idx, points = Card.GetBasePoints(card) })
            end
        end
        table.sort(sortedCards, function(a, b) return a.points > b.points end)

        local removed = 0
        local removedPoints = 0
        for _, entry in ipairs(sortedCards) do
            if removed >= maxDiscard then break end
            if totalPoints - removedPoints - entry.points >= target - 5 then
                table.insert(discardIndices, entry.idx)
                removedPoints = removedPoints + entry.points
                removed = removed + 1
            elseif distance - removedPoints > 3 then
                table.insert(discardIndices, entry.idx)
                removedPoints = removedPoints + entry.points
                removed = removed + 1
            end
        end
    elseif distance < -5 then
        -- 点数太低，弃掉小牌
        local sortedCards = {}
        for idx, card in ipairs(hand) do
            if card.rank ~= 7 and card.rank ~= 1 then
                table.insert(sortedCards, { idx = idx, points = Card.GetBasePoints(card) })
            end
        end
        table.sort(sortedCards, function(a, b) return a.points < b.points end)

        local removed = 0
        for _, entry in ipairs(sortedCards) do
            if removed >= maxDiscard then break end
            if entry.points <= 4 then
                table.insert(discardIndices, entry.idx)
                removed = removed + 1
            end
        end
    else
        -- 点数略低于21，弃1-2张小牌
        local sortedCards = {}
        for idx, card in ipairs(hand) do
            if card.rank ~= 7 and Card.IsNormal(card) then
                table.insert(sortedCards, { idx = idx, points = Card.GetBasePoints(card) })
            end
        end
        table.sort(sortedCards, function(a, b) return a.points < b.points end)

        local removed = 0
        local limit = math.min(2, maxDiscard)
        for _, entry in ipairs(sortedCards) do
            if removed >= limit then break end
            table.insert(discardIndices, entry.idx)
            removed = removed + 1
        end
    end

    return discardIndices
end

--- AI决策: 结算后选牌(保留/弃置)
---@param hand table[]
---@return number[] discardIndices 弃置到牌堆的索引
---@return number|nil keepIndex 保留到下局的索引
function AISystem.DecidePostGame(hand)
    -- 保留最好的牌(中等点数最优)
    local bestKeepIdx = nil
    local bestKeepScore = -1
    for idx, card in ipairs(hand) do
        local score = 0
        local pts = Card.GetBasePoints(card)
        score = 10 - math.abs(pts - 5)
        if card.rank == 1 then score = score + 3 end
        if card.rank >= 11 then score = score + 2 end
        if score > bestKeepScore then
            bestKeepScore = score
            bestKeepIdx = idx
        end
    end

    -- 弃置至多2张(点数最大的)
    local sortedIndices = {}
    for idx = 1, #hand do
        if idx ~= bestKeepIdx then
            table.insert(sortedIndices, idx)
        end
    end
    table.sort(sortedIndices, function(a, b)
        return Card.GetBasePoints(hand[a]) > Card.GetBasePoints(hand[b])
    end)

    local discardIndices = {}
    local discardCount = math.min(GameConfig.POST_DISCARD_MAX, #sortedIndices)
    for j = 1, discardCount do
        table.insert(discardIndices, sortedIndices[j])
    end

    return discardIndices, bestKeepIdx
end

return AISystem
