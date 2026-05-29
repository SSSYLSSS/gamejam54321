-- ============================================================================
-- main.lua - 五！四！三！二十一点！
-- 卡牌对战博弈游戏 (改版21点, 5局3胜)
-- ============================================================================

local UI = require("urhox-libs/UI")
local CardDefs = require("CardDefs")
local GameLogic = require("GameLogic")
local AIPlayer = require("AIPlayer")

-- ============================================================================
-- 全局状态
-- ============================================================================

---@type table
local gameState = nil
local selectedCards = {}   -- 玩家选中的牌索引集合
local uiRoot = nil

-- 当前场景: "menu" / "game" / "settings"
local currentScene = "menu"

-- UI 引用
local refs = {}

-- 音频设置
local audioSettings = {
    master = 80,
    music = 70,
    sfx = 90,
}

-- 游戏子阶段
local subPhase = "player_turn"  -- player_turn / ai_turn / waiting / jack_pick
local postPhase = "discard"     -- discard / keep (结算后子阶段)
local jokerPhase = "pending"    -- pending / small_joker_pick / big_joker_pick / done

-- 牌堆查看状态
local viewingPile = nil         -- nil / "discard" / "deck" / "jack_discard" / "jack_deck"

-- ============================================================================
-- 颜色定义
-- ============================================================================
local COLORS = {
    bg = { 25, 32, 45, 255 },
    cardBg = { 255, 252, 245, 255 },
    cardSelected = { 180, 230, 255, 255 },
    red = { 200, 50, 50, 255 },
    black = { 35, 35, 35, 255 },
    gold = { 218, 165, 32, 255 },
    panel = { 35, 45, 60, 230 },
    panelLight = { 45, 58, 78, 230 },
    text = { 240, 240, 240, 255 },
    textDim = { 160, 170, 185, 255 },
    accent = { 80, 160, 255, 255 },
    success = { 80, 200, 120, 255 },
    danger = { 230, 80, 80, 255 },
    jokerPurple = { 150, 80, 200, 255 },
    menuBg = { 18, 22, 36, 255 },
    menuCard = { 30, 40, 58, 240 },
    menuBorder = { 60, 80, 120, 120 },
}

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = "五!四!三!二十一点!"
    
    math.randomseed(os.time())
    
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })
    
    -- 显示主菜单
    ShowMainMenu()
    
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    
    print("=== 五!四!三!二十一点! ===")
end

function Stop()
    UI.Shutdown()
end

-- ============================================================================
-- 主菜单
-- ============================================================================

function ShowMainMenu()
    currentScene = "menu"
    
    uiRoot = UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        backgroundColor = COLORS.menuBg,
        justifyContent = "center",
        alignItems = "center",
        children = {
            -- 主菜单卡片
            UI.Panel {
                id = "menuCard",
                width = 320,
                backgroundColor = COLORS.menuCard,
                borderRadius = 16,
                borderWidth = 1,
                borderColor = COLORS.menuBorder,
                padding = 36,
                gap = 20,
                alignItems = "center",
                children = {
                    -- 标题
                    UI.Label {
                        text = "五!四!三!",
                        fontSize = 28,
                        fontColor = COLORS.gold,
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "二十一点!",
                        fontSize = 22,
                        fontColor = COLORS.text,
                        textAlign = "center",
                    },
                    -- 分隔
                    UI.Panel {
                        width = "80%",
                        height = 1,
                        backgroundColor = COLORS.menuBorder,
                        marginVertical = 8,
                    },
                    -- 菜单按钮
                    CreateMenuButton("startBtn", "开始游戏", COLORS.accent, function()
                        StartGame()
                    end),
                    CreateMenuButton("multiBtn", "多人游戏", COLORS.gold, function()
                        ShowMultiplayerNotice()
                    end),
                    CreateMenuButton("settingsBtn", "设置", COLORS.textDim, function()
                        ShowSettings()
                    end),
                    CreateMenuButton("exitBtn", "退出游戏", COLORS.danger, function()
                        engine:Exit()
                    end),
                    -- 底部版本信息
                    UI.Panel {
                        width = "100%",
                        marginTop = 12,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = "v1.0  |  GameJam 2025",
                                fontSize = 11,
                                fontColor = { 100, 110, 130, 180 },
                            },
                        }
                    },
                }
            },
        }
    }
    UI.SetRoot(uiRoot)
end

--- 创建菜单按钮
function CreateMenuButton(id, text, color, onClick)
    return UI.Button {
        id = id,
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

--- 多人游戏提示（暂未实现）
function ShowMultiplayerNotice()
    uiRoot = UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        backgroundColor = COLORS.menuBg,
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 300,
                backgroundColor = COLORS.menuCard,
                borderRadius = 16,
                borderWidth = 1,
                borderColor = COLORS.menuBorder,
                padding = 32,
                gap = 16,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "多人游戏",
                        fontSize = 20,
                        fontColor = COLORS.gold,
                    },
                    UI.Label {
                        text = "敬请期待...\n多人对战功能正在开发中",
                        fontSize = 13,
                        fontColor = COLORS.textDim,
                        textAlign = "center",
                    },
                    UI.Panel { height = 8 },
                    UI.Button {
                        text = "返回",
                        width = "100%",
                        height = 40,
                        onClick = function() ShowMainMenu() end,
                    },
                }
            },
        }
    }
    UI.SetRoot(uiRoot)
end

-- ============================================================================
-- 设置界面
-- ============================================================================

function ShowSettings()
    currentScene = "settings"
    
    uiRoot = UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        backgroundColor = COLORS.menuBg,
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 360,
                backgroundColor = COLORS.menuCard,
                borderRadius = 16,
                borderWidth = 1,
                borderColor = COLORS.menuBorder,
                padding = 32,
                gap = 20,
                alignItems = "center",
                children = {
                    -- 标题
                    UI.Label {
                        text = "设置",
                        fontSize = 22,
                        fontColor = COLORS.text,
                    },
                    -- 分隔线
                    UI.Panel {
                        width = "100%",
                        height = 1,
                        backgroundColor = COLORS.menuBorder,
                    },
                    -- 音频设置标题
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 8,
                        children = {
                            UI.Label {
                                text = "音频设置",
                                fontSize = 16,
                                fontColor = COLORS.gold,
                            },
                        }
                    },
                    -- 主音量
                    CreateVolumeSlider("master", "主音量", audioSettings.master, function(val)
                        audioSettings.master = val
                        ApplyAudioSettings()
                    end),
                    -- 音乐
                    CreateVolumeSlider("music", "音乐", audioSettings.music, function(val)
                        audioSettings.music = val
                        ApplyAudioSettings()
                    end),
                    -- 音效
                    CreateVolumeSlider("sfx", "音效", audioSettings.sfx, function(val)
                        audioSettings.sfx = val
                        ApplyAudioSettings()
                    end),
                    -- 分隔
                    UI.Panel {
                        width = "100%",
                        height = 1,
                        backgroundColor = COLORS.menuBorder,
                        marginTop = 8,
                    },
                    -- 返回按钮
                    UI.Button {
                        text = "返回主菜单",
                        width = "100%",
                        height = 44,
                        fontSize = 15,
                        borderRadius = 8,
                        onClick = function() ShowMainMenu() end,
                    },
                }
            },
        }
    }
    UI.SetRoot(uiRoot)
end

--- 创建音量滑块组件
function CreateVolumeSlider(id, label, value, onChange)
    return UI.Panel {
        id = "volume_" .. id,
        width = "100%",
        gap = 6,
        children = {
            -- 标签行: 名称 + 数值
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = label,
                        fontSize = 13,
                        fontColor = COLORS.text,
                    },
                    UI.Label {
                        id = "volumeVal_" .. id,
                        text = tostring(value) .. "%",
                        fontSize = 13,
                        fontColor = COLORS.accent,
                    },
                }
            },
            -- 滑块
            UI.Slider {
                id = "slider_" .. id,
                width = "100%",
                value = value,
                min = 0,
                max = 100,
                onChange = function(self, val)
                    local rounded = math.floor(val + 0.5)
                    local valLabel = uiRoot:FindById("volumeVal_" .. id)
                    if valLabel then
                        valLabel:SetText(tostring(rounded) .. "%")
                    end
                    if onChange then onChange(rounded) end
                end,
            },
        }
    }
end

--- 应用音频设置
function ApplyAudioSettings()
    -- 设置引擎音频
    local masterGain = audioSettings.master / 100.0
    local musicGain = audioSettings.music / 100.0 * masterGain
    local sfxGain = audioSettings.sfx / 100.0 * masterGain
    
    -- 应用到引擎音频系统
    if audio then
        audio:SetMasterGain("Master", masterGain)
        audio:SetMasterGain("Music", musicGain)
        audio:SetMasterGain("Effect", sfxGain)
    end
    
    print(string.format("[Audio] Master: %d%%, Music: %d%%, SFX: %d%%",
        audioSettings.master, audioSettings.music, audioSettings.sfx))
end

-- ============================================================================
-- 游戏界面
-- ============================================================================

function StartGame()
    currentScene = "game"
    gameState = GameLogic.NewGame()
    GameLogic.StartNewRound(gameState)
    selectedCards = {}
    subPhase = "player_turn"
    
    CreateGameUI()
    RefreshUI()
    UpdateInfoLabel(string.format("选择要弃置的牌（至多%d张），或跳过", GameLogic.MAX_DISCARD[gameState.turnIndex]))
end

function CreateGameUI()
    uiRoot = UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        backgroundColor = COLORS.bg,
        children = {
            -- 顶部信息栏
            CreateTopBar(),
            -- 主游戏区域
            UI.Panel {
                id = "gameArea",
                flexGrow = 1,
                flexBasis = 0,
                width = "100%",
                padding = 16,
                gap = 12,
                justifyContent = "space-between",
                children = {
                    CreateAIArea(),
                    CreateMiddleArea(),
                    CreatePlayerArea(),
                }
            },
            -- 底部操作栏
            CreateBottomBar(),
        }
    }
    UI.SetRoot(uiRoot)
end

function CreateTopBar()
    return UI.Panel {
        id = "topBar",
        width = "100%",
        height = 50,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingHorizontal = 20,
        backgroundColor = COLORS.panel,
        borderColor = { 60, 75, 100, 100 },
        borderWidth = { 0, 0, 1, 0 },
        children = {
            UI.Panel {
                flexDirection = "row",
                gap = 12,
                alignItems = "center",
                children = {
                    UI.Button {
                        id = "backBtn",
                        text = "< 菜单",
                        fontSize = 12,
                        height = 30,
                        onClick = function() ShowMainMenu() end,
                    },
                    UI.Label {
                        id = "titleLabel",
                        text = "五!四!三!二十一点!",
                        fontSize = 16,
                        fontColor = COLORS.gold,
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
                        fontColor = COLORS.text,
                    },
                    UI.Label {
                        id = "roundLabel",
                        text = "第 0 局",
                        fontSize = 14,
                        fontColor = COLORS.textDim,
                    },
                }
            },
        }
    }
end

function CreateAIArea()
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
                fontColor = COLORS.textDim,
            },
            UI.Panel {
                id = "aiHandPanel",
                flexDirection = "row",
                gap = 6,
                flexWrap = "wrap",
                justifyContent = "center",
                children = {},
            },
        }
    }
end

function CreateMiddleArea()
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
                fontColor = COLORS.accent,
            },
            UI.Label {
                id = "infoLabel",
                text = "",
                fontSize = 13,
                fontColor = COLORS.textDim,
                textAlign = "center",
            },
            UI.Label {
                id = "pointsLabel",
                text = "",
                fontSize = 14,
                fontColor = COLORS.gold,
            },
        }
    }
end

function CreatePlayerArea()
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
                fontColor = COLORS.success,
            },
            UI.Panel {
                id = "playerHandPanel",
                flexDirection = "row",
                gap = 6,
                flexWrap = "wrap",
                justifyContent = "center",
                children = {},
            },
            UI.Label {
                id = "playerLabel",
                text = "我的手牌",
                fontSize = 13,
                fontColor = COLORS.textDim,
            },
        }
    }
end

function CreateBottomBar()
    return UI.Panel {
        id = "bottomBar",
        width = "100%",
        height = 60,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingHorizontal = 20,
        backgroundColor = COLORS.panel,
        borderColor = { 60, 75, 100, 100 },
        borderWidth = { 1, 0, 0, 0 },
        children = {
            -- 左侧: 牌堆查看按钮
            UI.Panel {
                flexDirection = "row",
                gap = 8,
                alignItems = "center",
                children = {
                    UI.Button {
                        id = "viewDiscardBtn",
                        text = "弃牌堆",
                        fontSize = 12,
                        height = 34,
                        backgroundColor = { 80, 50, 50, 200 },
                        borderRadius = 6,
                        onClick = function() ShowPileView("discard") end,
                    },
                    UI.Button {
                        id = "viewDeckBtn",
                        text = "抽牌堆",
                        fontSize = 12,
                        height = 34,
                        backgroundColor = { 50, 50, 80, 200 },
                        borderRadius = 6,
                        onClick = function() ShowPileView("deck") end,
                    },
                }
            },
            -- 中间: 操作按钮
            UI.Panel {
                flexDirection = "row",
                gap = 12,
                alignItems = "center",
                children = {
                    UI.Button {
                        id = "actionBtn",
                        text = "确认",
                        variant = "primary",
                        onClick = function() OnActionButton() end,
                    },
                    UI.Button {
                        id = "skipBtn",
                        text = "跳过",
                        visible = false,
                        onClick = function() OnSkipButton() end,
                    },
                }
            },
            -- 右侧占位(保持居中)
            UI.Panel { width = 120 },
        }
    }
end

-- ============================================================================
-- 卡牌UI组件
-- ============================================================================

function CreateCardWidget(card, index, faceDown, selectable)
    local isSelected = selectedCards[index] == true
    local bgColor = isSelected and COLORS.cardSelected or COLORS.cardBg
    
    local cardContent
    if faceDown then
        cardContent = {
            UI.Label {
                text = "🂠",
                fontSize = 28,
                fontColor = { 80, 100, 140, 255 },
                textAlign = "center",
            }
        }
    else
        local suitColor = COLORS.black
        local suitSymbol = ""
        local rankText = ""
        
        if CardDefs.IsJoker(card) then
            suitColor = COLORS.jokerPurple
            suitSymbol = "🃏"
            rankText = card.rank == 14 and "小" or "大"
        else
            suitColor = CardDefs.SUIT_COLORS[card.suit] or COLORS.black
            suitSymbol = CardDefs.SUIT_SYMBOLS[card.suit] or "?"
            rankText = CardDefs.RANK_NAMES[card.rank] or "?"
        end
        
        cardContent = {
            UI.Label {
                text = rankText,
                fontSize = 14,
                fontColor = suitColor,
                textAlign = "center",
            },
            UI.Label {
                text = suitSymbol,
                fontSize = 20,
                fontColor = suitColor,
                textAlign = "center",
            },
        }
    end
    
    local cardWidget = UI.Panel {
        width = 52,
        height = 72,
        backgroundColor = bgColor,
        borderRadius = 6,
        borderWidth = isSelected and 2 or 1,
        borderColor = isSelected and COLORS.accent or { 180, 180, 180, 150 },
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        pointerEvents = selectable and "auto" or "none",
        children = cardContent,
    }
    
    if selectable then
        cardWidget:OnEvent("click", function()
            ToggleCardSelection(index)
        end)
    end
    
    return cardWidget
end

-- ============================================================================
-- UI 更新 (游戏中)
-- ============================================================================

function RefreshUI()
    if not gameState or currentScene ~= "game" then return end
    
    local scoreLabel = uiRoot:FindById("scoreLabel")
    if scoreLabel then
        scoreLabel:SetText(string.format("比分: %d - %d", gameState.playerWins, gameState.aiWins))
    end
    local roundLabel = uiRoot:FindById("roundLabel")
    if roundLabel then
        roundLabel:SetText(string.format("第 %d 局", gameState.roundNumber))
    end
    
    local phaseLabel = uiRoot:FindById("phaseLabel")
    if phaseLabel then
        phaseLabel:SetText(GetPhaseText())
    end
    
    RefreshPlayerHand()
    RefreshAIHand()
    
    local playerPointsLabel = uiRoot:FindById("playerPointsLabel")
    if playerPointsLabel and #gameState.playerHand > 0 then
        local pts = 0
        for _, card in ipairs(gameState.playerHand) do
            pts = pts + CardDefs.GetBasePoints(card)
        end
        playerPointsLabel:SetText(string.format("当前点数: %d", pts))
    elseif playerPointsLabel then
        playerPointsLabel:SetText("")
    end
    
    RefreshButtons()
end

function RefreshPlayerHand()
    local panel = uiRoot:FindById("playerHandPanel")
    if not panel then return end
    panel:ClearChildren()
    
    local phase = gameState.phase
    local selectable = (phase == GameLogic.PHASE.DRAW_FIVE or
                       phase == GameLogic.PHASE.DRAW_FOUR or
                       phase == GameLogic.PHASE.DRAW_THREE or
                       phase == GameLogic.PHASE.POST_GAME or
                       phase == GameLogic.PHASE.JOKER_EFFECT)
                       and subPhase == "player_turn"
    
    for i, card in ipairs(gameState.playerHand) do
        local cardWidget = CreateCardWidget(card, i, false, selectable)
        panel:AddChild(cardWidget)
    end
end

function RefreshAIHand()
    local panel = uiRoot:FindById("aiHandPanel")
    if not panel then return end
    panel:ClearChildren()
    
    local showCards = (gameState.phase == GameLogic.PHASE.SETTLEMENT or
                      gameState.phase == GameLogic.PHASE.POST_GAME or
                      gameState.phase == GameLogic.PHASE.ROUND_END)
    
    for i, card in ipairs(gameState.aiHand) do
        local cardWidget = CreateCardWidget(card, i, not showCards, false)
        panel:AddChild(cardWidget)
    end
end

function RefreshButtons()
    local actionBtn = uiRoot:FindById("actionBtn")
    local skipBtn = uiRoot:FindById("skipBtn")
    if not actionBtn then return end
    
    local phase = gameState.phase
    
    if phase == GameLogic.PHASE.GAME_OVER then
        actionBtn:SetText("返回主菜单")
        actionBtn:SetVisible(true)
        if skipBtn then skipBtn:SetVisible(false) end
    elseif phase == GameLogic.PHASE.DRAW_FIVE or
           phase == GameLogic.PHASE.DRAW_FOUR or
           phase == GameLogic.PHASE.DRAW_THREE then
        if subPhase == "player_turn" then
            local max = GameLogic.MAX_DISCARD[gameState.turnIndex]
            local count = CountSelected()
            actionBtn:SetText(string.format("弃置 (%d/%d)", count, max))
            actionBtn:SetVisible(true)
            actionBtn:SetDisabled(false)
            if skipBtn then
                skipBtn:SetVisible(true)
                skipBtn:SetText("不弃牌")
            end
        else
            actionBtn:SetVisible(false)
            if skipBtn then skipBtn:SetVisible(false) end
        end
    elseif phase == GameLogic.PHASE.JOKER_EFFECT then
        if subPhase == "player_turn" then
            actionBtn:SetText("进入结算")
            actionBtn:SetVisible(true)
            if skipBtn then skipBtn:SetVisible(false) end
        else
            actionBtn:SetVisible(false)
            if skipBtn then skipBtn:SetVisible(false) end
        end
    elseif phase == GameLogic.PHASE.POST_GAME then
        if postPhase == "discard" then
            local count = CountSelected()
            actionBtn:SetText(string.format("弃置至牌堆 (%d/2)", count))
            actionBtn:SetVisible(true)
            if skipBtn then skipBtn:SetText("跳过"); skipBtn:SetVisible(true) end
        elseif postPhase == "keep" then
            local count = CountSelected()
            actionBtn:SetText(string.format("保留至下局 (%d/1)", count))
            actionBtn:SetVisible(true)
            if skipBtn then skipBtn:SetText("不保留"); skipBtn:SetVisible(true) end
        end
    elseif phase == GameLogic.PHASE.ROUND_END then
        if GameLogic.IsGameOver(gameState) then
            actionBtn:SetText("查看结果")
        else
            actionBtn:SetText("下一局")
        end
        actionBtn:SetVisible(true)
        if skipBtn then skipBtn:SetVisible(false) end
    elseif phase == GameLogic.PHASE.SETTLEMENT then
        actionBtn:SetText("继续")
        actionBtn:SetVisible(true)
        if skipBtn then skipBtn:SetVisible(false) end
    else
        actionBtn:SetVisible(false)
        if skipBtn then skipBtn:SetVisible(false) end
    end
end

function GetPhaseText()
    local phase = gameState.phase
    if phase == GameLogic.PHASE.DRAW_FIVE then return "第一回合 - 五!"
    elseif phase == GameLogic.PHASE.DRAW_FOUR then return "第二回合 - 四!"
    elseif phase == GameLogic.PHASE.DRAW_THREE then return "第三回合 - 三!"
    elseif phase == GameLogic.PHASE.JOKER_EFFECT then return "鬼牌效果阶段"
    elseif phase == GameLogic.PHASE.SETTLEMENT then return "结算"
    elseif phase == GameLogic.PHASE.POST_GAME then
        if postPhase == "discard" then return "二! - 选至多2张弃置至牌堆"
        else return "一! - 选至多1张保留至下局" end
    elseif phase == GameLogic.PHASE.ROUND_END then return "本局结束"
    elseif phase == GameLogic.PHASE.GAME_OVER then return "游戏结束"
    end
    return ""
end

function UpdateInfoLabel(text)
    local infoLabel = uiRoot:FindById("infoLabel")
    if infoLabel then
        infoLabel:SetText(text)
    end
end

-- ============================================================================
-- 游戏逻辑交互
-- ============================================================================

function ToggleCardSelection(index)
    if selectedCards[index] then
        selectedCards[index] = nil
    else
        local phase = gameState.phase
        local maxSelect = 5
        
        if phase == GameLogic.PHASE.DRAW_FIVE or
           phase == GameLogic.PHASE.DRAW_FOUR or
           phase == GameLogic.PHASE.DRAW_THREE then
            maxSelect = GameLogic.MAX_DISCARD[gameState.turnIndex]
        elseif phase == GameLogic.PHASE.POST_GAME then
            maxSelect = postPhase == "discard" and 2 or 1
        elseif phase == GameLogic.PHASE.JOKER_EFFECT then
            maxSelect = 1
        end
        
        -- 7不可选(弃牌阶段)
        if phase == GameLogic.PHASE.DRAW_FIVE or
           phase == GameLogic.PHASE.DRAW_FOUR or
           phase == GameLogic.PHASE.DRAW_THREE then
            local card = gameState.playerHand[index]
            if card and card.rank == 7 then
                UpdateInfoLabel("7 无法被弃置!")
                return
            end
        end
        
        if CountSelected() >= maxSelect then
            UpdateInfoLabel(string.format("最多选择 %d 张牌", maxSelect))
            return
        end
        
        selectedCards[index] = true
    end
    RefreshUI()
end

function CountSelected()
    local count = 0
    for _, v in pairs(selectedCards) do
        if v then count = count + 1 end
    end
    return count
end

function GetSelectedIndices()
    local indices = {}
    for idx, v in pairs(selectedCards) do
        if v then table.insert(indices, idx) end
    end
    return indices
end

-- ============================================================================
-- 按钮回调
-- ============================================================================

function OnActionButton()
    local phase = gameState.phase
    
    if phase == GameLogic.PHASE.GAME_OVER then
        ShowMainMenu()
        return
    end
    
    if phase == GameLogic.PHASE.DRAW_FIVE or
       phase == GameLogic.PHASE.DRAW_FOUR or
       phase == GameLogic.PHASE.DRAW_THREE then
        local indices = GetSelectedIndices()
        local success, err = GameLogic.PlayerDiscard(gameState, indices)
        if not success then
            UpdateInfoLabel(err)
            return
        end
        selectedCards = {}
        RefreshUI()
        
        -- 检查是否有J待处理(玩家选牌)
        if gameState.pendingJackPicks and gameState.pendingJackPicks > 0 then
            ShowJackPickUI()
            return
        end
        
        -- 没有J效果，直接进入AI回合
        subPhase = "ai_turn"
        
        local aiIndices = AIPlayer.DecideDiscard(gameState.aiHand, gameState.turnIndex)
        GameLogic.AIDiscard(gameState, aiIndices)
        
        GameLogic.NextTurn(gameState)
        subPhase = "player_turn"
        
        if gameState.phase == GameLogic.PHASE.JOKER_EFFECT then
            HandleJokerPhase()
        else
            UpdateInfoLabel(string.format("选择要弃置的牌（至多%d张），或跳过",
                GameLogic.MAX_DISCARD[gameState.turnIndex]))
        end
        RefreshUI()
        return
    end
    
    if phase == GameLogic.PHASE.JOKER_EFFECT then
        HandleJokerEffects()
        DoSettlement()
        return
    end
    
    if phase == GameLogic.PHASE.SETTLEMENT then
        gameState.phase = GameLogic.PHASE.POST_GAME
        postPhase = "discard"
        selectedCards = {}
        subPhase = "player_turn"
        UpdateInfoLabel("选择至多2张牌弃置至你的抽牌堆")
        RefreshUI()
        return
    end
    
    if phase == GameLogic.PHASE.POST_GAME then
        if postPhase == "discard" then
            local indices = GetSelectedIndices()
            if #indices > 2 then
                UpdateInfoLabel("最多弃置2张!")
                return
            end
            -- 强制弃鬼牌
            local i = 1
            while i <= #gameState.playerHand do
                if CardDefs.IsJoker(gameState.playerHand[i]) then
                    local card = table.remove(gameState.playerHand, i)
                    table.insert(gameState.discardPile, card)
                else
                    i = i + 1
                end
            end
            table.sort(indices, function(a, b) return a > b end)
            for _, idx in ipairs(indices) do
                if idx >= 1 and idx <= #gameState.playerHand then
                    local card = table.remove(gameState.playerHand, idx)
                    table.insert(gameState.playerDeck, card)
                end
            end
            selectedCards = {}
            postPhase = "keep"
            UpdateInfoLabel("选择至多1张牌保留至下一局")
            RefreshUI()
        elseif postPhase == "keep" then
            local indices = GetSelectedIndices()
            if #indices > 1 then
                UpdateInfoLabel("最多保留1张!")
                return
            end
            if #indices == 1 then
                local idx = indices[1]
                if idx >= 1 and idx <= #gameState.playerHand then
                    gameState.playerKeep = table.remove(gameState.playerHand, idx)
                end
            end
            for _, card in ipairs(gameState.playerHand) do
                table.insert(gameState.discardPile, card)
            end
            gameState.playerHand = {}
            GameLogic.PostGameAIChoice(gameState)
            selectedCards = {}
            
            if GameLogic.IsGameOver(gameState) then
                gameState.phase = GameLogic.PHASE.GAME_OVER
                local winner = gameState.playerWins >= 3 and "玩家" or "AI"
                UpdateInfoLabel(string.format("游戏结束! %s获胜!\n最终比分: %d - %d",
                    winner, gameState.playerWins, gameState.aiWins))
            else
                gameState.phase = GameLogic.PHASE.ROUND_END
                UpdateInfoLabel("本局结束，准备下一局")
            end
            RefreshUI()
        end
        return
    end
    
    if phase == GameLogic.PHASE.ROUND_END then
        if GameLogic.IsGameOver(gameState) then
            gameState.phase = GameLogic.PHASE.GAME_OVER
            local winner = gameState.playerWins >= 3 and "玩家" or "AI"
            UpdateInfoLabel(string.format("游戏结束! %s获胜!\n最终比分: %d - %d",
                winner, gameState.playerWins, gameState.aiWins))
        else
            GameLogic.StartNewRound(gameState)
            selectedCards = {}
            subPhase = "player_turn"
            UpdateInfoLabel(string.format("选择要弃置的牌（至多%d张），或跳过",
                GameLogic.MAX_DISCARD[gameState.turnIndex]))
        end
        RefreshUI()
        return
    end
end

function OnSkipButton()
    local phase = gameState.phase
    
    if phase == GameLogic.PHASE.DRAW_FIVE or
       phase == GameLogic.PHASE.DRAW_FOUR or
       phase == GameLogic.PHASE.DRAW_THREE then
        selectedCards = {}
        GameLogic.AddLog(gameState, "玩家选择不弃牌")
        
        local aiIndices = AIPlayer.DecideDiscard(gameState.aiHand, gameState.turnIndex)
        GameLogic.AIDiscard(gameState, aiIndices)
        
        GameLogic.NextTurn(gameState)
        subPhase = "player_turn"
        
        if gameState.phase == GameLogic.PHASE.JOKER_EFFECT then
            HandleJokerPhase()
        else
            UpdateInfoLabel(string.format("选择要弃置的牌（至多%d张），或跳过",
                GameLogic.MAX_DISCARD[gameState.turnIndex]))
        end
        RefreshUI()
        return
    end
    
    if phase == GameLogic.PHASE.POST_GAME then
        if postPhase == "discard" then
            local i = 1
            while i <= #gameState.playerHand do
                if CardDefs.IsJoker(gameState.playerHand[i]) then
                    local card = table.remove(gameState.playerHand, i)
                    table.insert(gameState.discardPile, card)
                else
                    i = i + 1
                end
            end
            selectedCards = {}
            postPhase = "keep"
            UpdateInfoLabel("选择至多1张牌保留至下一局")
            RefreshUI()
        elseif postPhase == "keep" then
            for _, card in ipairs(gameState.playerHand) do
                table.insert(gameState.discardPile, card)
            end
            gameState.playerHand = {}
            GameLogic.PostGameAIChoice(gameState)
            selectedCards = {}
            
            if GameLogic.IsGameOver(gameState) then
                gameState.phase = GameLogic.PHASE.GAME_OVER
                local winner = gameState.playerWins >= 3 and "玩家" or "AI"
                UpdateInfoLabel(string.format("游戏结束! %s获胜!\n最终比分: %d - %d",
                    winner, gameState.playerWins, gameState.aiWins))
            else
                gameState.phase = GameLogic.PHASE.ROUND_END
                UpdateInfoLabel("本局结束，准备下一局")
            end
            RefreshUI()
        end
        return
    end
    
    if phase == GameLogic.PHASE.JOKER_EFFECT then
        HandleJokerEffects()
        DoSettlement()
        return
    end
end

-- ============================================================================
-- 鬼牌效果处理
-- ============================================================================

function HandleJokerPhase()
    local hasJoker = false
    for _, card in ipairs(gameState.playerHand) do
        if CardDefs.IsJoker(card) then
            hasJoker = true
            break
        end
    end
    
    if hasJoker then
        jokerPhase = "pending"
        subPhase = "player_turn"
        UpdateInfoLabel("你有鬼牌! 点击'进入结算'自动处理鬼牌效果")
    else
        HandleJokerEffects()
        DoSettlement()
    end
end

function HandleJokerEffects()
    -- 玩家鬼牌自动设最优点数
    local nonJokerPts = 0
    local jokerCount = 0
    for _, card in ipairs(gameState.playerHand) do
        if CardDefs.IsJoker(card) then
            jokerCount = jokerCount + 1
        else
            nonJokerPts = nonJokerPts + CardDefs.GetBasePoints(card)
        end
    end
    
    if jokerCount > 0 then
        local remaining = math.max(0, 21 - nonJokerPts)
        local perJoker = math.floor(remaining / jokerCount)
        perJoker = math.max(0, math.min(13, perJoker))
        local extra = remaining - perJoker * jokerCount
        
        local first = true
        for _, card in ipairs(gameState.playerHand) do
            if CardDefs.IsJoker(card) then
                if first and extra > 0 then
                    card.jokerValue = math.min(13, perJoker + extra)
                    first = false
                else
                    card.jokerValue = perJoker
                    first = false
                end
            end
        end
    end
    
    -- AI鬼牌
    local aiDecisions = AIPlayer.DecideJokerEffects(gameState.aiHand, gameState.playerHand)
    for idx, val in pairs(aiDecisions.jokerValues) do
        if gameState.aiHand[idx] then
            gameState.aiHand[idx].jokerValue = val
        end
    end
    
    -- 玩家小王: 移除对方一张牌
    for _, card in ipairs(gameState.playerHand) do
        if card.rank == 14 then
            local bestIdx, bestPts = nil, -1
            for i, c in ipairs(gameState.aiHand) do
                local pts = CardDefs.GetBasePoints(c)
                if pts > bestPts and c.rank ~= 7 then
                    bestPts = pts
                    bestIdx = i
                end
            end
            if bestIdx then
                local removed = table.remove(gameState.aiHand, bestIdx)
                table.insert(gameState.discardPile, removed)
                GameLogic.AddLog(gameState, "小王效果: 移除AI的 " .. CardDefs.GetCardName(removed))
            end
            break
        end
    end
    
    -- AI小王
    if aiDecisions.smallJokerTarget then
        for _, card in ipairs(gameState.aiHand) do
            if card.rank == 14 then
                local idx = aiDecisions.smallJokerTarget
                if idx and idx >= 1 and idx <= #gameState.playerHand then
                    local removed = table.remove(gameState.playerHand, idx)
                    table.insert(gameState.discardPile, removed)
                    GameLogic.AddLog(gameState, "AI小王效果: 移除玩家的 " .. CardDefs.GetCardName(removed))
                end
                break
            end
        end
    end
end

function DoSettlement()
    local result = GameLogic.DoSettlement(gameState)
    
    local resultText = ""
    if result.sevenRuleTriggered then
        resultText = "三7特殊规则触发! "
    end
    
    if result.winner == "player" then
        resultText = resultText .. string.format("你赢了! (%d点 vs %d点)", result.playerPoints, result.aiPoints)
    elseif result.winner == "ai" then
        resultText = resultText .. string.format("AI赢了! (%d点 vs %d点)", result.playerPoints, result.aiPoints)
    else
        resultText = resultText .. string.format("平局! (%d点 vs %d点)", result.playerPoints, result.aiPoints)
    end
    
    UpdateInfoLabel(resultText)
    selectedCards = {}
    RefreshUI()
end

-- ============================================================================
-- 牌堆查看 / J效果选牌 UI
-- ============================================================================

--- 显示牌堆查看弹窗
---@param pileType string "discard" 或 "deck"
function ShowPileView(pileType)
    if not gameState then return end
    viewingPile = pileType
    
    local pile
    local title
    if pileType == "discard" then
        pile = gameState.discardPile
        title = "弃牌堆"
    elseif pileType == "deck" then
        pile = gameState.playerDeck
        title = "抽牌堆"
    else
        return
    end
    
    local cardWidgets = {}
    if #pile == 0 then
        table.insert(cardWidgets, UI.Label {
            text = "（空）",
            fontSize = 14,
            fontColor = COLORS.textDim,
        })
    else
        for i, card in ipairs(pile) do
            table.insert(cardWidgets, CreateCardWidget(card, i, false, false))
        end
    end
    
    -- 创建弹窗覆盖层
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
                backgroundColor = COLORS.menuCard,
                borderRadius = 12,
                borderWidth = 1,
                borderColor = COLORS.menuBorder,
                padding = 20,
                gap = 12,
                alignItems = "center",
                children = {
                    -- 标题行
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = title .. string.format(" (%d张)", #pile),
                                fontSize = 16,
                                fontColor = COLORS.gold,
                            },
                            UI.Button {
                                text = "关闭",
                                fontSize = 12,
                                height = 30,
                                onClick = function() ClosePileView() end,
                            },
                        }
                    },
                    -- 分隔线
                    UI.Panel {
                        width = "100%",
                        height = 1,
                        backgroundColor = COLORS.menuBorder,
                    },
                    -- 牌列表
                    UI.ScrollView {
                        width = "100%",
                        flexGrow = 1,
                        flexBasis = 0,
                        children = {
                            UI.Panel {
                                id = "pileCards",
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

--- 关闭牌堆查看弹窗
function ClosePileView()
    viewingPile = nil
    local overlay = uiRoot:FindById("pileOverlay")
    if overlay then
        overlay:Remove()
    end
end

--- 显示J效果选牌堆弹窗(选择从弃牌堆还是抽牌堆随机抽一张)
function ShowJackPickUI()
    subPhase = "jack_pick"
    
    local discardCount = #gameState.discardPile
    local deckCount = #gameState.playerDeck
    local remaining = gameState.pendingJackPicks or 0
    
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
                backgroundColor = COLORS.menuCard,
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 150, 80, 200, 150 },
                padding = 24,
                gap = 16,
                alignItems = "center",
                children = {
                    -- 标题
                    UI.Label {
                        text = "J 弃置效果",
                        fontSize = 18,
                        fontColor = COLORS.jokerPurple,
                    },
                    UI.Label {
                        text = string.format("选择一个牌堆随机抽取一张牌\n(剩余 %d 次)", remaining),
                        fontSize = 13,
                        fontColor = COLORS.textDim,
                        textAlign = "center",
                    },
                    -- 两个选择按钮
                    UI.Button {
                        text = string.format("从弃牌堆抽 (%d张)", discardCount),
                        width = "100%",
                        height = 44,
                        fontSize = 14,
                        backgroundColor = { 100, 45, 45, 220 },
                        borderRadius = 8,
                        disabled = discardCount == 0,
                        onClick = function() OnJackPickChoice("discard") end,
                    },
                    UI.Button {
                        text = string.format("从抽牌堆抽 (%d张)", deckCount),
                        width = "100%",
                        height = 44,
                        fontSize = 14,
                        backgroundColor = { 45, 45, 100, 220 },
                        borderRadius = 8,
                        disabled = deckCount == 0,
                        onClick = function() OnJackPickChoice("deck") end,
                    },
                }
            },
        }
    }
    
    uiRoot:AddChild(overlay)
end

--- J效果: 玩家选择了牌堆
function OnJackPickChoice(source)
    local success, err, card = GameLogic.PlayerJackPick(gameState, source)
    if not success then
        UpdateInfoLabel(err or "抽取失败")
        return
    end
    
    -- 关闭弹窗
    local overlay = uiRoot:FindById("jackPickOverlay")
    if overlay then overlay:Remove() end
    
    -- 显示抽到的牌
    local cardName = card and CardDefs.GetCardName(card) or "?"
    UpdateInfoLabel(string.format("J效果: 从%s中随机抽到 %s",
        source == "discard" and "弃牌堆" or "抽牌堆", cardName))
    
    -- 还有J待处理?
    if gameState.pendingJackPicks and gameState.pendingJackPicks > 0 then
        RefreshUI()
        ShowJackPickUI()
    else
        -- J效果全部处理完毕，继续AI回合
        subPhase = "ai_turn"
        FinishPlayerTurnAfterJack()
    end
end

--- J效果处理完后继续游戏流程
function FinishPlayerTurnAfterJack()
    local aiIndices = AIPlayer.DecideDiscard(gameState.aiHand, gameState.turnIndex)
    GameLogic.AIDiscard(gameState, aiIndices)
    
    GameLogic.NextTurn(gameState)
    subPhase = "player_turn"
    
    if gameState.phase == GameLogic.PHASE.JOKER_EFFECT then
        HandleJokerPhase()
    else
        UpdateInfoLabel(string.format("选择要弃置的牌（至多%d张），或跳过",
            GameLogic.MAX_DISCARD[gameState.turnIndex]))
    end
    RefreshUI()
end

-- ============================================================================
-- 事件处理
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_ESCAPE then
        -- 先关闭弹窗
        if viewingPile then
            ClosePileView()
            return
        end
        local jackOverlay = uiRoot and uiRoot:FindById("jackPickOverlay")
        if jackOverlay then
            return -- J选牌时不允许ESC退出
        end
        
        if currentScene == "game" then
            ShowMainMenu()
        elseif currentScene == "settings" then
            ShowMainMenu()
        end
    end
end
