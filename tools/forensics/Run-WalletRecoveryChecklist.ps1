<#
.SYNOPSIS
  Executes the Wallet‑Recovery / IP Provenance checklist end-to-end with safe, auditable outputs.

.DESCRIPTION
  Creates scope logs, runs ip_provenance.ps1 (if available), generates a challenge file,
  builds a forensic MANIFEST and recursive SHA-256 inventory, and appends a governance entry.
  Also creates/updates a daily reflection journal.

.PARAMETER CaseId
  Case identifier, e.g. "NOVA-2025-10-19-A".

.PARAMETER Operator
  Operator name recorded in logs.

.PARAMETER IntakeRoot
  Root intake directory (default: C:\Nova\intake).

.PARAMETER ForensicRoot
  Root forensic directory (default: C:\Nova\forensic).

.PARAMETER LedgerRoot
  Root ledger directory (default: C:\Nova\ledger).

.PARAMETER ToolsRoot
  Root tools directory (default: C:\Nova\tools).

.PARAMETER SkipIpProvenance
  If supplied, skip executing ip_provenance.ps1 (useful when tool is not present).

.EXAMPLE
  ./Run-WalletRecoveryChecklist.ps1 -CaseId NOVA-2025-10-19-A -Operator "Tyler McKendry"

#>

param(
  [Parameter(Mandatory=$true)] [string]$CaseId,
  [string]$Operator = "Tyler McKendry",
  [string]$IntakeRoot = "C:\Nova\intake",
  [string]$ForensicRoot = "C:\Nova\forensic",
  [string]$LedgerRoot = "C:\Nova\ledger",
  [string]$ToolsRoot = "C:\Nova\tools",
  [switch]$SkipIpProvenance
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$msg) {
  Write-Host ("[INFO] " + $msg) -ForegroundColor Cyan
}

function Write-Warn([string]$msg) {
  Write-Warning $msg
}

function Ensure-Dir([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
  }
}

# Resolve key paths
$CaseIntake = Join-Path $IntakeRoot $CaseId
$CaseForensicRoot = Join-Path $ForensicRoot $CaseId
$CaseIpProv = Join-Path $CaseForensicRoot 'ip_provenance'
$LedgerScopeLog = Join-Path $LedgerRoot 'scope.log'
$LedgerGovDir = Join-Path $LedgerRoot 'governance'
$LedgerJournalDir = Join-Path $LedgerRoot 'journals'
$CasesDir = 'C:\Nova\cases'

Ensure-Dir $IntakeRoot
Ensure-Dir $ForensicRoot
Ensure-Dir $LedgerRoot
Ensure-Dir $LedgerGovDir
Ensure-Dir $LedgerJournalDir
Ensure-Dir $CasesDir
Ensure-Dir $CaseForensicRoot
Ensure-Dir $CaseIpProv

Write-Info "Case: $CaseId | Operator: $Operator"

# 1) Lawful scope confirmation log
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ssK"
$scopeLine = "[$stamp] Lawful scope confirmed by $Operator — Case $CaseId"
$scopeLine | Add-Content -LiteralPath $LedgerScopeLog
Get-Content -LiteralPath $LedgerScopeLog -Tail 2 | Write-Host

# 2) Run ip_provenance.ps1 (if present and not skipped)
$IpTool = Join-Path $ToolsRoot 'ip_provenance.ps1'
$RunLog = Join-Path $CaseIpProv 'run.log'
if (-not $SkipIpProvenance) {
  if (Test-Path -LiteralPath $IpTool) {
    Write-Info "Running ip_provenance.ps1 ..."
    & $IpTool -CaseId $CaseId -InputPath $CaseIntake -OutDir $CaseIpProv -Verbose *>&1 | Out-Null
    if (Test-Path -LiteralPath $RunLog) {
      Write-Info "Computing SHA-256 of run.log"
      Get-FileHash -Algorithm SHA256 -LiteralPath $RunLog | Format-List | Out-String | Write-Host
    } else {
      Write-Warn "ip_provenance run.log not found at $RunLog"
    }
  } else {
    Write-Warn "ip_provenance.ps1 not found at $IpTool — skipping this step."
  }
} else {
  Write-Info "SkipIpProvenance specified — skipping ip_provenance execution."
}

# 3) Intake & Affidavit review (manual): emit a reminder note file
$reviewNote = @"
Intake & Affidavit Review — Checklist
- Identity docs match requestor.
- Ownership/rights to the wallet/IP are explicit.
- Chain‑of‑custody is complete (who handled what, when).
- No contradictions or scope creep; note exceptions in the governance ledger.
"@
Set-Content -Encoding UTF8 -LiteralPath (Join-Path $CaseForensicRoot 'INTAKE_REVIEW_CHECKLIST.txt') -Value $reviewNote

# 4) Challenge‑Response test — generate a challenge file
$nonce = [Guid]::NewGuid().ToString('N')
$challenge = "Nova Verify | Case=$CaseId | Nonce=$nonce | TimeUTC=$((Get-Date).ToUniversalTime().ToString('s'))Z"
$CaseDir = Join-Path $CasesDir $CaseId
Ensure-Dir $CaseDir
Set-Content -Encoding UTF8 -LiteralPath (Join-Path $CaseDir 'challenge.txt') -Value $challenge
if (-not (Test-Path -LiteralPath (Join-Path $CaseDir 'challenge.signed.txt'))) {
  $placeholder = "<Place signed message here after claimant returns proof>"
  Set-Content -Encoding UTF8 -LiteralPath (Join-Path $CaseDir 'challenge.signed.txt') -Value $placeholder
}
Set-Content -Encoding UTF8 -LiteralPath (Join-Path $CaseDir 'challenge_verification.md') -Value @"
# Challenge Verification — $CaseId
- Address/Domain Tested: 
- Method: (wallet-signature / DNS TXT / DKIM header / other)
- Tools: 
- Result: (pass/fail)
- Timestamp (UTC): $(Get-Date -AsUTC -Format s)Z
- Operator: $Operator
"@

# 5) Forensic MANIFEST + recursive SHA‑256 inventory
$manifest = Join-Path $CaseForensicRoot 'MANIFEST.txt'
@"
case: $CaseId
created_utc: $(Get-Date -AsUTC -Format s)Z
operator: $Operator
host: $env:COMPUTERNAME
notes: initial capture + provenance run
"@ | Set-Content -Encoding UTF8 -LiteralPath $manifest

$hashOut = Join-Path $CaseForensicRoot 'HASHES.sha256'
Get-ChildItem -Recurse -LiteralPath $CaseForensicRoot | Where-Object { -not $_.PSIsContainer } |
  Get-FileHash -Algorithm SHA256 |
  Tee-Object -FilePath $hashOut | Out-Null

if (Get-Command gpg -ErrorAction SilentlyContinue) {
  Write-Info "Signing manifest via gpg (clearsign)"
  & gpg --yes --clearsign $manifest | Out-Null
} else {
  Write-Info "gpg not found, skipping manifest signing"
}

# 6) Governance ledger entry
$govFile = Join-Path $LedgerGovDir ("{0}.md" -f $CaseId)
$govBody = @"
# $CaseId — Governance Entry
- When (UTC): $(Get-Date -AsUTC -Format s)Z
- Operator: $Operator
- Authority: <authorization ref / signer>
- Scope: wallet recovery / IP provenance
- Actions: ip_provenance.ps1 run, CR issued, intake reviewed
- Evidence: $manifest; $hashOut; $(Join-Path $CaseIpProv 'run.log')
- Risk/Notes: <none|details>
- Decision/Next: <proceed / hold / escalate>
"@
if (Test-Path -LiteralPath $govFile) {
  Add-Content -Encoding UTF8 -LiteralPath $govFile -Value "`n`n$govBody"
} else {
  Set-Content -Encoding UTF8 -LiteralPath $govFile -Value $govBody
}

# 7) Reflection + next‑day priorities
$journalFile = Join-Path $LedgerJournalDir ("{0}.md" -f (Get-Date -Format 'yyyy-MM-dd'))
$journalEntry = @"
## Reflection — $(Get-Date -Format 'yyyy-MM-dd HH:mm')
- What worked:
- What was hard:
- What I’ll change tomorrow:

## Top 3 for tomorrow (ranked)
1)
2)
3)
"@
Add-Content -Encoding UTF8 -LiteralPath $journalFile -Value $journalEntry

# 8) Final summary
Write-Host "" -ForegroundColor Gray
Write-Info "Checklist complete. Key outputs:"
Write-Host " - Scope log:      $LedgerScopeLog"
Write-Host " - Forensic root:  $CaseForensicRoot"
Write-Host " - IpProv out:     $CaseIpProv" 
Write-Host " - Manifest:       $manifest"
Write-Host " - Hashes:         $hashOut"
Write-Host " - Governance md:  $govFile"
Write-Host " - Challenge dir:  $CaseDir"
if (Test-Path -LiteralPath $RunLog) { Write-Host " - IpProv run.log: $RunLog" }

Write-Info "Maintain Focus mode per policy; finalize with EOD ledger update."
