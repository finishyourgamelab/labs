do
  for _, a in ipairs(arg or {}) do
    if a == "editor" then
      require("level_editor").mount()
      return
    end
  end
end

local world = require("world")
local Player = require("player")
local Enemy = require("enemy")
local Boss = require("boss")

local state = "title"
local cam_x, cam_y = 0, 0
local bullets = {}
local boss_bullets = {}
local enemies = {}
local p
local boss
local boss_defeated = false
local stage_msg = ""
local stage_msg_t = 0
local hint_msg = ""
local hint_msg_t = 0
local hint_cd = 0

local snd = {}
local music_stage
local music_title
local font_body
local font_large

local function load_ui_fonts()
  for _, path in ipairs({ "fonts/NotoSansTC-VF.ttf", "fonts/NotoSansTC-Regular.ttf" }) do
    if love.filesystem.getInfo(path) then
      local ok1, f1 = pcall(love.graphics.newFont, path, 16)
      local ok2, f2 = pcall(love.graphics.newFont, path, 26)
      if ok1 and ok2 then return f1, f2 end
    end
  end
end

local function load_source(rel, mode)
  return love.audio.newSource(rel, mode or "static")
end

local function show_hint(text, duration, cooldown)
  if hint_cd > 0 and cooldown then return end
  hint_msg = text
  hint_msg_t = duration or 4
  if cooldown then hint_cd = cooldown end
end

local function spawn_grunts()
  enemies = {}
  for _, pos in ipairs(world.collect_enemy_spawns()) do
    enemies[#enemies + 1] = Enemy.new(world, pos[1], pos[2])
  end
end

local function spawn_arena_boss()
  local kind, bx, by = world.arena_boss_spawn()
  boss = Boss.new(kind, world, bx, by)
end

local function enter_arena()
  world.in_arena = true
  local sx, sy = world.arena_spawn_player()
  p.x, p.y = sx, sy
  p.vx, p.vy = 0, 0
  p.invuln = 1.2
  if not boss_defeated then
    spawn_arena_boss()
    show_hint("決鬥開始！收集的寶物會強化你的招式。", 3)
  else
    boss = nil
    world.open_gate()
  end
  boss_bullets = {}
end

local function leave_arena()
  world.in_arena = false
  local sx, sy = world.arena_return_player()
  p.x, p.y = sx, sy
  p.vx, p.vy = 0, 0
  boss = nil
  boss_bullets = {}
end

local function load_level(index, carry)
  carry = carry or {}
  world.load_level(index, { gate_open = false })
  bullets = {}
  boss_bullets = {}
  boss = nil
  boss_defeated = false

  local sx, sy = world.spawn_player()
  if carry.player then
    p = carry.player
    p.world = world
    p.x, p.y = sx, sy
    p.vx, p.vy = 0, 0
    p.invuln = 1.5
  else
    p = Player.new(world, sx, sy)
  end
  local snapped = world.snap_on_plank(p.x, p.y, p.w, p.h)
  if snapped then
    p.y = snapped
  end

  spawn_grunts()
  stage_msg = world.get_level().title
  stage_msg_t = 3
  state = "play"

  if index == 1 then
    show_hint("沿左側木道一路向上（單格高差可跳），收集寶物後進「決鬥圈」。", 6)
  else
    if p:has_weapon("thunder_palm") then
      show_hint("左側木道上攀，破甲釘可助破鐵扇門主，記得用霹靂掌。", 6)
    else
      show_hint("未習霹靂掌難破鐵扇門主…建議先通第一關。", 5)
    end
  end
end

local function start_game()
  if music_title and music_title:isPlaying() then music_title:stop() end
  if music_stage then music_stage:setLooping(true); music_stage:play() end
  load_level(1, {})
end

local function go_title()
  state = "title"
  bullets, boss_bullets, enemies, boss, p = {}, {}, {}, nil, nil
  boss_defeated = false
  if music_stage and music_stage:isPlaying() then music_stage:stop() end
  if music_title then music_title:setLooping(true); music_title:play() end
end

local function on_boss_killed()
  boss_defeated = true
  world.open_gate()
  local drop = boss and boss:get_drop()
  if drop then
    p:grant_weapon(drop)
    world.spawn_weapon_pickup(drop, boss.x + boss.w / 2, boss.y)
    show_hint("習得「霹靂掌」！按 2 施展。離開決鬥圈前往下一關。", 6)
  end
  if world.level_index == 2 then
    show_hint("鐵扇門主敗北！前往「通關」牌匾。", 4)
  end
  snd.enemy_die:stop()
  snd.enemy_die:play()
end

local function advance_to_level_2()
  load_level(2, { player = p })
end

function love.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  world.reload_level_list()
  font_body, font_large = load_ui_fonts()
  if font_body then love.graphics.setFont(font_body) end

  snd.jump = load_source("assets/audio/sfx_jump.ogg")
  snd.shoot = load_source("assets/audio/sfx_shoot.ogg")
  snd.land = load_source("assets/audio/sfx_land.ogg")
  snd.hit_enemy = load_source("assets/audio/sfx_hit_enemy.ogg")
  snd.enemy_die = load_source("assets/audio/sfx_enemy_die.ogg")
  snd.hurt = load_source("assets/audio/sfx_player_hurt.ogg")
  snd.pickup = load_source("assets/audio/sfx_charge_ping.ogg")

  music_stage = load_source("assets/audio/music_stage.ogg", "stream")
  music_title = load_source("assets/audio/music_title.ogg", "stream")
  music_stage:setVolume(0.55)
  music_title:setVolume(0.5)
  go_title()
end

local function shoot_pressed()
  return love.keyboard.isDown("x") or love.keyboard.isDown("j")
end

local function move_left()
  return love.keyboard.isDown("left") or love.keyboard.isDown("a")
end

local function move_right()
  return love.keyboard.isDown("right") or love.keyboard.isDown("d")
end

local function jump_held()
  return love.keyboard.isDown("space") or love.keyboard.isDown("z") or love.keyboard.isDown("k")
end

function love.keypressed(key)
  if key == "escape" then love.event.quit(); return end
  if state == "title" and (key == "return" or key == "space") then start_game(); return end
  if (state == "win" or state == "over") then
    if key == "return" or key == "space" then go_title()
    elseif key == "r" then start_game() end
    return
  end
  if state == "play" and p then
    if key == "r" then start_game(); return end
    if key == "1" then p:switch_weapon("qi_strike")
    elseif key == "2" and p:has_weapon("thunder_palm") then p:switch_weapon("thunder_palm") end
    if key == "space" or key == "z" or key == "k" then p:try_jump(snd.jump) end
    if key == "x" or key == "j" then p:try_shoot(bullets, snd.shoot) end
  end
end

local function update_camera()
  local ww, wh = love.graphics.getDimensions()
  if world.in_arena then
    local ax, ay, aw, ah = world.arena_bounds_px()
    cam_x = ax + aw / 2 - ww / 2
    cam_y = ay + ah / 2 - wh / 2
    cam_x = math.max(ax, math.min(cam_x, ax + aw - ww))
    cam_y = math.max(ay, math.min(cam_y, ay + ah - wh))
  else
    cam_x = p.x + p.w / 2 - ww / 2
    cam_y = p.y + p.h / 2 - wh / 2
    cam_x = math.max(0, math.min(cam_x, world.width_px() - ww))
    cam_y = math.max(0, math.min(cam_y, world.height_px() - wh))
  end
end

local function overlap(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

local function spawn_boss_projectile(proj)
  boss_bullets[#boss_bullets + 1] = proj
end

local function update_boss_bullets(dt)
  for i = #boss_bullets, 1, -1 do
    local b = boss_bullets[i]
    b.x = b.x + b.vx * dt
    b.y = b.y + b.vy * dt
    b.vy = b.vy + 380 * dt
    b.life = b.life - dt
    local dead = b.life <= 0
    if world.rect_hits_solid(b.x, b.y, b.w, b.h, "bullet") then dead = true end
    if not dead and p.invuln <= 0 and overlap(b.x, b.y, b.w, b.h, p.x, p.y, p.w, p.h) then
      p:hurt(b.dmg or 7)
      snd.hurt:stop(); snd.hurt:play()
      dead = true
    end
    if dead then table.remove(boss_bullets, i) end
  end
end

local function update_player_bullets(dt)
  for i = #bullets, 1, -1 do
    local b = bullets[i]
    b.x = b.x + b.vx * dt
    b.life = b.life - dt
    local dead = b.life <= 0
    if world.rect_hits_solid(b.x, b.y, b.w, b.h, "bullet") then dead = true end

    if not dead and boss and boss.alive then
      if overlap(b.x, b.y, b.w, b.h, boss.x, boss.y, boss.w, boss.h) then
        dead = true
        local mult = p:get_boss_damage_mult(b.weapon_id, boss.kind)
        local dmg = b.damage * mult
        local killed = boss:take_damage(dmg, b.weapon_id, 1)
        snd.hit_enemy:stop(); snd.hit_enemy:play()
        if killed then
          boss.alive = false
          on_boss_killed()
        elseif boss.kind == "iron_gate" and b.weapon_id == "qi_strike" then
          show_hint("氣功波難破鐵甲…改用霹靂掌（按 2）！", 1.5, 2.5)
        elseif boss.kind == "iron_gate" and b.weapon_id == "thunder_palm" then
          show_hint("霹靂掌克鐵甲！門主氣勢大衰！", 1.2, 2)
        end
      end
    end

    if not dead then
      for _, e in ipairs(enemies) do
        if e.alive and overlap(b.x, b.y, b.w, b.h, e.x, e.y, e.w, e.h) then
          dead = true
          if e:take_damage(b.damage) then
            e.alive = false
            snd.enemy_die:stop(); snd.enemy_die:play()
          else
            snd.hit_enemy:stop(); snd.hit_enemy:play()
          end
          break
        end
      end
    end
    if dead then table.remove(bullets, i) end
  end
end

function love.update(dt)
  if state ~= "play" or not p then return end

  stage_msg_t = math.max(0, stage_msg_t - dt)
  hint_msg_t = math.max(0, hint_msg_t - dt)
  hint_cd = math.max(0, hint_cd - dt)

  world.update_platforms(dt)

  p:update(dt, move_left(), move_right(), jump_held(), {
    jump = snd.jump, land = snd.land, pickup = snd.pickup, hurt = snd.hurt,
  })

  if shoot_pressed() then p:try_shoot(bullets, snd.shoot) end

  if not world.in_arena then
    for _, e in ipairs(enemies) do
      if e.alive then
        e:update(dt)
        if p.invuln <= 0 and overlap(p.x, p.y, p.w, p.h, e.x, e.y, e.w, e.h) then
          p:hurt(6)
          snd.hurt:stop(); snd.hurt:play()
        end
      end
    end
    if world.check_arena_entrance(p.x, p.y, p.w, p.h) then
      enter_arena()
    end
  else
    if boss and boss.alive then
      boss:update(dt, p, spawn_boss_projectile)
      if p.invuln <= 0 and overlap(p.x, p.y, p.w, p.h, boss.x, boss.y, boss.w, boss.h) then
        p:hurt(boss:contact_damage())
        snd.hurt:stop(); snd.hurt:play()
      end
    end
    if boss_defeated and world.check_arena_exit(p.x, p.y, p.w, p.h) then
      leave_arena()
      show_hint("離開決鬥圈，前往關隘。", 2.5)
    end
  end

  update_boss_bullets(dt)
  update_player_bullets(dt)
  update_camera()

  if not world.in_arena and world.check_flag(p.x, p.y, p.w, p.h) then
    if world.level_index == 1 then
      if boss_defeated then
        advance_to_level_2()
      else
        show_hint("需先於決鬥圈擊敗雷電真人。", 2)
      end
    elseif boss_defeated then
      state = "win"
      if music_stage then music_stage:stop() end
    else
      show_hint("鐵扇門主仍在決鬥圈等候！", 2.5)
    end
  end

  if p.hp <= 0 then
    state = "over"
    if music_stage then music_stage:stop() end
  end
end

local function buff_line()
  local parts = {}
  if p:has_buff("qinggong") then parts[#parts + 1] = "輕功" end
  if p:has_buff("thunder_charm") then parts[#parts + 1] = "雷符" end
  if p:has_buff("armor_break") then parts[#parts + 1] = "破甲" end
  if p:has_buff("iron_scroll") then parts[#parts + 1] = "鐵卷" end
  if #parts == 0 then return "寶物：無" end
  return "寶物：" .. table.concat(parts, " · ")
end

local function draw_hud()
  local ww = love.graphics.getWidth()
  love.graphics.setColor(0.08, 0.06, 0.05, 0.72)
  love.graphics.rectangle("fill", 6, 6, ww - 12, 86)
  love.graphics.setColor(0.95, 0.88, 0.75)
  love.graphics.print("氣血", 16, 12)
  love.graphics.rectangle("line", 58, 12, 120, 12)
  love.graphics.setColor(0.75, 0.15, 0.12)
  love.graphics.rectangle("fill", 60, 14, 116 * (p.hp / p.hp_max), 8)
  love.graphics.setColor(0.9, 0.85, 0.7)
  love.graphics.print("武功: " .. p:get_weapon_label() .. " (1/2)", 16, 32)
  love.graphics.print(buff_line(), 16, 50)
  love.graphics.print("X/J 發招 · Space/Z/K 躍 · 踩吊橋 · 避竹刺", 16, 68)
  if world.get_level() then
    love.graphics.printf(world.get_level().title, 220, 12, ww - 240, "center")
  end
  if world.in_arena then
    love.graphics.setColor(1, 0.75, 0.45)
    love.graphics.printf("── 決鬥圈中 ──", 0, 12, ww, "right")
  end
  if boss and boss.alive then Boss.draw_hp_bar(boss, cam_x, cam_y) end
  if p.weapon_msg_t > 0 then
    love.graphics.setColor(0.55, 0.95, 0.75)
    love.graphics.printf(p.weapon_msg, 0, 98, ww, "center")
  end
  if hint_msg_t > 0 then
    love.graphics.setColor(1, 0.88, 0.45)
    love.graphics.printf(hint_msg, 0, 122, ww, "center")
  end
  if stage_msg_t > 0 then
    love.graphics.setColor(1, 1, 1, 0.92)
    love.graphics.printf(stage_msg, 0, love.graphics.getHeight() * 0.32, ww, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

function love.draw()
  if state == "title" then
    if font_large then love.graphics.setFont(font_large) end
    love.graphics.setColor(0.12, 0.08, 0.06)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    love.graphics.setColor(0.92, 0.82, 0.65)
    love.graphics.printf(
      "江湖試煉\n\nEnter 開始（優先載入 levels/*.lua 自訂關卡）\n\n關卡編輯器：love . editor\n\n內建雙關：霹靂掌克鐵扇門主",
      0, 90, love.graphics.getWidth(), "center"
    )
    return
  end

  if font_body then love.graphics.setFont(font_body) end
  world.draw(cam_x, cam_y)
  world.draw_platforms(cam_x, cam_y)
  world.draw_pickups(cam_x, cam_y)

  if not world.in_arena then
    for _, e in ipairs(enemies) do e:draw(cam_x, cam_y) end
  end
  if boss then boss:draw(cam_x, cam_y) end

  for _, b in ipairs(boss_bullets) do
    if b.kind == "lightning" then
      love.graphics.setColor(0.45, 0.75, 1)
    else
      love.graphics.setColor(0.85, 0.45, 0.35)
    end
    love.graphics.rectangle("fill", b.x - cam_x, b.y - cam_y, b.w, b.h)
  end
  for _, b in ipairs(bullets) do
    local c = b.color or { 0.95, 0.88, 0.45 }
    love.graphics.setColor(c[1], c[2], c[3])
    love.graphics.rectangle("fill", b.x - cam_x, b.y - cam_y, b.w, b.h)
  end
  love.graphics.setColor(1, 1, 1)

  p:draw(cam_x, cam_y)
  draw_hud()

  if state == "win" then
    if font_large then love.graphics.setFont(font_large) end
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    love.graphics.setColor(0.55, 0.95, 0.65)
    love.graphics.printf(
      "名動江湖！\n霹靂掌破鐵扇，兩關皆過。\nEnter 回標題 · R 再闖",
      0, love.graphics.getHeight() / 2 - 50, love.graphics.getWidth(), "center"
    )
  elseif state == "over" then
    if font_large then love.graphics.setFont(font_large) end
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    love.graphics.setColor(1, 0.45, 0.4)
    love.graphics.printf(
      "力竭敗北…\nEnter 回標題 · R 再來",
      0, love.graphics.getHeight() / 2 - 40, love.graphics.getWidth(), "center"
    )
  end
end
