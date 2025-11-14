param(
    [Parameter(Mandatory=$true)] [string]$OutDir,
    [double]$InfraMonthlyCost,
    [double]$AvgDealValue,
    [double]$CloseRate,
    [double]$MeetingsPerWeek,
    [string]$MetricsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-CleanDir($Path) { if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null } }
function Assert-Number($v, $name) { if ($null -eq $v -or [double]::IsNaN([double]$v)) { throw "Missing or invalid $name" } }

New-CleanDir -Path $OutDir
$reportPath = Join-Path $OutDir 'self_sufficiency_report.json'

if ($MetricsPath) {
    if (-not (Test-Path $MetricsPath)) { throw "Metrics not found: $MetricsPath" }
    $ext = [System.IO.Path]::GetExtension($MetricsPath).ToLowerInvariant()
    if ($ext -eq '.json') {
        $m = Get-Content -Path $MetricsPath -Raw | ConvertFrom-Json
    } elseif ($ext -eq '.csv') {
        $m = Import-Csv -Path $MetricsPath | Select-Object -First 1
    } else {
        throw "Unsupported metrics file type: $ext"
    }
    if ($m.InfraMonthlyCost) { $InfraMonthlyCost = [double]$m.InfraMonthlyCost }
    if ($m.AvgDealValue)    { $AvgDealValue    = [double]$m.AvgDealValue }
    if ($m.CloseRate)       { $CloseRate       = [double]$m.CloseRate }
    if ($m.MeetingsPerWeek) { $MeetingsPerWeek = [double]$m.MeetingsPerWeek }
}

Assert-Number $InfraMonthlyCost 'InfraMonthlyCost'
Assert-Number $AvgDealValue 'AvgDealValue'
Assert-Number $CloseRate 'CloseRate'
if ($CloseRate -le 0 -or $CloseRate -gt 1) { throw 'CloseRate must be in (0,1].' }

$dealsToBreakEven = [math]::Ceiling($InfraMonthlyCost / $AvgDealValue)
$meetingsToBreakEven = [math]::Ceiling($dealsToBreakEven / $CloseRate)
$weeksToBreakEven = $null
if ($MeetingsPerWeek -and $MeetingsPerWeek -gt 0) {
    $weeksToBreakEven = [math]::Round(($meetingsToBreakEven / $MeetingsPerWeek), 2)
}

$report = [ordered]@{
    timestamp            = (Get-Date).ToString('o')
    inputs               = [ordered]@{
        InfraMonthlyCost = [math]::Round($InfraMonthlyCost,2)
        AvgDealValue     = [math]::Round($AvgDealValue,2)
        CloseRate        = [math]::Round($CloseRate,4)
        MeetingsPerWeek  = if ($MeetingsPerWeek) { [math]::Round($MeetingsPerWeek,2) } else { $null }
        MetricsPath      = $MetricsPath
    }
    outputs              = [ordered]@{
        DealsToBreakEven     = $dealsToBreakEven
        MeetingsToBreakEven  = $meetingsToBreakEven
        WeeksToBreakEven     = $weeksToBreakEven
    }
    guidance             = @(
        "Increase reply/close rate (copy/offer) to reduce meetings required",
        "Raise average deal value or add upsells/retainers",
        "Do not scale infra unless WeeksToBreakEven <= 4 and proof KPI is met"
    )
}

$report | ConvertTo-Json -Depth 6 | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "Self-Sufficiency Model written to $reportPath"
