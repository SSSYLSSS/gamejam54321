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
        title = "游戏目标",
        icon = "🎯",
        content = {
            { type = "text", value = "让手牌点数之和尽量接近 21 点！" },
            { type = "gap" },
            { type = "highlight", value = "双方比较谁更接近21点，更近者获胜\n超过21点不会直接判负，但距离会更远" },
            { type = "gap" },
            { type = "text", value = "每局双方比较与21点的距离，更接近的一方获胜。" },
            { type = "text", value = "先赢 3 局者赢得整场比赛。" },
        }
    },
    {
        title = "回合流程",
        icon = "🃏",
        content = {
            { type = "text", value = "每局分为三个抽牌阶段：" },
            { type = "gap" },
            { type = "step", label = "五!", value = "抽5张，弃至多5张" },
            { type = "step", label = "四!", value = "抽4张，弃至多4张" },
            { type = "step", label = "三!", value = "抽3张，弃至多3张" },
            { type = "gap" },
            { type = "text", value = "每阶段先选择要弃置的牌，然后点击「弃置」确认，或点击「跳过」保留所有牌。" },
        }
    },
    {
        title = "结算后阶段",
        icon = "✨",
        content = {
            { type = "text", value = "计分结束后，还有两个特殊阶段：" },
            { type = "gap" },
            { type = "step", label = "二!", value = "选至多2张手牌放回抽牌堆\n(下局可能再抽到)" },
            { type = "step", label = "一!", value = "选1张手牌保留至下一局\n(下局开始时直接在手中)" },
            { type = "gap" },
            { type = "text", value = "善用这两个阶段可以为下一局做准备！" },
        }
    },
    {
        title = "特殊牌效果(上)",
        icon = "⚡",
        content = {
            { type = "card", rank = "A", desc = "结算时翻倍对手同花色普通牌" },
            { type = "card", rank = "7", desc = "不可被其他效果改变或删除" },
            { type = "card", rank = "8", desc = "降低自己所有普通牌各1点" },
            { type = "card", rank = "9", desc = "灵活牌：可视为 0 或 9 点" },
            { type = "card", rank = "10", desc = "若曾被弃置过，最终得分+1" },
        }
    },
    {
        title = "特殊牌效果(下)",
        icon = "⚡",
        content = {
            { type = "card", rank = "J", desc = "弃置时从弃牌堆抽1张牌\n结算时翻倍对方普通牌" },
            { type = "card", rank = "Q", desc = "使对方最大普通牌点数×2(可叠加)" },
            { type = "card", rank = "K", desc = "对方点数向上取整到十位\n己方-5后向下取整到十位" },
            { type = "gap" },
            { type = "highlight", value = "三张7特殊规则：手持三张7直接获胜！" },
        }
    },
    {
        title = "鬼牌效果",
        icon = "🃏",
        content = {
            { type = "text", value = "鬼牌在抽牌阶段结束后触发效果：" },
            { type = "gap" },
            { type = "card", rank = "小王", desc = "选择移除对方一张牌(看不到牌面)\n点数自动选择最优(0~13)" },
            { type = "card", rank = "大王", desc = "选一张手牌设为任意点数\n大王自身也选任意点数(0~13)" },
            { type = "gap" },
            { type = "text", value = "鬼牌效果触发后仍保留在手中，以选定点数计入总分。" },
        }
    },
    {
        title = "小贴士",
        icon = "💡",
        content = {
            { type = "text", value = "• 不要一味追求高点数，控制在 21 以内更重要" },
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
