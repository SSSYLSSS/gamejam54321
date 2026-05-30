-- ============================================================================
-- system/MatchHistory.lua - 对局历史存储系统
-- 保存已完成的对局日志，支持回放查看
-- ============================================================================

local MatchHistory = {}

local HISTORY_FILE = "match_history.json"
local MAX_HISTORY = 20  -- 最多保存20局

---@type table[]
local history_ = {}

--- 加载历史记录
function MatchHistory.Load()
    if not fileSystem:FileExists(HISTORY_FILE) then
        history_ = {}
        return
    end

    local file = File(HISTORY_FILE, FILE_READ)
    if not file:IsOpen() then
        history_ = {}
        return
    end
    local content = file:ReadString()
    file:Close()

    if not content or content == "" then
        history_ = {}
        return
    end

    local ok, data = pcall(cjson.decode, content)
    if ok and type(data) == "table" then
        history_ = data
    else
        history_ = {}
    end
end

--- 保存历史记录到文件
local function save()
    local ok, json = pcall(cjson.encode, history_)
    if not ok then
        print("[MatchHistory] Encode error: " .. tostring(json))
        return
    end
    local file = File(HISTORY_FILE, FILE_WRITE)
    if not file:IsOpen() then
        print("[MatchHistory] Cannot open file for writing")
        return
    end
    file:WriteString(json)
    file:Close()
end

--- 记录一局已完成的对局
---@param entry table { timestamp, difficulty, result, finalScore, log }
function MatchHistory.Record(entry)
    -- 添加时间戳
    if not entry.timestamp then
        entry.timestamp = os.time()
    end

    -- 插入到最前面
    table.insert(history_, 1, entry)

    -- 超出上限时删除最旧的
    while #history_ > MAX_HISTORY do
        table.remove(history_)
    end

    save()
end

--- 获取所有历史记录
---@return table[]
function MatchHistory.GetAll()
    return history_
end

--- 获取指定索引的对局
---@param index number
---@return table|nil
function MatchHistory.Get(index)
    return history_[index]
end

--- 获取记录数
---@return number
function MatchHistory.Count()
    return #history_
end

--- 清除所有历史
function MatchHistory.Clear()
    history_ = {}
    save()
end

return MatchHistory
