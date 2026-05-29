-- ============================================================================
-- vfx/CardGlow.lua - 卡牌发光效果
-- 为特殊卡牌 (鬼牌/J/7) 提供发光渲染
-- ============================================================================

local VFXConfig = require("vfx.VFXConfig")

local CardGlow = {}

--- 卡牌类型对应的光晕颜色
local GLOW_COLORS = {
    joker = { r = 0.9, g = 0.2, b = 0.9 },   -- 紫色 (鬼牌)
    jack  = { r = 0.4, g = 0.3, b = 1.0 },   -- 蓝紫色 (J)
    seven = { r = 0.2, g = 0.9, b = 0.4 },   -- 绿色 (7)
    ace   = { r = 1.0, g = 0.8, b = 0.2 },   -- 金色 (A)
    win   = { r = 1.0, g = 0.85, b = 0.1 },  -- 胜利金色
}

--- 渲染一个矩形发光框
---@param ctx any NanoVG context
---@param x number 左上角X
---@param y number 左上角Y
---@param w number 宽度
---@param h number 高度
---@param glowType string "joker"|"jack"|"seven"|"ace"|"win"
---@param time number 当前时间 (用于呼吸动画)
function CardGlow.RenderGlow(ctx, x, y, w, h, glowType, time)
    local color = GLOW_COLORS[glowType]
    if not color then return end

    -- 呼吸动画
    local pulse = math.sin(time * VFXConfig.CARD_GLOW_PULSE_SPEED)
    local brightness = VFXConfig.CARD_GLOW_MIN_BRIGHTNESS
        + (VFXConfig.CARD_GLOW_MAX_BRIGHTNESS - VFXConfig.CARD_GLOW_MIN_BRIGHTNESS)
        * (0.5 + pulse * 0.5)

    local hdrR = color.r * brightness
    local hdrG = color.g * brightness
    local hdrB = color.b * brightness

    -- BoxGradient bloom
    local feather = math.max(w, h) * 0.35
    local cornerRadius = 6
    local alpha = VFXConfig.BLOOM_INNER_ALPHA * 0.7

    nvgBeginPath(ctx)
    nvgRect(ctx, x - feather, y - feather, w + feather * 2, h + feather * 2)
    local grad = nvgBoxGradient(ctx, x, y, w, h, cornerRadius, feather,
        nvgRGBAf(hdrR, hdrG, hdrB, alpha),
        nvgRGBAf(hdrR, hdrG, hdrB, 0))
    nvgFillPaint(ctx, grad)
    nvgFill(ctx)
end

--- 渲染一组卡牌的发光效果
--- 在 UI 渲染之前调用，作为底层光晕
---@param ctx any NanoVG context
---@param glowList table[] 每项 {x, y, w, h, type}
---@param time number
function CardGlow.RenderAll(ctx, glowList, time)
    for _, item in ipairs(glowList) do
        CardGlow.RenderGlow(ctx, item.x, item.y, item.w, item.h, item.type, time)
    end
end

--- 根据卡牌数据判断是否需要发光
---@param card table
---@return string|nil glowType
function CardGlow.GetGlowType(card)
    if not card then return nil end
    if card.isJoker then return "joker" end
    if card.rank == 11 then return "jack" end
    if card.rank == 7 then return "seven" end
    if card.rank == 1 then return "ace" end
    return nil
end

return CardGlow
