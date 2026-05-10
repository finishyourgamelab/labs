# Escape From Dark - Love2D

一個 LÖVE 2D 俯視角懸疑恐怖潛行撤離原型。玩家扮演被困在黑暗設施裡的小角色，
連續三晚潛入三個鬧鬼地點，**先看、先聽、先躲**，必要時才和敵人短促交火，
搜刮足夠物資後抵達撤離點。

> 本專案是 [finishyourgamelab](https://www.youtube.com/@finishyourgamelab) YouTube
> 頻道遊戲開發過程的紀錄分享。授權依 repository 根目錄 [LICENSE](../../LICENSE)
> ——程式碼採 BSD 3-Clause、非程式碼素材採 CC BY 4.0、第三方素材依各自授權檔。

## 執行

```sh
love prototypes/escape-from-dark-love2d
```

或在此資料夾內執行：

```sh
love .
```

## 測試

```sh
love prototypes/escape-from-dark-love2d --smoke-test
```

煙霧測試會逐一建立三個關卡，檢查：
1. 主選單能渲染
2. 三關卡都能載入並繪製一幀
3. 子彈擊倒敵人
4. 撤離流程（站在撤離區並按 E 通關）
5. 致命傷害結束關卡
6. 視野錐：敵人面對玩家會偵測
7. 聽覺：玩家開槍後鄰近敵人會被吸引
8. 蹲伏降噪：壓低噪音時不被聽見
9. 醫療包按 Q 回血並消耗
10. 主選單方向鍵選關 + Enter 開始
11. 音訊系統 update 不崩潰
12. 站在燈光中心，stress 會下降
13. 站在燈光半徑一半處，stress 仍會下降
14. alarm=1 + 強光下，stress 仍會下降（強光壓過警報懲罰）
15. 黑暗中站定不動，stress 不會上升
16. 玩家視野扇形：前方可見、後方不可見、近身周圍仍可見
17. 敵人最大視野距離 ≤ 玩家站立視野（460），三關都驗證
18. 搜刮箱子會把物品塞進背包
19. 背包估價會即時刷新到 `loot`（撤離條件根據估價）
20. 合成：2 繃帶 → 1 醫療包
21. 儲物箱：靠近按 `F` 開啟，`Space` 跨倉移動 stack
22. 重量上限：超重時無法再塞入

## 操作

| 鍵位 | 功能 |
| --- | --- |
| `WASD` / 方向鍵 | 移動 |
| `Shift` | 衝刺（消耗體力，噪音極大） |
| `Ctrl` / `C` | 蹲伏（速度 -55%，被聽到的距離 -45%） |
| 滑鼠移動 | 瞄準 + 視野朝向（玩家也只看得到視野扇形內的敵人） |
| 滑鼠左鍵 / `Space` | 射擊（噪音爆表，會驚動全圖警戒） |
| `E` | 持續按住搜尋箱子 / 觸發撤離 |
| `Q` | 快速使用醫療包（沒有則用繃帶） |
| `X` | 服用鎮靜劑（降壓） |
| `G` | 一鍵合成醫療包（2 繃帶） |
| `Tab` | 開啟 / 關閉背包面板（內含合成頁） |
| `F` | 靠近儲物箱時開啟存取面板（`←/→` 切換、`Space` 移動 stack） |
| `M` | 靜音切換（會存檔） |
| `[` / `]` | 主音量 -/+（會存檔） |
| `1` / `2` / `3` | 主選單關卡選擇 |
| `Enter` / `Space` | 主選單開始遊戲 |
| `R` | 失敗後重玩本關 |
| `B` | 失敗 / 通關後回主選單 |
| `N` | 通關後進入下一夜 |
| `Esc` | 離開 |

## 三個關卡設計

| 夜 | 關卡 | 關卡目標 | 重點機制 |
| --- | --- | --- | --- |
| 1 | **地下冷藏庫** | 搜刮 $80，從西側鐵捲門撤離 | 紅燈閃爍視線遮蔽、敵人少且巡邏範圍小，是教學潛行 |
| 2 | **被遺忘的太平間** | 搜刮 $140，從東南升降井撤離 | 敵人聽覺敏銳、壓力上升快、需依賴油燈恢復理智 |
| 3 | **空懸聖堂** | 搜刮 $200，啟動屋頂信標撤離 | 守衛視野超遠、開放迴廊危險、警報觸發援軍 |

## 懸疑恐怖潛行系統

- **玩家視野**：以滑鼠朝向為中心的扇形，蹲伏會收短距離但張開角度（探視）、
  奔跑會拉長距離但收窄角度（隧道視）；視野外的敵人不會被繪製，只能靠
  腳步聲與環境提示判斷。近身 90px 內仍可全周圍感知（背後也看得到）。
- **視野錐（敵人）**：敵人視野以扇形顯示，依警戒等級變色（黃→橙→紅）。
  視野與聽覺都會被牆面阻擋。
- **聽覺**：玩家移動有持續噪音、開槍會推到 1.0，蹲伏直接壓到 0.08。
  敵人聽到後會衝向「最後已知位置」。
- **警戒**：可見會快速上升、聽見會慢慢上升，2.0 進入戰鬥；任一敵人達到
  戰鬥就把全關卡 ALARM 推到 1，會週期性從邊緣呼叫援軍。
- **壓力值（理智）**：黑暗中持續累積、靠近燈光會回復；壓力到頂會直接
  「精神崩潰」失敗，並且高壓玩家連走路都更響（心慌的人聲息暴露自己）。
- **燈光呼吸**：每盞燈用低頻 sin 波動、紅燈額外高頻閃爍，模擬故障日光燈。
- **黑暗中的敵人**：光照低時敵人眼睛改用紅色脈衝光點。
- **暗角**：低 hp / 高壓力會在螢幕邊緣堆出血色 vignette。
- **音訊**：BGM 進關卡會淡入；心跳依壓力 / 低 hp 自動觸發；高壓會出現
  低語音效。設定（音量 / 靜音）寫入 LÖVE save 目錄。

## 物資系統（生存遊戲式）

- **背包**：16 格、30kg 重量上限。物品有重量、堆疊上限、估價。
- **儲物箱**：每關出生點旁有一個（綠色鐵箱）。`F` 靠近開啟，可以
  跨倉移動 stack。**注意：本原型每關獨立，儲物箱不跨關保留。**
- **箱子搜刮**：按住 `E` 0.7 秒，會根據箱子類型（彈藥 / 醫療 / 抽屜 /
  保險箱）從對應 loot table 隨機抽取 2-4 個 stack。`9mm` 彈藥會
  自動補進槍械彈匣，其餘進背包。
- **合成**：背包面板 `Tab` → `→` 切到「合成」頁。
  - `2 繃帶 → 1 醫療包`（也可在 HUD 直接按 `G` 一鍵）
  - `2 破布 → 1 繃帶`
  - `3 金屬廢料 → 12 發 9mm`
- **撤離條件**：`loot` 改為「背包估價即時值」，當估價 ≥ 關卡 lootGoal
  時撤離點才會啟動。彈藥不計入估價以避免刷分。
- **取捨**：背包格數 / 重量上限 / 物品估價密度（金戒指最划算、文件
  其次、電池中等）共同決定玩家在三關各要帶什麼東西回家。

## 專案結構

```
prototypes/escape-from-dark-love2d/
├── main.lua            # 入口、love callbacks、scene 切換、煙霧測試
├── conf.lua
├── README.md
├── TASKS.md            # 任務分段紀錄（中斷接續用）
├── src/
│   ├── util.lua        # 共用工具
│   ├── fonts.lua       # 字型載入
│   ├── audio.lua       # 音訊系統（優先 .ogg，見資產說明）
│   ├── enemies.lua     # 敵人模板
│   ├── levels.lua      # 三關卡資料表
│   ├── items.lua       # 物品定義 / 合成式 / loot table
│   ├── inventory.lua   # 背包資料模型 / 重量 / 合成 / 跨倉移動
│   └── scenes/
│       ├── menu.lua    # 主選單
│       └── play.lua    # 遊玩場景
└── assets/
    ├── fonts/          # NotoSansTC + VT323（含 OFL 授權）
    ├── audio/          # 4 軌 BGM + 13 SFX（.ogg；另可用腳本產 .mp3）
    └── audio_src/
        └── generate_audio.py
```

## 字型與音訊

- 字型放在 `assets/fonts/`，包含 `NotoSansTC`（中文，OFL）與 `VT323`
  （8-bit 風格英文，OFL）。
- 音效與音樂放在 `assets/audio/`，為 **`.ogg`**（LÖVE 執行時優先載入）。
  若需要對外分享 `.mp3`，請執行下方腳本用 lameenc 另產（不進 Git，縮減 repo 體積）。
- `assets/audio_src/generate_audio.py` 可重現產生 8-bit 恐怖風格音訊：

```sh
# 只產 mp3
python3 prototypes/escape-from-dark-love2d/assets/audio_src/generate_audio.py --mp3
# 兩種都要
python3 prototypes/escape-from-dark-love2d/assets/audio_src/generate_audio.py --all
# 依賴
pip3 install --user numpy soundfile lameenc
```

## 任務紀錄與中斷接續

請看 [`TASKS.md`](TASKS.md)。每段任務都有對應的 commit；如果某個
session 被中斷，下一個 session 可以打開 `TASKS.md` 從第一個未完成
的項目接續。

## 授權

著作權所有 © 2024–2026 finishyourgamelab、gogoapah。

本目錄依 repo 根目錄 [LICENSE](../../LICENSE)：程式碼採
[BSD 3-Clause](https://opensource.org/license/bsd-3-clause)、非程式碼素材
採 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)；第三方素材
（如 `assets/fonts/` 下的 SIL Open Font License 字型，以及由
`assets/audio_src/generate_audio.py` 程序產生的 `.ogg` 檔）依各自原授權檔，
不受本條款覆蓋。詳細條款（含 attribution 範例與 AI Disclosure）請見根目錄
[LICENSE](../../LICENSE)。
