local level_io = {}

local BOSS_KINDS = { "lightning_sect", "iron_gate" }

local function find_tile(map, ch)
  local row_i = 0
  for line in map:gmatch("[^\n]+") do
    row_i = row_i + 1
    local col = 1
    while true do
      local pos = line:find(ch, col, true)
      if not pos then break end
      return pos, row_i
    end
  end
  return nil, nil
end

local function find_arena_bounds(map)
  local x1, y1, x2, y2 = 9999, 9999, 0, 0
  local row_i = 0
  for line in map:gmatch("[^\n]+") do
    row_i = row_i + 1
    for col = 1, #line do
      if line:sub(col, col) == "#" then
        x1 = math.min(x1, col)
        y1 = math.min(y1, row_i)
        x2 = math.max(x2, col)
        y2 = math.max(y2, row_i)
      end
    end
  end
  if x2 == 0 then
    return nil
  end
  return { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
end

function level_io.auto_arena(map)
  local ex, ey = find_tile(map, "E")
  local ax, ay = find_tile(map, "a")
  local bx, by = find_tile(map, "B")
  local gx, gy = find_tile(map, "G")
  local rx, ry = find_tile(map, "e")
  local box = find_arena_bounds(map)

  if not ex then
    return {
      x1 = 10, y1 = 5, x2 = 25, y2 = 10,
      enter_tx = 10, enter_ty = 8,
      spawn_tx = 12, spawn_ty = 9,
      boss_tx = 20, boss_ty = 9,
      gate_tx = 10, gate_ty = 10,
      return_tx = 12, return_ty = 14,
    }
  end

  local a = box or { x1 = ex, y1 = ey, x2 = ex + 12, y2 = ey + 3 }
  return {
    x1 = a.x1, y1 = a.y1, x2 = a.x2, y2 = a.y2,
    enter_tx = ex, enter_ty = ey,
    spawn_tx = ax or (ex + 2), spawn_ty = ay or (ey + 1),
    boss_tx = bx or (a.x2 - 2), boss_ty = by or (ey + 1),
    gate_tx = gx or ex, gate_ty = gy or (ey + 2),
    return_tx = rx or (ex + 2), return_ty = ry or (ey + 4),
  }
end

function level_io.grid_to_map(grid, gw, gh)
  local lines = {}
  for y = 1, gh do
    local row = {}
    for x = 1, gw do
      row[x] = grid[y][x] or "."
    end
    lines[y] = table.concat(row)
  end
  return table.concat(lines, "\n")
end

function level_io.map_to_grid(map)
  local grid = {}
  local gw, gh = 0, 0
  local row_i = 0
  for line in map:gmatch("[^\n]+") do
    row_i = row_i + 1
    grid[row_i] = {}
    for x = 1, #line do
      grid[row_i][x] = line:sub(x, x)
    end
    gw = math.max(gw, #line)
    gh = row_i
  end
  for y = 1, gh do
    for x = 1, gw do
      if not grid[y][x] then
        grid[y][x] = "."
      end
    end
  end
  return grid, gw, gh
end

function level_io.blank_grid(gw, gh)
  local grid = {}
  for y = 1, gh do
    grid[y] = {}
    for x = 1, gw do
      if y == 1 or y == gh or x == 1 or x == gw then
        grid[y][x] = "#"
      else
        grid[y][x] = "."
      end
    end
  end
  return grid
end

function level_io.level_from_editor(meta, grid, gw, gh)
  local map = level_io.grid_to_map(grid, gw, gh)
  return {
    id = meta.id or 1,
    title = meta.title or "自訂關卡",
    boss_kind = meta.boss_kind or "lightning_sect",
    weapon_drop = meta.weapon_drop,
    arena = meta.arena or level_io.auto_arena(map),
    map = map,
  }
end

function level_io.serialize_lua(level)
  local a = level.arena
  local lines = {
    "return {",
    string.format('  id = %s,', level.id or 1),
    string.format('  title = %q,', level.title or "自訂關卡"),
    string.format('  boss_kind = %q,', level.boss_kind or "lightning_sect"),
  }
  if level.weapon_drop then
    lines[#lines + 1] = string.format('  weapon_drop = %q,', level.weapon_drop)
  else
    lines[#lines + 1] = "  weapon_drop = nil,"
  end
  lines[#lines + 1] = "  arena = {"
  lines[#lines + 1] = string.format("    x1 = %d, y1 = %d, x2 = %d, y2 = %d,", a.x1, a.y1, a.x2, a.y2)
  lines[#lines + 1] = string.format("    enter_tx = %d, enter_ty = %d,", a.enter_tx, a.enter_ty)
  lines[#lines + 1] = string.format("    spawn_tx = %d, spawn_ty = %d,", a.spawn_tx, a.spawn_ty)
  lines[#lines + 1] = string.format("    boss_tx = %d, boss_ty = %d,", a.boss_tx, a.boss_ty)
  lines[#lines + 1] = string.format("    gate_tx = %d, gate_ty = %d,", a.gate_tx, a.gate_ty)
  lines[#lines + 1] = string.format("    return_tx = %d, return_ty = %d,", a.return_tx, a.return_ty)
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "  map = [["
  for line in level.map:gmatch("[^\n]+") do
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = "]],"
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n")
end

function level_io.get_levels_dir()
  return love.filesystem.getSourceBaseDirectory() .. "/levels"
end

function level_io.ensure_levels_dir()
  local dir = level_io.get_levels_dir()
  os.execute('mkdir -p "' .. dir:gsub('"', '\\"') .. '"')
end

function level_io.list_level_files()
  level_io.ensure_levels_dir()
  local files = {}
  local ok, items = pcall(function()
    return love.filesystem.getDirectoryItems("levels")
  end)
  if ok and items then
    for _, name in ipairs(items) do
      if name:match("%.lua$") then
        files[#files + 1] = name
      end
    end
  end
  table.sort(files)
  if #files == 0 then
    local dir = level_io.get_levels_dir()
    if love.system.getOS() ~= "WebOS" then
      for name in io.popen('ls "' .. dir .. '" 2>/dev/null'):lines() do
        if name:match("%.lua$") then
          files[#files + 1] = name
        end
      end
      table.sort(files)
    end
  end
  return files
end

function level_io.load_file(filename)
  local path = "levels/" .. filename
  if love.filesystem.getInfo(path) then
    local chunk, err = love.filesystem.load(path)
    if not chunk then
      return nil, err
    end
    local ok, data = pcall(chunk)
    if ok then return data end
    return nil, data
  end
  local full = level_io.get_levels_dir() .. "/" .. filename
  local f = io.open(full, "r")
  if not f then
    return nil, "找不到檔案"
  end
  local src = f:read("*a")
  f:close()
  local fn, err = load(src, "@" .. full, "t", {})
  if not fn then return nil, err end
  local ok, data = pcall(fn)
  if ok then return data end
  return nil, data
end

function level_io.save_file(filename, level)
  level_io.ensure_levels_dir()
  local body = level_io.serialize_lua(level)
  local full = level_io.get_levels_dir() .. "/" .. filename
  local f = io.open(full, "w")
  if not f then
    return false, "無法寫入 " .. full
  end
  f:write(body)
  f:close()
  if love.filesystem.getInfo("levels") or love.filesystem.createDirectory("levels") then
    love.filesystem.write("levels/" .. filename, body)
  end
  return true, full
end

function level_io.boss_kinds()
  return BOSS_KINDS
end

return level_io
