## BUG-3524 · 影片續播時 ASS／VTT 副字幕消失
- **报告**：2026-10-25（用户：影片重開續播只顯示主字幕）
- **真实性**：✅ 真 bug（代码路径确认）。`fushi/lib/src/pages/implementations/video_fushi/subtitle.part.dart:2116` 恢复远端副字幕时固定使用 `.srt`；手选使用 `track.fileName`。服务器保留原格式下载，`video_fushi_page.dart:5110` 按扩展名选解析器，ASS／VTT 被误交给 SRT parser 后为空而跳过。
- **[x] ① 已修复** — 恢复时读取持久化轨号对应的元数据，使用该轨 `fileName`，与手选和主字幕恢复一致；缺少文件名时保留原有 SRT 回退。提交见本文件随附的修复提交。
- **[x] ② 已加自动化测试** — `fushi/test/pages/video_secondary_subtitle_restore_format_test.dart`，守住恢复路径按轨元数据选文件名；页面私有恢复方法依赖真实播放器与远端服务，使用源码守卫。
- **备注**：尚未使用真实媒体服务器肉眼复测原始路径；需 ASS／VTT 副字幕样本验证。
