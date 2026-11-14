# Builds the shippable installers:
#   dist/windows/  README.md + install.ps1  (NSIS setup exe embedded)
#   dist/linux/    README.md + install.sh   (source tarball embedded)
#   dist/MindPalace-source.zip  source tree for developers (no palace data)
#
# Usage:  powershell -File scripts\package.ps1 [-SkipBuild] [-NoData]
#   -SkipBuild  reuse the existing NSIS exe instead of running tauri build
#   -NoData     leave agent/data (palace.json + vault) out of the Linux bundle
param(
    [switch]$SkipBuild,
    [switch]$NoData
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

# ── 1. Windows build ─────────────────────────────────────────────────
if (-not $SkipBuild) {
    Write-Host "Building the app (npm run tauri build)..." -ForegroundColor Cyan
    Push-Location (Join-Path $repo 'app')
    npm run tauri build
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw "tauri build failed" }
    Pop-Location
}
$setup = Get-ChildItem (Join-Path $repo 'app\src-tauri\target\release\bundle\nsis\*-setup.exe') |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $setup) { throw "No NSIS setup exe found - run without -SkipBuild first" }
Write-Host "Setup exe: $($setup.Name) ($([math]::Round($setup.Length/1MB,2)) MB)"

# ── 2. Source tarball for Linux ──────────────────────────────────────
$tgz = Join-Path $env:TEMP "mindpalace-src.tgz"
if (Test-Path $tgz) { Remove-Item $tgz -Force }
$items = @('app', 'agent', 'installers', 'scripts', '.claude/skills', 'PLAN.md', 'BUILDING.md', 'mind.txt') |
    Where-Object { Test-Path (Join-Path $repo $_) }
$excludes = @(
    '--exclude', 'app/node_modules*',
    '--exclude', 'app/src-tauri/target*',
    '--exclude', 'app/src-tauri/gen*',
    '--exclude', 'app/dist*',
    '--exclude', 'agent/node_modules*',
    '--exclude', 'agent/dist*'
)
if ($NoData) { $excludes += @('--exclude', 'agent/data*') }
Write-Host "Creating source tarball..." -ForegroundColor Cyan
& tar -czf $tgz -C $repo @excludes @items
if ($LASTEXITCODE -ne 0) { throw "tar failed" }
$tgzInfo = Get-Item $tgz
Write-Host "Tarball: $([math]::Round($tgzInfo.Length/1MB,2)) MB"

# ── 3. Assemble dist/ ────────────────────────────────────────────────
$distW = Join-Path $repo 'dist\windows'
$distL = Join-Path $repo 'dist\linux'
New-Item -ItemType Directory -Force $distW | Out-Null
New-Item -ItemType Directory -Force $distL | Out-Null

# linux/install.sh = template (LF endings) + base64 tarball after __ARCHIVE__
$sh = [IO.File]::ReadAllText((Join-Path $repo 'installers\install.sh'))
$sh = $sh -replace "`r`n", "`n"
if (-not $sh.EndsWith("__ARCHIVE__`n")) { throw "install.sh template must end with the __ARCHIVE__ marker line" }
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($tgz))
[IO.File]::WriteAllText((Join-Path $distL 'install.sh'), $sh + $b64 + "`n")
Copy-Item (Join-Path $repo 'installers\README-linux.md') (Join-Path $distL 'README.md') -Force

# windows/install.ps1 = template + setup exe in a trailing block comment
$ps = [IO.File]::ReadAllText((Join-Path $repo 'installers\install.ps1'))
$exeB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($setup.FullName))
$payload = "`r`n<# __PAYLOAD__`r`n" + $exeB64 + "`r`n#>`r`n"
[IO.File]::WriteAllText((Join-Path $distW 'install.ps1'), $ps + $payload)
Copy-Item (Join-Path $repo 'installers\README-windows.md') (Join-Path $distW 'README.md') -Force

Remove-Item $tgz -Force

# ── 3.5 Source zip for developers ────────────────────────────────────
# Same file set, but the user's palace (agent/data) is NEVER included —
# that's personal data; BUILDING.md doubles as the zip's README.
$srcStage = Join-Path $env:TEMP 'MindPalace-source'
if (Test-Path $srcStage) { Remove-Item $srcStage -Recurse -Force }
New-Item -ItemType Directory -Force $srcStage | Out-Null
$srcTgz = Join-Path $env:TEMP 'mindpalace-dev.tgz'
if (Test-Path $srcTgz) { Remove-Item $srcTgz -Force }
$srcExcludes = $excludes + @('--exclude', 'agent/data*', '--exclude', 'mind.txt')
& tar -czf $srcTgz -C $repo @srcExcludes @items
if ($LASTEXITCODE -ne 0) { throw "tar (source) failed" }
& tar -xzf $srcTgz -C $srcStage
if ($LASTEXITCODE -ne 0) { throw "tar extract (source) failed" }
Remove-Item $srcTgz -Force
Copy-Item (Join-Path $repo 'BUILDING.md') (Join-Path $srcStage 'README.md') -Force
$srcZip = Join-Path $repo 'dist\MindPalace-source.zip'
New-Item -ItemType Directory -Force (Join-Path $repo 'dist') | Out-Null
if (Test-Path $srcZip) { Remove-Item $srcZip -Force }
Compress-Archive -Path $srcStage -DestinationPath $srcZip
Remove-Item $srcStage -Recurse -Force

# ── 4. Shipping zips (MindPalace-windows.zip / MindPalace-linux.zip) ─
foreach ($os in 'windows', 'linux') {
    $stage = Join-Path $env:TEMP "MindPalace-$os"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    Copy-Item (Join-Path $repo "dist\$os") $stage -Recurse
    $zip = Join-Path $repo "dist\MindPalace-$os.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path $stage -DestinationPath $zip
    Remove-Item $stage -Recurse -Force
}

Write-Host ""
Write-Host "dist/ ready:" -ForegroundColor Green
Get-ChildItem -Recurse (Join-Path $repo 'dist') -File | ForEach-Object {
    Write-Host ("  {0,-28} {1,8:N2} MB" -f $_.FullName.Substring($repo.Length + 1), ($_.Length / 1MB))
}
