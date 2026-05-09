-- 敵人模板。實際運行時的敵人實體在 src/scenes/play.lua 內生成。
local M = {}

M.TEMPLATES = {
  raider = {
    hp = 46, speed = 78, radius = 18, damage = 11, value = 12,
    color = { 0.78, 0.26, 0.22 },
    patrolSpeed = 0.55,    -- 巡邏速度倍率
    chaseSpeed = 1.10,     -- 警戒中追擊速度倍率
    fireCooldown = 1.4,    -- 射擊間隔
    bulletDamage = 9,
    bulletSpeed = 540,
    fov = math.rad(70),
    awareness = 1.0,
  },
  guard = {
    hp = 78, speed = 60, radius = 22, damage = 18, value = 24,
    color = { 0.92, 0.55, 0.20 },
    patrolSpeed = 0.45,
    chaseSpeed = 0.95,
    fireCooldown = 1.7,
    bulletDamage = 16,
    bulletSpeed = 580,
    fov = math.rad(55),
    awareness = 1.4,
  },
  drone = {
    hp = 26, speed = 132, radius = 14, damage = 6, value = 8,
    color = { 0.78, 0.78, 0.86 },
    patrolSpeed = 0.85,
    chaseSpeed = 1.45,
    fireCooldown = 0.85,
    bulletDamage = 5,
    bulletSpeed = 620,
    fov = math.rad(135),
    awareness = 1.6,
  },
}

function M.template(kind)
  return M.TEMPLATES[kind] or M.TEMPLATES.raider
end

return M
