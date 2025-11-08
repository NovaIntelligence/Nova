# Creators: Tyler McKendry & Nova
# Pester_Smoke.ps1 — PS 5.1-safe smoke using throw-based assertions (works without relying on Pester features)
$ErrorActionPreference = "Stop"

function Assert-True($cond, $msg){
  if(-not $cond){ throw $msg }
}

# Basic structure checks
$root = "C:\Nova"
$paths = @(
  "$root\ops\sessions",
  "$root\tests",
  "$root\wallet\scripts",
  "$root\gov\ledgers",
  "$root\voice",
  "$root\bank",
  "$root\trading"
)
foreach($p in $paths){ Assert-True (Test-Path $p) ("Missing required folder: {0}" -f $p) }

# Script existence checks (created by orchestrator writer)
$files = @(
  "$root\ops\sessions\Nova-Core_Deploy.ps1",
  "$root\tests\Pester_Smoke.ps1",
  "$root\wallet\scripts\Wallet_Watcher.ps1",
  "$root\gov\ledgers\update_entries.ps1",
  "$root\voice\Bridge_Init.ps1",
  "$root\bank\MVP_Scaffold.ps1",
  "$root\trading\Strategy_Stub.ps1"
)
foreach($f in $files){ Assert-True (Test-Path $f) ("Missing script: {0}" -f $f) }

Write-Host "Pester_Smoke: ✅ All basic checks passed." -ForegroundColor Green