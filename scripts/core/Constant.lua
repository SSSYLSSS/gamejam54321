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
    NORMAL  = "normal",     -- 2-6
    SEVEN   = "seven",      -- 7
    EIGHT   = "eight",      -- 8
    RARE    = "rare",       -- 9-10
    FACE    = "face",       -- J, Q, K
    JOKER   = "joker",      -- 小王, 大王
}

-- 卡牌效果ID
Constant.EFFECT = {
    NONE            = "none",
    ACE_DOUBLE      = "ace_double",       -- A: 翻倍对手同花色
    SEVEN_IMMUNE    = "seven_immune",     -- 7: 不可被改变点数/删除, 可弃置
    EIGHT_REDUCE    = "eight_reduce",     -- 8: 己方普通牌-1, 对方普通牌+2
    NINE_FLEX       = "nine_flex",        -- 9: 点数可视为0或9
    TEN_BONUS       = "ten_bonus",        -- 10: 若弃置过, 最终+1
    JACK_DRAW       = "jack_draw",        -- J: 弃置时所有补牌可逐张选择从弃牌堆或抽牌堆抽取
    QUEEN_TRIPLE    = "queen_triple",     -- Q: 使对方最小普通牌点数×3
    KING_BONUS      = "king_bonus",       -- K: 对方向上取整到十位, 己方向下取整到十位
    JOKER_SMALL     = "joker_small",      -- 小王: 移除对方一张牌
    JOKER_BIG       = "joker_big",        -- 大王: 选择自己任意点数
}

-- 子阶段(玩家/AI回合)
Constant.SUB_PHASE = {
    PLAYER_TURN = "player_turn",
    AI_TURN     = "ai_turn",
    JACK_PICK   = "jack_pick",
    WAITING     = "waiting",
}

return Constant
