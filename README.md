# Finish Your Game Lab

這裡是 [Finish Your Game Lab](https://www.youtube.com/@FinishYourGameLab) 對應的專案工作區。

這個頻道會陪伴大家把遊戲做完，也會分享開發過程中的研究、取捨、失敗與完成品。這個 repository 會用來整理不同遊戲技術的實驗、原型和可公開分享的範例，讓觀眾可以一起追蹤開發脈絡。

## 內容方向

- PICO-8 遊戲原型與小型完整作品
- LÖVE 2D / Lua 遊戲開發研究
- Godot 遊戲系統、工具與實作紀錄
- C++ 遊戲開發、底層系統與效能研究
- 遊戲設計、玩法原型、開發日誌與影片素材整理

## 目錄規劃

目前建議用以下結構逐步整理內容：

```text
prototypes/     遊戲原型與實驗性作品
research/       技術研究、測試專案與筆記
tools/          輔助工具、腳本與流程自動化
episodes/       影片集數對應的素材、筆記或範例
assets/         可公開追蹤的小型素材或 placeholder
docs/           長篇文件、設計筆記與開發紀錄
```

大型輸出檔、錄影、截圖、build 結果與平台匯出檔通常不會提交到 Git；需要保留時可以放在外部儲存空間，或另外建立釋出版流程。

## 開發原則

- 以「完成遊戲」為核心，研究是為了推進可玩的作品。
- 每個 prototype 盡量保留簡短說明，讓觀眾能理解目標、操作方式與目前狀態。
- 技術實驗可以很小，但最好有清楚的問題意識與結論。
- 可以公開分享的素材才放進 repository；授權不明或檔案過大的素材不要提交。

## YouTube

頻道連結：<https://www.youtube.com/@FinishYourGameLab>

## 授權

著作權所有 © 2024–2026 finishyourgamelab、gogoapah。

本 repository 為 YouTube 頻道的公開輔助專案，採「程式碼／非程式碼」雙軌授權：

- **程式碼**（Lua、Python、`.p8` 檔中作者撰寫的 Lua/設定部分、shell 腳本、設定檔等）：採
  [BSD 3-Clause License](https://opensource.org/license/bsd-3-clause)（含標準的 non-endorsement 條款）。
- **非程式碼素材**（README、開發筆記、原創設計、原創美術、原創音訊等）：採
  [Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/)。
- **第三方素材**（字型、音訊等）：依各自原授權檔（例如 `prototypes/escape-from-dark-love2d/assets/fonts/` 與
  `prototypes/no-9to5-hero-love2d/fonts/` 下的 SIL Open Font License 字型），不受上述條款覆蓋。

歡迎 fork、大幅改寫、發行你自己的遊戲，包含**商業用途**。唯一硬性需求是
**保留署名（attribution）**，建議格式如下，可直接複製：

```text
Based on work by Finish Your Game Lab (https://www.youtube.com/@FinishYourGameLab).
Original repository: <repo URL placeholder>
Modifications: <briefly describe>
Code portions licensed under the BSD 3-Clause License.
Documentation and creative material licensed under CC BY 4.0.
```

**品牌邊界**：請勿使用「Finish Your Game Lab」、頻道名稱或作者姓名來暗示對你衍生作品的
背書、推薦、贊助或官方合作關係（這已是 BSD 3-Clause 第三條與 CC BY 4.0 Section
2(b)(2)/2(a)(6) 的硬性條款）。單純事實性署名（「改作自 Finish Your Game Lab」）完全 OK
且歡迎。

**AI 揭露**：本 repo 多數內容由 AI 輔助產出（"vibe coding"）。在現行美國著作權實務下，
純 AI 產出且缺乏充分人類創作貢獻的部分可能不受著作權保護，使用者可視為近 public
domain，**不必署名亦可使用**；上述授權僅在作者實際享有著作權的範圍內生效。完整說明
請見 [LICENSE](LICENSE) 中的「AI Disclosure」段落。

詳細條款與正式英文 legal code 請見 [LICENSE](LICENSE)。
