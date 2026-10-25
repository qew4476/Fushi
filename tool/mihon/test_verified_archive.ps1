$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'verified_archive.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('mihon-archive-test-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
try {
    $source = Join-Path $root 'source.zip'
    $cache = Join-Path $root 'cache.zip'
    $destination = Join-Path $root 'private.zip'
    [IO.File]::WriteAllText($source, 'verified test payload')
    $sha = (Get-FileHash $source -Algorithm SHA256).Hash
    $uri = ([Uri]$source).AbsoluteUri
    Get-VerifiedArchive $uri $cache $destination $sha
    if ((Get-FileHash $cache).Hash -ne $sha) { throw 'Cache publication failed' }
    # A cache hit must work without contacting the source.
    Get-VerifiedArchive 'invalid://offline' $cache $destination $sha
    # Reproduce the original exclusive-file-lock failure. The private download
    # must succeed while the shared cache remains locked, with no sleeps/retries.
    $locked = [IO.File]::Open($cache, 'Open', 'ReadWrite', 'None')
    try { Get-VerifiedArchive $uri $cache $destination $sha }
    finally { $locked.Dispose() }
    [IO.File]::WriteAllText($cache, 'incomplete download')
    Get-VerifiedArchive $uri $cache $destination $sha
    if ((Get-FileHash $destination).Hash -ne $sha) { throw 'Invalid private archive' }
    [IO.File]::Delete($cache)
    $rejected = $false
    try { Get-VerifiedArchive $uri $cache $destination ('0' * 64) }
    catch { if ($_.Exception.Message -notlike 'Archive checksum mismatch:*') { throw }; $rejected = $true }
    if (-not $rejected -or [IO.File]::Exists($cache)) { throw 'Unverified cache published' }
    if (@(Get-ChildItem $root -Filter '*.part').Count -ne 0) { throw 'Partial files leaked' }
    Write-Host 'PASS: publish, offline hit, exclusive lock, partial cache, checksum rejection, cleanup'
} finally {
    # Only remove files created by this test; no recursive computed-path deletion.
    Get-ChildItem -LiteralPath $root -File | Remove-Item -Force
    [IO.Directory]::Delete($root)
}
