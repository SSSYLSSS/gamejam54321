-- ============================================================================
-- ui/scenes/MenuScene.lua - 主菜单场景
-- ============================================================================

local UI = require("urhox-libs/UI")
local Colors = require("ui.Colors")

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
---@param callbacks table {onStart, onMultiplayer, onSettings, onExit}
---@return table root
function MenuScene.Build(callbacks)
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
                children = {
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
                    CreateMenuButton("开始游戏", Colors.accent, callbacks.onStart),
                    CreateMenuButton("多人游戏", Colors.gold, callbacks.onMultiplayer),
                    CreateMenuButton("设置", Colors.textDim, callbacks.onSettings),
                    CreateMenuButton("退出游戏", Colors.danger, callbacks.onExit),
                    UI.Panel {
                        width = "100%",
                        marginTop = 12,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = "v1.1  |  GameJam 2025",
                                fontSize = 11,
                                fontColor = { 100, 110, 130, 180 },
                            },
                        }
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

return MenuScene
