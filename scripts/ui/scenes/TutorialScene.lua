-- ============================================================================
-- ui/scenes/TutorialScene.lua - 新手教程场景
-- ============================================================================

local UI = require("urhox-libs/UI")
local Colors = require("ui.Colors")
local SFXManager = require("system.SFXManager")

local TutorialScene = {}

-- ============================================================================
-- 教程页面数据
-- ============================================================================

local PAGES = {
    {
        title = "游戏简介",
        icon = "🎯",
        content = {
            { type = "text", value = "本游戏为卡牌对战博弈游戏，目标是让手牌点数尽可能接近21而不超过。" },
            { type = "gap" },
            { type = "highlight", value = "一轮游戏中，双方共进行5场对弈，\n先胜3场者赢得整场比赛。" },
            { type = "gap" },
            { type = "text", value = "第一场开局时，双方抽牌堆各有54张牌。从中随机抽取5张构成初始手牌，对方不能看见己方的手牌。" },
        }
    },
    {
        title = "回合流程",
        icon = "🃏",
        content = {
            { type = "text", value = "每局分为三个抽牌回合：" },
            { type = "gap" },
            { type = "step", label = "五!", value = "可选至多5张牌丢弃，再抽相同张数" },
            { type = "step", label = "四!", value = "可选至多4张牌丢弃，再抽相同张数" },
            { type = "step", label = "三!", value = "可选至多3张牌丢弃，再抽相同张数" },
            { type = "gap" },
            { type = "text", value = "选牌后点「弃置」确认，或点「跳过」保留所有牌。" },
        }
    },
    {
        title = "结算胜负判定",
        icon = "⚖️",
        content = {
            { type = "text", value = "三个抽牌回合后，双方明牌结算：" },
            { type = "gap" },
            { type = "highlight", value = "总点数超过21即为「爆点」" },
            { type = "gap" },
            { type = "text", value = "• 仅一方爆点 → 未爆点方直接获胜" },
            { type = "text", value = "• 双方均未爆点 → 更接近21者获胜" },
            { type = "text", value = "• 双方均爆点 → 更接近21者获胜\n  （即「爆得少」的赢）" },
            { type = "text", value = "• 距离相同 → 平局" },
        }
    },
    {
        title = "结算后阶段",
        icon = "✨",
        content = {
            { type = "text", value = "结算后进入收尾阶段：" },
            { type = "gap" },
            { type = "text", value = "强制处理：若手牌中有鬼牌，将其弃置。" },
            { type = "gap" },
            { type = "step", label = "二!", value = "选至多2张手牌弃置至抽牌堆\n(下局可能再抽到)" },
            { type = "step", label = "一!", value = "选至多1张手牌保留至下一局\n(下局开始时直接在手中)" },
            { type = "gap" },
            { type = "text", value = "下一场对局，双方继承上一局结束时的抽牌堆和弃牌堆。" },
        }
    },
    {
        title = "稀有牌(8-10)",
        icon = "⚡",
        content = {
            { type = "card", rank = "8", desc = "己方普通牌各-2，对方普通牌各+2\n(可叠加)" },
            { type = "card", rank = "9", desc = "灵活牌：可视为 0 或 9 点\n(自动选择更优值)" },
            { type = "card", rank = "10", desc = "己方每张稀有牌和罕见牌点数-9\n(可叠加)" },
            { type = "gap" },
            { type = "highlight", value = "稀有牌显示紫色光效" },
        }
    },
    {
        title = "罕见牌(J-K) & A",
        icon = "⚡",
        content = {
            { type = "card", rank = "J", desc = "己方所有普通牌点数→0" },
            { type = "card", rank = "Q", desc = "对方最高普通牌点数×2\n己方点数取至十位(可叠加)" },
            { type = "card", rank = "K", desc = "对方普通牌和稀有牌点数×2(可叠加)" },
            { type = "card", rank = "A", desc = "对方同花色牌点数×2(可叠加)" },
            { type = "gap" },
            { type = "highlight", value = "罕见牌显示金色光效，A显示红色光效" },
        }
    },
    {
        title = "鬼牌效果",
        icon = "🃏",
        content = {
            { type = "text", value = "鬼牌在抽牌阶段结束后触发效果：" },
            { type = "gap" },
            { type = "card", rank = "小王", desc = "选择0~13作为小王自身点数" },
            { type = "card", rank = "大王", desc = "选一张手牌设为任意点数(0~13)\n大王自身也选任意点数(0~13)\n(仅当局生效)" },
            { type = "gap" },
            { type = "text", value = "鬼牌效果触发后仍保留在手中，以选定点数计入总分。" },
        }
    },
    {
        title = "结算顺序",
        icon = "📐",
        content = {
            { type = "text", value = "牌效果按以下顺序结算：" },
            { type = "gap" },
            { type = "step", label = "1", value = "基础点数(各牌面值之和)" },
            { type = "step", label = "2", value = "加减效果(8: 己方普通牌-2, 对方+2)" },
            { type = "step", label = "3", value = "乘算效果(J→0, K×2, A×2)" },
            { type = "step", label = "4", value = "最终修正(10: 稀有/罕见牌-9)" },
            { type = "step", label = "5", value = "Q效果(对方最高普通牌×2,\n己方点数取至十位)" },
            { type = "gap" },
            { type = "text", value = "9的灵活选择在全部计算后自动优化。" },
        }
    },
    {
        title = "小贴士",
        icon = "💡",
        content = {
            { type = "text", value = "• 不要一味追求高点数，控制在21以内更重要" },
            { type = "gap" },
            { type = "text", value = "• 特殊牌是取胜关键，合理利用弃置和保留" },
            { type = "gap" },
            { type = "text", value = "• 「二!」阶段可以把好牌放回牌堆下局再用" },
            { type = "gap" },
            { type = "text", value = "• 「一!」阶段保留的牌下局一开始就在手中" },
            { type = "gap" },
            { type = "text", value = "• 注意对手的弃牌，推测他们的手牌组合" },
            { type = "gap" },
            { type = "text", value = "准备好了？开始挑战吧！" },
        }
    },
}

-- ============================================================================
-- UI 构建
-- ============================================================================

--- 构建单页内容
---@param pageData table
---@return table[] children
local function BuildPageContent(pageData)
    local children = {}

    for _, item in ipairs(pageData.content) do
        if item.type == "text" then
            table.insert(children, UI.Label {
                text = item.value,
                fontSize = 13,
                fontColor = Colors.text,
                width = "100%",
            })
        elseif item.type == "highlight" then
            table.insert(children, UI.Panel {
                width = "100%",
                backgroundColor = { 218, 165, 32, 30 },
                borderRadius = 6,
                borderWidth = 1,
                borderColor = { 218, 165, 32, 80 },
                padding = 8,
                children = {
                    UI.Label {
                        text = item.value,
                        fontSize = 13,
                        fontColor = Colors.gold,
                        width = "100%",
                    },
                }
            })
        elseif item.type == "step" then
            table.insert(children, UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 10,
                alignItems = "flex-start",
                children = {
                    UI.Panel {
                        width = 48,
                        height = 26,
                        backgroundColor = Colors.accent,
                        borderRadius = 4,
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = item.label,
                                fontSize = 13,
                                fontColor = { 255, 255, 255, 255 },
                            },
                        }
                    },
                    UI.Panel {
                        flexShrink = 1,
                        flexGrow = 1,
                        children = {
                            UI.Label {
                                text = item.value,
                                fontSize = 12,
                                fontColor = Colors.text,
                                width = "100%",
                            },
                        }
                    },
                }
            })
        elseif item.type == "card" then
            table.insert(children, UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 10,
                alignItems = "flex-start",
                paddingVertical = 3,
                children = {
                    UI.Panel {
                        width = 36,
                        height = 24,
                        backgroundColor = { 50, 65, 90, 200 },
                        borderRadius = 4,
                        borderWidth = 1,
                        borderColor = Colors.gold,
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = item.rank,
                                fontSize = 12,
                                fontColor = Colors.gold,
                            },
                        }
                    },
                    UI.Panel {
                        flexShrink = 1,
                        flexGrow = 1,
                        children = {
                            UI.Label {
                                text = item.desc,
                                fontSize = 12,
                                fontColor = Colors.textDim,
                                width = "100%",
                            },
                        }
                    },
                }
            })
        elseif item.type == "gap" then
            table.insert(children, UI.Panel { height = 6 })
        end
    end

    return children
end

--- 构建教程 UI
---@param onBack function
---@return table root
function TutorialScene.Build(onBack)
    local currentPage = 1
    local totalPages = #PAGES

    ---@type table
    local contentPanel = nil
    ---@type table
    local pageTitle = nil
    ---@type table
    local pageIcon = nil
    ---@type table
    local pageIndicator = nil
    ---@type table
    local prevBtn = nil
    ---@type table
    local nextBtn = nil

    --- 刷新当前页面
    local function RefreshPage()
        local page = PAGES[currentPage]

        -- 更新标题
        pageIcon:SetText(page.icon)
        pageTitle:SetText(page.title)

        -- 更新页码指示
        pageIndicator:SetText(string.format("%d / %d", currentPage, totalPages))

        -- 更新按钮状态
        prevBtn:SetDisabled(currentPage <= 1)
        if currentPage >= totalPages then
            nextBtn:SetText("完成")
        else
            nextBtn:SetText("下一页")
        end

        -- 更新内容区域
        contentPanel:ClearChildren()
        local contentChildren = BuildPageContent(page)
        for _, child in ipairs(contentChildren) do
            contentPanel:AddChild(child)
        end
    end

    -- 内容面板(初始为空，后续通过RefreshPage填充)
    contentPanel = UI.Panel {
        id = "tutorial_content",
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        gap = 6,
    }

    -- 页面标题区域
    pageIcon = UI.Label {
        id = "page_icon",
        text = "",
        fontSize = 24,
    }
    pageTitle = UI.Label {
        id = "page_title",
        text = "",
        fontSize = 18,
        fontColor = Colors.gold,
    }

    -- 页码指示
    pageIndicator = UI.Label {
        id = "page_indicator",
        text = "",
        fontSize = 11,
        fontColor = Colors.textDim,
    }

    -- 导航按钮
    prevBtn = UI.Button {
        id = "prev_btn",
        text = "上一页",
        width = 80,
        height = 34,
        fontSize = 13,
        onPointerEnter = function() SFXManager.Play("buttonFocus") end,
        onClick = function()
            SFXManager.Play("buttonPress")
            if currentPage > 1 then
                currentPage = currentPage - 1
                RefreshPage()
            end
        end,
    }
    nextBtn = UI.Button {
        id = "next_btn",
        text = "下一页",
        width = 80,
        height = 34,
        fontSize = 13,
        fontColor = Colors.accent,
        onPointerEnter = function() SFXManager.Play("buttonFocus") end,
        onClick = function()
            SFXManager.Play("buttonPress")
            if currentPage >= totalPages then
                onBack()
            else
                currentPage = currentPage + 1
                RefreshPage()
            end
        end,
    }

    local root = UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        backgroundColor = Colors.menuBg,
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 340,
                height = "85%",
                maxHeight = 520,
                backgroundColor = Colors.menuCard,
                borderRadius = 16,
                borderWidth = 1,
                borderColor = Colors.menuBorder,
                padding = 24,
                gap = 12,
                children = {
                    -- 标题行
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 8,
                        children = {
                            pageIcon,
                            pageTitle,
                            UI.Panel { flexGrow = 1 },
                            pageIndicator,
                        }
                    },
                    -- 分隔线
                    UI.Panel {
                        width = "100%",
                        height = 1,
                        backgroundColor = Colors.menuBorder,
                    },
                    -- 内容区域(可滚动)
                    contentPanel,
                    -- 底部导航
                    UI.Panel {
                        width = "100%",
                        height = 1,
                        backgroundColor = Colors.menuBorder,
                    },
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        children = {
                            prevBtn,
                            UI.Button {
                                text = "返回菜单",
                                height = 34,
                                fontSize = 12,
                                fontColor = Colors.textDim,
                                onPointerEnter = function() SFXManager.Play("buttonFocus") end,
                                onClick = function()
                                    SFXManager.Play("buttonPress")
                                    onBack()
                                end,
                            },
                            nextBtn,
                        }
                    },
                }
            },
        }
    }

    -- 初始化第一页
    RefreshPage()

    return root
end

return TutorialScene
