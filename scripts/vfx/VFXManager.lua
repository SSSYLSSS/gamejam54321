-- ============================================================================
-- vfx/VFXManager.lua - VFX 统一管理器
-- 管理所有视觉特效的生命周期: 初始化、更新、渲染
-- ============================================================================

local VFXConfig = require("vfx.VFXConfig")
local ParticleSystem = require("vfx.ParticleSystem")
local BackgroundRenderer = require("vfx.BackgroundRenderer")
local CardGlow = require("vfx.CardGlow")

local VFXManager = {}

---@type any NanoVG context
local vg = nil
---@type number
local fontId = -1
---@type table ParticleSystem instance
local particles = nil
---@type table BackgroundRenderer instance
local background = nil
---@type number
local time = 0
---@type number
local screenW = 0
---@type number
local screenH = 0
---@type table[] 当前帧要渲染的卡牌光晕列表
local cardGlowList = {}
---@type table[] 飞行卡牌动画列表
local flyingCards = {}
---@type table[] 图片辉光列表 {imgHandle, x, y, w, h, r, g, b, intensity}
local bloomImages = {}
---@type table<string, integer> 已加载的 NanoVG 图片句柄缓存
local imageCache = {}
---@type table[] 光线特效列表 {x1, y1, x2, y2, r, g, b, elapsed, duration}
local lightBeams = {}

-- ============================================================================
-- 生命周期
-- ============================================================================

--- 初始化 VFX 系统
function VFXManager.Init()
    vg = nvgCreate(1)
    fontId = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
    particles = ParticleSystem.New()
    background = BackgroundRenderer.New()
    time = 0

    -- 启用 NanoVG 层 Bloom 后处理
    nvgSetBloomEnabled(vg, true)

    -- 订阅 NanoVG 渲染事件
    SubscribeToEvent(vg, "NanoVGRender", "HandleVFXRender")
end

--- 销毁
function VFXManager.Shutdown()
    if vg then
        nvgDelete(vg)
        vg = nil
    end
end

--- 每帧更新 (在 HandleUpdate 中调用)
---@param dt number
function VFXManager.Update(dt)
    time = time + dt
    if background then background:Update(dt) end
    if particles then particles:Update(dt) end

    -- 更新光线特效
    local li = 1
    while li <= #lightBeams do
        local beam = lightBeams[li]
        beam.elapsed = beam.elapsed + dt
        if beam.elapsed >= beam.duration then
            table.remove(lightBeams, li)
        else
            li = li + 1
        end
    end

    -- 更新飞行卡牌
    local i = 1
    while i <= #flyingCards do
        local fc = flyingCards[i]
        fc.elapsed = fc.elapsed + dt
        local t = math.min(fc.elapsed / fc.duration, 1.0)
        -- easeOutCubic
        local ease = 1 - (1 - t) ^ 3
        fc.x = fc.startX + (fc.endX - fc.startX) * ease
        fc.y = fc.startY + (fc.endY - fc.startY) * ease
        fc.scale = 1.0 - ease * 0.35  -- 从1.0缩到0.65(保持更大)
        fc.alpha = 1.0 - ease * ease * 0.8  -- 逐渐透明但保留更久
        if t >= 1.0 then
            table.remove(flyingCards, i)
        else
            i = i + 1
        end
    end
end

--- 获取当前时间 (供外部动画用)
---@return number
function VFXManager.GetTime()
    return time
end

-- ============================================================================
-- 粒子效果触发接口
-- ============================================================================

--- 胜利烟花 (金色爆发)
---@param x number
---@param y number
function VFXManager.EmitWinParticles(x, y)
    if not particles then return end
    particles:Emit(x, y, 50, {
        r = 1.0, g = 0.85, b = 0.2,
        speed = 250,
        life = 2.0,
        radius = 5,
    })
    -- 追加一些白色小粒子
    particles:Emit(x, y, 30, {
        r = 1.0, g = 1.0, b = 0.9,
        speed = 150,
        life = 1.2,
        radius = 2,
    })
end

--- 失败粒子 (暗红碎裂)
---@param x number
---@param y number
function VFXManager.EmitLoseParticles(x, y)
    if not particles then return end
    particles:Emit(x, y, 30, {
        r = 0.8, g = 0.2, b = 0.2,
        speed = 120,
        life = 1.0,
        radius = 3,
    })
end

--- 弃牌飞散效果
---@param x number
---@param y number
function VFXManager.EmitDiscardParticles(x, y)
    if not particles then return end
    particles:EmitUpward(x, y, 12)
end

--- J效果触发 (紫色闪光)
---@param x number
---@param y number
function VFXManager.EmitJackEffect(x, y)
    if not particles then return end
    particles:Emit(x, y, 25, {
        r = 0.5, g = 0.3, b = 1.0,
        speed = 180,
        life = 1.0,
        radius = 4,
    })
end

--- 清除所有粒子
function VFXManager.ClearParticles()
    if particles then particles:Clear() end
end

--- 弃牌飞行动画: 从起点飞到终点
---@param startX number 起始X
---@param startY number 起始Y
---@param endX number 终点X
---@param endY number 终点Y
---@param count number 飞行卡牌数量
function VFXManager.EmitFlyingCards(startX, startY, endX, endY, count)
    count = count or 1
    for i = 1, count do
        table.insert(flyingCards, {
            startX = startX + (i - 1) * 12,
            startY = startY,
            endX = endX,
            endY = endY,
            x = startX,
            y = startY,
            elapsed = (i - 1) * 0.08,  -- 错开时间(加大间隔更有层次)
            duration = 0.55,
            scale = 1.0,
            alpha = 1.0,
        })
    end
end

--- 是否有飞行卡牌
---@return boolean
function VFXManager.HasFlyingCards()
    return #flyingCards > 0
end

-- ============================================================================
-- 卡牌光晕接口
-- ============================================================================

--- 设置当前帧的卡牌光晕列表 (由 GameScene 每帧设置)
---@param list table[] 每项 {x, y, w, h, type}
function VFXManager.SetCardGlowList(list)
    cardGlowList = list or {}
end

-- ============================================================================
-- 图片 Bloom 辉光接口
-- ============================================================================

--- 设置要施加 Bloom 辉光的图片列表 (每帧调用)
--- 图片以高亮度(>1.0)渲染, 触发引擎级 Bloom 后处理产生真正的辉光
---@param list table[] 每项 {src, x, y, w, h, rotate?, intensity?}
function VFXManager.SetBloomImages(list)
    bloomImages = {}
    if not list or not vg then return end
    for _, item in ipairs(list) do
        -- 缓存图片句柄
        local handle = imageCache[item.src]
        if not handle then
            handle = nvgCreateImage(vg, item.src, 0)
            imageCache[item.src] = handle
        end
        if handle and handle >= 0 then
            table.insert(bloomImages, {
                handle = handle,
                x = item.x or 0,
                y = item.y or 0,
                w = item.w or 100,
                h = item.h or 100,
                rotate = item.rotate or 0,
                intensity = item.intensity or 1.5,
            })
        end
    end
end

--- 清除图片 Bloom 列表
function VFXManager.ClearBloomImages()
    bloomImages = {}
end

-- ============================================================================
-- 光线特效接口
-- ============================================================================

--- 发射一道光线特效 (从 source 到 target，持续 duration 秒后淡出)
---@param x1 number 起点X
---@param y1 number 起点Y
---@param x2 number 终点X
---@param y2 number 终点Y
---@param opts table|nil {r, g, b, duration}
function VFXManager.EmitLightBeam(x1, y1, x2, y2, opts)
    opts = opts or {}
    table.insert(lightBeams, {
        x1 = x1, y1 = y1,
        x2 = x2, y2 = y2,
        r = opts.r or 0.6,
        g = opts.g or 0.4,
        b = opts.b or 1.0,
        duration = opts.duration or 1.0,
        elapsed = 0,
    })
end

--- 清除所有光线特效
function VFXManager.ClearLightBeams()
    lightBeams = {}
end

-- ============================================================================
-- NanoVG 渲染回调 (内部)
-- ============================================================================

--- NanoVG 渲染事件处理 (全局函数，由引擎调用)
function HandleVFXRender(eventType, eventData)
    if not vg then return end

    screenW = graphics:GetWidth() / graphics:GetDPR()
    screenH = graphics:GetHeight() / graphics:GetDPR()

    nvgBeginFrame(vg, screenW, screenH, graphics:GetDPR())

    -- 层级1: 动态背景
    if background then
        background:Render(vg, screenW, screenH)
    end

    -- 层级2: 卡牌光晕 (在UI下方)
    if #cardGlowList > 0 then
        CardGlow.RenderAll(vg, cardGlowList, time)
    end

    -- 层级2.5: 图片 Bloom 辉光 (BoxGradient 大范围模糊扩散)
    if #bloomImages > 0 then
        for _, bi in ipairs(bloomImages) do
            nvgSave(vg)
            local cx = bi.x + bi.w * 0.5
            local cy = bi.y + bi.h * 0.5
            nvgTranslate(vg, cx, cy)
            if bi.rotate ~= 0 then
                nvgRotate(vg, bi.rotate * math.pi / 180)
            end

            local intensity = bi.intensity
            local glowStrength = math.max(0, intensity - 1.0)

            -- 大范围 BoxGradient 模糊光晕 (feather 值越大扩散越远)
            local feather = math.max(bi.w, bi.h) * 0.6
            local glowAlpha = 0.4 * glowStrength
            nvgBeginPath(vg)
            nvgRect(vg, -bi.w * 0.5 - feather * 1.5, -bi.h * 0.5 - feather * 1.5,
                    bi.w + feather * 3, bi.h + feather * 3)
            local grad = nvgBoxGradient(vg,
                -bi.w * 0.5, -bi.h * 0.5, bi.w, bi.h,
                bi.w * 0.15,  -- cornerRadius
                feather,      -- feather (大范围扩散)
                nvgRGBAf(1.0, 0.92, 0.75, glowAlpha),
                nvgRGBAf(1.0, 0.8, 0.5, 0))
            nvgFillPaint(vg, grad)
            nvgFill(vg)

            -- 原始图片
            nvgGlobalAlpha(vg, 1.0)
            local pat = nvgImagePattern(vg, -bi.w * 0.5, -bi.h * 0.5, bi.w, bi.h, 0, bi.handle, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, -bi.w * 0.5, -bi.h * 0.5, bi.w, bi.h)
            nvgFillPaint(vg, pat)
            nvgFill(vg)

            nvgRestore(vg)
        end
    end

    -- 层级2.8: 光线特效 (技能影响光束)
    if #lightBeams > 0 then
        for _, beam in ipairs(lightBeams) do
            local progress = beam.elapsed / beam.duration
            -- 前20%快速亮起，后80%线性淡出
            local alpha
            if progress < 0.2 then
                alpha = progress / 0.2  -- 0→1 快速亮起
            else
                alpha = 1.0 - (progress - 0.2) / 0.8  -- 1→0 淡出
            end
            alpha = math.max(0, math.min(1, alpha))

            -- 绘制光束: 粗线 + 发光效果
            nvgSave(vg)

            -- 外层辉光 (宽, 半透明)
            nvgBeginPath(vg)
            nvgMoveTo(vg, beam.x1, beam.y1)
            nvgLineTo(vg, beam.x2, beam.y2)
            nvgStrokeColor(vg, nvgRGBAf(beam.r, beam.g, beam.b, alpha * 0.25))
            nvgStrokeWidth(vg, 12)
            nvgLineCap(vg, NVG_ROUND)
            nvgStroke(vg)

            -- 中层 (中等宽度)
            nvgBeginPath(vg)
            nvgMoveTo(vg, beam.x1, beam.y1)
            nvgLineTo(vg, beam.x2, beam.y2)
            nvgStrokeColor(vg, nvgRGBAf(beam.r, beam.g, beam.b, alpha * 0.5))
            nvgStrokeWidth(vg, 5)
            nvgLineCap(vg, NVG_ROUND)
            nvgStroke(vg)

            -- 核心高亮 (窄, 白色混合)
            nvgBeginPath(vg)
            nvgMoveTo(vg, beam.x1, beam.y1)
            nvgLineTo(vg, beam.x2, beam.y2)
            local coreR = beam.r * 0.5 + 0.5
            local coreG = beam.g * 0.5 + 0.5
            local coreB = beam.b * 0.5 + 0.5
            nvgStrokeColor(vg, nvgRGBAf(coreR, coreG, coreB, alpha * 0.8))
            nvgStrokeWidth(vg, 2)
            nvgLineCap(vg, NVG_ROUND)
            nvgStroke(vg)

            nvgRestore(vg)
        end
    end

    -- 层级3: 飞行卡牌 (在UI上方) - NanoVG Bloom 辉光效果
    local cardW, cardH = 90, 126
    local cardR = 10
    -- Bloom 参数
    local BLOOM_INNER_ALPHA = 0.4
    local BLOOM_SIZE = 2.2
    for _, fc in ipairs(flyingCards) do
        nvgSave(vg)
        nvgTranslate(vg, fc.x, fc.y)
        nvgScale(vg, fc.scale, fc.scale)
        nvgGlobalAlpha(vg, fc.alpha)

        -- Bloom 辉光层: 使用 BoxGradient 产生柔和发光
        local feather = 25 * BLOOM_SIZE  -- 发光扩散距离
        local bloomX = -cardW/2
        local bloomY = -cardH/2
        local bloomAlpha = BLOOM_INNER_ALPHA * fc.alpha
        nvgBeginPath(vg)
        nvgRect(vg, bloomX - feather, bloomY - feather, cardW + feather * 2, cardH + feather * 2)
        local bloomGrad = nvgBoxGradient(vg, bloomX, bloomY, cardW, cardH, cardR, feather,
            nvgRGBAf(0.35, 0.55, 1.0, bloomAlpha),
            nvgRGBAf(0.35, 0.55, 1.0, 0))
        nvgFillPaint(vg, bloomGrad)
        nvgFill(vg)

        -- 卡牌主体
        nvgBeginPath(vg)
        nvgRoundedRect(vg, -cardW/2, -cardH/2, cardW, cardH, cardR)
        nvgFillColor(vg, nvgRGBA(50, 70, 130, 245))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(120, 160, 230, 220))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
        -- 卡背内部图案
        nvgBeginPath(vg)
        nvgRoundedRect(vg, -cardW/2 + 12, -cardH/2 + 12, cardW - 24, cardH - 24, 5)
        nvgFillColor(vg, nvgRGBA(35, 50, 95, 210))
        nvgFill(vg)
        -- 菱形装饰
        nvgBeginPath(vg)
        nvgMoveTo(vg, 0, -cardH/2 + 20)
        nvgLineTo(vg, cardW/2 - 18, 0)
        nvgLineTo(vg, 0, cardH/2 - 20)
        nvgLineTo(vg, -cardW/2 + 18, 0)
        nvgClosePath(vg)
        nvgStrokeColor(vg, nvgRGBA(100, 140, 220, 150))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgRestore(vg)
    end

    -- 层级4: 粒子 (在UI上方)
    if particles and particles:IsActive() then
        particles:Render(vg)
    end

    nvgEndFrame(vg)
end

return VFXManager
