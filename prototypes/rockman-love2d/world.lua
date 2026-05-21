local world = {}

local TILE = 32

--[[
  # 山石   = 木道（可踩，單格高差可跳）
  ^ 竹刺   E 決鬥圈入口   e 出口（決鬥後回江湖）
  P 出生   a/B/G 決鬥圈內   @ 惡徒   F 關隘
  Q 輕功   R 雷符   K 破甲釘   N 養氣丹   % 金創藥   M 吊橋
]]

local BUILTIN_LEVELS = {
  {
    id = 1,
    title = "第一關 · 梅花林",
    boss_kind = "lightning_sect",
    weapon_drop = "thunder_palm",
    arena = {
      x1 = 36, y1 = 15, x2 = 57, y2 = 17,
      enter_tx = 36, enter_ty = 15,
      spawn_tx = 39, spawn_ty = 16,
      boss_tx = 48, boss_ty = 16,
      gate_tx = 36, gate_ty = 17,
      return_tx = 49, return_ty = 28,
    },
    map = [[
############################################################
#..........................................................#
#...........................Q..............................#
#..========................................................#
#..==========..............................................#
#..============...........................N................#
#..==============..........................................#
#..================.........................R..............#
#..==================.......................%%.............#
#..====================.....................##..##.........#
#..======================...................#....#.........#
#..========================.................#.@.#........#
#..==========================...............######......#
#..============================...........................#
#..==============================.........................#
#..================================E######################.#
#..=================================#G.a....B...#====......#
#..=================================#.............########..#
#..==============================..........................#
#..============================............................#
#..==========================..............................#
#..========================................................#
#..======================..................................#
#..====================....................................#
#..==================......................................#
#..================........................................#
#..==============..........................................#
#..============............................................#
#P===========..........^^^^..........M=============.......#
#=======================================================e==#
#=================================@==================F====#
############################################################
]],
  },
  {
    id = 2,
    title = "第二關 · 鐵門寨",
    boss_kind = "iron_gate",
    weapon_drop = nil,
    arena = {
      x1 = 36, y1 = 15, x2 = 57, y2 = 17,
      enter_tx = 36, enter_ty = 15,
      spawn_tx = 39, spawn_ty = 16,
      boss_tx = 48, boss_ty = 16,
      gate_tx = 36, gate_ty = 17,
      return_tx = 49, return_ty = 28,
    },
    map = [[
############################################################
#..........................................................#
#...........................K..............................#
#..========................................................#
#..==========..............................................#
#..============...........................N................#
#..==============..........................................#
#..================.........................R..............#
#..==================.......................%%.............#
#..====================.....................##..##.........#
#..======================...................#....#.........#
#..========================.................#.@.#........#
#..==========================...............######......#
#..============================...........................#
#..==============================.........................#
#..================================E######################.#
#..=================================#G.a....B...#====......#
#..=================================#.............########..#
#..==============================..........................#
#..============================............................#
#..==========================..............................#
#..========================................................#
#..======================..................................#
#..====================....................................#
#..==================......................................#
#..================........................................#
#..==============..........................................#
#..============............................................#
#P===========..........^^^^..........^^^^....M=========....#
#=======================================================e==#
#=================================@==================F====#
############################################################
]],
  },
}

local LEVELS = {}

function world.reload_level_list()
  LEVELS = {}
  local base = love.filesystem.getSourceBaseDirectory() .. "/levels"
  local names = {}
  local f = io.open(base, "r")
  if f then
    f:close()
    local p = io.popen('ls "' .. base:gsub('"', '\\"') .. '"/*.lua 2>/dev/null')
    if p then
      for path in p:lines() do
        names[#names + 1] = path:match("([^/]+)$")
      end
      p:close()
    end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local full = base .. "/" .. name
    local src_f = io.open(full, "r")
    if src_f then
      local src = src_f:read("*a")
      src_f:close()
      local fn, err = load(src, "@" .. full, "t", {})
      if fn then
        local ok, data = pcall(fn)
        if ok and data and data.map then
          LEVELS[#LEVELS + 1] = data
        end
      end
    end
  end
  if #LEVELS == 0 then
    for _, lv in ipairs(BUILTIN_LEVELS) do
      LEVELS[#LEVELS + 1] = lv
    end
  end
end

function world.load_level_data(level, opts)
  opts = opts or {}
  world.level_index = opts.index or 1
  world.current = level
  world.arena = level.arena or {}
  world.gate_open = opts.gate_open == true
  world.in_arena = false
  parse_map()
end

function world.get_all_levels()
  return LEVELS
end

local BUFF_ITEMS = {
  Q = { id = "qinggong", label = "輕功殘卷" },
  R = { id = "thunder_charm", label = "雷符" },
  K = { id = "armor_break", label = "破甲釘" },
  N = { id = "neili", label = "養氣丹" },
}

local grid = {}
local gw, gh = 0, 0

world.pickups = {}
world.gates = {}
world.spikes = {}
world.platforms = {}
world.current = nil
world.level_index = 1
world.gate_open = false
world.in_arena = false
world.arena = nil

function world.tile_size()
  return TILE
end

function world.get_level()
  return world.current
end

function world.get_level_count()
  return #LEVELS
end

local function parse_map()
  grid = {}
  world.pickups = {}
  world.gates = {}
  world.spikes = {}
  world.platforms = {}

  local rows = {}
  for line in world.current.map:gmatch("[^\n]+") do
    rows[#rows + 1] = line
  end
  gh = #rows
  gw = 0
  for _, r in ipairs(rows) do
    gw = math.max(gw, #r)
  end

  for y = 1, gh do
    grid[y] = {}
    local row = rows[y]
    if #row < gw then
      row = row .. string.rep(".", gw - #row)
    end
    for x = 1, gw do
      local ch = row:sub(x, x)
      if ch == "" then ch = "." end
      if ch == "P" or ch == "a" or ch == "B" or ch == "E" or ch == "e" then
        grid[y][x] = "."
      elseif ch == "M" then
        grid[y][x] = "."
        world.platforms[#world.platforms + 1] = {
          x = (x - 1) * TILE,
          y = (y - 1) * TILE + 14,
          w = TILE * 4,
          h = 14,
          x0 = (x - 1) * TILE - TILE * 2,
          x1 = (x - 1) * TILE + TILE * 6,
          vx = 48,
          dir = 1,
        }
      else
        grid[y][x] = ch
      end

      if ch == "%" then
        world.pickups[#world.pickups + 1] = {
          kind = "heal",
          x = (x - 1) * TILE + 8, y = (y - 1) * TILE + 8,
          w = 14, h = 14,
        }
      elseif BUFF_ITEMS[ch] then
        local b = BUFF_ITEMS[ch]
        world.pickups[#world.pickups + 1] = {
          kind = "buff", buff_id = b.id, label = b.label,
          x = (x - 1) * TILE + 6, y = (y - 1) * TILE + 4,
          w = 18, h = 18,
        }
      elseif ch == "^" then
        world.spikes[#world.spikes + 1] = {
          x = (x - 1) * TILE, y = (y - 1) * TILE + 18,
          w = TILE, h = 14, dmg = 5,
        }
      elseif ch == "G" then
        world.gates[#world.gates + 1] = { tx = x, ty = y }
      end
    end
  end
end

function world.load_level(index, opts)
  opts = opts or {}
  if #LEVELS == 0 then
    world.reload_level_list()
  end
  world.load_level_data(LEVELS[index], { index = index, gate_open = opts.gate_open })
end

function world.open_gate()
  world.gate_open = true
end

function world.is_gate_blocking(tx, ty)
  if world.gate_open then return false end
  for _, g in ipairs(world.gates) do
    if g.tx == tx and g.ty == ty then return true end
  end
  return false
end

local PLANK_TOP = 12  -- 與繪製的 = 木道表面一致（像素）

local function plank_surface_y(ty)
  return (ty - 1) * TILE + PLANK_TOP
end

function world.is_wall_char(ch, tx, ty)
  if ch == "#" then return true end
  if ch == "G" and world.is_gate_blocking(tx, ty) then return true end
  return false
end

-- mode: "wall" 牆與門；"land" 站立／落下（含木道頂）； "bullet" 子彈
function world.rect_hits_solid(x, y, w, h, mode)
  mode = mode or "wall"
  local tx0 = math.floor(x / TILE) + 1
  local ty0 = math.floor(y / TILE) + 1
  local tx1 = math.floor((x + w - 0.01) / TILE) + 1
  local ty1 = math.floor((y + h - 0.01) / TILE) + 1
  local feet = y + h

  for ty = ty0, ty1 do
    for tx = tx0, tx1 do
      if ty >= 1 and tx >= 1 and ty <= gh and tx <= gw then
        local ch = grid[ty][tx]
        if world.is_wall_char(ch, tx, ty) then
          return true
        end
        if ch == "=" and (mode == "land" or mode == "bullet") then
          local surf = plank_surface_y(ty)
          if mode == "bullet" then
            if y < surf + TILE and feet > surf then
              return true
            end
          elseif feet > surf + 2 and y < surf + TILE then
            return true
          end
        end
      elseif ty < 1 or ty > gh or tx < 1 or tx > gw then
        return true
      end
    end
  end

  if mode == "land" or mode == "wall" then
    for _, pl in ipairs(world.platforms) do
      if x < pl.x + pl.w and x + w > pl.x and feet > pl.y + 2 and y < pl.y + pl.h + 8 then
        return true
      end
    end
  end
  return false
end

function world.snap_on_plank(x, y, w, h)
  local best = nil
  local tx0 = math.floor(x / TILE) + 1
  local tx1 = math.floor((x + w - 0.01) / TILE) + 1
  local feet = y + h
  for ty = 1, gh do
    for tx = tx0, tx1 do
      if grid[ty][tx] == "=" then
        local surf = plank_surface_y(ty)
        if feet > surf and y < surf + TILE then
          local stand_y = surf - h - 1
          if not best or stand_y < best then
            best = stand_y
          end
        end
      end
    end
  end
  for _, pl in ipairs(world.platforms) do
    if x < pl.x + pl.w and x + w > pl.x and feet > pl.y then
      local stand_y = pl.y - h - 1
      if not best or stand_y < best then
        best = stand_y
      end
    end
  end
  return best
end

function world.get_platform_carry(px, py)
  for _, pl in ipairs(world.platforms) do
    if px >= pl.x and px <= pl.x + pl.w and py >= pl.y - 4 and py <= pl.y + pl.h + 6 then
      return pl.vx * pl.dir
    end
  end
  return 0
end

function world.update_platforms(dt)
  for _, pl in ipairs(world.platforms) do
    pl.x = pl.x + pl.vx * pl.dir * dt
    if pl.x <= pl.x0 then pl.x = pl.x0; pl.dir = 1 end
    if pl.x + pl.w >= pl.x1 then pl.x = pl.x1 - pl.w; pl.dir = -1 end
  end
end

function world.check_spikes(px, py, pw, ph)
  for _, s in ipairs(world.spikes) do
    if px < s.x + s.w and px + pw > s.x and py < s.y + s.h and py + ph > s.y then
      return s.dmg
    end
  end
  return 0
end

function world.width_px()
  return gw * TILE
end

function world.height_px()
  return gh * TILE
end

function world.spawn_player()
  local row_i = 0
  for line in world.current.map:gmatch("[^\n]+") do
    row_i = row_i + 1
    local px = line:find("P", 1, true)
    if px then
      local x = (px - 1) * TILE + 8
      local y = plank_surface_y(row_i) - 30
      local snapped = world.snap_on_plank(x, y, 20, 28)
      return x, snapped or y
    end
  end
  return TILE * 2, (gh - 2) * TILE - 40
end

function world.arena_spawn_player()
  local a = world.arena
  local x = (a.spawn_tx - 1) * TILE + 8
  local y = plank_surface_y(a.spawn_ty) - 30
  local snapped = world.snap_on_plank(x, y, 20, 28)
  return x, snapped or y
end

function world.arena_return_player()
  local a = world.arena
  local x = (a.return_tx - 1) * TILE + 8
  local y = plank_surface_y(a.return_ty) - 30
  local snapped = world.snap_on_plank(x, y, 20, 28)
  return x, snapped or y
end

function world.arena_boss_spawn()
  local a = world.arena
  return world.current.boss_kind, (a.boss_tx - 1) * TILE + 4, (a.boss_ty - 1) * TILE + 2
end

function world.arena_bounds_px()
  local a = world.arena
  return (a.x1 - 1) * TILE, (a.y1 - 1) * TILE,
         (a.x2 - a.x1 + 1) * TILE, (a.y2 - a.y1 + 1) * TILE
end

function world.check_arena_entrance(px, py, pw, ph)
  if world.in_arena then return false end
  local a = world.arena
  local fx, fy = (a.enter_tx - 1) * TILE, (a.enter_ty - 1) * TILE
  return px < fx + TILE * 2 and px + pw > fx - TILE
      and py < fy + TILE * 2 and py + ph > fy - TILE * 2
end

function world.check_arena_exit(px, py, pw, ph)
  if not world.in_arena or not world.gate_open then return false end
  local a = world.arena
  local fx, fy = (a.gate_tx - 1) * TILE, (a.gate_ty - 1) * TILE
  return px < fx + TILE * 3 and px + pw > fx - TILE
      and py < fy + TILE * 3 and py + ph > fy - TILE * 2
end

function world.collect_enemy_spawns()
  local list = {}
  local row_i = 0
  local ax = world.arena
  for line in world.current.map:gmatch("[^\n]+") do
    row_i = row_i + 1
    local x = 1
    while true do
      local pos = line:find("@", x, true)
      if not pos then break end
      if row_i < ax.y1 or row_i > ax.y2 or pos < ax.x1 or pos > ax.x2 then
        list[#list + 1] = { (pos - 1) * TILE + 6, row_i * TILE - 28 }
      end
      x = pos + 1
    end
  end
  return list
end

function world.check_flag(px, py, pw, ph)
  for y = 1, gh do
    for x = 1, gw do
      if grid[y][x] == "F" then
        local fx, fy = (x - 1) * TILE, (y - 1) * TILE
        if px < fx + TILE and px + pw > fx and py < fy + TILE and py + ph > fy then
          return true
        end
      end
    end
  end
  return false
end

function world.try_collect_pickup(px, py, pw, ph)
  for i = #world.pickups, 1, -1 do
    local p = world.pickups[i]
    if px < p.x + p.w and px + pw > p.x and py < p.y + p.h and py + ph > p.y then
      table.remove(world.pickups, i)
      if p.kind == "buff" then
        return "buff", { id = p.buff_id, label = p.label }
      elseif p.kind == "heal" then
        return "heal", nil
      elseif p.kind == "weapon" then
        return "weapon", p.weapon_id
      end
    end
  end
  return nil, nil
end

function world.spawn_weapon_pickup(weapon_id, x, y)
  world.pickups[#world.pickups + 1] = {
    kind = "weapon", weapon_id = weapon_id,
    x = x - 12, y = y - 10, w = 24, h = 24, bob = 0,
  }
end

function world.draw_pickups(camera_x, camera_y)
  for _, p in ipairs(world.pickups) do
    local sx, sy = p.x - camera_x, p.y - camera_y
    if p.kind == "weapon" then
      p.bob = (p.bob or 0) + love.timer.getDelta() * 4
      sy = sy + math.sin(p.bob) * 3
      love.graphics.setColor(0.9, 0.75, 0.2)
      love.graphics.rectangle("fill", sx, sy, p.w, p.h)
      love.graphics.setColor(0.4, 0.65, 1)
      love.graphics.printf("掌", sx, sy + 2, p.w, "center")
    elseif p.kind == "buff" then
      love.graphics.setColor(0.85, 0.35, 0.55)
      love.graphics.rectangle("fill", sx, sy, p.w, p.h)
      love.graphics.setColor(1, 0.95, 0.8)
      local mark = p.buff_id == "qinggong" and "輕" or p.buff_id == "thunder_charm" and "雷"
          or p.buff_id == "armor_break" and "破" or "氣"
      love.graphics.printf(mark, sx, sy + 1, p.w, "center")
    else
      love.graphics.setColor(0.3, 0.75, 0.4)
      love.graphics.rectangle("fill", sx, sy, p.w, p.h)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function world.draw_platforms(camera_x, camera_y)
  for _, pl in ipairs(world.platforms) do
    love.graphics.setColor(0.55, 0.38, 0.22)
    love.graphics.rectangle("fill", pl.x - camera_x, pl.y - camera_y, pl.w, pl.h)
    love.graphics.setColor(0.7, 0.5, 0.3)
    love.graphics.printf("橋", pl.x - camera_x, pl.y - camera_y, pl.w, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

function world.draw(camera_x, camera_y)
  local sky = world.level_index == 1 and { 0.42, 0.52, 0.38 } or { 0.36, 0.34, 0.4 }
  love.graphics.setColor(sky[1], sky[2], sky[3])
  love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())

  local vx0 = math.floor(camera_x / TILE) - 1
  local vy0 = math.floor(camera_y / TILE) - 1
  local vx1 = vx0 + math.ceil(love.graphics.getWidth() / TILE) + 2
  local vy1 = vy0 + math.ceil(love.graphics.getHeight() / TILE) + 2

  for ty = math.max(1, vy0), math.min(gh, vy1) do
    for tx = math.max(1, vx0), math.min(gw, vx1) do
      local ch = grid[ty][tx]
      local wx = (tx - 1) * TILE - camera_x
      local wy = (ty - 1) * TILE - camera_y
      if ch == "#" then
        love.graphics.setColor(0.32, 0.26, 0.22)
        love.graphics.rectangle("fill", wx, wy, TILE, TILE)
        love.graphics.setColor(0.16, 0.12, 0.1)
        love.graphics.rectangle("line", wx, wy, TILE, TILE)
      elseif ch == "=" then
        love.graphics.setColor(0.52, 0.36, 0.2)
        love.graphics.rectangle("fill", wx, wy + 12, TILE, TILE - 12)
        love.graphics.setColor(0.38, 0.26, 0.14)
        love.graphics.rectangle("line", wx, wy + 12, TILE, TILE - 12)
      elseif ch == "^" then
        love.graphics.setColor(0.75, 0.55, 0.2)
        for i = 0, 3 do
          love.graphics.polygon("fill",
            wx + 4 + i * 7, wy + TILE,
            wx + 8 + i * 7, wy + 18,
            wx + 12 + i * 7, wy + TILE)
        end
      elseif ch == "G" then
        if world.gate_open then
          love.graphics.setColor(0.85, 0.7, 0.25, 0.5)
          love.graphics.rectangle("fill", wx, wy, TILE, TILE)
          love.graphics.printf("出", wx, wy + 8, TILE, "center")
        else
          love.graphics.setColor(0.45, 0.12, 0.1)
          love.graphics.rectangle("fill", wx, wy, TILE, TILE)
          love.graphics.printf("封", wx, wy + 8, TILE, "center")
        end
      elseif ch == "F" then
        love.graphics.setColor(0.85, 0.2, 0.15)
        love.graphics.rectangle("fill", wx + 6, wy + 4, 20, 24)
        love.graphics.setColor(1, 0.85, 0.4)
        love.graphics.printf(world.level_index == 1 and "關二" or "通關", wx, wy + 10, TILE, "center")
      end
    end
  end

  if not world.in_arena and not world.gate_open then
    local a = world.arena
    local ex = (a.enter_tx - 1) * TILE - camera_x
    local ey = (a.enter_ty - 1) * TILE - camera_y
    love.graphics.setColor(0.9, 0.2, 0.15, 0.2)
    love.graphics.rectangle("fill", ex - TILE, ey, TILE * 3, TILE)
    love.graphics.setColor(1, 0.85, 0.5)
    love.graphics.printf("決鬥圈", ex - TILE, ey + 6, TILE * 3, "center")
  end

  if world.in_arena then
    local ax, ay, aw, ah = world.arena_bounds_px()
    love.graphics.setColor(0.9, 0.2, 0.15, 0.1)
    love.graphics.rectangle("fill", ax - camera_x, ay - camera_y, aw, ah)
    love.graphics.setColor(0.85, 0.25, 0.2, 0.45)
    love.graphics.rectangle("line", ax - camera_x, ay - camera_y, aw, ah)
  end

  love.graphics.setColor(1, 1, 1)
end

return world
