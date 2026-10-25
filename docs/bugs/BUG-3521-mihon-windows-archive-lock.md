## BUG-3521 · mihon-windows-archive-lock
- **报告**：2026-10-25（用户：本地 Windows 安装包构建失败）
- **真实性**：✅ 真 bug。原 `tool/mihon/build_desktop_runtime.ps1:109` 直接下载到跨进程共用缓存，随后原地 hash/解压；既无原子发布也无私有快照，缓存被独占时 Get-FileHash 直接失败，并可能读取另一构建尚未完成的下载。具体占用进程无法从日志确定。
- **[x] ① 已修复** — 同条目提交：`verified_archive.ps1` 先复制到构建私有路径；共享缓存占用或内容无效时独立下载，显式释放下载器后验证 SHA-256，最后同目录原子发布已验证缓存，不覆盖其他进程使用中的文件。
- **[x] ② 已加自动化测试** — `tool/mihon/test_verified_archive.ps1` 在 Windows PowerShell 5.1 实测通过：首次发布、离线缓存命中、FileShare.None 独占缓存、半成品缓存、错误 SHA 拒绝发布、临时文件清理。
- **备注**：未重新构建完整安装包；Flutter 编译在用户原日志已成功，CMake CMP0175 为独立开发警告。
