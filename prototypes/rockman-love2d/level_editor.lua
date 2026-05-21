--[[
  關卡編輯器 — 啟動：love . editor
  滑鼠左鍵繪製 · 右鍵擦除 · 滾輪縮放 · 中鍵/空白+拖曳平移
  S 儲存 · L 讀取 · N 新關卡 · T 試玩 · R 自動決鬥圈
]]
local level_io = require("level_io")

local TILE = 32
local PALETTE = {
  { ch = "#", name = "山石", color = { 0.32, 0.26, 0.22 } },
  { ch = "=", name = "木道", color = { 0.52, 0.36, 0.2 } },
  { ch = ".", name = "空氣", color = { 0.35, 0.45, 0.38 } },
  { ch = "^", name = "竹刺", color = { 0.75, 0.55, 0.2 } },
  { ch = "P", name = "出生", color = { 0.85, 0.25, 0.2 } },
  { ch = "@", name = "惡徒", color = { 0.55, 0.22, 0.2 } },
  { ch = "E", name = "決鬥入口", color = { 0.9, 0.35, 0.25 } },
  { ch = "a", name = "圈內落點", color = { 0.7, 0.8, 0.9 } },
  { ch = "B", name = "掌門", color = { 0.35, 0.55, 0.9 } },
  { ch = "G", name = "圈門", color = { 0.75, 0.2, 0.15 } },
  { ch = "e", name = "圈出口", color = { 0.5, 0.85, 0.5 } },
  { ch = "F", name = "關隘", color = { 0.85, 0.2, 0.15 } },
  { ch = "M", name = "吊橋", color = { 0.55, 0.38, 0.22 } },
  { ch = "Q", name = "輕功", color = { 0.85, 0.35, 0.55 } },
  { ch = "R", name = "雷符", color = { 0.4, 0.65, 1 } },
  { ch = "K", name = "破甲釘", color = { 0.7, 0.5, 0.35 } },
  { ch = "N", name = "養氣丹", color = { 0.85, 0.35, 0.55 } },
  { ch = "%", name = "金創藥", color = { 0.3, 0.75, 0.4 } },
}

local editor = {
  gw = 60,
  gh = 28,
  grid = nil,
  brush = 2,
  cam_x = 0,
  cam_y = 0,
  zoom = 1,
  panning = false,
  painting = false,
  erase = false,
  pan_ax = 0,
  pan_ay = 0,
  cam_sx = 0,
  cam_sy = 0,
  meta = {
    id = 1,
    title = "自訂關卡",
    boss_kind = "lightning_sect",
    weapon_drop = "thunder_palm",
    arena = nil,
  },
  filename = "custom_01.lua",
  status = "關卡編輯器",
  status_t = 4,
  file_index = 1,
  font = nil,
}

local function set_status(msg, t)
  editor.status = msg
  editor.status_t = t or 5
end

local function palette_index(ch)
  for i, p in ipairs(PALETTE) do
    if p.ch == ch then return i end
  end
  return 2
end

local function screen_to_tile(sx, sy)
  local wx = editor.cam_x + sx / editor.zoom
  local wy = editor.cam_y + sy / editor.zoom
  local tx = math.floor(wx / TILE) + 1
  local ty = math.floor(wy / TILE) + 1
  return tx, ty
end

local function paint_at(tx, ty)
  if tx < 1 or ty < 1 or tx > editor.gw or ty > editor.gh then
    return
  end
  local ch = PALETTE[editor.brush].ch
  if ch == "." and (ty == 1 or ty == editor.gh or tx == 1 or tx == editor.gw) then
    ch = "#"
  end
  editor.grid[ty][tx] = ch
end

local function build_level()
  local map = level_io.grid_to_map(editor.grid, editor.gw, editor.gh)
  editor.meta.arena = editor.meta.arena or level_io.auto_arena(map)
  return level_io.level_from_editor(editor.meta, editor.grid, editor.gw, editor.gh)
end

local function new_blank()
  editor.grid = level_io.blank_grid(editor.gw, editor.gh)
  editor.meta.title = "自訂關卡"
  editor.meta.arena = nil
  set_status("新關卡（空白外框）")
end

local function resize_grid(nw, nh)
  nw = math.max(20, math.min(120, nw))
  nh = math.max(12, math.min(80, nh))
  local ng = level_io.blank_grid(nw, nh)
  for y = 1, math.min(nh, editor.gh) do
    for x = 1, math.min(nw, editor.gw) do
      if editor.grid[y] and editor.grid[y][x] then
        ng[y][x] = editor.grid[y][x]
      end
    end
  end
  editor.gw, editor.gh, editor.grid = nw, nh, ng
  set_status(string.format("地圖尺寸 %dx%d", nw, nh))
end

local function load_level_data(data)
  editor.grid, editor.gw, editor.gh = level_io.map_to_grid(data.map)
  editor.meta.id = data.id or 1
  editor.meta.title = data.title or "自訂關卡"
  editor.meta.boss_kind = data.boss_kind or "lightning_sect"
  editor.meta.weapon_drop = data.weapon_drop
  editor.meta.arena = data.arena
  set_status("已載入：" .. (data.title or "?"))
end

local function save_current()
  local level = build_level()
  local ok, path = level_io.save_file(editor.filename, level)
  if ok then
    set_status("已儲存：" .. path)
  else
    set_status("儲存失敗：" .. tostring(path))
  end
end

local function cycle_load(delta)
  local files = level_io.list_level_files()
  if #files == 0 then
    set_status("levels/ 尚無 .lua，按 S 儲存第一個關卡")
    return
  end
  editor.file_index = ((editor.file_index - 1 + delta) % #files) + 1
  editor.filename = files[editor.file_index]
  local data, err = level_io.load_file(editor.filename)
  if data then
    load_level_data(data)
  else
    set_status("讀取失敗：" .. tostring(err))
  end
end

local function start_test_play()
  local level = build_level()
  set_status("試玩中… Esc 返回編輯器", 99)
  require("playtest").start(level)
  require("playtest").mount()
end

local M = {}

function M.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  local paths = { "fonts/NotoSansTC-VF.ttf", "fonts/NotoSansTC-Regular.ttf" }
  for _, path in ipairs(paths) do
    if love.filesystem.getInfo(path) then
      editor.font = love.graphics.newFont(path, 14)
      break
    end
  end
  if editor.font then love.graphics.setFont(editor.font) end
  new_blank()
  local files = level_io.list_level_files()
  if #files > 0 then
    editor.filename = files[1]
    editor.file_index = 1
    local data = level_io.load_file(files[1])
    if data then load_level_data(data) end
  end
  set_status("編輯器就緒 · S儲存 L切換 T試玩", 8)
end

function M.update(dt)
  editor.status_t = math.max(0, editor.status_t - dt)
  if editor.panning then
    local mx, my = love.mouse.getPosition()
    editor.cam_x = editor.cam_sx - (mx - editor.pan_ax) / editor.zoom
    editor.cam_y = editor.cam_sy - (my - editor.pan_ay) / editor.zoom
  end
  if editor.painting then
    local tx, ty = screen_to_tile(love.mouse.getPosition())
    paint_at(tx, ty)
  end
end

function M.draw()
  love.graphics.clear(0.22, 0.24, 0.26)
  love.graphics.push()
  love.graphics.scale(editor.zoom)

  for ty = 1, editor.gh do
    for tx = 1, editor.gw do
      local ch = editor.grid[ty][tx]
      local wx = (tx - 1) * TILE - editor.cam_x
      local wy = (ty - 1) * TILE - editor.cam_y
      local col = { 0.35, 0.45, 0.38 }
      for _, p in ipairs(PALETTE) do
        if p.ch == ch then col = p.color; break end
      end
      love.graphics.setColor(col[1], col[2], col[3])
      love.graphics.rectangle("fill", wx, wy + (ch == "=" and 12 or 0), TILE, ch == "=" and 20 or TILE)
      love.graphics.setColor(0, 0, 0, 0.15)
      love.graphics.rectangle("line", wx, wy, TILE, TILE)
      if ch ~= "." and ch ~= "#" and ch ~= "=" then
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(ch, wx, wy + 8, TILE, "center")
      end
    end
  end

  if editor.meta.arena then
    local a = editor.meta.arena
    love.graphics.setColor(0.9, 0.2, 0.15, 0.2)
    love.graphics.rectangle(
      "line",
      (a.x1 - 1) * TILE - editor.cam_x,
      (a.y1 - 1) * TILE - editor.cam_y,
      (a.x2 - a.x1 + 1) * TILE,
      (a.y2 - a.y1 + 1) * TILE
    )
  end

  love.graphics.pop()

  local mx, my = love.mouse.getPosition()
  local tx, ty = screen_to_tile(mx, my)
  local ch = (tx >= 1 and ty >= 1 and tx <= editor.gw and ty <= editor.gh)
      and editor.grid[ty][tx] or " "
  love.graphics.setColor(0, 0, 0, 0.75)
  love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), 72)
  love.graphics.rectangle("fill", 0, love.graphics.getHeight() - 36, love.graphics.getWidth(), 36)
  love.graphics.setColor(0.95, 0.9, 0.8)
  love.graphics.print("江湖試煉 · 關卡編輯器", 10, 8)
  love.graphics.print(string.format(
    "圖層:%s  游標:(%d,%d)='%s'  尺寸:%dx%d  檔名:%s",
    PALETTE[editor.brush].name, tx, ty, ch, editor.gw, editor.gh, editor.filename
  ), 10, 28)
  if editor.status_t > 0 then
    love.graphics.setColor(0.55, 0.95, 0.75)
    love.graphics.print(editor.status, 10, 50)
  end

  local px = 8
  for i, p in ipairs(PALETTE) do
    local sel = i == editor.brush
    love.graphics.setColor(p.color[1], p.color[2], p.color[3])
    love.graphics.rectangle("fill", px, love.graphics.getHeight() - 30, 28, 24)
    if sel then
      love.graphics.setColor(1, 0.9, 0.3)
      love.graphics.rectangle("line", px - 2, love.graphics.getHeight() - 32, 32, 28)
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(p.ch, px, love.graphics.getHeight() - 26, 28, "center")
    px = px + 34
  end

  love.graphics.setColor(0.7, 0.75, 0.8)
  love.graphics.print(
    "左鍵畫 · 右鍵擦 · 滾輪縮放 · 中鍵平移 · 1-9/0選圖層 · S存 L載 N新 T試玩 R自動圈 · [←→]寬 [↑↓]高",
    10, love.graphics.getHeight() - 18
  )
end

function M.keypressed(key)
  if key == "escape" then
    love.event.quit()
    return
  end
  local num = tonumber(key)
  if num then
    local idx = key == "0" and 10 or num
    if PALETTE[idx] then
      editor.brush = idx
      set_status("圖層：" .. PALETTE[idx].name)
    end
    return
  end
  if key == "s" then save_current(); return end
  if key == "l" then cycle_load(1); return end
  if key == "n" then new_blank(); return end
  if key == "t" then start_test_play(); return end
  if key == "r" then
    editor.meta.arena = level_io.auto_arena(level_io.grid_to_map(editor.grid, editor.gw, editor.gh))
    set_status("已依圖面重算決鬥圈範圍")
    return
  end
  if key == "left" then resize_grid(editor.gw - 2, editor.gh); return end
  if key == "right" then resize_grid(editor.gw + 2, editor.gh); return end
  if key == "up" then resize_grid(editor.gw, editor.gh - 2); return end
  if key == "down" then resize_grid(editor.gw, editor.gh + 2); return end
  if key == "pageup" then editor.zoom = math.min(2.5, editor.zoom * 1.15); return end
  if key == "pagedown" then editor.zoom = math.max(0.35, editor.zoom / 1.15); return end
  if key == "tab" then
    editor.brush = (editor.brush % #PALETTE) + 1
    set_status("圖層：" .. PALETTE[editor.brush].name)
    return
  end
  if key == "f5" then
    editor.meta.boss_kind = editor.meta.boss_kind == "lightning_sect" and "iron_gate" or "lightning_sect"
    editor.meta.weapon_drop = editor.meta.boss_kind == "lightning_sect" and "thunder_palm" or nil
    set_status("掌門類型：" .. editor.meta.boss_kind)
  end
end

function M.wheelmoved(x, y)
  if y > 0 then
    editor.zoom = math.min(2.5, editor.zoom * 1.1)
  elseif y < 0 then
    editor.zoom = math.max(0.35, editor.zoom / 1.1)
  end
end

function M.mousepressed(x, y, button)
  if button == 2 then
    editor.erase = true
    editor.brush = palette_index(".")
    editor.painting = true
    paint_at(screen_to_tile(x, y))
    return
  end
  if button == 3 then
    editor.panning = true
    editor.pan_ax, editor.pan_ay = x, y
    editor.cam_sx, editor.cam_sy = editor.cam_x, editor.cam_y
    return
  end
  if button == 1 then
    local ty = select(2, screen_to_tile(x, y))
    local py = 8
    for i = 1, #PALETTE do
      if x >= 6 + (i - 1) * 34 and x < 6 + i * 34 and y >= love.graphics.getHeight() - 32 then
        editor.brush = i
        set_status("圖層：" .. PALETTE[i].name)
        return
      end
    end
    editor.painting = true
    paint_at(screen_to_tile(x, y))
  end
end

function M.mousereleased()
  editor.painting = false
  editor.erase = false
  editor.panning = false
  if editor.erase then
    editor.brush = 2
  end
end

function M.mount()
  love.load = M.load
  love.update = M.update
  love.draw = M.draw
  love.keypressed = M.keypressed
  love.wheelmoved = M.wheelmoved
  love.mousepressed = M.mousepressed
  love.mousereleased = M.mousereleased
  M.load()
end

return M
