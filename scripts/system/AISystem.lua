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
---@param card table
---@param hand table[]
---@param totalPoints number
---@return number score 越高越值得保留
local function calculateCardStrategicValue(card, hand, totalPoints)
    local score = 0
    local target = GameConfig.TARGET_POINTS
    local distance = totalPoints - target

    -- 7: 极高保留价值(三7必胜+不可被改变)
    if card.rank == 7 then
        local sevenCount = 0
        for _, c in ipairs(hand) do
            if c.rank == 7 then sevenCount = sevenCount + 1 end
        end
        score = score + 15
        if sevenCount >= 2 then score = score + 10 end  -- 接近三7
        return score
    end

    -- A: 高战略价值(翻倍对手同花色)
    if card.rank == 1 then
        score = score + 12
        return score
    end

    -- K: 对方向上取整到十位, 己方向下取整到十位 (总体有利)
    if card.rank == 13 then
        -- K效果: 拉远差距, 一般是有利的
        -- 当己方点数个位数大(如25→20)时减分多, 对方个位数小(如21→30)时加分多
        score = score + 7
        return score
    end

    -- Q: 使对方最小普通牌点数×3，战略价值高
    if card.rank == 12 then
        score = score + 10
        return score
    end

    -- J: 双重效果 - 弃置可选择补牌来源; 留在手中则结算时对方普通牌×2
    -- 策略: 如果留着J总点数接近21, 保留(翻倍对方); 否则弃置(利用选择补牌)
    if card.rank == 11 then
        local totalWithJ = totalPoints
        local totalWithoutJ = totalPoints - 11
        if math.abs(totalWithJ - GameConfig.TARGET_POINTS) <= 5 then
            score = score + 8  -- 留着J且接近21: 高保留价值(翻倍对方)
        else
            score = score - 2  -- 离21太远: 弃掉利用选择补牌效果
        end
        return score
    end

    -- 9: 灵活牌(0或9)，在接近21时极有价值
    if card.rank == 9 then
        score = score + 8
        if math.abs(distance) <= 9 then score = score + 4 end
        return score
    end

    -- 8: 己方普通牌-1, 对方普通牌+2 (双刃剑: 降己方但也拉高对方)
    -- 当己方普通牌多时8是劣势(降低太多); 当己方普通牌少时8有利(对方被+2更多)
    if card.rank == 8 then
        local normalCount = 0
        for _, c in ipairs(hand) do
            if Card.IsNormal(c) then normalCount = normalCount + 1 end
        end
        -- 己方普通牌越少, 8越有利(对方+2的收益>己方-1的损失)
        if normalCount <= 1 then
            score = score + 7  -- 己方没啥普通牌, 8主要拉高对方
        elseif normalCount <= 3 then
            score = score + 4  -- 平衡
        else
            score = score + 1  -- 己方普通牌太多, 8弊大于利
        end
        return score
    end

    -- 10: 弃置后+1，根据点数差距决定
    if card.rank == 10 then
        if distance >= 0 then
            score = score - 1  -- 点数够了，10本身0点但弃置有+1
        else
            score = score + 2
        end
        return score
    end

    -- 普通牌(2-6): 根据距离21的贡献决定价值
    local pts = Card.GetBasePoints(card)
    if distance > 0 then
        -- 超过21: 大点数牌价值低
        score = score - pts
    elseif distance < -5 then
        -- 远低于21: 小点数牌价值低
        score = score + pts
    else
        -- 接近21: 能精确凑数的牌价值高
        local need = target - (totalPoints - pts)
        if need >= 2 and need <= 6 then
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

    -- 如果已经很接近21, 考虑是否需要弃牌
    if math.abs(totalPoints - target) <= 1 then
        -- 接近21时: J留在手中更有价值(翻倍对方普通牌), 不要弃掉
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
        local newTotal = totalPoints - removedPoints - pts

        -- 不弃7(太有价值)
        if entry.card.rank == 7 then
            goto continue
        end

        -- J: 如果离21远则优先弃(选择补牌来源); 接近21则保留(翻倍对方)
        if entry.card.rank == 11 and math.abs(totalPoints - removedPoints - target) > 5 then
            table.insert(discardIndices, entry.idx)
            removedPoints = removedPoints + pts
            goto continue
        end

        -- 如果弃掉后点数更接近21, 或者当前点数已超21
        if totalPoints - removedPoints > target then
            -- 超过21: 弃掉大点数的非战略牌
            if entry.value < 8 then
                table.insert(discardIndices, entry.idx)
                removedPoints = removedPoints + pts
            end
        elseif totalPoints - removedPoints < target - 3 then
            -- 远低于21: 弃掉低价值的小牌(反直觉但为了腾位置)
            if entry.value < 5 and pts <= 3 then
                table.insert(discardIndices, entry.idx)
                removedPoints = removedPoints + pts
            end
        else
            -- 接近21: 只弃J或极低价值牌
            if entry.value < 0 then
                table.insert(discardIndices, entry.idx)
                removedPoints = removedPoints + pts
            end
        end

        ::continue::
    end

    return discardIndices
end

--- 困难AI: 策略性保留
---@param hand table[]
---@return number[], number|nil
local function hardDecidePostGame(hand)
    -- 按战略价值评估每张牌(用于下一局)
    local totalPoints = 0
    for _, card in ipairs(hand) do
        totalPoints = totalPoints + Card.GetBasePoints(card)
    end

    local bestKeepIdx = nil
    local bestKeepScore = -999
    for idx, card in ipairs(hand) do
        local score = 0
        -- 保留策略: 偏好特殊牌(A/Q/9/7)和适中点数牌
        if card.rank == 7 then
            score = 20  -- 7最优先保留(三7规则)
        elseif card.rank == 1 then
            score = 15  -- A翻倍效果
        elseif card.rank == 12 then
            score = 13  -- Q使对方最小普通牌×3
        elseif card.rank == 9 then
            score = 12  -- 9灵活(0或9)
        elseif card.rank == 8 then
            score = 7   -- 8双刃剑(己方-1, 对方+2)
        elseif card.rank == 13 then
            score = 9   -- K取整效果总体有利
        elseif card.rank == 11 then
            score = 4   -- J弃了更好
        elseif card.rank == 10 then
            score = 3   -- 10弃了+1
        else
            -- 普通牌: 4-5点最佳(中间值)
            local pts = Card.GetBasePoints(card)
            score = 7 - math.abs(pts - 4.5) * 2
        end

        if score > bestKeepScore then
            bestKeepScore = score
            bestKeepIdx = idx
        end
    end

    -- 弃牌: 优先弃掉J和10(利用弃置效果)，然后弃价值低的
    local sortedIndices = {}
    for idx = 1, #hand do
        if idx ~= bestKeepIdx then
            local card = hand[idx]
            local priority = 0
            if card.rank == 11 then priority = 60 end   -- J弃置有选择补牌来源效果(但保留可翻倍对方)
            if card.rank == 10 then priority = 50 end   -- 10弃了+1
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
