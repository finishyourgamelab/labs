# Love2D 武俠原型 — 開發紀錄

摘要整理自 Cursor 匯出對話（2026-05-01）。下列內容已**不以本機使用者絕對路徑**表述，便於版本庫共用與避免不必要資訊揭露。

---

## 專案概要

在 `prototypes/no-9to5-hero-love2d` 建立 Love2D、類 Vampire Survivor 之試玩原型：

- `main.lua`：移動、自動攻擊、敵人生成、修為（XP）、升級三選一、HUD、結束與重開。
- `conf.lua`：視窗與 `identity` 設定。
- `README.md`：執行與操作說明。
- `fonts/`：繁體中文顯示用字型與授權檔（Noto Sans TC，OFL）。

遊戲內文案採**江湖／武俠**語境（初入江湖、心法、俠名等）。

---

## macOS：Love2D 執行方式

於**存放本 repo 的根目錄**執行：

```sh
love prototypes/no-9to5-hero-love2d
```

或在該原型資料夾內：

```sh
cd prototypes/no-9to5-hero-love2d
love .
```

若未將 `love` 加入 `PATH`，可直接呼叫 App Bundle 內執行檔（路徑依你的安裝位置調整），例如：

```sh
"/Applications/LOVE.app/Contents/MacOS/love" prototypes/no-9to5-hero-love2d
```

可選：將 `love.app` 移至 `/Applications/LOVE.app`，並以 `ln -sf` 建立 `love` 指令（必要時搭配 `sudo`）。Lua／Homebrew 僅為開發輔助，非執行遊戲必須。

---

## 繁體中文顯示

Love2D 預設字型不含 CJK，中文會成方塊或亂碼。解法為以 `love.graphics.newFont` 載入支援中文的字型，並在繪製前 `love.graphics.setFont`。

載入順序（見 `main.lua` 之 `FONT_PATHS`）優先使用專案內 `fonts/NotoSansTC-Regular.ttf`，其次為常見 macOS 系統字型路徑作後備。

字型來源可參考：[Noto Sans TC（Google Fonts）](https://fonts.google.com/noto/specimen/Noto+Sans+TC)。

建議使用 **static** 包內的固定字重（如 `NotoSansTC-Regular.ttf`）；Variable Font 在部分環境下相容性較差。

---

## 字型檔與授權

應於本原型目錄下維持：

- `fonts/NotoSansTC-Regular.ttf`
- `fonts/OFL.txt`

以利授權留存與跨機器建置。

---

## Cursor／VS Code 擴充（可選）

開發 Love2D／Lua 時可選用：Lua Language Server、Love2D 相關語法支援、Error Lens 等（依個人習慣）。

---

## 版本控制（參考）

本原型曾以單一 commit 納入 repo（含程式、README、字型與 OFL）；推送目標分支為 `main`。後續請以實際 `git log` 為準。
