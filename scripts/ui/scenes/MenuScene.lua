-- ============================================================================
-- ui/scenes/MenuScene.lua - 主菜单场景
-- ============================================================================

local UI = require("urhox-libs/UI")
local Colors = require("ui.Colors")
local StatsSystem = require("system.StatsSystem")

local MenuScene = {}

--- 创建菜单按钮
---@param text string
---@param color table
---@param onClick function
local function CreateMenuButton(text, color, onClick)
    return UI.Button {
        text = text,
        width = "100%",
        height = 44,
        fontSize = 15,
        fontColor = color,
        backgroundColor = { 40, 52, 72, 200 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { color[1], color[2], color[3], 80 },
        onClick = onClick,
    }
end

--- 构建主菜单 UI
---@param callbacks table {hasSave, onContinue, onStart, onMultiplayer, onStats, onSettings, onExit}
---@return table root
function MenuScene.Build(callbacks)
    -- 动态构建按钮列表
    local buttons = {}

    -- 继续游戏按钮(有存档时显示)
    if callbacks.hasSave then
        table.insert(buttons, CreateMenuButton("继续游戏", Colors.success, callbacks.onContinue))
    end

    table.insert(buttons, CreateMenuButton("开始游戏", Colors.accent, callbacks.onStart))
    table.insert(buttons, CreateMenuButton("多人游戏", Colors.gold, callbacks.onMultiplayer))
    table.insert(buttons, CreateMenuButton("教程", { 180, 160, 255, 255 }, callbacks.onTutorial))
    table.insert(buttons, CreateMenuButton("统计", { 130, 200, 180, 255 }, callbacks.onStats))
    table.insert(buttons, CreateMenuButton("设置", Colors.textDim, callbacks.onSettings))
    table.insert(buttons, CreateMenuButton("退出游戏", Colors.danger, callbacks.onExit))

    -- 构建children
    local children = {
        UI.Label {
            text = "五!四!三!",
            fontSize = 28,
            fontColor = Colors.gold,
            textAlign = "center",
        },
        UI.Label {
            text = "二十一点!",
            fontSize = 22,
            fontColor = Colors.text,
            textAlign = "center",
        },
        UI.Panel {
            width = "80%",
            height = 1,
            backgroundColor = Colors.menuBorder,
            marginVertical = 8,
        },
    }

    for _, btn in ipairs(buttons) do
        table.insert(children, btn)
    end

    table.insert(children, UI.Panel {
        width = "100%",
        marginTop = 12,
        alignItems = "center",
        children = {
            UI.Label {
                text = "v1.3  |  GameJam 2025",
                fontSize = 11,
                fontColor = { 100, 110, 130, 180 },
            },
        }
    })

    return UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        backgroundColor = Colors.menuBg,
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 320,
                backgroundColor = Colors.menuCard,
                borderRadius = 16,
                borderWidth = 1,
                borderColor = Colors.menuBorder,
                padding = 36,
                gap = 20,
                alignItems = "center",
                children = children,
            },
        }
    }
end

--- 构建难度选择 UI
---@param callbacks table {onSelect(difficulty), onBack}
---@return table root
function MenuScene.BuildDifficultySelect(callbacks)
    local diffColors = {
        easy = { 80, 200, 120, 255 },
        normal = { 100, 160, 255, 255 },
        hard = { 255, 80, 80, 255 },
    }

    return UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        backgroundColor = Colors.menuBg,
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 320,
                backgroundColor = Colors.menuCard,
                borderRadius = 16,
                borderWidth = 1,
                borderColor = Colors.menuBorder,
                padding = 32,
                gap = 16,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "选择难度",
                        fontSize = 22,
                        fontColor = Colors.gold,
                    },
                    UI.Panel {
                        width = "80%",
                        height = 1,
                        backgroundColor = Colors.menuBorder,
                        marginVertical = 4,
                    },
                    -- 简单
                    UI.Panel {
                        width = "100%",
                        gap = 4,
                        children = {
                            CreateMenuButton("简单", diffColors.easy, function()
                                callbacks.onSelect("easy")
                            end),
                            UI.Label {
                                text = "AI决策随机，适合新手熟悉规则",
                                fontSize = 11,
                                fontColor = Colors.textDim,
                                textAlign = "center",
                            },
                        }
                    },
                    -- 普通
                    UI.Panel {
                        width = "100%",
                        gap = 4,
                        children = {
                            CreateMenuButton("普通", diffColors.normal, function()
                                callbacks.onSelect("normal")
                            end),
                            UI.Label {
                                text = "AI基于点数距离决策，平衡挑战",
                                fontSize = 11,
                                fontColor = Colors.textDim,
                                textAlign = "center",
                            },
                        }
                    },
                    -- 困难
                    UI.Panel {
                        width = "100%",
                        gap = 4,
                        children = {
                            CreateMenuButton("困难", diffColors.hard, function()
                                callbacks.onSelect("hard")
                            end),
                            UI.Label {
                                text = "AI利用特殊牌效果，策略性极强",
                                fontSize = 11,
                                fontColor = Colors.textDim,
                                textAlign = "center",
                            },
                        }
                    },
                    UI.Panel { height = 8 },
                    UI.Button {
                        text = "返回",
                        width = "100%",
                        height = 36,
                        fontSize = 13,
                        onClick = callbacks.onBack,
                    },
                }
            },
        }
    }
end

--- 构建多人游戏提示 UI
---@param onBack function
---@return table root
function MenuScene.BuildMultiplayerNotice(onBack)
    return UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        backgroundColor = Colors.menuBg,
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 300,
                backgroundColor = Colors.menuCard,
                borderRadius = 16,
                borderWidth = 1,
                borderColor = Colors.menuBorder,
                padding = 32,
                gap = 16,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "多人游戏",
                        fontSize = 20,
                        fontColor = Colors.gold,
                    },
                    UI.Label {
                        text = "敬请期待...\n多人对战功能正在开发中",
                        fontSize = 13,
                        fontColor = Colors.textDim,
                        textAlign = "center",
                    },
                    UI.Panel { height = 8 },
                    UI.Button {
                        text = "返回",
                        width = "100%",
                        height = 40,
                        onClick = onBack,
                    },
                }
            },
        }
    }
end

--- 构建统计数据 UI
---@param onBack function
---@return table root
function MenuScene.BuildStats(onBack)
    local stats = StatsSystem.GetStats()
    local winRate = StatsSystem.GetWinRate()

    -- 难度胜率
    local easyWR = StatsSystem.GetDifficultyWinRate("easy")
    local normalWR = StatsSystem.GetDifficultyWinRate("normal")
    local hardWR = StatsSystem.GetDifficultyWinRate("hard")

    --- 创建统计行
    ---@param label string
    ---@param value string
    ---@param color table|nil
    local function StatRow(label, value, color)
        return UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            paddingHorizontal = 8,
            height = 28,
            children = {
                UI.Label { text = label, fontSize = 12, fontColor = Colors.textDim },
                UI.Label { text = value, fontSize = 13, fontColor = color or Colors.text },
            }
        }
    end

    return UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        backgroundColor = Colors.menuBg,
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 340,
                maxHeight = "85%",
                backgroundColor = Colors.menuCard,
                borderRadius = 16,
                borderWidth = 1,
                borderColor = Colors.menuBorder,
                padding = 28,
                gap = 12,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "游戏统计",
                        fontSize = 20,
                        fontColor = Colors.gold,
                    },
                    UI.Panel { width = "80%", height = 1, backgroundColor = Colors.menuBorder },
                    -- 总体
                    StatRow("总场次", tostring(stats.totalGames)),
                    StatRow("胜/负/平", string.format("%d / %d / %d", stats.totalWins, stats.totalLosses, stats.totalTies)),
                    StatRow("总胜率", string.format("%.1f%%", winRate), Colors.success),
                    StatRow("当前连胜", tostring(stats.currentStreak), stats.currentStreak > 0 and Colors.gold or Colors.textDim),
                    StatRow("最高连胜", tostring(stats.bestWinStreak), Colors.gold),
                    -- 分隔
                    UI.Panel { width = "80%", height = 1, backgroundColor = Colors.menuBorder, marginVertical = 4 },
                    UI.Label { text = "分难度胜率", fontSize = 13, fontColor = Colors.textDim },
                    StatRow("简单", string.format("%.1f%%  (%d局)", easyWR, stats.byDifficulty.easy and stats.byDifficulty.easy.games or 0), { 80, 200, 120, 255 }),
                    StatRow("普通", string.format("%.1f%%  (%d局)", normalWR, stats.byDifficulty.normal and stats.byDifficulty.normal.games or 0), { 100, 160, 255, 255 }),
                    StatRow("困难", string.format("%.1f%%  (%d局)", hardWR, stats.byDifficulty.hard and stats.byDifficulty.hard.games or 0), { 255, 80, 80, 255 }),
                    -- 分隔
                    UI.Panel { width = "80%", height = 1, backgroundColor = Colors.menuBorder, marginVertical = 4 },
                    UI.Label { text = "趣味数据", fontSize = 13, fontColor = Colors.textDim },
                    StatRow("三7触发次数", tostring((stats.sevenRuleWins or 0) + (stats.sevenRuleLosses or 0))),
                    StatRow("完美胜利(3-0)", tostring(stats.perfectGames or 0), Colors.gold),
                    StatRow("最高得分", tostring(stats.highestPoints or 0)),
                    StatRow("最低得分", stats.lowestPoints and stats.lowestPoints < 999 and tostring(stats.lowestPoints) or "-"),
                    -- 返回按钮
                    UI.Panel { height = 8 },
                    UI.Button {
                        text = "返回",
                        width = "100%",
                        height = 36,
                        fontSize = 13,
                        onClick = onBack,
                    },
                }
            },
        }
    }
end

return MenuScene
