-- ============================================================================
-- ui/scenes/GameScene.lua - 游戏主界面
-- ============================================================================

local UI = require("urhox-libs/UI")
local Colors = require("ui.Colors")
local Card = require("core.Card")
local Constant = require("core.Constant")
local CardWidget = require("ui.components.CardWidget")
local GameController = require("service.GameController")
local VFXManager = require("vfx.VFXManager")

local GameScene = {}

-- 本地状态
local selectedCards = {}     -- 选中的牌索引集合
local uiRoot = nil           -- 当前 UI 根节点
local viewingPile = nil      -- 正在查看的牌堆

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

--- 处理 ESC 键
---@return boolean handled
function GameScene.HandleEscape()
    if viewingPile then
        GameScene._ClosePileView()
        return true
    end
    local jackOverlay = uiRoot and uiRoot:FindById("jackPickOverlay")
    if jackOverlay then
        return true  -- J选牌时不允许ESC退出
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
                gap = 16,
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
            -- AI 弃牌堆（不可查看内容）
            UI.Panel {
                alignItems = "center", gap = 3,
                children = {
                    UI.Label { text = "AI弃牌", fontSize = 10, fontColor = Colors.textDim },
                    createStackVisual("aiDiscardTop",
                        { {55,35,35,180}, {68,42,42,200}, {80,48,48,255}, {105,60,60,255} },
                        { {80,50,50,150}, {95,60,60,180}, {115,70,70,200} },
                        "X", {160,100,100,255},
                        function() GameScene._ShowPileInfo("aiDiscard") end
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
                fontSize = 15,
                fontColor = Colors.accent,
            },
            UI.Label {
                id = "infoLabel",
                text = "",
                fontSize = 13,
                fontColor = Colors.textDim,
                textAlign = "center",
            },
            UI.Label {
                id = "pointsLabel",
                text = "",
                fontSize = 14,
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
                fontSize = 13,
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
                        onClick = function() GameScene._OnAction() end,
                    },
                    UI.Button {
                        id = "skipBtn",
                        text = "跳过",
                        visible = false,
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
    local panel = uiRoot:FindById("playerHandPanel")
    if not panel then return end
    panel:ClearChildren()

    local hand = GameController.GetPlayerHand()
    local phase = GameController.GetPhase()
    local subPhase = GameController.GetSubPhase()

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
    end
end

function GameScene._RefreshAIHand()
    local panel = uiRoot:FindById("aiHandPanel")
    if not panel then return end
    panel:ClearChildren()

    local hand = GameController.GetAIHand()
    local phase = GameController.GetPhase()
    local showCards = (phase == Constant.PHASE.SETTLEMENT or
                      phase == Constant.PHASE.POST_DISCARD or
                      phase == Constant.PHASE.POST_KEEP or
                      phase == Constant.PHASE.ROUND_END)

    for _, card in ipairs(hand) do
        local widget = CardWidget.Create(showCards and card or nil, { isAI = true })
        panel:AddChild(widget)
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
        actionBtn:SetText(string.format("弃置至牌堆 (%d/2)", count))
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
        actionBtn:SetText("继续")
        actionBtn:SetVisible(true)
        actionBtn:SetDisabled(false)
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
    elseif phase == Constant.PHASE.POST_DISCARD then return "二! - 选至多2张弃置至牌堆"
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
-- 内部: 按钮回调
-- ============================================================================

function GameScene._OnAction()
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
        -- 弃牌粒子效果
        if #indices > 0 then
            local sw = graphics:GetWidth() / graphics:GetDPR()
            local sh = graphics:GetHeight() / graphics:GetDPR()
            VFXManager.EmitDiscardParticles(sw * 0.5, sh * 0.7)
        end
        selectedCards = {}

        -- 检查J效果
        if GameController.GetPendingJackPicks() > 0 then
            GameScene.Refresh()
            GameScene._ShowJackPickUI()
            return
        end

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
        local result = GameController.DoJokerAndSettle()
        GameScene._ShowSettlementResult(result)
        selectedCards = {}
        GameScene.Refresh()
        return
    end

    if phase == Constant.PHASE.SETTLEMENT then
        GameController.EnterPostGame()
        selectedCards = {}
        GameScene.SetInfo("选择至多2张牌弃置至你的抽牌堆")
        GameScene.Refresh()
        return
    end

    if phase == Constant.PHASE.POST_DISCARD then
        local indices = GameScene._GetSelectedIndices()
        if #indices > 2 then
            GameScene.SetInfo("最多弃置2张!")
            return
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
            local winner = GameController.GetGameWinner()
            local pw, aw = GameController.GetScore()
            GameScene.SetInfo(string.format("游戏结束! %s获胜!\n最终比分: %d - %d",
                winner == "player" and "玩家" or "AI", pw, aw))
            -- 直接设置到 GAME_OVER
            local gs = GameController.GetState()
            if gs then gs.round.phase = Constant.PHASE.GAME_OVER end
        else
            GameController.StartNextRound()
            selectedCards = {}
            GameScene.SetInfo(string.format("选择要弃置的牌（至多%d张），或跳过",
                GameController.GetMaxDiscard()))
        end
        GameScene.Refresh()
        return
    end
end

function GameScene._OnSkip()
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
    if GameController.PlayerHasJoker() then
        GameScene.SetInfo("你有鬼牌! 点击'进入结算'自动处理鬼牌效果")
    else
        local result = GameController.DoJokerAndSettle()
        GameScene._ShowSettlementResult(result)
    end
end

function GameScene._ShowSettlementResult(result)
    if not result then return end
    local text = ""
    if result.sevenRuleTriggered then
        text = "三7特殊规则触发! "
    end

    -- 获取屏幕中心用于粒子效果
    local sw = graphics:GetWidth() / graphics:GetDPR()
    local sh = graphics:GetHeight() / graphics:GetDPR()
    local cx, cy = sw * 0.5, sh * 0.5

    if result.winner == "player" then
        text = text .. string.format("你赢了! (%d点 vs %d点)", result.playerPoints, result.aiPoints)
        -- 胜利烟花
        VFXManager.EmitWinParticles(cx, cy)
    elseif result.winner == "ai" then
        text = text .. string.format("AI赢了! (%d点 vs %d点)", result.playerPoints, result.aiPoints)
        -- 失败粒子
        VFXManager.EmitLoseParticles(cx, cy)
    else
        text = text .. string.format("平局! (%d点 vs %d点)", result.playerPoints, result.aiPoints)
    end
    GameScene.SetInfo(text)
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

function GameScene._ShowPileView(pileType)
    viewingPile = pileType

    local pile, title
    if pileType == "playerDiscard" then
        pile = GameController.GetPlayerDiscardPile()
        title = "我的弃牌堆"
    elseif pileType == "playerDeck" then
        pile = GameController.GetPlayerDeck()
        title = "我的抽牌堆"
    else
        return
    end

    -- 排序
    local sortedPile = sortPile(pile)

    local cardWidgets = {}
    if #sortedPile == 0 then
        table.insert(cardWidgets, UI.Label {
            text = "（空）",
            fontSize = 14,
            fontColor = Colors.textDim,
        })
    else
        for _, card in ipairs(sortedPile) do
            table.insert(cardWidgets, CardWidget.Create(card, { small = true }))
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
                                text = title .. string.format(" (%d张)", #sortedPile),
                                fontSize = 16,
                                fontColor = Colors.gold,
                            },
                            UI.Button {
                                text = "关闭",
                                fontSize = 12,
                                height = 30,
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
                                flexDirection = "row",
                                flexWrap = "wrap",
                                gap = 6,
                                justifyContent = "center",
                                padding = 8,
                                children = cardWidgets,
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
-- 内部: J效果弹窗
-- ============================================================================

function GameScene._ShowJackPickUI()
    local playerDeck, playerDiscard = GameController.GetPileCounts()
    local remaining = GameController.GetPendingJackPicks()

    local overlay = UI.Panel {
        id = "jackPickOverlay",
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
                padding = 24,
                gap = 16,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "J 弃置效果",
                        fontSize = 18,
                        fontColor = Colors.jokerPurple,
                    },
                    UI.Label {
                        text = string.format("从你的牌堆中随机抽取一张牌\n(剩余 %d 次)", remaining),
                        fontSize = 13,
                        fontColor = Colors.textDim,
                        textAlign = "center",
                    },
                    UI.Button {
                        text = string.format("从我的弃牌堆抽 (%d张)", playerDiscard),
                        width = "100%",
                        height = 44,
                        fontSize = 14,
                        backgroundColor = { 100, 45, 45, 220 },
                        borderRadius = 8,
                        disabled = playerDiscard == 0,
                        onClick = function() GameScene._OnJackPick("discard") end,
                    },
                    UI.Button {
                        text = string.format("从我的抽牌堆抽 (%d张)", playerDeck),
                        width = "100%",
                        height = 44,
                        fontSize = 14,
                        backgroundColor = { 45, 45, 100, 220 },
                        borderRadius = 8,
                        disabled = playerDeck == 0,
                        onClick = function() GameScene._OnJackPick("deck") end,
                    },
                }
            },
        }
    }

    uiRoot:AddChild(overlay)
end

function GameScene._OnJackPick(source)
    local success, err, card = GameController.PlayerJackPick(source)
    if not success then
        GameScene.SetInfo(err or "抽取失败")
        return
    end

    -- J效果紫色闪光
    local sw = graphics:GetWidth() / graphics:GetDPR()
    local sh = graphics:GetHeight() / graphics:GetDPR()
    VFXManager.EmitJackEffect(sw * 0.5, sh * 0.5)

    -- 关闭弹窗
    local overlay = uiRoot:FindById("jackPickOverlay")
    if overlay then overlay:Remove() end

    local cardName = card and Card.GetName(card) or "?"
    GameScene.SetInfo(string.format("J效果: 从%s中随机抽到 %s",
        source == "discard" and "弃牌堆" or "抽牌堆", cardName))

    -- 还有J待处理?
    if GameController.GetPendingJackPicks() > 0 then
        GameScene.Refresh()
        GameScene._ShowJackPickUI()
    else
        -- J全部处理完毕
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
    end
end

return GameScene
