-- ============================================================================
-- AIPlayer.lua - AI对手决策逻辑
-- "五！四！三！二十一点！"
-- ============================================================================

local CardDefs = require("CardDefs")
local GameLogic = require("GameLogic")

local AIPlayer = {}

--- AI决策: 选择要弃置的牌
---@param hand table[] AI的手牌
---@param turnIndex number 当前回合(1,2,3)
---@return number[] 要弃置的牌索引
function AIPlayer.DecideDiscard(hand, turnIndex)
    local maxDiscard = GameLogic.MAX_DISCARD[turnIndex]
    local discardIndices = {}
    
    -- 计算当前手牌总点数
    local totalPoints = 0
    for _, card in ipairs(hand) do
        totalPoints = totalPoints + CardDefs.GetBasePoints(card)
    end
    
    -- 策略: 根据与21的距离决定弃牌
    local target = 21
    local distance = totalPoints - target
    
    if math.abs(distance) <= 2 then
        -- 已经很接近21了，不弃牌
        return {}
    end
    
    -- 如果点数太高，弃掉大牌
    if distance > 0 then
        -- 点数超过21, 弃掉最大的牌(非7)
        local sortedCards = {}
        for idx, card in ipairs(hand) do
            if card.rank ~= 7 then  -- 7不能弃
                table.insert(sortedCards, { idx = idx, points = CardDefs.GetBasePoints(card) })
            end
        end
        table.sort(sortedCards, function(a, b) return a.points > b.points end)
        
        local removed = 0
        local removedPoints = 0
        for _, entry in ipairs(sortedCards) do
            if removed >= maxDiscard then break end
            if totalPoints - removedPoints - entry.points >= target - 5 then
                -- 弃掉这张后点数仍然合理
                table.insert(discardIndices, entry.idx)
                removedPoints = removedPoints + entry.points
                removed = removed + 1
            elseif distance - removedPoints > 3 then
                -- 点数差距还大，继续弃
                table.insert(discardIndices, entry.idx)
                removedPoints = removedPoints + entry.points
                removed = removed + 1
            end
        end
    elseif distance < -5 then
        -- 点数太低, 弃掉小牌希望抽到大牌
        local sortedCards = {}
        for idx, card in ipairs(hand) do
            if card.rank ~= 7 and card.rank ~= 1 then  -- 保留A(有特效)和7
                table.insert(sortedCards, { idx = idx, points = CardDefs.GetBasePoints(card) })
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
        -- 点数略低于21, 弃1-2张小牌
        local sortedCards = {}
        for idx, card in ipairs(hand) do
            if card.rank ~= 7 and CardDefs.IsNormal(card) then
                table.insert(sortedCards, { idx = idx, points = CardDefs.GetBasePoints(card) })
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

--- AI决策: 鬼牌效果
---@param hand table[] AI手牌
---@param opponentHand table[] 对手手牌(可能只有部分可见)
---@return table 决策 {jokerValues={}, smallJokerTarget=idx, bigJokerTarget={idx,value}}
function AIPlayer.DecideJokerEffects(hand, opponentHand)
    local decisions = {
        jokerValues = {},       -- 鬼牌选择的点数
        smallJokerTarget = nil, -- 小王要移除对方哪张牌的索引
        bigJokerCard = nil,     -- 大王修改自己哪张牌
        bigJokerValue = nil,    -- 大王设置的点数
    }
    
    -- 计算当前非鬼牌点数
    local nonJokerPoints = 0
    for _, card in ipairs(hand) do
        if not CardDefs.IsJoker(card) then
            nonJokerPoints = nonJokerPoints + CardDefs.GetBasePoints(card)
        end
    end
    
    -- 鬼牌选择点数: 让总和尽量接近21
    local jokerCount = 0
    for _, card in ipairs(hand) do
        if CardDefs.IsJoker(card) then
            jokerCount = jokerCount + 1
        end
    end
    
    if jokerCount > 0 then
        local remaining = 21 - nonJokerPoints
        local perJoker = math.floor(remaining / jokerCount)
        perJoker = math.max(0, math.min(13, perJoker))
        
        for idx, card in ipairs(hand) do
            if CardDefs.IsJoker(card) then
                decisions.jokerValues[idx] = perJoker
            end
        end
    end
    
    -- 小王: 移除对方点数最高的牌
    for _, card in ipairs(hand) do
        if card.rank == 14 then -- 小王
            local bestTarget = nil
            local bestPoints = -1
            for idx, opCard in ipairs(opponentHand) do
                local pts = CardDefs.GetBasePoints(opCard)
                if pts > bestPoints and opCard.rank ~= 7 then -- 7不能移除
                    bestPoints = pts
                    bestTarget = idx
                end
            end
            decisions.smallJokerTarget = bestTarget
            break
        end
    end
    
    -- 大王: 选择一张自己的牌改变点数
    for _, card in ipairs(hand) do
        if card.rank == 15 then -- 大王
            -- 找一张改变后收益最大的牌
            local bestIdx = nil
            local bestGain = -999
            for idx, c in ipairs(hand) do
                if not CardDefs.IsJoker(c) and c.rank ~= 7 then
                    local currentPts = CardDefs.GetBasePoints(c)
                    -- 目标: 让总点数更接近21
                    local optimalPts = 21 - (nonJokerPoints - currentPts)
                    optimalPts = math.max(0, math.min(13, optimalPts))
                    local gain = math.abs(21 - nonJokerPoints) - math.abs(21 - (nonJokerPoints - currentPts + optimalPts))
                    if gain > bestGain then
                        bestGain = gain
                        bestIdx = idx
                        decisions.bigJokerValue = optimalPts
                    end
                end
            end
            decisions.bigJokerCard = bestIdx
            break
        end
    end
    
    return decisions
end

return AIPlayer
