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

-- ============================================================================
-- 卡牌光晕接口
-- ============================================================================

--- 设置当前帧的卡牌光晕列表 (由 GameScene 每帧设置)
---@param list table[] 每项 {x, y, w, h, type}
function VFXManager.SetCardGlowList(list)
    cardGlowList = list or {}
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

    -- 层级3: 粒子 (在UI上方)
    if particles and particles:IsActive() then
        particles:Render(vg)
    end

    nvgEndFrame(vg)
end

return VFXManager
