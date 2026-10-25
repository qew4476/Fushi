function Get-LocalReleaseRepository {
    param([string] $RepositoryRoot)
    $origin = (& git -C $RepositoryRoot remote get-url origin | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve origin for local release.' }
    $match = [regex]::Match($origin, '^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+/[^/]+?)(?:\.git)?/?$')
    if (-not $match.Success) { throw 'origin must identify a GitHub repository.' }
    $repo = $match.Groups[1].Value
    # gh defaults to the upstream in fork checkouts. Always supply origin.
    $details = & gh repo view $repo --json nameWithOwner,viewerPermission | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Cannot access release repository $repo. Check gh auth status." }
    $details = $details | ConvertFrom-Json
    if ($details.viewerPermission -notin @('ADMIN', 'MAINTAIN', 'WRITE')) {
        throw "No release write permission for $repo (permission: $($details.viewerPermission))."
    }
    return $details.nameWithOwner
}

function Publish-LocalWindowsInstaller {
    param([string] $RepositoryRoot, [string] $Repository, [string] $Tag)
    $out = Join-Path $RepositoryRoot 'dist/local-windows'
    $manifestPath = Join-Path $out 'build.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'No build.json. Run .\fushi build first.' }
    $m = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($m.sourceRepo -ne $Repository) { throw 'Installer source repository differs from origin. Rebuild before publishing.' }
    if ($m.commit -notmatch '^[0-9a-f]{40}$') { throw 'Invalid build commit in build.json.' }
    $appVersion = [regex]::Match((Get-Content -LiteralPath (Join-Path $RepositoryRoot 'fushi/pubspec.yaml') -Raw), '(?m)^version:\s*(\S+)').Groups[1].Value.Split('+')[0]
    $expectedVersion = "$appVersion-local.$($m.commit.Substring(0,10))"
    if ($m.version -ne $expectedVersion) { throw "Installer version differs from project version $appVersion. Rebuild before publishing." }
    if ($m.file -ne "fushi-$expectedVersion-windows-setup.exe") { throw 'Unexpected installer filename in build.json.' }
    $installer = Join-Path $out $m.file
    if ((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash -ne $m.sha256) { throw 'Installer checksum differs from build.json.' }
    $sidecar = (Get-Content -LiteralPath "$installer.sha256" -Raw).Trim()
    if ($sidecar -ne "$($m.sha256)  $($m.file)") { throw 'Installer checksum sidecar differs from build.json.' }
    if (-not $Tag) { $Tag = "local-windows-$($m.version)" }
    if ($Tag -notmatch '^local-windows-[A-Za-z0-9._-]+$') { throw 'Use a local-windows- tag to avoid triggering the multi-platform release workflows.' }
    & git -C $RepositoryRoot fetch origin --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Cannot fetch origin before publishing.' }
    $refs = @(& git -C $RepositoryRoot for-each-ref '--format=%(refname)' "--contains=$($m.commit)" refs/remotes/origin/)
    if ($LASTEXITCODE -ne 0 -or $refs.Count -eq 0) { throw 'Build commit must be pushed to origin before publishing.' }
    & gh api "repos/$Repository/commits/$($m.commit)" --jq .sha | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Build commit is not accessible in the release repository.' }
    # Listing fails on authentication/network errors rather than treating every
    # failure of `release view` as proof that a tag is free.
    $tags = @(& gh api "repos/$Repository/releases" --paginate --jq '.[].tag_name')
    if ($LASTEXITCODE -ne 0) { throw "Cannot list releases in $Repository." }
    if ($tags -contains $Tag) { throw "Release $Tag already exists; assets are never overwritten." }
    & gh release create $Tag $installer "$installer.sha256" --repo $Repository --target $m.commit --title "Fushi $($m.version) Windows" --notes 'Locally built Windows installer (unsigned).' --prerelease --latest=false
    if ($LASTEXITCODE -ne 0) { throw 'GitHub release upload failed. Fix the error, then run .\fushi publish to reuse the verified installer.' }
    & gh release view $Tag --repo $Repository --json url,assets
    if ($LASTEXITCODE -ne 0) { throw 'Cannot verify the published release.' }
}
