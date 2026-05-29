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

-- UI 引用
local refs = {}

-- 游戏子阶段
local subPhase = "player_turn"  -- player_turn / ai_turn / waiting
local postPhase = "discard"     -- discard / keep (结算后子阶段)
local jokerPhase = "pending"    -- pending / small_joker_pick / big_joker_pick / done
local smallJokerTargetIdx = nil
local bigJokerTargetIdx = nil
local bigJokerValue = nil

-- ============================================================================
-- 颜色定义
-- ============================================================================
local COLORS = {
    bg = { 25, 32, 45, 255 },
    cardBg = { 255, 252, 245, 255 },
    cardSelected = { 180, 230, 255, 255 },
    cardHover = { 240, 245, 255, 255 },
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
    
    -- 初始化游戏
    gameState = GameLogic.NewGame()
    
    -- 创建UI
    CreateUI()
    
    -- 显示开始界面
    ShowStartScreen()
    
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    
    print("=== 五!四!三!二十一点! ===")
end

function Stop()
    UI.Shutdown()
end

-- ============================================================================
-- UI 创建
-- ============================================================================

function CreateUI()
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
                    -- AI 手牌区域
                    CreateAIArea(),
                    -- 中间信息区
                    CreateMiddleArea(),
                    -- 玩家手牌区域
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
            UI.Label {
                id = "titleLabel",
                text = "五!四!三!二十一点!",
                fontSize = 16,
                fontColor = COLORS.gold,
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
                text = "准备开始游戏",
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
        justifyContent = "center",
        gap = 12,
        paddingHorizontal = 20,
        backgroundColor = COLORS.panel,
        borderColor = { 60, 75, 100, 100 },
        borderWidth = { 1, 0, 0, 0 },
        children = {
            UI.Button {
                id = "actionBtn",
                text = "开始游戏",
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
    }
end

-- ============================================================================
-- 卡牌UI组件
-- ============================================================================

--- 创建一张牌的UI
---@param card table 卡牌数据
---@param index number 手牌中的索引
---@param faceDown boolean 是否背面朝上
---@param selectable boolean 是否可选
---@return table Widget
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
        transition = "scale 0.15s easeOut, backgroundColor 0.15s easeOut",
        children = cardContent,
    }
    
    if selectable then
        cardWidget:OnEvent("click", function()
            ToggleCardSelection(index)
        end)
        cardWidget:OnEvent("pointerenter", function(_, w)
            if not selectedCards[index] then
                w:SetStyle({ scale = 1.05 })
            end
        end)
        cardWidget:OnEvent("pointerleave", function(_, w)
            if not selectedCards[index] then
                w:SetStyle({ scale = 1.0 })
            end
        end)
    end
    
    return cardWidget
end

-- ============================================================================
-- UI 更新
-- ============================================================================

function RefreshUI()
    if not gameState then return end
    
    -- 更新分数和回合
    local scoreLabel = uiRoot:FindById("scoreLabel")
    if scoreLabel then
        scoreLabel:SetText(string.format("比分: %d - %d", gameState.playerWins, gameState.aiWins))
    end
    local roundLabel = uiRoot:FindById("roundLabel")
    if roundLabel then
        roundLabel:SetText(string.format("第 %d 局", gameState.roundNumber))
    end
    
    -- 更新阶段提示
    local phaseLabel = uiRoot:FindById("phaseLabel")
    if phaseLabel then
        local phaseText = GetPhaseText()
        phaseLabel:SetText(phaseText)
    end
    
    -- 更新玩家手牌
    RefreshPlayerHand()
    
    -- 更新AI手牌
    RefreshAIHand()
    
    -- 更新玩家点数
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
    
    -- 更新按钮
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
        actionBtn:SetText("重新开始")
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
            if jokerPhase == "small_joker_pick" then
                actionBtn:SetText("移除选中的对方牌")
                actionBtn:SetVisible(true)
                if skipBtn then skipBtn:SetText("跳过"); skipBtn:SetVisible(true) end
            elseif jokerPhase == "big_joker_pick" then
                actionBtn:SetText("确认修改")
                actionBtn:SetVisible(true)
                if skipBtn then skipBtn:SetVisible(false) end
            else
                actionBtn:SetText("进入结算")
                actionBtn:SetVisible(true)
                if skipBtn then skipBtn:SetVisible(false) end
            end
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
    if phase == GameLogic.PHASE.DRAW_FIVE then
        return "第一回合 - 五!"
    elseif phase == GameLogic.PHASE.DRAW_FOUR then
        return "第二回合 - 四!"
    elseif phase == GameLogic.PHASE.DRAW_THREE then
        return "第三回合 - 三!"
    elseif phase == GameLogic.PHASE.JOKER_EFFECT then
        return "鬼牌效果阶段"
    elseif phase == GameLogic.PHASE.SETTLEMENT then
        return "结算"
    elseif phase == GameLogic.PHASE.POST_GAME then
        if postPhase == "discard" then
            return "二! - 选至多2张弃置至牌堆"
        else
            return "一! - 选至多1张保留至下局"
        end
    elseif phase == GameLogic.PHASE.ROUND_END then
        return "本局结束"
    elseif phase == GameLogic.PHASE.GAME_OVER then
        return "游戏结束"
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

function ShowStartScreen()
    UpdateInfoLabel("经典21点改版 · 5局3胜\n每回合可弃牌换牌，比谁更接近21点")
    local actionBtn = uiRoot:FindById("actionBtn")
    if actionBtn then
        actionBtn:SetText("开始游戏")
        actionBtn:SetVisible(true)
    end
end

function StartGame()
    gameState = GameLogic.NewGame()
    GameLogic.StartNewRound(gameState)
    selectedCards = {}
    subPhase = "player_turn"
    RefreshUI()
    UpdateInfoLabel(string.format("选择要弃置的牌（至多%d张），或跳过", GameLogic.MAX_DISCARD[gameState.turnIndex]))
end

function ToggleCardSelection(index)
    if selectedCards[index] then
        selectedCards[index] = nil
    else
        -- 检查选中数量限制
        local phase = gameState.phase
        local maxSelect = 5
        
        if phase == GameLogic.PHASE.DRAW_FIVE or
           phase == GameLogic.PHASE.DRAW_FOUR or
           phase == GameLogic.PHASE.DRAW_THREE then
            maxSelect = GameLogic.MAX_DISCARD[gameState.turnIndex]
        elseif phase == GameLogic.PHASE.POST_GAME then
            if postPhase == "discard" then
                maxSelect = 2
            else
                maxSelect = 1
            end
        elseif phase == GameLogic.PHASE.JOKER_EFFECT then
            maxSelect = 1
        end
        
        -- 检查7不可选(弃牌阶段)
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
    
    if phase == GameLogic.PHASE.INIT or phase == nil then
        StartGame()
        return
    end
    
    if phase == GameLogic.PHASE.GAME_OVER then
        StartGame()
        return
    end
    
    if phase == GameLogic.PHASE.DRAW_FIVE or
       phase == GameLogic.PHASE.DRAW_FOUR or
       phase == GameLogic.PHASE.DRAW_THREE then
        -- 玩家弃牌
        local indices = GetSelectedIndices()
        local success, err = GameLogic.PlayerDiscard(gameState, indices)
        if not success then
            UpdateInfoLabel(err)
            return
        end
        selectedCards = {}
        
        -- AI回合
        subPhase = "ai_turn"
        RefreshUI()
        UpdateInfoLabel("AI思考中...")
        
        -- AI弃牌
        local aiIndices = AIPlayer.DecideDiscard(gameState.aiHand, gameState.turnIndex)
        GameLogic.AIDiscard(gameState, aiIndices)
        
        -- 进入下一回合
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
        -- 直接进入结算(简化鬼牌处理)
        HandleJokerEffects()
        DoSettlement()
        return
    end
    
    if phase == GameLogic.PHASE.SETTLEMENT then
        -- 进入结算后阶段
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
            -- 弃置选中的牌
            local indices = GetSelectedIndices()
            if #indices > 2 then
                UpdateInfoLabel("最多弃置2张!")
                return
            end
            -- 强制弃鬼牌先
            local i = 1
            while i <= #gameState.playerHand do
                if CardDefs.IsJoker(gameState.playerHand[i]) then
                    local card = table.remove(gameState.playerHand, i)
                    table.insert(gameState.discardPile, card)
                    GameLogic.AddLog(gameState, "强制弃置: " .. CardDefs.GetCardName(card))
                else
                    i = i + 1
                end
            end
            -- 弃置选中的牌到抽牌堆
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
            -- 保留选中的牌
            local indices = GetSelectedIndices()
            if #indices > 1 then
                UpdateInfoLabel("最多保留1张!")
                return
            end
            if #indices == 1 then
                local idx = indices[1]
                if idx >= 1 and idx <= #gameState.playerHand then
                    gameState.playerKeep = table.remove(gameState.playerHand, idx)
                    GameLogic.AddLog(gameState, "保留: " .. CardDefs.GetCardName(gameState.playerKeep))
                end
            end
            -- 剩余放入弃牌堆
            for _, card in ipairs(gameState.playerHand) do
                table.insert(gameState.discardPile, card)
            end
            gameState.playerHand = {}
            
            -- AI结算后选择
            GameLogic.PostGameAIChoice(gameState)
            
            selectedCards = {}
            
            -- 检查游戏是否结束
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
            -- 开始下一局
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
        -- 不弃牌，直接到AI回合
        selectedCards = {}
        GameLogic.AddLog(gameState, "玩家选择不弃牌")
        
        -- AI弃牌
        local aiIndices = AIPlayer.DecideDiscard(gameState.aiHand, gameState.turnIndex)
        GameLogic.AIDiscard(gameState, aiIndices)
        
        -- 下一回合
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
            -- 跳过弃置，强制弃鬼牌
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
            -- 不保留, 剩余放弃牌堆
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
        -- 跳过鬼牌效果
        HandleJokerEffects()
        DoSettlement()
        return
    end
end

-- ============================================================================
-- 鬼牌效果处理
-- ============================================================================

function HandleJokerPhase()
    -- 检查玩家是否有鬼牌
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
        -- 无鬼牌直接结算
        HandleJokerEffects()
        DoSettlement()
    end
end

function HandleJokerEffects()
    -- 自动处理鬼牌: 设置最优点数
    -- 玩家鬼牌
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
                GameLogic.AddLog(gameState, string.format("%s 设为 %d 点",
                    CardDefs.GetCardName(card), card.jokerValue))
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
    
    -- 小王效果: 移除对方一张牌
    for _, card in ipairs(gameState.playerHand) do
        if card.rank == 14 then -- 玩家小王
            -- 自动选择对方点数最高的非7牌移除
            local bestIdx = nil
            local bestPts = -1
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
    
    -- AI小王效果
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
-- 事件处理
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    -- 游戏更新逻辑 (动画等)
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_ESCAPE then
        -- ESC退出
    end
end
