-- ============================================================================
-- ui/components/CardWidget.lua - 卡牌 UI 组件
-- 支持: 更大尺寸显示、悬停放大高亮、效果提示文字
-- ============================================================================

local UI = require("urhox-libs/UI")
local Card = require("core.Card")
local Constant = require("core.Constant")

local CardWidget = {}

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
            return "大王: 点数可选0~13, 可将自己一张牌视为任意点数"
        end
    end
    local rank = card.rank
    if rank == 1 then return "A: 结算时翻倍对方同花色牌点数" end
    if rank == 7 then return "7: 不可被改变点数/删除, 3张7触发特殊胜负" end
    if rank == 8 then return "8: 使自己普通牌(2~6)点数各减1" end
    if rank == 9 then return "9: 结算时点数可视为0或9" end
    if rank == 10 then return "10(10点): 若弃置过此牌, 最终点数+1" end
    if rank == 11 then return "J(11点): 弃置时从弃牌堆抽牌; 结算前翻倍对方普通牌" end
    if rank == 12 then return "Q(12点): 结算时使对方点数最小的牌变为0" end
    if rank == 13 then return "K(13点): 手中每张K最终点数+1" end
    if rank >= 2 and rank <= 6 then
        return string.format("%d: 普通牌, %d点", rank, rank)
    end
    return nil
end

--- 获取卡牌光晕颜色 (用于 shadowColor)
---@param card table|nil
---@return table|nil glowColor {r, g, b, a}
local function getGlowColor(card)
    if not card then return nil end
    if Card.IsJoker(card) then return { 180, 60, 220, 120 } end   -- 紫色
    if card.rank == 1 then return { 255, 200, 50, 100 } end       -- 金色 (A)
    if card.rank == 7 then return { 50, 220, 100, 100 } end       -- 绿色
    if card.rank == 8 then return { 100, 180, 255, 80 } end       -- 蓝色
    if card.rank == 9 then return { 255, 150, 50, 80 } end        -- 橙色
    if card.rank == 10 then return { 255, 220, 80, 80 } end       -- 亮黄
    if card.rank == 11 then return { 120, 80, 255, 110 } end      -- 蓝紫 (J)
    if card.rank == 12 then return { 255, 80, 150, 100 } end      -- 粉红 (Q)
    if card.rank == 13 then return { 255, 50, 50, 100 } end       -- 红色 (K)
    return nil
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

    local w = isAI and AI_CARD_WIDTH or CARD_WIDTH
    local h = isAI and AI_CARD_HEIGHT or CARD_HEIGHT

    local bgColor = isSelected and COLORS.cardSelected or COLORS.cardBg
    local hoverBg = isSelected and { 160, 210, 255, 255 } or COLORS.cardHover
    local borderColor = isSelected and COLORS.accent or { 180, 180, 180, 150 }
    local hoverBorderColor = isSelected and { 60, 140, 255, 255 } or { 120, 150, 200, 200 }
    local borderWidth = isSelected and 2 or 1

    local rankFontSize = isAI and 28 or 54
    local suitFontSize = isAI and 44 or 84

    -- 卡牌光晕
    local glowColor = getGlowColor(card)
    local shadowBlur = glowColor and (isAI and 12 or 20) or 0

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

    -- 悬停放大效果 (仅玩家手牌)
    if not isAI then
        cardPanel:OnEvent("pointerenter", function()
            cardPanel:SetStyle({ scale = 1.2 })
        end)
        cardPanel:OnEvent("pointerleave", function()
            cardPanel:SetStyle({ scale = 1.0 })
        end)
    end

    -- 有卡牌数据且不是AI的牌时，包裹 Tooltip 显示效果提示
    local effectText = card and getCardEffectText(card) or nil
    if effectText and not isAI then
        return UI.Tooltip {
            content = effectText,
            position = "top",
            delay = 0.3,
            maxWidth = 260,
            children = { cardPanel },
        }
    end

    return cardPanel
end

return CardWidget
