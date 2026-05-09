# Escape From Dark - 任務紀錄

> 目的：當任務中斷時，下一個 session 可以從這份檔案接續工作。
> 每完成一段就更新狀態並 commit。狀態符號：`[ ] pending`、`[~] in progress`、`[x] done`。

## 設計目標

懸疑恐怖、淺度潛行（先看、先聽、先躲，必要時短促交火）、三段式關卡推進，
帶有生存遊戲式的物資管理（背包 / 重量 / 儲物箱 / 簡單合成）。
玩家是被困在黑暗設施裡的孤獨角色，三晚連續闖入鬧鬼地點，每一晚都比前一晚更危險。

### 三個關卡（依序通關）

1. **第一夜・地下冷藏庫** — 教學潛行：紅燈閃爍、冷藏室視線遮蔽、敵人少且巡邏範圍小，搜刮 `$80` 從西側鐵捲門撤離。
2. **第二夜・被遺忘的太平間** — 聲音導向：敵人聽覺敏銳，黑暗會累積壓力值，需要靠近油燈恢復理智，搜刮 `$140`。
3. **第三夜・空懸聖堂** — 高壓收尾：鐘樓守衛視野更遠、有警報觸發援軍、必須繞路避開開放迴廊，搜刮 `$200` 後啟動屋頂信標撤離。

## 任務分段（里程碑紀錄）

> Git：`Escape From Dark` 相關開發紀錄已整併為單一 commit（移除舊分支名與
> `duckov` 字樣的零碎訊息）。對齊進度請看  
> `git log --oneline -5 -- prototypes/escape-from-dark-love2d/`。

- [x] **T1–T2 骨架、字型、程序音訊**
  - Love2D 專案骨架、VT323 + NotoSansTC；`generate_audio.py` 支援 `--ogg` /
    `--mp3` / `--all`（repo 內僅追蹤 `.ogg`，`.mp3` 按需本機產生）。
- [x] **T3–T4 模組化與潛行核心**
  - `src/` 拆分；三關資料表；巡邏、視野錐、聽覺、警戒與迷你地圖。
- [x] **T5–T6 恐怖氛圍與音訊**
  - 壓力、燈光、紅眼、暗角；BGM 淡入淡出、`settings.lua` 持久化。
- [x] **T7 測試與文件**
  - 煙霧測試擴充、README / TASKS 流程。
- [x] **壓力與玩家視野迭代**
  - 光照下恢復、原地不升壓、扇形視野與迷霧。
- [x] **T8–T9 命名與授權**
  - 專案更名 **Escape From Dark**，路徑 `prototypes/escape-from-dark-love2d/`；
    **整個 lab repo** 以根目錄 `LICENSE` 為準（無本子目錄獨立 LICENSE）。
- [x] **T10 敵我視野平衡**
  - 敵人 `sightRange` 不高於玩家站立視野距離。
- [x] **T11 物資系統**
  - `items.lua` / `inventory.lua`；背包重量、儲物箱、合成、撤離估價；煙霧 22 項。

## 接續工作的方法

1. 進到 `prototypes/escape-from-dark-love2d/`。
2. 看這份 `TASKS.md` 找到第一個非 `[x]` 的項目。
3. 看 `git log --oneline -- prototypes/escape-from-dark-love2d/` 對齊進度。
4. 如果未完成的子任務有 `TODO:` 註記在程式碼裡，用 grep 搜尋。
5. 完成一段就把該行改 `[x]` 並 commit。

## 已知的測試指令

```sh
# 自動煙霧測試（22 項）
love prototypes/escape-from-dark-love2d --smoke-test

# 一般遊玩
love prototypes/escape-from-dark-love2d

# 重新產生音訊
python3 prototypes/escape-from-dark-love2d/assets/audio_src/generate_audio.py --mp3
python3 prototypes/escape-from-dark-love2d/assets/audio_src/generate_audio.py --all
```

## 後續可選擴充（留給下個 session）

- T12 結算畫面：加入「下一夜」選項，串聯三關卡形成連續戰役（含累計帶出物資金額）。
- T13 跨關儲物箱：本地端 `progress.lua` 讓儲物箱跨夜保留，建立「家」的概念。
- T14 重量影響移動：背包越重移動越慢、噪音越大。
- T15 控制器支援：把鍵盤輸入抽象成 input 模組，再加上 gamepad。
- T16 動畫：玩家走路 / 開槍動畫、敵人受傷閃爍。
- T17 音訊：依警戒等級切換 BGM 緊張版（已有 alarm 變數可串）。
- T18 拖曳合成：背包面板支援 mouse hover / drag / drop。
