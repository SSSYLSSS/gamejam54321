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
local TutorialScene = require("ui.scenes.TutorialScene")
local AISystem = require("system.AISystem")
local StatsSystem = require("system.StatsSystem")
local SaveSystem = require("system.SaveSystem")
local MatchHistory = require("system.MatchHistory")
local ReplayScene = require("ui.scenes.ReplayScene")
local BGMManager = require("system.BGMManager")
local SFXManager = require("system.SFXManager")
local GameState = require("model.GameState")
local PlayerState = require("model.PlayerState")
local RoundState = require("model.RoundState")

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

--- 保存当前游戏进度
local function SaveCurrentGame()
    local gs = GameController.GetState()
    if gs and not gs:IsGameOver() then
        SaveSystem.Save(gs, AISystem.GetDifficulty())
    end
end

--- 切换到主菜单
local function ShowMenu()
    currentScene = "menu"
    VFXManager.ClearParticles()
    BGMManager.Play("menu")

    local root = MenuScene.Build({
        hasSave = SaveSystem.HasSave(),
        onContinue = function()
            ShowGame(true)  -- 从存档恢复
        end,
        onStart = function()
            SaveSystem.Delete()  -- 新游戏时删除旧存档
            ShowDifficultySelect()
        end,
        onMultiplayer = function()
            ShowMultiplayer()
        end,
        onReplay = function()
            ShowReplay()
        end,
        onTutorial = function()
            ShowTutorial()
        end,
        onStats = function()
            ShowStats()
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

--- 切换到难度选择
function ShowDifficultySelect()
    currentScene = "difficulty"
    VFXManager.ClearParticles()

    local root = MenuScene.BuildDifficultySelect({
        onSelect = function(difficulty)
            AISystem.SetDifficulty(difficulty)
            ShowGame()
        end,
        onBack = function()
            ShowMenu()
        end,
    })
    UI.SetRoot(root)
end

--- 切换到游戏
---@param fromSave boolean|nil 是否从存档恢复
function ShowGame(fromSave)
    currentScene = "game"
    VFXManager.ClearParticles()
    BGMManager.Play("game")

    if fromSave then
        -- 从存档恢复
        local saveData = SaveSystem.Load()
        if saveData then
            local gs = SaveSystem.RestoreGameState(saveData, GameState, PlayerState, RoundState)
            if gs then
                GameController.RestoreGame(gs)
                AISystem.SetDifficulty(saveData.difficulty or "normal")
                SaveSystem.Delete()
            else
                GameController.NewGame()
            end
        else
            GameController.NewGame()
        end
    else
        GameController.NewGame()
    end

    GameScene.SetCallbacks({
        onBackToMenu = function()
            SaveCurrentGame()
            ShowMenu()
        end,
        onLastRound = function()
            BGMManager.Play("lastRound")
        end,
    })

    local root = GameScene.Build()
    UI.SetRoot(root)

    -- 初始提示
    local phase = GameController.GetPhase()
    local Constant = require("core.Constant")
    if phase == Constant.PHASE.GAME_OVER then
        GameScene.SetInfo("游戏已结束")
    elseif phase == Constant.PHASE.POST_DISCARD then
        GameScene.SetInfo("选择至多2张牌放回你的抽牌堆")
    elseif phase == Constant.PHASE.POST_KEEP then
        GameScene.SetInfo("选择至多1张牌保留至下一局")
    else
        GameScene.SetInfo(string.format("选择要弃置的牌（至多%d张），或跳过",
            GameController.GetMaxDiscard()))
    end
    GameScene.Refresh()
end

--- 切换到多人游戏
function ShowMultiplayer()
    currentScene = "multiplayer"

    -- 检查是否有可用的服务器连接 (background_match 模式)
    local hasConnection = false
    if network and network.GetServerConnection then
        local conn = network:GetServerConnection()
        if conn then hasConnection = true end
    end

    if hasConnection then
        -- 已匹配成功，直接进入多人游戏
        StartMultiplayerGame()
    else
        -- 显示匹配等待界面
        local root = MenuScene.BuildMultiplayerWaiting(function()
            CancelMultiplayer()
        end)
        UI.SetRoot(root)

        -- 订阅 ServerReady 事件
        SubscribeToEvent("ServerReady", "HandleServerReady")
    end
end

--- 取消多人匹配，返回主菜单
function CancelMultiplayer()
    UnsubscribeFromEvent("ServerReady")
    ShowMenu()
end

--- ServerReady 事件处理: 匹配成功
function HandleServerReady(eventType, eventData)
    if currentScene == "multiplayer" then
        StartMultiplayerGame()
    end
end

--- 启动多人游戏客户端
function StartMultiplayerGame()
    local Client = require("network.Client")
    Client.Start()
    currentScene = "multiplayer_game"
end

--- 切换到对局回放
function ShowReplay()
    currentScene = "replay"
    VFXManager.ClearParticles()
    local root = ReplayScene.BuildList(function()
        ShowMenu()
    end)
    UI.SetRoot(root)
end

--- 切换到统计页面
function ShowStats()
    currentScene = "stats"
    VFXManager.ClearParticles()
    local root = MenuScene.BuildStats(function()
        ShowMenu()
    end)
    UI.SetRoot(root)
end

--- 切换到教程页面
function ShowTutorial()
    currentScene = "tutorial"
    VFXManager.ClearParticles()
    local root = TutorialScene.Build(function()
        ShowMenu()
    end)
    UI.SetRoot(root)
end

--- 切换到设置
function ShowSettings()
    currentScene = "settings"
    local root = SettingsScene.Build(audioSettings, {
        onAudioChange = function()
            audio:SetMasterGain(SOUND_MASTER, audioSettings.master / 100)
            audio:SetMasterGain(SOUND_MUSIC, audioSettings.music / 100)
            audio:SetMasterGain(SOUND_EFFECT, audioSettings.sfx / 100)
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

    -- 4. 加载统计数据
    StatsSystem.Load()

    -- 5. 加载对局历史
    MatchHistory.Load()

    -- 6. 初始化音频系统
    audio:SetMasterGain(SOUND_MASTER, audioSettings.master / 100)
    audio:SetMasterGain(SOUND_MUSIC, audioSettings.music / 100)
    audio:SetMasterGain(SOUND_EFFECT, audioSettings.sfx / 100)
    BGMManager.Init(scene_)
    SFXManager.Init(scene_)

    -- 7. 显示主菜单
    ShowMenu()

    -- 8. 订阅事件
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
    BGMManager.Update(dt)
    CardWidget.UpdateBreathing(dt)
    if currentScene == "game" then
        GameScene.Update(dt)
    end
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
        elseif currentScene == "multiplayer" then
            CancelMultiplayer()
        elseif currentScene == "settings" or currentScene == "difficulty" or currentScene == "stats" or currentScene == "tutorial" or currentScene == "replay" then
            ShowMenu()
        else
            engine:Exit()
        end
    end
end
