local fonts = require("src.fonts")
local levels = require("src.levels")
local audio = require("src.audio")
local util = require("src.util")

local Menu = {}
Menu.__index = Menu

local TITLE = "ESCAPE FROM DARK"
local SUBTITLE = "三夜・潛行・鴨子的逃亡"

function Menu.new()
  local self = setmetatable({}, Menu)
  self.selected = 1
  self.flicker = 0
  self.tip = "↑↓ 或 1/2/3 選擇關卡，Enter 開始，M 靜音，Esc 離開。"
  return self
end

function Menu:enter()
  audio.playMusic("music_menu")
end

function Menu:leave()
  -- 切到遊玩場景時關卡會切自己的 BGM
end

function Menu:update(dt)
  self.flicker = (self.flicker + dt) % 1.6
end

function Menu:keypressed(key, scenes)
  local count = levels.count()
  if key == "up" or key == "w" then
    self.selected = ((self.selected - 2) % count) + 1
  elseif key == "down" or key == "s" then
    self.selected = (self.selected % count) + 1
  elseif key == "1" or key == "2" or key == "3" then
    local n = tonumber(key)
    if n and n >= 1 and n <= count then
      self.selected = n
    end
  elseif key == "return" or key == "kpenter" or key == "space" then
    scenes.start(self.selected)
  elseif key == "m" then
    audio.toggleMute()
  end
end

local function drawScanlines(width, height)
  love.graphics.setColor(0, 0, 0, 0.18)
  for y = 0, height, 3 do
    love.graphics.rectangle("fill", 0, y, width, 1)
  end
end

function Menu:draw(width, height)
  love.graphics.clear(0.04, 0.05, 0.06)

  -- 標題
  love.graphics.setFont(fonts.pixelHuge)
  love.graphics.setColor(0.92, 0.18, 0.16, 0.85 + 0.15 * math.sin(self.flicker * 6))
  love.graphics.printf(TITLE, 0, 130, width, "center")
  love.graphics.setFont(fonts.medium)
  love.graphics.setColor(0.78, 0.74, 0.62)
  love.graphics.printf(SUBTITLE, 0, 218, width, "center")

  -- 關卡清單
  local list = levels.list()
  local startY = 290
  local rowH = 88
  for i, level in ipairs(list) do
    local y = startY + (i - 1) * rowH
    local active = i == self.selected

    if active then
      love.graphics.setColor(0.10, 0.04, 0.05, 0.85)
      love.graphics.rectangle("fill", width / 2 - 360, y - 6, 720, rowH - 14, 8, 8)
      love.graphics.setColor(0.92, 0.22, 0.18)
      love.graphics.rectangle("line", width / 2 - 360, y - 6, 720, rowH - 14, 8, 8)
    else
      love.graphics.setColor(0.04, 0.05, 0.05, 0.55)
      love.graphics.rectangle("fill", width / 2 - 360, y - 6, 720, rowH - 14, 8, 8)
      love.graphics.setColor(0.22, 0.22, 0.22)
      love.graphics.rectangle("line", width / 2 - 360, y - 6, 720, rowH - 14, 8, 8)
    end

    love.graphics.setFont(fonts.large)
    love.graphics.setColor(active and { 1, 0.92, 0.74, 1 } or { 0.62, 0.6, 0.55, 1 })
    util.setColor({ love.graphics.getColor() })
    love.graphics.print(("LV%d  %s"):format(i, level.name), width / 2 - 340, y)

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(active and { 0.92, 0.78, 0.45 } or { 0.45, 0.44, 0.42 })
    love.graphics.printf(level.subtitle, width / 2 - 340, y + 36, 680, "left")
  end

  -- 底部提示
  love.graphics.setFont(fonts.small)
  love.graphics.setColor(0.55, 0.55, 0.5)
  love.graphics.printf(self.tip, 0, height - 60, width, "center")
  love.graphics.setColor(0.4, 0.4, 0.36)
  local mute = audio.isMuted() and "[ M 靜音中 ]" or ""
  love.graphics.printf(mute, 0, height - 36, width, "center")

  drawScanlines(width, height)
end

return Menu
