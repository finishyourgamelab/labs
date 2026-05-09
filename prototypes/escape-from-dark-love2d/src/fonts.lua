local M = {}

local cache = {}

local FONT_PATHS = {
  cjkRegular = "assets/fonts/NotoSansTC-Regular.otf",
  cjkBold = "assets/fonts/NotoSansTC-Bold.otf",
  pixel = "assets/fonts/VT323-Regular.ttf",
}

local function load(path, size)
  local key = path .. "@" .. size
  if not cache[key] then
    cache[key] = love.graphics.newFont(path, size)
    cache[key]:setFilter("nearest", "nearest")
  end
  return cache[key]
end

function M.load()
  M.huge = load(FONT_PATHS.cjkBold, 44)
  M.title = load(FONT_PATHS.cjkBold, 56)
  M.large = load(FONT_PATHS.cjkBold, 26)
  M.medium = load(FONT_PATHS.cjkRegular, 18)
  M.small = load(FONT_PATHS.cjkRegular, 14)
  M.pixelHuge = load(FONT_PATHS.pixel, 72)
  M.pixelLarge = load(FONT_PATHS.pixel, 36)
  M.pixelMedium = load(FONT_PATHS.pixel, 22)
end

return M
