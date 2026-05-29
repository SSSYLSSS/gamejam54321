-- ============================================================================
-- ui/components/CardWidget.lua - 卡牌 UI 组件
-- 支持: 更大尺寸显示、悬停放大高亮、效果提示文字
-- ============================================================================

local UI = require("urhox-libs/UI")
local Card = require("core.Card")
local Constant = require("core.Constant")

local CardWidget = {}

-- 卡牌尺寸
local CARD_WIDTH = 72
local CARD_HEIGHT = 100

-- AI 卡牌尺寸 (稍小)
local AI_CARD_WIDTH = 60
local AI_CARD_HEIGHT = 84

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
    if rank == 7 then return "7: 不可弃置/修改, 3张7触发特殊规则" end
    if rank == 8 then return "8: 使自己普通牌(2~6)点数各减1" end
    if rank == 11 then return "J: 弃置时可从牌堆随机抽一张牌" end
    if rank == 12 then return "Q: 0点花牌, 无特效" end
    if rank == 13 then return "K: 0点花牌, 无特效" end
    if rank >= 2 and rank <= 6 then
        return string.format("%d: 普通牌, %d点", rank, rank)
    end
    if rank == 9 then return "9: 稀有牌, 9点" end
    if rank == 10 then return "10: 稀有牌, 10点" end

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

    local rankFontSize = isAI and 14 or 18
    local suitFontSize = isAI and 22 or 28

    local cardContent
    if not card then
        -- 牌背
        cardContent = {
            UI.Panel {
                width = w - 12,
                height = h - 12,
                backgroundColor = COLORS.cardBackBg,
                borderRadius = 4,
                borderWidth = 1,
                borderColor = { 70, 90, 130, 200 },
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "🂠",
                        fontSize = isAI and 24 or 30,
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
            suitSymbol = "🃏"
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
        backgroundColor = bgColor,
        hoverBackgroundColor = hoverBg,
        pressedBackgroundColor = isSelected and { 140, 190, 240, 255 } or { 240, 240, 230, 255 },
        borderRadius = 8,
        borderWidth = borderWidth,
        borderColor = borderColor,
        hoverBorderColor = hoverBorderColor,
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        pointerEvents = (selectable or (card ~= nil)) and "auto" or "none",
        children = cardContent,
        onClick = (selectable and opts.onClick) and opts.onClick or nil,
    }

    -- 有卡牌数据且不是AI的牌背时，包裹 Tooltip 显示效果提示
    local effectText = card and getCardEffectText(card) or nil
    if effectText and not isAI then
        return UI.Tooltip {
            content = effectText,
            position = "top",
            delay = 0.2,
            maxWidth = 280,
            children = { cardPanel },
        }
    end

    return cardPanel
end

return CardWidget
