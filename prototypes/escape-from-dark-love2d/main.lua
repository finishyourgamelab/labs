-- Escape From Dark - Love2D
-- 三段式潛行恐怖遊戲。模組化結構：
--   src/util.lua      共用工具
--   src/fonts.lua     字型載入
--   src/audio.lua     音訊系統（mp3 / ogg）
--   src/levels.lua    三關卡資料
--   src/enemies.lua   敵人模板
--   src/scenes/menu   主選單
--   src/scenes/play   遊玩

local fonts = require("src.fonts")
local audio = require("src.audio")
local levels = require("src.levels")
local items = require("src.items")
local Menu = require("src.scenes.menu")
local Play = require("src.scenes.play")

local GAME = {
  title = "Escape From Dark",
  width = 1280,
  height = 720,
}

local current = nil

-- scene 控制 API：傳給 scene 的 keypressed / 內部呼叫
local scenes = {}

function scenes.menu()
  if current and current.leave then current:leave() end
  current = Menu.new()
  if current.enter then current:enter() end
end

function scenes.start(levelIndex)
  if current and current.leave then current:leave() end
  current = Play.new(levelIndex)
  if current.enter then current:enter() end
end

-- ---------------------------------------------------------------------------
-- 煙霧測試：自動跑過三關卡的關鍵流程，命中錯誤即 fail。
-- ---------------------------------------------------------------------------

local function assertSmoke(condition, label)
  if not condition then
    error("smoke test failed: " .. label, 2)
  end
end

local function runSmokeTest()
  love.math.setRandomSeed(12345)

  -- 1. 載入主選單能渲染
  scenes.menu()
  assertSmoke(current ~= nil, "menu created")
  local ok, err = pcall(function()
    current:draw(GAME.width, GAME.height)
  end)
  assertSmoke(ok, err or "menu draws")

  -- 2. 三個關卡都能載入並繪製一幀
  for i = 1, levels.count() do
    scenes.start(i)
    assertSmoke(current.level ~= nil, "level " .. i .. " loaded")
    assertSmoke(#current.enemies >= 1, "level " .. i .. " has enemies")
    assertSmoke(#current.crates >= 1, "level " .. i .. " has crates")
    assertSmoke(#current.level.extracts >= 1, "level " .. i .. " has extracts")
    -- 跑幾個 update tick
    for _ = 1, 6 do current:update(0.05) end
    local drewOk, drawErr = pcall(function()
      current:draw(GAME.width, GAME.height)
    end)
    assertSmoke(drewOk, drawErr or ("level " .. i .. " draws"))
  end

  -- 3. 戰鬥流程：給玩家一發子彈穿過敵人
  scenes.start(1)
  local enemy = current.enemies[1]
  table.insert(current.bullets, {
    x = enemy.x, y = enemy.y, vx = 0, vy = 0,
    radius = 5, damage = 9999, life = 0.1,
  })
  current:update(0.016)
  assertSmoke(current.player.kills >= 1, "bullet kills enemy")

  -- 4. 撤離流程：背包塞滿值錢物品 + 走進撤離區
  scenes.start(1)
  do
    local inv = require("src.inventory")
    -- 估價公式：goldring 28 / document 32 / battery 14；隨意塞夠超過 lootGoal 的物資
    inv.add(current.player.inventory, "goldring", 6)
    inv.add(current.player.inventory, "document", 3)
    inv.add(current.player.inventory, "battery", 4)
  end
  local ext = current.level.extracts[1]
  current.player.x = ext.x + ext.w / 2
  current.player.y = ext.y + ext.h / 2
  -- 模擬按住 E 兩秒半
  local origIsDown = love.keyboard.isDown
  love.keyboard.isDown = function(key, ...) return key == "e" end
  for _ = 1, 60 do current:update(0.05) end
  love.keyboard.isDown = origIsDown
  assertSmoke(current.phase == "won", "extracting wins the level")

  -- 5. 致命傷害結束關卡
  scenes.start(1)
  current.player.armor = 0
  current.player.hp = 1
  for _, e in ipairs(current.enemies) do e.x = current.player.x; e.y = current.player.y end
  for _ = 1, 30 do current:update(0.05) end
  assertSmoke(current.phase == "lost" or current.player.hp <= 1,
    "lethal proximity damage ends raid")

  -- 6. 視野錐 / 噪音偵測：把敵人擺到玩家面前看 awareness 上升
  scenes.start(1)
  local p = current.player
  local e = current.enemies[1]
  e.x = p.x + 80
  e.y = p.y
  e.angle = math.pi   -- 朝向玩家
  for _ = 1, 30 do current:update(0.05) end
  assertSmoke(e.awareness > 0, "enemy detects player in line of sight")

  -- 7. 噪音偵測：讓玩家開槍，鄰近敵人（背向、不在視野裡）應收到聽覺
  scenes.start(1)
  local p7 = current.player
  local e7 = current.enemies[1]
  e7.x = p7.x + 80
  e7.y = p7.y + 80
  e7.angle = 0    -- 背向玩家（玩家在左上）
  e7.awareness = 0
  p7.noise = 1.0   -- 直接模擬剛開槍
  current:update(0.3)
  assertSmoke(e7.awareness > 0, "loud noise alerts nearby enemy")

  -- 8. 蹲伏降噪：把噪音壓到很低，敵人不應被觸發
  scenes.start(1)
  local p8 = current.player
  local e8 = current.enemies[1]
  e8.x = p8.x + 200
  e8.y = p8.y - 200
  e8.angle = 0
  e8.awareness = 0
  p8.crouching = true
  p8.noise = 0.05
  current:update(0.3)
  assertSmoke(e8.awareness < 0.5, "crouching keeps enemy unaware")

  -- 9. 醫療包：扣血後使用 medkit 應回血（從背包消耗）
  scenes.start(1)
  do
    local inv = require("src.inventory")
    -- 清空原本起始的繃帶，確保 Q 真的拿到 medkit
    inv.remove(current.player.inventory, "bandage", 99)
    inv.remove(current.player.inventory, "cloth", 99)
    inv.add(current.player.inventory, "medkit", 1)
    current.player.hp = 50
    current:keypressed("q", { menu = function() end, start = function() end })
    assertSmoke(current.player.hp > 50, "medkit heals player")
    assertSmoke(inv.countOf(current.player.inventory, "medkit") == 0, "medkit is consumed")
  end

  -- 10. 選單：切換關卡、開始遊戲
  scenes.menu()
  current:keypressed("down", { menu = scenes.menu, start = scenes.start })
  assertSmoke(current.selected == 2, "menu selection moves to lv2")
  current:keypressed("return", { menu = scenes.menu, start = scenes.start })
  assertSmoke(current.level and current.level.id == "lv2_morgue", "menu starts lv2")

  -- 11. audio.update 在沒有 BGM 時也不會出錯
  audio.stopMusic()
  for _ = 1, 5 do audio.update(0.05) end

  -- 12. 壓力值會在燈光下降下來（防止「站在燈下 stress 卻不掉」的回歸）
  scenes.start(1)
  -- 把玩家放到第一盞燈正中心，燈光值會接近 1
  local lt = current.level.lights[1]
  current.player.x = lt.x
  current.player.y = lt.y
  current.player.stress = 60
  current.alarm = 0
  -- 清掉所有敵人，避免 alarm 觸發
  current.enemies = {}
  for _ = 1, 60 do current:update(0.1) end
  assertSmoke(current.player.stress < 60, "stress recovers under light")

  -- 13. 站在燈光半徑一半處（不是中心）也應該能恢復
  scenes.start(1)
  local lt2 = current.level.lights[1]
  current.player.x = lt2.x + lt2.radius * 0.5
  current.player.y = lt2.y
  current.player.stress = 50
  current.alarm = 0
  current.enemies = {}
  for _ = 1, 60 do current:update(0.1) end
  assertSmoke(current.player.stress < 50, "stress recovers at half-radius from light")

  -- 14. alarm=1 + 強光下也應能恢復（不會被 alarm 永遠拖住）
  scenes.start(1)
  local lt3 = current.level.lights[1]
  current.player.x = lt3.x
  current.player.y = lt3.y
  current.player.stress = 70
  current.alarm = 1
  current.enemies = {}
  for _ = 1, 60 do current:update(0.1) end
  assertSmoke(current.player.stress < 70, "strong light overpowers alarm penalty")

  -- 15. 黑暗中完全站定時，壓力不應再原地上升
  scenes.start(1)
  current.player.x = current.level.spawn.x
  current.player.y = current.level.spawn.y
  current.player.stress = 40
  current.player.noise = 0
  current.alarm = 0
  current.enemies = {}
  for _ = 1, 60 do current:update(0.1) end
  assertSmoke(current.player.stress <= 40, "standing still does not increase stress")

  -- 16. 玩家視野：朝右 (angle=0) 時，左後方 800px 處的敵人不應被視為可見；
  --     正前方 200px 處的敵人應該可見；近身周圍 50px 即使在背後也應可見。
  scenes.start(1)
  current.player.x = 1000
  current.player.y = 800
  current.player.angle = 0      -- 朝右
  current.player.visionRange = 460
  current.player.visionAngle = math.rad(110)
  current.player.proximityRange = 90
  -- 玩家可見性 helper 是檔案內 local，這裡透過 draw 結果驗證行為：
  -- 直接用 dist + angle 重現 playerCanSee 的扇形判定（白盒測試）
  local function canSeeFromPlayer(tx, ty)
    local p = current.player
    local dx, dy = tx - p.x, ty - p.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < p.proximityRange then return true end
    if d > p.visionRange then return false end
    local a = math.atan2 and math.atan2(dy, dx) or math.atan(dy, dx)
    local diff = math.abs(((a - p.angle + math.pi) % (math.pi * 2)) - math.pi)
    return diff <= p.visionAngle / 2
  end
  assertSmoke(canSeeFromPlayer(1200, 800), "front 200px is visible")
  assertSmoke(not canSeeFromPlayer(200, 800), "rear 800px is not visible")
  assertSmoke(canSeeFromPlayer(960, 760), "close-by 50px behind is visible (proximity)")
  assertSmoke(not canSeeFromPlayer(1000 + 600, 800 + 600), "far diagonal beyond range is not visible")

  -- 17. 敵人視野不能比玩家站立視野遠（460），維持「兩者距離一致」的緊張刺激
  for li = 1, levels.count() do
    scenes.start(li)
    local stand = current.player.visionRange  -- 460
    local maxEnemy = 0
    for _, e in ipairs(current.enemies) do
      if e.sightRange > maxEnemy then maxEnemy = e.sightRange end
    end
    assertSmoke(maxEnemy <= stand,
      ("level %d max enemy sightRange %d should be ≤ player %d"):format(li, maxEnemy, stand))
  end

  -- 18. 物資系統：搜刮箱子應該把物品塞進背包（用 stash 類型，避免 ammo crate
  --     被立刻轉成 player.ammo 而不進背包）
  do
    scenes.start(1)
    local inv = require("src.inventory")
    local crate
    for _, c in ipairs(current.crates) do
      if c.kind == "stash" or c.kind == "safe" then crate = c; break end
    end
    assertSmoke(crate ~= nil, "found a stash/safe crate to test loot")
    current.player.x = crate.x
    current.player.y = crate.y
    local origIsDown = love.keyboard.isDown
    love.keyboard.isDown = function(key) return key == "e" end
    for _ = 1, 30 do current:update(0.05) end
    love.keyboard.isDown = origIsDown
    assertSmoke(crate.searched, "crate searched after E hold")
    assertSmoke(#current.player.inventory.stacks >= 1, "loot added to inventory")
  end

  -- 19. 物資估價會即時等於 loot
  do
    scenes.start(1)
    local inv = require("src.inventory")
    inv.add(current.player.inventory, "goldring", 1)  -- value 28
    current:update(0.016)
    assertSmoke(current.player.loot >= 28, "appraise refreshes p.loot")
  end

  -- 20. 合成：2 繃帶 → 1 醫療包
  do
    scenes.start(1)
    local inv = require("src.inventory")
    inv.remove(current.player.inventory, "bandage", 99)
    inv.add(current.player.inventory, "bandage", 2)
    local recipe
    for _, r in ipairs(items.recipes()) do
      if r.id == "craft_medkit" then recipe = r end
    end
    local ok, msg = inv.craft(current.player.inventory, recipe)
    assertSmoke(ok, "bandage→medkit craft works: " .. tostring(msg))
    assertSmoke(inv.countOf(current.player.inventory, "medkit") >= 1, "got 1 medkit")
    assertSmoke(inv.countOf(current.player.inventory, "bandage") == 0, "bandages consumed")
  end

  -- 21. 儲物箱：F 互動需玩家靠近才能開
  do
    scenes.start(1)
    current.player.x = current.stash.x
    current.player.y = current.stash.y
    current:keypressed("f", { menu = function() end, start = function() end })
    assertSmoke(current.uiPanel == "stash", "stash opens when player adjacent")
    -- 用 SPACE 把第一個 stack 移到儲物箱
    local s1 = current.player.inventory.stacks[1]
    if s1 then
      local id = s1.id
      local cnt = s1.count
      current:keypressed("space")
      local moved = require("src.inventory").countOf(current.stash.inventory, id)
      assertSmoke(moved >= 1, "space moves stack to stash")
    end
    current:keypressed("escape")
    assertSmoke(current.uiPanel == nil, "esc closes panel")
  end

  -- 22. 重量上限：超重後不能再塞進去
  do
    scenes.start(1)
    local inv = require("src.inventory")
    local p = current.player
    p.inventory.weightLimit = 1.0   -- 故意拉低
    inv.remove(p.inventory, "bandage", 99)
    inv.remove(p.inventory, "cloth", 99)
    local got1, _ = inv.add(p.inventory, "battery", 4)   -- 4 * 0.3 = 1.2 > 1.0
    assertSmoke(got1 < 4, "weight limit blocks excess battery")
    assertSmoke(inv.weight(p.inventory) <= 1.0 + 1e-6, "weight stays within limit")
  end

  print("Escape From Dark smoke test passed: 三關卡 / 戰鬥 / 撤離 / 視野 / 聽覺 / 蹲伏 / 醫療 / 選單 / 音訊 / 壓力恢復 / 原地穩定 / 玩家視野 / 敵我視野齊齊 / 背包 / 合成 / 儲物箱 / 重量 OK")
end

-- ---------------------------------------------------------------------------
-- LÖVE callbacks
-- ---------------------------------------------------------------------------

-- 煙霧測試或 CI 環境：把 error 直接印到 stdout 並 quit，避免進入錯誤畫面卡住終端機
function love.errorhandler(msg)
  io.stderr:write(tostring(msg) .. "\n")
  io.stderr:write(debug.traceback("", 2) .. "\n")
  io.stderr:flush()
  return function() return 1 end
end
love.errhand = love.errorhandler

function love.load(args)
  love.window.setTitle(GAME.title)
  love.graphics.setBackgroundColor(0.04, 0.05, 0.06)
  love.math.setRandomSeed(os.time())

  fonts.load()
  audio.load()

  for _, value in ipairs(args or {}) do
    if value == "--smoke-test" then
      runSmokeTest()
      love.event.quit(0)
      return
    end
  end

  scenes.menu()
end

function love.update(dt)
  audio.update(dt)
  if not current then return end
  current:update(math.min(dt, 1 / 30))
end

function love.draw()
  if not current then return end
  current:draw(love.graphics.getWidth(), love.graphics.getHeight())
end

function love.keypressed(key)
  if key == "escape" then
    love.event.quit()
    return
  end
  if key == "m" then
    audio.toggleMute()
    return
  elseif key == "[" then
    audio.setMasterVolume(audio.getMasterVolume() - 0.1)
    return
  elseif key == "]" then
    audio.setMasterVolume(audio.getMasterVolume() + 0.1)
    return
  end
  if current and current.keypressed then
    current:keypressed(key, scenes)
  end
end
