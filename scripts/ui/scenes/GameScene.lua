-- ============================================================================
-- ui/scenes/GameScene.lua - 游戏主界面
-- ============================================================================

local UI = require("urhox-libs/UI")
local Colors = require("ui.Colors")
local Card = require("core.Card")
local Constant = require("core.Constant")
local GameConfig = require("core.GameConfig")
local CardWidget = require("ui.components.CardWidget")
local GameController = require("service.GameController")
local AISystem = require("system.AISystem")
local StatsSystem = require("system.StatsSystem")
local SaveSystem = require("system.SaveSystem")
local VFXManager = require("vfx.VFXManager")
local SFXManager = require("system.SFXManager")
local BGMManager = require("system.BGMManager")
local GameLogViewer = require("ui.components.GameLogViewer")
local MatchHistory = require("system.MatchHistory")

local GameScene = {}

-- 本地状态
local selectedCards = {}     -- 选中的牌索引集合
local uiRoot = nil           -- 当前 UI 根节点
local viewingPile = nil      -- 正在查看的牌堆

-- 手牌组件追踪(用于显式清理，避免 Tooltip 脱离 bug)
local playerHandWidgets = {}
local aiHandWidgets = {}

-- 结算翻牌动画状态
local settlementAnim = nil   -- nil=无动画, table=动画进行中

-- 局间过渡动画状态
local transitionAnim = nil   -- nil=无动画, {text, timer, duration, phase}

-- 统计记录防重复
local gameStatsRecorded = false

-- 回调(由 UIManager 设置)
local sceneCallbacks = {}

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 设置回调
---@param callbacks table {onBackToMenu}
function GameScene.SetCallbacks(callbacks)
    sceneCallbacks = callbacks or {}
end

--- 构建游戏 UI
---@return table root
function GameScene.Build()
    selectedCards = {}
    viewingPile = nil
    gameStatsRecorded = false

    uiRoot = UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        backgroundColor = Colors.bg,
        children = {
            GameScene._CreateTopBar(),
            UI.Panel {
                id = "gameArea",
                flexGrow = 1,
                flexBasis = 0,
                width = "100%",
                flexDirection = "row",
                children = {
                    -- 左侧: 抽牌堆（叠牌样式）
                    GameScene._CreateDeckPile(),
                    -- 中间: 主游戏区
                    UI.Panel {
                        id = "centerColumn",
                        flexGrow = 1,
                        flexBasis = 0,
                        padding = 16,
                        gap = 12,
                        justifyContent = "space-between",
                        children = {
                            GameScene._CreateAIArea(),
                            GameScene._CreateMiddleArea(),
                            GameScene._CreatePlayerArea(),
                        }
                    },
                    -- 右侧: 弃牌堆（叠牌样式）
                    GameScene._CreateDiscardPile(),
                }
            },
            GameScene._CreateBottomBar(),
        }
    }

    return uiRoot
end

--- 刷新整个游戏界面
function GameScene.Refresh()
    if not uiRoot then return end
    CardWidget.ClearBreathingList()
    GameScene._RefreshScore()
    GameScene._RefreshPhaseLabel()
    GameScene._RefreshPlayerHand()
    GameScene._RefreshAIHand()
    GameScene._RefreshPlayerPoints()
    GameScene._RefreshButtons()
    GameScene._RefreshPileCounts()
end

--- 更新信息标签
---@param text string
function GameScene.SetInfo(text)
    if not uiRoot then return end
    local infoLabel = uiRoot:FindById("infoLabel")
    if infoLabel then
        infoLabel:SetText(text)
    end
end

--- 获取 UI 根节点
---@return table|nil
function GameScene.GetRoot()
    return uiRoot
end

--- 重置选牌状态
function GameScene.ClearSelection()
    selectedCards = {}
end

--- 每帧更新 (驱动结算翻牌动画 + 局间过渡动画)
---@param dt number
function GameScene.Update(dt)
    -- 局间过渡动画
    if transitionAnim then
        transitionAnim.timer = transitionAnim.timer + dt
        local t = transitionAnim.timer
        local dur = transitionAnim.duration

        if t >= dur then
            -- 动画结束，移除覆盖层并进入新回合
            GameScene._EndTransition()
        else
            -- 更新覆盖层透明度动画
            GameScene._UpdateTransitionOverlay()
        end
        return  -- 过渡期间不处理其他动画
    end

    -- 结算翻牌动画
    if not settlementAnim then return end
    local anim = settlementAnim
    anim.timer = anim.timer + dt
    if anim.revealedCount < #anim.aiHand then
        -- 逐张翻牌阶段
        if anim.timer >= anim.interval then
            anim.timer = 0
            anim.revealedCount = anim.revealedCount + 1
            -- 播放倒计时翻牌音效 (5!→4!→3!→2!→1!)
            local remaining = #anim.aiHand - anim.revealedCount + 1
            if remaining >= 1 and remaining <= 5 then
                SFXManager.PlayCardFlipCountdown(remaining)
            else
                SFXManager.Play("flipCard")
            end

            GameScene._UpdateSettlementOverlay()
        end
    else
        -- 全部翻完后延迟2秒，同时显示结算弹窗和播放胜负音效
        if anim.winLoseTimer and anim.winLoseTimer > 0 then
            anim.winLoseTimer = anim.winLoseTimer - dt
            if anim.winLoseTimer <= 0 then
                anim.winLoseTimer = 0
                -- 同时触发: 弹窗 + 音效
                if not anim.showedContinue then
                    anim.showedContinue = true
                    GameScene._ShowSettlementContinueBtn()
                end
                if anim.result.winner == "player" then
                    SFXManager.Play("win")
                elseif anim.result.winner == "ai" then
                    SFXManager.Play("lose")
                end
            end
        end
    end
end

--- 处理 ESC 键
---@return boolean handled
function GameScene.HandleEscape()
    -- 日志弹窗
    if uiRoot then
        local logOverlay = uiRoot:FindById("gameLogOverlay")
        if logOverlay then
            GameScene._CloseGameLog()
            return true
        end
    end
    if viewingPile then
        GameScene._ClosePileView()
        return true
    end

    return false
end

-- ============================================================================
-- 内部: 构建子区域
-- ============================================================================

function GameScene._CreateTopBar()
    return UI.Panel {
        id = "topBar",
        width = "100%",
        height = 50,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingHorizontal = 20,
        backgroundColor = Colors.panel,
        borderColor = Colors.topBorder,
        borderWidth = { 0, 0, 1, 0 },
        children = {
            UI.Panel {
                flexDirection = "row",
                gap = 12,
                alignItems = "center",
                children = {
                    UI.Button {
                        text = "< 菜单",
                        fontSize = 12,
                        height = 30,
                        onPointerEnter = function() SFXManager.Play("buttonFocus") end,
                        onClick = function()
                            if sceneCallbacks.onBackToMenu then
                                sceneCallbacks.onBackToMenu()
                            end
                        end,
                    },
                    UI.Label {
                        id = "titleLabel",
                        text = "五!四!三!二十一点!",
                        fontSize = 16,
                        fontColor = Colors.gold,
                    },
                },
            },
            UI.Panel {
                flexDirection = "row",
                gap = 12,
                alignItems = "center",
                children = {
                    UI.Label {
                        id = "scoreLabel",
                        text = "比分: 0 - 0",
                        fontSize = 14,
                        fontColor = Colors.text,
                    },
                    UI.Label {
                        id = "roundLabel",
                        text = "第 0 局",
                        fontSize = 14,
                        fontColor = Colors.textDim,
                    },
                }
            },
        }
    }
end

--- 创建一个叠牌堆视觉组件
---@param id string
---@param bgColors table {layer1, layer2, top}
---@param borderColors table {layer1, layer2, top}
---@param iconText string
---@param iconColor table
---@param onClick function
local function createStackVisual(id, bgColors, borderColors, iconText, iconColor, onClick)
    return UI.Panel {
        width = 52,
        height = 72,
        children = {
            UI.Panel {
                width = 46, height = 64,
                position = "absolute", top = 5, left = 5,
                backgroundColor = bgColors[1],
                borderRadius = 5, borderWidth = 1, borderColor = borderColors[1],
            },
            UI.Panel {
                width = 46, height = 64,
                position = "absolute", top = 2, left = 2,
                backgroundColor = bgColors[2],
                borderRadius = 5, borderWidth = 1, borderColor = borderColors[2],
            },
            UI.Button {
                id = id,
                width = 46, height = 64,
                position = "absolute", top = 0, left = 0,
                backgroundColor = bgColors[3],
                hoverBackgroundColor = bgColors[4] or bgColors[3],
                borderRadius = 5, borderWidth = 1, borderColor = borderColors[3],
                justifyContent = "center", alignItems = "center",
                onPointerEnter = function() SFXManager.Play("buttonFocus") end,
                onClick = onClick,
                children = {
                    UI.Label { text = iconText, fontSize = 18, fontColor = iconColor },
                }
            },
        }
    }
end

--- 创建左侧抽牌堆区域（上:AI抽牌堆, 下:玩家抽牌堆）
function GameScene._CreateDeckPile()
    return UI.Panel {
        id = "deckPileArea",
        width = 90,
        height = "100%",
        justifyContent = "space-around",
        alignItems = "center",
        paddingVertical = 12,
        children = {
            -- AI 抽牌堆（不可查看内容）
            UI.Panel {
                alignItems = "center", gap = 3,
                children = {
                    UI.Label { text = "AI牌库", fontSize = 10, fontColor = Colors.textDim },
                    createStackVisual("aiDeckTop",
                        { {40,45,65,180}, {50,55,78,200}, {60,68,100,255}, {75,83,120,255} },
                        { {55,65,90,150}, {65,75,105,180}, {85,95,130,200} },
                        "?", {100,120,160,255},
                        function() GameScene._ShowPileInfo("aiDeck") end
                    ),
                    UI.Label { id = "aiDeckCountLabel", text = "0", fontSize = 10, fontColor = Colors.textDim },
                }
            },
            -- 玩家抽牌堆（可查看内容）
            UI.Panel {
                alignItems = "center", gap = 3,
                children = {
                    UI.Label { text = "我的牌库", fontSize = 10, fontColor = { 140, 170, 220, 255 } },
                    createStackVisual("playerDeckTop",
                        { {50,55,80,200}, {60,65,95,220}, {70,80,120,255}, {90,100,145,255} },
                        { {70,80,110,180}, {80,90,125,200}, {100,110,150,220} },
                        "?", {130,150,200,255},
                        function() GameScene._ShowPileView("playerDeck") end
                    ),
                    UI.Label { id = "playerDeckCountLabel", text = "0", fontSize = 10, fontColor = Colors.textDim },
                }
            },
        }
    }
end

--- 创建右侧弃牌堆区域（上:AI弃牌堆, 下:玩家弃牌堆）
function GameScene._CreateDiscardPile()
    return UI.Panel {
        id = "discardPileArea",
        width = 90,
        height = "100%",
        justifyContent = "space-around",
        alignItems = "center",
        paddingVertical = 12,
        children = {
            -- AI 弃牌堆（可查看内容）
            UI.Panel {
                alignItems = "center", gap = 3,
                children = {
                    UI.Label { text = "AI弃牌", fontSize = 10, fontColor = Colors.textDim },
                    createStackVisual("aiDiscardTop",
                        { {55,35,35,180}, {68,42,42,200}, {80,48,48,255}, {105,60,60,255} },
                        { {80,50,50,150}, {95,60,60,180}, {115,70,70,200} },
                        "X", {160,100,100,255},
                        function() GameScene._ShowPileView("aiDiscard") end
                    ),
                    UI.Label { id = "aiDiscardCountLabel", text = "0", fontSize = 10, fontColor = Colors.textDim },
                }
            },
            -- 玩家弃牌堆（可查看内容）
            UI.Panel {
                alignItems = "center", gap = 3,
                children = {
                    UI.Label { text = "我的弃牌", fontSize = 10, fontColor = { 220, 150, 150, 255 } },
                    createStackVisual("playerDiscardTop",
                        { {70,40,40,200}, {85,50,50,220}, {100,55,55,255}, {130,70,70,255} },
                        { {100,60,60,180}, {115,70,70,200}, {140,80,80,220} },
                        "X", {200,130,130,255},
                        function() GameScene._ShowPileView("playerDiscard") end
                    ),
                    UI.Label { id = "playerDiscardCountLabel", text = "0", fontSize = 10, fontColor = Colors.textDim },
                }
            },
        }
    }
end

function GameScene._CreateAIArea()
    return UI.Panel {
        id = "aiArea",
        width = "100%",
        alignItems = "center",
        gap = 6,
        children = {
            UI.Label {
                id = "aiLabel",
                text = "AI 对手",
                fontSize = 13,
                fontColor = Colors.textDim,
            },
            UI.Panel {
                id = "aiHandPanel",
                flexDirection = "row",
                gap = 12,
                flexWrap = "wrap",
                justifyContent = "center",
                children = {},
            },
        }
    }
end

function GameScene._CreateMiddleArea()
    return UI.Panel {
        id = "middleArea",
        width = "100%",
        alignItems = "center",
        justifyContent = "center",
        gap = 8,
        children = {
            UI.Label {
                id = "phaseLabel",
                text = "",
                fontSize = 17,
                fontColor = Colors.accent,
            },
            UI.Label {
                id = "infoLabel",
                text = "",
                fontSize = 15,
                fontColor = Colors.textDim,
                textAlign = "center",
            },
            UI.Label {
                id = "pointsLabel",
                text = "",
                fontSize = 16,
                fontColor = Colors.gold,
            },
        }
    }
end

function GameScene._CreatePlayerArea()
    return UI.Panel {
        id = "playerArea",
        width = "100%",
        alignItems = "center",
        gap = 6,
        children = {
            UI.Label {
                id = "playerPointsLabel",
                text = "",
                fontSize = 26,
                fontColor = Colors.success,
            },
            UI.Panel {
                id = "playerHandPanel",
                flexDirection = "row",
                gap = 12,
                flexWrap = "wrap",
                justifyContent = "center",
                children = {},
            },
            UI.Label {
                text = "我的手牌",
                fontSize = 13,
                fontColor = Colors.textDim,
            },
        }
    }
end

function GameScene._CreateBottomBar()
    return UI.Panel {
        id = "bottomBar",
        width = "100%",
        height = 60,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        paddingHorizontal = 20,
        backgroundColor = Colors.panel,
        borderColor = Colors.topBorder,
        borderWidth = { 1, 0, 0, 0 },
        children = {
            -- 操作按钮（居中）
            UI.Panel {
                flexDirection = "row",
                gap = 12,
                alignItems = "center",
                children = {
                    UI.Button {
                        id = "actionBtn",
                        text = "确认",
                        variant = "primary",
                        onPointerEnter = function() SFXManager.Play("buttonFocus") end,
                        onClick = function() GameScene._OnAction() end,
                    },
                    UI.Button {
                        id = "skipBtn",
                        text = "跳过",
                        visible = false,
                        onPointerEnter = function() SFXManager.Play("buttonFocus") end,
                        onClick = function() GameScene._OnSkip() end,
                    },
                }
            },
        }
    }
end

-- ============================================================================
-- 内部: 刷新逻辑
-- ============================================================================

function GameScene._RefreshScore()
    local pw, aw = GameController.GetScore()
    local scoreLabel = uiRoot:FindById("scoreLabel")
    if scoreLabel then
        scoreLabel:SetText(string.format("比分: %d - %d", pw, aw))
    end
    local roundLabel = uiRoot:FindById("roundLabel")
    if roundLabel then
        roundLabel:SetText(string.format("第 %d 局", GameController.GetRoundNumber()))
    end
end

function GameScene._RefreshPhaseLabel()
    local phaseLabel = uiRoot:FindById("phaseLabel")
    if phaseLabel then
        phaseLabel:SetText(GameScene._GetPhaseText())
    end
end

function GameScene._RefreshPlayerHand()
    -- 结算动画期间由 _UpdatePlayerHandInPlace 控制展示，不覆盖
    if settlementAnim then return end

    local panel = uiRoot:FindById("playerHandPanel")
    if not panel then return end

    -- 显式移除旧组件(避免 Tooltip 子组件脱离到根节点)
    for _, w in ipairs(playerHandWidgets) do
        if w and w.Remove then w:Remove() end
    end
    playerHandWidgets = {}
    panel:ClearChildren()

    local hand = GameController.GetPlayerHand()
    local phase = GameController.GetPhase()
    local subPhase = GameController.GetSubPhase()

    -- ROUND_END 阶段: 手牌已清空, 若有保留牌则居中展示
    if phase == Constant.PHASE.ROUND_END or phase == Constant.PHASE.GAME_OVER then
        local keepCard = GameController.GetPlayerKeepCard()
        if keepCard then
            local cardW = CardWidget.Create(keepCard, { skipTooltip = true })
            local wrapper = UI.Panel {
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label {
                        text = "已保留至下局",
                        fontSize = 12,
                        fontColor = Colors.gold,
                    },
                    cardW,
                }
            }
            panel:AddChild(wrapper)
            table.insert(playerHandWidgets, wrapper)
        end
        return
    end

    local selectable = (phase == Constant.PHASE.DRAW_FIVE or
                       phase == Constant.PHASE.DRAW_FOUR or
                       phase == Constant.PHASE.DRAW_THREE or
                       phase == Constant.PHASE.POST_DISCARD or
                       phase == Constant.PHASE.POST_KEEP or
                       phase == Constant.PHASE.JOKER_EFFECT)
                       and subPhase == Constant.SUB_PHASE.PLAYER_TURN

    for i, card in ipairs(hand) do
        local widget = CardWidget.Create(card, {
            selected = selectedCards[i] == true,
            selectable = selectable,
            onClick = function() GameScene._ToggleCard(i) end,
        })
        panel:AddChild(widget)
        table.insert(playerHandWidgets, widget)
    end
end

function GameScene._RefreshAIHand()
    -- 结算动画期间由 _UpdateAIHandInPlace 控制展示，不覆盖
    if settlementAnim then return end

    local panel = uiRoot:FindById("aiHandPanel")
    if not panel then return end

    -- 显式移除旧组件
    for _, w in ipairs(aiHandWidgets) do
        if w and w.Remove then w:Remove() end
    end
    aiHandWidgets = {}
    panel:ClearChildren()

    -- 结算动画期间由 _UpdateAIHandInPlace 接管，不在这里全部翻开
    if settlementAnim then
        GameScene._UpdateAIHandInPlace()
        return
    end

    local hand = GameController.GetAIHand()
    local phase = GameController.GetPhase()
    local showCards = (phase == Constant.PHASE.POST_DISCARD or
                      phase == Constant.PHASE.POST_KEEP or
                      phase == Constant.PHASE.ROUND_END)

    for _, card in ipairs(hand) do
        local widget = CardWidget.Create(showCards and card or nil, {
            isAI = true,
            glowCard = card,  -- 即使牌背面也显示光效
        })
        panel:AddChild(widget)
        table.insert(aiHandWidgets, widget)
    end
end

function GameScene._RefreshPlayerPoints()
    local label = uiRoot:FindById("playerPointsLabel")
    if not label then return end
    local hand = GameController.GetPlayerHand()
    if #hand > 0 then
        label:SetText(string.format("当前点数: %d", GameController.GetPlayerPoints()))
    else
        label:SetText("")
    end
end

function GameScene._RefreshButtons()
    local actionBtn = uiRoot:FindById("actionBtn")
    local skipBtn = uiRoot:FindById("skipBtn")
    if not actionBtn then return end

    local phase = GameController.GetPhase()
    local subPhase = GameController.GetSubPhase()

    if phase == Constant.PHASE.GAME_OVER then
        actionBtn:SetText("返回主菜单")
        actionBtn:SetVisible(true)
        actionBtn:SetDisabled(false)
        if skipBtn then skipBtn:SetVisible(false) end
    elseif phase == Constant.PHASE.DRAW_FIVE or
           phase == Constant.PHASE.DRAW_FOUR or
           phase == Constant.PHASE.DRAW_THREE then
        if subPhase == Constant.SUB_PHASE.PLAYER_TURN then
            local max = GameController.GetMaxDiscard()
            local count = GameScene._CountSelected()
            actionBtn:SetText(string.format("弃置 (%d/%d)", count, max))
            actionBtn:SetVisible(true)
            actionBtn:SetDisabled(false)
            if skipBtn then skipBtn:SetVisible(true); skipBtn:SetText("不弃牌") end
        else
            actionBtn:SetVisible(false)
            if skipBtn then skipBtn:SetVisible(false) end
        end
    elseif phase == Constant.PHASE.JOKER_EFFECT then
        if subPhase == Constant.SUB_PHASE.PLAYER_TURN then
            actionBtn:SetText("进入结算")
            actionBtn:SetVisible(true)
            actionBtn:SetDisabled(false)
            if skipBtn then skipBtn:SetVisible(false) end
        else
            actionBtn:SetVisible(false)
            if skipBtn then skipBtn:SetVisible(false) end
        end
    elseif phase == Constant.PHASE.POST_DISCARD then
        local count = GameScene._CountSelected()
        actionBtn:SetText(string.format("放回抽牌堆 (%d/2)", count))
        actionBtn:SetVisible(true)
        actionBtn:SetDisabled(false)
        if skipBtn then skipBtn:SetText("跳过"); skipBtn:SetVisible(true) end
    elseif phase == Constant.PHASE.POST_KEEP then
        local count = GameScene._CountSelected()
        actionBtn:SetText(string.format("保留至下局 (%d/1)", count))
        actionBtn:SetVisible(true)
        actionBtn:SetDisabled(false)
        if skipBtn then skipBtn:SetText("不保留"); skipBtn:SetVisible(true) end
    elseif phase == Constant.PHASE.ROUND_END then
        if GameController.IsGameOver() then
            actionBtn:SetText("查看结果")
        else
            actionBtn:SetText("下一局")
        end
        actionBtn:SetVisible(true)
        actionBtn:SetDisabled(false)
        if skipBtn then skipBtn:SetVisible(false) end
    elseif phase == Constant.PHASE.SETTLEMENT then
        -- 结算阶段通过弹窗自动推进，隐藏底部按钮
        actionBtn:SetVisible(false)
        if skipBtn then skipBtn:SetVisible(false) end
    else
        actionBtn:SetVisible(false)
        if skipBtn then skipBtn:SetVisible(false) end
    end
end

function GameScene._RefreshPileCounts()
    local playerDeck, playerDiscard, aiDeck, aiDiscard = GameController.GetPileCounts()
    local pdLabel = uiRoot:FindById("playerDeckCountLabel")
    if pdLabel then pdLabel:SetText(string.format("%d张", playerDeck)) end
    local pdcLabel = uiRoot:FindById("playerDiscardCountLabel")
    if pdcLabel then pdcLabel:SetText(string.format("%d张", playerDiscard)) end
    local adLabel = uiRoot:FindById("aiDeckCountLabel")
    if adLabel then adLabel:SetText(string.format("%d张", aiDeck)) end
    local adcLabel = uiRoot:FindById("aiDiscardCountLabel")
    if adcLabel then adcLabel:SetText(string.format("%d张", aiDiscard)) end
end

function GameScene._GetPhaseText()
    local phase = GameController.GetPhase()
    if phase == Constant.PHASE.DRAW_FIVE then return "第一回合 - 五!"
    elseif phase == Constant.PHASE.DRAW_FOUR then return "第二回合 - 四!"
    elseif phase == Constant.PHASE.DRAW_THREE then return "第三回合 - 三!"
    elseif phase == Constant.PHASE.JOKER_EFFECT then return "鬼牌效果阶段"
    elseif phase == Constant.PHASE.SETTLEMENT then return "结算"
    elseif phase == Constant.PHASE.POST_DISCARD then return "二! - 选至多2张放回抽牌堆"
    elseif phase == Constant.PHASE.POST_KEEP then return "一! - 选至多1张保留至下局"
    elseif phase == Constant.PHASE.ROUND_END then return "本局结束"
    elseif phase == Constant.PHASE.GAME_OVER then return "游戏结束"
    end
    return ""
end

-- ============================================================================
-- 内部: 选牌逻辑
-- ============================================================================

function GameScene._ToggleCard(index)
    if selectedCards[index] then
        selectedCards[index] = nil
    else
        local phase = GameController.GetPhase()
        local maxSelect = 5

        if phase == Constant.PHASE.DRAW_FIVE or
           phase == Constant.PHASE.DRAW_FOUR or
           phase == Constant.PHASE.DRAW_THREE then
            maxSelect = GameController.GetMaxDiscard()
        elseif phase == Constant.PHASE.POST_DISCARD then
            maxSelect = 2
        elseif phase == Constant.PHASE.POST_KEEP then
            maxSelect = 1
        elseif phase == Constant.PHASE.JOKER_EFFECT then
            maxSelect = 1
        end

        if GameScene._CountSelected() >= maxSelect then
            GameScene.SetInfo(string.format("最多选择 %d 张牌", maxSelect))
            return
        end
        selectedCards[index] = true
    end
    GameScene.Refresh()
end

function GameScene._CountSelected()
    local count = 0
    for _, v in pairs(selectedCards) do
        if v then count = count + 1 end
    end
    return count
end

function GameScene._GetSelectedIndices()
    local indices = {}
    for idx, v in pairs(selectedCards) do
        if v then table.insert(indices, idx) end
    end
    return indices
end

-- ============================================================================
-- 内部: 统计记录
-- ============================================================================

--- 记录游戏结束统计(防重复) + 删除存档 + 保存对局历史
local function recordGameOverStats()
    if gameStatsRecorded then return end
    gameStatsRecorded = true

    local winner = GameController.GetGameWinner()
    local pw, aw = GameController.GetScore()
    local difficulty = AISystem.GetDifficulty()
    local lastResult = GameController.GetLastResult()
    local hadSeven = lastResult and lastResult.sevenRuleTriggered or false
    local playerPts = lastResult and lastResult.playerPoints or nil

    StatsSystem.RecordGame(winner or "tie", difficulty, pw, aw, hadSeven, playerPts)
    SaveSystem.Delete()

    -- 保存对局历史(用于回放)
    local result = "tie"
    if winner == "player" then result = "win"
    elseif winner == "ai" then result = "lose" end

    local log = GameController.GetLog()
    MatchHistory.Record({
        difficulty = difficulty,
        result = result,
        finalScore = { pw, aw },
        log = log,
    })
end

-- ============================================================================
-- 内部: 按钮回调
-- ============================================================================

function GameScene._OnAction()
    SFXManager.Play("buttonPress")
    local phase = GameController.GetPhase()

    if phase == Constant.PHASE.GAME_OVER then
        if sceneCallbacks.onBackToMenu then sceneCallbacks.onBackToMenu() end
        return
    end

    if phase == Constant.PHASE.DRAW_FIVE or
       phase == Constant.PHASE.DRAW_FOUR or
       phase == Constant.PHASE.DRAW_THREE then
        local indices = GameScene._GetSelectedIndices()
        local success, err = GameController.PlayerDiscard(indices)
        if not success then
            GameScene.SetInfo(err or "操作失败")
            return
        end
        -- 弃牌音效
        if #indices > 0 then
            SFXManager.Play("discard")
        end
        -- 弃牌飞行动画: 从手牌区飞向右侧弃牌堆
        if #indices > 0 then
            local sw = graphics:GetWidth() / graphics:GetDPR()
            local sh = graphics:GetHeight() / graphics:GetDPR()
            local startX = sw * 0.5
            local startY = sh * 0.75
            local endX = sw - 45   -- 右侧弃牌堆大致位置
            local endY = sh * 0.7  -- 玩家弃牌堆位置(下方)
            VFXManager.EmitFlyingCards(startX, startY, endX, endY, #indices)
        end
        selectedCards = {}

        -- 完成玩家回合
        GameController.FinishPlayerTurn()
        selectedCards = {}

        local newPhase = GameController.GetPhase()
        if newPhase == Constant.PHASE.JOKER_EFFECT then
            GameScene._HandleJokerPhase()
        else
            GameScene.SetInfo(string.format("选择要弃置的牌（至多%d张），或跳过",
                GameController.GetMaxDiscard()))
        end
        GameScene.Refresh()
        return
    end

    if phase == Constant.PHASE.JOKER_EFFECT then
        GameScene._HandleJokerPhase()
        selectedCards = {}
        GameScene.Refresh()
        return
    end

    if phase == Constant.PHASE.SETTLEMENT then
        -- 结算阶段通过弹窗自动推进，不再需要底部按钮
        return
    end

    if phase == Constant.PHASE.POST_DISCARD then
        local indices = GameScene._GetSelectedIndices()
        if #indices > 2 then
            GameScene.SetInfo("最多弃置2张!")
            return
        end
        -- 放回抽牌堆飞行动画: 从手牌区飞向左侧抽牌堆
        if #indices > 0 then
            local sw = graphics:GetWidth() / graphics:GetDPR()
            local sh = graphics:GetHeight() / graphics:GetDPR()
            VFXManager.EmitFlyingCards(sw * 0.5, sh * 0.75, 45, sh * 0.7, #indices)
        end
        GameController.PlayerPostDiscard(indices)
        selectedCards = {}
        GameScene.SetInfo("选择至多1张牌保留至下一局")
        GameScene.Refresh()
        return
    end

    if phase == Constant.PHASE.POST_KEEP then
        local indices = GameScene._GetSelectedIndices()
        if #indices > 1 then
            GameScene.SetInfo("最多保留1张!")
            return
        end
        local keepIdx = indices[1] or nil
        GameController.PlayerPostKeep(keepIdx)
        selectedCards = {}

        local newPhase = GameController.GetPhase()
        if newPhase == Constant.PHASE.GAME_OVER then
            recordGameOverStats()
            local winner = GameController.GetGameWinner()
            local pw, aw = GameController.GetScore()
            GameScene.SetInfo(string.format("游戏结束! %s获胜!\n最终比分: %d - %d",
                winner == "player" and "玩家" or "AI", pw, aw))
        else
            GameScene.SetInfo("本局结束，准备下一局")
        end
        GameScene.Refresh()
        return
    end

    if phase == Constant.PHASE.ROUND_END then
        if GameController.IsGameOver() then
            recordGameOverStats()
            local winner = GameController.GetGameWinner()
            local pw, aw = GameController.GetScore()
            GameScene.SetInfo(string.format("游戏结束! %s获胜!\n最终比分: %d - %d",
                winner == "player" and "玩家" or "AI", pw, aw))
            -- 直接设置到 GAME_OVER
            local gs = GameController.GetState()
            if gs then gs.round.phase = Constant.PHASE.GAME_OVER end
        else
            -- 启动局间过渡动画(动画结束后自动StartNextRound)
            local nextRound = GameController.GetRoundNumber() + 1
            GameScene._StartTransition(nextRound)
        end
        GameScene.Refresh()
        return
    end
end

function GameScene._OnSkip()
    SFXManager.Play("buttonPress")
    local phase = GameController.GetPhase()

    if phase == Constant.PHASE.DRAW_FIVE or
       phase == Constant.PHASE.DRAW_FOUR or
       phase == Constant.PHASE.DRAW_THREE then
        selectedCards = {}
        GameController.SkipDiscard()

        local newPhase = GameController.GetPhase()
        if newPhase == Constant.PHASE.JOKER_EFFECT then
            GameScene._HandleJokerPhase()
        else
            GameScene.SetInfo(string.format("选择要弃置的牌（至多%d张），或跳过",
                GameController.GetMaxDiscard()))
        end
        GameScene.Refresh()
        return
    end

    if phase == Constant.PHASE.POST_DISCARD then
        GameController.SkipPostDiscard()
        selectedCards = {}
        GameScene.SetInfo("选择至多1张牌保留至下一局")
        GameScene.Refresh()
        return
    end

    if phase == Constant.PHASE.POST_KEEP then
        GameController.SkipPostKeep()
        selectedCards = {}
        local newPhase = GameController.GetPhase()
        if newPhase == Constant.PHASE.GAME_OVER then
            recordGameOverStats()
            local winner = GameController.GetGameWinner()
            local pw, aw = GameController.GetScore()
            GameScene.SetInfo(string.format("游戏结束! %s获胜!\n最终比分: %d - %d",
                winner == "player" and "玩家" or "AI", pw, aw))
        else
            GameScene.SetInfo("本局结束，准备下一局")
        end
        GameScene.Refresh()
        return
    end

    if phase == Constant.PHASE.JOKER_EFFECT then
        local result = GameController.DoJokerAndSettle()
        GameScene._ShowSettlementResult(result)
        selectedCards = {}
        GameScene.Refresh()
        return
    end
end

-- ============================================================================
-- 内部: 鬼牌阶段
-- ============================================================================

function GameScene._HandleJokerPhase()
    local hasSmall = GameController.PlayerHasSmallJoker()
    local hasBig = GameController.PlayerHasBigJoker()

    if hasSmall then
        -- 玩家有小王: 显示点数选择UI(0-13)
        GameScene._ShowSmallJokerValueUI()
    elseif hasBig then
        -- 玩家有大王: 显示目标牌+点数选择UI
        GameScene._ShowBigJokerChoiceUI()
    else
        -- 玩家无鬼牌，直接结算
        local result = GameController.DoJokerAndSettle()
        GameScene._ShowSettlementResult(result)
    end
end

--- 小王点数选择UI: 让玩家选择0-13作为小王自身点数
function GameScene._ShowSmallJokerValueUI()
    if not uiRoot then return end

    local valueButtons = {}
    for v = 0, 13 do
        table.insert(valueButtons, UI.Button {
            text = tostring(v),
            width = 44,
            height = 36,
            fontSize = 14,
            backgroundColor = { 80, 40, 140, 220 },
            borderRadius = 6,
            onPointerEnter = function() SFXManager.Play("buttonFocus") end,
            onClick = function()
                SFXManager.Play("buttonPress")
                GameScene._OnSmallJokerValueChosen(v)
            end,
        })
    end

    local overlay = UI.Panel {
        id = "jokerChoiceOverlay",
        width = "100%",
        height = "100%",
        position = "absolute",
        backgroundColor = { 0, 0, 0, 200 },
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 340,
                backgroundColor = Colors.menuCard,
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 150, 80, 200, 150 },
                padding = 20,
                gap = 14,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "小王 - 选择点数",
                        fontSize = 18,
                        fontColor = Colors.jokerPurple,
                    },
                    UI.Label {
                        text = "选择0~13作为小王的点数",
                        fontSize = 13,
                        fontColor = Colors.textDim,
                        textAlign = "center",
                    },
                    UI.Panel {
                        flexDirection = "row",
                        flexWrap = "wrap",
                        justifyContent = "center",
                        gap = 6,
                        children = valueButtons,
                    },
                }
            },
        }
    }
    uiRoot:AddChild(overlay)
end

function GameScene._OnSmallJokerValueChosen(value)
    -- 关闭选择UI
    local overlay = uiRoot:FindById("jokerChoiceOverlay")
    if overlay then overlay:Remove() end

    -- 设置小王点数
    GameController.PlayerSetSmallJokerValue(value)
    GameScene.SetInfo(string.format("小王点数设为: %d", value))

    -- 小王处理完, 检查是否还有大王需要选择
    if GameController.PlayerHasBigJoker() then
        GameScene._ShowBigJokerChoiceUI()
    else
        -- 全部处理完, 进入结算
        local result = GameController.DoJokerAndSettle()
        GameScene._ShowSettlementResult(result)
    end
end

--- 大王选择UI: 第一步 - 选择要变更点数的手牌
function GameScene._ShowBigJokerChoiceUI()
    if not uiRoot then return end

    local playerHand = GameController.GetPlayerHand()

    -- 创建手牌按钮(让玩家选择哪张牌要改点数)
    local cardButtons = {}
    for i, card in ipairs(playerHand) do
        local cardName = Card.GetName(card)
        local pts = Card.GetBasePoints(card)
        local displayText = string.format("%s(%d点)", cardName, pts)
        if Card.IsJoker(card) then
            displayText = cardName
        end
        table.insert(cardButtons, UI.Button {
            text = displayText,
            height = 36,
            fontSize = 12,
            paddingLeft = 10,
            paddingRight = 10,
            backgroundColor = { 50, 50, 80, 220 },
            borderRadius = 6,
            onPointerEnter = function() SFXManager.Play("buttonFocus") end,
            onClick = function()
                SFXManager.Play("buttonPress")
                GameScene._ShowBigJokerValueUI(i)
            end,
        })
    end

    local overlay = UI.Panel {
        id = "jokerChoiceOverlay",
        width = "100%",
        height = "100%",
        position = "absolute",
        backgroundColor = { 0, 0, 0, 200 },
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 300,
                backgroundColor = Colors.menuCard,
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 150, 80, 200, 150 },
                padding = 20,
                gap = 12,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "大王效果",
                        fontSize = 18,
                        fontColor = Colors.jokerPurple,
                    },
                    UI.Label {
                        text = "选择一张手牌, 将其点数变为0-13",
                        fontSize = 13,
                        fontColor = Colors.textDim,
                        textAlign = "center",
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 6, flexWrap = "wrap", justifyContent = "center",
                        children = cardButtons,
                    },
                }
            },
        }
    }
    uiRoot:AddChild(overlay)
end

--- 大王选择UI: 第二步 - 为选中的手牌选择目标点数(0-13)
function GameScene._ShowBigJokerValueUI(targetIdx)
    if not uiRoot then return end

    -- 关闭第一步的UI
    local overlay = uiRoot:FindById("jokerChoiceOverlay")
    if overlay then overlay:Remove() end

    local playerHand = GameController.GetPlayerHand()
    local targetCard = playerHand[targetIdx]
    local targetName = targetCard and Card.GetName(targetCard) or "?"

    -- 计算推荐值(让总分接近21)
    local otherPts = 0
    for i, card in ipairs(playerHand) do
        if i ~= targetIdx and not (card.rank == 15) then
            otherPts = otherPts + Card.GetBasePoints(card)
        end
    end
    local recommended = math.max(0, math.min(13, GameConfig.TARGET_POINTS - otherPts))

    -- 创建点数按钮行
    local rows = {}
    for row = 0, 1 do
        local rowBtns = {}
        local startVal = row * 7
        local endVal = math.min(startVal + 6, 13)
        for v = startVal, endVal do
            local isRec = (v == recommended)
            table.insert(rowBtns, UI.Button {
                text = tostring(v),
                width = 36,
                height = 34,
                fontSize = 13,
                backgroundColor = isRec and { 60, 120, 60, 220 } or { 50, 50, 80, 220 },
                borderRadius = 6,
                borderWidth = isRec and 2 or 0,
                borderColor = isRec and { 100, 255, 100, 200 } or nil,
                onPointerEnter = function() SFXManager.Play("buttonFocus") end,
                onClick = function()
                    SFXManager.Play("buttonPress")
                    GameScene._OnBigJokerChoice(targetIdx, v)
                end,
            })
        end
        table.insert(rows, UI.Panel {
            flexDirection = "row", gap = 4, justifyContent = "center",
            children = rowBtns,
        })
    end

    local overlay2 = UI.Panel {
        id = "jokerChoiceOverlay",
        width = "100%",
        height = "100%",
        position = "absolute",
        backgroundColor = { 0, 0, 0, 200 },
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 300,
                backgroundColor = Colors.menuCard,
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 150, 80, 200, 150 },
                padding = 20,
                gap = 12,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "大王效果",
                        fontSize = 18,
                        fontColor = Colors.jokerPurple,
                    },
                    UI.Label {
                        text = string.format("将 %s 的点数设为: (推荐: %d)", targetName, recommended),
                        fontSize = 13,
                        fontColor = Colors.textDim,
                        textAlign = "center",
                    },
                    rows[1],
                    rows[2],
                }
            },
        }
    }
    uiRoot:AddChild(overlay2)
end

function GameScene._OnBigJokerChoice(targetIdx, value)
    -- 关闭选择UI
    local overlay = uiRoot:FindById("jokerChoiceOverlay")
    if overlay then overlay:Remove() end

    -- 设置目标牌的点数
    GameController.PlayerSetBigJokerValue(targetIdx, value)

    -- 第三步: 为大王自身选择点数
    GameScene._ShowBigJokerSelfValueUI()
end

--- 大王选择UI: 第三步 - 为大王自身选择点数(0-13)
function GameScene._ShowBigJokerSelfValueUI()
    if not uiRoot then return end

    -- 计算推荐值(让总分接近21)
    local playerHand = GameController.GetPlayerHand()
    local otherPts = 0
    for _, card in ipairs(playerHand) do
        if card.rank ~= 15 then  -- 不算大王自身
            local pts = card.jokerOverride or Card.GetBasePoints(card)
            otherPts = otherPts + pts
        end
    end
    local recommended = math.max(0, math.min(13, GameConfig.TARGET_POINTS - otherPts))

    -- 创建点数按钮行
    local rows = {}
    for row = 0, 1 do
        local rowBtns = {}
        local startVal = row * 7
        local endVal = math.min(startVal + 6, 13)
        for v = startVal, endVal do
            local isRec = (v == recommended)
            table.insert(rowBtns, UI.Button {
                text = tostring(v),
                width = 36,
                height = 34,
                fontSize = 13,
                backgroundColor = isRec and { 60, 120, 60, 220 } or { 50, 50, 80, 220 },
                borderRadius = 6,
                borderWidth = isRec and 2 or 0,
                borderColor = isRec and { 100, 255, 100, 200 } or nil,
                onPointerEnter = function() SFXManager.Play("buttonFocus") end,
                onClick = function()
                    SFXManager.Play("buttonPress")
                    GameScene._OnBigJokerSelfChoice(v)
                end,
            })
        end
        table.insert(rows, UI.Panel {
            flexDirection = "row", gap = 4, justifyContent = "center",
            children = rowBtns,
        })
    end

    local overlay = UI.Panel {
        id = "jokerChoiceOverlay",
        width = "100%",
        height = "100%",
        position = "absolute",
        backgroundColor = { 0, 0, 0, 200 },
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 300,
                backgroundColor = Colors.menuCard,
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 150, 80, 200, 150 },
                padding = 20,
                gap = 12,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "大王效果",
                        fontSize = 18,
                        fontColor = Colors.jokerPurple,
                    },
                    UI.Label {
                        text = string.format("设置大王自身的点数: (推荐: %d)", recommended),
                        fontSize = 13,
                        fontColor = Colors.textDim,
                        textAlign = "center",
                    },
                    rows[1],
                    rows[2],
                }
            },
        }
    }
    uiRoot:AddChild(overlay)
end

function GameScene._OnBigJokerSelfChoice(value)
    -- 关闭选择UI
    local overlay = uiRoot:FindById("jokerChoiceOverlay")
    if overlay then overlay:Remove() end

    -- 设置大王自身点数
    GameController.PlayerSetBigJokerSelfValue(value)

    -- 全部处理完, 进入结算
    local result = GameController.DoJokerAndSettle()
    GameScene._ShowSettlementResult(result)
end

function GameScene._ShowSettlementResult(result)
    if not result then return end

    -- 结算开始: 压低 BGM 音量
    BGMManager.Duck(0.2)

    -- 启动逐张翻牌动画(包括三7特殊规则也走翻牌流程)
    local aiHand = GameController.GetAIHand()
    local playerHand = GameController.GetPlayerHand()

    -- 结算时手牌已经是最终状态(鬼牌效果已执行), 直接使用
    local displayPlayerHand = {}
    for _, c in ipairs(playerHand) do
        table.insert(displayPlayerHand, c)
    end

    -- 排序AI手牌: 普通(2-7) → 稀有(8-10) → 罕见(J-K) → Ace → 鬼牌
    local displayAIHand = {}
    for _, c in ipairs(aiHand) do
        table.insert(displayAIHand, c)
    end
    table.sort(displayAIHand, function(a, b)
        local function categoryOrder(card)
            if Card.IsNormal(card) then return 1 end       -- 2-7: 普通
            if card.rank >= 8 and card.rank <= 10 then return 2 end  -- 8-10: 稀有
            if Card.IsFace(card) then return 3 end         -- J-K: 罕见
            if card.rank == 1 then return 4 end            -- Ace
            if Card.IsJoker(card) then return 5 end        -- 鬼牌
            return 1
        end
        local oa, ob = categoryOrder(a), categoryOrder(b)
        if oa ~= ob then return oa < ob end
        return a.rank < b.rank
    end)

    -- 计算玩家"裸分"(不含对方效果影响的基础得分)
    local RuleEngine = require("system.RuleEngine")
    local playerRawPts = 0
    do
        local emptyHand = {}
        local gs = GameController.GetState()
        playerRawPts, _ = RuleEngine.CalculatePoints(displayPlayerHand, emptyHand,
            gs and gs.player or nil, nil)
    end

    settlementAnim = {
        result = result,
        aiHand = aiHand,
        playerHand = playerHand,
        displayPlayerHand = displayPlayerHand,
        displayAIHand = displayAIHand,  -- 已排序的展示用AI手牌
        playerRawPoints = playerRawPts,
        revealedCount = 0,
        timer = 0,
        interval = 1.0,  -- 每1.0秒翻一张
        finished = false,
    }
    -- 创建结算弹窗
    GameScene._CreateSettlementOverlay()
end

--- 创建结算翻牌弹窗
function GameScene._CreateSettlementOverlay()
    if not uiRoot then return end
    local anim = settlementAnim
    if not anim then return end

    -- 翻牌时不创建遮挡窗口，只在屏幕中央显示倒计时图片
    -- AI手牌直接在游戏界面的aiHandPanel中逐张翻开
    GameScene._UpdateAIHandInPlace()
    -- 玩家手牌使用 displayPlayerHand 显示(包含可能被小王移除的牌)
    GameScene._UpdatePlayerHandInPlace()
    GameScene._UpdateCountdownOverlay()
end

--- 检测翻开的AI牌是否影响玩家手牌, 触发光线特效
---@param revealedIdx number 刚翻开的AI牌索引
function GameScene._TriggerSkillBeamVFX(revealedIdx)
    local anim = settlementAnim
    if not anim then return end
    local aiCard = anim.aiHand[revealedIdx]
    if not aiCard then return end

    local playerHand = anim.displayPlayerHand or anim.playerHand
    local displayAIHand = anim.displayAIHand or anim.aiHand
    local aiCount = #displayAIHand  -- 使用展示手牌数量计算布局
    local playerCount = #playerHand

    local displayRevealedIdx = revealedIdx

    -- 判断哪些玩家牌受影响
    local affectedIndices = {}
    local beamColor = { r = 0.6, g = 0.4, b = 1.0 }  -- 默认紫色

    if aiCard.rank == 13 then
        -- K: 对方普通牌+稀有牌×2
        beamColor = { r = 1.0, g = 0.8, b = 0.2 }
        for i, card in ipairs(playerHand) do
            if Card.IsNormal(card) or (card.rank >= 8 and card.rank <= 10) then
                table.insert(affectedIndices, i)
            end
        end
    elseif aiCard.rank == 12 then
        -- Q: 对方最高普通牌×2
        beamColor = { r = 0.8, g = 0.2, b = 0.9 }
        local maxIdx, maxPts = nil, -1
        for i, card in ipairs(playerHand) do
            if Card.IsNormal(card) then
                local pts = Card.GetBasePoints(card)
                if pts > maxPts then
                    maxPts = pts
                    maxIdx = i
                end
            end
        end
        if maxIdx then
            table.insert(affectedIndices, maxIdx)
        end
    elseif aiCard.rank == 1 then
        -- A: 对方同花色的牌×2
        beamColor = { r = 1.0, g = 0.4, b = 0.3 }
        for i, card in ipairs(playerHand) do
            if card.suit and card.suit == aiCard.suit then
                table.insert(affectedIndices, i)
            end
        end
    elseif aiCard.rank == 8 then
        -- 8: 对方所有普通牌+2
        beamColor = { r = 1.0, g = 0.7, b = 0.2 }
        for i, card in ipairs(playerHand) do
            if Card.IsNormal(card) then
                table.insert(affectedIndices, i)
            end
        end
    end

    -- 计算屏幕坐标 (基于布局估算)
    local sw = graphics:GetWidth() / graphics:GetDPR()
    local sh = graphics:GetHeight() / graphics:GetDPR()

    -- AI 牌位置估算: topBar(50) + aiArea上部约30 + 牌中心
    local aiCardW = 120
    local aiCardH = 168
    local aiTotalW = aiCount * aiCardW + (aiCount - 1) * 12
    local centerAreaLeft = 90
    local centerAreaW = sw - 180  -- 减去左右两侧
    local aiStartX = centerAreaLeft + (centerAreaW - aiTotalW) * 0.5
    local aiY = 50 + 6 + 13 + 6 + aiCardH * 0.5  -- topBar + gap + label + gap + 半高

    local srcX = aiStartX + (displayRevealedIdx - 1) * (aiCardW + 12) + aiCardW * 0.5
    local srcY = aiY

    -- 玩家牌位置估算
    local playerCardW = 216
    local playerCardH = 300
    local playerTotalW = playerCount * playerCardW + (playerCount - 1) * 12
    local playerStartX = centerAreaLeft + (centerAreaW - playerTotalW) * 0.5
    local playerY = sh - 60 - 6 - 13 - 6 - playerCardH * 0.5

    -- 1) AI特殊牌 → 影响玩家牌 (从AI牌发射到玩家牌)
    if #affectedIndices > 0 then
        -- 确定效果描述文字
        local effectText = ""
        if aiCard.rank == 13 then
            effectText = "×2"
        elseif aiCard.rank == 12 then
            effectText = "×2"
        elseif aiCard.rank == 1 then
            effectText = "×2"
        elseif aiCard.rank == 8 then
            effectText = "+2"
        end

        for _, pIdx in ipairs(affectedIndices) do
            local destX = playerStartX + (pIdx - 1) * (playerCardW + 12) + playerCardW * 0.5
            local destY = playerY
            VFXManager.EmitLightBeam(srcX, srcY, destX, destY, {
                r = beamColor.r, g = beamColor.g, b = beamColor.b,
                duration = 1.0,
            })
            -- 在被影响的玩家牌上方飘字
            if effectText ~= "" then
                VFXManager.EmitFloatingText(destX, destY - playerCardH * 0.5 - 10, effectText, {
                    r = beamColor.r, g = beamColor.g, b = beamColor.b,
                    duration = 1.4,
                    fontSize = 16,
                })
            end
        end
    end

    -- 2) 玩家特殊牌 → 影响该AI牌 (从玩家牌发射到AI牌)
    local aiCard2 = aiCard  -- 被翻开的AI牌
    for pIdx, pCard in ipairs(playerHand) do
        local shouldBeam = false
        local pBeamColor = { r = 0.3, g = 0.8, b = 1.0 }
        local pEffectText = ""

        if pCard.rank == 13 and (Card.IsNormal(aiCard2) or (aiCard2.rank >= 8 and aiCard2.rank <= 10)) then
            -- K: 对方普通牌+稀有牌×2
            shouldBeam = true
            pBeamColor = { r = 1.0, g = 0.8, b = 0.2 }
            pEffectText = "×2"
        elseif pCard.rank == 12 and Card.IsNormal(aiCard2) then
            -- Q: 对方最高普通牌×2 (这里简化为标记)
            shouldBeam = true
            pBeamColor = { r = 0.5, g = 0.2, b = 1.0 }
            pEffectText = "×2"
        elseif pCard.rank == 1 and aiCard2.suit and pCard.suit == aiCard2.suit then
            -- A: 同花色×2
            shouldBeam = true
            pBeamColor = { r = 0.2, g = 1.0, b = 0.5 }
            pEffectText = "×2"
        elseif pCard.rank == 8 and Card.IsNormal(aiCard2) then
            -- 8: 对方普通牌-2
            shouldBeam = true
            pBeamColor = { r = 0.2, g = 0.9, b = 0.7 }
            pEffectText = "-2"
        end

        if shouldBeam then
            local pSrcX = playerStartX + (pIdx - 1) * (playerCardW + 12) + playerCardW * 0.5
            local pSrcY = playerY
            VFXManager.EmitLightBeam(pSrcX, pSrcY, srcX, srcY, {
                r = pBeamColor.r, g = pBeamColor.g, b = pBeamColor.b,
                duration = 1.0,
            })
            -- 在被影响的AI牌上方飘字
            if pEffectText ~= "" then
                VFXManager.EmitFloatingText(srcX, srcY - aiCardH * 0.5 - 10, pEffectText, {
                    r = pBeamColor.r, g = pBeamColor.g, b = pBeamColor.b,
                    duration = 1.4,
                    fontSize = 16,
                })
            end
        end
    end
end



--- 更新结算内容(每翻一张牌时调用)
function GameScene._UpdateSettlementOverlay()
    -- 在游戏界面直接翻开AI手牌
    GameScene._UpdateAIHandInPlace()

    -- 更新玩家手牌(结算期间用 displayPlayerHand, 支持小王半透明化)
    GameScene._UpdatePlayerHandInPlace()

    -- 显示AI当前累计点数
    GameScene._UpdateAIPointsDuringReveal()

    -- 翻牌时触发技能影响光线特效
    local anim = settlementAnim
    if anim and anim.revealedCount > 0 then
        GameScene._TriggerSkillBeamVFX(anim.revealedCount)
    end

    -- 更新倒计时图片
    GameScene._UpdateCountdownOverlay()

    -- 全部翻完后触发结算效果
    if anim and anim.revealedCount >= #anim.aiHand and not anim.vfxTriggered then
        anim.vfxTriggered = true
        local sw = graphics:GetWidth() / graphics:GetDPR()
        local sh = graphics:GetHeight() / graphics:GetDPR()
        local cx, cy = sw * 0.5, sh * 0.5
        if anim.result.winner == "player" then
            VFXManager.EmitWinParticles(cx, cy)
        elseif anim.result.winner == "ai" then
            VFXManager.EmitLoseParticles(cx, cy)
        end
        -- 延迟2秒后同时显示结算弹窗和播放胜负音效
        anim.winLoseTimer = 2.0
    end
end

--- 在游戏界面直接翻开AI手牌(不创建弹窗)
function GameScene._UpdateAIHandInPlace()
    local anim = settlementAnim
    if not anim then return end
    local panel = uiRoot:FindById("aiHandPanel")
    if not panel then return end

    -- 清理旧组件
    for _, w in ipairs(aiHandWidgets) do
        if w and w.Remove then w:Remove() end
    end
    aiHandWidgets = {}
    panel:ClearChildren()

    -- 使用 displayAIHand 逐张翻牌
    local hand = anim.displayAIHand or anim.aiHand

    for i, card in ipairs(hand) do
        local widget
        if i <= anim.revealedCount then
            -- 已翻开: 正面显示
            widget = CardWidget.Create(card, { isAI = true })
        else
            -- 未翻开: 背面
            widget = CardWidget.Create(nil, { isAI = true })
        end
        panel:AddChild(widget)
        table.insert(aiHandWidgets, widget)
    end
end

--- 结算时更新玩家手牌显示
function GameScene._UpdatePlayerHandInPlace()
    local anim = settlementAnim
    if not anim then return end
    local panel = uiRoot:FindById("playerHandPanel")
    if not panel then return end

    -- 清理旧组件
    for _, w in ipairs(playerHandWidgets) do
        if w and w.Remove then w:Remove() end
    end
    playerHandWidgets = {}
    panel:ClearChildren()

    local hand = anim.displayPlayerHand or anim.playerHand

    for _, card in ipairs(hand) do
        local widget = CardWidget.Create(card, { skipTooltip = true })
        panel:AddChild(widget)
        table.insert(playerHandWidgets, widget)
    end
end

--- 翻牌期间显示AI当前累计点数
function GameScene._UpdateAIPointsDuringReveal()
    local anim = settlementAnim
    if not anim then return end
    local aiLabel = uiRoot:FindById("aiLabel")
    if not aiLabel then return end

    if anim.revealedCount > 0 then
        -- 用已翻开的AI牌计算当前点数
        local RuleEngine = require("system.RuleEngine")
        local revealedHand = {}
        for i = 1, anim.revealedCount do
            table.insert(revealedHand, anim.aiHand[i])
        end
        -- 计算AI已翻牌的裸分(使用玩家手牌作为对手牌来算交互效果)
        local gs = GameController.GetState()
        local playerHand = anim.displayPlayerHand or anim.playerHand
        local aiPts, _ = RuleEngine.CalculatePoints(revealedHand, playerHand,
            gs and gs.ai or nil, gs and gs.player or nil)
        aiLabel:SetText(string.format("AI 对手 (当前: %d点)", aiPts))
    else
        aiLabel:SetText("AI 对手")
    end
end

--- 更新屏幕中央倒计时文字
function GameScene._UpdateCountdownOverlay()
    local anim = settlementAnim
    if not anim then return end

    local remaining = #anim.aiHand - anim.revealedCount + 1

    -- 倒计时文字映射(5→1)
    local countdownTexts = {
        [5] = "五!",
        [4] = "四!",
        [3] = "三!",
        [2] = "二!",
        [1] = "一!",
    }

    -- remaining 在 1-5 范围内时显示
    if remaining >= 1 and remaining <= 5 then
        local txt = countdownTexts[remaining]

        -- 隐藏中间提示区域(避免与倒计时文字重叠)
        local middleArea = uiRoot:FindById("middleArea")
        if middleArea then middleArea:SetStyle({ opacity = 0 }) end

        -- 复用已有 overlay，只更新文字
        local existingOverlay = uiRoot:FindById("countdownOverlay")
        if existingOverlay then
            local label = existingOverlay:FindById("countdownLabel")
            if label then
                label:SetText(txt)
            end
        else
            local overlay = UI.Panel {
                id = "countdownOverlay",
                width = "100%",
                height = "100%",
                position = "absolute",
                justifyContent = "center",
                alignItems = "center",
                paddingBottom = 120,
                opacity = 1.0,
                children = {
                    UI.Label {
                        id = "countdownLabel",
                        text = txt,
                        fontSize = 200,
                        fontWeight = "bold",
                        color = "#FFFFFF",
                        textAlign = "center",
                    },
                }
            }
            uiRoot:AddChild(overlay)
        end
    else
        -- 超出范围则移除
        local oldOverlay = uiRoot:FindById("countdownOverlay")
        if oldOverlay then oldOverlay:Remove() end
        VFXManager.ClearBloomImages()

        -- 恢复中间提示区域显示
        local middleArea = uiRoot:FindById("middleArea")
        if middleArea then middleArea:SetStyle({ opacity = 1 }) end
    end
end

--- 构建效果详情标签列表
---@param hand table
---@param details table|nil 计算详情
---@param isPlayer boolean
local function buildEffectDetails(hand, details, isPlayer)
    if not details then return {} end

    local effects = {}
    local headerColor = { 220, 200, 140, 255 }
    local formulaColor = { 200, 200, 200, 255 }
    local effectColor = { 180, 180, 120, 255 }

    -- ===== 逐张运算过程 =====
    if details.cardBreakdown and #details.cardBreakdown > 0 then
        -- 标题
        table.insert(effects, UI.Label {
            text = "逐张计算:",
            fontSize = 11,
            fontColor = headerColor,
        })

        -- 逐张展示: 基础点 → 效果 → 最终
        for _, entry in ipairs(details.cardBreakdown) do
            local line
            if #entry.effects > 0 then
                line = string.format("  %s: %d → %s → %d",
                    entry.name, entry.base,
                    table.concat(entry.effects, " → "),
                    entry.final)
            else
                line = string.format("  %s: %d", entry.name, entry.final)
            end
            table.insert(effects, UI.Label {
                text = line,
                fontSize = 10,
                fontColor = formulaColor,
            })
        end

        -- 求和公式
        local parts = {}
        local sum = 0
        for _, entry in ipairs(details.cardBreakdown) do
            table.insert(parts, tostring(entry.final))
            sum = sum + entry.final
        end
        local sumLine = "  合计: " .. table.concat(parts, " + ") .. " = " .. sum
        table.insert(effects, UI.Label {
            text = sumLine,
            fontSize = 10,
            fontColor = { 160, 220, 160, 255 },
        })
    end

    -- ===== 触发的效果摘要 =====
    local hasEffectSummary = false

    -- 8 效果
    if (details.eightEffects and details.eightEffects > 0) or (details.opponentEightCount and details.opponentEightCount > 0) then
        if not hasEffectSummary then
            table.insert(effects, UI.Label { text = "生效效果:", fontSize = 11, fontColor = headerColor })
            hasEffectSummary = true
        end
        local parts = {}
        if details.eightEffects > 0 then
            table.insert(parts, string.format("己方8×%d: 己方普通牌各-%d", details.eightEffects, details.eightEffects * 2))
        end
        if details.opponentEightCount > 0 then
            table.insert(parts, string.format("对方8×%d: 己方普通牌各+%d", details.opponentEightCount, details.opponentEightCount * 2))
        end
        table.insert(effects, UI.Label {
            text = "  8: " .. table.concat(parts, "; "),
            fontSize = 10,
            fontColor = effectColor,
        })
    end

    -- J 效果
    if details.jackActive then
        if not hasEffectSummary then
            table.insert(effects, UI.Label { text = "生效效果:", fontSize = 11, fontColor = headerColor })
            hasEffectSummary = true
        end
        table.insert(effects, UI.Label {
            text = "  J: 己方普通牌(2-7)点数→0",
            fontSize = 10,
            fontColor = { 200, 100, 255, 255 },
        })
    end

    -- K 效果 (被对方K影响)
    if details.kingActive then
        if not hasEffectSummary then
            table.insert(effects, UI.Label { text = "生效效果:", fontSize = 11, fontColor = headerColor })
            hasEffectSummary = true
        end
        table.insert(effects, UI.Label {
            text = "  K(对方): 己方普通牌+稀有牌点数×2",
            fontSize = 10,
            fontColor = { 255, 160, 60, 255 },
        })
    end

    -- A 翻倍效果 (被对方A翻倍)
    if details.aceEffects and #details.aceEffects > 0 then
        if not hasEffectSummary then
            table.insert(effects, UI.Label { text = "生效效果:", fontSize = 11, fontColor = headerColor })
            hasEffectSummary = true
        end
        local suits = {}
        for _, s in ipairs(details.aceEffects) do
            table.insert(suits, Constant.SUIT_SYMBOLS[s] or s)
        end
        table.insert(effects, UI.Label {
            text = string.format("  A(对方): 己方%s花色牌点数×2", table.concat(suits, "")),
            fontSize = 10,
            fontColor = { 255, 120, 120, 255 },
        })
    end

    -- 10 效果
    if details.tenReduce and details.tenReduce > 0 then
        if not hasEffectSummary then
            table.insert(effects, UI.Label { text = "生效效果:", fontSize = 11, fontColor = headerColor })
            hasEffectSummary = true
        end
        table.insert(effects, UI.Label {
            text = string.format("  10: 己方稀有+罕见牌各-9(总计-%d)", details.tenReduce),
            fontSize = 10,
            fontColor = { 100, 200, 200, 255 },
        })
    end

    -- 9 灵活
    if details.nineFlexSaved and details.nineFlexSaved > 0 then
        if not hasEffectSummary then
            table.insert(effects, UI.Label { text = "生效效果:", fontSize = 11, fontColor = headerColor })
            hasEffectSummary = true
        end
        table.insert(effects, UI.Label {
            text = string.format("  9灵活: 视为0(节省%d点)", details.nineFlexSaved),
            fontSize = 10,
            fontColor = effectColor,
        })
    end

    -- Q 效果 (己方Q对对方的影响 / 己方被取整)
    if details.queenFloor then
        if not hasEffectSummary then
            table.insert(effects, UI.Label { text = "生效效果:", fontSize = 11, fontColor = headerColor })
            hasEffectSummary = true
        end
        table.insert(effects, UI.Label {
            text = "  Q(己方): 己方点数取至十位(向下)",
            fontSize = 10,
            fontColor = { 180, 80, 200, 255 },
        })
    end
    if details.queenTriple and details.queenTriple > 0 then
        if not hasEffectSummary then
            table.insert(effects, UI.Label { text = "生效效果:", fontSize = 11, fontColor = headerColor })
            hasEffectSummary = true
        end
        table.insert(effects, UI.Label {
            text = string.format("  Q(己方): 对方最高普通牌×2(+%d给对方)", details.queenTriple),
            fontSize = 10,
            fontColor = { 180, 80, 200, 255 },
        })
    end

    return effects
end

--- 全部翻完后显示结果覆盖层(胜负+点数计算+继续按钮)
function GameScene._ShowSettlementContinueBtn()
    if not uiRoot then return end
    local anim = settlementAnim
    if not anim then return end

    -- 移除倒计时
    local cdOverlay = uiRoot:FindById("countdownOverlay")
    if cdOverlay then cdOverlay:Remove() end
    VFXManager.ClearBloomImages()

    -- 构建结果文字
    local resultText = ""
    local resultColor = Colors.textDim
    if anim.result.winner == "player" then
        resultText = "你赢了!"
        resultColor = Colors.success
    elseif anim.result.winner == "ai" then
        resultText = "AI赢了!"
        resultColor = { 255, 100, 100, 255 }
    else
        resultText = "平局!"
        resultColor = Colors.gold
    end

    -- 点数信息
    local playerPts = anim.result.playerPoints or 0
    local aiPts = anim.result.aiPoints or 0
    local ptsInfo = string.format("你: %d点  AI: %d点", playerPts, aiPts)

    -- 距离21 + 爆点提示
    local distInfo = ""
    if not anim.result.sevenRuleTriggered then
        local playerDist = math.abs(GameConfig.TARGET_POINTS - playerPts)
        local aiDist = math.abs(GameConfig.TARGET_POINTS - aiPts)
        local playerOverStr = playerPts > GameConfig.TARGET_POINTS and "(爆)" or ""
        local aiOverStr = aiPts > GameConfig.TARGET_POINTS and "(爆)" or ""
        distInfo = string.format("距21: 你%d%s  AI%d%s", playerDist, playerOverStr, aiDist, aiOverStr)
    end

    -- 效果详情
    local detailChildren = {}
    if not anim.result.sevenRuleTriggered then
        local playerDetails = anim.result.playerDetails
        local aiDetails = anim.result.aiDetails
        local playerEffects = buildEffectDetails(anim.playerHand, playerDetails, true)
        local aiEffects = buildEffectDetails(anim.aiHand, aiDetails, false)
        if #playerEffects > 0 then
            table.insert(detailChildren, UI.Label { text = "── 你 ──", fontSize = 11, fontColor = Colors.textDim })
            for _, w in ipairs(playerEffects) do
                table.insert(detailChildren, w)
            end
        end
        if #aiEffects > 0 then
            table.insert(detailChildren, UI.Label { text = "── AI ──", fontSize = 11, fontColor = Colors.textDim })
            for _, w in ipairs(aiEffects) do
                table.insert(detailChildren, w)
            end
        end

        -- Q的跨玩家最终处理步骤(在两方明细之后统一展示)
        local hasQueenStep = false
        local queenStepChildren = {}
        -- 玩家Q对AI的加分
        if playerDetails and playerDetails.queenTriple and playerDetails.queenTriple > 0 then
            hasQueenStep = true
            local preAiPts = aiPts - playerDetails.queenTriple
            table.insert(queenStepChildren, UI.Label {
                text = string.format("  你的Q → AI点数: %d + %d = %d", preAiPts, playerDetails.queenTriple, aiPts),
                fontSize = 10,
                fontColor = { 180, 80, 200, 255 },
            })
        end
        -- AI的Q对玩家的加分
        if aiDetails and aiDetails.queenTriple and aiDetails.queenTriple > 0 then
            hasQueenStep = true
            local prePlayerPts = playerPts - aiDetails.queenTriple
            table.insert(queenStepChildren, UI.Label {
                text = string.format("  AI的Q → 你点数: %d + %d = %d", prePlayerPts, aiDetails.queenTriple, playerPts),
                fontSize = 10,
                fontColor = { 180, 80, 200, 255 },
            })
        end
        -- 玩家Q取整(己方点数向下取至十位)
        if playerDetails and playerDetails.queenFloor then
            hasQueenStep = true
            table.insert(queenStepChildren, UI.Label {
                text = "  你的Q → 你点数向下取至十位",
                fontSize = 10,
                fontColor = { 180, 80, 200, 255 },
            })
        end
        -- AI的Q取整
        if aiDetails and aiDetails.queenFloor then
            hasQueenStep = true
            table.insert(queenStepChildren, UI.Label {
                text = "  AI的Q → AI点数向下取至十位",
                fontSize = 10,
                fontColor = { 180, 80, 200, 255 },
            })
        end
        if hasQueenStep then
            table.insert(detailChildren, UI.Label { text = "── Q结算 ──", fontSize = 11, fontColor = { 180, 80, 200, 255 } })
            for _, w in ipairs(queenStepChildren) do
                table.insert(detailChildren, w)
            end
        end
    else
        table.insert(detailChildren, UI.Label {
            text = "三7特殊规则触发!",
            fontSize = 13,
            fontColor = { 255, 200, 50, 255 },
        })
    end

    -- 构建内容children
    local contentChildren = {
        UI.Label { text = resultText, fontSize = 22, fontColor = resultColor },
        UI.Label { text = ptsInfo, fontSize = 14, fontColor = Colors.textDim },
    }
    if distInfo ~= "" then
        table.insert(contentChildren, UI.Label { text = distInfo, fontSize = 12, fontColor = Colors.textDim })
    end
    -- 效果详情区域(可滚动)
    if #detailChildren > 0 then
        table.insert(contentChildren, UI.Panel {
            width = "100%", height = 1, backgroundColor = Colors.menuBorder, marginVertical = 4,
        })
        table.insert(contentChildren, UI.ScrollView {
            width = "100%",
            maxHeight = 260,
            flexShrink = 1,
            children = detailChildren,
        })
    end
    -- 继续按钮
    table.insert(contentChildren, UI.Panel {
        width = "100%", height = 1, backgroundColor = Colors.menuBorder, marginVertical = 4,
    })
    table.insert(contentChildren, UI.Button {
        text = "继续",
        width = "70%",
        height = 40,
        fontSize = 15,
        variant = "primary",
        onPointerEnter = function() SFXManager.Play("buttonFocus") end,
        onClick = function()
            GameScene._CloseSettlementAndAdvance()
        end,
    })

    -- 创建结果覆盖层
    local overlay = UI.Panel {
        id = "settlementOverlay",
        width = "100%",
        height = "100%",
        position = "absolute",
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                id = "settlementContent",
                width = "85%",
                maxHeight = "80%",
                backgroundColor = Colors.menuCard,
                borderRadius = 12,
                borderWidth = 1,
                borderColor = Colors.gold,
                padding = 20,
                gap = 8,
                alignItems = "center",
                children = contentChildren,
            }
        }
    }
    uiRoot:AddChild(overlay)
end

--- 关闭结算覆盖层
function GameScene._CloseSettlementOverlay()
    settlementAnim = nil
    local overlay = uiRoot:FindById("settlementOverlay")
    if overlay then overlay:Remove() end
    local cdOverlay = uiRoot:FindById("countdownOverlay")
    if cdOverlay then cdOverlay:Remove() end
    VFXManager.ClearBloomImages()
    -- 恢复中间提示区域(倒计时期间被隐藏)
    local middleArea = uiRoot:FindById("middleArea")
    if middleArea then middleArea:SetStyle({ opacity = 1 }) end
    -- 恢复AI标签
    local aiLabel = uiRoot:FindById("aiLabel")
    if aiLabel then aiLabel:SetText("AI 对手") end
end

--- 关闭结算弹窗并自动推进到POST_DISCARD阶段(或直接结束游戏)
function GameScene._CloseSettlementAndAdvance()
    GameScene._CloseSettlementOverlay()
    -- 结算结束: 恢复 BGM 音量
    BGMManager.Unduck()
    -- 比分已达胜利条件时跳过二!/一!直接结束
    if GameController.IsGameOver() then
        GameController.SkipToGameOver()
        recordGameOverStats()
        selectedCards = {}
        GameScene.Refresh()
        return
    end
    GameController.EnterPostGame()
    selectedCards = {}
    GameScene.SetInfo("选择至多2张牌放回你的抽牌堆")
    GameScene.Refresh()
end

-- ============================================================================
-- 内部: 牌堆查看弹窗
-- ============================================================================

--- 对牌进行排序: 鬼牌在前, 然后按rank降序排列
---@param pile table[]
---@return table[]
local function sortPile(pile)
    local sorted = {}
    for _, c in ipairs(pile) do table.insert(sorted, c) end
    table.sort(sorted, function(a, b)
        -- 鬼牌排在最前面
        local aJoker = Card.IsJoker(a) and 1 or 0
        local bJoker = Card.IsJoker(b) and 1 or 0
        if aJoker ~= bJoker then return aJoker > bJoker end
        -- rank 降序（A=1 视为14排在最前）
        local aRank = a.rank == 1 and 14 or a.rank
        local bRank = b.rank == 1 and 14 or b.rank
        if aRank ~= bRank then return aRank > bRank end
        -- 同rank按suit排序
        return (a.suit or "") < (b.suit or "")
    end)
    return sorted
end

--- 按rank分组: 返回 { {rankKey, cards}, ... } 排好序
---@param pile table[]
---@return table[]
local function groupByRank(pile)
    local sorted = sortPile(pile)
    local groups = {}
    local currentRank = nil
    local currentGroup = nil
    for _, card in ipairs(sorted) do
        local rk = Card.IsJoker(card) and 99 or card.rank
        if rk ~= currentRank then
            currentRank = rk
            currentGroup = { rank = rk, cards = {} }
            table.insert(groups, currentGroup)
        end
        table.insert(currentGroup.cards, card)
    end
    return groups
end

function GameScene._ShowPileView(pileType)
    viewingPile = pileType

    local pile, title
    if pileType == "playerDiscard" then
        pile = GameController.GetPlayerDiscardPile()
        title = "我的弃牌堆"
    elseif pileType == "playerDeck" then
        pile = GameController.GetPlayerDeck()
        title = "我的抽牌堆"
    elseif pileType == "aiDiscard" then
        pile = GameController.GetAIDiscardPile()
        title = "AI 弃牌堆"
    else
        return
    end

    -- 按rank分组
    local groups = groupByRank(pile)

    local rowWidgets = {}
    if #pile == 0 then
        table.insert(rowWidgets, UI.Label {
            text = "（空）",
            fontSize = 14,
            fontColor = Colors.textDim,
        })
    else
        for _, group in ipairs(groups) do
            local cardRow = {}
            for _, card in ipairs(group.cards) do
                table.insert(cardRow, CardWidget.Create(card, { small = true }))
            end
            table.insert(rowWidgets, UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 6,
                paddingHorizontal = 8,
                paddingVertical = 4,
                alignItems = "center",
                children = cardRow,
            })
        end
    end

    local overlay = UI.Panel {
        id = "pileOverlay",
        width = "100%",
        height = "100%",
        position = "absolute",
        backgroundColor = { 0, 0, 0, 180 },
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = "85%",
                maxHeight = "75%",
                backgroundColor = Colors.menuCard,
                borderRadius = 12,
                borderWidth = 1,
                borderColor = Colors.menuBorder,
                padding = 20,
                gap = 12,
                alignItems = "center",
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = title .. string.format(" (%d张)", #pile),
                                fontSize = 16,
                                fontColor = Colors.gold,
                            },
                            UI.Button {
                                text = "关闭",
                                fontSize = 12,
                                height = 30,
                                onPointerEnter = function() SFXManager.Play("buttonFocus") end,
                                onClick = function() GameScene._ClosePileView() end,
                            },
                        }
                    },
                    UI.Panel {
                        width = "100%",
                        height = 1,
                        backgroundColor = Colors.menuBorder,
                    },
                    UI.ScrollView {
                        width = "100%",
                        flexGrow = 1,
                        flexBasis = 0,
                        children = {
                            UI.Panel {
                                width = "100%",
                                gap = 2,
                                padding = 4,
                                children = rowWidgets,
                            }
                        }
                    },
                }
            },
        }
    }

    uiRoot:AddChild(overlay)
end

function GameScene._ClosePileView()
    viewingPile = nil
    local overlay = uiRoot:FindById("pileOverlay")
    if overlay then overlay:Remove() end
end

--- 显示AI牌堆信息（只显示数量，不显示内容）
function GameScene._ShowPileInfo(pileType)
    local count, title
    if pileType == "aiDeck" then
        count = GameController.GetAIDeckCount()
        title = "AI 抽牌堆"
    elseif pileType == "aiDiscard" then
        local _, _, _, aiDiscard = GameController.GetPileCounts()
        count = aiDiscard
        title = "AI 弃牌堆"
    else
        return
    end
    GameScene.SetInfo(string.format("%s: %d 张牌", title, count))
end

-- ============================================================================
-- 内部: 局间过渡动画
-- ============================================================================

--- 启动局间过渡动画
---@param roundNum number 即将开始的局数
function GameScene._StartTransition(roundNum)
    local pw, aw = GameController.GetScore()
    transitionAnim = {
        timer = 0,
        duration = 1.8,  -- 总时长1.8秒
        roundNum = roundNum,
        scoreText = string.format("比分  %d : %d", pw, aw),
    }
    SFXManager.Play("shuffle", 4.0)
    GameScene._CreateTransitionOverlay()
end

--- 创建过渡覆盖层
function GameScene._CreateTransitionOverlay()
    if not uiRoot then return end
    -- 移除旧的
    local old = uiRoot:FindById("transitionOverlay")
    if old then old:Remove() end

    local anim = transitionAnim
    if not anim then return end

    local overlay = UI.Panel {
        id = "transitionOverlay",
        width = "100%",
        height = "100%",
        position = "absolute",
        backgroundColor = { 10, 15, 30, 220 },
        justifyContent = "center",
        alignItems = "center",
        gap = 12,
        children = {
            UI.Label {
                id = "transRoundLabel",
                text = string.format("第 %d 局", anim.roundNum),
                fontSize = 32,
                fontColor = Colors.gold,
                textAlign = "center",
            },
            UI.Label {
                id = "transScoreLabel",
                text = anim.scoreText,
                fontSize = 16,
                fontColor = Colors.text,
                textAlign = "center",
            },
            UI.Panel {
                width = 60,
                height = 3,
                backgroundColor = Colors.accent,
                borderRadius = 2,
                marginTop = 8,
            },
        }
    }
    uiRoot:AddChild(overlay)
end

--- 更新过渡覆盖层(可扩展为渐变动画)
function GameScene._UpdateTransitionOverlay()
    -- 当前实现为静态展示，可未来扩展淡入淡出
end

--- 结束过渡动画，进入新回合
function GameScene._EndTransition()
    transitionAnim = nil
    -- 移除覆盖层
    if uiRoot then
        local overlay = uiRoot:FindById("transitionOverlay")
        if overlay then overlay:Remove() end
    end
    -- 检查是否进入决赛局（任一方2分），通知切换BGM
    local pw, aw = GameController.GetScore()
    if (pw >= GameConfig.WINS_NEEDED - 1 or aw >= GameConfig.WINS_NEEDED - 1) then
        if sceneCallbacks and sceneCallbacks.onLastRound then
            sceneCallbacks.onLastRound()
        end
    end
    -- 开始新回合
    GameController.StartNextRound()
    selectedCards = {}
    GameScene.SetInfo(string.format("选择要弃置的牌（至多%d张），或跳过",
        GameController.GetMaxDiscard()))
    GameScene.Refresh()
end

-- ============================================================================
-- 内部: 游戏日志查看
-- ============================================================================

--- 显示游戏日志弹窗
function GameScene._ShowGameLog()
    if not uiRoot then return end
    -- 防止重复打开
    local existing = uiRoot:FindById("gameLogOverlay")
    if existing then return end

    local overlay = GameLogViewer.Create(function()
        GameScene._CloseGameLog()
    end)
    uiRoot:AddChild(overlay)
end

--- 关闭游戏日志弹窗
function GameScene._CloseGameLog()
    if not uiRoot then return end
    local overlay = uiRoot:FindById("gameLogOverlay")
    if overlay then overlay:Remove() end
end

return GameScene
