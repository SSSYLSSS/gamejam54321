-- ============================================================================
-- vfx/ParticleSystem.lua - NanoVG 粒子系统
-- 支持: 胜利烟花、弃牌飞散、金色碎片
-- ============================================================================

local VFXConfig = require("vfx.VFXConfig")

local ParticleSystem = {}
ParticleSystem.__index = ParticleSystem

-- 星星纹理资源路径
local STAR_IMAGES = {
    "pic/stars/Star1.png",
    "pic/stars/Star2.png",
    "pic/stars/Star3.png",
    "pic/stars/Star4.png",
    "pic/stars/Star5.png",
}

-- 已加载的 NanoVG 图片句柄 (全局共享)
local starHandles = nil  -- {[1]=handle, [2]=handle, ...}
local starHandlesCtx = nil  -- 记录加载时的 ctx，防止重复加载

---@class Particle
---@field x number
---@field y number
---@field vx number
---@field vy number
---@field life number
---@field maxLife number
---@field radius number
---@field r number
---@field g number
---@field b number
---@field brightness number

--- 创建粒子系统实例
---@return table
function ParticleSystem.New()
    local self = setmetatable({}, ParticleSystem)
    self.particles = {}
    return self
end

--- 发射一组粒子 (胜利烟花效果)
---@param x number 发射中心X
---@param y number 发射中心Y
---@param count number 粒子数量
---@param opts table|nil 可选参数 {color, speed, life, radius}
function ParticleSystem:Emit(x, y, count, opts)
    opts = opts or {}
    local baseR = opts.r or 1.0
    local baseG = opts.g or 0.85
    local baseB = opts.b or 0.2
    local speed = opts.speed or 200
    local life = opts.life or 1.5
    local radius = opts.radius or 4

    for _ = 1, count do
        if #self.particles >= VFXConfig.MAX_PARTICLES then break end

        local angle = math.random() * math.pi * 2
        local spd = speed * (0.3 + math.random() * 0.7)

        local p = {
            x = x,
            y = y,
            vx = math.cos(angle) * spd,
            vy = math.sin(angle) * spd,
            life = life * (0.6 + math.random() * 0.4),
            maxLife = life,
            radius = radius * (0.5 + math.random() * 0.5),
            r = baseR * (0.8 + math.random() * 0.2),
            g = baseG * (0.8 + math.random() * 0.2),
            b = baseB * (0.5 + math.random() * 0.5),
            brightness = 1.4 + math.random() * 0.4,
        }
        -- 40% 概率成为星星粒子
        if math.random() < 0.4 then
            p.starIdx = math.random(1, #STAR_IMAGES)
            p.rotation = math.random() * math.pi * 2
            p.rotSpeed = (math.random() - 0.5) * 4  -- 旋转速度
            p.radius = p.radius * 3.6  -- 星星大尺寸
        end
        table.insert(self.particles, p)
    end
end

--- 从指定位置向目标点发射粒子 (四角向中央)
---@param fromX number 起始X
---@param fromY number 起始Y
---@param toX number 目标X
---@param toY number 目标Y
---@param count number 粒子数量
---@param opts table|nil 可选参数 {r, g, b, speed, life, radius, spread}
function ParticleSystem:EmitToward(fromX, fromY, toX, toY, count, opts)
    opts = opts or {}
    local baseR = opts.r or 1.0
    local baseG = opts.g or 0.85
    local baseB = opts.b or 0.2
    local speed = opts.speed or 300
    local life = opts.life or 1.5
    local radius = opts.radius or 5
    local spread = opts.spread or 0.5  -- 角度散布(弧度)

    -- 计算从起点到目标的方向角
    local dx = toX - fromX
    local dy = toY - fromY
    local baseAngle = math.atan(dy, dx)

    for _ = 1, count do
        if #self.particles >= VFXConfig.MAX_PARTICLES then break end

        -- 在基础方向上加随机偏移
        local angle = baseAngle + (math.random() - 0.5) * spread
        local spd = speed * (0.5 + math.random() * 0.5)

        local p = {
            x = fromX + (math.random() - 0.5) * 30,
            y = fromY + (math.random() - 0.5) * 30,
            vx = math.cos(angle) * spd,
            vy = math.sin(angle) * spd,
            life = life * (0.6 + math.random() * 0.4),
            maxLife = life,
            radius = radius * (0.5 + math.random() * 0.5),
            r = baseR * (0.8 + math.random() * 0.2),
            g = baseG * (0.8 + math.random() * 0.2),
            b = baseB * (0.5 + math.random() * 0.5),
            brightness = 1.4 + math.random() * 0.4,
            noGravity = true,  -- 向目标飞行不受重力
        }
        -- 40% 概率成为星星粒子
        if math.random() < 0.4 then
            p.starIdx = math.random(1, #STAR_IMAGES)
            p.rotation = math.random() * math.pi * 2
            p.rotSpeed = (math.random() - 0.5) * 4
            p.radius = p.radius * 3.6  -- 星星大尺寸
        end
        table.insert(self.particles, p)
    end
end

--- 发射向上喷射的粒子 (弃牌效果)
---@param x number
---@param y number
---@param count number
function ParticleSystem:EmitUpward(x, y, count)
    for _ = 1, count do
        if #self.particles >= VFXConfig.MAX_PARTICLES then break end

        local p = {
            x = x + (math.random() - 0.5) * 40,
            y = y,
            vx = (math.random() - 0.5) * 60,
            vy = -(100 + math.random() * 80),
            life = 0.8 + math.random() * 0.4,
            maxLife = 1.0,
            radius = 4 + math.random() * 3,
            r = 0.4,
            g = 0.6,
            b = 1.0,
            brightness = 1.3,
        }
        table.insert(self.particles, p)
    end
end

--- 更新所有粒子
---@param dt number 时间步
function ParticleSystem:Update(dt)
    local gravity = VFXConfig.PARTICLE_GRAVITY
    local i = 1
    while i <= #self.particles do
        local p = self.particles[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(self.particles, i)
        else
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            if not p.noGravity then
                p.vy = p.vy + gravity * dt
            end
            -- 星星旋转更新
            if p.rotation then
                p.rotation = p.rotation + p.rotSpeed * dt
            end
            -- 亮度随生命衰减
            local lifeRatio = p.life / p.maxLife
            p.brightness = 1.0 + (p.brightness - 1.0) * lifeRatio
            i = i + 1
        end
    end
end

--- 确保星星图片已加载
---@param ctx any NanoVG context
local function ensureStarImages(ctx)
    if starHandles and starHandlesCtx == ctx then return end
    starHandles = {}
    starHandlesCtx = ctx
    for i, path in ipairs(STAR_IMAGES) do
        -- NVG_IMAGE_NEAREST = 1<<5 = 32, 使用最近邻过滤保持像素清晰
        local handle = nvgCreateImage(ctx, path, 32)
        starHandles[i] = handle
    end
end

--- 渲染所有粒子 (NanoVG)
---@param ctx any NanoVG context
function ParticleSystem:Render(ctx)
    ensureStarImages(ctx)

    for _, p in ipairs(self.particles) do
        local lifeRatio = p.life / p.maxLife
        -- alpha 在生命后30%才开始衰减，前70%保持满不透明
        local alpha = lifeRatio > 0.3 and 1.0 or (lifeRatio / 0.3)
        local radius = p.radius * (0.5 + lifeRatio * 0.5)

        local hdrR = p.r * p.brightness
        local hdrG = p.g * p.brightness
        local hdrB = p.b * p.brightness

        -- Bloom glow (只在亮度>1时，星星和圆形通用)
        if p.brightness > 1.0 then
            local maxR = radius * VFXConfig.BLOOM_SIZE * (1.0 + VFXConfig.BLOOM_OUTER_ALPHA * 3.0)
            local innerR = radius * VFXConfig.BLOOM_MID_ALPHA * 0.5

            nvgBeginPath(ctx)
            nvgCircle(ctx, p.x, p.y, maxR)
            local grad = nvgRadialGradient(ctx, p.x, p.y, innerR, maxR,
                nvgRGBAf(hdrR, hdrG, hdrB, VFXConfig.BLOOM_INNER_ALPHA * alpha),
                nvgRGBAf(hdrR, hdrG, hdrB, 0))
            nvgFillPaint(ctx, grad)
            nvgFill(ctx)
        end

        -- 星星粒子：用图片渲染
        if p.starIdx and starHandles and starHandles[p.starIdx] then
            local size = radius * 2.5
            nvgSave(ctx)
            nvgTranslate(ctx, p.x, p.y)
            nvgRotate(ctx, p.rotation or 0)
            nvgBeginPath(ctx)
            nvgRect(ctx, -size * 0.5, -size * 0.5, size, size)
            local imgPaint = nvgImagePattern(ctx, -size * 0.5, -size * 0.5, size, size, 0, starHandles[p.starIdx], alpha)
            nvgFillPaint(ctx, imgPaint)
            nvgFill(ctx)
            nvgRestore(ctx)
        else
            -- 普通圆形粒子
            nvgBeginPath(ctx)
            nvgCircle(ctx, p.x, p.y, radius)
            nvgFillColor(ctx, nvgRGBAf(
                math.min(1, hdrR),
                math.min(1, hdrG),
                math.min(1, hdrB),
                alpha
            ))
            nvgFill(ctx)
        end
    end
end

--- 是否还有活跃粒子
---@return boolean
function ParticleSystem:IsActive()
    return #self.particles > 0
end

--- 清除所有粒子
function ParticleSystem:Clear()
    self.particles = {}
end

return ParticleSystem
