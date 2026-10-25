[CmdletBinding()]
param(
    [ValidateSet('setup','dev','build','release','publish','help')][string]$Command = 'help',
    [string]$Tag,
    [string]$VcpkgRoot = $env:VCPKG_ROOT
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'local_windows_release.ps1')
function Invoke-Checked {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed (exit $LASTEXITCODE)" }
}
function Invoke-Script {
    param([string]$Path, [string[]]$Arguments = @())
    Invoke-Checked 'powershell' (@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root $Path)) + $Arguments)
}
if ($Command -eq 'help') {
    Write-Host '.\fushi setup | dev | build | release | publish [-Tag local-windows-X.Y.Z.N]'
    Write-Host 'release builds then uploads; publish uploads the existing verified installer without rebuilding.'
    exit 0
}
Push-Location $root
try {
    if ($Command -eq 'setup') {
        Invoke-Script 'tool/setup_local_windows.ps1'
        exit 0
    }
    if ($Command -in @('release', 'publish')) {
        $releaseRepository = Get-LocalReleaseRepository -RepositoryRoot $root
        Write-Host "Release repository: $releaseRepository (origin)"
        if ($Command -eq 'publish') {
            Publish-LocalWindowsInstaller -RepositoryRoot $root -Repository $releaseRepository -Tag $Tag
            exit 0
        }
    }
    $version = (Get-Content (Join-Path $root 'fushi/.fvmrc') -Raw | ConvertFrom-Json).flutter
    if (-not $env:FUSHI_FLUTTER) {
        $sdk = Join-Path $env:USERPROFILE "flutter_sdk/flutter_$version"
        $env:FUSHI_FLUTTER = Join-Path $sdk 'bin/flutter.bat'
    }
    if (-not (Test-Path -LiteralPath $env:FUSHI_FLUTTER)) { throw 'Run .\fushi setup first, or set FUSHI_FLUTTER.' }
    $flutter = $env:FUSHI_FLUTTER
    $sdkInfo = & $flutter --version --machine | Out-String | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $sdkInfo.frameworkVersion -ne $version) { throw "Flutter $version is required." }
    $dart = Join-Path (Split-Path -Parent $flutter) 'dart.bat'
    $env:PATH = "$(Split-Path -Parent $flutter);$env:USERPROFILE\.cargo\bin;$env:LOCALAPPDATA\FushiBuild\protoc\bin;$([Environment]::GetEnvironmentVariable('Path','User'));$([Environment]::GetEnvironmentVariable('Path','Machine'));$env:PATH"
    $env:PROTOC_BINARY = Join-Path $env:LOCALAPPDATA 'FushiBuild/protoc/bin/protoc.exe'
    $out = Join-Path $root 'dist/local-windows'
    $manifestPath = Join-Path $out 'build.json'
    if ($Command -eq 'release') {
        $buildArguments = @('-Command','build')
        if ($VcpkgRoot) { $buildArguments += @('-VcpkgRoot',$VcpkgRoot) }
        Invoke-Script 'tool/local_windows.ps1' $buildArguments
        Publish-LocalWindowsInstaller -RepositoryRoot $root -Repository $releaseRepository -Tag $Tag
        exit 0
    }
    Invoke-Script 'tool/bootstrap.ps1'
    Push-Location (Join-Path $root 'fushi')
    try {
        if ($Command -eq 'dev') {
            if (-not $env:FUSHI_FFMPEG) { $env:FUSHI_FFMPEG = Join-Path $root 'third_party/ffmpeg-min/windows/ffmpeg.exe' }
            if (-not $env:FUSHI_FFPROBE) { $env:FUSHI_FFPROBE = Join-Path $root 'third_party/ffmpeg-min/windows/ffprobe.exe' }
            Invoke-Checked $flutter @('run','-d','windows','--no-pub')
            exit 0
        }
    } finally { Pop-Location }
    if ((& git status --porcelain | Out-String).Trim()) { throw 'Commit tracked/untracked source changes before building an uploadable installer.' }
    if (-not $VcpkgRoot) { $VcpkgRoot = Join-Path $env:LOCALAPPDATA 'FushiBuild/vcpkg' }
    Invoke-Script 'native/fushi_torrent/build_windows_dll.ps1' @('-VcpkgRoot',$VcpkgRoot)
    Invoke-Script 'native/fushi_p2p/build_windows_dll.ps1'
    Invoke-Script 'native/fushi_fsrs/build_windows_dll.ps1'
    Invoke-Script 'native/galgame_hook/tools/build_distribution.ps1' @('-RunTests')
    Invoke-Script 'tools/build_magpie_slim.ps1'
    $appVersion = [regex]::Match((Get-Content 'fushi/pubspec.yaml' -Raw),'(?m)^version:\s*(\S+)').Groups[1].Value.Split('+')[0]
    $commit = (& git rev-parse HEAD | Out-String).Trim()
    $originUrl = (& git remote get-url origin | Out-String).Trim()
    $sourceRepo = [regex]::Match($originUrl, 'github\.com[:/]([^/]+/[^/]+?)(?:\.git)?$')
    if (-not $sourceRepo.Success) { throw 'origin must identify the GitHub source repository for the bundled source notice.' }
    $env:FUSHI_SOURCE_REPO = $sourceRepo.Groups[1].Value
    $env:FUSHI_SOURCE_COMMIT = $commit
    $buildVersion = "$appVersion-local.$($commit.Substring(0,10))"
    $bundle = Join-Path $root 'fushi/build/windows/x64/runner/Release'
    Invoke-Checked $flutter @('precache','--windows')
    Invoke-Script 'tool/prepare_windows_aot.ps1' @('-FlutterRoot',(Split-Path -Parent (Split-Path -Parent $flutter)))
    Push-Location (Join-Path $root 'fushi')
    try { Invoke-Checked $dart @('tool/heavy.dart','--',$flutter,'build','windows','--release','--no-pub','--build-name',$appVersion,"--dart-define=FUSHI_BUILD_VERSION=$buildVersion") }
    finally { Pop-Location }
    Invoke-Script 'tool/mihon/build_desktop_runtime.ps1' @('-OutputDirectory',"$bundle/mihon_bridge")
    Invoke-Script 'native/galgame_hook/tools/install_into_bundle.ps1' @('-BundleDirectory',$bundle)
    Invoke-Script 'tools/bundle_7za.ps1' @('-BundleDirectory',$bundle)
    Invoke-Script 'native/fushi_anki_sync/build.ps1' @('-InstallDirectory',$bundle)
    Invoke-Checked $dart @('compile','exe','packages/fushi_cli/bin/fushi_cli.dart','-o',"$bundle/fushi_cli.exe")
    New-Item -ItemType Directory -Force "$bundle/magpie_bundle" | Out-Null
    Copy-Item 'dist/Magpie-hibiki-slim-x64.zip*' "$bundle/magpie_bundle" -Force
    Copy-Item 'third_party/ffmpeg-min/windows/*.exe' $bundle -Force
    $vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
    $vs = (& $vswhere -latest -products '*' -property installationPath | Out-String).Trim()
    $crt = Get-ChildItem "$vs/VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT" -Directory | Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $crt) { throw 'VC++ CRT redist not found.' }
    Copy-Item "$($crt.FullName)/*.dll" $bundle -Force
    foreach ($file in @('fushi.exe','flutter_windows.dll','fushidicts_ffi.dll','libaacs.dll','fushi_p2p.dll','fushi_fsrs.dll','fushi_torrent_ffi.dll','ffmpeg.exe','ffprobe.exe','msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll','fushi-anki-sync.exe','fushi_cli.exe','bluray/bdj/bdj_runtime.ps1')) {
        if (-not (Test-Path (Join-Path $bundle $file))) { throw "Missing payload: $file" }
    }
    $iscc = @("${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe","$env:LOCALAPPDATA/Programs/Inno Setup 6/ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $iscc) { throw 'Inno Setup compiler not found. Run .\fushi setup.' }
    New-Item -ItemType Directory -Force $out | Out-Null
    $probe = Join-Path $out 'compiler-probe.iss'
    @('[Setup]','AppName=Probe','AppVersion=1','DefaultDirName={tmp}\Probe',"OutputDir=$out",'OutputBaseFilename=compiler-probe','WizardStyle=modern dynamic windows11 hidebevels','WizardBackColor=#FEF7FF','Uninstallable=no') | Set-Content $probe -Encoding UTF8
    Invoke-Checked $iscc @($probe)
    Invoke-Checked $iscc @("/DAppVersion=$buildVersion","/DSourceDir=$bundle","/DOutputDir=$out",'fushi/windows/installer/fushi.iss')
    $fileName = "fushi-$buildVersion-windows-setup.exe"
    $hash = (Get-FileHash (Join-Path $out $fileName) -Algorithm SHA256).Hash
    "$hash  $fileName" | Set-Content (Join-Path $out "$fileName.sha256") -Encoding ASCII
    @{version=$buildVersion;commit=$commit;sourceRepo=$env:FUSHI_SOURCE_REPO;file=$fileName;sha256=$hash} | ConvertTo-Json | Set-Content $manifestPath -Encoding UTF8
    Write-Host "Installer: $(Join-Path $out $fileName)"
} finally { Pop-Location }
