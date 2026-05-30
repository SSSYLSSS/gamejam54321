-- ============================================================================
-- client_main.lua - 多人游戏客户端入口
-- 在 background_match 模式下，直接加载主游戏（main.lua）
-- 用户通过主菜单选择多人游戏后，再激活网络连接
-- ============================================================================

require "main"

-- 构建工具要求入口文件显式包含 Start() 函数声明
-- main.lua 中已定义全局 Start()，此处提供兜底（不会被调用到）
if not Start then
    function Start()
        -- fallback, should not reach here
    end
end
