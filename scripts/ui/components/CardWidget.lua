-- ============================================================================
-- ui/components/CardWidget.lua - 卡牌 UI 组件
-- 支持: 更大尺寸显示、悬停放大高亮、效果提示文字
-- ============================================================================

local UI = require("urhox-libs/UI")
local Card = require("core.Card")
local Constant = require("core.Constant")
local SFXManager = require("system.SFXManager")

local CardWidget = {}

-- 呼吸动画: 存储所有带光晕的卡牌引用
local glowCards = {}
local breathTime = 0

-- 卡牌尺寸 (3倍大)
local CARD_WIDTH = 216
local CARD_HEIGHT = 300

-- AI 卡牌尺寸 (稍小)
local AI_CARD_WIDTH = 120
local AI_CARD_HEIGHT = 168

-- 颜色定义
local COLORS = {
    cardBg = { 255, 252, 245, 255 },
    cardSelected = { 180, 230, 255, 255 },
    cardHover = { 255, 255, 240, 255 },
    black = { 35, 35, 35, 255 },
    red = { 200, 50, 50, 255 },
    jokerPurple = { 150, 80, 200, 255 },
    accent = { 80, 160, 255, 255 },
    cardBack = { 80, 100, 140, 255 },
    cardBackBg = { 60, 75, 110, 255 },
}

--- 获取卡牌效果描述文字
---@param card table
---@return string|nil
local function getCardEffectText(card)
    if not card then return nil end
    if Card.IsJoker(card) then
        if card.rank == 14 then
            return "小王: 点数可选0~13, 移除对方一张牌"
        else
            return "大王: 选一张手牌设为任意点数(仅当局有效), 大王自身也选任意点数"
        end
    end
    local rank = card.rank
    if rank == 1 then return "A: 结算时翻倍对方同花色牌点数" end
    if rank == 7 then return "7: 不可被改变点数/删除, 3张7触发特殊胜负" end
    if rank == 8 then return "8: 结算时己方普通牌各-1点, 对方普通牌各+2点(可叠加)" end
    if rank == 9 then return "9: 结算时点数可视为0或9" end
    if rank == 10 then return "10(10点): 若弃置过此牌, 最终点数+1" end
    if rank == 11 then return "J(11点): 弃置含J时, 所有补牌可逐张选择来源; 结算时手中有J则对方普通牌×2" end
    if rank == 12 then return "Q(12点): 结算时使对方最大普通牌点数×2(可叠加)" end
    if rank == 13 then return "K: 结算时对方点数向上取整到十位, 己方点数向下取整到十位" end
    if rank >= 2 and rank <= 6 then
        return string.format("%d: 普通牌, %d点", rank, rank)
    end
    return nil
end

--- 获取卡牌光晕颜色和大小 (用于 shadowColor / shadowBlur)
---@param card table|nil
---@return table|nil glowColor {r, g, b, a}
---@return number baseBlur 光晕模糊半径
local function getGlowColor(card)
    if not card then return nil, 0 end
    -- 鬼牌: 暗金色, 最大光晕
    if Card.IsJoker(card) then return { 180, 150, 50, 220 }, 120 end
    -- A: 金色, 第二大光晕
    if card.rank == 1 then return { 255, 210, 60, 200 }, 100 end
    -- J~K: 紫色, 第三大光晕
    if card.rank == 11 then return { 160, 80, 255, 220 }, 70 end
    if card.rank == 12 then return { 160, 80, 255, 220 }, 70 end
    if card.rank == 13 then return { 160, 80, 255, 220 }, 70 end
    -- 8~10: 蓝色
    if card.rank == 8 then return { 100, 180, 255, 180 }, 50 end
    if card.rank == 9 then return { 100, 180, 255, 180 }, 50 end
    if card.rank == 10 then return { 100, 180, 255, 180 }, 50 end
    -- 7: 绿色
    if card.rank == 7 then return { 60, 255, 120, 200 }, 50 end
    return nil, 0
end

--- 创建一个卡牌 UI 组件
---@param card table|nil 卡牌数据(nil 表示牌背)
---@param opts table 选项 {selected, selectable, onClick, isAI}
---@return table widget
function CardWidget.Create(card, opts)
    opts = opts or {}
    local isSelected = opts.selected or false
    local selectable = opts.selectable or false
    local isAI = opts.isAI or false
    local isSmall = opts.small or false

    local w = isAI and AI_CARD_WIDTH or (isSmall and 150 or CARD_WIDTH)
    local h = isAI and AI_CARD_HEIGHT or (isSmall and 210 or CARD_HEIGHT)

    local bgColor = isSelected and COLORS.cardSelected or COLORS.cardBg
    local hoverBg = isSelected and { 160, 210, 255, 255 } or COLORS.cardHover
    local borderColor = isSelected and COLORS.accent or { 180, 180, 180, 150 }
    local hoverBorderColor = isSelected and { 60, 140, 255, 255 } or { 120, 150, 200, 200 }
    local borderWidth = isSelected and 2 or 1

    local rankFontSize = isAI and 28 or (isSmall and 38 or 54)
    local suitFontSize = isAI and 44 or (isSmall and 60 or 84)

    -- 卡牌光晕 (加大范围使其更醒目)
    local glowColor, glowBaseBlur = getGlowColor(card)
    local shadowBlur = glowColor and (isAI and math.floor(glowBaseBlur * 0.6) or glowBaseBlur) or 0

    local cardContent
    if not card then
        -- 牌背
        cardContent = {
            UI.Panel {
                width = w - 20,
                height = h - 20,
                backgroundColor = COLORS.cardBackBg,
                borderRadius = 8,
                borderWidth = 2,
                borderColor = { 70, 90, 130, 200 },
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "?",
                        fontSize = isAI and 40 or 72,
                        fontColor = { 120, 140, 180, 255 },
                        textAlign = "center",
                    },
                }
            }
        }
    else
        local suitColor = COLORS.black
        local suitSymbol = ""
        local rankText = ""

        if Card.IsJoker(card) then
            suitColor = COLORS.jokerPurple
            suitSymbol = "★"
            rankText = card.rank == 14 and "小" or "大"
        else
            suitColor = Constant.SUIT_COLORS[card.suit] or COLORS.black
            suitSymbol = Constant.SUIT_SYMBOLS[card.suit] or "?"
            rankText = Constant.RANK_NAMES[card.rank] or "?"
        end

        cardContent = {
            UI.Label {
                text = rankText,
                fontSize = rankFontSize,
                fontColor = suitColor,
                textAlign = "center",
            },
            UI.Label {
                text = suitSymbol,
                fontSize = suitFontSize,
                fontColor = suitColor,
                textAlign = "center",
            },
        }
    end

    local cardPanel = UI.Button {
        width = w,
        height = h,
        backgroundColor = card and bgColor or COLORS.cardBack,
        hoverBackgroundColor = card and hoverBg or { 90, 110, 150, 255 },
        pressedBackgroundColor = isSelected and { 140, 190, 240, 255 } or { 240, 240, 230, 255 },
        borderRadius = 8,
        borderWidth = borderWidth,
        borderColor = borderColor,
        hoverBorderColor = hoverBorderColor,
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        pointerEvents = (selectable or (card ~= nil)) and "auto" or "none",
        transition = "scale 0.15s easeOut",
        transformOrigin = "center",
        -- 卡牌光晕 (彩色阴影)
        shadowX = 0,
        shadowY = 0,
        shadowBlur = shadowBlur,
        shadowColor = glowColor or { 0, 0, 0, 0 },
        children = cardContent,
        onClick = (selectable and opts.onClick) and opts.onClick or nil,
    }

    -- 注册到呼吸动画列表
    if glowColor then
        table.insert(glowCards, {
            panel = cardPanel,
            baseBlur = shadowBlur,
            color = glowColor,
        })
    end

    -- 有卡牌数据且不是AI的牌时，包裹 Tooltip 显示效果提示
    local skipTooltip = opts.skipTooltip or false
    local effectText = card and getCardEffectText(card) or nil
    if effectText and not isAI and not skipTooltip then
        -- 先创建 Tooltip 容器
        -- delay 不能为 0（Tooltip 内部 timer < delay 条件会恒 false），用极小值模拟即时
        local tooltipWrapper = UI.Tooltip {
            content = effectText,
            position = "top",
            delay = 0.001,
            maxWidth = 700,
            children = { cardPanel },
        }

        -- 重写 RenderTooltip 以强制使用大字号（绕过内置 fontSize 属性不生效的问题）
        local TOOLTIP_FONT_SIZE = 40  -- 约为默认 12px 的 3.3 倍
        local TOOLTIP_PADDING = 14
        local TOOLTIP_RADIUS = 8
        tooltipWrapper.RenderTooltip = function(self, nvg)
            local text = self.content_
            if not text or text == "" then return end
            local tb = self.triggerBounds_
            if not tb then return end

            local alpha = self.opacity_
            if alpha <= 0 then return end

            -- 设置字体
            nvgFontFace(nvg, "sans")
            nvgFontSize(nvg, TOOLTIP_FONT_SIZE)

            -- 测量文本宽度
            local textWidth = nvgTextBounds(nvg, 0, 0, text) or 0
            if textWidth <= 0 then textWidth = #text * TOOLTIP_FONT_SIZE * 0.5 end
            textWidth = math.min(textWidth, 700)

            local tooltipW = textWidth + TOOLTIP_PADDING * 2
            local tooltipH = TOOLTIP_FONT_SIZE + TOOLTIP_PADDING * 2

            -- 定位: 在触发元素上方居中
            local x = tb.x + tb.w / 2 - tooltipW / 2
            local y = tb.y - tooltipH - 10

            -- 屏幕边界裁剪
            local screenW = UI.GetWidth() or 1200
            local screenH = UI.GetHeight() or 800
            x = math.max(4, math.min(screenW - tooltipW - 4, x))
            if y < 4 then y = tb.y + tb.h + 10 end -- 上方放不下就放下方

            -- 绘制阴影
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, x + 1, y + 2, tooltipW, tooltipH, TOOLTIP_RADIUS)
            nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(60 * alpha)))
            nvgFill(nvg)

            -- 绘制背景
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, x, y, tooltipW, tooltipH, TOOLTIP_RADIUS)
            nvgFillColor(nvg, nvgRGBA(30, 30, 30, math.floor(240 * alpha)))
            nvgFill(nvg)

            -- 绘制箭头（指向下方）
            local arrowX = tb.x + tb.w / 2
            local arrowY = y + tooltipH
            if y > tb.y then -- 如果 tooltip 在下方，箭头指向上方
                arrowY = y
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, arrowX - 6, arrowY)
                nvgLineTo(nvg, arrowX, arrowY - 6)
                nvgLineTo(nvg, arrowX + 6, arrowY)
                nvgClosePath(nvg)
            else
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, arrowX - 6, arrowY)
                nvgLineTo(nvg, arrowX, arrowY + 6)
                nvgLineTo(nvg, arrowX + 6, arrowY)
                nvgClosePath(nvg)
            end
            nvgFillColor(nvg, nvgRGBA(30, 30, 30, math.floor(240 * alpha)))
            nvgFill(nvg)

            -- 绘制文本
            nvgFontFace(nvg, "sans")
            nvgFontSize(nvg, TOOLTIP_FONT_SIZE)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, math.floor(255 * alpha)))
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(nvg, x + tooltipW / 2, y + tooltipH / 2, text)
        end

        -- 事件注册在 cardPanel 上（指针命中的是 cardPanel，Tooltip 包装后仍 dispatch）
        -- scale 设在 cardPanel（视觉放大），zIndex 设在 tooltipWrapper（在兄弟中提升层级）
        cardPanel:OnEvent("pointerenter", function()
            SFXManager.Play("buttonFocus")
            cardPanel:SetStyle({ scale = 1.2 })
            tooltipWrapper:SetStyle({ zIndex = 100 })
        end)
        cardPanel:OnEvent("pointerleave", function()
            cardPanel:SetStyle({ scale = 1.0 })
            tooltipWrapper:SetStyle({ zIndex = 0 })
        end)

        return tooltipWrapper
    end

    -- 无 Tooltip 的卡牌 (普通牌2~6无特效文字，或AI牌)
    if not isAI then
        cardPanel:OnEvent("pointerenter", function()
            SFXManager.Play("buttonFocus")
            cardPanel:SetStyle({ scale = 1.2, zIndex = 100 })
        end)
        cardPanel:OnEvent("pointerleave", function()
            cardPanel:SetStyle({ scale = 1.0, zIndex = 0 })
        end)
    end

    return cardPanel
end

--- 每帧更新呼吸动画 (由 main.lua HandleUpdate 调用)
---@param dt number deltaTime
function CardWidget.UpdateBreathing(dt)
    breathTime = breathTime + dt
    -- sin 呼吸: 周期约2秒
    local pulse = math.sin(breathTime * 3.0) -- 3.0 rad/s ≈ 2.1秒周期
    local factor = 0.6 + 0.4 * (0.5 + pulse * 0.5) -- 范围 0.6~1.0

    for i = #glowCards, 1, -1 do
        local item = glowCards[i]
        local panel = item.panel
        -- 检查面板是否还有效(未被移除)
        if panel and panel.SetStyle then
            local newBlur = math.floor(item.baseBlur * factor)
            local c = item.color
            local newAlpha = math.floor(c[4] * factor)
            panel:SetStyle({
                shadowBlur = newBlur,
                shadowColor = { c[1], c[2], c[3], newAlpha },
            })
        else
            table.remove(glowCards, i)
        end
    end
end

--- 清空呼吸动画列表 (在 Refresh/场景切换时调用)
function CardWidget.ClearBreathingList()
    glowCards = {}
end

return CardWidget
