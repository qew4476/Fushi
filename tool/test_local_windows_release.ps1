$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/local_windows_release.ps1"
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('fushi-release-test-' + [guid]::NewGuid().ToString('N'))
$script:checks = 0
function Assert-True { param([bool] $Condition, [string] $Message) if (-not $Condition) { throw $Message }; $script:checks++ }
function Reset-Mocks {
    $script:origin = 'https://github.com/qew4476/Fushi.git'
    $script:permission = 'ADMIN'; $script:authFails = $false
    $script:originContains = $true; $script:apiFails = $false; $script:commitFails = $false
    $script:tags = @(); $script:calls = @(); $script:createFails = $false
}
function git {
    $a = @($args); $script:calls += ,@('git', $a)
    $global:LASTEXITCODE = 0
    if ($a -contains 'get-url') { return $script:origin }
    if ($a -contains 'fetch') { return }
    if ($a -contains 'for-each-ref') {
        Assert-True ($a -contains 'refs/remotes/origin/') 'Commit check must be limited to origin.'
        if ($script:originContains) { return 'refs/remotes/origin/develop' }; return
    }
    throw "Unexpected git call: $a"
}
function gh {
    $a = @($args); $script:calls += ,@('gh', $a)
    $global:LASTEXITCODE = 0
    if ($a[0] -eq 'repo') {
        # Model the real fork trap: an implicit query would return upstream.
        if ($a[2] -ne 'qew4476/Fushi') { return '{"nameWithOwner":"hajisensai/Fushi","viewerPermission":"READ"}' }
        if ($script:authFails) { $global:LASTEXITCODE = 1; return }
        return (@{nameWithOwner='qew4476/Fushi';viewerPermission=$script:permission} | ConvertTo-Json)
    }
    if ($a[0] -eq 'api') {
        if ($a[1] -match '/commits/') {
            if ($script:commitFails) { $global:LASTEXITCODE=1; return }
            return $script:commit
        }
        if ($script:apiFails) { $global:LASTEXITCODE=1; return }
        return $script:tags
    }
    if ($a[0] -eq 'release' -and $a[1] -eq 'create') { if ($script:createFails) { $global:LASTEXITCODE=1 }; return }
    if ($a[0] -eq 'release' -and $a[1] -eq 'view') { return '{}' }
    throw "Unexpected gh call: $a"
}
function Write-Fixture {
    $script:commit = '0123456789abcdef0123456789abcdef01234567'
    $script:version = '3.0.1-local.0123456789'
    $script:out = Join-Path $temporary 'dist/local-windows'
    New-Item -ItemType Directory -Force $out, (Join-Path $temporary 'fushi') | Out-Null
    'version: 3.0.1+1' | Set-Content (Join-Path $temporary 'fushi/pubspec.yaml') -Encoding UTF8
    $script:file = "fushi-$script:version-windows-setup.exe"
    $script:installer = Join-Path $script:out $script:file
    'fixture installer' | Set-Content $script:installer -Encoding ASCII
    $script:hash = (Get-FileHash $script:installer -Algorithm SHA256).Hash
    "$script:hash  $script:file" | Set-Content "$script:installer.sha256" -Encoding ASCII
    $script:manifest = @{sourceRepo='qew4476/Fushi';commit=$script:commit;version=$script:version;file=$script:file;sha256=$script:hash}
    Save-Manifest
}
function Save-Manifest { $script:manifest | ConvertTo-Json | Set-Content (Join-Path $script:out 'build.json') -Encoding UTF8 }
function Publish-Fixture { Publish-LocalWindowsInstaller -RepositoryRoot $temporary -Repository 'qew4476/Fushi' }
function Assert-Rejected {
    param([scriptblock] $Action, [string] $Pattern)
    $message = $null
    try { & $Action | Out-Null } catch { $message = $_.Exception.Message }
    Assert-True ($message -and $message -match $Pattern) "Expected rejection '$Pattern', got '$message'."
    $creates = @($script:calls | Where-Object { $_[0] -eq 'gh' -and $_[1][0] -eq 'release' -and $_[1][1] -eq 'create' })
    Assert-True ($creates.Count -eq 0) 'Rejected operation attempted publication.'
}
try {
    foreach ($url in @('https://github.com/qew4476/Fushi.git','git@github.com:qew4476/Fushi.git','ssh://git@github.com/qew4476/Fushi.git')) {
        Reset-Mocks; $script:origin=$url
        Assert-True ((Get-LocalReleaseRepository -RepositoryRoot $temporary) -eq 'qew4476/Fushi') "Wrong fork target for $url"
    }
    Reset-Mocks; $script:permission='READ'
    Assert-Rejected { Get-LocalReleaseRepository -RepositoryRoot $temporary } 'permission'
    Reset-Mocks; $script:authFails=$true
    Assert-Rejected { Get-LocalReleaseRepository -RepositoryRoot $temporary } 'Cannot access'
    Reset-Mocks; Write-Fixture; $script:manifest.version='2.0.0'; Save-Manifest
    Assert-Rejected { Publish-Fixture } 'version differs'
    Reset-Mocks; Write-Fixture; $script:manifest.sha256='BAD'; Save-Manifest
    Assert-Rejected { Publish-Fixture } 'checksum differs'
    Reset-Mocks; Write-Fixture; 'BAD' | Set-Content "$script:installer.sha256"
    Assert-Rejected { Publish-Fixture } 'sidecar differs'
    Reset-Mocks; Write-Fixture; $script:originContains=$false
    Assert-Rejected { Publish-Fixture } 'pushed to origin'
    Reset-Mocks; Write-Fixture; $script:apiFails=$true
    Assert-Rejected { Publish-Fixture } 'Cannot list releases'
    Reset-Mocks; Write-Fixture; $script:commitFails=$true
    Assert-Rejected { Publish-Fixture } 'not accessible'
    Reset-Mocks; Write-Fixture; $script:manifest.sourceRepo='hajisensai/Fushi'; Save-Manifest
    Assert-Rejected { Publish-Fixture } 'source repository differs'
    Reset-Mocks; Write-Fixture; $script:tags=@("local-windows-$script:version")
    Assert-Rejected { Publish-Fixture } 'already exists'
    Reset-Mocks; Write-Fixture; Publish-Fixture | Out-Null
    $creates = @($script:calls | Where-Object { $_[0] -eq 'gh' -and $_[1][1] -eq 'create' })
    Assert-True ($creates.Count -eq 1) 'Success must create exactly one release.'
    $create = $creates[0][1]
    Assert-True ($create[([array]::IndexOf($create,'--repo')+1)] -eq 'qew4476/Fushi') 'Create must explicitly target fork.'
    Assert-True ($create[([array]::IndexOf($create,'--target')+1)] -eq $script:commit) 'Create must target manifest commit.'
    Assert-True (($create -contains '--prerelease=false') -and ($create -contains '--latest') -and -not ($create -contains '--prerelease') -and -not ($create -contains '--latest=false')) 'Local release must be a stable Latest release.'
    $entry = Get-Content "$PSScriptRoot/local_windows.ps1" -Raw
    $preflight = $entry.IndexOf('Get-LocalReleaseRepository -RepositoryRoot')
    $sdk = $entry.IndexOf("'fushi/.fvmrc'")
    $build = $entry.IndexOf("Invoke-Script 'tool/local_windows.ps1' `$buildArguments")
    Assert-True ($preflight -ge 0 -and $preflight -lt $sdk -and $preflight -lt $build) 'Release permission preflight must precede SDK access and build.'
    $publish = [regex]::Match($entry, '(?s)if \(\$Command -eq ''publish''\) \{(.*?)\n\s*\}')
    Assert-True ($publish.Success -and $publish.Groups[1].Value.Contains('Publish-LocalWindowsInstaller') -and $publish.Groups[1].Value.Contains('exit 0') -and -not $publish.Groups[1].Value.Contains('Invoke-Script')) 'Publish must upload existing artifacts and exit before build.'
    Write-Host "PASS: $script:checks assertions; fork resolution, authorization, artifact validation, origin commit, API errors, duplicate protection, create arguments and entry wiring."
} finally {
    $resolved = [IO.Path]::GetFullPath($temporary)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Cleanup escaped temp directory.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
