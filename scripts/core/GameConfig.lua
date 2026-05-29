-- ============================================================================
-- core/GameConfig.lua - 游戏可配置参数
-- ============================================================================

local GameConfig = {}

-- 胜利条件
GameConfig.WINS_NEEDED = 3          -- 先赢3局
GameConfig.MAX_ROUNDS = 5           -- 最多5局

-- 手牌规则
GameConfig.HAND_SIZE = 5            -- 手牌数量
GameConfig.MAX_DISCARD = { 5, 4, 3 } -- 每回合最大弃牌数

-- 结算后规则
GameConfig.POST_DISCARD_MAX = 2     -- 结算后最多弃2张
GameConfig.POST_KEEP_MAX = 1        -- 结算后最多保留1张

-- 目标点数
GameConfig.TARGET_POINTS = 21       -- 21点

-- 鬼牌点数范围
GameConfig.JOKER_MIN_VALUE = 0
GameConfig.JOKER_MAX_VALUE = 13

-- 牌组大小
GameConfig.DECK_SIZE = 54           -- 54张(含2张鬼牌)

return GameConfig
