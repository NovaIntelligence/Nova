param(
    [Parameter(Mandatory=$true)] [string]$LeadsCsv,
    [Parameter(Mandatory=$true)] [string]$OutDir,
    [string]$Channel = 'email',
    [string]$TemplatePath = $(Join-Path $PSScriptRoot 'templates/outreach-email.txt')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-File($Path) { if (-not (Test-Path $Path)) { throw "Missing file: $Path" } }
function New-CleanDir($Path) { if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null } }

Assert-File -Path $LeadsCsv
Assert-File -Path $TemplatePath

New-CleanDir -Path $OutDir
$emailsDir = Join-Path $OutDir 'outreach_emails'
$logsDir   = Join-Path $OutDir 'logs'
New-CleanDir -Path $emailsDir
New-CleanDir -Path $logsDir

$now = Get-Date
$runId = $now.ToString('yyyyMMdd_HHmmss')
$runLog = Join-Path $logsDir "run_$runId.log"

"[INFO] Outbound-Deal-Machine start $now" | Out-File -FilePath $runLog -Encoding UTF8
"[INFO] Leads: $LeadsCsv" | Out-File -FilePath $runLog -Append -Encoding UTF8
"[INFO] Channel: $Channel" | Out-File -FilePath $runLog -Append -Encoding UTF8

# Load template
$template = Get-Content -Path $TemplatePath -Raw -ErrorAction Stop

# Read leads
try {
    $leads = Import-Csv -Path $LeadsCsv
} catch {
    throw "Failed to read CSV. Ensure it has headers like Name,Email,Company,Title,Website,Notes. Error: $_"
}

if (-not $leads) { throw 'No leads found in CSV.' }

# Deduplicate and validate
$emailRegex = '^[^@\s]+@[^@\s]+\.[^@\s]+$'
$seen = @{}
$cleanLeads = @()
foreach ($lead in $leads) {
    $email = ('' + $lead.Email).Trim()
    if (-not $email -or ($email -notmatch $emailRegex)) { continue }
    if ($seen.ContainsKey($email)) { continue }
    $seen[$email] = $true
    $cleanLeads += $lead
}

if (-not $cleanLeads) { throw 'No valid leads after dedup/validation.' }

$generated = 0
foreach ($lead in $cleanLeads) {
    $name    = ('' + $lead.Name).Trim()
    $email   = ('' + $lead.Email).Trim()
    $company = ('' + $lead.Company).Trim()
    $title   = ('' + $lead.Title).Trim()
    $website = ('' + $lead.Website).Trim()
    $notes   = ('' + $lead.Notes).Trim()

    $body = $template
    $replacements = @{
        '{{name}}'    = $name
        '{{email}}'   = $email
        '{{company}}' = $company
        '{{title}}'   = $title
        '{{website}}' = $website
        '{{notes}}'   = $notes
        '{{today}}'   = (Get-Date).ToString('yyyy-MM-dd')
    }
    foreach ($k in $replacements.Keys) { $body = $body -replace [regex]::Escape($k), [System.Text.RegularExpressions.Regex]::Escape($replacements[$k]).Replace('\\','\') }

    $subject = "Quick idea for $company"
    $fileSafe = ($email -replace '[^a-zA-Z0-9._-]', '_')
    $outFile = Join-Path $emailsDir ("${fileSafe}.txt")
    @(
        "Subject: $subject"
        "To: $name <$email>"
        "Channel: $Channel"
        "---"
        $body
    ) | Out-File -FilePath $outFile -Encoding UTF8
    $generated++
}

# Next actions placeholder CSV for manual/auto dialer import
$nextActions = Join-Path $OutDir 'next_actions.csv'
@("Name,Email,Company,FirstTouchScheduledDate,Status") + (
    $cleanLeads | ForEach-Object { "$($_.Name),$($_.Email),$($_.Company),,PENDING" }
) | Out-File -FilePath $nextActions -Encoding UTF8

# Summary
$summary = [ordered]@{
    run_id        = $runId
    timestamp     = (Get-Date).ToString('o')
    input_csv     = (Resolve-Path $LeadsCsv).Path
    out_dir       = (Resolve-Path $OutDir).Path
    channel       = $Channel
    leads_in      = @($leads).Count
    leads_clean   = @($cleanLeads).Count
    emails_written= $generated
    artifacts     = @{
        outreach_emails = $emailsDir
        run_log         = $runLog
        next_actions    = $nextActions
    }
}
$summaryPath = Join-Path $OutDir 'summary.json'
$summary | ConvertTo-Json -Depth 6 | Out-File -FilePath $summaryPath -Encoding UTF8

"[INFO] Generated: $generated emails" | Out-File -FilePath $runLog -Append -Encoding UTF8
"[INFO] Done" | Out-File -FilePath $runLog -Append -Encoding UTF8

Write-Host "Outbound-Deal-Machine completed. Outputs in: $OutDir"
