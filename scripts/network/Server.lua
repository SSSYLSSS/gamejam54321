-- ============================================================================
-- network/Server.lua - 多人游戏服务端
-- 权威服务器: 管理两名玩家的游戏逻辑
-- 同步回合制: 两名玩家同时提交弃牌，服务器处理后广播结果
-- ============================================================================

local Shared = require("network.Shared")
local Constant = require("core.Constant")
local GameConfig = require("core.GameConfig")
local Card = require("core.Card")
local DeckSystem = require("system.DeckSystem")
local RuleEngine = require("system.RuleEngine")
local EffectSystem = require("system.EffectSystem")
local PlayerState = require("model.PlayerState")
local RoundState = require("model.RoundState")

local Server = {}

-- ============================================================================
-- 服务器状态
-- ============================================================================

---@type Scene
local scene_ = nil

-- 玩家连接管理
local players_ = {}        -- { [connKey] = { connection, playerId, state, ready, action } }
local playerOrder_ = {}    -- { connKey1, connKey2 } 按加入顺序

-- 游戏状态
local gameState_ = {
    phase = "waiting",      -- waiting, playing, post_discard, post_keep, round_end, game_over
    roundNumber = 0,
    turnIndex = 0,
    maxDiscard = 0,
    p1Wins = 0,
    p2Wins = 0,
    round = nil,            -- RoundState
}

-- 等待两人都提交操作
local pendingActions_ = { nil, nil }

-- ============================================================================
-- 工具函数
-- ============================================================================

local function GetConnectionKey(connection)
    return tostring(connection:GetAddress()) .. ":" .. tostring(connection:GetPort())
end

local function GetPlayerByConnection(connection)
    local key = GetConnectionKey(connection)
    return players_[key]
end

local function GetPlayerById(playerId)
    local key = playerOrder_[playerId]
    if key then return players_[key] end
    return nil
end

local function GetOpponent(playerId)
    return playerId == 1 and 2 or 1
end

local function BothActionsReceived()
    return pendingActions_[1] ~= nil and pendingActions_[2] ~= nil
end

local function ClearPendingActions()
    pendingActions_[1] = nil
    pendingActions_[2] = nil
end

--- 发送事件给指定玩家
local function SendToPlayer(playerId, eventName, data)
    local p = GetPlayerById(playerId)
    if p and p.connection then
        p.connection:SendRemoteEvent(eventName, true, data or VariantMap())
    end
end

--- 广播给所有玩家
local function Broadcast(eventName, data)
    for _, key in ipairs(playerOrder_) do
        local p = players_[key]
        if p and p.connection then
            p.connection:SendRemoteEvent(eventName, true, data or VariantMap())
        end
    end
end

-- ============================================================================
-- 游戏逻辑 (前向声明)
-- ============================================================================

local StartNewRound
local StartNextTurn
local DoSettlement
local ResolveTurn
local ResolvePostDiscard
local ResolvePostKeep
local ResolveNextRound

--- 开始新一局
StartNewRound = function()
    gameState_.roundNumber = gameState_.roundNumber + 1
    gameState_.turnIndex = 0
    gameState_.round = RoundState.New()
    gameState_.phase = "playing"

    -- 第一局时创建牌组
    for i = 1, 2 do
        local p = GetPlayerById(i)
        if gameState_.roundNumber == 1 then
            p.state.deck = DeckSystem.CreateFullDeck()
            DeckSystem.Shuffle(p.state.deck)
        end
        p.state:ResetHand()

        -- 保留牌放入手牌
        local keepCard = p.state:TakeKeepCard()
        if keepCard then
            p.state:AddToHand(keepCard)
        end

        -- 补满5张手牌
        DeckSystem.DealToHand(p.state, gameState_.round, GameConfig.HAND_SIZE)
    end

    -- 通知每个玩家他们的手牌
    for i = 1, 2 do
        local p = GetPlayerById(i)
        local opp = GetPlayerById(GetOpponent(i))
        local data = VariantMap()
        data["RoundNumber"] = Variant(gameState_.roundNumber)
        data["P1Wins"] = Variant(gameState_.p1Wins)
        data["P2Wins"] = Variant(gameState_.p2Wins)
        data["OpponentHandSize"] = Variant(#opp.state.hand)
        Shared.EncodeHand(data, "Hand", p.state.hand)
        -- 双方弃牌堆完整内容(可互相查看)
        Shared.EncodeHand(data, "MyDiscard", p.state.discardPile)
        Shared.EncodeHand(data, "OppDiscard", opp.state.discardPile)
        SendToPlayer(i, Shared.EVENTS.ROUND_START, data)
    end

    -- 开始第一回合
    StartNextTurn()
end

--- 开始下一个弃牌回合
StartNextTurn = function()
    gameState_.turnIndex = gameState_.turnIndex + 1
    if gameState_.turnIndex > 3 then
        -- 三回合结束，进入结算
        DoSettlement()
        return
    end

    gameState_.maxDiscard = GameConfig.MAX_DISCARD[gameState_.turnIndex]
    ClearPendingActions()

    -- 通知两位玩家开始新回合
    for i = 1, 2 do
        local data = VariantMap()
        data["TurnIndex"] = Variant(gameState_.turnIndex)
        data["MaxDiscard"] = Variant(gameState_.maxDiscard)
        data["DeckCount"] = Variant(#GetPlayerById(i).state.deck)
        data["DiscardCount"] = Variant(GetPlayerById(i).state:GetDiscardCount())
        SendToPlayer(i, Shared.EVENTS.TURN_START, data)
    end

    print(string.format("[Server] Turn %d started, max discard: %d", gameState_.turnIndex, gameState_.maxDiscard))
end

--- 处理单个玩家的弃牌逻辑(服务端)
---@param playerId number
---@param discardIndices number[]
local function ProcessPlayerDiscard(playerId, discardIndices)
    local p = GetPlayerById(playerId)
    local playerState = p.state
    local round = gameState_.round

    -- 验证索引合法性
    local maxDiscard = gameState_.maxDiscard
    if #discardIndices > maxDiscard then
        discardIndices = { table.unpack(discardIndices, 1, maxDiscard) }
    end

    -- 按索引从大到小排序
    table.sort(discardIndices, function(a, b) return a > b end)

    local discarded = {}
    local jackCount = 0
    for _, idx in ipairs(discardIndices) do
        local card = playerState:RemoveFromHand(idx)
        if card then
            table.insert(discarded, card)
            if card.rank == 11 then
                jackCount = jackCount + 1
            end

        end
    end

    -- 弃牌放入自己的弃牌堆
    for _, card in ipairs(discarded) do
        playerState:AddToDiscard(card)
    end

    -- 追踪J弃牌数
    playerState.discardedJackCount = playerState.discardedJackCount + jackCount

    -- J效果: 弃置含J → 所有补牌从弃牌堆/抽牌堆智能选择(服务端自动决策)
    local drawn = {}
    if jackCount > 0 then
        playerState.pendingJackPicks = #discarded
        while playerState.pendingJackPicks > 0 do
            local card
            -- 服务端策略: 优先从弃牌堆拿
            if playerState:GetDiscardCount() > 0 then
                card = playerState:DrawRandomFromDiscard()
            elseif #playerState.deck > 0 then
                card = DeckSystem.Draw(playerState.deck, round)
            end
            if card then
                playerState:AddToHand(card)
                table.insert(drawn, card)
            end
            playerState.pendingJackPicks = playerState.pendingJackPicks - 1
        end
    else
        -- 无J: 正常从抽牌堆补牌
        playerState.pendingJackPicks = 0
        for _ = 1, #discarded do
            local card = DeckSystem.Draw(playerState.deck, round)
            if card then
                playerState:AddToHand(card)
                table.insert(drawn, card)
            end
        end
    end

    return {
        discarded = discarded,
        drawn = drawn,
        jackCount = jackCount,
    }
end

--- 两人都提交弃牌后处理
ResolveTurn = function()
    local results = {}
    for i = 1, 2 do
        local action = pendingActions_[i]
        if action.skip then
            results[i] = { discarded = {}, drawn = {}, jackCount = 0 }
        else
            results[i] = ProcessPlayerDiscard(i, action.indices)
        end
    end

    -- 发送结果给每个玩家
    for i = 1, 2 do
        local oppId = GetOpponent(i)
        local myResult = results[i]
        local oppResult = results[oppId]
        local p = GetPlayerById(i)
        local opp = GetPlayerById(oppId)

        local data = VariantMap()
        -- 自己的新手牌
        Shared.EncodeHand(data, "Hand", p.state.hand)
        -- 自己的弃牌信息
        data["MyDiscardCount"] = Variant(#myResult.discarded)
        data["MyJackCount"] = Variant(myResult.jackCount)
        -- 对手弃牌数
        data["OppDiscardCount"] = Variant(#oppResult.discarded)
        data["OppJackCount"] = Variant(oppResult.jackCount)
        data["OppHandSize"] = Variant(#opp.state.hand)
        -- 牌堆信息
        data["DeckCount"] = Variant(#p.state.deck)
        data["DiscardPileCount"] = Variant(p.state:GetDiscardCount())
        -- 双方弃牌堆完整内容(可互相查看)
        Shared.EncodeHand(data, "MyDiscard", p.state.discardPile)
        Shared.EncodeHand(data, "OppDiscard", opp.state.discardPile)

        SendToPlayer(i, Shared.EVENTS.TURN_RESULT, data)
    end

    ClearPendingActions()

    -- 进入下一回合
    StartNextTurn()
end

--- 执行结算
DoSettlement = function()
    local p1 = GetPlayerById(1)
    local p2 = GetPlayerById(2)

    -- 设置鬼牌最优点数
    EffectSystem.AutoSetJokerValues(p1.state.hand)
    EffectSystem.AutoSetJokerValues(p2.state.hand)

    -- 小王效果: 互相移除
    local removedByP1 = EffectSystem.SmallJokerEffect(p1.state.hand, p2.state.hand, p2.state)
    local removedByP2 = EffectSystem.SmallJokerEffect(p2.state.hand, p1.state.hand, p1.state)

    -- 执行 RuleEngine 结算
    local result = RuleEngine.Settle(p1.state.hand, p2.state.hand, p1.state, p2.state)

    -- 更新胜场
    if result.winner == "player" then
        gameState_.p1Wins = gameState_.p1Wins + 1
    elseif result.winner == "ai" then
        gameState_.p2Wins = gameState_.p2Wins + 1
    end

    -- 通知双方结算结果(暴露双方手牌)
    for i = 1, 2 do
        local data = VariantMap()
        Shared.EncodeHand(data, "P1Hand", p1.state.hand)
        Shared.EncodeHand(data, "P2Hand", p2.state.hand)
        data["P1Points"] = Variant(result.playerPoints)
        data["P2Points"] = Variant(result.aiPoints)
        data["Winner"] = Variant(result.winner == "player" and 1 or (result.winner == "ai" and 2 or 0))
        data["SevenRule"] = Variant(result.sevenRuleTriggered and 1 or 0)
        data["P1Wins"] = Variant(gameState_.p1Wins)
        data["P2Wins"] = Variant(gameState_.p2Wins)
        -- 小王效果信息
        if removedByP1 then
            data["P1RemovedCard"] = Variant(Shared.EncodeCard(removedByP1))
        end
        if removedByP2 then
            data["P2RemovedCard"] = Variant(Shared.EncodeCard(removedByP2))
        end
        SendToPlayer(i, Shared.EVENTS.SETTLEMENT_RESULT, data)
    end

    -- 判断是否直接结束游戏
    if gameState_.p1Wins >= GameConfig.WINS_NEEDED or gameState_.p2Wins >= GameConfig.WINS_NEEDED then
        gameState_.phase = "game_over"
        local data = VariantMap()
        data["Winner"] = Variant(gameState_.p1Wins >= GameConfig.WINS_NEEDED and 1 or 2)
        data["P1Wins"] = Variant(gameState_.p1Wins)
        data["P2Wins"] = Variant(gameState_.p2Wins)
        Broadcast(Shared.EVENTS.GAME_OVER, data)
        return
    end

    -- 进入结算后阶段 (二!)
    gameState_.phase = "post_discard"
    ClearPendingActions()

    for i = 1, 2 do
        local p = GetPlayerById(i)
        local data = VariantMap()
        data["Phase"] = Variant("post_discard")
        data["MaxDiscard"] = Variant(GameConfig.POST_DISCARD_MAX)
        Shared.EncodeHand(data, "Hand", p.state.hand)
        SendToPlayer(i, Shared.EVENTS.POST_PHASE_START, data)
    end
end

--- 处理结算后弃牌 (二!)
local function ProcessPostDiscard(playerId, discardIndices)
    local p = GetPlayerById(playerId)
    local playerState = p.state

    -- 强制弃置鬼牌到自己的弃牌堆
    local i = 1
    while i <= #playerState.hand do
        if Card.IsJoker(playerState.hand[i]) then
            local card = table.remove(playerState.hand, i)
            playerState:AddToDiscard(card)
        else
            i = i + 1
        end
    end

    -- 弃置选中的牌到抽牌堆
    local count = math.min(#discardIndices, GameConfig.POST_DISCARD_MAX)
    table.sort(discardIndices, function(a, b) return a > b end)
    for j = 1, count do
        local idx = discardIndices[j]
        if idx >= 1 and idx <= #playerState.hand then
            local card = table.remove(playerState.hand, idx)
            playerState:AddToDeck(card)
        end
    end

    -- 放回后洗牌，避免下次必定抽到这些牌
    if count > 0 then
        DeckSystem.Shuffle(playerState.deck)
    end
end

--- 两人都提交结算后弃牌
ResolvePostDiscard = function()
    for i = 1, 2 do
        local action = pendingActions_[i]
        ProcessPostDiscard(i, action.indices or {})
    end

    -- 进入保留阶段 (一!)
    gameState_.phase = "post_keep"
    ClearPendingActions()

    for i = 1, 2 do
        local p = GetPlayerById(i)
        local data = VariantMap()
        data["Phase"] = Variant("post_keep")
        data["MaxKeep"] = Variant(GameConfig.POST_KEEP_MAX)
        Shared.EncodeHand(data, "Hand", p.state.hand)
        SendToPlayer(i, Shared.EVENTS.POST_PHASE_START, data)
    end
end

--- 处理结算后保留 (一!)
local function ProcessPostKeep(playerId, keepIndex)
    local p = GetPlayerById(playerId)
    local playerState = p.state

    if keepIndex and keepIndex >= 1 and keepIndex <= #playerState.hand then
        local card = table.remove(playerState.hand, keepIndex)
        playerState:SetKeepCard(card)
    end

    -- 剩余手牌放入弃牌堆
    for _, card in ipairs(playerState.hand) do
        playerState:AddToDiscard(card)
    end
    playerState.hand = {}
end

--- 两人都提交保留选择
ResolvePostKeep = function()
    for i = 1, 2 do
        local action = pendingActions_[i]
        ProcessPostKeep(i, action.keepIndex)
    end

    -- 本局结束
    gameState_.phase = "round_end"
    ClearPendingActions()

    local data = VariantMap()
    data["RoundNumber"] = Variant(gameState_.roundNumber)
    data["P1Wins"] = Variant(gameState_.p1Wins)
    data["P2Wins"] = Variant(gameState_.p2Wins)
    Broadcast(Shared.EVENTS.ROUND_END, data)
end

--- 两人都准备好进入下一局
ResolveNextRound = function()
    ClearPendingActions()
    StartNewRound()
end

-- ============================================================================
-- 事件处理
-- ============================================================================

local function HandleClientReady(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = GetConnectionKey(connection)

    -- 避免重复注册
    if players_[connKey] then return end

    connection.scene = scene_

    local playerId = #playerOrder_ + 1
    if playerId > 2 then
        print("[Server] Rejecting extra player")
        return
    end

    players_[connKey] = {
        connection = connection,
        playerId = playerId,
        state = PlayerState.New(false),
        ready = true,
    }
    table.insert(playerOrder_, connKey)

    -- 通知玩家他的编号
    local data = VariantMap()
    data["PlayerId"] = Variant(playerId)
    data["MaxPlayers"] = Variant(2)
    connection:SendRemoteEvent(Shared.EVENTS.ASSIGN_PLAYER, true, data)

    print(string.format("[Server] Player %d connected: %s", playerId, connKey))

    -- 两人到齐，开始游戏
    if #playerOrder_ == 2 then
        print("[Server] Both players connected, starting game!")
        StartNewRound()
    end
end

local function HandlePlayerDiscard(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local player = GetPlayerByConnection(connection)
    if not player then return end

    local pid = player.playerId
    if gameState_.phase ~= "playing" then return end
    if pendingActions_[pid] then return end  -- 已提交

    local indices = Shared.DecodeIndices(eventData, "Idx")
    pendingActions_[pid] = { indices = indices, skip = false }

    -- 通知对手正在等待
    SendToPlayer(GetOpponent(pid), Shared.EVENTS.WAIT_OPPONENT, VariantMap())

    print(string.format("[Server] Player %d discarded %d cards", pid, #indices))

    if BothActionsReceived() then
        ResolveTurn()
    end
end

local function HandlePlayerSkip(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local player = GetPlayerByConnection(connection)
    if not player then return end

    local pid = player.playerId
    if gameState_.phase ~= "playing" then return end
    if pendingActions_[pid] then return end

    pendingActions_[pid] = { indices = {}, skip = true }
    SendToPlayer(GetOpponent(pid), Shared.EVENTS.WAIT_OPPONENT, VariantMap())

    print(string.format("[Server] Player %d skipped discard", pid))

    if BothActionsReceived() then
        ResolveTurn()
    end
end

local function HandlePlayerPostDiscard(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local player = GetPlayerByConnection(connection)
    if not player then return end

    local pid = player.playerId
    if gameState_.phase ~= "post_discard" then return end
    if pendingActions_[pid] then return end

    local indices = Shared.DecodeIndices(eventData, "Idx")
    pendingActions_[pid] = { indices = indices }

    print(string.format("[Server] Player %d post-discard %d cards", pid, #indices))

    if BothActionsReceived() then
        ResolvePostDiscard()
    end
end

local function HandlePlayerPostKeep(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local player = GetPlayerByConnection(connection)
    if not player then return end

    local pid = player.playerId
    if gameState_.phase ~= "post_keep" then return end
    if pendingActions_[pid] then return end

    local keepIndex = eventData["KeepIndex"]:GetInt()
    if keepIndex <= 0 then keepIndex = nil end
    pendingActions_[pid] = { keepIndex = keepIndex }

    print(string.format("[Server] Player %d post-keep index: %s", pid, tostring(keepIndex)))

    if BothActionsReceived() then
        ResolvePostKeep()
    end
end

local function HandlePlayerContinue(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local player = GetPlayerByConnection(connection)
    if not player then return end

    local pid = player.playerId
    if gameState_.phase ~= "round_end" then return end
    if pendingActions_[pid] then return end

    pendingActions_[pid] = { continue = true }

    print(string.format("[Server] Player %d ready for next round", pid))

    if BothActionsReceived() then
        ResolveNextRound()
    end
end

local function HandleClientDisconnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = GetConnectionKey(connection)
    local player = players_[connKey]
    if not player then return end

    print(string.format("[Server] Player %d disconnected", player.playerId))

    -- 通知另一个玩家
    local oppId = GetOpponent(player.playerId)
    SendToPlayer(oppId, Shared.EVENTS.OPPONENT_DISCONNECTED, VariantMap())
end

-- ============================================================================
-- 生命周期
-- ============================================================================

function Server.Start()
    print("[Server] Starting multiplayer server...")

    -- 创建必需的 Scene (网络同步介质)
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    -- 注册接收的远程事件
    network:RegisterRemoteEvent(Shared.EVENTS.CLIENT_READY)
    network:RegisterRemoteEvent(Shared.EVENTS.PLAYER_DISCARD)
    network:RegisterRemoteEvent(Shared.EVENTS.PLAYER_SKIP)
    network:RegisterRemoteEvent(Shared.EVENTS.PLAYER_JACK_PICK)
    network:RegisterRemoteEvent(Shared.EVENTS.PLAYER_POST_DISCARD)
    network:RegisterRemoteEvent(Shared.EVENTS.PLAYER_POST_KEEP)
    network:RegisterRemoteEvent(Shared.EVENTS.PLAYER_CONTINUE)

    -- 订阅事件
    SubscribeToEvent(Shared.EVENTS.CLIENT_READY, "HandleClientReadyGlobal")
    SubscribeToEvent(Shared.EVENTS.PLAYER_DISCARD, "HandlePlayerDiscardGlobal")
    SubscribeToEvent(Shared.EVENTS.PLAYER_SKIP, "HandlePlayerSkipGlobal")
    SubscribeToEvent(Shared.EVENTS.PLAYER_POST_DISCARD, "HandlePlayerPostDiscardGlobal")
    SubscribeToEvent(Shared.EVENTS.PLAYER_POST_KEEP, "HandlePlayerPostKeepGlobal")
    SubscribeToEvent(Shared.EVENTS.PLAYER_CONTINUE, "HandlePlayerContinueGlobal")
    SubscribeToEvent("ClientDisconnected", "HandleClientDisconnectedGlobal")

    print("[Server] Ready, waiting for players...")
end

function Server.Stop()
    print("[Server] Shutting down")
end

-- ============================================================================
-- 全局事件转发 (UrhoX 要求全局函数名)
-- ============================================================================

function HandleClientReadyGlobal(eventType, eventData)
    HandleClientReady(eventType, eventData)
end
function HandlePlayerDiscardGlobal(eventType, eventData)
    HandlePlayerDiscard(eventType, eventData)
end
function HandlePlayerSkipGlobal(eventType, eventData)
    HandlePlayerSkip(eventType, eventData)
end
function HandlePlayerPostDiscardGlobal(eventType, eventData)
    HandlePlayerPostDiscard(eventType, eventData)
end
function HandlePlayerPostKeepGlobal(eventType, eventData)
    HandlePlayerPostKeep(eventType, eventData)
end
function HandlePlayerContinueGlobal(eventType, eventData)
    HandlePlayerContinue(eventType, eventData)
end
function HandleClientDisconnectedGlobal(eventType, eventData)
    HandleClientDisconnected(eventType, eventData)
end

return Server
