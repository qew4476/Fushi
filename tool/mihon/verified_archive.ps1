function Get-VerifiedArchive {
    param(
        [string] $Uri,
        [string] $CachePath,
        [string] $Destination,
        [string] $Sha256
    )
    # Never hash/extract a shared download in place. Older builders may still
    # hold the cache file open; in that case obtain our own private download.
    $copied = $false
    if ([IO.File]::Exists($CachePath)) {
        try {
            [IO.File]::Copy($CachePath, $Destination, $true)
            $copied = $true
        } catch [IO.IOException] {
            Write-Verbose "Shared archive unavailable; downloading a private copy."
        }
    }
    if ($copied) {
        $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
        if ($actual -eq $Sha256) { return }
    }

    # Explicitly dispose the downloader before hashing, including on PS 5.1.
    $client = New-Object Net.WebClient
    try {
        $client.DownloadFile($Uri, $Destination)
    } finally {
        $client.Dispose()
    }
    $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    if ($actual -ne $Sha256) {
        throw "Archive checksum mismatch: expected $Sha256, got $actual"
    }

    # Publish only complete verified bytes with an atomic same-directory rename.
    # Do not overwrite a cache another process may be using.
    $pending = "$CachePath.$([Guid]::NewGuid().ToString('N')).part"
    try {
        [IO.File]::Copy($Destination, $pending)
        try {
            [IO.File]::Move($pending, $CachePath)
        } catch [IO.IOException] {
            if (-not [IO.File]::Exists($CachePath)) { throw }
        }
    } finally {
        if ([IO.File]::Exists($pending)) { [IO.File]::Delete($pending) }
    }
}
