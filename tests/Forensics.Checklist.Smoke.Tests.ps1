BeforeAll {
  $global:ErrorActionPreference = 'Stop'
  $repoRoot = Split-Path -Parent $PSScriptRoot
  $scriptPath = Join-Path $repoRoot 'tools\forensics\Run-WalletRecoveryChecklist.ps1'
  $stubPath = Join-Path $repoRoot 'tools\ip_provenance.ps1'

  # Prepare expected C:\Nova structure
  $base = 'C:\Nova'
  foreach ($dir in @('intake','forensic','ledger','tools','cases')) {
    $p = Join-Path $base $dir
    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
  }

  # Ensure stub tool exists so optional copy step works when SkipIpProvenance is removed later
  $destStub = Join-Path $base 'tools\ip_provenance.ps1'
  try {
    $srcResolved = (Resolve-Path -LiteralPath $stubPath).Path
    $destResolved = $null
    if (Test-Path -LiteralPath $destStub) {
      $destResolved = (Resolve-Path -LiteralPath $destStub).Path
    }
    if (-not (Test-Path -LiteralPath $destStub) -or ($srcResolved -ne $destResolved)) {
      Copy-Item -LiteralPath $stubPath -Destination $destStub -Force
    }
  } catch {
    # Best-effort: if resolution fails but dest missing, attempt copy
    if (-not (Test-Path -LiteralPath $destStub)) {
      Copy-Item -LiteralPath $stubPath -Destination $destStub -Force
    }
  }

  $ts = Get-Date -Format 'yyyyMMddHHmmss'
  Set-Variable -Name CaseId -Value ("NOVA-TEST-{0}" -f $ts) -Scope Script
}

Describe 'WalletRecoveryChecklist (Smoke)' {
  It 'runs successfully and produces expected outputs' {
    $operator = 'CI Bot'
    & $scriptPath -CaseId $Script:CaseId -Operator $operator -SkipIpProvenance | Out-String | Write-Host

    # Verify scope log contains case entry
    $scopeLog = 'C:\Nova\ledger\scope.log'
    Test-Path -LiteralPath $scopeLog | Should -BeTrue
    (Get-Content -LiteralPath $scopeLog -Raw) | Should -Match ([regex]::Escape($Script:CaseId))

    # Verify governance entry exists
    $govFile = Join-Path 'C:\Nova\ledger\governance' ("{0}.md" -f $Script:CaseId)
    Test-Path -LiteralPath $govFile | Should -BeTrue
    (Get-Content -LiteralPath $govFile -Raw) | Should -Match "#\s+$([regex]::Escape($Script:CaseId))"

    # Verify forensic outputs
    $forensicRoot = Join-Path 'C:\Nova\forensic' $Script:CaseId
    $manifest = Join-Path $forensicRoot 'MANIFEST.txt'
    $hashes = Join-Path $forensicRoot 'HASHES.sha256'
    Test-Path -LiteralPath $manifest | Should -BeTrue
    Test-Path -LiteralPath $hashes | Should -BeTrue

    # Verify daily journal created
    $journal = Join-Path 'C:\Nova\ledger\journals' ("{0}.md" -f (Get-Date -Format 'yyyy-MM-dd'))
    Test-Path -LiteralPath $journal | Should -BeTrue
  }

  It 'runs ip_provenance and writes log and summary' {
    # Prepare intake with a sample artifact
    $intakeCaseDir = Join-Path 'C:\Nova\intake' $Script:CaseId
    if (-not (Test-Path -LiteralPath $intakeCaseDir)) { New-Item -ItemType Directory -Force -Path $intakeCaseDir | Out-Null }
    $sampleFile = Join-Path $intakeCaseDir 'sample.txt'
    Set-Content -Encoding UTF8 -LiteralPath $sampleFile -Value 'hello world'
    $expectedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sampleFile).Hash

    # Run checklist without -SkipIpProvenance to execute the stub
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'tools\forensics\Run-WalletRecoveryChecklist.ps1'
    & $scriptPath -CaseId $Script:CaseId -Operator 'CI Bot' | Out-String | Write-Host

    $ipProvDir = Join-Path (Join-Path 'C:\Nova\forensic' $Script:CaseId) 'ip_provenance'
    $runLog = Join-Path $ipProvDir 'run.log'
    $summary = Join-Path $ipProvDir 'summary.json'

    # Validate log and summary exist
    Test-Path -LiteralPath $ipProvDir | Should -BeTrue
    Test-Path -LiteralPath $runLog | Should -BeTrue
    Test-Path -LiteralPath $summary | Should -BeTrue

    # Log should mention stub start and input path
    $logText = Get-Content -LiteralPath $runLog -Raw
    $logText | Should -Match 'ip_provenance.ps1 \(stub\) starting'
    $logText | Should -Match ([regex]::Escape($intakeCaseDir))

    # Summary should include case id and at least the sample artifact with correct hash
    $json = Get-Content -LiteralPath $summary -Raw | ConvertFrom-Json
    $json.case | Should -Be $Script:CaseId
    ($json.artifacts.Count -gt 0) | Should -BeTrue
    $match = $json.artifacts | Where-Object { $_.Path -eq $sampleFile }
    ($null -ne $match) | Should -BeTrue
    $match.Hash | Should -Be $expectedHash
  }
}
