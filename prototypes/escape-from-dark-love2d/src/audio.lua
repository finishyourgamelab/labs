-- 音訊管理：載入 .ogg / .mp3，按需播放。
-- Repository 內預設只追蹤 .ogg（節省體積）；缺檔時會 fallback 載入同名 .mp3。
-- 可用 assets/audio_src/generate_audio.py --mp3 在本機另產 mp3。

local M = {}

local sources = {}
local musicSource = nil
local musicTargetVolume = 0
local currentMusicName = nil
local muted = false
local masterVolume = 0.7
local sfxVolume = 0.85
local musicVolume = 0.55
local SETTINGS_FILE = "settings.lua"

local function tryLoad(name, mode)
  for _, ext in ipairs({ "ogg", "mp3" }) do
    local path = ("assets/audio/%s.%s"):format(name, ext)
    if love.filesystem.getInfo(path) then
      local ok, src = pcall(love.audio.newSource, path, mode)
      if ok and src then
        return src
      end
    end
  end
  return nil
end

local function loadSettings()
  if not love.filesystem.getInfo(SETTINGS_FILE) then return end
  local content = love.filesystem.read(SETTINGS_FILE)
  if not content then return end
  local fn, err = loadstring(content)
  if not fn then return end
  local ok, data = pcall(fn)
  if not ok or type(data) ~= "table" then return end
  if data.muted ~= nil then muted = data.muted end
  if data.master then masterVolume = tonumber(data.master) or masterVolume end
  if data.sfx then sfxVolume = tonumber(data.sfx) or sfxVolume end
  if data.music then musicVolume = tonumber(data.music) or musicVolume end
end

local function saveSettings()
  local body = ("return { muted = %s, master = %.3f, sfx = %.3f, music = %.3f }")
    :format(tostring(muted), masterVolume, sfxVolume, musicVolume)
  love.filesystem.write(SETTINGS_FILE, body)
end

function M.load()
  loadSettings()
  local sfxNames = {
    "sfx_pistol", "sfx_dryfire", "sfx_hit", "sfx_enemy_die",
    "sfx_player_hurt", "sfx_pickup", "sfx_search_loop",
    "sfx_extract_arm", "sfx_extract_done", "sfx_alarm",
    "sfx_heartbeat", "sfx_step", "sfx_whisper",
  }
  for _, name in ipairs(sfxNames) do
    sources[name] = tryLoad(name, "static")
  end
end

function M.playSfx(name, opts)
  if muted then return end
  local src = sources[name]
  if not src then return end
  local clone = src:clone()
  clone:setVolume(masterVolume * sfxVolume * (opts and opts.volume or 1))
  if opts and opts.pitch then
    clone:setPitch(opts.pitch)
  end
  clone:play()
end

function M.playMusic(name)
  if currentMusicName == name and musicSource and musicSource:isPlaying() then
    return
  end
  if musicSource then
    musicSource:stop()
    musicSource = nil
  end
  if not name then
    currentMusicName = nil
    musicTargetVolume = 0
    return
  end
  local src = tryLoad(name, "stream")
  if not src then return end
  src:setLooping(true)
  -- 從 0 淡入；目標音量在 update 中逼近
  src:setVolume(0)
  src:play()
  musicSource = src
  currentMusicName = name
  musicTargetVolume = muted and 0 or masterVolume * musicVolume
end

function M.stopMusic()
  if musicSource then
    musicSource:stop()
    musicSource = nil
    currentMusicName = nil
    musicTargetVolume = 0
  end
end

function M.update(dt)
  if musicSource then
    local current = musicSource:getVolume()
    local target = muted and 0 or musicTargetVolume
    local diff = target - current
    if math.abs(diff) > 0.001 then
      local step = math.min(math.abs(diff), 0.6 * dt)
      musicSource:setVolume(current + (diff > 0 and step or -step))
    end
  end
end

function M.setMuted(v)
  muted = v
  if musicSource then
    musicTargetVolume = muted and 0 or masterVolume * musicVolume
  end
  saveSettings()
end

function M.toggleMute()
  M.setMuted(not muted)
  return muted
end

function M.isMuted()
  return muted
end

function M.setMasterVolume(v)
  masterVolume = math.max(0, math.min(1, v))
  if musicSource then
    musicTargetVolume = muted and 0 or masterVolume * musicVolume
  end
  saveSettings()
end

function M.getMasterVolume() return masterVolume end
function M.getMusicVolume() return musicVolume end
function M.getSfxVolume() return sfxVolume end

return M
