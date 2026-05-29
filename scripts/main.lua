-- ============================================================================
-- main.lua - 游戏入口 (五!四!三!二十一点!)
-- 负责: UI初始化、场景管理、全局事件分发
-- ============================================================================

require "LuaScripts/Utilities/Sample"

local UI = require("urhox-libs/UI")
local GameController = require("service.GameController")
local MenuScene = require("ui.scenes.MenuScene")
local SettingsScene = require("ui.scenes.SettingsScene")
local GameScene = require("ui.scenes.GameScene")

-- ============================================================================
-- 全局状态
-- ============================================================================

---@type string "menu"|"game"|"settings"|"multiplayer"
local currentScene = "menu"

local audioSettings = {
    master = 80,
    music = 60,
    sfx = 80,
}

-- ============================================================================
-- 场景管理
-- ============================================================================

--- 切换到主菜单
local function ShowMenu()
    currentScene = "menu"
    local root = MenuScene.Build({
        onStart = function()
            ShowGame()
        end,
        onMultiplayer = function()
            ShowMultiplayer()
        end,
        onSettings = function()
            ShowSettings()
        end,
        onExit = function()
            engine:Exit()
        end,
    })
    UI.SetRoot(root)
end

--- 切换到游戏
function ShowGame()
    currentScene = "game"
    GameController.NewGame()

    GameScene.SetCallbacks({
        onBackToMenu = function()
            ShowMenu()
        end,
    })

    local root = GameScene.Build()
    UI.SetRoot(root)

    -- 初始提示
    GameScene.SetInfo(string.format("选择要弃置的牌（至多%d张），或跳过",
        GameController.GetMaxDiscard()))
    GameScene.Refresh()
end

--- 切换到多人游戏提示
function ShowMultiplayer()
    currentScene = "multiplayer"
    local root = MenuScene.BuildMultiplayerNotice(function()
        ShowMenu()
    end)
    UI.SetRoot(root)
end

--- 切换到设置
function ShowSettings()
    currentScene = "settings"
    local root = SettingsScene.Build(audioSettings, {
        onAudioChange = function()
            -- 未来: 应用音量到引擎
        end,
        onBack = function()
            ShowMenu()
        end,
    })
    UI.SetRoot(root)
end

-- ============================================================================
-- 引擎生命周期
-- ============================================================================

function Start()
    -- 初始化 UI 系统
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 显示主菜单
    ShowMenu()

    -- 订阅事件
    SubscribeToEvent("KeyDown", "HandleKeyDown")
end

function Stop()
    UI.Shutdown()
end

-- ============================================================================
-- 全局事件处理
-- ============================================================================

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if key == KEY_ESCAPE then
        if currentScene == "game" then
            -- 先让 GameScene 处理(关闭弹窗等)
            if not GameScene.HandleEscape() then
                ShowMenu()
            end
        elseif currentScene == "settings" or currentScene == "multiplayer" then
            ShowMenu()
        else
            engine:Exit()
        end
    end
end
