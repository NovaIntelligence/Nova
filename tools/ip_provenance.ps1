param(
  [Parameter(Mandatory=$true)] [string]$CaseId,
  [Parameter(Mandatory=$true)] [string]$InputPath,
  [Parameter(Mandatory=$true)] [string]$OutDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $OutDir)) {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}

$log = Join-Path $OutDir 'run.log'
$summary = Join-Path $OutDir 'summary.json'

"[#] ip_provenance.ps1 (stub) starting for case $CaseId" | Tee-Object -FilePath $log -Append | Out-Null
"Input: $InputPath" | Tee-Object -FilePath $log -Append | Out-Null
"Output: $OutDir" | Tee-Object -FilePath $log -Append | Out-Null

# Simulate artifact collection
$artifacts = @()
if (Test-Path -LiteralPath $InputPath) {
  Get-ChildItem -Recurse -LiteralPath $InputPath | Where-Object { -not $_.PSIsContainer } | ForEach-Object {
    $artifacts += [PSCustomObject]@{
      Path = $_.FullName
      Size = $_.Length
      Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
    }
  }
} else {
  "[!] InputPath not found; proceeding with empty artifact set" | Tee-Object -FilePath $log -Append | Out-Null
}

"[#] Writing summary.json" | Tee-Object -FilePath $log -Append | Out-Null
@{
  case = $CaseId
  generated_utc = (Get-Date -AsUTC -Format s) + 'Z'
  host = $env:COMPUTERNAME
  artifacts = $artifacts
} | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath $summary

"[#] Completed." | Tee-Object -FilePath $log -Append | Out-Null

Write-Host "ip_provenance.ps1 (stub) completed. Summary: $summary" -ForegroundColor Green
