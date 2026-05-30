-- ============================================================================
-- system/AISystem.lua - AI 决策系统(支持三种难度)
-- easy: 随机决策，经常犯错
-- normal: 基础策略(原逻辑)
-- hard: 高级策略，考虑特殊牌效果和对手状态
-- ============================================================================

local Card = require("core.Card")
local Constant = require("core.Constant")
local GameConfig = require("core.GameConfig")

local AISystem = {}

--- AI 难度等级
AISystem.DIFFICULTY = {
    EASY = "easy",
    NORMAL = "normal",
    HARD = "hard",
}

-- 当前难度(默认普通)
local currentDifficulty = AISystem.DIFFICULTY.NORMAL

--- 设置AI难度
---@param diff string "easy"|"normal"|"hard"
function AISystem.SetDifficulty(diff)
    currentDifficulty = diff or AISystem.DIFFICULTY.NORMAL
end

--- 获取当前难度
---@return string
function AISystem.GetDifficulty()
    return currentDifficulty
end

-- ============================================================================
-- 简单难度: 随机决策，有较高概率犯错
-- ============================================================================

--- 简单AI: 随机弃牌
---@param hand table[]
---@param turnIndex number
---@return number[]
local function easyDecideDiscard(hand, turnIndex)
    local maxDiscard = GameConfig.MAX_DISCARD[turnIndex]
    local discardIndices = {}

    -- 30%概率完全不弃牌
    if math.random() < 0.3 then
        return {}
    end

    -- 随机弃1-2张牌(不管好坏)
    local count = math.random(1, math.min(2, maxDiscard))
    local available = {}
    for i = 1, #hand do
        table.insert(available, i)
    end

    for _ = 1, count do
        if #available == 0 then break end
        local pick = math.random(1, #available)
        table.insert(discardIndices, available[pick])
        table.remove(available, pick)
    end

    return discardIndices
end

--- 简单AI: 结算后随机保留
---@param hand table[]
---@return number[], number|nil
local function easyDecidePostGame(hand)
    -- 随机保留一张
    local keepIdx = math.random(1, #hand)

    -- 随机弃0-2张
    local discardIndices = {}
    local count = math.random(0, math.min(GameConfig.POST_DISCARD_MAX, #hand - 1))
    local available = {}
    for i = 1, #hand do
        if i ~= keepIdx then
            table.insert(available, i)
        end
    end

    for _ = 1, count do
        if #available == 0 then break end
        local pick = math.random(1, #available)
        table.insert(discardIndices, available[pick])
        table.remove(available, pick)
    end

    return discardIndices, keepIdx
end

-- ============================================================================
-- 普通难度: 基础策略(原始逻辑)
-- ============================================================================

--- 普通AI: 根据距21的距离决定弃牌
---@param hand table[]
---@param turnIndex number
---@return number[]
local function normalDecideDiscard(hand, turnIndex)
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
        return {}
    end

    if distance > 0 then
        -- 点数超过21，弃掉最大的普通牌
        local sortedCards = {}
        for idx, card in ipairs(hand) do
            if Card.IsNormal(card) then
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
            if Card.IsNormal(card) and card.rank ~= 1 then
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
            if Card.IsNormal(card) then
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

--- 普通AI: 保留中等价值牌
---@param hand table[]
---@return number[], number|nil
local function normalDecidePostGame(hand)
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

-- ============================================================================
-- 困难难度: 高级策略，考虑特殊牌效果
-- ============================================================================

--- 计算牌的战略价值(困难AI用)
--- 新规则:
---   8: 己方普通牌各-2, 对方普通牌各+2
---   9: 灵活(0或9)
---   10: 己方稀有牌+罕见牌各-9
---   J: 己方普通牌→0
---   Q: 对方最高普通牌×2, 己方取至十位
---   K: 对方普通牌+稀有牌×2
---   A: 对方同花色牌×2
---@param card table
---@param hand table[]
---@param totalPoints number
---@return number score 越高越值得保留
local function calculateCardStrategicValue(card, hand, totalPoints)
    local score = 0
    local target = GameConfig.TARGET_POINTS

    -- A: 高战略价值(翻倍对手同花色)
    if card.rank == 1 then
        score = score + 14
        return score
    end

    -- K: 对方普通牌+稀有牌×2, 战略价值极高
    if card.rank == 13 then
        score = score + 13
        return score
    end

    -- Q: 对方最高普通牌×3 + 己方取整, 战略价值高
    if card.rank == 12 then
        score = score + 12
        return score
    end

    -- J: 己方普通牌→0 (大幅降低己方点数)
    -- 如果己方普通牌多且总点数高, J能大幅降点
    if card.rank == 11 then
        local normalCount = 0
        local normalPointsTotal = 0
        for _, c in ipairs(hand) do
            if Card.IsNormal(c) then
                normalCount = normalCount + 1
                normalPointsTotal = normalPointsTotal + Card.GetBasePoints(c)
            end
        end
        -- J把普通牌全变0, 节省 = normalPointsTotal
        if totalPoints > target and normalPointsTotal > 5 then
            score = score + 11  -- 超21且J能省很多点 → 极高价值
        elseif normalCount >= 2 then
            score = score + 7
        else
            score = score + 2  -- 没普通牌, J自身11点太高
        end
        return score
    end

    -- 10: 己方稀有牌(8-10)+罕见牌(J/Q/K)各-9, 让高点数牌变低
    if card.rank == 10 then
        local rareOrFaceCount = 0
        for _, c in ipairs(hand) do
            if Card.IsFace(c) or (c.rank >= 8 and c.rank <= 10) then
                rareOrFaceCount = rareOrFaceCount + 1
            end
        end
        -- 10本身也是稀有牌, 扣除自身计数
        rareOrFaceCount = rareOrFaceCount - 1
        if rareOrFaceCount >= 2 then
            score = score + 12  -- 有多张稀有/罕见牌, 10效果极佳
        elseif rareOrFaceCount == 1 then
            score = score + 7   -- 只有一张其他稀有/罕见牌, 效果一般
        else
            score = score + 3   -- 无其他稀有/罕见牌, 10只贡献自身(且自身也被-10=0点)
        end
        return score
    end

    -- 9: 灵活牌(0或9)，在接近21时极有价值
    if card.rank == 9 then
        score = score + 9
        if math.abs(totalPoints - target) <= 9 then score = score + 3 end
        return score
    end

    -- 8: 己方普通牌各-2, 对方普通牌各+2
    -- 己方普通牌越少8越好(对方被+2更多)
    if card.rank == 8 then
        local normalCount = 0
        for _, c in ipairs(hand) do
            if Card.IsNormal(c) then normalCount = normalCount + 1 end
        end
        if normalCount <= 1 then
            score = score + 8   -- 己方几乎没普通牌, 8主要拉高对方
        elseif normalCount <= 3 then
            score = score + 5
        else
            score = score + 2   -- 己方普通牌太多, 8弊大于利
        end
        return score
    end

    -- 普通牌(2-7): 根据距离21的贡献决定价值
    local pts = Card.GetBasePoints(card)
    local distance = totalPoints - target
    if distance > 0 then
        -- 超过21: 大点数牌价值低
        score = score - pts
    elseif distance < -5 then
        -- 远低于21: 大点数牌价值高
        score = score + pts
    else
        -- 接近21: 能精确凑数的牌价值高
        local need = target - (totalPoints - pts)
        if need >= 2 and need <= 7 then
            score = score + 5
        else
            score = score + 3
        end
    end

    return score
end

--- 困难AI: 策略性弃牌
---@param hand table[]
---@param turnIndex number
---@return number[]
local function hardDecideDiscard(hand, turnIndex)
    local maxDiscard = GameConfig.MAX_DISCARD[turnIndex]

    -- 计算总点数
    local totalPoints = 0
    for _, card in ipairs(hand) do
        totalPoints = totalPoints + Card.GetBasePoints(card)
    end

    local target = GameConfig.TARGET_POINTS

    -- 如果已经很接近21, 不弃牌
    if math.abs(totalPoints - target) <= 1 then
        return {}
    end

    -- 计算每张牌的战略价值
    local cardValues = {}
    for i, card in ipairs(hand) do
        local value = calculateCardStrategicValue(card, hand, totalPoints)
        table.insert(cardValues, { idx = i, value = value, card = card })
    end

    -- 按价值升序排列(价值低的优先弃掉)
    table.sort(cardValues, function(a, b) return a.value < b.value end)

    local discardIndices = {}

    -- 策略: 弃掉价值最低的牌，同时考虑点数优化
    local removedPoints = 0
    for _, entry in ipairs(cardValues) do
        if #discardIndices >= maxDiscard then break end

        local pts = Card.GetBasePoints(entry.card)

        -- 如果弃掉后点数更接近21, 或者当前点数已超21
        if totalPoints - removedPoints > target then
            -- 超过21: 弃掉价值低于8的牌
            if entry.value < 8 then
                table.insert(discardIndices, entry.idx)
                removedPoints = removedPoints + pts
            end
        elseif totalPoints - removedPoints < target - 3 then
            -- 远低于21: 弃掉低价值的小牌
            if entry.value < 5 and pts <= 3 then
                table.insert(discardIndices, entry.idx)
                removedPoints = removedPoints + pts
            end
        else
            -- 接近21: 只弃极低价值牌
            if entry.value < 0 then
                table.insert(discardIndices, entry.idx)
                removedPoints = removedPoints + pts
            end
        end
    end

    return discardIndices
end

--- 困难AI: 策略性保留
---@param hand table[]
---@return number[], number|nil
local function hardDecidePostGame(hand)
    local totalPoints = 0
    for _, card in ipairs(hand) do
        totalPoints = totalPoints + Card.GetBasePoints(card)
    end

    local bestKeepIdx = nil
    local bestKeepScore = -999
    for idx, card in ipairs(hand) do
        local score = 0
        -- 保留策略: 偏好特殊牌和适中点数牌
        if card.rank == 1 then
            score = 18  -- A翻倍效果极强
        elseif card.rank == 13 then
            score = 16  -- K对方全普通×2
        elseif card.rank == 12 then
            score = 15  -- Q对方最高普通×3+己方取整
        elseif card.rank == 9 then
            score = 14  -- 9灵活(0或9)
        elseif card.rank == 11 then
            score = 10  -- J己方普通→0
        elseif card.rank == 10 then
            score = 9   -- 10己方稀有/罕见牌-9
        elseif card.rank == 8 then
            score = 8   -- 8双刃剑
        elseif Card.IsJoker(card) then
            score = 20  -- 鬼牌最优先保留
        else
            -- 普通牌(2-7): 4-5点最佳(中间值)
            local pts = Card.GetBasePoints(card)
            score = 7 - math.abs(pts - 4.5) * 2
        end

        if score > bestKeepScore then
            bestKeepScore = score
            bestKeepIdx = idx
        end
    end

    -- 弃牌: 普通牌优先弃
    local sortedIndices = {}
    for idx = 1, #hand do
        if idx ~= bestKeepIdx then
            local card = hand[idx]
            local priority = 0
            if Card.IsNormal(card) then priority = 30 end  -- 普通牌优先弃
            if card.rank == 8 then priority = 15 end       -- 8次优先弃
            table.insert(sortedIndices, { idx = idx, priority = priority })
        end
    end
    table.sort(sortedIndices, function(a, b) return a.priority > b.priority end)

    local discardIndices = {}
    local discardCount = math.min(GameConfig.POST_DISCARD_MAX, #sortedIndices)
    for j = 1, discardCount do
        table.insert(discardIndices, sortedIndices[j].idx)
    end

    return discardIndices, bestKeepIdx
end

-- ============================================================================
-- 公开接口(根据难度分派)
-- ============================================================================

--- AI决策: 选择要弃置的牌索引
---@param hand table[] AI手牌
---@param turnIndex number 当前回合(1,2,3)
---@return number[]
function AISystem.DecideDiscard(hand, turnIndex)
    if currentDifficulty == AISystem.DIFFICULTY.EASY then
        return easyDecideDiscard(hand, turnIndex)
    elseif currentDifficulty == AISystem.DIFFICULTY.HARD then
        return hardDecideDiscard(hand, turnIndex)
    else
        return normalDecideDiscard(hand, turnIndex)
    end
end

--- AI决策: 结算后选牌(保留/弃置)
---@param hand table[]
---@return number[] discardIndices 弃置到牌堆的索引
---@return number|nil keepIndex 保留到下局的索引
function AISystem.DecidePostGame(hand)
    if currentDifficulty == AISystem.DIFFICULTY.EASY then
        return easyDecidePostGame(hand)
    elseif currentDifficulty == AISystem.DIFFICULTY.HARD then
        return hardDecidePostGame(hand)
    else
        return normalDecidePostGame(hand)
    end
end

return AISystem
