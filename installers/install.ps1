# ──────────────────────────────────────────────────────────────────────
#  MindPalace installer for Windows (self-contained)
#
#  The real setup program is embedded at the end of this file; this
#  script just asks a few questions, then installs and configures.
#
#  Run:       powershell -ExecutionPolicy Bypass -File install.ps1
#  Flags:     -Defaults    accept every default, ask nothing
#             -Uninstall   remove the app (palace data is never touched)
# ──────────────────────────────────────────────────────────────────────
param(
    [switch]$Defaults,
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'

function Ask([string]$Question, [string]$Default) {
    if ($Defaults) { return $Default }
    $reply = Read-Host "$Question [$Default]"
    if ([string]::IsNullOrWhiteSpace($reply)) { return $Default }
    return $reply.Trim()
}
function Confirm-Yes([string]$Question, [string]$Default = 'Y') {
    if ($Defaults) { return ($Default -eq 'Y') }
    $reply = Read-Host "$Question [$Default]"
    if ([string]::IsNullOrWhiteSpace($reply)) { $reply = $Default }
    return $reply -match '^[Yy]'
}

# ── uninstall ────────────────────────────────────────────────────────
if ($Uninstall) {
    $dir = Ask "Where is MindPalace installed" "$env:LOCALAPPDATA\MindPalace"
    $un = Join-Path $dir 'uninstall.exe'
    if (-not (Test-Path $un)) { Write-Host "No uninstall.exe in $dir - nothing to do."; exit 1 }
    Start-Process -FilePath $un -ArgumentList '/S' -Wait
    Write-Host "Uninstalled. Your palace data and the MINDPALACE_DATA variable were left in place."
    exit 0
}

Write-Host ""
Write-Host "MindPalace installer" -ForegroundColor White
Write-Host ""

# ── questions ────────────────────────────────────────────────────────
$installDir = Ask "Install MindPalace where" "$env:LOCALAPPDATA\MindPalace"

$dataDefault = [Environment]::GetEnvironmentVariable('MINDPALACE_DATA', 'User')
if ([string]::IsNullOrWhiteSpace($dataDefault)) { $dataDefault = "$env:APPDATA\MindPalace\palace.json" }
$dataFile = Ask "Where should your palace live (palace.json)" $dataDefault

$hotkey = Ask "Global open/hide hotkey" "Ctrl+Shift+Space"
$autostart = Confirm-Yes "Start MindPalace automatically at login" 'Y'

# ── AI backend selection ───────────────────────────────────────────────
$AI_BACKEND = "off"
$AI_COMMAND = ""
$AI_MODEL = ""
if (-not $Defaults) {
    Write-Host ""
    Write-Host "AI backends found on this system:"
    $found = @()
    foreach ($name in @("claude","codex","opencode","ollama")) {
        if (Get-Command $name -ErrorAction SilentlyContinue) {
            $found += $name
            Write-Host "  $($found.Count}) $name"
        }
    }
    Write-Host "  0) none (AI off — enable later from the titlebar button)"
    Write-Host "  c) custom (enter your own AI command)"
    $aiChoice = Read-Host "Configure AI backend [0]"
    if ([string]::IsNullOrWhiteSpace($aiChoice)) { $aiChoice = "0" }
    switch ($aiChoice) {
        "0" { $AI_BACKEND = "off" }
        "c" { 
            $AI_BACKEND = "custom"
            $AI_COMMAND = Read-Host "Custom AI command (argv JSON, e.g. [""C:\path\opencode.exe"",""run"",""{prompt}""])"
        }
        default {
            $idx = [int]$aiChoice - 1
            if ($idx -ge 0 -and $idx -lt $found.Count) {
                $AI_BACKEND = $found[$idx]
                if ($AI_BACKEND -eq "ollama") {
                    $AI_MODEL = Read-Host "Ollama model (e.g. qwen2.5:3b)"
                    if ([string]::IsNullOrWhiteSpace($AI_MODEL)) { $AI_MODEL = "qwen2.5:3b" }
                }
            } else {
                $AI_BACKEND = "off"
            }
        }
    }
}

# ── extract the embedded setup exe ───────────────────────────────────
$raw = [IO.File]::ReadAllText($PSCommandPath)
$marker = '<# __PAY' + 'LOAD__'   # split so this line never matches itself
$idx = $raw.LastIndexOf($marker)
if ($idx -lt 0) {
    Write-Host "This copy has no embedded setup program - generate it with scripts/package.ps1." -ForegroundColor Yellow
    exit 1
}
$b64 = $raw.Substring($idx + $marker.Length)
$end = $b64.LastIndexOf('#>')
if ($end -ge 0) { $b64 = $b64.Substring(0, $end) }
$setupExe = Join-Path $env:TEMP "MindPalace-setup-$PID.exe"
[IO.File]::WriteAllBytes($setupExe, [Convert]::FromBase64String($b64.Trim()))

# ── configure first, so the app starts with the right settings ───────
$dataDir = Split-Path -Parent $dataFile
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Force $dataDir | Out-Null }

# the app and the Claude Code skill share this store; set it machine-wide for the user
setx MINDPALACE_DATA $dataFile | Out-Null
$env:MINDPALACE_DATA = $dataFile

$configPath = Join-Path $dataDir 'config.json'
# Merge into an existing config.json — a reinstall must never wipe keys the
# user added (ai, searchUrl, window, aiModel, ...).
$config = $null
if (Test-Path $configPath) {
    try { $config = Get-Content $configPath -Raw | ConvertFrom-Json } catch {}
}
if ($null -eq $config) { $config = New-Object PSObject }
$config | Add-Member -NotePropertyName hotkey -NotePropertyValue $hotkey -Force
$config | Add-Member -NotePropertyName autostart -NotePropertyValue ([bool]$autostart) -Force
$config | Add-Member -NotePropertyName ai -NotePropertyValue $AI_BACKEND -Force
if ($AI_COMMAND) { $config | Add-Member -NotePropertyName aiCommand -NotePropertyValue $AI_COMMAND -Force }
if ($AI_MODEL) { $config | Add-Member -NotePropertyName aiModel -NotePropertyValue $AI_MODEL -Force }
# WriteAllText = UTF-8 without BOM (the app's JSON parser rejects a BOM)
[IO.File]::WriteAllText($configPath, (ConvertTo-Json $config))

# ── install ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Installing to $installDir ..."
# Stop a running copy first, or NSIS can't replace the exe in place
Get-Process app -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like (Join-Path $installDir '*') } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
# NSIS: /D= must be the last argument and must NOT be quoted, even with spaces
Start-Process -FilePath $setupExe -ArgumentList "/S /D=$installDir" -Wait
Remove-Item $setupExe -ErrorAction SilentlyContinue

$exe = Join-Path $installDir 'app.exe'
if (-not (Test-Path $exe)) {
    Write-Host "Setup finished but $exe was not found - check $installDir." -ForegroundColor Yellow
    exit 1
}
Start-Process -FilePath $exe

Write-Host ""
Write-Host "Installed." -ForegroundColor Green
Write-Host "  app        $exe"
Write-Host "  palace     $dataFile"
Write-Host "  hotkey     $hotkey"
Write-Host "  autostart  $autostart"
Write-Host ""
Write-Host "Change settings later in $configPath (hotkey, window size, autostart),"
Write-Host "then quit from the tray and relaunch. Uninstall: install.ps1 -Uninstall"
