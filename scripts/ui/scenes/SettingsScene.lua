-- ============================================================================
-- ui/scenes/SettingsScene.lua - 设置界面
-- ============================================================================

local UI = require("urhox-libs/UI")
local Colors = require("ui.Colors")
local SFXManager = require("system.SFXManager")

local SettingsScene = {}

--- 创建音量滑块
---@param getRoot fun():table 延迟获取 root 的函数
local function CreateVolumeSlider(getRoot, id, label, value, onChange)
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
                    local r = getRoot()
                    if r then
                        local valLabel = r:FindById("volumeVal_" .. id)
                        if valLabel then
                            valLabel:SetText(tostring(rounded) .. "%")
                        end
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
    -- 提前声明 root, 通过闭包延迟引用
    local root
    local function getRoot() return root end

    local masterSlider = CreateVolumeSlider(getRoot, "master", "主音量", audioSettings.master, function(val)
        audioSettings.master = val
        if callbacks.onAudioChange then callbacks.onAudioChange() end
    end)
    local musicSlider = CreateVolumeSlider(getRoot, "music", "音乐", audioSettings.music, function(val)
        audioSettings.music = val
        if callbacks.onAudioChange then callbacks.onAudioChange() end
    end)
    local sfxSlider = CreateVolumeSlider(getRoot, "sfx", "音效", audioSettings.sfx, function(val)
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

    return root
end

return SettingsScene
