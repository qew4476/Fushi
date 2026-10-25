$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'remove_build_tree.ps1')
$parent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$root = Join-Path $parent ('fushi-mihon-cleanup-test-' + [Guid]::NewGuid().ToString('N'))
if (-not $root.StartsWith($parent + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid test root' }
$leaf = Join-Path $root 'M-Extension-Server\server\build\classes\kotlin\test\mextensionserver'
$name = 'AnimeVideoLoaderTest$a dead hoster is skipped and the first failure only surfaces when nothing plays$allDead$1.class'
$file = Join-Path $leaf $name
if ($file.Length -le 260) { throw 'Fixture must exceed MAX_PATH' }
try {
    [IO.Directory]::CreateDirectory('\\?\' + $leaf) | Out-Null
    [IO.File]::WriteAllText(('\\?\' + $file), 'class fixture')
    # Ensure the fixture really exists before testing deletion.
    if (-not (Test-Path -LiteralPath ('\\?\' + $file))) { throw 'Missing long file' }
    $oldFailed = $false
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop }
    catch { $oldFailed = $true; Write-Host "Original cleanup reproduced: $($_.Exception.Message)" }
    if (-not $oldFailed) { Write-Host 'Host supports ordinary long-path removal' }
    # Recreate even if the old traversal removed some or all of the tree.
    [IO.Directory]::CreateDirectory('\\?\' + $leaf) | Out-Null
    [IO.File]::WriteAllText(('\\?\' + $file), 'class fixture')
    Remove-BuildTree -LiteralPath $root -AllowedParent $parent
    if (Test-Path -LiteralPath ('\\?\' + $root)) { throw 'Long-path tree remains' }
    Remove-BuildTree -LiteralPath $root -AllowedParent $parent
    $rejected = $false
    try { Remove-BuildTree -LiteralPath $parent -AllowedParent $parent }
    catch { $rejected = $true }
    if (-not $rejected) { throw 'Allowed parent itself was not rejected' }
    $rejected = $false
    try { Remove-BuildTree -LiteralPath ($root + '-sibling') -AllowedParent $root }
    catch { $rejected = $true }
    if (-not $rejected) { throw 'Sibling outside boundary was not rejected' }
    Write-Host "PASS: long path ($($file.Length) characters), missing tree, parent and sibling safety boundaries"
} finally {
    Remove-BuildTree -LiteralPath $root -AllowedParent $parent
}
