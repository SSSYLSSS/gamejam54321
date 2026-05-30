--- BGM 背景音乐管理器
--- 管理游戏中不同场景的背景音乐播放与切换
local BGMManager = {}

-- BGM 配置
local BGM_FILES = {
    menu = "sounds/BGM/mainmenu.ogg",
    game = "sounds/BGM/in_game.ogg",
    lastRound = "sounds/BGM/last_round.ogg",
}

-- 状态
local currentTrack = nil      -- 当前播放的 track key
local musicNode = nil         -- 音乐节点
local soundSource = nil       -- SoundSource 组件
local playGain = 1.0          -- 播放增益(由 track 配置决定)
local fadeTarget = nil        -- 渐变目标音量
local fadeSpeed = 2.0         -- 渐变速度(每秒)
local pendingTrack = nil      -- 渐出后要播放的曲目
local currentSound = nil      -- 保持 Sound 引用防止 GC
local duckGain = nil          -- 临时压低音量目标(结算翻牌时)

-- 每个 track 的默认音量
local TRACK_GAIN = {
    menu = 1.0,
    game = 0.6,
    lastRound = 1.0,
}

--- 初始化 BGM 系统（在 Start 中调用一次）
---@param scene Scene
function BGMManager.Init(scene)
    if musicNode then return end
    musicNode = scene:CreateChild("BGMNode")
    soundSource = musicNode:CreateComponent("SoundSource")
    soundSource.soundType = SOUND_MUSIC
    soundSource.gain = playGain
end

--- 播放指定曲目（带淡入淡出）
---@param track string "menu" | "game" | "lastRound"
---@param immediate? boolean 是否立即切换（跳过淡出）
function BGMManager.Play(track, immediate)
    if not soundSource then return end
    if track == currentTrack then return end

    local file = BGM_FILES[track]
    if not file then return end

    if immediate or not soundSource.playing then
        -- 直接播放
        BGMManager._PlayTrack(track, file)
    else
        -- 先淡出当前曲目，再播放新曲目
        pendingTrack = track
        fadeTarget = 0.0
        fadeSpeed = 3.0  -- 淡出快一些
    end
end

--- 停止播放（带淡出）
function BGMManager.Stop()
    if not soundSource then return end
    if not soundSource.playing then return end
    pendingTrack = nil
    currentTrack = nil
    fadeTarget = 0.0
    fadeSpeed = 2.0
end

--- 每帧更新（处理淡入淡出）
---@param dt number
function BGMManager.Update(dt)
    if not soundSource then return end
    if fadeTarget == nil then return end

    local current = soundSource.gain
    if current < fadeTarget then
        current = math.min(current + fadeSpeed * dt, fadeTarget)
    elseif current > fadeTarget then
        current = math.max(current - fadeSpeed * dt, fadeTarget)
    end
    soundSource.gain = current

    -- 到达目标
    if math.abs(current - fadeTarget) < 0.01 then
        soundSource.gain = fadeTarget

        if fadeTarget == 0.0 then
            -- 淡出完成
            if pendingTrack then
                local track = pendingTrack
                pendingTrack = nil
                local file = BGM_FILES[track]
                if file then
                    BGMManager._PlayTrack(track, file)
                end
            else
                soundSource:Stop()
            end
        else
            -- 淡入完成
            fadeTarget = nil
        end
    end
end

--- 内部：直接播放曲目
function BGMManager._PlayTrack(track, file)
    local sound = cache:GetResource("Sound", file)
    if not sound then
        print("[BGMManager] Failed to load: " .. file)
        return
    end
    sound.looped = true
    currentSound = sound  -- 保持引用防止 GC 导致循环中断
    currentTrack = track
    playGain = TRACK_GAIN[track] or 1.0
    duckGain = nil  -- 清除 duck 状态
    soundSource.gain = 0.0
    soundSource:Play(sound)
    -- 淡入到目标音量
    fadeTarget = playGain
    fadeSpeed = 1.5
end

--- 压低 BGM 音量（结算翻牌时调用）
---@param gain? number 目标音量 (默认 0.2)
function BGMManager.Duck(gain)
    if not soundSource then return end
    duckGain = gain or 0.2
    fadeTarget = duckGain
    fadeSpeed = 3.0
end

--- 恢复 BGM 音量（结算结束后调用）
function BGMManager.Unduck()
    if not soundSource then return end
    duckGain = nil
    fadeTarget = playGain
    fadeSpeed = 1.5
end

--- 获取当前曲目
---@return string|nil
function BGMManager.GetCurrentTrack()
    return currentTrack
end

return BGMManager
