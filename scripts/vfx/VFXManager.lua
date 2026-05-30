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
---@type any NanoVG overlay context (渲染在 UI 上层, 用于飘字)
local vgOverlay = nil
---@type number
local fontId = -1
---@type number
local fontIdOverlay = -1
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
---@type table[] 飘字列表 {x, y, text, r, g, b, elapsed, duration}
local floatingTexts = {}

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

    -- 创建 overlay 上下文 (渲染在 UI 上层, 用于飘字)
    vgOverlay = nvgCreate(1)
    fontIdOverlay = nvgCreateFont(vgOverlay, "sans", "Fonts/MiSans-Regular.ttf")
    nvgSetRenderOrder(vgOverlay, 999995)  -- UI=999990, 比UI高

    -- 订阅 NanoVG 渲染事件
    SubscribeToEvent(vg, "NanoVGRender", "HandleVFXRender")
    SubscribeToEvent(vgOverlay, "NanoVGRender", "HandleVFXOverlayRender")
end

--- 销毁
function VFXManager.Shutdown()
    if vgOverlay then
        nvgDelete(vgOverlay)
        vgOverlay = nil
    end
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

    -- 更新飘字
    local fi = 1
    while fi <= #floatingTexts do
        local ft = floatingTexts[fi]
        ft.elapsed = ft.elapsed + dt
        if ft.elapsed >= ft.duration then
            table.remove(floatingTexts, fi)
        else
            fi = fi + 1
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

--- 胜利烟花 (四角向中央金色粒子)
---@param cx number 中心X (目标点)
---@param cy number 中心Y (目标点)
function VFXManager.EmitWinParticles(cx, cy)
    if not particles then return end
    local sw = graphics:GetWidth() / graphics:GetDPR()
    local sh = graphics:GetHeight() / graphics:GetDPR()
    -- 四个角
    local corners = {
        { x = 0, y = 0 },
        { x = sw, y = 0 },
        { x = 0, y = sh },
        { x = sw, y = sh },
    }
    for _, corner in ipairs(corners) do
        particles:EmitToward(corner.x, corner.y, cx, cy, 30, {
            r = 1.0, g = 0.85, b = 0.2,
            speed = 700,
            life = 1.8,
            radius = 7,
            spread = 0.5,
        })
        -- 追加白色小粒子
        particles:EmitToward(corner.x, corner.y, cx, cy, 18, {
            r = 1.0, g = 1.0, b = 0.9,
            speed = 500,
            life = 1.2,
            radius = 4,
            spread = 0.4,
        })
    end
end

--- 失败粒子 (四角向中央暗红)
---@param cx number 中心X (目标点)
---@param cy number 中心Y (目标点)
function VFXManager.EmitLoseParticles(cx, cy)
    if not particles then return end
    local sw = graphics:GetWidth() / graphics:GetDPR()
    local sh = graphics:GetHeight() / graphics:GetDPR()
    local corners = {
        { x = 0, y = 0 },
        { x = sw, y = 0 },
        { x = 0, y = sh },
        { x = sw, y = sh },
    }
    for _, corner in ipairs(corners) do
        particles:EmitToward(corner.x, corner.y, cx, cy, 22, {
            r = 0.8, g = 0.2, b = 0.2,
            speed = 500,
            life = 1.2,
            radius = 6,
            spread = 0.5,
        })
    end
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
        radius = 7,
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

--- 发射飘字 (随机倾斜, 随机方向渐出)
---@param x number 中心X
---@param y number 起始Y
---@param text string 文字内容
---@param opts table|nil {r, g, b, duration, fontSize}
function VFXManager.EmitFloatingText(x, y, text, opts)
    opts = opts or {}
    -- 随机方向角度 (弧度)
    local angle = (math.random() * 2 - 1) * math.pi * 0.4 + (-math.pi / 2)  -- 大致向上, 带随机偏移
    local speed = 50 + math.random() * 30  -- 飘动速度
    -- 随机倾斜角度 (-25° ~ +25°)
    local tilt = (math.random() * 2 - 1) * 25

    table.insert(floatingTexts, {
        x = x, y = y,
        text = text,
        r = opts.r or 1.0,
        g = opts.g or 1.0,
        b = opts.b or 1.0,
        fontSize = opts.fontSize or 18,
        duration = opts.duration or 1.2,
        elapsed = 0,
        dirX = math.cos(angle) * speed,
        dirY = math.sin(angle) * speed,
        tilt = tilt,
    })
end

--- 清除所有飘字
function VFXManager.ClearFloatingTexts()
    floatingTexts = {}
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

    -- 层级2.5: 图片辉光 (中心点光源 + 呼吸效果 + 旋转, 无背景副本)
    if #bloomImages > 0 then
        for _, bi in ipairs(bloomImages) do
            nvgSave(vg)
            local cx = bi.x + bi.w * 0.5
            local cy = bi.y + bi.h * 0.5
            nvgTranslate(vg, cx, cy)
            if bi.rotate ~= 0 then
                nvgRotate(vg, bi.rotate * math.pi / 180)
            end

            -- 点光源: 呼吸 (无旋转)
            local intensity = bi.intensity
            local glowStrength = math.max(0, intensity - 1.0)
            local breath = 0.85 + 0.15 * math.sin(time * 3.0)
            local glowAlpha = 0.6 * glowStrength * breath

            -- 圆形光源 (缩小)
            local radius = math.max(bi.w, bi.h) * 0.5 * (0.9 + 0.1 * breath)

            -- 外层柔光 (天色 あまいろ #2ca9e1 霓虹感)
            nvgBeginPath(vg)
            nvgCircle(vg, 0, 0, radius * 1.5)
            local outerGrad = nvgRadialGradient(vg, 0, 0, 0, radius * 1.3,
                nvgRGBAf(0.173, 0.663, 0.882, glowAlpha * 0.4),
                nvgRGBAf(0.1, 0.5, 0.8, 0))
            nvgFillPaint(vg, outerGrad)
            nvgFill(vg)

            -- 核心亮点 (白青色中心)
            nvgBeginPath(vg)
            nvgCircle(vg, 0, 0, radius * 0.6)
            local coreGrad = nvgRadialGradient(vg, 0, 0, 0, radius * 0.4,
                nvgRGBAf(0.7, 0.95, 1.0, glowAlpha * 0.85),
                nvgRGBAf(0.173, 0.663, 0.882, 0))
            nvgFillPaint(vg, coreGrad)
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

    -- 飘字已移至 overlay 上下文 (HandleVFXOverlayRender), 不在此层渲染

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

-- ============================================================================
-- Overlay NanoVG 渲染回调 (飘字, 渲染在 UI 上层)
-- ============================================================================

--- Overlay 渲染事件处理 (renderOrder 999995, 在 UI 上层)
function HandleVFXOverlayRender(eventType, eventData)
    if not vgOverlay then return end
    if #floatingTexts == 0 then return end

    local sw = graphics:GetWidth() / graphics:GetDPR()
    local sh = graphics:GetHeight() / graphics:GetDPR()

    nvgBeginFrame(vgOverlay, sw, sh, graphics:GetDPR())

    nvgFontFace(vgOverlay, "sans")
    nvgTextAlign(vgOverlay, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    for _, ft in ipairs(floatingTexts) do
        local progress = ft.elapsed / ft.duration
        -- 随机方向偏移
        local offsetX = ft.dirX * progress
        local offsetY = ft.dirY * progress
        -- 淡入淡出: 前15%快速亮起, 后40%淡出
        local alpha
        if progress < 0.15 then
            alpha = progress / 0.15
        elseif progress > 0.6 then
            alpha = 1.0 - (progress - 0.6) / 0.4
        else
            alpha = 1.0
        end
        alpha = math.max(0, math.min(1, alpha))

        nvgSave(vgOverlay)
        nvgTranslate(vgOverlay, ft.x + offsetX, ft.y + offsetY)
        nvgRotate(vgOverlay, ft.tilt * math.pi / 180)
        nvgFontSize(vgOverlay, ft.fontSize * 3)

        -- 描边 (多方向偏移绘制黑色轮廓)
        local strokeW = 2.5
        nvgFillColor(vgOverlay, nvgRGBAf(0, 0, 0, alpha * 0.9))
        for ox = -strokeW, strokeW, strokeW do
            for oy = -strokeW, strokeW, strokeW do
                if ox ~= 0 or oy ~= 0 then
                    nvgText(vgOverlay, ox, oy, ft.text)
                end
            end
        end

        -- 正文
        nvgFillColor(vgOverlay, nvgRGBAf(ft.r, ft.g, ft.b, alpha))
        nvgText(vgOverlay, 0, 0, ft.text)

        nvgRestore(vgOverlay)
    end

    nvgEndFrame(vgOverlay)
end

return VFXManager
