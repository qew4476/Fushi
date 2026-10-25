[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$FlutterRoot)
$ErrorActionPreference = 'Stop'
# BUG-1589: this application's AOT compilation exceeds gen_snapshot's default
# Windows stack reserve. Match CI until upstream increases the default reserve.
$snapshot = Join-Path $FlutterRoot 'bin/cache/artifacts/engine/windows-x64-release/gen_snapshot.exe'
if (-not (Test-Path -LiteralPath $snapshot)) { throw "Missing Windows release snapshotter: $snapshot. Run flutter precache --windows." }
function Get-StackReserve {
    param([string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    $reader = New-Object System.IO.BinaryReader($stream)
    try {
        $stream.Position = 0x3c
        $pe = $reader.ReadInt32()
        $stream.Position = $pe
        if ($reader.ReadUInt32() -ne 0x4550) { throw "Invalid PE image: $Path" }
        $stream.Position = $pe + 24
        if ($reader.ReadUInt16() -ne 0x20b) { throw "Expected PE32+ snapshotter: $Path" }
        $stream.Position = $pe + 24 + 72
        return $reader.ReadUInt64()
    } finally { $reader.Dispose() }
}
$reserve = 134217728
if ((Get-StackReserve $snapshot) -ge $reserve) {
    Write-Host 'Windows AOT snapshotter stack reserve already >= 128 MB.'
    return
}
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $vs) { throw 'Visual Studio C++ toolchain not found. Run .\fushi setup.' }
$editbin = Get-ChildItem "$vs/VC/Tools/MSVC/*/bin/Hostx64/x64/editbin.exe" | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $editbin) { throw 'editbin.exe not found in the Visual Studio C++ toolchain.' }
& $editbin.FullName /STACK:134217728 $snapshot
if ($LASTEXITCODE -ne 0) { throw "editbin failed on $snapshot (exit $LASTEXITCODE)" }
if ((Get-StackReserve $snapshot) -lt $reserve) { throw 'Windows AOT snapshotter stack reserve verification failed.' }
Write-Host "Raised Windows AOT snapshotter stack reserve to 128 MB: $snapshot"
