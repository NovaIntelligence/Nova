Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-Default($prompt, $default) {
    $v = Read-Host "$prompt [$default]"
    if ([string]::IsNullOrWhiteSpace($v)) { return $default } else { return $v }
}

Write-Host "Nova Skills Dashboard v0.1" -ForegroundColor Cyan
Write-Host "1) Outbound Deal Machine (Cold Caller)"
Write-Host "2) Self-Sufficiency Model"
Write-Host "Q) Quit"

$choice = Read-Host 'Choose an option'
switch ($choice) {
    '1' {
        $defaultCsv = Join-Path $PSScriptRoot '..\samples\skills\sample-leads.csv'
        $csv = Read-Default 'Leads CSV path' $defaultCsv
        $outBase = Join-Path $PSScriptRoot '..\tools\skills\_out'
        if (-not (Test-Path $outBase)) { New-Item -ItemType Directory -Path $outBase | Out-Null }
        $outDir = Join-Path $outBase (Get-Date -Format 'yyyyMMdd_HHmmss')
        $channel = Read-Default 'Channel (email/sms/call)' 'email'
        $script = Join-Path $PSScriptRoot '..\tools\skills\Outbound-Deal-Machine.ps1'
        & $script -LeadsCsv $csv -OutDir $outDir -Channel $channel
        Write-Host "Outputs: $outDir" -ForegroundColor Green
    }
    '2' {
        $outBase = Join-Path $PSScriptRoot '..\tools\skills\_out'
        if (-not (Test-Path $outBase)) { New-Item -ItemType Directory -Path $outBase | Out-Null }
        $outDir = Join-Path $outBase (Get-Date -Format 'yyyyMMdd_HHmmss')
        $infra  = [double](Read-Default 'Infra monthly cost (e.g., 200)' '200')
        $adv    = [double](Read-Default 'Average deal value (e.g., 1500)' '1500')
        $cr     = [double](Read-Default 'Close rate (0-1, e.g., 0.2)' '0.2')
        $mpw    = [double](Read-Default 'Meetings per week (e.g., 10)' '10')
        $script = Join-Path $PSScriptRoot '..\tools\skills\Self-Sufficiency-Model.ps1'
        & $script -OutDir $outDir -InfraMonthlyCost $infra -AvgDealValue $adv -CloseRate $cr -MeetingsPerWeek $mpw
        Write-Host "Report: $(Join-Path $outDir 'self_sufficiency_report.json')" -ForegroundColor Green
    }
    default { Write-Host 'Bye.' }
}
