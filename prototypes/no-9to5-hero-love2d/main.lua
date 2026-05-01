local game = {}

local W, H = 960, 540
local world = { w = 2200, h = 1600 }

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

local function dist2(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy
end

local function normalize(x, y)
  local length = math.sqrt(x * x + y * y)
  if length == 0 then
    return 0, 0
  end
  return x / length, y / length
end

local function formatTime(seconds)
  local minutes = math.floor(seconds / 60)
  local secs = math.floor(seconds % 60)
  return string.format("%02d:%02d", minutes, secs)
end

-- Love2D 預設字型不含中文；依序嘗試 macOS 系統字型（並保留專案內 fonts/ 後備）。
local FONT_PATHS = {
  -- 專案內 fonts/：Google Fonts 下載多為 .ttf；建議用 static/NotoSansTC-Regular.ttf，相容性優於 Variable Font
  "fonts/NotoSansTC-Regular.ttf",
  "fonts/NotoSansTC-Regular.otf",
  "fonts/NotoSansTC-VariableFont_wght.ttf",
  "fonts/NotoSansCJKtc-Regular.otf",
  "/System/Library/Fonts/PingFang.ttc",
  "/System/Library/Fonts/STHeiti Medium.ttc",
  "/System/Library/Fonts/STHeiti Light.ttc",
  "/System/Library/Fonts/Supplemental/Songti.ttc",
  "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"
}

local function tryLoadFont(path, size)
  local ok, font = pcall(love.graphics.newFont, path, size)
  if ok and font then
    font:setFilter("linear", "linear")
    return font
  end
end

local function loadCJKFonts()
  game.fontWorld = nil
  game.fontUi = nil
  game.fontTitle = nil

  for _, path in ipairs(FONT_PATHS) do
    local fWorld = tryLoadFont(path, 14)
    local fUi = tryLoadFont(path, 16)
    local fTitle = tryLoadFont(path, 24)
    if fWorld and fUi and fTitle then
      game.fontWorld = fWorld
      game.fontUi = fUi
      game.fontTitle = fTitle
      break
    end
  end

  if not game.fontUi then
    game.fontWorld = love.graphics.newFont(14)
    game.fontUi = love.graphics.newFont(16)
    game.fontTitle = love.graphics.newFont(24)
    game.fontWorld:setFilter("linear", "linear")
    game.fontUi:setFilter("linear", "linear")
    game.fontTitle:setFilter("linear", "linear")
  end
end

local function resetGame()
  game.state = "playing"
  game.time = 0
  game.spawnTimer = 0
  game.upgradeChoices = {}
  game.messageTimer = 4
  game.camera = { x = 0, y = 0 }

  game.player = {
    x = world.w / 2,
    y = world.h / 2,
    r = 15,
    hp = 100,
    maxHp = 100,
    speed = 210,
    level = 1,
    xp = 0,
    xpNext = 8,
    invuln = 0,
    fireTimer = 0,
    fireRate = 0.72,
    bulletDamage = 18,
    bulletSpeed = 560,
    pickupRange = 72,
    magnet = 1,
    projectiles = 1,
    score = 0
  }

  game.enemies = {}
  game.bullets = {}
  game.gems = {}
  game.floaters = {}
end

local upgrades = {
  {
    title = "輕功·燕子抄水",
    desc = "身法輕靈，步履迅捷（移動 +12%）",
    apply = function(p)
      p.speed = p.speed * 1.12
    end
  },
  {
    title = "內勁·破甲罡風",
    desc = "掌勁更沉，破敵於數丈之外（傷害 +7）",
    apply = function(p)
      p.bulletDamage = p.bulletDamage + 7
    end
  },
  {
    title = "連環·行雲流水",
    desc = "招式相接不暇，間不容髮（出招更快 -12%）",
    apply = function(p)
      p.fireRate = p.fireRate * 0.88
    end
  },
  {
    title = "劍意·一念三生",
    desc = "勁氣分化，一式多出一路暗襲（多一招）",
    apply = function(p)
      p.projectiles = p.projectiles + 1
    end
  },
  {
    title = "氣場·乾坤接引",
    desc = "真氣外放，遠近皆可吸納（拾取範圍 +45%）",
    apply = function(p)
      p.pickupRange = p.pickupRange * 1.45
      p.magnet = p.magnet + 0.45
    end
  },
  {
    title = "洗髓·固本培元",
    desc = "經脈疏浚，氣血充盈（上限 +20，並回復 20）",
    apply = function(p)
      p.maxHp = p.maxHp + 20
      p.hp = math.min(p.maxHp, p.hp + 20)
    end
  }
}

local function addFloater(text, x, y, color)
  table.insert(game.floaters, {
    text = text,
    x = x,
    y = y,
    vy = -28,
    life = 0.9,
    maxLife = 0.9,
    color = color or { 1, 1, 1 }
  })
end

local function chooseUpgrades()
  game.upgradeChoices = {}
  local bag = {}
  for i = 1, #upgrades do
    bag[i] = i
  end

  for _ = 1, 3 do
    if #bag == 0 then
      break
    end
    local pick = love.math.random(#bag)
    table.insert(game.upgradeChoices, upgrades[bag[pick]])
    table.remove(bag, pick)
  end

  game.state = "levelup"
end

local function gainXp(amount)
  local p = game.player
  p.xp = p.xp + amount

  while p.xp >= p.xpNext do
    p.xp = p.xp - p.xpNext
    p.level = p.level + 1
    p.xpNext = math.floor(p.xpNext * 1.25 + 5)
    chooseUpgrades()
    break
  end
end

local function spawnEnemy()
  local p = game.player
  local side = love.math.random(4)
  local margin = 80
  local x, y

  if side == 1 then
    x = p.x + love.math.random(-W / 2, W / 2)
    y = p.y - H / 2 - margin
  elseif side == 2 then
    x = p.x + love.math.random(-W / 2, W / 2)
    y = p.y + H / 2 + margin
  elseif side == 3 then
    x = p.x - W / 2 - margin
    y = p.y + love.math.random(-H / 2, H / 2)
  else
    x = p.x + W / 2 + margin
    y = p.y + love.math.random(-H / 2, H / 2)
  end

  x = clamp(x, 30, world.w - 30)
  y = clamp(y, 30, world.h - 30)

  local minutes = game.time / 60
  local elite = love.math.random() < clamp(0.04 + minutes * 0.02, 0.04, 0.18)
  local hp = elite and (70 + minutes * 18) or (28 + minutes * 9)

  table.insert(game.enemies, {
    x = x,
    y = y,
    r = elite and 20 or 13,
    hp = hp,
    maxHp = hp,
    speed = elite and (60 + minutes * 4) or (92 + minutes * 6),
    damage = elite and 18 or 10,
    xp = elite and 5 or 2,
    elite = elite
  })
end

local function nearestEnemy()
  local p = game.player
  local best, bestD2 = nil, math.huge

  for _, enemy in ipairs(game.enemies) do
    local d = dist2(p.x, p.y, enemy.x, enemy.y)
    if d < bestD2 then
      best = enemy
      bestD2 = d
    end
  end

  return best
end

local function fireBullets()
  local p = game.player
  local target = nearestEnemy()
  if not target then
    return
  end

  local baseAngle = math.atan2(target.y - p.y, target.x - p.x)
  local spread = math.rad(13)
  local count = p.projectiles

  for i = 1, count do
    local offset = (i - (count + 1) / 2) * spread
    local angle = baseAngle + offset
    table.insert(game.bullets, {
      x = p.x,
      y = p.y,
      r = 5,
      dx = math.cos(angle),
      dy = math.sin(angle),
      speed = p.bulletSpeed,
      damage = p.bulletDamage,
      life = 1.15
    })
  end
end

local function updatePlayer(dt)
  local p = game.player
  local mx, my = 0, 0

  if love.keyboard.isDown("a", "left") then mx = mx - 1 end
  if love.keyboard.isDown("d", "right") then mx = mx + 1 end
  if love.keyboard.isDown("w", "up") then my = my - 1 end
  if love.keyboard.isDown("s", "down") then my = my + 1 end

  mx, my = normalize(mx, my)
  p.x = clamp(p.x + mx * p.speed * dt, p.r, world.w - p.r)
  p.y = clamp(p.y + my * p.speed * dt, p.r, world.h - p.r)
  p.invuln = math.max(0, p.invuln - dt)

  p.fireTimer = p.fireTimer - dt
  if p.fireTimer <= 0 then
    fireBullets()
    p.fireTimer = p.fireRate
  end
end

local function updateCamera()
  local p = game.player
  game.camera.x = clamp(p.x - W / 2, 0, world.w - W)
  game.camera.y = clamp(p.y - H / 2, 0, world.h - H)
end

local function updateEnemies(dt)
  local p = game.player

  for i = #game.enemies, 1, -1 do
    local enemy = game.enemies[i]
    local dx, dy = normalize(p.x - enemy.x, p.y - enemy.y)
    enemy.x = enemy.x + dx * enemy.speed * dt
    enemy.y = enemy.y + dy * enemy.speed * dt

    local touch = p.r + enemy.r
    if dist2(p.x, p.y, enemy.x, enemy.y) < touch * touch and p.invuln <= 0 then
      p.hp = p.hp - enemy.damage
      p.invuln = 0.55
      addFloater("氣血 -" .. enemy.damage, p.x, p.y - 24, { 1, 0.35, 0.35 })

      if p.hp <= 0 then
        p.hp = 0
        game.state = "gameover"
      end
    end
  end
end

local function updateBullets(dt)
  for i = #game.bullets, 1, -1 do
    local bullet = game.bullets[i]
    bullet.x = bullet.x + bullet.dx * bullet.speed * dt
    bullet.y = bullet.y + bullet.dy * bullet.speed * dt
    bullet.life = bullet.life - dt

    local removeBullet = bullet.life <= 0

    for j = #game.enemies, 1, -1 do
      local enemy = game.enemies[j]
      local hit = bullet.r + enemy.r
      if dist2(bullet.x, bullet.y, enemy.x, enemy.y) < hit * hit then
        enemy.hp = enemy.hp - bullet.damage
        addFloater("勁 " .. tostring(math.floor(bullet.damage)), enemy.x, enemy.y - 18, { 1, 0.95, 0.55 })
        removeBullet = true

        if enemy.hp <= 0 then
          table.insert(game.gems, {
            x = enemy.x,
            y = enemy.y,
            r = enemy.elite and 8 or 6,
            xp = enemy.xp
          })
          game.player.score = game.player.score + (enemy.elite and 35 or 10)
          table.remove(game.enemies, j)
        end

        break
      end
    end

    if removeBullet then
      table.remove(game.bullets, i)
    end
  end
end

local function updateGems(dt)
  local p = game.player

  for i = #game.gems, 1, -1 do
    local gem = game.gems[i]
    local range = p.pickupRange
    local d = math.sqrt(dist2(p.x, p.y, gem.x, gem.y))

    if d < range then
      local dx, dy = normalize(p.x - gem.x, p.y - gem.y)
      local pull = (260 + (range - d) * 7) * p.magnet
      gem.x = gem.x + dx * pull * dt
      gem.y = gem.y + dy * pull * dt
    end

    if d < p.r + gem.r then
      gainXp(gem.xp)
      addFloater("修為 +" .. gem.xp, p.x, p.y - 34, { 0.45, 0.9, 1 })
      table.remove(game.gems, i)
    end
  end
end

local function updateFloaters(dt)
  for i = #game.floaters, 1, -1 do
    local floater = game.floaters[i]
    floater.life = floater.life - dt
    floater.y = floater.y + floater.vy * dt

    if floater.life <= 0 then
      table.remove(game.floaters, i)
    end
  end
end

local function updateSpawner(dt)
  game.spawnTimer = game.spawnTimer - dt
  local pressure = clamp(game.time / 180, 0, 1)

  if game.spawnTimer <= 0 then
    local batch = 1 + math.floor(game.time / 35)
    for _ = 1, batch do
      spawnEnemy()
    end
    game.spawnTimer = 0.86 - pressure * 0.42
  end
end

function love.load()
  love.window.setMode(W, H)
  love.graphics.setDefaultFilter("nearest", "nearest")
  math.randomseed(os.time())
  loadCJKFonts()
  resetGame()
end

function love.update(dt)
  if game.state ~= "playing" then
    return
  end

  dt = math.min(dt, 1 / 30)
  game.time = game.time + dt
  game.messageTimer = math.max(0, game.messageTimer - dt)

  updateSpawner(dt)
  updatePlayer(dt)
  updateEnemies(dt)
  updateBullets(dt)
  updateGems(dt)
  updateFloaters(dt)
  updateCamera()
end

local function drawGrid()
  love.graphics.setColor(0.12, 0.14, 0.18)
  love.graphics.rectangle("fill", 0, 0, world.w, world.h)

  love.graphics.setColor(0.18, 0.2, 0.25)
  for x = 0, world.w, 80 do
    love.graphics.line(x, 0, x, world.h)
  end
  for y = 0, world.h, 80 do
    love.graphics.line(0, y, world.w, y)
  end

  love.graphics.setColor(0.26, 0.2, 0.18)
  for i = 1, 14 do
    local x = (i * 157) % world.w
    local y = (i * 263) % world.h
    love.graphics.rectangle("fill", x, y, 72, 42, 8, 8)
  end
end

local function drawWorld()
  local p = game.player

  love.graphics.push()
  love.graphics.translate(-game.camera.x, -game.camera.y)
  love.graphics.setFont(game.fontWorld)

  drawGrid()

  for _, gem in ipairs(game.gems) do
    love.graphics.setColor(0.1, 0.82, 1)
    love.graphics.polygon("fill", gem.x, gem.y - gem.r, gem.x + gem.r, gem.y, gem.x, gem.y + gem.r, gem.x - gem.r, gem.y)
  end

  for _, bullet in ipairs(game.bullets) do
    love.graphics.setColor(1, 0.9, 0.35)
    love.graphics.circle("fill", bullet.x, bullet.y, bullet.r)
  end

  for _, enemy in ipairs(game.enemies) do
    if enemy.elite then
      love.graphics.setColor(0.85, 0.22, 0.42)
    else
      love.graphics.setColor(0.62, 0.18, 0.78)
    end
    love.graphics.circle("fill", enemy.x, enemy.y, enemy.r)
    love.graphics.setColor(0.98, 0.78, 0.9)
    love.graphics.circle("line", enemy.x, enemy.y, enemy.r)
  end

  if p.invuln > 0 then
    love.graphics.setColor(0.35, 0.85, 1, 0.45 + math.sin(game.time * 38) * 0.2)
  else
    love.graphics.setColor(0.18, 0.9, 0.58)
  end
  love.graphics.circle("fill", p.x, p.y, p.r)
  love.graphics.setColor(0.04, 0.15, 0.1)
  love.graphics.circle("line", p.x, p.y, p.r + 2)
  love.graphics.setColor(0.9, 1, 0.95)
  love.graphics.print("少俠", p.x - 16, p.y - 8)

  for _, floater in ipairs(game.floaters) do
    local alpha = floater.life / floater.maxLife
    love.graphics.setColor(floater.color[1], floater.color[2], floater.color[3], alpha)
    love.graphics.print(floater.text, floater.x, floater.y)
  end

  love.graphics.pop()
end

local function drawBar(x, y, w, h, value, maxValue, fillColor, backColor)
  love.graphics.setColor(backColor)
  love.graphics.rectangle("fill", x, y, w, h, 6, 6)
  love.graphics.setColor(fillColor)
  love.graphics.rectangle("fill", x, y, w * clamp(value / maxValue, 0, 1), h, 6, 6)
  love.graphics.setColor(1, 1, 1, 0.7)
  love.graphics.rectangle("line", x, y, w, h, 6, 6)
end

local function drawHud()
  local p = game.player

  love.graphics.setFont(game.fontUi)

  love.graphics.setColor(0.04, 0.05, 0.07, 0.78)
  love.graphics.rectangle("fill", 14, 12, 460, 76, 10, 10)

  love.graphics.setColor(1, 1, 1)
  love.graphics.print("初入江湖 · 問俠之路", 26, 22)
  love.graphics.print("境界 " .. p.level .. "    俠名 " .. p.score, 26, 62)
  love.graphics.print("時辰 " .. formatTime(game.time), W / 2 - 36, 22)

  drawBar(26, 42, 190, 12, p.hp, p.maxHp, { 0.92, 0.22, 0.24 }, { 0.22, 0.08, 0.1 })
  drawBar(26, H - 24, W - 52, 10, p.xp, p.xpNext, { 0.2, 0.75, 1 }, { 0.05, 0.14, 0.2 })

  love.graphics.setColor(1, 1, 1, 0.75)
  love.graphics.print("WASD／方向鍵挪移身形；勁氣自動襲向最近之敵", 26, H - 48)

  if game.messageTimer > 0 then
    love.graphics.setColor(1, 0.96, 0.65, game.messageTimer / 4)
    love.graphics.printf("邪祟外道四起，挺過試煉、凝練功力，方能踏上大俠之路。", 0, 110, W, "center")
  end
end

local function drawLevelUp()
  love.graphics.setColor(0, 0, 0, 0.68)
  love.graphics.rectangle("fill", 0, 0, W, H)
  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(game.fontTitle)
  love.graphics.printf("功力精進！請擇一門心法傍身", 0, 92, W, "center")
  love.graphics.setFont(game.fontUi)

  for i, choice in ipairs(game.upgradeChoices) do
    local x = 165 + (i - 1) * 220
    local y = 180
    love.graphics.setColor(0.12, 0.15, 0.22)
    love.graphics.rectangle("fill", x, y, 190, 150, 12, 12)
    love.graphics.setColor(0.8, 0.9, 1)
    love.graphics.rectangle("line", x, y, 190, 150, 12, 12)
    love.graphics.setColor(1, 0.95, 0.55)
    love.graphics.printf(i .. ". " .. choice.title, x + 14, y + 22, 162, "center")
    love.graphics.setColor(1, 1, 1, 0.84)
    love.graphics.printf(choice.desc, x + 18, y + 78, 154, "center")
  end

  love.graphics.setColor(1, 1, 1, 0.7)
  love.graphics.printf("按 1／2／3 抉擇心法", 0, 370, W, "center")
end

local function drawGameOver()
  love.graphics.setColor(0, 0, 0, 0.72)
  love.graphics.rectangle("fill", 0, 0, W, H)
  love.graphics.setColor(1, 0.55, 0.55)
  love.graphics.setFont(game.fontTitle)
  love.graphics.printf("刀光劍影之中，你力竭倒地……", 0, 150, W, "center")
  love.graphics.setFont(game.fontUi)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(
    "行走江湖 " .. formatTime(game.time) .. "    俠名 " .. game.player.score,
    0,
    210,
    W,
    "center"
  )
  love.graphics.setColor(1, 1, 1, 0.72)
  love.graphics.printf("按 R 再闖江湖，Esc 退去", 0, 270, W, "center")
end

function love.draw()
  drawWorld()
  drawHud()

  if game.state == "levelup" then
    drawLevelUp()
  elseif game.state == "gameover" then
    drawGameOver()
  end
end

function love.keypressed(key)
  if key == "escape" then
    love.event.quit()
  end

  if game.state == "gameover" and key == "r" then
    resetGame()
    return
  end

  if game.state == "levelup" then
    local index = tonumber(key)
    local choice = index and game.upgradeChoices[index]
    if choice then
      choice.apply(game.player)
      game.state = "playing"
      game.messageTimer = 1.4
      addFloater(choice.title, game.player.x - 24, game.player.y - 44, { 1, 0.95, 0.45 })
    end
  end
end
