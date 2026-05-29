-- ============================================================================
-- vfx/BackgroundRenderer.lua - 动态背景渲染
-- 暗色渐变 + 缓慢流动光带 + 星星粒子
-- ============================================================================

local VFXConfig = require("vfx.VFXConfig")

local BackgroundRenderer = {}
BackgroundRenderer.__index = BackgroundRenderer

---@class Star
---@field x number 归一化 0-1
---@field y number 归一化 0-1
---@field radius number
---@field brightness number
---@field twinkleSpeed number
---@field twinkleOffset number

--- 创建背景渲染器
---@return table
function BackgroundRenderer.New()
    local self = setmetatable({}, BackgroundRenderer)
    self.time = 0
    self.stars = {}
    self.flowBands = {}

    -- 生成星星
    for _ = 1, VFXConfig.BG_STAR_COUNT do
        table.insert(self.stars, {
            x = math.random(),
            y = math.random(),
            radius = 1 + math.random() * 2,
            brightness = 0.3 + math.random() * 0.7,
            twinkleSpeed = 1.0 + math.random() * 2.0,
            twinkleOffset = math.random() * math.pi * 2,
        })
    end

    -- 生成光带 (3-5条缓慢移动的半透明渐变带)
    for i = 1, 4 do
        table.insert(self.flowBands, {
            yOffset = 0.15 + (i - 1) * 0.22,
            speed = VFXConfig.BG_FLOW_SPEED * (0.5 + math.random() * 0.5),
            width = 0.08 + math.random() * 0.12,
            r = 0.1 + math.random() * 0.15,
            g = 0.15 + math.random() * 0.2,
            b = 0.3 + math.random() * 0.3,
            alpha = 0.04 + math.random() * 0.06,
            phase = math.random() * math.pi * 2,
        })
    end

    return self
end

--- 更新
---@param dt number
function BackgroundRenderer:Update(dt)
    self.time = self.time + dt
end

--- 渲染背景
---@param ctx any NanoVG context
---@param width number 画布宽度
---@param height number 画布高度
function BackgroundRenderer:Render(ctx, width, height)
    -- 1. 深色渐变底色
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, width, height)
    local bgGrad = nvgLinearGradient(ctx, 0, 0, 0, height,
        nvgRGBAf(0.05, 0.06, 0.12, 1.0),    -- 顶部: 深蓝黑
        nvgRGBAf(0.02, 0.03, 0.08, 1.0))    -- 底部: 更深
    nvgFillPaint(ctx, bgGrad)
    nvgFill(ctx)

    -- 2. 流动光带
    for _, band in ipairs(self.flowBands) do
        local yCenter = band.yOffset * height
            + math.sin(self.time * band.speed + band.phase) * height * 0.05
        local bandH = band.width * height

        nvgBeginPath(ctx)
        nvgRect(ctx, 0, yCenter - bandH * 0.5, width, bandH)
        local bandGrad = nvgLinearGradient(ctx,
            0, yCenter - bandH * 0.5,
            0, yCenter + bandH * 0.5,
            nvgRGBAf(band.r, band.g, band.b, 0),
            nvgRGBAf(band.r, band.g, band.b, band.alpha))
        nvgFillPaint(ctx, bandGrad)
        nvgFill(ctx)

        -- 对称渐变: 从中心向两边淡出
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, yCenter - bandH * 0.5, width, bandH)
        local bandGrad2 = nvgLinearGradient(ctx,
            0, yCenter + bandH * 0.5,
            0, yCenter - bandH * 0.5,
            nvgRGBAf(band.r, band.g, band.b, 0),
            nvgRGBAf(band.r, band.g, band.b, band.alpha))
        nvgFillPaint(ctx, bandGrad2)
        nvgFill(ctx)
    end

    -- 3. 暗角 (NanoVG 模拟 Vignette)
    local cx, cy = width * 0.5, height * 0.5
    local maxR = math.sqrt(cx * cx + cy * cy)
    local innerR = maxR * 0.45

    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, width, height)
    local vigGrad = nvgRadialGradient(ctx, cx, cy, innerR, maxR,
        nvgRGBAf(0, 0, 0, 0),
        nvgRGBAf(0, 0, 0, 0.6))
    nvgFillPaint(ctx, vigGrad)
    nvgFill(ctx)

    -- 4. 星星 (带闪烁)
    for _, star in ipairs(self.stars) do
        local twinkle = 0.5 + 0.5 * math.sin(self.time * star.twinkleSpeed + star.twinkleOffset)
        local alpha = star.brightness * twinkle * 0.8
        local radius = star.radius * (0.7 + twinkle * 0.3)

        local sx = star.x * width
        local sy = star.y * height

        -- 微弱bloom
        if alpha > 0.4 then
            local bloomR = radius * 3
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy, bloomR)
            local sGrad = nvgRadialGradient(ctx, sx, sy, radius * 0.5, bloomR,
                nvgRGBAf(0.6, 0.7, 1.0, alpha * 0.2),
                nvgRGBAf(0.6, 0.7, 1.0, 0))
            nvgFillPaint(ctx, sGrad)
            nvgFill(ctx)
        end

        -- 核心点
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, radius)
        nvgFillColor(ctx, nvgRGBAf(0.7, 0.8, 1.0, alpha))
        nvgFill(ctx)
    end
end

return BackgroundRenderer
