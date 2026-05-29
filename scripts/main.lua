-- ============================================================================
-- main.lua - 游戏入口 (五!四!三!二十一点!)
-- 负责: UI初始化、3D场景(后处理)、VFX系统、场景管理、全局事件分发
-- ============================================================================

require "LuaScripts/Utilities/Sample"

local UI = require("urhox-libs/UI")
local GameController = require("service.GameController")
local MenuScene = require("ui.scenes.MenuScene")
local SettingsScene = require("ui.scenes.SettingsScene")
local GameScene = require("ui.scenes.GameScene")
local VFXManager = require("vfx.VFXManager")
local VFXConfig = require("vfx.VFXConfig")
local CardWidget = require("ui.components.CardWidget")

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

---@type Scene
local scene_ = nil
---@type Node
local cameraNode_ = nil

-- ============================================================================
-- 3D 场景 (仅用于后处理: Vignette暗角)
-- ============================================================================

local function Setup3DScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    -- 相机
    cameraNode_ = scene_:CreateChild("Camera")
    local camera = cameraNode_:CreateComponent("Camera")
    camera.farClip = 100

    -- 加载 LightGroup 提供基础 Zone (不开启 Vignette, 由 NanoVG 层模拟暗角)
    local lightGroupFile = cache:GetResource("XMLFile", "LightGroup/DarkNight.xml")
    local lightGroup = scene_:CreateChild("LightGroup")
    lightGroup:LoadXML(lightGroupFile:GetRoot())

    -- 设置视口
    local viewport = Viewport:new(scene_, camera)
    renderer:SetViewport(0, viewport)
end

-- ============================================================================
-- 场景管理
-- ============================================================================

--- 切换到主菜单
local function ShowMenu()
    currentScene = "menu"
    VFXManager.ClearParticles()

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
    VFXManager.ClearParticles()
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
    -- 1. 初始化 3D 场景 (用于后处理效果)
    Setup3DScene()

    -- 2. 初始化 VFX 系统 (NanoVG 粒子/背景/光晕)
    VFXManager.Init()

    -- 3. 初始化 UI 系统
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 4. 显示主菜单
    ShowMenu()

    -- 5. 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
end

function Stop()
    UI.Shutdown()
    VFXManager.Shutdown()
end

-- ============================================================================
-- 全局事件处理
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    VFXManager.Update(dt)
    CardWidget.UpdateBreathing(dt)
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if key == KEY_ESCAPE then
        if currentScene == "game" then
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
