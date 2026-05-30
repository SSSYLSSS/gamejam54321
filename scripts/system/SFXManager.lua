--- SFX 音效管理器
--- 管理游戏中所有音效的播放
local SFXManager = {}

-- 音效文件映射
local SFX_FILES = {
    buttonFocus = "sounds/SFX/bottom_foucs.ogg",
    buttonPress = "sounds/SFX/bottom_press.ogg",
    discard = "sounds/SFX/discard.ogg",
    drawCard = "sounds/SFX/draw_card.ogg",
    flipCard = "sounds/SFX/flip_card.ogg",
    shuffle = "sounds/SFX/shuffling_card.ogg",
    win = "sounds/SFX/win.ogg",
    lose = "sounds/SFX/lose.ogg",
    -- 倒计时翻牌 (5! 4! 3! 2! 1!)
    cardFlip5 = "sounds/SFX/on_card_flip(5!).ogg",
    cardFlip4 = "sounds/SFX/on_card_flip(4!).ogg",
    cardFlip3 = "sounds/SFX/on_card_flip(3!).ogg",
    cardFlip2 = "sounds/SFX/on_card_flip(2!).ogg",
    cardFlip1 = "sounds/SFX/on_card_flip(1!).ogg",
}

---@type Node
local sfxNode = nil

--- 预加载的 Sound 资源缓存
local soundCache = {}

--- 初始化 SFX 系统（预加载所有音效到内存消除播放延迟）
---@param scene Scene
function SFXManager.Init(scene)
    if sfxNode then return end
    sfxNode = scene:CreateChild("SFXNode")

    -- 预加载所有音效资源到内存
    for name, file in pairs(SFX_FILES) do
        local sound = cache:GetResource("Sound", file)
        if sound then
            soundCache[name] = sound
        end
    end
end

--- 播放音效
---@param name string 音效名称 (SFX_FILES 的 key)
---@param gain? number 音量 (默认 1.0)
function SFXManager.Play(name, gain)
    if not sfxNode then return end

    -- 使用预加载缓存，避免运行时加载延迟
    local sound = soundCache[name]
    if not sound then
        local file = SFX_FILES[name]
        if not file then return end
        sound = cache:GetResource("Sound", file)
        if not sound then return end
        soundCache[name] = sound
    end

    local source = sfxNode:CreateComponent("SoundSource")
    source.soundType = SOUND_EFFECT
    source.gain = gain or 1.0
    source.autoRemoveMode = REMOVE_COMPONENT
    source:Play(sound)
end

--- 播放倒计时翻牌音效 (根据剩余张数)
---@param remaining number 剩余未翻的牌数 (5,4,3,2,1)
function SFXManager.PlayCardFlipCountdown(remaining)
    local name = "cardFlip" .. tostring(remaining)
    SFXManager.Play(name)
end

return SFXManager
