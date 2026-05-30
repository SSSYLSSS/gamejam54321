-- ============================================================================
-- network/Client.lua - 多人游戏客户端
-- 负责: UI渲染、玩家输入、与服务器通信
-- ============================================================================

local UI = require("urhox-libs/UI")
local Shared = require("network.Shared")
local Constant = require("core.Constant")
local GameConfig = require("core.GameConfig")
local Card = require("core.Card")
local Colors = require("ui.Colors")
local CardWidget = require("ui.components.CardWidget")
local VFXManager = require("vfx.VFXManager")
local SFXManager = require("system.SFXManager")

local Client = {}

-- ============================================================================
-- 客户端状态
-- ============================================================================

---@type Scene
local scene_ = nil
---@type Node
local cameraNode_ = nil
local serverConnection_ = nil

local myPlayerId_ = 0
local myHand_ = {}
local selectedIndices_ = {}
local opponentHandSize_ = 0

local roundNumber_ = 0
local turnIndex_ = 0
local maxDiscard_ = 0
local p1Wins_ = 0
local p2Wins_ = 0

local phase_ = "connecting"  -- connecting, waiting_opponent, turn, waiting_resolve, settlement, post_discard, post_keep, round_end, game_over, disconnected
local infoText_ = "连接中..."

---@type table|nil
local uiRoot_ = nil

-- ============================================================================
-- UI 构建
-- ============================================================================

local function GetMyWins()
    return myPlayerId_ == 1 and p1Wins_ or p2Wins_
end

local function GetOppWins()
    return myPlayerId_ == 1 and p2Wins_ or p1Wins_
end

--- 刷新整个UI
local function RefreshUI()
    if not uiRoot_ then return end

    local children = {}

    -- 顶部信息栏
    table.insert(children, UI.Panel {
        width = "100%", height = 40,
        flexDirection = "row", justifyContent = "space-between", alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = { 20, 28, 45, 220 },
        children = {
            UI.Label {
                text = string.format("第%d局", roundNumber_),
                fontSize = 12, fontColor = Colors.textDim,
            },
            UI.Label {
                text = string.format("玩家%d", myPlayerId_),
                fontSize = 12, fontColor = Colors.gold,
            },
            UI.Label {
                text = string.format("比分 %d : %d", GetMyWins(), GetOppWins()),
                fontSize = 13, fontColor = Colors.text,
            },
        }
    })

    -- 对手信息
    table.insert(children, UI.Panel {
        width = "100%", height = 36,
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 30, 20, 20, 120 },
        children = {
            UI.Label {
                text = string.format("对手手牌: %d 张", opponentHandSize_),
                fontSize = 12, fontColor = { 255, 140, 80, 200 },
            },
        }
    })

    -- 提示信息
    table.insert(children, UI.Panel {
        width = "100%", height = 32,
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Label {
                id = "infoLabel",
                text = infoText_,
                fontSize = 13, fontColor = Colors.accent,
                textAlign = "center",
            },
        }
    })

    -- 手牌区域
    local cardChildren = {}
    for i, card in ipairs(myHand_) do
        local isSelected = false
        for _, idx in ipairs(selectedIndices_) do
            if idx == i then isSelected = true; break end
        end
        local cardNode = CardWidget.Create(card, {
            selected = isSelected,
            index = i,
            onClick = function()
                if phase_ == "turn" or phase_ == "post_discard" then
                    ToggleCardSelection(i)
                elseif phase_ == "post_keep" then
                    SelectKeepCard(i)
                end
            end,
        })
        table.insert(cardChildren, cardNode)
    end

    table.insert(children, UI.Panel {
        width = "100%", flex = 1,
        flexDirection = "row", flexWrap = "wrap",
        justifyContent = "center", alignItems = "center",
        gap = 6, paddingTop = 8, paddingBottom = 8,
        children = cardChildren,
    })

    -- 操作按钮区域
    local buttons = {}
    if phase_ == "turn" then
        table.insert(buttons, UI.Button {
            text = string.format("弃牌 (%d/%d)", #selectedIndices_, maxDiscard_),
            width = 130, height = 38, fontSize = 13,
            variant = "primary",
            disabled = #selectedIndices_ == 0,
            onPointerEnter = function() SFXManager.Play("buttonFocus") end,
            onClick = function() SFXManager.Play("buttonPress"); SendDiscard() end,
        })
        table.insert(buttons, UI.Button {
            text = "跳过",
            width = 80, height = 38, fontSize = 13,
            fontColor = Colors.textDim,
            onPointerEnter = function() SFXManager.Play("buttonFocus") end,
            onClick = function() SFXManager.Play("buttonPress"); SendSkip() end,
        })
    elseif phase_ == "post_discard" then
        table.insert(buttons, UI.Button {
            text = string.format("放回牌堆 (%d/%d)", #selectedIndices_, GameConfig.POST_DISCARD_MAX),
            width = 160, height = 38, fontSize = 13,
            variant = "primary",
            onPointerEnter = function() SFXManager.Play("buttonFocus") end,
            onClick = function() SFXManager.Play("buttonPress"); SendPostDiscard() end,
        })
        table.insert(buttons, UI.Button {
            text = "跳过",
            width = 80, height = 38, fontSize = 13,
            fontColor = Colors.textDim,
            onPointerEnter = function() SFXManager.Play("buttonFocus") end,
            onClick = function() SFXManager.Play("buttonPress"); SendPostDiscard(true) end,
        })
    elseif phase_ == "post_keep" then
        table.insert(buttons, UI.Button {
            text = "不保留，跳过",
            width = 140, height = 38, fontSize = 13,
            fontColor = Colors.textDim,
            onPointerEnter = function() SFXManager.Play("buttonFocus") end,
            onClick = function() SFXManager.Play("buttonPress"); SendPostKeep(nil) end,
        })
    elseif phase_ == "round_end" then
        table.insert(buttons, UI.Button {
            text = "继续下一局",
            width = 130, height = 38, fontSize = 13,
            variant = "primary",
            onPointerEnter = function() SFXManager.Play("buttonFocus") end,
            onClick = function() SFXManager.Play("buttonPress"); SendContinue() end,
        })
    elseif phase_ == "game_over" then
        local winnerText = ""
        if (myPlayerId_ == 1 and p1Wins_ >= GameConfig.WINS_NEEDED) or
           (myPlayerId_ == 2 and p2Wins_ >= GameConfig.WINS_NEEDED) then
            winnerText = "你赢了!"
        else
            winnerText = "你输了"
        end
        table.insert(buttons, UI.Label {
            text = winnerText,
            fontSize = 20, fontColor = Colors.gold,
        })
    end

    table.insert(children, UI.Panel {
        width = "100%", height = 56,
        flexDirection = "row", justifyContent = "center", alignItems = "center",
        gap = 12,
        children = buttons,
    })

    -- 重建UI
    uiRoot_:ClearChildren()
    for _, child in ipairs(children) do
        uiRoot_:AddChild(child)
    end
end

-- ============================================================================
-- 玩家操作
-- ============================================================================

function ToggleCardSelection(index)
    -- 检查是否已选中
    for i, idx in ipairs(selectedIndices_) do
        if idx == index then
            table.remove(selectedIndices_, i)
            RefreshUI()
            return
        end
    end

    -- 添加选中(检查上限)
    local maxSel = 0
    if phase_ == "turn" then
        maxSel = maxDiscard_
    elseif phase_ == "post_discard" then
        maxSel = GameConfig.POST_DISCARD_MAX
    end

    if #selectedIndices_ < maxSel then
        table.insert(selectedIndices_, index)
    end
    RefreshUI()
end

function SelectKeepCard(index)
    -- 保留阶段:选一张直接发送
    SendPostKeep(index)
end

function SendDiscard()
    if #selectedIndices_ == 0 then return end
    local data = VariantMap()
    Shared.EncodeIndices(data, "Idx", selectedIndices_)
    serverConnection_:SendRemoteEvent(Shared.EVENTS.PLAYER_DISCARD, true, data)

    phase_ = "waiting_resolve"
    infoText_ = "等待对手操作..."
    selectedIndices_ = {}
    RefreshUI()
end

function SendSkip()
    serverConnection_:SendRemoteEvent(Shared.EVENTS.PLAYER_SKIP, true, VariantMap())
    phase_ = "waiting_resolve"
    infoText_ = "等待对手操作..."
    selectedIndices_ = {}
    RefreshUI()
end

function SendPostDiscard(skip)
    local data = VariantMap()
    if skip then
        Shared.EncodeIndices(data, "Idx", {})
    else
        Shared.EncodeIndices(data, "Idx", selectedIndices_)
    end
    serverConnection_:SendRemoteEvent(Shared.EVENTS.PLAYER_POST_DISCARD, true, data)

    phase_ = "waiting_resolve"
    infoText_ = "等待对手操作..."
    selectedIndices_ = {}
    RefreshUI()
end

function SendPostKeep(keepIndex)
    local data = VariantMap()
    data["KeepIndex"] = Variant(keepIndex or 0)
    serverConnection_:SendRemoteEvent(Shared.EVENTS.PLAYER_POST_KEEP, true, data)

    phase_ = "waiting_resolve"
    infoText_ = "等待对手操作..."
    selectedIndices_ = {}
    RefreshUI()
end

function SendContinue()
    serverConnection_:SendRemoteEvent(Shared.EVENTS.PLAYER_CONTINUE, true, VariantMap())
    phase_ = "waiting_resolve"
    infoText_ = "等待对手准备..."
    RefreshUI()
end

-- ============================================================================
-- 服务器事件处理
-- ============================================================================

local function OnAssignPlayer(eventType, eventData)
    myPlayerId_ = eventData["PlayerId"]:GetInt()
    phase_ = "waiting_opponent"
    infoText_ = string.format("你是玩家 %d，等待对手加入...", myPlayerId_)
    print(string.format("[Client] Assigned as Player %d", myPlayerId_))
    RefreshUI()
end

local function OnRoundStart(eventType, eventData)
    roundNumber_ = eventData["RoundNumber"]:GetInt()
    p1Wins_ = eventData["P1Wins"]:GetInt()
    p2Wins_ = eventData["P2Wins"]:GetInt()
    opponentHandSize_ = eventData["OpponentHandSize"]:GetInt()
    myHand_ = Shared.DecodeHand(eventData, "Hand")
    selectedIndices_ = {}

    infoText_ = string.format("第 %d 局开始!", roundNumber_)
    print(string.format("[Client] Round %d started, hand size: %d", roundNumber_, #myHand_))
    RefreshUI()
end

local function OnTurnStart(eventType, eventData)
    turnIndex_ = eventData["TurnIndex"]:GetInt()
    maxDiscard_ = eventData["MaxDiscard"]:GetInt()
    selectedIndices_ = {}
    phase_ = "turn"

    local turnNames = { "五!", "四!", "三!" }
    infoText_ = string.format("%s 选择至多%d张牌弃置", turnNames[turnIndex_] or "", maxDiscard_)
    RefreshUI()
end

local function OnWaitOpponent(eventType, eventData)
    -- 对手还没提交，我已提交
    infoText_ = "等待对手操作..."
    RefreshUI()
end

local function OnTurnResult(eventType, eventData)
    myHand_ = Shared.DecodeHand(eventData, "Hand")
    local oppDiscardCount = eventData["OppDiscardCount"]:GetInt()
    opponentHandSize_ = eventData["OppHandSize"]:GetInt()
    selectedIndices_ = {}

    infoText_ = string.format("对手弃置了%d张牌", oppDiscardCount)
    RefreshUI()
end

local function OnSettlementResult(eventType, eventData)
    local p1Hand = Shared.DecodeHand(eventData, "P1Hand")
    local p2Hand = Shared.DecodeHand(eventData, "P2Hand")
    local p1Points = eventData["P1Points"]:GetInt()
    local p2Points = eventData["P2Points"]:GetInt()
    local winnerId = eventData["Winner"]:GetInt()
    local sevenRule = eventData["SevenRule"]:GetInt() == 1
    p1Wins_ = eventData["P1Wins"]:GetInt()
    p2Wins_ = eventData["P2Wins"]:GetInt()

    phase_ = "settlement"

    local myPoints = myPlayerId_ == 1 and p1Points or p2Points
    local oppPoints = myPlayerId_ == 1 and p2Points or p1Points

    if sevenRule then
        infoText_ = "三7特殊规则触发!"
    else
        local resultStr = ""
        if winnerId == myPlayerId_ then
            resultStr = "你赢了本局!"
        elseif winnerId == 0 then
            resultStr = "平局!"
        else
            resultStr = "你输了本局"
        end
        infoText_ = string.format("结算: 你 %d点 vs 对手 %d点 - %s", myPoints, oppPoints, resultStr)
    end

    -- 显示对手手牌
    local oppHand = myPlayerId_ == 1 and p2Hand or p1Hand
    opponentHandSize_ = #oppHand

    RefreshUI()
end

local function OnPostPhaseStart(eventType, eventData)
    local phaseName = eventData["Phase"]:GetString()
    myHand_ = Shared.DecodeHand(eventData, "Hand")
    selectedIndices_ = {}

    if phaseName == "post_discard" then
        phase_ = "post_discard"
        infoText_ = string.format("二! 选择至多%d张牌放回抽牌堆", GameConfig.POST_DISCARD_MAX)
    elseif phaseName == "post_keep" then
        phase_ = "post_keep"
        infoText_ = "一! 选择1张牌保留至下局 (点击卡牌选择)"
    end
    RefreshUI()
end

local function OnRoundEnd(eventType, eventData)
    roundNumber_ = eventData["RoundNumber"]:GetInt()
    p1Wins_ = eventData["P1Wins"]:GetInt()
    p2Wins_ = eventData["P2Wins"]:GetInt()
    phase_ = "round_end"
    infoText_ = string.format("本局结束! 比分 %d : %d", GetMyWins(), GetOppWins())
    RefreshUI()
end

local function OnGameOver(eventType, eventData)
    local winnerId = eventData["Winner"]:GetInt()
    p1Wins_ = eventData["P1Wins"]:GetInt()
    p2Wins_ = eventData["P2Wins"]:GetInt()
    phase_ = "game_over"

    if winnerId == myPlayerId_ then
        infoText_ = "恭喜你赢得了比赛!"
    else
        infoText_ = "很遗憾，你输了"
    end
    RefreshUI()
end

local function OnOpponentDisconnected(eventType, eventData)
    phase_ = "disconnected"
    infoText_ = "对手已断开连接"
    RefreshUI()
end

-- ============================================================================
-- 生命周期
-- ============================================================================

function Client.Start()
    print("[Client] Starting multiplayer client...")

    -- 创建 Scene (网络同步必需)
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    -- 相机 (用于viewport, 实际不渲染3D内容)
    cameraNode_ = scene_:CreateChild("Camera", LOCAL)
    local camera = cameraNode_:CreateComponent("Camera", LOCAL)
    camera.farClip = 100
    local viewport = Viewport:new(scene_, camera)
    renderer:SetViewport(0, viewport)

    -- 初始化 VFX
    VFXManager.Init()

    -- 初始化 UI
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 创建根 UI 容器
    uiRoot_ = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        backgroundColor = { 15, 20, 35, 255 },
        children = {
            UI.Label { text = "连接服务器中...", fontSize = 16, fontColor = Colors.text },
        }
    }
    UI.SetRoot(uiRoot_)

    -- 注册接收的远程事件
    network:RegisterRemoteEvent(Shared.EVENTS.ASSIGN_PLAYER)
    network:RegisterRemoteEvent(Shared.EVENTS.ROUND_START)
    network:RegisterRemoteEvent(Shared.EVENTS.TURN_START)
    network:RegisterRemoteEvent(Shared.EVENTS.WAIT_OPPONENT)
    network:RegisterRemoteEvent(Shared.EVENTS.TURN_RESULT)
    network:RegisterRemoteEvent(Shared.EVENTS.SETTLEMENT_RESULT)
    network:RegisterRemoteEvent(Shared.EVENTS.POST_PHASE_START)
    network:RegisterRemoteEvent(Shared.EVENTS.ROUND_END)
    network:RegisterRemoteEvent(Shared.EVENTS.GAME_OVER)
    network:RegisterRemoteEvent(Shared.EVENTS.OPPONENT_DISCONNECTED)

    -- 订阅事件
    SubscribeToEvent(Shared.EVENTS.ASSIGN_PLAYER, "OnAssignPlayerGlobal")
    SubscribeToEvent(Shared.EVENTS.ROUND_START, "OnRoundStartGlobal")
    SubscribeToEvent(Shared.EVENTS.TURN_START, "OnTurnStartGlobal")
    SubscribeToEvent(Shared.EVENTS.WAIT_OPPONENT, "OnWaitOpponentGlobal")
    SubscribeToEvent(Shared.EVENTS.TURN_RESULT, "OnTurnResultGlobal")
    SubscribeToEvent(Shared.EVENTS.SETTLEMENT_RESULT, "OnSettlementResultGlobal")
    SubscribeToEvent(Shared.EVENTS.POST_PHASE_START, "OnPostPhaseStartGlobal")
    SubscribeToEvent(Shared.EVENTS.ROUND_END, "OnRoundEndGlobal")
    SubscribeToEvent(Shared.EVENTS.GAME_OVER, "OnGameOverGlobal")
    SubscribeToEvent(Shared.EVENTS.OPPONENT_DISCONNECTED, "OnOpponentDisconnectedGlobal")

    -- 连接服务器
    serverConnection_ = network:GetServerConnection()
    if serverConnection_ then
        serverConnection_.scene = scene_
        -- 发送 ClientReady
        serverConnection_:SendRemoteEvent(Shared.EVENTS.CLIENT_READY, true, VariantMap())
        infoText_ = "已连接，等待对手加入..."
        print("[Client] Connected, sent ClientReady")
    else
        -- 可能是 background_match 模式
        SubscribeToEvent("ServerReady", "HandleServerReadyGlobal")
        infoText_ = "等待服务器..."
        print("[Client] No server connection yet, waiting for ServerReady")
    end

    SubscribeToEvent("Update", "HandleUpdateGlobal")
    SubscribeToEvent("KeyDown", "HandleKeyDownGlobal")
end

function Client.Stop()
    UI.Shutdown()
    VFXManager.Shutdown()
end

-- ============================================================================
-- 全局事件转发
-- ============================================================================

function HandleServerReadyGlobal(eventType, eventData)
    serverConnection_ = network:GetServerConnection()
    if serverConnection_ then
        serverConnection_.scene = scene_
        serverConnection_:SendRemoteEvent(Shared.EVENTS.CLIENT_READY, true, VariantMap())
        infoText_ = "已连接，等待对手加入..."
        print("[Client] ServerReady received, sent ClientReady")
        RefreshUI()
    end
end

function OnAssignPlayerGlobal(eventType, eventData) OnAssignPlayer(eventType, eventData) end
function OnRoundStartGlobal(eventType, eventData) OnRoundStart(eventType, eventData) end
function OnTurnStartGlobal(eventType, eventData) OnTurnStart(eventType, eventData) end
function OnWaitOpponentGlobal(eventType, eventData) OnWaitOpponent(eventType, eventData) end
function OnTurnResultGlobal(eventType, eventData) OnTurnResult(eventType, eventData) end
function OnSettlementResultGlobal(eventType, eventData) OnSettlementResult(eventType, eventData) end
function OnPostPhaseStartGlobal(eventType, eventData) OnPostPhaseStart(eventType, eventData) end
function OnRoundEndGlobal(eventType, eventData) OnRoundEnd(eventType, eventData) end
function OnGameOverGlobal(eventType, eventData) OnGameOver(eventType, eventData) end
function OnOpponentDisconnectedGlobal(eventType, eventData) OnOpponentDisconnected(eventType, eventData) end

function HandleUpdateGlobal(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    VFXManager.Update(dt)
    CardWidget.UpdateBreathing(dt)
end

function HandleKeyDownGlobal(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_ESCAPE then
        -- 多人游戏中按ESC不做特殊处理
    end
end

return Client
