## BUG-3524 · 句子循環未隨主動跳句更新目標
- **报告**：2026-10-25（用户：循環未解除時，跳到下一句應持續重複下一句；方向鍵仍被原循環拉回，上一句未立即循環）
- **真实性**：✅ 真 bug。`fushi/lib/src/pages/implementations/video_fushi_page.dart:7430` 的一般左右鍵呼叫 `seekRelative`，原修復只涵蓋 `skipToCue`，時間 seek 未改變 `_repeatingCue`，因此向前被拉回、向後播回舊句才循環。Ctrl+左鍵也可能因遠距離退化成時間 seek。
- **[x] ① 根因修复** — 循環啟用時，`video_player_controller.dart` 的 `seekRelative` 按方向走相鄰句跳轉並移動循環目標；Ctrl+左鍵禁止遠句時間退化。關閉循環後恢復既有時間 seek。沿用原跳句 generation 作廢舊回呼及在途保護。
- **[x] ② 自动化测试** — `fushi/test/media/video/video_sentence_repeat_test.dart` 補一般左右鍵 transport、Ctrl+左鍵遠句與關閉後時間 seek 測試；與 `video_player_shortcuts_dispatch_test.dart` 合跑 24 項通過（Flutter 3.47.6，exit 0），全量 analyze 無問題。
- **备注**：尚未以新建置在真實播放器 UI 上復測，不將控制器與快捷鍵測試視為設備驗證。上一輪只測句子跳轉，漏掉一般方向鍵的時間 transport 路徑。
