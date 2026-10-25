$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
function Invoke-Checked {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed (exit $LASTEXITCODE)" }
}
function Install-Package {
    param([string]$Id)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & winget list --id $Id -e --accept-source-agreements *> $null; $installed = $LASTEXITCODE -eq 0 }
    finally { $ErrorActionPreference = $previousPreference }
    if (-not $installed) {
        Invoke-Checked 'winget' @('install','--id',$Id,'-e','--silent','--accept-package-agreements','--accept-source-agreements')
    }
}
$version = (Get-Content "$root/fushi/.fvmrc" -Raw | ConvertFrom-Json).flutter
$sdk = Join-Path $env:USERPROFILE "flutter_sdk/flutter_$version"
if (-not (Test-Path "$sdk/bin/flutter.bat")) {
    Invoke-Checked 'git' @('clone','--depth','1','--branch',$version,'https://github.com/flutter/flutter.git',$sdk)
}
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs = if (Test-Path $vswhere) { (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.ATL Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Out-String).Trim() }
if (-not $vs) {
    $existingVs = if (Test-Path $vswhere) { (& $vswhere -latest -products '*' -property installationPath | Out-String).Trim() }
    if ($existingVs) {
        $installer = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/setup.exe"
        $process = Start-Process $installer -WindowStyle Hidden -Wait -PassThru -ArgumentList @('modify','--installPath',('"' + $existingVs + '"'),'--passive','--norestart','--add','Microsoft.VisualStudio.Workload.VCTools','--includeRecommended','--add','Microsoft.VisualStudio.Component.VC.ATL')
        if ($process.ExitCode -notin @(0,3010)) { throw "Visual Studio modification failed ($($process.ExitCode))" }
    } else {
        Invoke-Checked 'winget' @('install','--id','Microsoft.VisualStudio.2022.BuildTools','-e','--accept-package-agreements','--accept-source-agreements','--override','--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --add Microsoft.VisualStudio.Component.VC.ATL')
    }
}
Install-Package 'JRSoftware.InnoSetup'
Install-Package 'Kitware.CMake'
Install-Package 'Rustlang.Rustup'
Install-Package '7zip.7zip'
Install-Package 'GitHub.cli'
Install-Package 'Microsoft.NuGet'
$tools = Join-Path $env:LOCALAPPDATA 'FushiBuild'
$vcpkg = Join-Path $tools 'vcpkg'
if (-not (Test-Path "$vcpkg/.git")) {
    Invoke-Checked 'git' @('clone','https://github.com/microsoft/vcpkg.git',$vcpkg)
}
if (-not (Test-Path "$vcpkg/vcpkg.exe")) { Invoke-Checked "$vcpkg/bootstrap-vcpkg.bat" @('-disableMetrics') }
$protoc = Join-Path $tools 'protoc'
if (-not (Test-Path "$protoc/bin/protoc.exe")) {
    New-Item -ItemType Directory -Force $tools | Out-Null
    $zip = Join-Path $tools 'protoc-31.1.zip'
    Invoke-WebRequest 'https://github.com/protocolbuffers/protobuf/releases/download/v31.1/protoc-31.1-win64.zip' -OutFile $zip -UseBasicParsing
    if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne '70381b116ab0d71cb6a5177d9b17c7c13415866603a0fd40d513dafe32d56c35') { throw 'protoc checksum mismatch' }
    Expand-Archive $zip $protoc -Force
}
$env:FUSHI_FLUTTER = "$sdk/bin/flutter.bat"
$env:PATH = "$sdk/bin;$env:USERPROFILE/.cargo/bin;$env:ProgramFiles/CMake/bin;$protoc/bin;$([Environment]::GetEnvironmentVariable('Path','User'));$([Environment]::GetEnvironmentVariable('Path','Machine'));$env:PATH"
$env:VCPKG_ROOT = $vcpkg
Invoke-Checked $env:FUSHI_FLUTTER @('config','--enable-windows-desktop')
Invoke-Checked 'powershell' @('-NoProfile','-ExecutionPolicy','Bypass','-File',"$root/tool/bootstrap.ps1")
Invoke-Checked $env:FUSHI_FLUTTER @('doctor','-v')
Write-Host 'Setup complete. Run .\fushi dev or .\fushi build.'
