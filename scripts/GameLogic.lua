-- ============================================================================
-- GameLogic.lua - 游戏核心逻辑
-- "五！四！三！二十一点！" 流程管理与结算
-- ============================================================================

local CardDefs = require("CardDefs")

local GameLogic = {}

-- 游戏阶段
GameLogic.PHASE = {
    INIT = "init",              -- 初始化
    DRAW_FIVE = "draw_five",    -- 第一回合: 弃至多5张再抽5张
    DRAW_FOUR = "draw_four",    -- 第二回合: 弃至多4张再抽4张
    DRAW_THREE = "draw_three",  -- 第三回合: 弃至多3张再抽3张
    JOKER_EFFECT = "joker_effect", -- 鬼牌效果阶段
    SETTLEMENT = "settlement",  -- 结算
    POST_GAME = "post_game",    -- 结算后选牌阶段(二!一!)
    ROUND_END = "round_end",    -- 本局结束
    GAME_OVER = "game_over",    -- 游戏结束
}

-- 每回合最大弃牌数
GameLogic.MAX_DISCARD = { 5, 4, 3 }
-- 回合对应阶段名
GameLogic.ROUND_PHASES = {
    GameLogic.PHASE.DRAW_FIVE,
    GameLogic.PHASE.DRAW_FOUR,
    GameLogic.PHASE.DRAW_THREE,
}

--- 创建新的游戏状态
---@return table
function GameLogic.NewGame()
    local state = {
        -- 大局状态
        playerWins = 0,
        aiWins = 0,
        roundNumber = 0,      -- 当前第几局 (1~5)
        
        -- 抽牌堆/弃牌堆 (双方共享弃牌堆，各自独立抽牌堆)
        playerDeck = {},
        aiDeck = {},
        discardPile = {},
        
        -- 当前对局状态
        phase = GameLogic.PHASE.INIT,
        turnIndex = 0,        -- 当前回合 (1,2,3)
        
        -- 手牌
        playerHand = {},
        aiHand = {},
        
        -- 下一局保留的牌
        playerKeep = nil,
        aiKeep = nil,
        
        -- 结算信息
        lastResult = nil,
        
        -- 日志
        log = {},
    }
    return state
end

--- 初始化新一局
---@param state table
function GameLogic.StartNewRound(state)
    state.roundNumber = state.roundNumber + 1
    state.turnIndex = 0
    state.phase = GameLogic.PHASE.INIT
    state.lastResult = nil
    
    -- 第一局时创建牌组
    if state.roundNumber == 1 then
        state.playerDeck = CardDefs.CreateFullDeck()
        state.aiDeck = CardDefs.CreateFullDeck()
        CardDefs.Shuffle(state.playerDeck)
        CardDefs.Shuffle(state.aiDeck)
        state.discardPile = {}
    end
    
    -- 发5张手牌
    state.playerHand = {}
    state.aiHand = {}
    
    -- 如果有上局保留的牌，先放入手牌
    if state.playerKeep then
        table.insert(state.playerHand, state.playerKeep)
        state.playerKeep = nil
    end
    if state.aiKeep then
        table.insert(state.aiHand, state.aiKeep)
        state.aiKeep = nil
    end
    
    -- 补满5张
    local playerNeed = 5 - #state.playerHand
    local aiNeed = 5 - #state.aiHand
    
    for _ = 1, playerNeed do
        local card = GameLogic.DrawFromDeck(state.playerDeck, state.discardPile)
        if card then table.insert(state.playerHand, card) end
    end
    for _ = 1, aiNeed do
        local card = GameLogic.DrawFromDeck(state.aiDeck, state.discardPile)
        if card then table.insert(state.aiHand, card) end
    end
    
    GameLogic.AddLog(state, string.format("=== 第 %d 局开始 ===", state.roundNumber))
    GameLogic.AddLog(state, string.format("比分: 玩家 %d - AI %d", state.playerWins, state.aiWins))
    
    -- 进入第一回合
    GameLogic.NextTurn(state)
end

--- 进入下一个回合
---@param state table
function GameLogic.NextTurn(state)
    state.turnIndex = state.turnIndex + 1
    if state.turnIndex > 3 then
        -- 三回合结束，进入鬼牌效果阶段
        state.phase = GameLogic.PHASE.JOKER_EFFECT
        GameLogic.AddLog(state, "三回合结束，进入结算前效果阶段")
        return
    end
    state.phase = GameLogic.ROUND_PHASES[state.turnIndex]
    local maxDiscard = GameLogic.MAX_DISCARD[state.turnIndex]
    GameLogic.AddLog(state, string.format("第 %d 回合: 可弃置至多 %d 张牌", state.turnIndex, maxDiscard))
end

--- 从牌堆抽一张牌
---@param deck table[] 抽牌堆
---@param discardPile table[] 弃牌堆(牌堆空时洗入)
---@return table|nil
function GameLogic.DrawFromDeck(deck, discardPile)
    if #deck == 0 then
        -- 将弃牌堆洗入
        if #discardPile > 0 then
            for _, card in ipairs(discardPile) do
                table.insert(deck, card)
            end
            -- 清空弃牌堆 (逐个移除保持引用正确)
            for i = #discardPile, 1, -1 do
                discardPile[i] = nil
            end
            CardDefs.Shuffle(deck)
        end
    end
    if #deck == 0 then return nil end
    return table.remove(deck)
end

--- 玩家执行弃牌换牌操作
--- 当弃置J时，返回特殊状态等待玩家选择从哪里抽牌
---@param state table 游戏状态
---@param discardIndices number[] 要弃置的手牌索引数组(1-based)
---@return boolean success
---@return string|nil errMsg
function GameLogic.PlayerDiscard(state, discardIndices)
    local maxDiscard = GameLogic.MAX_DISCARD[state.turnIndex]
    
    if #discardIndices > maxDiscard then
        return false, string.format("最多弃置 %d 张牌", maxDiscard)
    end
    
    -- 检查是否包含7(7不能被弃置/改变)
    for _, idx in ipairs(discardIndices) do
        local card = state.playerHand[idx]
        if card and card.rank == 7 then
            return false, "7 无法被弃置"
        end
    end
    
    -- 按索引从大到小排序，确保移除时不影响其他索引
    table.sort(discardIndices, function(a, b) return a > b end)
    
    local discarded = {}
    local jackCount = 0
    for _, idx in ipairs(discardIndices) do
        if idx >= 1 and idx <= #state.playerHand then
            local card = table.remove(state.playerHand, idx)
            table.insert(discarded, card)
            if card.rank == 11 then
                jackCount = jackCount + 1
            end
        end
    end
    
    -- 弃置的牌放入弃牌堆
    for _, card in ipairs(discarded) do
        table.insert(state.discardPile, card)
    end
    
    -- 记录待处理的J数量(玩家需要选择从弃牌堆还是抽牌堆抽牌)
    state.pendingJackPicks = jackCount
    
    -- 抽取相同张数的新牌(不含J的额外抽取)
    local drawCount = #discarded
    for _ = 1, drawCount do
        local card = GameLogic.DrawFromDeck(state.playerDeck, state.discardPile)
        if card then
            table.insert(state.playerHand, card)
        end
    end
    
    GameLogic.AddLog(state, string.format("弃置 %d 张, 抽取 %d 张", #discarded, drawCount))
    
    if jackCount > 0 then
        GameLogic.AddLog(state, string.format("J 弃置效果: 可从弃牌堆或抽牌堆中选取 %d 张牌", jackCount))
    end
    
    return true, nil
end

--- 玩家J效果: 从指定牌堆中选取一张指定的牌
---@param state table
---@param source string "discard" 或 "deck"
---@param cardIndex number 在该牌堆中的索引
---@return boolean, string
function GameLogic.PlayerJackPick(state, source, cardIndex)
    if not state.pendingJackPicks or state.pendingJackPicks <= 0 then
        return false, "没有待处理的J效果"
    end
    
    local pile
    if source == "discard" then
        pile = state.discardPile
    elseif source == "deck" then
        pile = state.playerDeck
    else
        return false, "无效来源"
    end
    
    if #pile == 0 then
        return false, "该牌堆为空"
    end
    
    if cardIndex < 1 or cardIndex > #pile then
        return false, "无效索引"
    end
    
    local card = table.remove(pile, cardIndex)
    table.insert(state.playerHand, card)
    state.pendingJackPicks = state.pendingJackPicks - 1
    
    GameLogic.AddLog(state, string.format("J效果: 从%s中抽取了 %s",
        source == "discard" and "弃牌堆" or "抽牌堆",
        CardDefs.GetCardName(card)))
    
    return true, nil
end

--- AI执行弃牌换牌操作
---@param state table
---@param discardIndices number[]
function GameLogic.AIDiscard(state, discardIndices)
    local maxDiscard = GameLogic.MAX_DISCARD[state.turnIndex]
    
    -- 过滤掉7
    local validIndices = {}
    for _, idx in ipairs(discardIndices) do
        local card = state.aiHand[idx]
        if card and card.rank ~= 7 then
            table.insert(validIndices, idx)
        end
    end
    
    -- 限制数量
    while #validIndices > maxDiscard do
        table.remove(validIndices)
    end
    
    table.sort(validIndices, function(a, b) return a > b end)
    
    local discarded = {}
    for _, idx in ipairs(validIndices) do
        if idx >= 1 and idx <= #state.aiHand then
            local card = table.remove(state.aiHand, idx)
            table.insert(discarded, card)
            -- J效果
            if card.rank == 11 then
                if #state.discardPile > 0 then
                    local drawnCard = table.remove(state.discardPile, math.random(1, #state.discardPile))
                    table.insert(state.aiHand, drawnCard)
                end
            end
        end
    end
    
    for _, card in ipairs(discarded) do
        table.insert(state.discardPile, card)
    end
    
    for _ = 1, #discarded do
        local card = GameLogic.DrawFromDeck(state.aiDeck, state.discardPile)
        if card then table.insert(state.aiHand, card) end
    end
    
    GameLogic.AddLog(state, string.format("AI 弃置 %d 张, 抽取 %d 张", #discarded, #discarded))
end

--- 计算一手牌的最终点数(含特效)
---@param hand table[] 自己的手牌
---@param opponentHand table[] 对手的手牌
---@return number 最终点数
---@return table 结算详情
function GameLogic.CalculatePoints(hand, opponentHand)
    local details = {
        basePoints = 0,
        aceEffects = {},
        eightEffects = 0,
        jackEffects = false,
        sevenCount = 0,
        finalPoints = 0,
    }
    
    -- 1. 检查7的特殊胜利条件
    local mySevenCount = 0
    for _, card in ipairs(hand) do
        if CardDefs.CanCountAsSeven(card) then
            mySevenCount = mySevenCount + 1
        end
    end
    details.sevenCount = mySevenCount
    
    -- 2. 检查对手的J效果 (J弃置时已经处理，这里是留在手中的J效果)
    -- 根据规则: J "在结算前, 将对方牌堆里的普通牌点数翻倍"
    -- 这个效果是弃置J时触发的，对当前局对方牌有效
    -- 简化处理：J只在手中时不触发翻倍效果(翻倍效果在弃置时已标记)
    
    -- 3. 计算基础点数
    local totalPoints = 0
    
    -- 3a. 先检查对手手中的 Ace 效果 (对方的A会翻倍我方对应花色)
    local aceDoubledSuits = {}
    for _, card in ipairs(opponentHand) do
        if card.rank == 1 then
            aceDoubledSuits[card.suit] = true
            table.insert(details.aceEffects, card.suit)
        end
    end
    
    -- 3b. 计算对手手中J的效果（在结算前翻倍对方普通牌）
    local opponentJackCount = 0
    for _, card in ipairs(opponentHand) do
        if card.rank == 11 then
            opponentJackCount = opponentJackCount + 1
        end
    end
    -- 注意：题目说J是"弃置时"触发效果，不是留在手里
    -- 重新解读：J留在手中也有"结算前将对方普通牌翻倍"的效果
    -- 这里暂时按"J在手中时对结算无效果"处理
    -- TODO: 可根据需要调整
    
    -- 3c. 检查对手手中8的效果(使我方普通牌-1)
    local opponentEightCount = 0
    for _, card in ipairs(opponentHand) do
        if card.rank == 8 then
            opponentEightCount = opponentEightCount + 1
        end
    end
    -- 注意: 8的效果是"使你的普通牌降低一点"，是对自己有效
    -- 所以8是自己的牌对自己生效
    
    -- 3d. 计算自己手牌中8的效果
    local myEightCount = 0
    for _, card in ipairs(hand) do
        if card.rank == 8 then
            myEightCount = myEightCount + 1
        end
    end
    details.eightEffects = myEightCount
    
    -- 4. 逐张计算点数
    for _, card in ipairs(hand) do
        local points = CardDefs.GetBasePoints(card)
        
        -- Ace翻倍效果 (对方的A翻倍我方对应花色)
        if card.suit and aceDoubledSuits[card.suit] then
            points = points * 2
        end
        
        -- 8的效果: 使自己的普通牌(2~6)点数-1 (每张8降1点)
        if CardDefs.IsNormal(card) and myEightCount > 0 then
            points = math.max(0, points - myEightCount)
        end
        
        totalPoints = totalPoints + points
    end
    
    details.basePoints = totalPoints
    details.finalPoints = totalPoints
    
    return totalPoints, details
end

--- 检查7的特殊胜利条件
---@param hand table[]
---@param opponentHand table[]
---@return string|nil "win", "lose", 或 nil(无特殊结果)
function GameLogic.CheckSevenRule(hand, opponentHand)
    local mySevenCount = 0
    for _, card in ipairs(hand) do
        if CardDefs.CanCountAsSeven(card) then
            mySevenCount = mySevenCount + 1
        end
    end
    
    if mySevenCount < 3 then return nil end
    
    -- 有3张7, 检查对方是否有可视为7的牌
    local opponentSevenCount = 0
    for _, card in ipairs(opponentHand) do
        if CardDefs.CanCountAsSeven(card) then
            opponentSevenCount = opponentSevenCount + 1
        end
    end
    
    if opponentSevenCount == 0 then
        return "win"   -- 对方无7，胜利
    elseif opponentSevenCount >= 2 then
        return "lose"  -- 对方有2+张7，失败
    end
    
    return nil  -- 对方有1张7，无特殊效果
end

--- 执行结算
---@param state table
---@return table 结算结果 {winner, playerPoints, aiPoints, ...}
function GameLogic.DoSettlement(state)
    local result = {
        winner = nil,        -- "player" / "ai" / "tie"
        playerPoints = 0,
        aiPoints = 0,
        playerDetails = nil,
        aiDetails = nil,
        sevenRuleTriggered = false,
    }
    
    -- 先处理鬼牌的jokerValue (需要在结算前设定)
    -- 大王: 选择自己一张牌视为任意点数 (AI自动选择最优)
    -- 小王: 移除对方一张牌
    
    -- 小王效果: 抽取对方一张牌移出 (需要在结算前处理)
    -- 这些在 JOKER_EFFECT 阶段处理
    
    -- 检查7的特殊规则
    local playerSevenResult = GameLogic.CheckSevenRule(state.playerHand, state.aiHand)
    local aiSevenResult = GameLogic.CheckSevenRule(state.aiHand, state.playerHand)
    
    if playerSevenResult == "win" and aiSevenResult == "win" then
        -- 双方都触发7胜利 → 平局
        result.winner = "tie"
        result.sevenRuleTriggered = true
        GameLogic.AddLog(state, "双方都触发三7规则，平局！")
    elseif playerSevenResult == "win" then
        result.winner = "player"
        result.sevenRuleTriggered = true
        GameLogic.AddLog(state, "玩家触发三7规则获胜！")
    elseif playerSevenResult == "lose" then
        result.winner = "ai"
        result.sevenRuleTriggered = true
        GameLogic.AddLog(state, "玩家三7遭遇对方7，失败！")
    elseif aiSevenResult == "win" then
        result.winner = "ai"
        result.sevenRuleTriggered = true
        GameLogic.AddLog(state, "AI触发三7规则获胜！")
    elseif aiSevenResult == "lose" then
        result.winner = "player"
        result.sevenRuleTriggered = true
        GameLogic.AddLog(state, "AI三7遭遇对方7，失败！")
    end
    
    if not result.sevenRuleTriggered then
        -- 正常结算: 比较谁更接近21点
        local playerPts, playerDetails = GameLogic.CalculatePoints(state.playerHand, state.aiHand)
        local aiPts, aiDetails = GameLogic.CalculatePoints(state.aiHand, state.playerHand)
        
        result.playerPoints = playerPts
        result.aiPoints = aiPts
        result.playerDetails = playerDetails
        result.aiDetails = aiDetails
        
        -- 比较与21的距离(绝对值)
        local playerDist = math.abs(21 - playerPts)
        local aiDist = math.abs(21 - aiPts)
        
        if playerDist < aiDist then
            result.winner = "player"
        elseif aiDist < playerDist then
            result.winner = "ai"
        else
            result.winner = "tie"
        end
        
        GameLogic.AddLog(state, string.format("结算: 玩家 %d点 (距21: %d) vs AI %d点 (距21: %d)",
            playerPts, playerDist, aiPts, aiDist))
    end
    
    -- 更新胜场
    if result.winner == "player" then
        state.playerWins = state.playerWins + 1
        GameLogic.AddLog(state, ">>> 玩家赢得本局! <<<")
    elseif result.winner == "ai" then
        state.aiWins = state.aiWins + 1
        GameLogic.AddLog(state, ">>> AI赢得本局! <<<")
    else
        GameLogic.AddLog(state, ">>> 平局! <<<")
    end
    
    state.lastResult = result
    state.phase = GameLogic.PHASE.POST_GAME
    
    return result
end

--- 结算后处理: 弃置鬼牌 + 选至多2张弃置 + 选至多1张保留
---@param state table
---@param playerDiscardIndices number[] 玩家选择弃置的牌索引(不含鬼牌)
---@param playerKeepIndex number|nil 玩家选择保留的牌索引
function GameLogic.PostGamePlayerChoice(state, playerDiscardIndices, playerKeepIndex)
    -- 1. 强制弃置鬼牌
    local i = 1
    while i <= #state.playerHand do
        if CardDefs.IsJoker(state.playerHand[i]) then
            local card = table.remove(state.playerHand, i)
            table.insert(state.discardPile, card)
            GameLogic.AddLog(state, "强制弃置鬼牌: " .. CardDefs.GetCardName(card))
        else
            i = i + 1
        end
    end
    
    -- 2. 选择至多2张弃置(二!)
    if playerDiscardIndices and #playerDiscardIndices > 0 then
        local count = math.min(#playerDiscardIndices, 2)
        -- 排序从大到小
        table.sort(playerDiscardIndices, function(a, b) return a > b end)
        for j = 1, count do
            local idx = playerDiscardIndices[j]
            if idx >= 1 and idx <= #state.playerHand then
                local card = table.remove(state.playerHand, idx)
                -- 弃置至抽牌堆(不是弃牌堆!)
                table.insert(state.playerDeck, card)
                GameLogic.AddLog(state, "弃置至牌堆: " .. CardDefs.GetCardName(card))
            end
        end
    end
    
    -- 3. 选择至多1张保留(一!)
    if playerKeepIndex and playerKeepIndex >= 1 and playerKeepIndex <= #state.playerHand then
        state.playerKeep = table.remove(state.playerHand, playerKeepIndex)
        GameLogic.AddLog(state, "保留至下局: " .. CardDefs.GetCardName(state.playerKeep))
    end
    
    -- 剩余手牌放入弃牌堆
    for _, card in ipairs(state.playerHand) do
        table.insert(state.discardPile, card)
    end
    state.playerHand = {}
end

--- AI的结算后选择
---@param state table
function GameLogic.PostGameAIChoice(state)
    -- 1. 强制弃置鬼牌
    local i = 1
    while i <= #state.aiHand do
        if CardDefs.IsJoker(state.aiHand[i]) then
            local card = table.remove(state.aiHand, i)
            table.insert(state.discardPile, card)
        else
            i = i + 1
        end
    end
    
    -- 2. AI策略: 保留最好的牌
    -- 优先保留点数中等(接近4-5点)的牌用于下局凑21
    local bestKeepIdx = nil
    local bestKeepScore = -1
    for idx, card in ipairs(state.aiHand) do
        if card.rank ~= 7 then  -- 7不能被移除但可以保留
            local score = 0
            -- 偏好中等点数
            local pts = CardDefs.GetBasePoints(card)
            score = 10 - math.abs(pts - 5)
            -- 特殊牌加分
            if card.rank == 1 then score = score + 3 end
            if card.rank >= 11 then score = score + 2 end
            if score > bestKeepScore then
                bestKeepScore = score
                bestKeepIdx = idx
            end
        end
    end
    
    -- 保留一张
    if bestKeepIdx and #state.aiHand > 0 then
        state.aiKeep = table.remove(state.aiHand, bestKeepIdx)
    end
    
    -- 弃置至多2张到抽牌堆(选择点数最大的)
    local sortedIndices = {}
    for idx = 1, #state.aiHand do
        table.insert(sortedIndices, idx)
    end
    table.sort(sortedIndices, function(a, b)
        return CardDefs.GetBasePoints(state.aiHand[a]) > CardDefs.GetBasePoints(state.aiHand[b])
    end)
    
    local discardCount = math.min(2, #state.aiHand)
    -- 从大到小索引移除
    local toRemove = {}
    for j = 1, discardCount do
        table.insert(toRemove, sortedIndices[j])
    end
    table.sort(toRemove, function(a, b) return a > b end)
    for _, idx in ipairs(toRemove) do
        if idx >= 1 and idx <= #state.aiHand then
            local card = table.remove(state.aiHand, idx)
            table.insert(state.aiDeck, card)
        end
    end
    
    -- 剩余放入弃牌堆
    for _, card in ipairs(state.aiHand) do
        table.insert(state.discardPile, card)
    end
    state.aiHand = {}
end

--- 检查游戏是否结束
---@param state table
---@return boolean
function GameLogic.IsGameOver(state)
    return state.playerWins >= 3 or state.aiWins >= 3
end

--- 添加日志
---@param state table
---@param msg string
function GameLogic.AddLog(state, msg)
    table.insert(state.log, msg)
    print("[Game] " .. msg)
end

return GameLogic
