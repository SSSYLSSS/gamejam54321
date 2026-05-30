-- ============================================================================
-- system/StatsSystem.lua - 统计数据系统
-- 跟踪: 胜率、连胜、各难度战绩、牌使用情况等
-- ============================================================================

local StatsSystem = {}

-- 默认统计数据结构
local defaultStats = {
    -- 总体战绩
    totalGames = 0,
    totalWins = 0,
    totalLosses = 0,
    totalTies = 0,

    -- 连胜记录
    currentStreak = 0,      -- 当前连胜(负数为连败)
    bestWinStreak = 0,      -- 最长连胜
    worstLoseStreak = 0,    -- 最长连败

    -- 按难度统计
    byDifficulty = {
        easy = { games = 0, wins = 0, losses = 0, ties = 0 },
        normal = { games = 0, wins = 0, losses = 0, ties = 0 },
        hard = { games = 0, wins = 0, losses = 0, ties = 0 },
    },

    -- 特殊事件计数
    sevenRuleWins = 0,      -- 三7规则获胜次数
    sevenRuleLosses = 0,    -- 三7规则失败次数
    perfectGames = 0,       -- 完美胜利(3-0)

    -- 最高/最低点数
    highestPoints = 0,
    lowestPoints = 999,
    closestToTarget = 999,  -- 最接近21的距离
}

-- 当前统计数据
local stats = nil

local SAVE_FILE = "stats.json"

--- 深拷贝默认值
---@return table
local function deepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        copy[k] = deepCopy(v)
    end
    return copy
end

--- 加载统计数据
function StatsSystem.Load()
    if fileSystem:FileExists(SAVE_FILE) then
        local file = File(SAVE_FILE, FILE_READ)
        if file:IsOpen() then
            local content = file:ReadString()
            file:Close()
            local ok, data = pcall(cjson.decode, content)
            if ok and type(data) == "table" then
                -- 合并(防止旧版本缺字段)
                stats = deepCopy(defaultStats)
                for k, v in pairs(data) do
                    if type(v) == "table" and type(stats[k]) == "table" then
                        for kk, vv in pairs(v) do
                            stats[k][kk] = vv
                        end
                    else
                        stats[k] = v
                    end
                end
                return
            end
        end
    end
    stats = deepCopy(defaultStats)
end

--- 保存统计数据
function StatsSystem.Save()
    if not stats then return end
    local file = File(SAVE_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(cjson.encode(stats))
        file:Close()
    end
end

--- 确保已加载
local function ensureLoaded()
    if not stats then
        StatsSystem.Load()
    end
end

--- 记录一场游戏结果
---@param winner string "player"|"ai"|"tie"
---@param difficulty string "easy"|"normal"|"hard"
---@param playerScore number 玩家赢的局数
---@param aiScore number AI赢的局数
---@param hadSevenRule boolean 是否触发三7规则
---@param playerPoints number|nil 最终玩家点数
function StatsSystem.RecordGame(winner, difficulty, playerScore, aiScore, hadSevenRule, playerPoints)
    ensureLoaded()

    stats.totalGames = stats.totalGames + 1

    -- 按难度记录
    local diffStats = stats.byDifficulty[difficulty]
    if not diffStats then
        diffStats = { games = 0, wins = 0, losses = 0, ties = 0 }
        stats.byDifficulty[difficulty] = diffStats
    end
    diffStats.games = diffStats.games + 1

    if winner == "player" then
        stats.totalWins = stats.totalWins + 1
        diffStats.wins = diffStats.wins + 1

        -- 连胜
        if stats.currentStreak >= 0 then
            stats.currentStreak = stats.currentStreak + 1
        else
            stats.currentStreak = 1
        end
        stats.bestWinStreak = math.max(stats.bestWinStreak, stats.currentStreak)

        -- 完美胜利(3-0)
        if aiScore == 0 then
            stats.perfectGames = stats.perfectGames + 1
        end
    elseif winner == "ai" then
        stats.totalLosses = stats.totalLosses + 1
        diffStats.losses = diffStats.losses + 1

        -- 连败
        if stats.currentStreak <= 0 then
            stats.currentStreak = stats.currentStreak - 1
        else
            stats.currentStreak = -1
        end
        stats.worstLoseStreak = math.max(stats.worstLoseStreak, math.abs(stats.currentStreak))
    else
        stats.totalTies = stats.totalTies + 1
        diffStats.ties = diffStats.ties + 1
        stats.currentStreak = 0
    end

    -- 三7规则
    if hadSevenRule then
        if winner == "player" then
            stats.sevenRuleWins = stats.sevenRuleWins + 1
        elseif winner == "ai" then
            stats.sevenRuleLosses = stats.sevenRuleLosses + 1
        end
    end

    -- 点数记录
    if playerPoints then
        if playerPoints > stats.highestPoints then
            stats.highestPoints = playerPoints
        end
        if playerPoints < stats.lowestPoints then
            stats.lowestPoints = playerPoints
        end
        local dist = math.abs(21 - playerPoints)
        if dist < stats.closestToTarget then
            stats.closestToTarget = dist
        end
    end

    StatsSystem.Save()
end

--- 获取所有统计数据
---@return table
function StatsSystem.GetStats()
    ensureLoaded()
    return stats
end

--- 获取胜率百分比
---@return number 0-100
function StatsSystem.GetWinRate()
    ensureLoaded()
    if stats.totalGames == 0 then return 0 end
    return math.floor(stats.totalWins / stats.totalGames * 100)
end

--- 获取指定难度胜率
---@param difficulty string
---@return number
function StatsSystem.GetDifficultyWinRate(difficulty)
    ensureLoaded()
    local d = stats.byDifficulty[difficulty]
    if not d or d.games == 0 then return 0 end
    return math.floor(d.wins / d.games * 100)
end

--- 重置统计数据
function StatsSystem.Reset()
    stats = deepCopy(defaultStats)
    StatsSystem.Save()
end

return StatsSystem
