-- ============================================================================
-- core/Constant.lua - 游戏常量与枚举
-- ============================================================================

local Constant = {}

-- 游戏阶段枚举
Constant.PHASE = {
    INIT            = "init",
    DRAW_FIVE       = "draw_five",       -- 第一回合: 五!
    DRAW_FOUR       = "draw_four",        -- 第二回合: 四!
    DRAW_THREE      = "draw_three",       -- 第三回合: 三!
    JOKER_EFFECT    = "joker_effect",     -- 鬼牌效果阶段
    SETTLEMENT      = "settlement",       -- 结算
    POST_DISCARD    = "post_discard",     -- 结算后弃牌: 二!
    POST_KEEP       = "post_keep",        -- 结算后保留: 一!
    ROUND_END       = "round_end",        -- 本局结束
    GAME_OVER       = "game_over",        -- 游戏结束
}

-- 阶段顺序(主回合)
Constant.ROUND_PHASES = {
    Constant.PHASE.DRAW_FIVE,
    Constant.PHASE.DRAW_FOUR,
    Constant.PHASE.DRAW_THREE,
}

-- 花色
Constant.SUIT = {
    SPADE   = "spade",
    HEART   = "heart",
    CLUB    = "club",
    DIAMOND = "diamond",
}

-- 花色符号
Constant.SUIT_SYMBOLS = {
    spade   = "♠",
    heart   = "♥",
    club    = "♣",
    diamond = "♦",
}

-- 花色颜色
Constant.SUIT_COLORS = {
    spade   = { 35, 35, 35, 255 },
    heart   = { 200, 50, 50, 255 },
    club    = { 35, 35, 35, 255 },
    diamond = { 200, 50, 50, 255 },
}

-- 点数名称
Constant.RANK_NAMES = {
    [1] = "A", [2] = "2", [3] = "3", [4] = "4", [5] = "5",
    [6] = "6", [7] = "7", [8] = "8", [9] = "9", [10] = "10",
    [11] = "J", [12] = "Q", [13] = "K",
    [14] = "小王", [15] = "大王",
}

-- 卡牌类别
Constant.CATEGORY = {
    ACE     = "ace",        -- A (1)
    NORMAL  = "normal",     -- 2-7
    RARE    = "rare",       -- 8-10 (稀有牌)
    FACE    = "face",       -- J, Q, K (罕见牌)
    JOKER   = "joker",      -- 小王, 大王
}

-- 卡牌效果ID
Constant.EFFECT = {
    NONE            = "none",
    ACE_DOUBLE      = "ace_double",       -- A: 翻倍对手同花色牌点数(×2)
    EIGHT_REDUCE    = "eight_reduce",     -- 8: 己方普通牌-2, 对方普通牌+2
    NINE_FLEX       = "nine_flex",        -- 9: 点数可视为0或9
    TEN_REDUCE      = "ten_reduce",       -- 10: 己方罕见牌(J/Q/K)点数-10
    JACK_ZERO       = "jack_zero",        -- J: 己方普通牌点数视为0
    QUEEN_TRIPLE    = "queen_triple",     -- Q: 对方最大普通牌×3, 己方取整
    KING_DOUBLE     = "king_double",      -- K: 对方普通牌点数×2
    JOKER_SMALL     = "joker_small",      -- 小王: 点数0~13
    JOKER_BIG       = "joker_big",        -- 大王: 结算前改一张牌点数, 自身0~13
}

-- 子阶段(玩家/AI回合)
Constant.SUB_PHASE = {
    PLAYER_TURN = "player_turn",
    AI_TURN     = "ai_turn",

    WAITING     = "waiting",
}

return Constant
