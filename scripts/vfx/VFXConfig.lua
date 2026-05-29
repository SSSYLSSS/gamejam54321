-- ============================================================================
-- vfx/VFXConfig.lua - VFX 全局参数配置
-- ============================================================================

local VFXConfig = {}

-- Bloom 参数
VFXConfig.BLOOM_INNER_ALPHA = 0.45
VFXConfig.BLOOM_MID_ALPHA = 0.6
VFXConfig.BLOOM_OUTER_ALPHA = 0.1
VFXConfig.BLOOM_SIZE = 2.0

-- 粒子系统
VFXConfig.MAX_PARTICLES = 200
VFXConfig.PARTICLE_GRAVITY = 120    -- 像素/秒²

-- 动态背景
VFXConfig.BG_STAR_COUNT = 60        -- 背景星星数量
VFXConfig.BG_FLOW_SPEED = 0.3       -- 光带流动速度

-- 卡牌光晕
VFXConfig.CARD_GLOW_PULSE_SPEED = 2.5  -- 呼吸频率
VFXConfig.CARD_GLOW_MIN_BRIGHTNESS = 1.1
VFXConfig.CARD_GLOW_MAX_BRIGHTNESS = 1.6

-- 暗角
VFXConfig.VIGNETTE_INTENSITY = 1.5

return VFXConfig
