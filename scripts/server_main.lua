-- ============================================================================
-- server_main.lua - 多人游戏服务端入口
-- ============================================================================

require "LuaScripts/Utilities/Sample"

local Server = require("network.Server")

function Start()
    math.randomseed(os.time())
    Server.Start()
end

function Stop()
    Server.Stop()
end
