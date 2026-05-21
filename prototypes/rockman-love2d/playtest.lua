--[[ 編輯器內試玩（按 T 進入，Esc 回編輯器） ]]
local world = require("world")
local Player = require("player")
local Enemy = require("enemy")
local Boss = require("boss")

local pt = {
  p = nil,
  boss = nil,
  enemies = {},
  bullets = {},
  boss_bullets = {},
  cam_x = 0,
  cam_y = 0,
  boss_defeated = false,
  in_arena = false,
  hint = "試玩中 · Esc 回編輯器",
  hint_t = 999,
}

local function overlap(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

local function spawn_all(level)
  world.load_level_data(level, { index = 1, gate_open = false })
  local sx, sy = world.spawn_player()
  pt.p = Player.new(world, sx, sy)
  local snapped = world.snap_on_plank(pt.p.x, pt.p.y, pt.p.w, pt.p.h)
  if snapped then pt.p.y = snapped end
  pt.enemies = {}
  for _, pos in ipairs(world.collect_enemy_spawns()) do
    pt.enemies[#pt.enemies + 1] = Enemy.new(world, pos[1], pos[2])
  end
  pt.boss = nil
  pt.bullets = {}
  pt.boss_bullets = {}
  pt.boss_defeated = false
  pt.in_arena = false
end

local function enter_arena()
  world.in_arena = true
  local sx, sy = world.arena_spawn_player()
  pt.p.x, pt.p.y = sx, sy
  pt.p.vx, pt.p.vy = 0, 0
  if not pt.boss_defeated then
    local kind, bx, by = world.arena_boss_spawn()
    pt.boss = Boss.new(kind, world, bx, by)
  end
end

local M = {}

function M.start(level)
  spawn_all(level)
end

function M.update(dt)
  local p = pt.p
  world.update_platforms(dt)
  local ml = love.keyboard.isDown("left") or love.keyboard.isDown("a")
  local mr = love.keyboard.isDown("right") or love.keyboard.isDown("d")
  local jmp = love.keyboard.isDown("space") or love.keyboard.isDown("z")
  p:update(dt, ml, mr, jmp, {})
  if love.keyboard.isDown("x") or love.keyboard.isDown("j") then
    p:try_shoot(pt.bullets, nil)
  end

  if not world.in_arena then
    for _, e in ipairs(pt.enemies) do
      if e.alive then e:update(dt) end
    end
    if world.check_arena_entrance(p.x, p.y, p.w, p.h) then
      enter_arena()
    end
  else
    if pt.boss and pt.boss.alive then
      pt.boss:update(dt, p, function(proj)
        pt.boss_bullets[#pt.boss_bullets + 1] = proj
      end)
    end
    if pt.boss_defeated and world.check_arena_exit(p.x, p.y, p.w, p.h) then
      world.in_arena = false
      local sx, sy = world.arena_return_player()
      p.x, p.y = sx, sy
      pt.boss = nil
    end
  end

  local ww, wh = love.graphics.getDimensions()
  if world.in_arena then
    local ax, ay, aw, ah = world.arena_bounds_px()
    pt.cam_x = math.max(ax, math.min(ax + aw / 2 - ww / 2, ax + aw - ww))
    pt.cam_y = math.max(ay, math.min(ay + ah / 2 - wh / 2, ay + ah - wh))
  else
    pt.cam_x = math.max(0, math.min(p.x - ww / 2, world.width_px() - ww))
    pt.cam_y = math.max(0, math.min(p.y - wh / 2, world.height_px() - wh))
  end
end

function M.draw()
  world.draw(pt.cam_x, pt.cam_y)
  world.draw_platforms(pt.cam_x, pt.cam_y)
  world.draw_pickups(pt.cam_x, pt.cam_y)
  if not world.in_arena then
    for _, e in ipairs(pt.enemies) do e:draw(pt.cam_x, pt.cam_y) end
  end
  if pt.boss then pt.boss:draw(pt.cam_x, pt.cam_y) end
  pt.p:draw(pt.cam_x, pt.cam_y)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", 0, 0, 400, 28)
  love.graphics.setColor(1, 0.9, 0.7)
  love.graphics.print(pt.hint, 10, 8)
end

function M.keypressed(key)
  if key == "escape" then
    require("level_editor").mount()
    return true
  end
  if key == "1" then pt.p:switch_weapon("qi_strike") end
  if key == "2" and pt.p:has_weapon("thunder_palm") then pt.p:switch_weapon("thunder_palm") end
  if key == "space" or key == "z" then pt.p:try_jump() end
  if key == "x" or key == "j" then pt.p:try_shoot(pt.bullets, nil) end
  return false
end

function M.mount()
  love.load = function() end
  love.update = M.update
  love.draw = M.draw
  love.keypressed = function(key)
    if M.keypressed(key) then return end
  end
  love.mousepressed = function() end
  love.mousereleased = function() end
  love.wheelmoved = function() end
end

return M
