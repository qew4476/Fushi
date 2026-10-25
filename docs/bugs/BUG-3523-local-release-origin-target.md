## BUG-3523 · local-release-origin-target
- **报告**：2026-10-25（用户：Windows installer 编译成功，GitHub Release POST 404；版本不得擅自提高）
- **真实性**：✅ 真 bug。原 `tool/local_windows.ps1:53` 无仓库参数调用 `gh repo view`，fork checkout 自动选到上游 `hajisensai/Fushi`（当前账户 READ），而 origin 实为 `qew4476/Fushi`（ADMIN）。实际命令验证了两者的权限差异。原远端 commit 检查还允许任意远端命中，并把 release 查询所有失败当作 tag 不存在。
- **[x] ① 已修复** — 本条目同次提交：显式从 origin 解析目标并于建置前检查写权限；所有 GitHub 操作指定目标；上传验证来源仓库、版本、文件名、SHA256/sidecar、origin refs 与目标 commit；API 错误直接停止。新增 `publish` 复用已验证安装包，仍拒绝覆盖 tag。遵照用户将语义版本恢复为 `3.0.1`，保留现有 build 后缀 `+1358`；在 CLAUDE.md 记录禁止自行提高语义版本。
- **[x] ② 已加自动化测试** — `tool/test_local_windows_release.ps1`：Windows PowerShell 5.1 通过 34 条断言，覆盖 fork 目标、权限、产物一致性、origin commit 边界、API 失败、重复发布保护、create 参数与入口预检顺序。
- **备注**：本机发布保持 prerelease / non-Latest，不改官网正式 Release；实际构建与发布验证见本轮执行结果。
