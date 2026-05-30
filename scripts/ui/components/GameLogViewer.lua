-- ============================================================================
-- ui/components/GameLogViewer.lua - 游戏日志回放查看器
-- 以时间线形式展示本局所有操作(含对手隐藏操作)
-- ============================================================================

local UI = require("urhox-libs/UI")
local Colors = require("ui.Colors")
local GameController = require("service.GameController")
local SFXManager = require("system.SFXManager")

local GameLogViewer = {}

-- 日志条目颜色分类
local LOG_COLORS = {
    round   = { 218, 165, 32, 255 },   -- 金色: 回合/局标题
    player  = { 80, 200, 120, 255 },   -- 绿色: 玩家操作
    ai      = { 255, 140, 80, 255 },   -- 橙色: AI操作
    result  = { 180, 120, 255, 255 },  -- 紫色: 结算/特殊
    system  = { 160, 170, 185, 255 },  -- 灰色: 系统信息
}

--- 根据日志内容判断颜色类别
---@param msg string
---@return table color RGBA
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

--- 根据日志内容判断图标前缀
---@param msg string
---@return string icon
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

--- 创建日志查看器弹窗
---@param onClose function 关闭回调
---@return table overlay UI面板
function GameLogViewer.Create(onClose)
    local log = GameController.GetLog()

    -- 构建日志行
    local logEntries = {}

    if #log == 0 then
        table.insert(logEntries, UI.Label {
            text = "暂无游戏日志",
            fontSize = 13,
            fontColor = Colors.textDim,
        })
    else
        for i, msg in ipairs(log) do
            local color = getLogColor(msg)
            local icon = getLogIcon(msg)
            local isSeparator = msg:find("^===")

            if isSeparator then
                -- 局分隔线
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

    local overlay = UI.Panel {
        id = "gameLogOverlay",
        width = "100%",
        height = "100%",
        position = "absolute",
        backgroundColor = { 0, 0, 0, 200 },
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = "90%",
                height = "85%",
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
                            UI.Label {
                                text = "本局日志回放",
                                fontSize = 16,
                                fontColor = Colors.gold,
                            },
                            UI.Button {
                                text = "关闭",
                                fontSize = 12,
                                height = 30,
                                onPointerEnter = function() SFXManager.Play("buttonFocus") end,
                                onClick = function()
                                    SFXManager.Play("buttonPress")
                                    if onClose then onClose() end
                                end,
                            },
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
                    -- 滚动日志区
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

    return overlay
end

return GameLogViewer
