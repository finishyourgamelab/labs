-- 物品定義表。每個 item 用 string id 索引，欄位：
--   name     UI 顯示名稱
--   short    HUD 速覽用簡短名稱
--   weight   單個重量（公斤）
--   stackMax 同格最大堆疊數
--   kind     "consumable" / "ammo" / "valuable" / "key" / "material"
--   value    估價（用於撤離結算）
--   color    UI 圖示色
--   onUse    如果是 consumable，使用時對 player 套用的閉包 (player) → boolean
--   description 中文說明（背包提示）
local M = {}

M.DEFS = {
  bandage = {
    name = "繃帶", short = "BD", weight = 0.2, stackMax = 6,
    kind = "consumable", value = 6, color = { 0.96, 0.92, 0.78 },
    description = "回血 18 / 不消除壓力。可合成醫療包。",
    onUse = function(p)
      if p.hp >= p.maxHp then return false end
      p.hp = math.min(p.maxHp, p.hp + 18)
      return true
    end,
  },
  medkit = {
    name = "醫療包", short = "MK", weight = 0.6, stackMax = 3,
    kind = "consumable", value = 22, color = { 0.96, 0.32, 0.30 },
    description = "回血 38 並小幅降低壓力。可由 2 繃帶合成。",
    onUse = function(p)
      p.hp = math.min(p.maxHp, p.hp + 38)
      p.stress = math.max(0, p.stress - 12)
      return true
    end,
  },
  pill = {
    name = "鎮靜劑", short = "PL", weight = 0.1, stackMax = 8,
    kind = "consumable", value = 8, color = { 0.55, 0.42, 0.92 },
    description = "立即降壓 35，但不回血。",
    onUse = function(p)
      if p.stress <= 0 then return false end
      p.stress = math.max(0, p.stress - 35)
      return true
    end,
  },
  ammo_pistol = {
    name = "9mm 彈藥", short = "9MM", weight = 0.05, stackMax = 60,
    kind = "ammo", value = 1, color = { 0.95, 0.84, 0.32 },
    description = "手槍彈藥。使用後直接補進子彈槽。",
    onUse = function(p)
      if p.ammo >= p.maxAmmo then return false end
      p.ammo = math.min(p.maxAmmo, p.ammo + 6)
      return true
    end,
  },
  scrap = {
    name = "金屬廢料", short = "SC", weight = 0.4, stackMax = 8,
    kind = "material", value = 3, color = { 0.55, 0.55, 0.55 },
    description = "可合成 9mm 彈藥（3 個 → 12 發）。",
  },
  cloth = {
    name = "破布", short = "CL", weight = 0.15, stackMax = 10,
    kind = "material", value = 2, color = { 0.62, 0.46, 0.30 },
    description = "可合成繃帶（2 個 → 1 繃帶）。",
  },
  battery = {
    name = "舊電池", short = "BT", weight = 0.3, stackMax = 6,
    kind = "valuable", value = 14, color = { 0.30, 0.78, 0.95 },
    description = "撤離點高價回收物。",
  },
  goldring = {
    name = "金戒指", short = "$$", weight = 0.05, stackMax = 12,
    kind = "valuable", value = 28, color = { 0.96, 0.78, 0.20 },
    description = "撤離點高價回收物。",
  },
  document = {
    name = "機密文件", short = "DOC", weight = 0.1, stackMax = 4,
    kind = "valuable", value = 32, color = { 0.85, 0.30, 0.25 },
    description = "撤離點高價回收物，第三夜的關鍵物。",
  },
  keycard = {
    name = "通行卡", short = "KEY", weight = 0.02, stackMax = 1,
    kind = "key", value = 0, color = { 0.36, 0.92, 0.55 },
    description = "未來關卡解鎖用（暫保留）。",
  },
}

-- 合成配方：input table → output { id, count }
M.RECIPES = {
  {
    id = "craft_medkit",
    name = "繃帶 ×2 → 醫療包",
    inputs = { { id = "bandage", count = 2 } },
    output = { id = "medkit", count = 1 },
  },
  {
    id = "craft_bandage",
    name = "破布 ×2 → 繃帶",
    inputs = { { id = "cloth", count = 2 } },
    output = { id = "bandage", count = 1 },
  },
  {
    id = "craft_ammo",
    name = "金屬廢料 ×3 → 9mm 彈藥 ×12",
    inputs = { { id = "scrap", count = 3 } },
    output = { id = "ammo_pistol", count = 12 },
  },
}

-- 戰利品箱掉落表。crate.kind ↔ 隨機掉落清單（id, min, max, weight）
-- weight 越大越容易抽到。每次搜刮會抽 2-3 個 stack。
M.LOOT_TABLES = {
  medical = {
    rolls = { 1, 3 },
    pool = {
      { id = "bandage", min = 1, max = 3, weight = 5 },
      { id = "medkit",  min = 1, max = 1, weight = 2 },
      { id = "pill",    min = 1, max = 2, weight = 3 },
      { id = "cloth",   min = 1, max = 2, weight = 4 },
    },
  },
  ammo = {
    rolls = { 1, 3 },
    pool = {
      { id = "ammo_pistol", min = 6, max = 18, weight = 6 },
      { id = "scrap",       min = 1, max = 3,  weight = 4 },
      { id = "bandage",     min = 1, max = 1,  weight = 2 },
    },
  },
  stash = {
    rolls = { 2, 3 },
    pool = {
      { id = "cloth",       min = 1, max = 3, weight = 5 },
      { id = "scrap",       min = 1, max = 3, weight = 5 },
      { id = "battery",     min = 1, max = 2, weight = 3 },
      { id = "goldring",    min = 1, max = 1, weight = 2 },
      { id = "ammo_pistol", min = 4, max = 10, weight = 3 },
      { id = "bandage",     min = 1, max = 2, weight = 3 },
    },
  },
  safe = {
    rolls = { 2, 4 },
    pool = {
      { id = "goldring", min = 1, max = 3, weight = 5 },
      { id = "battery",  min = 1, max = 2, weight = 4 },
      { id = "document", min = 1, max = 1, weight = 3 },
      { id = "medkit",   min = 1, max = 2, weight = 3 },
      { id = "ammo_pistol", min = 8, max = 18, weight = 3 },
    },
  },
}

function M.def(id)
  return M.DEFS[id]
end

function M.recipes()
  return M.RECIPES
end

function M.lootTable(kind)
  return M.LOOT_TABLES[kind] or M.LOOT_TABLES.stash
end

return M
