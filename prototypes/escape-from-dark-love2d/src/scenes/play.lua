local util = require("src.util")
local fonts = require("src.fonts")
local levels = require("src.levels")
local enemyTpl = require("src.enemies")
local audio = require("src.audio")
local items = require("src.items")
local inventory = require("src.inventory")

local Play = {}
Play.__index = Play

local TAU = util.TAU

local function clamp(v, a, b) return util.clamp(v, a, b) end
local function dist(ax, ay, bx, by) return util.distance(ax, ay, bx, by) end
local function setColor(c) util.setColor(c) end

-- ---------------------------------------------------------------------------
-- 工具：碰撞判定
-- ---------------------------------------------------------------------------

local function pointInRect(rect, x, y)
  return x >= rect.x and x <= rect.x + rect.w
    and y >= rect.y and y <= rect.y + rect.h
end

local function isBlocked(level, x, y, radius)
  if x < radius or y < radius
    or x > level.world.w - radius or y > level.world.h - radius then
    return true
  end
  for _, rect in ipairs(level.obstacles) do
    local closestX = clamp(x, rect.x, rect.x + rect.w)
    local closestY = clamp(y, rect.y, rect.y + rect.h)
    if dist(x, y, closestX, closestY) < radius then
      return true
    end
  end
  return false
end

local function lineBlocked(level, x1, y1, x2, y2)
  -- 取樣式線段檢測：每 12px 取一次點
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  if len <= 0.0001 then return false end
  local steps = math.max(2, math.floor(len / 12))
  for i = 1, steps - 1 do
    local t = i / steps
    local x = x1 + dx * t
    local y = y1 + dy * t
    for _, rect in ipairs(level.obstacles) do
      if pointInRect(rect, x, y) then
        return true
      end
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- 玩家
-- ---------------------------------------------------------------------------

local function newPlayer(level)
  return {
    x = level.spawn.x, y = level.spawn.y,
    radius = 16, speed = 200,
    hp = 100, maxHp = 100,
    armor = 35, maxArmor = 35,
    stamina = 100, maxStamina = 100,
    stress = 0, maxStress = 100, stressDelta = 0, lightLevel = 0,
    ammo = 30, maxAmmo = 90,
    medkits = 1,
    loot = 0, kills = 0,
    fireCooldown = 0, footstepTimer = 0,
    interactTarget = nil, extracting = 0,
    angle = 0,
    crouching = false,
    sprinting = false,
    -- 噪音值（0-1）：開槍/奔跑會推高，蹲伏/靜止會下降
    noise = 0,
    heartbeatTimer = 0,
    whisperTimer = math.huge,  -- 觸發 stress 高時短暫播放低語
    hurtFlash = 0,
    -- 視野：以滑鼠方向為中心的扇形，加上一個小範圍的全周圍感知圈
    visionRange = 460,
    visionAngle = math.rad(110),  -- 站立 ±55°
    proximityRange = 90,          -- 背後也能感知到的近身圈
    -- 物資：背包初始給少量起手；ammo 不再放在背包，仍直接走 player.ammo
    inventory = inventory.new({ weightLimit = 30, slotLimit = 16 }),
  }
end

-- ---------------------------------------------------------------------------
-- 敵人
-- ---------------------------------------------------------------------------

local function newEnemy(spec)
  local t = enemyTpl.template(spec.kind)
  local first = spec.patrol and spec.patrol[1] or { x = 0, y = 0 }
  return {
    kind = spec.kind, template = t,
    x = first.x, y = first.y,
    hp = t.hp, maxHp = t.hp,
    radius = t.radius, color = t.color,
    speed = t.speed,
    damage = t.damage, value = t.value,
    angle = 0,
    patrol = spec.patrol or { { x = first.x, y = first.y } },
    patrolIdx = 1,
    waitTimer = 0,
    sightRange = spec.sightRange or 220,
    sightAngle = spec.sightAngle or t.fov,
    hearingRange = spec.hearingRange or 120,
    awareness = 0,           -- 0=放鬆, 1=警戒(衝過去), >=2=戰鬥
    alertTimer = 0,
    investigateTarget = nil, -- 聽到聲音時的目標座標
    fireCooldown = 0,
    stagger = 0,
  }
end

-- ---------------------------------------------------------------------------
-- 場景生命週期
-- ---------------------------------------------------------------------------

function Play.new(levelIndex)
  local self = setmetatable({}, Play)
  self.levelIndex = levelIndex or 1
  return self
end

function Play:enter()
  local level = levels.get(self.levelIndex)
  self.level = level
  self.phase = "playing"
  self.time = 0
  self.shake = 0
  self.alarm = 0  -- 全關卡警報級別 0/1/2
  self.spawnTimer = 14   -- 援軍計時器
  self.message = ("關卡 %d  %s"):format(self.levelIndex, level.name)
  self.messageTimer = 4.5
  self.player = newPlayer(level)
  self.bullets = {}
  self.enemyBullets = {}
  self.enemies = {}
  self.particles = {}
  self.crates = {}
  self.lights = {}

  for _, c in ipairs(level.crates) do
    table.insert(self.crates, {
      x = c.x, y = c.y, kind = c.kind, label = c.label,
      radius = 30, searched = false, searchProgress = 0,
    })
  end
  for _, lt in ipairs(level.lights) do
    table.insert(self.lights, lt)
  end
  for _, e in ipairs(level.enemies) do
    table.insert(self.enemies, newEnemy(e))
  end

  -- 儲物箱：每關放一個在 spawn 旁，inventory 跨關卡不保留（單關生存遊戲）。
  -- 撤離條件改為「估價 ≥ lootGoal」，玩家要從背包中挑值錢的東西帶走。
  self.stash = {
    x = level.spawn.x + 80,
    y = level.spawn.y,
    radius = 32,
    label = "儲物箱",
    inventory = inventory.new({ weightLimit = 80, slotLimit = 24 }),
  }

  -- 初始物資（給玩家熟悉系統）
  inventory.add(self.player.inventory, "bandage", 2)
  inventory.add(self.player.inventory, "cloth", 2)

  -- UI 狀態
  self.uiPanel = nil   -- nil / "inventory" / "stash"
  self.uiCursor = 1
  self.uiSide = "player"   -- 在 stash 模式時切換 player / stash
  self.uiTab = "items"     -- "items" / "craft"
  self.uiCraftCursor = 1

  self.camera = { x = 0, y = 0 }

  audio.playMusic(level.bgm)
  audio.playSfx("sfx_extract_arm", { volume = 0.4 })
end

function Play:leave()
end

-- ---------------------------------------------------------------------------
-- 共用
-- ---------------------------------------------------------------------------

local function newParticle(self, x, y, color, size, life, vx, vy)
  table.insert(self.particles, {
    x = x, y = y,
    vx = vx or love.math.random(-30, 30),
    vy = vy or love.math.random(-30, 30),
    color = color, size = size, life = life, maxLife = life,
  })
end

local function postMessage(self, text, duration)
  self.message = text
  self.messageTimer = duration or 2.4
end

local function moveActor(self, actor, dx, dy, dt)
  local nx = actor.x + dx * dt
  if not isBlocked(self.level, nx, actor.y, actor.radius) then
    actor.x = nx
  end
  local ny = actor.y + dy * dt
  if not isBlocked(self.level, actor.x, ny, actor.radius) then
    actor.y = ny
  end
end

local function screenToWorld(self, x, y)
  return x + self.camera.x, y + self.camera.y
end

-- 玩家是否能看到 (tx, ty)：以滑鼠朝向的扇形視野 + 近身周圍圈 + 線段遮蔽
local function playerCanSee(self, tx, ty)
  local p = self.player
  local d = dist(p.x, p.y, tx, ty)
  -- 近身全周圍：背後也能察覺
  if d < p.proximityRange then
    return not lineBlocked(self.level, p.x, p.y, tx, ty)
  end
  if d > p.visionRange then return false end
  local angleToTarget = util.angleTo(ty - p.y, tx - p.x)
  local diff = math.abs(util.angleDelta(p.angle, angleToTarget))
  if diff > p.visionAngle / 2 then return false end
  return not lineBlocked(self.level, p.x, p.y, tx, ty)
end

-- 任意點接收到的光照亮度（0..1），考慮燈光半徑與遮蔽。
-- 採用「中心 plateau」曲線：靠近燈光時亮度迅速接近 1，邊緣才快速衰減，
-- 玩家可以靠在油燈旁長時間恢復，而不需要踩在像素點上。
local function lightAt(self, x, y)
  local total = 0
  for _, lt in ipairs(self.lights) do
    local d = dist(x, y, lt.x, lt.y)
    if d < lt.radius then
      if not lineBlocked(self.level, x, y, lt.x, lt.y) then
        -- t in [0,1]：0 = 中心，1 = 邊緣
        local t = d / lt.radius
        -- 1 - t² 在中心附近平緩，邊緣加速衰減
        local v = 1 - t * t
        if v > total then total = v end
      end
    end
  end
  return total
end

-- ---------------------------------------------------------------------------
-- 玩家行為
-- ---------------------------------------------------------------------------

local function shoot(self)
  local p = self.player
  if p.fireCooldown > 0 then return end
  if p.ammo <= 0 then
    audio.playSfx("sfx_dryfire")
    postMessage(self, "沒有彈藥，搜尋彈藥箱或按 E 開箱。", 1.4)
    p.fireCooldown = 0.35
    return
  end

  local mx, my = screenToWorld(self, love.mouse.getPosition())
  local dx, dy = util.normalize(mx - p.x, my - p.y)
  if dx == 0 and dy == 0 then
    dx, dy = math.cos(p.angle), math.sin(p.angle)
  end
  p.angle = util.angleTo(dy, dx)
  p.ammo = p.ammo - 1
  p.fireCooldown = 0.22
  self.shake = 4
  p.noise = 1.0   -- 開槍是最大聲

  table.insert(self.bullets, {
    x = p.x + dx * 22, y = p.y + dy * 22,
    vx = dx * 760, vy = dy * 760,
    radius = 5, damage = 24, life = 0.72,
  })
  for _ = 1, 4 do
    newParticle(self, p.x + dx * 24, p.y + dy * 24,
      { 1, 0.78, 0.34 }, 3, 0.22,
      dx * 80 + love.math.random(-30, 30),
      dy * 80 + love.math.random(-30, 30))
  end
  audio.playSfx("sfx_pistol")
end

local function giveLoot(self, crate)
  local p = self.player
  local table_ = items.lootTable(crate.kind)
  local added = inventory.lootFromTable(p.inventory, table_)

  crate.searched = true
  -- 即時把 ammo_pistol 變成槍枝彈藥（避免子彈也擠背包）
  for i = #p.inventory.stacks, 1, -1 do
    local s = p.inventory.stacks[i]
    if s.id == "ammo_pistol" then
      local need = p.maxAmmo - p.ammo
      if need > 0 then
        local n = math.min(s.count, need)
        p.ammo = p.ammo + n
        s.count = s.count - n
        if s.count <= 0 then table.remove(p.inventory.stacks, i) end
      end
    end
  end

  -- 估價只供訊息顯示；實際結算在撤離時 inventory.appraise
  local summary = {}
  local overflow = false
  for _, a in ipairs(added) do
    local def = items.def(a.id)
    local label = ("%s ×%d"):format(def and def.name or a.id, a.count)
    if a.overflow then label = label .. "（背包滿）"; overflow = true end
    table.insert(summary, label)
  end
  if #summary == 0 then summary = { "（空無一物）" } end
  postMessage(self, ("搜出 %s：%s"):format(crate.label, table.concat(summary, "、")), 3.0)
  if overflow then
    postMessage(self, "背包已滿，部分物資只能丟在原地。", 3.0)
  end
  for _ = 1, 12 do
    newParticle(self, crate.x, crate.y, { 0.98, 0.82, 0.32 },
      love.math.random(2, 5), 0.65)
  end
  audio.playSfx("sfx_pickup")
end

local function useMedkit(self)
  local p = self.player
  -- Q：先用 medkit；沒有再用 bandage；都沒有就提示。
  local order = { "medkit", "bandage" }
  for _, id in ipairs(order) do
    if inventory.countOf(p.inventory, id) > 0 then
      if inventory.useFirst(p.inventory, id, p) then
        local def = items.def(id)
        postMessage(self, ("使用%s，HP %d/%d"):format(def.name, math.floor(p.hp), p.maxHp), 1.6)
        audio.playSfx("sfx_pickup", { pitch = 0.8 })
        return
      end
    end
  end
  if p.hp >= p.maxHp then
    postMessage(self, "生命值已滿。", 1.0)
  else
    postMessage(self, "沒有可用的醫療物品。", 1.5)
  end
end

local function usePill(self)
  local p = self.player
  if inventory.useFirst(p.inventory, "pill", p) then
    postMessage(self, "服用鎮靜劑，壓力降低。", 1.6)
    audio.playSfx("sfx_pickup", { pitch = 1.1 })
  else
    postMessage(self, "沒有鎮靜劑。", 1.0)
  end
end

local function craftFirstAvailable(self, recipeId)
  local p = self.player
  for _, r in ipairs(items.recipes()) do
    if r.id == recipeId then
      local ok, msg = inventory.craft(p.inventory, r)
      postMessage(self, msg, 2.0)
      if ok then audio.playSfx("sfx_pickup", { pitch = 0.9 }) end
      return ok
    end
  end
  return false
end

local function damagePlayer(self, amount, source)
  local p = self.player
  local armorDamage = math.min(p.armor, amount * 0.65)
  p.armor = p.armor - armorDamage
  p.hp = p.hp - (amount - armorDamage)
  p.hurtFlash = 1.0
  self.shake = 6
  audio.playSfx("sfx_player_hurt")
  if p.hp <= 0 then
    p.hp = 0
    self.phase = "lost"
    postMessage(self, "撤離失敗，鴨子倒在" .. (self.level.name) .. "。", 99)
  end
end

-- ---------------------------------------------------------------------------
-- 玩家更新
-- ---------------------------------------------------------------------------

local function updateInteraction(self, dt)
  local p = self.player
  p.interactTarget = nil
  for _, crate in ipairs(self.crates) do
    if not crate.searched and dist(p.x, p.y, crate.x, crate.y) <= 56 then
      p.interactTarget = { type = "crate", ref = crate }
      break
    end
  end
  if not p.interactTarget and p.loot >= self.level.lootGoal then
    for _, ext in ipairs(self.level.extracts) do
      if pointInRect(ext, p.x, p.y) then
        p.interactTarget = { type = "extract", ref = ext }
        break
      end
    end
  end
  if love.keyboard.isDown("e") and p.interactTarget then
    if p.interactTarget.type == "crate" then
      local crate = p.interactTarget.ref
      crate.searchProgress = crate.searchProgress + dt
      if crate.searchProgress >= 0.7 then
        giveLoot(self, crate)
      end
    elseif p.interactTarget.type == "extract" then
      p.extracting = p.extracting + dt
      if p.extracting >= 2.4 then
        self.phase = "won"
        audio.playSfx("sfx_extract_done")
        postMessage(self, "成功撤離 — 第 " .. self.levelIndex .. " 夜結束。", 99)
      end
    end
  else
    p.extracting = 0
    for _, crate in ipairs(self.crates) do
      if not crate.searched then
        crate.searchProgress = math.max(0, crate.searchProgress - dt * 1.7)
      end
    end
  end
end

local function updatePlayer(self, dt)
  local p = self.player
  local ix, iy = 0, 0
  if love.keyboard.isDown("w", "up") then iy = iy - 1 end
  if love.keyboard.isDown("s", "down") then iy = iy + 1 end
  if love.keyboard.isDown("a", "left") then ix = ix - 1 end
  if love.keyboard.isDown("d", "right") then ix = ix + 1 end

  local nx, ny = util.normalize(ix, iy)
  local moving = nx ~= 0 or ny ~= 0

  -- 蹲伏：Ctrl 或 C
  p.crouching = love.keyboard.isDown("lctrl", "rctrl", "c")
  p.sprinting = love.keyboard.isDown("lshift", "rshift") and p.stamina > 5 and moving and not p.crouching

  local speed = p.speed
  if p.crouching then
    speed = speed * 0.45
  elseif p.sprinting then
    speed = speed * 1.45
    p.stamina = math.max(0, p.stamina - dt * 22)
  end
  if not p.sprinting then
    p.stamina = clamp(p.stamina + dt * 18, 0, p.maxStamina)
  end

  moveActor(self, p, nx * speed, ny * speed, dt)

  -- 視野依姿態調整：
  --   蹲伏 → 距離縮短、角度變廣（探視）
  --   奔跑 → 距離拉長、角度收窄（隧道視效應）
  --   站立 → 平衡值
  if p.crouching then
    p.visionRange = 380
    p.visionAngle = math.rad(140)
  elseif p.sprinting then
    p.visionRange = 540
    p.visionAngle = math.rad(70)
  else
    p.visionRange = 460
    p.visionAngle = math.rad(110)
  end

  -- 噪音衰減；移動會持續產生噪音
  local moveNoise = 0
  if moving then
    if p.sprinting then moveNoise = 0.7
    elseif p.crouching then moveNoise = 0.08
    else moveNoise = 0.32 end
  end
  -- 高壓玩家踩踏較重，連走路都更響（恐怖氛圍：心慌的人聲息暴露自己）
  local stressBoost = 1 + (p.stress / p.maxStress) * 0.4
  moveNoise = moveNoise * stressBoost
  -- 噪音採取較大值，避免開槍立即被衰減覆蓋
  p.noise = math.max(p.noise * (1 - dt * 1.4), moveNoise)

  -- 走路腳步聲（給予玩家節奏感的音效）
  if moving then
    p.footstepTimer = p.footstepTimer - dt
    if p.footstepTimer <= 0 then
      audio.playSfx("sfx_step", {
        volume = p.crouching and 0.25 or (p.sprinting and 0.65 or 0.45),
        pitch = 0.85 + love.math.random() * 0.3,
      })
      p.footstepTimer = p.crouching and 0.6 or (p.sprinting and 0.28 or 0.42)
    end
  else
    p.footstepTimer = 0
  end

  -- 滑鼠瞄準
  local mx, my = screenToWorld(self, love.mouse.getPosition())
  local ax, ay = util.normalize(mx - p.x, my - p.y)
  if ax ~= 0 or ay ~= 0 then
    p.angle = util.angleTo(ay, ax)
  end

  p.fireCooldown = math.max(0, p.fireCooldown - dt)
  if love.mouse.isDown(1) or love.keyboard.isDown("space") then
    shoot(self)
  end

  p.hurtFlash = math.max(0, p.hurtFlash - dt * 1.6)
  updateInteraction(self, dt)

  -- 壓力值（恐怖氛圍）
  -- 設計目標：黑暗中「行動」會推高壓力，站定時能穩住呼吸；
  -- 靠近燈光持續恢復，玩家總是有出路降壓。
  -- 平衡點：light ≈ 0.2 是中性區，更亮恢復、更暗累積；光照非常亮時直接無視 alarm。
  local light = lightAt(self, p.x, p.y)
  p.lightLevel = light
  local stressRate = self.level.ambience.stressRate
  local stressRecover = self.level.ambience.stressRecover
  local NEUTRAL = 0.2
  if light > NEUTRAL then
    local recoverMul = (light - NEUTRAL) / (1 - NEUTRAL)
    if light > 0.55 then recoverMul = recoverMul * 1.6 end
    p.stressDelta = -stressRecover * recoverMul
    p.stress = math.max(0, p.stress + p.stressDelta * dt)
  else
    -- 黑暗累積：只在玩家移動時增加；站定時不再「原地嚇到爆」。
    local darkness = 1 - (light / NEUTRAL)
    local activity = 0
    if moving then
      if p.sprinting then
        activity = 1.2
      elseif p.crouching then
        activity = 0.25
      else
        activity = 0.65
      end
    end
    if activity > 0 then
      p.stressDelta = stressRate * (0.3 + darkness * 0.7) * activity
      p.stress = math.min(p.maxStress, p.stress + p.stressDelta * dt)
    else
      -- 停下來聽、看、穩住呼吸：黑暗仍危險，但不會憑空繼續增加壓力。
      p.stressDelta = -0.35
      p.stress = math.max(0, p.stress + p.stressDelta * dt)
    end
  end
  -- 警報懲罰：只在 alarm 活躍 + 玩家不在強光下時加
  if self.alarm >= 1 and light < 0.55 then
    local alarmStress = 1.5 * (1 - light * 0.9)
    if alarmStress > 0 then
      p.stressDelta = (p.stressDelta or 0) + alarmStress
      p.stress = math.min(p.maxStress, p.stress + alarmStress * dt)
    end
  end
  if p.stress >= p.maxStress then
    -- 壓力到頂視為精神崩潰
    self.phase = "lost"
    postMessage(self, "壓力到頂，鴨子在黑暗中失神。", 99)
    audio.playSfx("sfx_whisper")
  end

  -- 心跳：壓力高 / hp 低 觸發
  local heartbeatLevel = math.max(p.stress / p.maxStress, 1 - p.hp / p.maxHp)
  if heartbeatLevel > 0.4 then
    p.heartbeatTimer = p.heartbeatTimer - dt
    if p.heartbeatTimer <= 0 then
      audio.playSfx("sfx_heartbeat", {
        volume = clamp(heartbeatLevel, 0.4, 1),
        pitch = 0.85 + heartbeatLevel * 0.25,
      })
      p.heartbeatTimer = util.lerp(1.4, 0.55, clamp(heartbeatLevel, 0, 1))
    end
  else
    p.heartbeatTimer = 0
  end
  -- 低語：壓力非常高時偶發
  if p.stress > p.maxStress * 0.7 then
    p.whisperTimer = p.whisperTimer - dt
    if p.whisperTimer <= 0 then
      audio.playSfx("sfx_whisper", { volume = 0.55 })
      p.whisperTimer = love.math.random(6, 10)
    end
  else
    p.whisperTimer = love.math.random(8, 14)
  end
end

-- ---------------------------------------------------------------------------
-- 敵人 AI
-- ---------------------------------------------------------------------------

local function canSee(self, enemy, target)
  local d = dist(enemy.x, enemy.y, target.x, target.y)
  if d > enemy.sightRange then return false, d end
  local angleToTarget = util.angleTo(target.y - enemy.y, target.x - enemy.x)
  local diff = math.abs(util.angleDelta(enemy.angle, angleToTarget))
  if diff > enemy.sightAngle / 2 then return false, d end
  if lineBlocked(self.level, enemy.x, enemy.y, target.x, target.y) then
    return false, d
  end
  return true, d
end

local function canHear(enemy, target, noise, alarm, crouching)
  local d = dist(enemy.x, enemy.y, target.x, target.y)
  -- 噪音越高、警報越高，聽覺範圍實際擴大；蹲伏會直接削減聽覺距離
  local effective = enemy.hearingRange * (0.4 + noise * 1.2 + alarm * 0.4)
  if crouching then effective = effective * 0.55 end
  return d < effective, d
end

local function enemyShoot(self, enemy)
  local p = self.player
  local dx, dy = util.normalize(p.x - enemy.x, p.y - enemy.y)
  if dx == 0 and dy == 0 then return end
  enemy.fireCooldown = enemy.template.fireCooldown
  table.insert(self.enemyBullets, {
    x = enemy.x + dx * (enemy.radius + 4),
    y = enemy.y + dy * (enemy.radius + 4),
    vx = dx * enemy.template.bulletSpeed,
    vy = dy * enemy.template.bulletSpeed,
    radius = 4,
    damage = enemy.template.bulletDamage,
    life = 1.1,
  })
  audio.playSfx("sfx_pistol", { pitch = 0.7 + love.math.random() * 0.2, volume = 0.6 })
end

local function moveEnemyTowards(self, enemy, tx, ty, dt, speedMul)
  local dx, dy = util.normalize(tx - enemy.x, ty - enemy.y)
  if dx == 0 and dy == 0 then return false end
  enemy.angle = util.angleTo(dy, dx)
  local s = enemy.template.speed * (speedMul or 1) * (enemy.stagger > 0 and 0.35 or 1)
  moveActor(self, enemy, dx * s, dy * s, dt)
  return true
end

local function updateEnemy(self, enemy, dt)
  enemy.fireCooldown = math.max(0, enemy.fireCooldown - dt)
  enemy.stagger = math.max(0, enemy.stagger - dt)

  local p = self.player
  local sees, sightDist = canSee(self, enemy, p)
  local hears, hearDist = canHear(enemy, p, p.noise, self.alarm, p.crouching)

  -- 警戒值更新
  if sees then
    enemy.awareness = math.min(2.5, enemy.awareness + dt * 2.4 * enemy.template.awareness)
    enemy.investigateTarget = { x = p.x, y = p.y }
    enemy.alertTimer = 6
  elseif hears then
    enemy.awareness = math.min(1.6, enemy.awareness + dt * 1.0 * (1 + p.noise))
    enemy.investigateTarget = { x = p.x, y = p.y }
    enemy.alertTimer = math.max(enemy.alertTimer, 3.5)
  else
    enemy.alertTimer = math.max(0, enemy.alertTimer - dt)
    if enemy.alertTimer <= 0 then
      enemy.awareness = math.max(0, enemy.awareness - dt * 0.55)
    end
  end

  -- 警報擴散：任何敵人達到 2 就把全關卡警戒值推到 1
  if enemy.awareness >= 2 then
    self.alarm = math.max(self.alarm, 1)
  end

  -- 行為決策
  if enemy.awareness >= 2 and sees and sightDist < enemy.sightRange * 0.85 then
    -- 戰鬥：保持距離並射擊
    local desired = enemy.template.fireCooldown < 1.5 and 220 or 280
    if sightDist > desired + 30 then
      moveEnemyTowards(self, enemy, p.x, p.y, dt, enemy.template.chaseSpeed)
    elseif sightDist < desired - 40 then
      moveEnemyTowards(self, enemy, enemy.x * 2 - p.x, enemy.y * 2 - p.y, dt, enemy.template.chaseSpeed * 0.6)
    else
      enemy.angle = util.angleTo(p.y - enemy.y, p.x - enemy.x)
    end
    if enemy.fireCooldown <= 0 and sightDist < enemy.sightRange then
      enemyShoot(self, enemy)
    end
  elseif enemy.awareness >= 1 and enemy.investigateTarget then
    -- 警戒：衝向最後已知位置
    local d = dist(enemy.x, enemy.y, enemy.investigateTarget.x, enemy.investigateTarget.y)
    if d > 24 then
      moveEnemyTowards(self, enemy, enemy.investigateTarget.x, enemy.investigateTarget.y, dt, enemy.template.chaseSpeed * 0.85)
    else
      enemy.investigateTarget = nil
    end
  else
    -- 巡邏
    local target = enemy.patrol[enemy.patrolIdx]
    if not target then
      target = { x = enemy.x, y = enemy.y }
    end
    if enemy.waitTimer > 0 then
      enemy.waitTimer = enemy.waitTimer - dt
    else
      local d = dist(enemy.x, enemy.y, target.x, target.y)
      if d < 18 then
        enemy.patrolIdx = (enemy.patrolIdx % #enemy.patrol) + 1
        enemy.waitTimer = 0.6 + love.math.random() * 0.6
      else
        moveEnemyTowards(self, enemy, target.x, target.y, dt, enemy.template.patrolSpeed)
      end
    end
  end

  -- 近身傷害
  local d = dist(enemy.x, enemy.y, p.x, p.y)
  if d < enemy.radius + p.radius + 4 and enemy.fireCooldown <= 0.2 then
    damagePlayer(self, enemy.damage)
    enemy.fireCooldown = 0.7
    newParticle(self, p.x, p.y, { 1, 0.25, 0.2 }, 8, 0.35)
    audio.playSfx("sfx_hit")
  end
end

-- ---------------------------------------------------------------------------
-- 援軍 / 子彈 / 粒子
-- ---------------------------------------------------------------------------

local function spawnReinforcement(self)
  if self.alarm < 1 then return end
  local edges = {
    { x = 80, y = 80 },
    { x = self.level.world.w - 80, y = 80 },
    { x = self.level.world.w - 80, y = self.level.world.h - 80 },
    { x = 80, y = self.level.world.h - 80 },
  }
  local pt = edges[love.math.random(#edges)]
  local kinds = { "raider", "drone", "raider", "guard" }
  local kind = kinds[love.math.random(#kinds)]
  local enemy = newEnemy({
    kind = kind,
    patrol = { { x = pt.x, y = pt.y }, { x = self.player.x, y = self.player.y } },
    sightRange = 220,
    sightAngle = math.rad(70),
    hearingRange = 140,
  })
  enemy.x = pt.x; enemy.y = pt.y
  enemy.awareness = 1.2
  enemy.alertTimer = 6
  enemy.investigateTarget = { x = self.player.x, y = self.player.y }
  table.insert(self.enemies, enemy)
end

local function updateBullets(self, dt)
  for i = #self.bullets, 1, -1 do
    local b = self.bullets[i]
    b.x = b.x + b.vx * dt
    b.y = b.y + b.vy * dt
    b.life = b.life - dt
    local hit = false
    for j = #self.enemies, 1, -1 do
      local e = self.enemies[j]
      if dist(b.x, b.y, e.x, e.y) < b.radius + e.radius then
        e.hp = e.hp - b.damage
        e.stagger = 0.18
        e.awareness = math.max(e.awareness, 2)
        e.alertTimer = 8
        e.investigateTarget = { x = self.player.x, y = self.player.y }
        self.alarm = math.max(self.alarm, 1)
        hit = true
        for _ = 1, 5 do
          newParticle(self, e.x, e.y, { 0.85, 0.12, 0.12 }, 4, 0.38)
        end
        if e.hp <= 0 then
          self.player.kills = self.player.kills + 1
          self.player.loot = self.player.loot + e.value
          audio.playSfx("sfx_enemy_die")
          for _ = 1, 14 do
            newParticle(self, e.x, e.y, { 0.95, 0.68, 0.18 },
              love.math.random(2, 6), 0.72)
          end
          table.remove(self.enemies, j)
        else
          audio.playSfx("sfx_hit")
        end
        break
      end
    end
    if hit or b.life <= 0
      or isBlocked(self.level, b.x, b.y, b.radius) then
      table.remove(self.bullets, i)
    end
  end
end

local function updateEnemyBullets(self, dt)
  for i = #self.enemyBullets, 1, -1 do
    local b = self.enemyBullets[i]
    b.x = b.x + b.vx * dt
    b.y = b.y + b.vy * dt
    b.life = b.life - dt
    local p = self.player
    if dist(b.x, b.y, p.x, p.y) < b.radius + p.radius then
      damagePlayer(self, b.damage)
      table.remove(self.enemyBullets, i)
    elseif b.life <= 0 or isBlocked(self.level, b.x, b.y, b.radius) then
      table.remove(self.enemyBullets, i)
    end
  end
end

local function updateParticles(self, dt)
  for i = #self.particles, 1, -1 do
    local p = self.particles[i]
    p.life = p.life - dt
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    p.vx = p.vx * (1 - dt * 2.2)
    p.vy = p.vy * (1 - dt * 2.2)
    if p.life <= 0 then
      table.remove(self.particles, i)
    end
  end
end

local function updateCamera(self)
  local p = self.player
  local sx, sy = 0, 0
  if self.shake > 0 then
    sx = love.math.random(-self.shake, self.shake)
    sy = love.math.random(-self.shake, self.shake)
  end
  local screenW, screenH = love.graphics.getWidth(), love.graphics.getHeight()
  self.camera.x = clamp(p.x - screenW / 2 + sx, 0, self.level.world.w - screenW)
  self.camera.y = clamp(p.y - screenH / 2 + sy, 0, self.level.world.h - screenH)
end

-- ---------------------------------------------------------------------------
-- 場景 update / draw
-- ---------------------------------------------------------------------------

function Play:update(dt)
  if self.phase ~= "playing" then
    updateParticles(self, dt)
    return
  end

  -- 開啟背包/儲物箱面板時暫停（生存遊戲常見處理）
  if self.uiPanel then
    return
  end

  self.time = self.time + dt
  self.shake = math.max(0, self.shake - dt * 22)
  self.messageTimer = math.max(0, self.messageTimer - dt)

  -- 撤離估價即時刷新：把背包估價當作 p.loot，跟 lootGoal 比對
  self.player.loot = inventory.appraise(self.player.inventory)

  updatePlayer(self, dt)
  for _, e in ipairs(self.enemies) do
    updateEnemy(self, e, dt)
  end
  updateBullets(self, dt)
  updateEnemyBullets(self, dt)
  updateParticles(self, dt)
  updateCamera(self)

  -- 警報衰減：持續沒被看到，警報會慢慢降回 0
  local stillAlarmed = false
  for _, e in ipairs(self.enemies) do
    if e.awareness >= 1 then stillAlarmed = true; break end
  end
  if not stillAlarmed then
    self.alarm = math.max(0, self.alarm - dt * 0.25)
  end

  -- 援軍：警報 >=1 才會逐步追加
  self.spawnTimer = self.spawnTimer - dt
  if self.spawnTimer <= 0 and self.alarm >= 1 and #self.enemies < 9 then
    spawnReinforcement(self)
    self.spawnTimer = 12 - clamp(self.time / self.level.raidLength, 0, 1) * 5
    audio.playSfx("sfx_alarm", { volume = 0.5 })
  end

  if self.time >= self.level.raidLength then
    self.phase = "lost"
    postMessage(self, "時間耗盡，撤離路線關閉。", 99)
  end
end

local function drawGrid(self)
  local lvl = self.level
  setColor(lvl.ambience.bg)
  love.graphics.rectangle("fill", 0, 0, lvl.world.w, lvl.world.h)
  setColor(lvl.ambience.grid)
  for x = 0, lvl.world.w, 80 do
    love.graphics.line(x, 0, x, lvl.world.h)
  end
  for y = 0, lvl.world.h, 80 do
    love.graphics.line(0, y, lvl.world.w, y)
  end
  love.graphics.setColor(0.2, 0.2, 0.22)
  love.graphics.rectangle("line", 0, 0, lvl.world.w, lvl.world.h)
end

local function drawObstacles(self)
  for _, rect in ipairs(self.level.obstacles) do
    love.graphics.setColor(0.18, 0.18, 0.18)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 6, 6)
    love.graphics.setColor(0.32, 0.31, 0.28)
    love.graphics.rectangle("line", rect.x + 4, rect.y + 4, rect.w - 8, rect.h - 8, 4, 4)
    if rect.label then
      love.graphics.setColor(0.55, 0.55, 0.48)
      love.graphics.setFont(fonts.small)
      love.graphics.printf(rect.label, rect.x, rect.y + rect.h / 2 - 8, rect.w, "center")
    end
  end
end

local function drawCrates(self)
  for _, c in ipairs(self.crates) do
    local color = c.searched and { 0.18, 0.2, 0.18 }
      or (c.kind == "safe" and { 0.62, 0.46, 0.20 } or { 0.55, 0.42, 0.22 })
    setColor(color)
    love.graphics.rectangle("fill", c.x - 22, c.y - 18, 44, 36, 4, 4)
    love.graphics.setColor(0.13, 0.10, 0.06)
    love.graphics.rectangle("line", c.x - 22, c.y - 18, 44, 36, 4, 4)
    if c.searchProgress > 0 and not c.searched then
      love.graphics.setColor(0.96, 0.86, 0.38)
      love.graphics.arc("fill", c.x, c.y - 28, 11,
        -math.pi / 2, -math.pi / 2 + TAU * (c.searchProgress / 0.7))
    end
  end
end

local function drawStash(self)
  local s = self.stash
  if not s then return end
  -- 黑底金邊鐵箱：跟撤離點同調的顏色，讓玩家辨識
  setColor({ 0.10, 0.10, 0.12 })
  love.graphics.rectangle("fill", s.x - 30, s.y - 22, 60, 44, 6, 6)
  setColor({ 0.36, 0.92, 0.55 })
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", s.x - 30, s.y - 22, 60, 44, 6, 6)
  love.graphics.setLineWidth(1)
  setColor({ 0.36, 0.92, 0.55, 0.20 })
  love.graphics.circle("fill", s.x, s.y, s.radius)

  -- 玩家靠近時顯示按鍵提示
  local dx, dy = self.player.x - s.x, self.player.y - s.y
  if dx * dx + dy * dy <= s.radius * s.radius then
    love.graphics.setFont(fonts.small)
    setColor({ 0.96, 0.96, 0.96 })
    love.graphics.printf("按 [F] 開啟儲物箱", s.x - 80, s.y - 50, 160, "center")
  end
end

local function drawExtracts(self)
  local active = self.player.loot >= self.level.lootGoal
  for _, e in ipairs(self.level.extracts) do
    setColor(active and { 0.10, 0.55, 0.24, 0.42 } or { 0.22, 0.22, 0.22, 0.32 })
    love.graphics.rectangle("fill", e.x, e.y, e.w, e.h, 8, 8)
    setColor(active and { 0.26, 0.95, 0.43 } or { 0.45, 0.45, 0.45 })
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", e.x, e.y, e.w, e.h, 8, 8)
    love.graphics.setLineWidth(1)
    love.graphics.setFont(fonts.small)
    love.graphics.printf(e.label, e.x, e.y + e.h / 2 - 8, e.w, "center")
  end
end

local function drawPlayer(self)
  local p = self.player
  love.graphics.push()
  love.graphics.translate(p.x, p.y)
  love.graphics.rotate(p.angle)
  if p.crouching then
    love.graphics.scale(0.85, 0.85)
  end
  love.graphics.setColor(0.95, 0.74, 0.2)
  love.graphics.circle("fill", 0, 0, p.radius)
  love.graphics.setColor(0.18, 0.12, 0.04)
  love.graphics.circle("fill", 7, -6, 3)
  love.graphics.circle("fill", 7, 6, 3)
  love.graphics.setColor(0.26, 0.26, 0.22)
  love.graphics.rectangle("fill", 8, -4, 27, 8, 2, 2)
  love.graphics.setColor(0.97, 0.48, 0.16)
  love.graphics.polygon("fill", 17, 0, 28, -5, 28, 5)
  love.graphics.pop()

  -- 噪音指示圈
  if p.noise > 0.05 then
    love.graphics.setColor(0.95, 0.85, 0.32, 0.18 * p.noise)
    love.graphics.circle("line", p.x, p.y, 50 + p.noise * 70)
  end
end

local function drawPatrolPath(self, e)
  if not e.patrol or #e.patrol < 2 or e.awareness >= 1 then return end
  -- 巡邏路徑只在玩家能看到敵人本體時才顯示，否則就是洩漏資訊
  if not playerCanSee(self, e.x, e.y) then return end
  love.graphics.setColor(0.85, 0.78, 0.32, 0.18)
  love.graphics.setLineWidth(2)
  for i = 1, #e.patrol do
    local a = e.patrol[i]
    local b = e.patrol[(i % #e.patrol) + 1]
    love.graphics.line(a.x, a.y, b.x, b.y)
  end
  for _, pt in ipairs(e.patrol) do
    love.graphics.circle("fill", pt.x, pt.y, 4)
  end
  love.graphics.setLineWidth(1)
end

local function drawInvestigateMarker(self, e)
  if e.awareness >= 1 and e.investigateTarget then
    if not playerCanSee(self, e.x, e.y) then return end
    local pulse = 0.4 + 0.6 * math.sin(love.timer.getTime() * 5)
    love.graphics.setColor(1, 0.55, 0.18, 0.6 * pulse)
    love.graphics.circle("line", e.investigateTarget.x, e.investigateTarget.y, 16 + pulse * 8)
    love.graphics.setColor(1, 0.55, 0.18, 0.3)
    love.graphics.line(e.x, e.y, e.investigateTarget.x, e.investigateTarget.y)
  end
end

local function drawEnemies(self)
  for _, e in ipairs(self.enemies) do
    -- 玩家視野外的敵人完全不繪製，營造潛行緊張感。
    -- 例外：敵人正在戰鬥（awareness>=2）且距離不太遠時，仍顯示模糊的「危險指示」
    -- 提示玩家剛剛被誰打到 —— 但只用紅色閃爍輪廓，不畫本體。
    local seen = playerCanSee(self, e.x, e.y)
    if not seen then
      if e.awareness >= 2 and dist(self.player.x, self.player.y, e.x, e.y) < 720 then
        local pulse = 0.3 + 0.4 * math.sin(love.timer.getTime() * 8)
        love.graphics.setColor(1, 0.18, 0.18, pulse)
        love.graphics.circle("line", e.x, e.y, e.radius + 6)
      end
      goto continue_enemy
    end

    drawPatrolPath(self, e)
    drawInvestigateMarker(self, e)

    -- 視野錐
    local coneR = e.sightRange
    local half = e.sightAngle / 2
    local color
    if e.awareness >= 2 then
      color = { 0.95, 0.18, 0.18, 0.22 }
    elseif e.awareness >= 1 then
      color = { 0.95, 0.62, 0.18, 0.18 }
    else
      color = { 0.92, 0.84, 0.32, 0.10 }
    end
    setColor(color)
    local steps = 18
    local pts = { e.x, e.y }
    for i = 0, steps do
      local a = e.angle - half + (e.sightAngle * (i / steps))
      pts[#pts + 1] = e.x + math.cos(a) * coneR
      pts[#pts + 1] = e.y + math.sin(a) * coneR
    end
    love.graphics.polygon("fill", pts)

    setColor(e.color)
    love.graphics.circle("fill", e.x, e.y, e.radius)
    -- 眼睛：在黑暗中會發出微紅光，增加恐怖感
    local lightHere = lightAt(self, e.x, e.y)
    if lightHere < 0.2 then
      local glow = 0.7 + 0.3 * math.sin(love.timer.getTime() * 4.7)
      love.graphics.setColor(0.95, 0.18, 0.18, glow)
      love.graphics.circle("fill", e.x + 6, e.y - 5, 2.4)
      love.graphics.circle("fill", e.x + 6, e.y + 5, 2.4)
    else
      love.graphics.setColor(0.12, 0.05, 0.04)
      love.graphics.circle("fill", e.x + 5, e.y - 5, 3)
      love.graphics.circle("fill", e.x + 5, e.y + 5, 3)
    end

    -- 朝向
    love.graphics.setColor(0.95, 0.92, 0.78)
    love.graphics.line(e.x, e.y,
      e.x + math.cos(e.angle) * (e.radius + 6),
      e.y + math.sin(e.angle) * (e.radius + 6))

    -- 血條
    local bw = e.radius * 2
    love.graphics.setColor(0.15, 0.05, 0.05)
    love.graphics.rectangle("fill", e.x - e.radius, e.y - e.radius - 12, bw, 4)
    love.graphics.setColor(0.88, 0.18, 0.14)
    love.graphics.rectangle("fill", e.x - e.radius, e.y - e.radius - 12, bw * (e.hp / e.maxHp), 4)

    -- 警戒圖示
    if e.awareness >= 2 then
      love.graphics.setColor(1, 0.2, 0.2)
      love.graphics.setFont(fonts.medium)
      love.graphics.print("!!", e.x - 6, e.y - e.radius - 32)
    elseif e.awareness >= 1 then
      love.graphics.setColor(1, 0.8, 0.3)
      love.graphics.setFont(fonts.medium)
      love.graphics.print("?", e.x - 4, e.y - e.radius - 32)
    end

    ::continue_enemy::
  end
end

local function drawBulletsAndParticles(self)
  for _, b in ipairs(self.bullets) do
    love.graphics.setColor(1, 0.86, 0.38)
    love.graphics.circle("fill", b.x, b.y, b.radius)
  end
  for _, b in ipairs(self.enemyBullets) do
    love.graphics.setColor(1, 0.34, 0.30)
    love.graphics.circle("fill", b.x, b.y, b.radius)
  end
  for _, p in ipairs(self.particles) do
    local alpha = clamp(p.life / p.maxLife, 0, 1)
    love.graphics.setColor(p.color[1], p.color[2], p.color[3], alpha)
    love.graphics.circle("fill", p.x, p.y, p.size * alpha)
  end
end

local function drawLightsAndFog(self, screenW, screenH)
  -- 黑霧覆蓋整個世界，再用「lights」做減法（用 add blend 反向）
  -- fog 透明度依 stress 微幅加深，模擬「視野收窄」的恐怖感
  local fog = self.level.ambience.fog
  local stressTint = (self.player.stress / self.player.maxStress) * 0.18
  love.graphics.setColor(fog[1], fog[2], fog[3], math.min(0.92, fog[4] + stressTint))
  love.graphics.rectangle("fill",
    self.camera.x, self.camera.y, screenW, screenH)

  -- 燈光的呼吸：用時間 sin 微幅變化，加上偶發閃爍（紅燈、聖堂）
  local t = love.timer.getTime()
  love.graphics.setBlendMode("add")
  for i, lt in ipairs(self.lights) do
    local breath = 0.85 + 0.15 * math.sin(t * (1.4 + i * 0.07) + i)
    -- 第一夜紅燈會隨機閃爍
    if lt.color[1] > 0.7 and lt.color[2] < 0.4 then
      breath = breath * (0.7 + 0.3 * math.sin(t * 7 + i * 1.3))
    end
    love.graphics.setColor(lt.color[1] * 0.45, lt.color[2] * 0.45, lt.color[3] * 0.45, 0.55 * breath)
    love.graphics.circle("fill", lt.x, lt.y, lt.radius * (0.95 + 0.05 * math.sin(t * 2 + i)))
    love.graphics.setColor(lt.color[1], lt.color[2], lt.color[3], 0.10 * breath)
    love.graphics.circle("fill", lt.x, lt.y, lt.radius * 0.55)
  end
  love.graphics.setBlendMode("alpha")
end

local function drawBar(x, y, w, h, ratio, bg, fg, label)
  setColor(bg)
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)
  setColor(fg)
  love.graphics.rectangle("fill", x, y, w * clamp(ratio, 0, 1), h, 4, 4)
  love.graphics.setColor(0.93, 0.92, 0.82)
  love.graphics.setFont(fonts.small)
  love.graphics.print(label, x + 6, y + 3)
end

local function drawHud(self, screenW, screenH)
  local p = self.player
  love.graphics.origin()

  love.graphics.setColor(0.04, 0.05, 0.04, 0.82)
  love.graphics.rectangle("fill", 18, 18, 360, 162, 10, 10)
  drawBar(36, 36, 220, 18, p.hp / p.maxHp,
    { 0.17, 0.04, 0.04 }, { 0.8, 0.16, 0.12 }, ("HP %d/%d"):format(p.hp, p.maxHp))
  drawBar(36, 62, 220, 16, p.armor / p.maxArmor,
    { 0.06, 0.08, 0.11 }, { 0.24, 0.45, 0.78 }, ("ARMOR %d"):format(p.armor))
  drawBar(36, 86, 220, 14, p.stamina / p.maxStamina,
    { 0.09, 0.09, 0.03 }, { 0.83, 0.77, 0.25 }, "STAMINA")
  do
    local arrow = ""
    if p.stressDelta and p.stressDelta < -0.2 then arrow = " ↓"
    elseif p.stressDelta and p.stressDelta > 0.2 then arrow = " ↑" end
    drawBar(36, 108, 220, 14, p.stress / p.maxStress,
      { 0.08, 0.04, 0.10 }, { 0.62, 0.20, 0.86 },
      ("STRESS %d%s  LIGHT %d%%"):format(p.stress, arrow, math.floor(p.lightLevel * 100)))
  end

  love.graphics.setFont(fonts.medium)
  love.graphics.setColor(0.96, 0.92, 0.72)
  love.graphics.print(("AMMO %02d/%02d"):format(p.ammo, p.maxAmmo), 272, 36)
  local medCount = inventory.countOf(p.inventory, "medkit") + inventory.countOf(p.inventory, "bandage")
  love.graphics.print(("MED %d"):format(medCount), 272, 62)
  love.graphics.print(("KILLS %d"):format(p.kills), 272, 88)
  love.graphics.print(("LOOT $%d / $%d"):format(p.loot, self.level.lootGoal), 36, 142)
  -- 背包重量
  local w = inventory.weight(p.inventory)
  love.graphics.setColor(0.78, 0.82, 0.86)
  love.graphics.print(("BAG %.1f / %d kg  [TAB]"):format(w, p.inventory.weightLimit), 36, 162)

  -- 計時器與警戒
  local remaining = math.max(0, self.level.raidLength - self.time)
  love.graphics.setColor(0.04, 0.05, 0.04, 0.82)
  love.graphics.rectangle("fill", screenW - 242, 18, 224, 92, 10, 10)
  love.graphics.setColor(0.96, 0.92, 0.72)
  love.graphics.setFont(fonts.large)
  love.graphics.printf(("%02d:%02d"):format(math.floor(remaining / 60), math.floor(remaining % 60)),
    screenW - 224, 28, 190, "center")
  love.graphics.setFont(fonts.small)
  love.graphics.printf("RAID TIMER", screenW - 224, 62, 190, "center")
  if self.alarm >= 1 then
    love.graphics.setColor(1, 0.18, 0.18, 0.6 + 0.4 * math.sin(love.timer.getTime() * 6))
    love.graphics.printf("[ ALARM ]", screenW - 224, 82, 190, "center")
  else
    love.graphics.setColor(0.5, 0.55, 0.45)
    love.graphics.printf("[ STEALTH ]", screenW - 224, 82, 190, "center")
  end

  -- 訊息
  if self.messageTimer > 0 then
    love.graphics.setColor(0.05, 0.06, 0.05, 0.78)
    love.graphics.rectangle("fill", screenW / 2 - 320, 24, 640, 42, 10, 10)
    love.graphics.setColor(0.96, 0.9, 0.63)
    love.graphics.setFont(fonts.medium)
    love.graphics.printf(self.message, screenW / 2 - 300, 36, 600, "center")
  end

  -- 互動提示
  if p.interactTarget then
    local text = "按住 E 搜尋"
    if p.interactTarget.type == "extract" then
      text = ("按住 E 撤離 %.0f%%"):format((p.extracting / 2.4) * 100)
    end
    love.graphics.setColor(0.04, 0.05, 0.04, 0.86)
    love.graphics.rectangle("fill", screenW / 2 - 150, screenH - 92, 300, 42, 10, 10)
    love.graphics.setColor(0.88, 0.96, 0.72)
    love.graphics.setFont(fonts.medium)
    love.graphics.printf(text, screenW / 2 - 140, screenH - 80, 280, "center")
  elseif p.loot < self.level.lootGoal then
    love.graphics.setColor(0.04, 0.05, 0.04, 0.64)
    love.graphics.rectangle("fill", screenW / 2 - 240, screenH - 72, 480, 34, 8, 8)
    love.graphics.setColor(0.74, 0.79, 0.67)
    love.graphics.setFont(fonts.small)
    love.graphics.printf(("搜刮 $%d 後，綠色撤離區才會啟動。"):format(self.level.lootGoal),
      screenW / 2 - 230, screenH - 61, 460, "center")
  end

  -- 受傷紅閃 / 壓力暗角
  if p.hurtFlash > 0 then
    love.graphics.setColor(1, 0.1, 0.1, 0.25 * p.hurtFlash)
    love.graphics.rectangle("fill", 0, 0, screenW, screenH)
  end

  local stressRatio = p.stress / p.maxStress
  local hpRatio = 1 - p.hp / p.maxHp
  -- 用一個漸層暗角：以螢幕中心為亮點、四角為暗角，stress / 低血量 加深
  local vignetteAlpha = math.max(stressRatio * 0.5, hpRatio * 0.55)
  if vignetteAlpha > 0.05 then
    local layers = 6
    for i = 1, layers do
      local t = i / layers
      local alpha = vignetteAlpha * t * 0.18
      love.graphics.setColor(0.55, 0.04, 0.20, alpha)
      love.graphics.rectangle("fill", 0, 0, screenW, screenH * 0.04 * t)
      love.graphics.rectangle("fill", 0, screenH * (1 - 0.04 * t), screenW, screenH * 0.04 * t)
      love.graphics.rectangle("fill", 0, 0, screenW * 0.04 * t, screenH)
      love.graphics.rectangle("fill", screenW * (1 - 0.04 * t), 0, screenW * 0.04 * t, screenH)
    end
  end
  if stressRatio > 0.3 then
    love.graphics.setColor(0.4, 0.06, 0.62, 0.18 * (stressRatio - 0.3))
    love.graphics.rectangle("fill", 0, 0, screenW, screenH)
  end

  -- 蹲伏指示
  if p.crouching then
    love.graphics.setColor(0.55, 0.95, 0.65)
    love.graphics.setFont(fonts.small)
    love.graphics.print("[ CROUCH ]", 36, screenH - 30)
  end

  -- 迷你地圖（右下角，幫助玩家在潛行時規劃路徑）
  local mapW, mapH = 220, 150
  local mapX, mapY = screenW - mapW - 22, screenH - mapH - 22
  love.graphics.setColor(0.04, 0.05, 0.05, 0.78)
  love.graphics.rectangle("fill", mapX - 4, mapY - 4, mapW + 8, mapH + 8, 6, 6)
  love.graphics.setColor(0.22, 0.24, 0.20)
  love.graphics.rectangle("line", mapX - 4, mapY - 4, mapW + 8, mapH + 8, 6, 6)

  local lvl = self.level
  local sx = mapW / lvl.world.w
  local sy = mapH / lvl.world.h
  -- 障礙
  love.graphics.setColor(0.28, 0.28, 0.26)
  for _, r in ipairs(lvl.obstacles) do
    love.graphics.rectangle("fill", mapX + r.x * sx, mapY + r.y * sy, r.w * sx, r.h * sy)
  end
  -- 撤離
  local active = p.loot >= lvl.lootGoal
  for _, e in ipairs(lvl.extracts) do
    love.graphics.setColor(active and { 0.26, 0.95, 0.43 } or { 0.42, 0.42, 0.42 })
    love.graphics.rectangle("fill", mapX + e.x * sx, mapY + e.y * sy, e.w * sx, e.h * sy)
  end
  -- 戰利品
  for _, c in ipairs(self.crates) do
    if not c.searched then
      love.graphics.setColor(0.96, 0.78, 0.30)
      love.graphics.circle("fill", mapX + c.x * sx, mapY + c.y * sy, 2)
    end
  end
  -- 敵人
  for _, e in ipairs(self.enemies) do
    if e.awareness >= 2 then
      love.graphics.setColor(1, 0.18, 0.18)
    elseif e.awareness >= 1 then
      love.graphics.setColor(1, 0.65, 0.18)
    else
      love.graphics.setColor(0.85, 0.40, 0.30)
    end
    love.graphics.circle("fill", mapX + e.x * sx, mapY + e.y * sy, 3)
  end
  -- 玩家
  love.graphics.setColor(0.95, 0.92, 0.30)
  love.graphics.circle("fill", mapX + p.x * sx, mapY + p.y * sy, 3.5)

  love.graphics.setFont(fonts.small)
  love.graphics.setColor(0.7, 0.68, 0.55)
  love.graphics.print(("M"):format(), mapX + mapW - 14, mapY + 2)
end

-- 背包 / 儲物箱面板 ----------------------------------------------------------
local function drawInvList(inv, x, y, w, h, cursor, active, title)
  love.graphics.setColor(0.04, 0.05, 0.06, 0.92)
  love.graphics.rectangle("fill", x, y, w, h, 8, 8)
  love.graphics.setColor(active and 0.96 or 0.45, active and 0.92 or 0.42, active and 0.52 or 0.40)
  love.graphics.setLineWidth(active and 3 or 1)
  love.graphics.rectangle("line", x, y, w, h, 8, 8)
  love.graphics.setLineWidth(1)

  love.graphics.setFont(fonts.medium)
  love.graphics.setColor(0.96, 0.92, 0.72)
  love.graphics.print(title, x + 12, y + 8)
  love.graphics.setFont(fonts.small)
  love.graphics.setColor(0.78, 0.82, 0.86)
  local w_ = inventory.weight(inv)
  love.graphics.printf(("%.1f / %d kg"):format(w_, inv.weightLimit),
    x + 12, y + 8, w - 24, "right")

  love.graphics.setFont(fonts.small)
  if #inv.stacks == 0 then
    love.graphics.setColor(0.55, 0.55, 0.55)
    love.graphics.printf("（空）", x, y + h / 2 - 8, w, "center")
    return
  end
  for i, s in ipairs(inv.stacks) do
    local def = items.def(s.id)
    local row = y + 36 + (i - 1) * 22
    if active and i == cursor then
      love.graphics.setColor(0.36, 0.92, 0.55, 0.18)
      love.graphics.rectangle("fill", x + 6, row - 2, w - 12, 22, 4, 4)
    end
    if def and def.color then love.graphics.setColor(def.color) else love.graphics.setColor(0.86, 0.86, 0.86) end
    love.graphics.rectangle("fill", x + 12, row + 4, 12, 12, 2, 2)
    love.graphics.setColor(0.96, 0.94, 0.84)
    love.graphics.print(def and def.name or s.id, x + 32, row + 2)
    love.graphics.setColor(0.78, 0.82, 0.86)
    love.graphics.printf(("×%d"):format(s.count), x, row + 2, w - 60, "right")
    love.graphics.printf(("%.1fkg"):format((def and def.weight or 0) * s.count),
      x, row + 2, w - 12, "right")
  end
end

local function drawPanel(self, screenW, screenH)
  love.graphics.origin()
  love.graphics.setColor(0, 0, 0, 0.62)
  love.graphics.rectangle("fill", 0, 0, screenW, screenH)

  local panelW = 720
  local panelH = 460
  local x = (screenW - panelW) / 2
  local y = (screenH - panelH) / 2
  love.graphics.setColor(0.08, 0.07, 0.10, 0.94)
  love.graphics.rectangle("fill", x, y, panelW, panelH, 12, 12)
  love.graphics.setColor(0.36, 0.92, 0.55)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x, y, panelW, panelH, 12, 12)
  love.graphics.setLineWidth(1)

  love.graphics.setFont(fonts.large)
  love.graphics.setColor(0.96, 0.92, 0.72)
  if self.uiPanel == "stash" then
    love.graphics.printf("儲物箱  ←/→ 切換  SPACE 移動  TAB 關閉",
      x, y + 14, panelW, "center")
    drawInvList(self.player.inventory, x + 24, y + 56, (panelW - 72) / 2, panelH - 80,
      self.uiCursor, self.uiSide == "player", "背包（玩家）")
    drawInvList(self.stash.inventory, x + 24 + (panelW - 72) / 2 + 24, y + 56,
      (panelW - 72) / 2, panelH - 80,
      self.uiCursor, self.uiSide == "stash", "儲物箱")
  else
    love.graphics.printf("背包  ←/→ 切換頁  Enter 使用  TAB 關閉",
      x, y + 14, panelW, "center")
    -- tab 列
    love.graphics.setFont(fonts.medium)
    local tx1, tx2 = x + 32, x + 152
    love.graphics.setColor(self.uiTab == "items" and 0.96 or 0.40,
      self.uiTab == "items" and 0.92 or 0.40, 0.52)
    love.graphics.print("[ 物品 ]", tx1, y + 50)
    love.graphics.setColor(self.uiTab == "craft" and 0.96 or 0.40,
      self.uiTab == "craft" and 0.92 or 0.40, 0.52)
    love.graphics.print("[ 合成 ]", tx2, y + 50)

    if self.uiTab == "items" then
      drawInvList(self.player.inventory, x + 24, y + 80, panelW - 280, panelH - 110,
        self.uiCursor, true, "背包")
      -- 右側：選中物品說明
      local s = self.player.inventory.stacks[self.uiCursor]
      local def = s and items.def(s.id)
      love.graphics.setFont(fonts.medium)
      love.graphics.setColor(0.96, 0.92, 0.72)
      local rx = x + panelW - 244
      local ry = y + 80
      love.graphics.print(def and def.name or "—", rx, ry)
      love.graphics.setFont(fonts.small)
      love.graphics.setColor(0.78, 0.82, 0.86)
      if def then
        love.graphics.printf(("重量 %.2fkg / 估價 $%d"):format(def.weight, def.value),
          rx, ry + 28, 220, "left")
        love.graphics.printf(def.description or "", rx, ry + 56, 220, "left")
      else
        love.graphics.printf("選擇背包中的物品。", rx, ry + 28, 220, "left")
      end
    else
      -- 合成列表
      local cx = x + 32
      local cy = y + 86
      local cw = panelW - 64
      love.graphics.setFont(fonts.small)
      for i, r in ipairs(items.recipes()) do
        local row = cy + (i - 1) * 30
        if i == self.uiCraftCursor then
          love.graphics.setColor(0.36, 0.92, 0.55, 0.18)
          love.graphics.rectangle("fill", cx, row - 2, cw, 26, 4, 4)
        end
        love.graphics.setColor(0.96, 0.94, 0.84)
        love.graphics.print(r.name, cx + 8, row + 2)
        local can = true
        for _, inp in ipairs(r.inputs) do
          if inventory.countOf(self.player.inventory, inp.id) < inp.count then can = false end
        end
        love.graphics.setColor(can and 0.36 or 0.55, can and 0.92 or 0.30, can and 0.55 or 0.30)
        love.graphics.printf(can and "✓ 可合成" or "✗ 材料不足",
          cx, row + 2, cw - 12, "right")
      end
      love.graphics.setFont(fonts.small)
      love.graphics.setColor(0.78, 0.82, 0.86)
      love.graphics.printf("Enter 合成", cx, y + panelH - 36, cw, "right")
    end
  end
end

local function drawEndScreen(self, screenW, screenH)
  if self.phase == "playing" then return end
  love.graphics.origin()
  love.graphics.setColor(0, 0, 0, 0.72)
  love.graphics.rectangle("fill", 0, 0, screenW, screenH)
  love.graphics.setFont(fonts.huge)
  if self.phase == "won" then
    love.graphics.setColor(0.76, 1, 0.48)
    love.graphics.printf("撤離成功", 0, 220, screenW, "center")
  else
    love.graphics.setColor(1, 0.38, 0.32)
    love.graphics.printf("撤離失敗", 0, 220, screenW, "center")
  end
  love.graphics.setColor(0.96, 0.92, 0.72)
  love.graphics.setFont(fonts.large)
  love.graphics.printf(("帶出物資 $%d   擊倒 %d"):format(self.player.loot, self.player.kills),
    0, 296, screenW, "center")
  love.graphics.setFont(fonts.medium)
  love.graphics.printf("R 重新開始本關，B 回主選單，Esc 離開。",
    0, 360, screenW, "center")
end

-- 玩家視野遮罩：螢幕上不在視野扇形 / 周圍圈內的區域加一層黑霧，
-- 強化潛行緊張感（看不到的地方就是看不到）。
local function drawVisionFog(self, screenW, screenH)
  local p = self.player
  local steps = 40
  local half = p.visionAngle / 2
  -- 扇形多邊形頂點（世界座標）
  local cone = { p.x, p.y }
  for i = 0, steps do
    local a = p.angle - half + (p.visionAngle * (i / steps))
    cone[#cone + 1] = p.x + math.cos(a) * p.visionRange
    cone[#cone + 1] = p.y + math.sin(a) * p.visionRange
  end

  local function maskFn()
    love.graphics.polygon("fill", cone)
    love.graphics.circle("fill", p.x, p.y, p.proximityRange)
  end

  -- stencil 為 0 的地方（視野外）才繪製黑霧
  love.graphics.stencil(maskFn, "replace", 1)
  love.graphics.setStencilTest("equal", 0)
  love.graphics.setColor(0, 0, 0, 0.62)
  love.graphics.rectangle("fill",
    self.camera.x - 4, self.camera.y - 4, screenW + 8, screenH + 8)
  love.graphics.setStencilTest()

  -- 視野邊緣：再畫一條淡色邊讓玩家清楚看到視野範圍
  love.graphics.setColor(0.95, 0.85, 0.30, 0.10)
  love.graphics.setLineWidth(1)
  love.graphics.polygon("line", cone)
  love.graphics.circle("line", p.x, p.y, p.proximityRange)
end

function Play:draw(screenW, screenH)
  love.graphics.push()
  love.graphics.translate(-self.camera.x, -self.camera.y)
  drawGrid(self)
  drawExtracts(self)
  drawObstacles(self)
  drawCrates(self)
  drawStash(self)
  drawBulletsAndParticles(self)
  drawEnemies(self)
  drawPlayer(self)
  drawLightsAndFog(self, screenW, screenH)
  drawVisionFog(self, screenW, screenH)
  love.graphics.pop()
  drawHud(self, screenW, screenH)
  if self.uiPanel then drawPanel(self, screenW, screenH) end
  drawEndScreen(self, screenW, screenH)
end

-- panel 內按鍵 ----------------------------------------------------------------
local function activeInv(self)
  if self.uiPanel == "stash" and self.uiSide == "stash" then
    return self.stash.inventory
  end
  return self.player.inventory
end

local function passiveInv(self)
  if self.uiPanel == "stash" then
    if self.uiSide == "stash" then return self.player.inventory end
    return self.stash.inventory
  end
  return nil
end

local function panelKey(self, key)
  local inv = activeInv(self)
  if key == "escape" or key == "tab" or key == "f" then
    self.uiPanel = nil
    return
  end
  if self.uiPanel == "stash" and (key == "left" or key == "right") then
    self.uiSide = (self.uiSide == "player") and "stash" or "player"
    self.uiCursor = 1
    return
  end
  if self.uiPanel == "inventory" and (key == "left" or key == "right") then
    self.uiTab = (self.uiTab == "items") and "craft" or "items"
    self.uiCursor = 1; self.uiCraftCursor = 1
    return
  end

  if self.uiPanel == "inventory" and self.uiTab == "craft" then
    local recipes = items.recipes()
    if key == "up" then
      self.uiCraftCursor = math.max(1, self.uiCraftCursor - 1)
    elseif key == "down" then
      self.uiCraftCursor = math.min(#recipes, self.uiCraftCursor + 1)
    elseif key == "return" or key == "kpenter" or key == "space" then
      local r = recipes[self.uiCraftCursor]
      if r then
        local ok, msg = inventory.craft(self.player.inventory, r)
        postMessage(self, msg, 2.0)
        if ok then audio.playSfx("sfx_pickup", { pitch = 0.9 }) end
      end
    end
    return
  end

  -- items tab / stash 共用
  local n = #inv.stacks
  if n == 0 then
    if key == "up" or key == "down" or key == "return" then return end
  end
  if key == "up" then
    self.uiCursor = math.max(1, self.uiCursor - 1)
  elseif key == "down" then
    self.uiCursor = math.min(math.max(1, n), self.uiCursor + 1)
  elseif key == "return" or key == "kpenter" then
    -- inventory 模式：使用該物品
    if self.uiPanel == "inventory" then
      local ok = inventory.useStack(inv, self.uiCursor, self.player)
      if not ok then
        postMessage(self, "這個物品無法直接使用。", 1.2)
      else
        if self.uiCursor > #inv.stacks then self.uiCursor = math.max(1, #inv.stacks) end
      end
    end
  elseif key == "space" then
    -- stash 模式：把整 stack 搬去另一邊
    if self.uiPanel == "stash" then
      local dst = passiveInv(self)
      if dst then
        local moved = inventory.moveStack(inv, self.uiCursor, dst)
        if moved == 0 then
          postMessage(self, "對面背包塞不下了。", 1.2)
        else
          if self.uiCursor > #inv.stacks then self.uiCursor = math.max(1, #inv.stacks) end
        end
      end
    end
  end
end

local function nearStash(self)
  local p, s = self.player, self.stash
  if not s then return false end
  local dx, dy = p.x - s.x, p.y - s.y
  return (dx * dx + dy * dy) <= (s.radius * s.radius)
end

function Play:keypressed(key, scenes)
  -- panel 開啟時，所有按鍵都交給 panel 處理
  if self.uiPanel then
    panelKey(self, key)
    return
  end

  if key == "q" then
    useMedkit(self)
  elseif key == "x" then
    usePill(self)
  elseif key == "g" then
    craftFirstAvailable(self, "craft_medkit")
  elseif key == "tab" then
    self.uiPanel = "inventory"
    self.uiTab = "items"
    self.uiCursor = 1
  elseif key == "f" and nearStash(self) then
    self.uiPanel = "stash"
    self.uiSide = "player"
    self.uiCursor = 1
  elseif key == "r" and self.phase ~= "playing" then
    scenes.start(self.levelIndex)
  elseif key == "b" and self.phase ~= "playing" then
    scenes.menu()
  elseif key == "n" and self.phase == "won" then
    if self.levelIndex < levels.count() then
      scenes.start(self.levelIndex + 1)
    else
      scenes.menu()
    end
  elseif key == "m" then
    audio.toggleMute()
  end
end

return Play
