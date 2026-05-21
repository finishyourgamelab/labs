local player = {}
player.__index = player

local GRAVITY = 2000
local MOVE_SPEED = 300
local JUMP_VEL = -620
local JUMP_VEL_QING = -700
local MAX_FALL = 820
local COYOTE = 0.1

local WEAPONS = {
  qi_strike = {
    id = "qi_strike",
    label = "氣功波",
    cooldown = 0.2,
    damage = 4,
    bullet_w = 12,
    bullet_h = 8,
    speed = 640,
    life = 1.0,
    color = { 0.95, 0.88, 0.45 },
  },
  thunder_palm = {
    id = "thunder_palm",
    label = "霹靂掌",
    cooldown = 0.3,
    damage = 7,
    bullet_w = 16,
    bullet_h = 12,
    speed = 520,
    life = 1.3,
    color = { 0.45, 0.75, 1 },
  },
}

function player.new(world_mod, x, y)
  local self = setmetatable({}, player)
  self.world = world_mod
  self.x = x
  self.y = y
  self.w = 20
  self.h = 28
  self.vx = 0
  self.vy = 0
  self.facing = 1
  self.grounded = false
  self.coyote = 0
  self.hp = 32
  self.hp_max = 32
  self.shoot_cd = 0
  self.invuln = 0
  self.was_grounded = false
  self.weapons = { qi_strike = true }
  self.active_weapon = "qi_strike"
  self.buffs = {}
  self.weapon_msg = ""
  self.weapon_msg_t = 0
  self.on_platform = nil
  return self
end

function player:has_buff(id)
  return self.buffs[id] == true
end

function player:collect_buff(id, label)
  self.buffs[id] = true
  if id == "neili" then
    self.hp_max = self.hp_max + 6
    self.hp = math.min(self.hp_max, self.hp + 10)
  end
  self.weapon_msg = "取得：" .. (label or id)
  self.weapon_msg_t = 3.2
end

function player:get_jump_vel()
  return self:has_buff("qinggong") and JUMP_VEL_QING or JUMP_VEL
end

function player:get_boss_damage_mult(weapon_id, boss_kind)
  local mult = 1
  if weapon_id == "qi_strike" then
    mult = 1
  elseif weapon_id == "thunder_palm" then
    mult = 1
  end
  if boss_kind == "lightning_sect" then
    if self:has_buff("thunder_charm") then mult = mult * 1.45 end
    if weapon_id == "thunder_palm" then mult = mult * 1.2 end
  elseif boss_kind == "iron_gate" then
    if weapon_id == "thunder_palm" then mult = mult * 2.6 end
    if self:has_buff("armor_break") then mult = mult * 1.35 end
    if weapon_id == "qi_strike" then mult = mult * 0.18 end
  end
  return mult
end

function player:has_weapon(id)
  return self.weapons[id] == true
end

function player:grant_weapon(id)
  if not WEAPONS[id] then return end
  self.weapons[id] = true
  self.active_weapon = id
  self.weapon_msg = "習得武功：" .. WEAPONS[id].label
  self.weapon_msg_t = 3.5
end

function player:switch_weapon(id)
  if self.weapons[id] then
    self.active_weapon = id
  end
end

function player:get_weapon_label()
  local w = WEAPONS[self.active_weapon]
  return w and w.label or "?"
end

function player:hurt(amount)
  if self.invuln > 0 then return end
  local reduce = self:has_buff("iron_scroll") and 0.75 or 1
  self.hp = math.max(0, self.hp - amount * reduce)
  self.invuln = 1.0
  self.vy = -240
  self.vx = -200 * self.facing
end

local function sign(x)
  if x > 0 then return 1 end
  if x < 0 then return -1 end
  return 0
end

function player:try_jump(sfx_jump)
  if self.grounded or self.coyote > 0 then
    self.vy = self:get_jump_vel()
    self.grounded = false
    self.coyote = 0
    if sfx_jump then sfx_jump:stop(); sfx_jump:play() end
  end
end

function player:try_shoot(bullets, sfx_shoot)
  if self.shoot_cd > 0 then return end
  local wdef = WEAPONS[self.active_weapon]
  if not wdef then return end
  self.shoot_cd = wdef.cooldown
  local bx = self.facing > 0 and (self.x + self.w) or (self.x - wdef.bullet_w)
  bullets[#bullets + 1] = {
    x = bx, y = self.y + 10,
    vx = wdef.speed * self.facing,
    life = wdef.life,
    w = wdef.bullet_w, h = wdef.bullet_h,
    damage = wdef.damage,
    weapon_id = wdef.id,
    color = wdef.color,
  }
  if sfx_shoot then sfx_shoot:stop(); sfx_shoot:play() end
end

function player:update(dt, input_left, input_right, jump_pressed, sounds)
  self.shoot_cd = math.max(0, self.shoot_cd - dt)
  self.invuln = math.max(0, self.invuln - dt)
  self.weapon_msg_t = math.max(0, self.weapon_msg_t - dt)

  local move = 0
  if input_left then move = move - 1 end
  if input_right then move = move + 1 end
  if move ~= 0 then self.facing = sign(move) end
  self.vx = move * MOVE_SPEED

  if jump_pressed then self:try_jump(sounds.jump) end
  self.vy = math.min(MAX_FALL, self.vy + GRAVITY * dt)

  if self.grounded then self.coyote = COYOTE
  else self.coyote = math.max(0, self.coyote - dt) end

  self.was_grounded = self.grounded
  self.grounded = false
  self.on_platform = nil

  local w = self.world
  local plat_vx = 0

  self.x = self.x + self.vx * dt
  if w.rect_hits_solid(self.x, self.y, self.w, self.h, "wall") then
    local step = sign(self.vx) * 0.5
    while w.rect_hits_solid(self.x, self.y, self.w, self.h, "wall") do
      self.x = self.x - step
      if math.abs(step) < 0.01 then break end
    end
    self.vx = 0
  end

  self.y = self.y + self.vy * dt
  local hit_wall = w.rect_hits_solid(self.x, self.y, self.w, self.h, "wall")
  local hit_land = self.vy >= 0 and w.rect_hits_solid(self.x, self.y, self.w, self.h, "land")
  if hit_land or hit_wall then
    local step = sign(self.vy) * 0.5
    while (self.vy >= 0 and w.rect_hits_solid(self.x, self.y, self.w, self.h, "land"))
        or w.rect_hits_solid(self.x, self.y, self.w, self.h, "wall") do
      self.y = self.y - step
      if math.abs(step) < 0.01 then break end
    end
    if self.vy > 0 then
      self.grounded = true
      plat_vx = w.get_platform_carry and w.get_platform_carry(self.x + self.w / 2, self.y + self.h) or 0
      self.on_platform = plat_vx ~= 0
      if not self.was_grounded and sounds.land then
        sounds.land:stop(); sounds.land:play()
      end
    end
    self.vy = 0
  end

  if plat_vx ~= 0 then
    self.x = self.x + plat_vx * dt
  end

  local spike_dmg = w.check_spikes(self.x, self.y, self.w, self.h)
  if spike_dmg > 0 and self.invuln <= 0 then
    self:hurt(spike_dmg)
    if sounds.hurt then sounds.hurt:stop(); sounds.hurt:play() end
  end

  local kind, extra = w.try_collect_pickup(self.x, self.y, self.w, self.h)
  if kind == "heal" then
    self.hp = math.min(self.hp_max, self.hp + 8)
    if sounds.pickup then sounds.pickup:stop(); sounds.pickup:play() end
  elseif kind == "buff" and extra then
    self:collect_buff(extra.id, extra.label)
    if sounds.pickup then sounds.pickup:stop(); sounds.pickup:play() end
  elseif kind == "weapon" and extra then
    self:grant_weapon(extra)
    if sounds.pickup then sounds.pickup:stop(); sounds.pickup:play() end
  end
end

function player:draw(cam_x, cam_y)
  local sx, sy = self.x - cam_x, self.y - cam_y
  local flash = self.invuln > 0 and (math.floor(love.timer.getTime() * 14) % 2 == 0)
  if flash then
    love.graphics.setColor(1, 0.95, 0.9, 0.4)
  else
    love.graphics.setColor(0.82, 0.22, 0.18)
  end
  love.graphics.rectangle("fill", sx, sy, self.w, self.h)
  love.graphics.setColor(0.35, 0.12, 0.1)
  love.graphics.rectangle("line", sx, sy, self.w, self.h)
  love.graphics.setColor(0.15, 0.12, 0.1)
  love.graphics.rectangle("fill", sx + 4, sy + 4, self.w - 8, 10)
  if self.active_weapon == "thunder_palm" then
    love.graphics.setColor(0.5, 0.7, 1, 0.9)
    love.graphics.rectangle("fill", sx + 2, sy + 18, 8, 8)
  end
  love.graphics.setColor(0.9, 0.75, 0.5)
  local hx = self.facing > 0 and (sx + self.w - 6) or (sx + 2)
  love.graphics.rectangle("fill", hx, sy + 12, 4, 4)
  love.graphics.setColor(1, 1, 1)
end

return player
