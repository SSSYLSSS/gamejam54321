-- ============================================================================
-- client_main.lua - 多人游戏客户端入口
-- ============================================================================

require "LuaScripts/Utilities/Sample"

local Client = require("network.Client")

function Start()
    math.randomseed(os.time())
    Client.Start()
end

function Stop()
    Client.Stop()
end
