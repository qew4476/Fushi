## BUG-3524 · 句子循環未隨主動跳句更新目標
- **报告**：2026-10-25（用户：循環未解除時，跳到下一句應持續重複下一句）
- **真实性**：✅ 真 bug。`fushi/lib/src/media/video/video_player_controller.dart:5793` 的 `skipToCue` 原本只 seek，沒有更新 `_repeatingCue`；句尾仍按舊句目標回跳。
- **[x] ① 根因修复** — 主動跳句時同步移動循環目標，遞增 generation 作廢舊回呼，跳轉期間抑制循環重入；顯式關閉及換字幕沿用原生命週期。
- **[x] ② 自动化测试** — `fushi/test/media/video/video_sentence_repeat_test.dart` 新增下一句持續循環、上一句移動目標、在途循環起播失效三項行為測試；全檔 13 項通過（Flutter 3.47.6，exit 0）。
- **备注**：控制器測試已驗證；尚未在真實播放器 UI 上復測，不將單元測試視為設備驗證。還原上一輪誤改的快捷鍵長文案。
