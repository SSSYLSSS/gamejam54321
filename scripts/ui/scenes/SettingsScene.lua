-- ============================================================================
-- ui/scenes/SettingsScene.lua - 设置界面
-- ============================================================================

local UI = require("urhox-libs/UI")
local Colors = require("ui.Colors")

local SettingsScene = {}

--- 创建音量滑块
local function CreateVolumeSlider(root, id, label, value, onChange)
    return UI.Panel {
        width = "100%",
        gap = 6,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = label,
                        fontSize = 13,
                        fontColor = Colors.text,
                    },
                    UI.Label {
                        id = "volumeVal_" .. id,
                        text = tostring(value) .. "%",
                        fontSize = 13,
                        fontColor = Colors.accent,
                    },
                }
            },
            UI.Slider {
                id = "slider_" .. id,
                width = "100%",
                value = value,
                min = 0,
                max = 100,
                onChange = function(self, val)
                    local rounded = math.floor(val + 0.5)
                    local valLabel = root:FindById("volumeVal_" .. id)
                    if valLabel then
                        valLabel:SetText(tostring(rounded) .. "%")
                    end
                    if onChange then onChange(rounded) end
                end,
            },
        }
    }
end

--- 构建设置 UI
---@param audioSettings table {master, music, sfx}
---@param callbacks table {onAudioChange, onBack}
---@return table root
function SettingsScene.Build(audioSettings, callbacks)
    -- 需要提前声明 root 供 slider onChange 引用
    local root

    local masterSlider = CreateVolumeSlider(nil, "master", "主音量", audioSettings.master, function(val)
        audioSettings.master = val
        if callbacks.onAudioChange then callbacks.onAudioChange() end
    end)
    local musicSlider = CreateVolumeSlider(nil, "music", "音乐", audioSettings.music, function(val)
        audioSettings.music = val
        if callbacks.onAudioChange then callbacks.onAudioChange() end
    end)
    local sfxSlider = CreateVolumeSlider(nil, "sfx", "音效", audioSettings.sfx, function(val)
        audioSettings.sfx = val
        if callbacks.onAudioChange then callbacks.onAudioChange() end
    end)

    root = UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        backgroundColor = Colors.menuBg,
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 360,
                backgroundColor = Colors.menuCard,
                borderRadius = 16,
                borderWidth = 1,
                borderColor = Colors.menuBorder,
                padding = 32,
                gap = 20,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "设置",
                        fontSize = 22,
                        fontColor = Colors.text,
                    },
                    UI.Panel {
                        width = "100%",
                        height = 1,
                        backgroundColor = Colors.menuBorder,
                    },
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 8,
                        children = {
                            UI.Label {
                                text = "音频设置",
                                fontSize = 16,
                                fontColor = Colors.gold,
                            },
                        }
                    },
                    masterSlider,
                    musicSlider,
                    sfxSlider,
                    UI.Panel {
                        width = "100%",
                        height = 1,
                        backgroundColor = Colors.menuBorder,
                        marginTop = 8,
                    },
                    UI.Button {
                        text = "返回主菜单",
                        width = "100%",
                        height = 44,
                        fontSize = 15,
                        borderRadius = 8,
                        onClick = callbacks.onBack,
                    },
                }
            },
        }
    }

    -- 修正 slider onChange 中的 root 引用
    -- 注: 由于闭包捕获, root 赋值后 slider 内的 onChange 也能正确引用

    return root
end

return SettingsScene
