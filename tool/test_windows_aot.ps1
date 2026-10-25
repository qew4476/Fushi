[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$FlutterRoot)
$ErrorActionPreference = 'Stop'
$temporary = Join-Path ([System.IO.Path]::GetTempPath()) ('fushi-aot-test-' + [guid]::NewGuid().ToString('N'))
$fixture = Join-Path $temporary 'bin/cache/artifacts/engine/windows-x64-release/gen_snapshot.exe'
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
try {
    New-Item -ItemType Directory -Force (Split-Path -Parent $fixture) | Out-Null
    Copy-Item -LiteralPath (Join-Path $FlutterRoot 'bin/cache/artifacts/engine/windows-x64-release/gen_snapshot.exe') -Destination $fixture
    $bytes = [System.IO.File]::ReadAllBytes($fixture)
    $offset = [BitConverter]::ToInt32($bytes, 0x3c) + 24 + 72
    [Array]::Copy([BitConverter]::GetBytes([uint64]1048576), 0, $bytes, $offset, 8)
    [System.IO.File]::WriteAllBytes($fixture, $bytes)
    & "$PSScriptRoot/prepare_windows_aot.ps1" -FlutterRoot $temporary
    $patched = [System.IO.File]::ReadAllBytes($fixture)
    Assert-True ([BitConverter]::ToUInt64($patched, $offset) -eq 134217728) 'Small stack reserve was not increased.'
    & $fixture --version
    Assert-True ($LASTEXITCODE -eq 0) 'Patched executable no longer runs.'
    $hash = (Get-FileHash -LiteralPath $fixture).Hash
    & "$PSScriptRoot/prepare_windows_aot.ps1" -FlutterRoot $temporary
    Assert-True ((Get-FileHash -LiteralPath $fixture).Hash -eq $hash) 'Repeated preparation changed the executable.'
    [Array]::Copy([BitConverter]::GetBytes([uint64]268435456), 0, $patched, $offset, 8)
    [System.IO.File]::WriteAllBytes($fixture, $patched)
    & "$PSScriptRoot/prepare_windows_aot.ps1" -FlutterRoot $temporary
    Assert-True ([BitConverter]::ToUInt64([System.IO.File]::ReadAllBytes($fixture), $offset) -eq 268435456) 'Larger reserve was reduced.'
    $rejected = $false
    try { & "$PSScriptRoot/prepare_windows_aot.ps1" -FlutterRoot (Join-Path $temporary 'missing') } catch { $rejected = $true }
    Assert-True $rejected 'Missing artifact was silently accepted.'
    $localBuild = Get-Content -LiteralPath "$PSScriptRoot/local_windows.ps1" -Raw
    $prepareIndex = $localBuild.IndexOf("Invoke-Script 'tool/prepare_windows_aot.ps1'")
    $buildIndex = $localBuild.IndexOf("'build','windows','--release'")
    Assert-True ($prepareIndex -ge 0 -and $buildIndex -gt $prepareIndex) 'AOT preparation must precede release compilation.'
    Write-Host 'PASS: stack increase, executable launch, idempotence, larger reserve, missing artifact, build wiring.'
} finally {
    # This is the unique absolute temp directory created above, never a repository path.
    $resolvedTemporary = [System.IO.Path]::GetFullPath($temporary)
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedTemporary.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Test cleanup escaped the temp directory.' }
    if (Test-Path -LiteralPath $resolvedTemporary) { Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force }
}
