-- ============================================================================
-- ui/scenes/ReplayScene.lua - 对局回放场景
-- 包含: 历史列表选择 + 详细日志查看(观战模式)
-- ============================================================================

local UI = require("urhox-libs/UI")
local Colors = require("ui.Colors")
local MatchHistory = require("system.MatchHistory")

local ReplayScene = {}

--- 构建历史对局列表
---@param onBack function 返回主菜单
---@return table root
function ReplayScene.BuildList(onBack)
    local records = MatchHistory.GetAll()

    local listChildren = {}

    if #records == 0 then
        table.insert(listChildren, UI.Panel {
            width = "100%", height = 80,
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label {
                    text = "暂无对局记录",
                    fontSize = 14,
                    fontColor = Colors.textDim,
                },
                UI.Label {
                    text = "完成一局游戏后会自动保存",
                    fontSize = 11,
                    fontColor = { 100, 110, 130, 150 },
                    marginTop = 6,
                },
            }
        })
    else
        for i, record in ipairs(records) do
            local resultText = ""
            local resultColor = Colors.textDim
            if record.result == "win" then
                resultText = "胜利"
                resultColor = Colors.success
            elseif record.result == "lose" then
                resultText = "失败"
                resultColor = { 255, 100, 100, 255 }
            else
                resultText = "平局"
                resultColor = Colors.gold
            end

            -- 格式化时间
            local timeStr = ""
            if record.timestamp then
                timeStr = os.date("%m-%d %H:%M", record.timestamp)
            end

            -- 难度文本
            local diffText = ""
            if record.difficulty == "easy" then diffText = "简单"
            elseif record.difficulty == "hard" then diffText = "困难"
            else diffText = "普通" end

            local scoreText = ""
            if record.finalScore then
                scoreText = string.format("%d:%d", record.finalScore[1] or 0, record.finalScore[2] or 0)
            end

            local idx = i
            table.insert(listChildren, UI.Button {
                width = "100%",
                height = 52,
                backgroundColor = { 35, 45, 65, 200 },
                hoverBackgroundColor = { 50, 60, 85, 220 },
                borderRadius = 8,
                borderWidth = 1,
                borderColor = { 60, 75, 100, 120 },
                paddingHorizontal = 14,
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                onClick = function()
                    ReplayScene._showReplay(idx, onBack)
                end,
                children = {
                    -- 左侧: 时间+难度
                    UI.Panel {
                        gap = 2,
                        children = {
                            UI.Label {
                                text = timeStr,
                                fontSize = 12,
                                fontColor = Colors.text,
                            },
                            UI.Label {
                                text = diffText,
                                fontSize = 10,
                                fontColor = Colors.textDim,
                            },
                        }
                    },
                    -- 中间: 比分
                    UI.Label {
                        text = scoreText,
                        fontSize = 16,
                        fontColor = Colors.text,
                    },
                    -- 右侧: 结果
                    UI.Label {
                        text = resultText,
                        fontSize = 14,
                        fontColor = resultColor,
                    },
                }
            })
        end
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
                width = 360,
                maxHeight = "90%",
                backgroundColor = Colors.menuCard,
                borderRadius = 16,
                borderWidth = 1,
                borderColor = Colors.menuBorder,
                padding = 24,
                gap = 14,
                alignItems = "center",
                children = {
                    -- 标题
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = "对局回放",
                                fontSize = 20,
                                fontColor = Colors.gold,
                            },
                            UI.Button {
                                text = "返回",
                                fontSize = 12,
                                height = 30,
                                onClick = onBack,
                            },
                        }
                    },
                    UI.Panel { width = "80%", height = 1, backgroundColor = Colors.menuBorder },
                    -- 列表
                    UI.ScrollView {
                        width = "100%",
                        flexGrow = 1,
                        flexBasis = 0,
                        maxHeight = 400,
                        children = {
                            UI.Panel {
                                width = "100%",
                                gap = 8,
                                children = listChildren,
                            }
                        }
                    },
                }
            },
        }
    }
end

-- ============================================================================
-- 日志颜色分类 (与 GameLogViewer 一致)
-- ============================================================================

local LOG_COLORS = {
    round   = { 218, 165, 32, 255 },
    player  = { 80, 200, 120, 255 },
    ai      = { 255, 140, 80, 255 },
    result  = { 180, 120, 255, 255 },
    system  = { 160, 170, 185, 255 },
}

local function getLogColor(msg)
    if msg:find("^===") or msg:find("^第 %d+ 回合") then
        return LOG_COLORS.round
    elseif msg:find("^玩家") or msg:find("^弃置至牌堆") or msg:find("^保留至下局")
        or msg:find("^强制弃置鬼牌") then
        return LOG_COLORS.player
    elseif msg:find("^AI ") or msg:find("^AI") then
        return LOG_COLORS.ai
    elseif msg:find("^>>>") or msg:find("^结算") or msg:find("三7特殊规则")
        or msg:find("鬼牌效果") then
        return LOG_COLORS.result
    end
    return LOG_COLORS.system
end

local function getLogIcon(msg)
    if msg:find("^===") then return "---" end
    if msg:find("^第 %d+ 回合") then return " > " end
    if msg:find("弃置") then return " - " end
    if msg:find("补牌") or msg:find("抽") then return " + " end
    if msg:find("保留") then return " * " end
    if msg:find("放回抽牌堆") then return " < " end
    if msg:find("^>>>") then return " ! " end
    if msg:find("结算") then return " = " end
    if msg:find("比分") then return "   " end
    if msg:find("不弃牌") then return " . " end
    return "   "
end

--- 显示某一局的详细回放
---@param index number 历史记录索引
---@param onBackToList function 返回列表
function ReplayScene._showReplay(index, onBackToList)
    local record = MatchHistory.Get(index)
    if not record then return end

    local log = record.log or {}

    -- 构建日志行
    local logEntries = {}
    if #log == 0 then
        table.insert(logEntries, UI.Label {
            text = "无日志数据",
            fontSize = 13,
            fontColor = Colors.textDim,
        })
    else
        for i, msg in ipairs(log) do
            local color = getLogColor(msg)
            local icon = getLogIcon(msg)
            local isSeparator = msg:find("^===")

            if isSeparator then
                if i > 1 then
                    table.insert(logEntries, UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 60, 80, 120, 80 },
                        marginVertical = 6,
                    })
                end
                table.insert(logEntries, UI.Label {
                    text = msg,
                    fontSize = 13,
                    fontColor = color,
                    width = "100%",
                    textAlign = "center",
                })
            else
                table.insert(logEntries, UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    paddingHorizontal = 4,
                    paddingVertical = 2,
                    children = {
                        UI.Label {
                            text = icon,
                            fontSize = 11,
                            fontColor = { color[1], color[2], color[3], 150 },
                            width = 28,
                        },
                        UI.Label {
                            text = msg,
                            fontSize = 12,
                            fontColor = color,
                            flexGrow = 1,
                            flexShrink = 1,
                        },
                    }
                })
            end
        end
    end

    -- 顶部信息
    local resultText = ""
    local resultColor = Colors.textDim
    if record.result == "win" then
        resultText = "胜利"
        resultColor = Colors.success
    elseif record.result == "lose" then
        resultText = "失败"
        resultColor = { 255, 100, 100, 255 }
    else
        resultText = "平局"
        resultColor = Colors.gold
    end

    local timeStr = ""
    if record.timestamp then
        timeStr = os.date("%Y-%m-%d %H:%M", record.timestamp)
    end

    local scoreText = ""
    if record.finalScore then
        scoreText = string.format("最终比分 %d : %d", record.finalScore[1] or 0, record.finalScore[2] or 0)
    end

    local root = UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        backgroundColor = Colors.menuBg,
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = "92%",
                height = "90%",
                backgroundColor = Colors.menuCard,
                borderRadius = 12,
                borderWidth = 1,
                borderColor = Colors.menuBorder,
                padding = 16,
                gap = 10,
                children = {
                    -- 标题栏
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        children = {
                            UI.Panel {
                                flexDirection = "row", gap = 10, alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = "对局回放",
                                        fontSize = 16,
                                        fontColor = Colors.gold,
                                    },
                                    UI.Label {
                                        text = resultText,
                                        fontSize = 14,
                                        fontColor = resultColor,
                                    },
                                }
                            },
                            UI.Button {
                                text = "返回列表",
                                fontSize = 12,
                                height = 30,
                                onClick = function()
                                    -- 重建列表
                                    local listRoot = ReplayScene.BuildList(onBackToList)
                                    UI.SetRoot(listRoot)
                                end,
                            },
                        }
                    },
                    -- 对局信息
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        paddingHorizontal = 4,
                        children = {
                            UI.Label { text = timeStr, fontSize = 11, fontColor = Colors.textDim },
                            UI.Label { text = scoreText, fontSize = 11, fontColor = Colors.text },
                        }
                    },
                    -- 图例
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 12,
                        paddingHorizontal = 4,
                        children = {
                            UI.Label { text = "玩家", fontSize = 10, fontColor = LOG_COLORS.player },
                            UI.Label { text = "AI", fontSize = 10, fontColor = LOG_COLORS.ai },
                            UI.Label { text = "结算", fontSize = 10, fontColor = LOG_COLORS.result },
                            UI.Label { text = "系统", fontSize = 10, fontColor = LOG_COLORS.system },
                        }
                    },
                    -- 分割线
                    UI.Panel { width = "100%", height = 1, backgroundColor = Colors.menuBorder },
                    -- 日志滚动区
                    UI.ScrollView {
                        width = "100%",
                        flexGrow = 1,
                        flexBasis = 0,
                        children = {
                            UI.Panel {
                                width = "100%",
                                gap = 1,
                                padding = 4,
                                children = logEntries,
                            }
                        }
                    },
                }
            },
        }
    }

    UI.SetRoot(root)
end

return ReplayScene
