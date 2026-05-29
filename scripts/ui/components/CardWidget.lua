-- ============================================================================
-- ui/components/CardWidget.lua - 卡牌 UI 组件
-- ============================================================================

local UI = require("urhox-libs/UI")
local Card = require("core.Card")
local Constant = require("core.Constant")

local CardWidget = {}

-- 颜色定义
local COLORS = {
    cardBg = { 255, 252, 245, 255 },
    cardSelected = { 180, 230, 255, 255 },
    black = { 35, 35, 35, 255 },
    red = { 200, 50, 50, 255 },
    jokerPurple = { 150, 80, 200, 255 },
    accent = { 80, 160, 255, 255 },
    cardBack = { 80, 100, 140, 255 },
}

--- 创建一个卡牌 UI 组件
---@param card table|nil 卡牌数据(nil 表示牌背)
---@param opts table 选项 {selected, selectable, onClick}
---@return table widget
function CardWidget.Create(card, opts)
    opts = opts or {}
    local isSelected = opts.selected or false
    local selectable = opts.selectable or false

    local bgColor = isSelected and COLORS.cardSelected or COLORS.cardBg
    local borderColor = isSelected and COLORS.accent or { 180, 180, 180, 150 }
    local borderWidth = isSelected and 2 or 1

    local cardContent
    if not card then
        -- 牌背
        cardContent = {
            UI.Label {
                text = "🂠",
                fontSize = 28,
                fontColor = COLORS.cardBack,
                textAlign = "center",
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
                fontSize = 14,
                fontColor = suitColor,
                textAlign = "center",
            },
            UI.Label {
                text = suitSymbol,
                fontSize = 20,
                fontColor = suitColor,
                textAlign = "center",
            },
        }
    end

    local widget = UI.Panel {
        width = 52,
        height = 72,
        backgroundColor = bgColor,
        borderRadius = 6,
        borderWidth = borderWidth,
        borderColor = borderColor,
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        pointerEvents = selectable and "auto" or "none",
        children = cardContent,
    }

    if selectable and opts.onClick then
        widget:OnEvent("click", opts.onClick)
    end

    return widget
end

return CardWidget
