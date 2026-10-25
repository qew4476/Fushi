function Remove-BuildTree {
    param(
        [Parameter(Mandatory = $true)][string] $LiteralPath,
        [Parameter(Mandatory = $true)][string] $AllowedParent
    )
    $target = [IO.Path]::GetFullPath($LiteralPath).TrimEnd('\')
    $parent = [IO.Path]::GetFullPath($AllowedParent).TrimEnd('\')
    if (-not $target.StartsWith($parent + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove build tree outside allowed parent: $target"
    }
    # PS 5.1's FileSystem provider cannot reliably remove Java/Kotlin class
    # names exceeding MAX_PATH. Use the Windows extended-length path for the
    # whole traversal, including its existence check; never hide cleanup errors.
    $extended = if ($target.StartsWith('\\')) {
        '\\?\UNC\' + $target.Substring(2)
    } else {
        '\\?\' + $target
    }
    if (Test-Path -LiteralPath $extended) {
        Remove-Item -LiteralPath $extended -Recurse -Force -ErrorAction Stop
    }
}
