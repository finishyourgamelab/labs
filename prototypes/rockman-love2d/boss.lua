local boss = {}
boss.__index = boss

local function sign(x)
  if x > 0 then return 1 end
  if x < 0 then return -1 end
  return 0
end

local CONFIG = {
  lightning_sect = {
    name = "雷電真人",
    w = 38,
    h = 42,
    hp = 78,
    contact_dmg = 10,
    move_speed = 88,
    weapon_drop = "thunder_palm",
    color = { 0.35, 0.55, 0.88 },
    outline = { 0.12, 0.2, 0.45 },
    weak_to = nil,
  },
  iron_gate = {
    name = "鐵扇門主",
    w = 50,
    h = 48,
    hp = 150,
    contact_dmg = 14,
    move_speed = 48,
    weapon_drop = nil,
    color = { 0.48, 0.5, 0.54 },
    outline = { 0.22, 0.24, 0.28 },
    weak_to = "thunder_palm",
    armored = true,
  },
}

function boss.new(kind, world_mod, x, y)
  local cfg = CONFIG[kind]
  local self = setmetatable({}, boss)
  self.kind = kind
  self.cfg = cfg
  self.world = world_mod
  self.x = x
  self.y = y
  self.w = cfg.w
  self.h = cfg.h
  self.hp = cfg.hp
  self.hp_max = cfg.hp
  self.vx = -cfg.move_speed
  self.vy = 0
  self.alive = true
  self.hit_flash = 0
  self.attack_cd = 1.0
  self.stunned = 0
  self.weak_flash = 0
  return self
end

function boss:get_name()
  return self.cfg.name
end

function boss:get_drop()
  return self.cfg.weapon_drop
end

function boss:take_damage(amount, weapon_id, damage_mult)
  if not self.alive then return false end
  local dmg = amount * (damage_mult or 1)
  if dmg < 0.4 then dmg = 0.4 end
  self.hp = self.hp - dmg
  self.hit_flash = 0.14
  if self.cfg.weak_to == weapon_id then
    self.weak_flash = 0.4
    self.stunned = math.max(self.stunned, 0.3)
  end
  return self.hp <= 0
end

function boss:contact_damage()
  return self.cfg.contact_dmg
end

function boss:update(dt, player, spawn_projectile)
  if not self.alive then return end
  self.hit_flash = math.max(0, self.hit_flash - dt)
  self.weak_flash = math.max(0, self.weak_flash - dt)
  self.stunned = math.max(0, self.stunned - dt)

  if self.stunned <= 0 then
    local wmod = self.world
    self.x = self.x + self.vx * dt
    if wmod.rect_hits_solid(self.x, self.y, self.w, self.h, "wall") then
      self.vx = -self.vx
      self.x = self.x + sign(self.vx) * 3
    end
    local edge_x = self.vx < 0 and self.x or (self.x + self.w)
    if not wmod.rect_hits_solid(edge_x, self.y + self.h - 2, 2, 6, "land") then
      self.vx = -self.vx
    end

    self.attack_cd = self.attack_cd - dt
    if self.attack_cd <= 0 and spawn_projectile then
      self.attack_cd = self.kind == "lightning_sect" and 1.25 or 1.65
      local cx = self.x + self.w / 2
      local cy = self.y + self.h / 2
      if self.kind == "lightning_sect" then
        local dir = player.x + player.w / 2 < cx and -1 or 1
        for i = -1, 1 do
          spawn_projectile({
            x = cx - 6, y = cy - 6,
            vx = 260 * dir + i * 50, vy = -80 + i * 70,
            w = 10, h = 10, life = 2.0, dmg = 8,
            kind = "lightning",
          })
        end
      else
        spawn_projectile({
          x = cx - 10, y = self.y + 10,
          vx = player.x > self.x and 190 or -190, vy = -40,
          w = 16, h = 12, life = 2.2, dmg = 10,
          kind = "iron_fan",
        })
      end
    end
  end

  self.vy = (self.vy or 0) + 2000 * dt
  self.vy = math.min(self.vy, 800)
  self.y = self.y + self.vy * dt
  if self.world.rect_hits_solid(self.x, self.y, self.w, self.h, "land")
      or self.world.rect_hits_solid(self.x, self.y, self.w, self.h, "wall") then
    while self.world.rect_hits_solid(self.x, self.y, self.w, self.h, "land")
        or self.world.rect_hits_solid(self.x, self.y, self.w, self.h, "wall") do
      self.y = self.y - 1
    end
    self.vy = 0
  end
end

function boss:draw(cam_x, cam_y)
  if not self.alive then return end
  local sx, sy = self.x - cam_x, self.y - cam_y
  local c = self.cfg.color
  if self.hit_flash > 0 then
    love.graphics.setColor(1, 0.92, 0.75)
  elseif self.weak_flash > 0 then
    love.graphics.setColor(0.55, 0.85, 1)
  else
    love.graphics.setColor(c[1], c[2], c[3])
  end
  love.graphics.rectangle("fill", sx, sy, self.w, self.h)
  love.graphics.setColor(self.cfg.outline[1], self.cfg.outline[2], self.cfg.outline[3])
  love.graphics.rectangle("line", sx, sy, self.w, self.h)
  if self.kind == "lightning_sect" then
    love.graphics.setColor(0.6, 0.85, 1)
    love.graphics.printf("雷", sx, sy + 10, self.w, "center")
  else
    love.graphics.setColor(0.65, 0.68, 0.72)
    love.graphics.rectangle("fill", sx + 6, sy + 8, self.w - 12, self.h - 16)
    love.graphics.setColor(0.85, 0.88, 0.92, 0.45)
    love.graphics.rectangle("line", sx - 4, sy - 4, self.w + 8, self.h + 8)
    love.graphics.printf("鐵", sx, sy + 14, self.w, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

function boss.draw_hp_bar(b, cam_x, cam_y)
  if not b or not b.alive then return end
  local bx = b.x - cam_x
  local by = b.y - cam_y - 18
  local bw = math.max(b.w, 80)
  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", bx - 20, by, bw + 40, 10)
  love.graphics.setColor(0.82, 0.18, 0.14)
  love.graphics.rectangle("fill", bx - 18, by + 1, (bw + 36) * (b.hp / b.hp_max), 7)
  love.graphics.setColor(1, 0.9, 0.75)
  love.graphics.printf("掌門 · " .. b:get_name(), bx - 20, by - 18, bw + 40, "center")
  love.graphics.setColor(1, 1, 1)
end

return boss
