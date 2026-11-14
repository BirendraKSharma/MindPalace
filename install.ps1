# ──────────────────────────────────────────────────────────────────────
#  MindPalace — one-command install for Windows (PowerShell)
#
#  Usage:
#    iwr -useb https://raw.githubusercontent.com/BirendraKSharma/MindPalace/main/install.ps1 | iex
#
#  Downloads the source, builds with Rust + Node, and installs the app.
#  Requires Visual Studio Build Tools ("Desktop development with C++")
#  for the Rust linker. Your palace data is never touched.
# ──────────────────────────────────────────────────────────────────────
$ErrorActionPreference = 'Stop'

$TMP = [System.IO.Path]::GetTempPath()
$ZIP = Join-Path $TMP "MindPalace.zip"

Write-Host "==> Downloading MindPalace source…"
Invoke-WebRequest -Uri "https://github.com/BirendraKSharma/MindPalace/archive/refs/heads/main.zip" -OutFile $ZIP

Write-Host "==> Extracting…"
Expand-Archive -Path $ZIP -DestinationPath $TMP -Force

$SRC = Get-ChildItem -Path $TMP -Filter "MindPalace-*" | Select-Object -First 1
if (-not $SRC) { throw "ERROR: failed to extract source archive." }

Write-Host "==> Running installer from $($SRC.FullName)…"
& "$($SRC.FullName)\installers\install.ps1" -Defaults

Write-Host ""
Write-Host "==> Done. Launch from the Start menu or run: & "$env:LOCALAPPDATA\MindPalace\app.exe""