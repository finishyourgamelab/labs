--[[==========================================================================
  main_v2.lua — 《初入江湖》Love2D 教學版（v2）

  【給同學的導讀】
  這份檔案在「玩法數學」上與 main_v1.lua 相同（仍是圓形碰撞、自動鎖敵、三選一升級），
  但刻意示範三件事：
    1. 資料驅動（data-driven）：升級選項集中在 upgrades 表，每項含「流派標籤」與文案，
       方便修改數值或換皮而不動到底層碰撞。
    2. 呈現與玩法分離：同樣的 bullet 資料結構，在 draw 階段改畫成「劍氣」視覺（旋轉橢圓 + 尾芒），
       不改 update 裡的位移公式。
    3. UI 狀態機：game.state 在 playing / levelup / gameover 三態切換；升級時 update 暫停，
       只接收鍵盤選招。

  【武俠設定備註】
  招式文案刻意混搭「近身寫實」（步法、腰馬、丹田調息）與「劍氣風格」（罡氣外吐、分化劍芒），
  方便對照網路上常見的新派武俠／玄幻武俠描述；遊戲內仍以抽象「勁氣彈」代表遠距劍罡。
==========================================================================]]

local game = {}

---------------------------------------------------------------------------
-- 一、常數：視窗大小與「江湖」地圖（世界座標）
-- Love2D 的 draw 預設原點在左上角；我們用 camera 平移，讓主角大致落在螢幕中央。
---------------------------------------------------------------------------
local W, H = 960, 540
local world = { w = 2200, h = 1600 }

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

--- 距離平方（避免頻繁 sqrt；碰撞判斷常用「半徑和的平方」）
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

---------------------------------------------------------------------------
-- 二、字型：CJK 必須自行載入（預設字型缺字會變□□）
---------------------------------------------------------------------------
local FONT_PATHS = {
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
  game.fontSmall = nil

  for _, path in ipairs(FONT_PATHS) do
    local fWorld = tryLoadFont(path, 14)
    local fUi = tryLoadFont(path, 16)
    local fTitle = tryLoadFont(path, 26)
    local fSmall = tryLoadFont(path, 12)
    if fWorld and fUi and fTitle and fSmall then
      game.fontWorld = fWorld
      game.fontUi = fUi
      game.fontTitle = fTitle
      game.fontSmall = fSmall
      break
    end
  end

  if not game.fontUi then
    game.fontWorld = love.graphics.newFont(14)
    game.fontUi = love.graphics.newFont(16)
    game.fontTitle = love.graphics.newFont(26)
    game.fontSmall = love.graphics.newFont(12)
    game.fontWorld:setFilter("linear", "linear")
    game.fontUi:setFilter("linear", "linear")
    game.fontTitle:setFilter("linear", "linear")
    game.fontSmall:setFilter("linear", "linear")
  end
end

---------------------------------------------------------------------------
-- 三、遊戲重設：清空列表、建立主角狀態（單一 table 集中管理屬性）
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- 四、升級表（資料驅動）
--   style = "near"  → 文案走「近身、步法、丹田」等較寫實的比武語境
--   style = "qi"    → 文案走「劍罡、劍芒、遙發」等劍氣語境
--   apply(p)        → 閉包：只修改 player，不改全域，方便單元想像與除錯
---------------------------------------------------------------------------
local upgrades = {
  {
    style = "near",
    title = "步法·八卦趟泥",
    subtitle = "腰腿送勁 · 圈步換勢",
    desc = "不賣弄縹緲輕功，而以腰胯帶步如犁耙地；進退更快半式。（移動 +12%）",
    apply = function(p)
      p.speed = p.speed * 1.12
    end
  },
  {
    style = "qi",
    title = "劍罡·青刃吐芒",
    subtitle = "腕肘發勁 · 寸許外罡",
    desc = "真氣經腕肘而出，劍尖吐出淡淡青芒；透甲之力。（傷害 +7）",
    apply = function(p)
      p.bulletDamage = p.bulletDamage + 7
    end
  },
  {
    style = "qi",
    title = "劍訣·疾雨連刺",
    subtitle = "劍花連環 · 氣密如織",
    desc = "腕底翻身不停，劍氣勃發更密；敵勢未穩再添一招。（出招間隔 -12%）",
    apply = function(p)
      p.fireRate = p.fireRate * 0.88
    end
  },
  {
    style = "qi",
    title = "劍影·三清分化",
    subtitle = "一氣化形 · 數縷齊至",
    desc = "丹田一吐，真氣裂為數縷劍芒，彷彿數劍封門。（每次多一道劍氣）",
    apply = function(p)
      p.projectiles = p.projectiles + 1
    end
  },
  {
    style = "near",
    title = "身法·攝步牽引",
    subtitle = "步帶氣機 · 吞吐為引",
    desc = "步法起落牽動周身氣機，丈內碎屑、修為光點不由自主向你靠攏。（拾取範圍 +45%）",
    apply = function(p)
      p.pickupRange = p.pickupRange * 1.45
      p.magnet = p.magnet + 0.45
    end
  },
  {
    style = "near",
    title = "調息·鼓盪丹田",
    subtitle = "吐納歸元 · 氣血為本",
    desc = "坐下三呼三吸，經脈暫通；氣血充盈，再度起身。（上限 +20，並回復 20）",
    apply = function(p)
      p.maxHp = p.maxHp + 20
      p.hp = math.min(p.maxHp, p.hp + 20)
    end
  }
}

--- 飄字：只在畫面上浮動一段時間，不影響碰撞（純 FX）
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

---------------------------------------------------------------------------
-- 五、升級抽選：自全域 upgrades 表中不重複抽三張（若不足三張則全亮）
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- 六、修為（XP）：每級只跳一次選單（break 刻意為之，避免同一幀連升多級卡 UI）
---------------------------------------------------------------------------
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

--- 自動鎖敵：找距離平方最小者（O(n)，原型足夠）
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

---------------------------------------------------------------------------
-- 七、「劍氣」投射物：邏輯仍是「方向單位向量 × 速度」；繪製時才旋轉成刃形
---------------------------------------------------------------------------
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
    local dx, dy = math.cos(angle), math.sin(angle)
    table.insert(game.bullets, {
      x = p.x,
      y = p.y,
      r = 5,
      dx = dx,
      dy = dy,
      angle = angle,
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
        addFloater(
          "劍罡 " .. tostring(math.floor(bullet.damage)),
          enemy.x,
          enemy.y - 18,
          { 0.65, 0.92, 1 }
        )
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

--- update：levelup / gameover 時提早 return，畫面凍結在上一幀世界狀態（常見 Roguelike 做法）
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

---------------------------------------------------------------------------
-- 八、劍氣繪製：橢圓當「刃身」，半透明線當「尾芒」（視覺暗示運動方向）
---------------------------------------------------------------------------
local function drawSwordQiBullet(bullet)
  love.graphics.push()
  love.graphics.translate(bullet.x, bullet.y)
  love.graphics.rotate(bullet.angle)

  love.graphics.setColor(0.45, 0.82, 1, 0.35)
  love.graphics.ellipse("fill", -10, 0, 22, 7)

  love.graphics.setColor(0.85, 0.96, 1, 0.95)
  love.graphics.ellipse("fill", 0, 0, 16, 5)

  love.graphics.setColor(1, 1, 0.92, 0.55)
  love.graphics.ellipse("line", 0, 0, 18, 6)

  love.graphics.setLineWidth(2)
  love.graphics.setColor(0.7, 0.95, 1, 0.45)
  love.graphics.line(-28, 0, -10, 0)
  love.graphics.setLineWidth(1)

  love.graphics.pop()
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
    drawSwordQiBullet(bullet)
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
  love.graphics.print("WASD／方向鍵挪移身形；劍氣自動鎖向最近之敵", 26, H - 48)

  if game.messageTimer > 0 then
    love.graphics.setColor(1, 0.96, 0.65, game.messageTimer / 4)
    love.graphics.printf("邪祟外道四起，挺過試煉、凝練功力，方能踏上大俠之路。", 0, 110, W, "center")
  end
end

---------------------------------------------------------------------------
-- 九、升級選單（v2）：依 style 上色區分「近身」與「劍氣」，並畫卷軸裝飾框
---------------------------------------------------------------------------
local function drawScrollCorners(x, y, w, h, col)
  local k = 14
  love.graphics.setColor(col[1], col[2], col[3], 0.9)
  love.graphics.setLineWidth(2)
  love.graphics.line(x, y + k, x, y, x + k, y)
  love.graphics.line(x + w - k, y, x + w, y, x + w, y + k)
  love.graphics.line(x, y + h - k, x, y + h, x + k, y + h)
  love.graphics.line(x + w, y + h - k, x + w, y + h, x + w - k, y + h)
  love.graphics.setLineWidth(1)
end

local function drawLevelUp()
  love.graphics.setColor(0.02, 0.03, 0.06, 0.82)
  love.graphics.rectangle("fill", 0, 0, W, H)

  love.graphics.setColor(0.35, 0.28, 0.18, 0.55)
  love.graphics.rectangle("fill", 0, 58, W, 110)

  love.graphics.setFont(game.fontSmall)
  love.graphics.setColor(0.82, 0.72, 0.48, 0.95)
  love.graphics.printf("──────────────── 秘笈抉擇 ────────────────", 0, 68, W, "center")

  love.graphics.setFont(game.fontTitle)
  love.graphics.setColor(1, 0.94, 0.78)
  love.graphics.printf("功力精進 · 擇一門傍身", 0, 94, W, "center")

  love.graphics.setFont(game.fontUi)
  love.graphics.setColor(0.88, 0.88, 0.92, 0.75)
  love.graphics.printf("【近身】步法腰馬、丹田調息　｜　【劍氣】罡芒外吐、遙御劍訣", 0, 134, W, "center")

  local cardW, cardH, gap = 208, 212, 18
  local totalW = cardW * 3 + gap * 2
  local startX = (W - totalW) / 2
  local cy = 175

  for i, choice in ipairs(game.upgradeChoices) do
    local x = startX + (i - 1) * (cardW + gap)
    local y = cy

    local isQi = choice.style == "qi"
    local headCol = isQi and { 0.22, 0.42, 0.62 } or { 0.42, 0.28, 0.2 }
    local accent = isQi and { 0.55, 0.88, 1 } or { 0.92, 0.72, 0.48 }
    local badge = isQi and "劍氣" or "近身"

    love.graphics.setColor(0.08, 0.1, 0.14)
    love.graphics.rectangle("fill", x, y, cardW, cardH, 14, 14)

    love.graphics.setColor(headCol[1], headCol[2], headCol[3], 1)
    love.graphics.rectangle("fill", x + 6, y + 8, cardW - 12, 36, 8, 8)

    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(accent[1], accent[2], accent[3], 1)
    love.graphics.printf("【" .. badge .. "】", x + 10, y + 14, cardW - 20, "center")

    love.graphics.setFont(game.fontUi)
    love.graphics.setColor(1, 0.96, 0.82)
    love.graphics.printf(tostring(i) .. " · " .. choice.title, x + 12, y + 52, cardW - 24, "center")

    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(0.78, 0.82, 0.9, 0.9)
    love.graphics.printf(choice.subtitle, x + 14, y + 82, cardW - 28, "center")

    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(0.9, 0.9, 0.92, 0.88)
    love.graphics.printf(choice.desc, x + 14, y + 108, cardW - 28, "center")

    drawScrollCorners(x + 4, y + 4, cardW - 8, cardH - 8, accent)

    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.rectangle("line", x, y, cardW, cardH, 14, 14)
  end

  love.graphics.setFont(game.fontUi)
  love.graphics.setColor(0.92, 0.86, 0.72, 0.85)
  love.graphics.printf("按 1／2／3 認領秘笈　·　Esc 離開江湖", 0, cy + cardH + 28, W, "center")
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
      addFloater("習得 · " .. choice.title, game.player.x - 40, game.player.y - 44, { 0.75, 0.95, 1 })
    end
  end
end
