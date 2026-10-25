## BUG-3522 · mihon-windows-long-path-cleanup
- **报告**：2026-10-25（用户：Windows 安装包在 Gradle 成功后失败）
- **真实性**：✅ 真 bug。原 `tool/mihon/build_desktop_runtime.ps1:235` 用普通路径递归删除临时树；Kotlin 反引号测试名生成的 class 文件全路径超过 MAX_PATH，Windows PowerShell 5.1 报 DirectoryNotFoundException，finally 的清理错误令已成功的运行时构建退出 1。使用同名 class、277 字符路径实测复现相同报错。
- **[x] ① 已修复** — 本条目同次提交：引入 `Remove-BuildTree`，先校验绝对目标位于指定父目录内，再以 Windows 扩展长度路径执行存在检查及删除；工作目录与旧输出备份均接入。不吞异常，不跨 shell 删除。
- **[x] ② 已加自动化测试** — `tool/mihon/test_remove_build_tree.ps1` 在 Windows PowerShell 5.1 通过：原错误复现、长路径清理、已不存在目录、拒绝父目录自身与前缀相似兄弟路径。`test_verified_archive.ps1` 回归通过。
- **备注**：未重建完整安装包；Gradle configuration cache 建议与 jlink --compress 棄用警告不导致本次失败。
