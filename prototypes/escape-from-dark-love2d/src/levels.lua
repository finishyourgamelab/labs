-- 三個懸疑潛行關卡。每關都遵循「先看／先聽／先躲，必要時短促交火」的設計：
-- 障礙物提供視線遮蔽、燈光讓玩家壓力恢復、敵人有固定巡邏路徑與視野錐。
--
-- 關卡資料表欄位說明：
--   id, name, subtitle      — UI 顯示
--   bgm                     — assets/audio 內的檔名（不含副檔名）
--   ambience                — 設定環境色調與壓力累積速率
--   world                   — 世界尺寸 { w, h }
--   spawn                   — 玩家出生點 { x, y }
--   lootGoal                — 抵達撤離區所需的最低物資值
--   raidLength              — 關卡時間（秒）
--   obstacles               — 牆面 / 家具，玩家、敵人、子彈都會被擋
--   crates                  — 可搜刮的箱子 { x, y, kind, label }
--   extracts                — 撤離區 { x, y, w, h, label }
--   lights                  — 光源 { x, y, radius, color }
--   enemies                 — 敵人配置 { kind, patrol = { {x, y}, ... }, sightRange, hearingRange }
--
-- kind 對應於 src/enemies.lua 的模板：raider / guard / drone / hound
-- 燈光 color 預設亮度低、偏黃；越深的關卡越冷越紅。

local M = {}

local LEVELS = {
  --
  -- LV1 - 第一夜・地下冷藏庫
  --
  {
    id = "lv1_basement",
    name = "第一夜・地下冷藏庫",
    subtitle = "教學潛行：紅燈與冷藏室之間，搜刮 $80 後從西側鐵捲門撤離。",
    bgm = "music_lv1_basement",
    ambience = {
      bg = { 0.06, 0.07, 0.08 },
      grid = { 0.10, 0.11, 0.12 },
      fog = { 0.05, 0.05, 0.07, 0.55 },
      stressRate = 4,    -- 黑暗中每秒壓力上升
      stressRecover = 6, -- 燈光下每秒壓力下降
    },
    world = { w = 2000, h = 1400 },
    spawn = { x = 1820, y = 1240 },
    lootGoal = 80,
    raidLength = 240,
    obstacles = {
      { x = 220, y = 220, w = 360, h = 160, label = "冷藏室 A" },
      { x = 760, y = 220, w = 320, h = 160, label = "冷藏室 B" },
      { x = 1280, y = 220, w = 320, h = 160, label = "倉儲" },
      { x = 220, y = 540, w = 240, h = 280, label = "壓縮機室" },
      { x = 640, y = 540, w = 460, h = 110, label = "輸送帶" },
      { x = 1280, y = 540, w = 460, h = 110, label = "輸送帶" },
      { x = 220, y = 940, w = 460, h = 90, label = "管線溝" },
      { x = 860, y = 920, w = 240, h = 200, label = "電箱" },
      { x = 1300, y = 880, w = 320, h = 240, label = "卸貨區" },
    },
    crates = {
      { x = 380, y = 480, kind = "ammo", label = "彈匣" },
      { x = 920, y = 460, kind = "medical", label = "醫療櫃" },
      { x = 1440, y = 480, kind = "stash", label = "辦公抽屜" },
      { x = 1180, y = 760, kind = "stash", label = "工具櫃" },
      { x = 540, y = 1100, kind = "ammo", label = "備用彈藥" },
      { x = 1620, y = 1080, kind = "safe", label = "保險箱" },
    },
    extracts = {
      { x = 60, y = 1180, w = 160, h = 140, label = "西側鐵捲門" },
    },
    lights = {
      { x = 320, y = 460, radius = 130, color = { 0.90, 0.32, 0.20 } },
      { x = 1100, y = 460, radius = 110, color = { 0.85, 0.55, 0.20 } },
      { x = 1500, y = 1080, radius = 140, color = { 0.78, 0.22, 0.18 } },
      { x = 200, y = 1240, radius = 120, color = { 0.42, 0.55, 0.92 } },
    },
    enemies = {
      {
        kind = "raider",
        patrol = { { x = 720, y = 760 }, { x = 1180, y = 760 }, { x = 1180, y = 880 }, { x = 720, y = 880 } },
        sightRange = 200,
        sightAngle = math.rad(70),
        hearingRange = 130,
      },
      {
        kind = "guard",
        patrol = { { x = 360, y = 740 }, { x = 360, y = 940 } },
        sightRange = 240,
        sightAngle = math.rad(60),
        hearingRange = 150,
      },
      {
        kind = "drone",
        patrol = { { x = 1700, y = 540 }, { x = 1700, y = 880 } },
        sightRange = 160,
        sightAngle = math.rad(120),
        hearingRange = 90,
      },
    },
  },

  --
  -- LV2 - 第二夜・被遺忘的太平間
  --
  {
    id = "lv2_morgue",
    name = "第二夜・被遺忘的太平間",
    subtitle = "聲音導向：黑暗會累積壓力，靠近油燈恢復理智，搜刮 $140 撤離。",
    bgm = "music_lv2_morgue",
    ambience = {
      bg = { 0.05, 0.06, 0.08 },
      grid = { 0.09, 0.09, 0.11 },
      fog = { 0.03, 0.04, 0.07, 0.72 },
      stressRate = 6,
      stressRecover = 5,
    },
    world = { w = 2200, h = 1500 },
    spawn = { x = 220, y = 220 },
    lootGoal = 140,
    raidLength = 270,
    obstacles = {
      { x = 360, y = 200, w = 380, h = 90, label = "停屍櫃 A" },
      { x = 360, y = 360, w = 380, h = 90, label = "停屍櫃 B" },
      { x = 360, y = 520, w = 380, h = 90, label = "停屍櫃 C" },
      { x = 920, y = 200, w = 90, h = 410, label = "解剖檯" },
      { x = 1100, y = 200, w = 90, h = 410, label = "藥品櫃" },
      { x = 1320, y = 200, w = 360, h = 110, label = "等候室" },
      { x = 1320, y = 410, w = 200, h = 200, label = "牧師室" },
      { x = 1700, y = 200, w = 260, h = 410, label = "鍋爐房" },
      { x = 220, y = 760, w = 460, h = 110, label = "走廊長椅" },
      { x = 800, y = 740, w = 800, h = 140, label = "中央走廊" },
      { x = 1700, y = 760, w = 260, h = 200, label = "備品間" },
      { x = 360, y = 1020, w = 380, h = 120, label = "焚化爐" },
      { x = 920, y = 1020, w = 380, h = 120, label = "通風井" },
      { x = 1480, y = 1020, w = 380, h = 120, label = "棺材儲藏" },
    },
    crates = {
      { x = 200, y = 540, kind = "medical", label = "急救包" },
      { x = 820, y = 320, kind = "stash", label = "鑰匙串" },
      { x = 1240, y = 360, kind = "ammo", label = "彈藥袋" },
      { x = 1620, y = 540, kind = "stash", label = "鍋爐配件" },
      { x = 540, y = 940, kind = "stash", label = "病例檔案" },
      { x = 1380, y = 940, kind = "ammo", label = "彈藥盒" },
      { x = 1820, y = 1060, kind = "safe", label = "院長保險箱" },
      { x = 460, y = 1300, kind = "medical", label = "嗎啡" },
      { x = 1160, y = 1300, kind = "stash", label = "金牙" },
    },
    extracts = {
      { x = 1980, y = 1280, w = 200, h = 200, label = "東南升降井" },
    },
    lights = {
      { x = 220, y = 220, radius = 140, color = { 0.95, 0.78, 0.30 } },
      { x = 1000, y = 700, radius = 120, color = { 0.78, 0.62, 0.30 } },
      { x = 1820, y = 980, radius = 110, color = { 0.85, 0.32, 0.22 } },
      { x = 540, y = 1240, radius = 130, color = { 0.30, 0.42, 0.80 } },
      { x = 1700, y = 1380, radius = 150, color = { 0.85, 0.58, 0.20 } },
    },
    enemies = {
      {
        kind = "raider",
        patrol = { { x = 820, y = 940 }, { x = 1500, y = 940 } },
        sightRange = 210,
        sightAngle = math.rad(70),
        hearingRange = 170,
      },
      {
        kind = "guard",
        patrol = { { x = 1620, y = 320 }, { x = 1620, y = 700 }, { x = 1880, y = 700 }, { x = 1880, y = 320 } },
        sightRange = 240,
        sightAngle = math.rad(55),
        hearingRange = 180,
      },
      {
        kind = "drone",
        patrol = { { x = 940, y = 200 }, { x = 940, y = 700 } },
        sightRange = 170,
        sightAngle = math.rad(140),
        hearingRange = 90,
      },
      {
        kind = "raider",
        patrol = { { x = 380, y = 1180 }, { x = 1340, y = 1180 } },
        sightRange = 200,
        sightAngle = math.rad(75),
        hearingRange = 160,
      },
    },
  },

  --
  -- LV3 - 第三夜・空懸聖堂
  --
  {
    id = "lv3_chapel",
    name = "第三夜・空懸聖堂",
    subtitle = "高壓收尾：守衛視野更遠、警報觸發援軍，搜刮 $200 啟動屋頂信標。",
    bgm = "music_lv3_chapel",
    ambience = {
      bg = { 0.06, 0.05, 0.08 },
      grid = { 0.08, 0.08, 0.10 },
      fog = { 0.04, 0.03, 0.06, 0.78 },
      stressRate = 8,
      stressRecover = 4,
    },
    world = { w = 2400, h = 1700 },
    spawn = { x = 1200, y = 1500 },
    lootGoal = 200,
    raidLength = 300,
    obstacles = {
      { x = 800, y = 160, w = 800, h = 160, label = "聖壇" },
      { x = 800, y = 380, w = 200, h = 380, label = "祭司席（左）" },
      { x = 1400, y = 380, w = 200, h = 380, label = "祭司席（右）" },
      { x = 240, y = 160, w = 360, h = 220, label = "鐘樓基座" },
      { x = 1800, y = 160, w = 360, h = 220, label = "唱詩臺" },
      { x = 240, y = 460, w = 200, h = 320, label = "壁龕" },
      { x = 1960, y = 460, w = 200, h = 320, label = "聖物櫃" },
      { x = 240, y = 880, w = 360, h = 150, label = "石棺 A" },
      { x = 800, y = 880, w = 800, h = 150, label = "中殿長椅" },
      { x = 1800, y = 880, w = 360, h = 150, label = "石棺 B" },
      { x = 240, y = 1140, w = 360, h = 200, label = "迴廊（西）" },
      { x = 1800, y = 1140, w = 360, h = 200, label = "迴廊（東）" },
      { x = 800, y = 1240, w = 200, h = 220, label = "懺悔室" },
      { x = 1400, y = 1240, w = 200, h = 220, label = "聖洗池" },
    },
    crates = {
      { x = 420, y = 280, kind = "stash", label = "捐款箱" },
      { x = 1980, y = 280, kind = "stash", label = "詩歌本櫃" },
      { x = 700, y = 600, kind = "ammo", label = "祭司彈藥" },
      { x = 1700, y = 600, kind = "ammo", label = "守衛彈匣" },
      { x = 1200, y = 540, kind = "medical", label = "聖油" },
      { x = 420, y = 980, kind = "stash", label = "石棺金器" },
      { x = 1980, y = 980, kind = "stash", label = "石棺金器" },
      { x = 1200, y = 980, kind = "safe", label = "聖物保險箱" },
      { x = 700, y = 1340, kind = "medical", label = "繃帶" },
      { x = 1700, y = 1340, kind = "medical", label = "繃帶" },
      { x = 1200, y = 1380, kind = "safe", label = "獻祭金庫" },
    },
    extracts = {
      { x = 1080, y = 60, w = 240, h = 90, label = "屋頂信標（搜刮 $200 後啟動）" },
    },
    lights = {
      { x = 1200, y = 220, radius = 160, color = { 0.95, 0.84, 0.40 } },
      { x = 320, y = 460, radius = 110, color = { 0.85, 0.62, 0.20 } },
      { x = 2080, y = 460, radius = 110, color = { 0.85, 0.62, 0.20 } },
      { x = 1200, y = 1180, radius = 140, color = { 0.85, 0.30, 0.22 } },
      { x = 1200, y = 1500, radius = 120, color = { 0.45, 0.55, 0.92 } },
    },
    enemies = {
      {
        kind = "guard",
        patrol = { { x = 1200, y = 220 }, { x = 1200, y = 540 } },
        sightRange = 280,
        sightAngle = math.rad(50),
        hearingRange = 200,
      },
      {
        kind = "guard",
        patrol = { { x = 320, y = 460 }, { x = 320, y = 880 }, { x = 700, y = 880 }, { x = 700, y = 460 } },
        sightRange = 260,
        sightAngle = math.rad(55),
        hearingRange = 200,
      },
      {
        kind = "guard",
        patrol = { { x = 2080, y = 460 }, { x = 2080, y = 880 }, { x = 1700, y = 880 }, { x = 1700, y = 460 } },
        sightRange = 260,
        sightAngle = math.rad(55),
        hearingRange = 200,
      },
      {
        kind = "raider",
        patrol = { { x = 700, y = 1100 }, { x = 1700, y = 1100 } },
        sightRange = 220,
        sightAngle = math.rad(70),
        hearingRange = 180,
      },
      {
        kind = "drone",
        patrol = { { x = 320, y = 1380 }, { x = 2080, y = 1380 } },
        sightRange = 180,
        sightAngle = math.rad(140),
        hearingRange = 110,
      },
      {
        kind = "raider",
        patrol = { { x = 1200, y = 1380 }, { x = 1200, y = 1620 } },
        sightRange = 220,
        sightAngle = math.rad(70),
        hearingRange = 180,
      },
    },
  },
}

function M.list()
  return LEVELS
end

function M.get(index)
  return LEVELS[index]
end

function M.count()
  return #LEVELS
end

return M
