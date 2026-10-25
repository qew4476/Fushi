## BUG-3520 · local-windows-aot-stack
- **报告**：2026-10-25（用户：本机 `.\fushi release` 在 flutter_assemble 报 MSB8066）
- **真实性**：✅ 真 bug。`tool/local_windows.ps1:94` 直接运行 Windows release 编译，漏掉 CI 的 BUG-1589 snapshotter 栈准备；verbose 复现 `aot_elf_release` 中 gen_snapshot 以 -1073741571（0xC00000FD）退出。
- **[x] ① 已修复** — `tool/prepare_windows_aot.ps1` 通过 vswhere 发现含 C++ 工具的 VS（含 BuildTools），用 editbin 将 Windows x64 release snapshotter 栈保留提高到 128 MB 并回读 PE 验证；本机 build 在 precache 后、编译前执行，每次检测，覆盖 SDK 更新后的重置。
- **[x] ② 已加自动化测试** — `tool/test_windows_aot.ps1` 用真实 snapshotter 的临时副本验证小栈修正、可执行性、重复执行不改文件、保留更大栈、缺失产物失败和 build 接线顺序。
- **备注**：与 CI 同一工具链兼容方案；上游增加默认栈或本仓 AOT 深度下降后可移除。原始及修复后编译日志保存于本机 `.codex-test/windows-release-diagnosis/`。
