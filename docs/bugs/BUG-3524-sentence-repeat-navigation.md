## BUG-3524 · 句子循環未隨主動跳句更新目標
- **报告**：2026-10-25（用户澄清：僅 Ctrl+左右鍵切句更新循環；一般左右鍵維持時間 seek。Ctrl+左鍵跳前一句後循環目標未跟上）
- **真实性**：✅ 真 bug。`video_player_controller.dart` 原 `skipToCue` 循環分支走 `_rawSeekMs`，缺少循環回跳共用的普通 seek 落點保護；向後跳時舊位置可能已超過新句尾。另外跳句決策未把 `_repeatingCue` 當權威錨點，連按時會受在途位置影響。
- **[x] ① 根因修复** — 撤回 `seekRelative` 的循環切句分支，一般左右鍵恢復原時間 seek。循環下 Ctrl+左右跳句以循環目標為錨點，更新目標後共用 `_restartSentenceRepeat` 的 transport、generation 與 seek 落點保護；Ctrl+左鍵循環中不退化成時間 seek。
- **[x] ② 自动化测试** — `fushi/test/media/video/video_sentence_repeat_test.dart` 覆蓋一般方向鍵不切循環目標、Ctrl+左鍵遠距離倒跳及舊位置回報、連續倒跳後前跳與句尾重複；連同快捷鍵派發測試共 25 項通過（Flutter 3.47.6，exit 0）。
- **备注**：上一輪對一般方向鍵的需求理解有誤，本輪已撤回。尚未以新建置在真實播放器 UI 上復測。
