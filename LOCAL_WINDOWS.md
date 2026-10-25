# Windows 本機開發與發佈

在專案根目錄的 PowerShell 執行：

```powershell
.\fushi setup    # 首次安裝 Flutter（讀取 .fvmrc）、VS C++/ATL、CMake、Rust、Inno Setup、vcpkg、protoc，解析依賴並打補丁
.\fushi dev      # 啟動 Windows 開發版，支援 Flutter hot reload
.\fushi build    # 編譯本體與原生元件、組裝完整 Windows 安裝檔
.\fushi release  # 先在本機 build，成功後將本次安裝檔與 SHA256 上傳到 GitHub Release
```

首次安裝 VS 可能需要 Windows UAC 與重新啟動；原生依賴初次編譯可能需一小時以上。需允許 Windows 開發人員模式（Flutter 插件 symbolic link）。`setup` 可重跑；自備 Flutter 可設 `FUSHI_FLUTTER`，版本必須與 `fushi/.fvmrc` 相同。自備 vcpkg 可用 `VCPKG_ROOT` 或 `build -VcpkgRoot C:\path\vcpkg`。

安裝檔放在 `dist/local-windows/`，旁邊的 `build.json` 記錄來源 commit 與 SHA256。`build` 要求工作目錄乾淨，`release` 要求建置 commit 已推到 origin，且 `gh auth login` 已登入。發佈預設為 prerelease、非 Latest，不覆蓋現有 tag；可指定 `.\fushi release -Tag local-windows-X.Y.Z.N`。tag 必須以 `local-windows-` 開頭，避免觸發既有多平台發布 workflow。只上傳本機檔案，不更新應用程式自動更新清單。未設定商用簽章，本機安裝檔無程式碼簽章。

本機設定與依賴不寫入版本庫；GitHub 權限使用既有 `gh` 登入。

`release` 每次都會先執行完整的 `build` 流程；建置失敗立即停止，不會使用舊安裝檔上傳。`release -VcpkgRoot C:\path\vcpkg` 會將指定的 vcpkg 路徑傳給建置流程。
