local enemy = {}
enemy.__index = enemy

local function sign(x)
  if x > 0 then return 1 end
  if x < 0 then return -1 end
  return 0
end

function enemy.new(world_mod, x, y)
  local self = setmetatable({}, enemy)
  self.world = world_mod
  self.x = x
  self.y = y
  self.w = 22
  self.h = 24
  self.vx = -65
  self.hp = 10
  self.hit_flash = 0
  self.alive = true
  self.vy = 0
  return self
end

function enemy:take_damage(n)
  self.hp = self.hp - n
  self.hit_flash = 0.12
  return self.hp <= 0
end

function enemy:update(dt)
  if not self.alive then return end
  self.hit_flash = math.max(0, self.hit_flash - dt)
  local wmod = self.world
  self.x = self.x + self.vx * dt
  local turn = wmod.rect_hits_solid(self.x, self.y, self.w, self.h, "wall")
  local edge_x = self.vx < 0 and self.x or (self.x + self.w)
  if not turn and not wmod.rect_hits_solid(edge_x, self.y + self.h, 2, 6, "land") then
    turn = true
  end
  if turn then
    self.vx = -self.vx
    self.x = self.x + sign(self.vx) * 2
  end
  self.vy = self.vy + 1800 * dt
  self.vy = math.min(self.vy, 700)
  self.y = self.y + self.vy * dt
  if wmod.rect_hits_solid(self.x, self.y, self.w, self.h, "land")
      or wmod.rect_hits_solid(self.x, self.y, self.w, self.h, "wall") then
    while wmod.rect_hits_solid(self.x, self.y, self.w, self.h, "land")
        or wmod.rect_hits_solid(self.x, self.y, self.w, self.h, "wall") do
      self.y = self.y - 1
    end
    self.vy = 0
  end
end

function enemy:draw(cam_x, cam_y)
  if not self.alive then return end
  local sx, sy = self.x - cam_x, self.y - cam_y
  if self.hit_flash > 0 then
    love.graphics.setColor(1, 0.9, 0.7)
  else
    love.graphics.setColor(0.55, 0.22, 0.2)
  end
  love.graphics.rectangle("fill", sx + 2, sy + 4, self.w - 4, self.h - 4)
  love.graphics.setColor(0.25, 0.1, 0.08)
  love.graphics.rectangle("line", sx + 2, sy + 4, self.w - 4, self.h - 4)
  love.graphics.setColor(0.9, 0.75, 0.5)
  love.graphics.printf("惡", sx, sy + 6, self.w, "center")
  love.graphics.setColor(1, 1, 1)
end

return enemy
