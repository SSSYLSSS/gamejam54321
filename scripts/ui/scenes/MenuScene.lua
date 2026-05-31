-- ============================================================================
-- ui/scenes/MenuScene.lua - 主菜单场景
-- ============================================================================

local UI = require("urhox-libs/UI")
local Colors = require("ui.Colors")
local StatsSystem = require("system.StatsSystem")
local SFXManager = require("system.SFXManager")

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
        onPointerEnter = function()
            SFXManager.Play("buttonFocus")
        end,
        onClick = function(self)
            SFXManager.Play("buttonPress")
            if onClick then onClick(self) end
        end,
    }
end

--- 标题图片 widget 引用 (供外部每帧获取位置)
MenuScene.titleWidgets = nil
--- 标题图片配置 (size/rotate)
MenuScene.titleConfigs = nil

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
    table.insert(buttons, CreateMenuButton("对局回放", { 120, 180, 220, 255 }, callbacks.onReplay))
    table.insert(buttons, CreateMenuButton("教程", { 180, 160, 255, 255 }, callbacks.onTutorial))
    table.insert(buttons, CreateMenuButton("统计", { 130, 200, 180, 255 }, callbacks.onStats))
    table.insert(buttons, CreateMenuButton("设置", Colors.textDim, callbacks.onSettings))
    table.insert(buttons, CreateMenuButton("退出游戏", Colors.danger, callbacks.onExit))

    -- 标题图片(五 四 三 21) - 居中散列 + 浮动动画
    -- 根据屏幕高度动态缩放，避免小屏幕下遮挡按钮
    local sw = graphics:GetWidth() / graphics:GetDPR()
    local sh = graphics:GetHeight() / graphics:GetDPR()
    -- 菜单卡片约占 550px 高度 + 5%底部边距，标题只能用剩余空间
    local availableTop = sh - 550 - sh * 0.05
    -- 以 21 图片为约束：它从 y=11% 开始，需要在 availableTop 内放下
    local maxBigSize = math.max(150, availableTop - sh * 0.11)
    local titleScale = math.min(1.0, maxBigSize / 500)
    titleScale = math.max(0.3, titleScale)
    local smallSize = math.floor(300 * titleScale)
    local bigSize = math.floor(500 * titleScale)
    local bigTopPercent = math.floor(11 * titleScale)
    -- 五四三居中散列: 中心点分别在 30%, 50%, 70% 宽度
    -- 四在正中(50%), 五在左(30%), 三在右(70%)
    -- 二一居中在四下方, 二在左(42%), 一在右(58%)
    -- left = 中心百分比 - 半宽/屏幕宽
    local halfSmall = smallSize * 0.5
    local halfBig = bigSize * 0.5
    local titleImages = {
        { src = "pic/五.png", size = smallSize, x = tostring(math.floor((0.30 * sw - halfSmall) / sw * 100)) .. "%", y = "0%",  rotate = -12 },
        { src = "pic/四.png", size = smallSize, x = tostring(math.floor((0.50 * sw - halfSmall) / sw * 100)) .. "%", y = "0%",  rotate = 0 },
        { src = "pic/三.png", size = smallSize, x = tostring(math.floor((0.70 * sw - halfSmall) / sw * 100)) .. "%", y = "0%",  rotate = 10 },
        { src = "pic/二.png", size = bigSize,   x = tostring(math.floor((0.42 * sw - halfBig) / sw * 100)) .. "%",   y = tostring(bigTopPercent) .. "%", rotate = -5 },
        { src = "pic/一.png", size = bigSize,   x = tostring(math.floor((0.58 * sw - halfBig) / sw * 100)) .. "%",   y = tostring(bigTopPercent) .. "%", rotate = 3 },
    }
    local titleWidgets = {}
    for i, img in ipairs(titleImages) do
        local w = UI.Panel {
            width = img.size,
            height = img.size,
            backgroundImage = img.src,
            backgroundFit = "contain",
            position = "absolute",
            left = img.x,
            top = img.y,
            rotate = img.rotate,
            pointerEvents = "none",
        }
        table.insert(titleWidgets, w)
    end

    -- 保存引用供外部位置跟踪
    MenuScene.titleWidgets = titleWidgets
    MenuScene.titleConfigs = titleImages

    -- 启动呼吸浮动动画(每个图片独立循环, 利用不同duration实现错开效果)
    for i, w in ipairs(titleWidgets) do
        local baseDuration = 2.2 + i * 0.15  -- 每个略微不同周期，产生自然错开
        local amplitude = 10 + i * 2  -- 浮动幅度微差
        w:Animate({
            keyframes = {
                [0]   = { translateY = 0, scale = 1.0 },
                [0.5] = { translateY = -amplitude, scale = 1.04 },
                [1]   = { translateY = 0, scale = 1.0 },
            },
            duration = baseDuration,
            easing = "easeInOut",
            loop = true,
            direction = "normal",
        })
    end

    -- 构建children(菜单卡片内不再放标题)
    local children = {}

    for _, btn in ipairs(buttons) do
        table.insert(children, btn)
    end

    table.insert(children, UI.Panel {
        width = "100%",
        marginTop = 12,
        alignItems = "center",
        children = {
            UI.Label {
                text = "v1.3  |  聚光灯48小时GameJam广州站2026",
                fontSize = 11,
                fontColor = { 100, 110, 130, 180 },
            },
        }
    })

    -- 根面板: 标题图片(absolute)漂浮在屏幕上方, 菜单卡片偏下
    local rootChildren = {
        UI.Panel {
            width = 320,
            backgroundColor = Colors.menuCard,
            borderRadius = 16,
            borderWidth = 1,
            borderColor = Colors.menuBorder,
            padding = 36,
            gap = 20,
            alignItems = "center",
            marginTop = "auto",
            marginBottom = "5%",
            children = children,
        },
    }
    -- 把标题图片作为 absolute 元素加入根面板
    for _, w in ipairs(titleWidgets) do
        table.insert(rootChildren, w)
    end

    return UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        backgroundColor = Colors.menuBg,
        justifyContent = "center",
        alignItems = "center",
        children = rootChildren,
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
                        onPointerEnter = function()
                            SFXManager.Play("buttonFocus")
                        end,
                        onClick = function(self)
                            SFXManager.Play("buttonPress")
                            if callbacks.onBack then callbacks.onBack(self) end
                        end,
                    },
                }
            },
        }
    }
end

--- 构建多人游戏房间选择 UI
---@param callbacks table {onStartMatch, onBack}
---@return table root
function MenuScene.BuildMultiplayerMenu(callbacks)
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
                        text = "多人游戏",
                        fontSize = 20,
                        fontColor = Colors.gold,
                    },
                    UI.Panel { width = "80%", height = 1, backgroundColor = Colors.menuBorder, marginVertical = 4 },
                    CreateMenuButton("开始匹配", Colors.accent, callbacks.onStartMatch),
                    UI.Panel { height = 8 },
                    CreateMenuButton("返回菜单", Colors.textDim, callbacks.onBack),
                }
            },
        }
    }
end

--- 构建多人游戏匹配等待 UI
---@param onBack function
---@return table root
function MenuScene.BuildMultiplayerWaiting(onBack)
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
                        text = "正在匹配对手...",
                        fontSize = 15,
                        fontColor = Colors.accent,
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "匹配成功后将自动进入游戏",
                        fontSize = 12,
                        fontColor = Colors.textDim,
                        textAlign = "center",
                    },
                    UI.Panel { height = 8 },
                    UI.Button {
                        text = "取消",
                        width = "100%",
                        height = 40,
                        onPointerEnter = function()
                            SFXManager.Play("buttonFocus")
                        end,
                        onClick = function(self)
                            SFXManager.Play("buttonPress")
                            if onBack then onBack(self) end
                        end,
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
                        onPointerEnter = function()
                            SFXManager.Play("buttonFocus")
                        end,
                        onClick = function(self)
                            SFXManager.Play("buttonPress")
                            if onBack then onBack(self) end
                        end,
                    },
                }
            },
        }
    }
end

return MenuScene
