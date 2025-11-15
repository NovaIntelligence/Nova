param(
    [Parameter(Mandatory=$true)] [string]$LeadsCsv,
    [Parameter(Mandatory=$true)] [string]$OutDir,
    [string]$Channel = 'email',
    [string]$TemplatePath = $(Join-Path $PSScriptRoot 'templates/outreach-email.txt'),
    [switch]$SendViaSmtp,
    [string]$SmtpFrom,
    [string]$SmtpHost,
    [int]$SmtpPort,
    [string]$SmtpUser,
    [string]$SmtpPassword,
    [switch]$SmtpUseSsl
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

# SMTP configuration (safe-by-default: requires both -SendViaSmtp and OUTBOUND_SEND_ENABLED=true)
$smtp = [ordered]@{
    enabled     = [bool]$SendViaSmtp
    allow_live  = (($env:OUTBOUND_SEND_ENABLED + '').ToLowerInvariant() -eq 'true')
    from        = if ($SmtpFrom) { $SmtpFrom } elseif ($env:SMTP_FROM) { $env:SMTP_FROM } else { $null }
    host        = if ($SmtpHost) { $SmtpHost } elseif ($env:SMTP_HOST) { $env:SMTP_HOST } else { $null }
    port        = if ($SmtpPort) { $SmtpPort } elseif ($env:SMTP_PORT) { [int]$env:SMTP_PORT } else { 587 }
    user        = if ($SmtpUser) { $SmtpUser } elseif ($env:SMTP_USER) { $env:SMTP_USER } else { $null }
    pass        = if ($SmtpPassword) { $SmtpPassword } elseif ($env:SMTP_PASS) { $env:SMTP_PASS } else { $null }
    ssl         = if ($SmtpUseSsl.IsPresent) { $true } elseif ($env:SMTP_USE_SSL) { (($env:SMTP_USE_SSL + '').ToLowerInvariant() -eq 'true') } else { $true }
}
$smtpReady = ($smtp.from -and $smtp.host -and $smtp.port)

"[INFO] SMTP: enabled=$($smtp.enabled) allow_live=$($smtp.allow_live) host=$($smtp.host) port=$($smtp.port) ssl=$($smtp.ssl) from=$($smtp.from) ready=$smtpReady" |
    Out-File -FilePath $runLog -Append -Encoding UTF8

function Send-OutreachEmail {
    param(
        [hashtable]$Smtp,
        [string]$ToName,
        [string]$ToEmail,
        [string]$Subject,
        [string]$Body
    )
    # Double safety: only send if explicitly enabled and allowed via env gate
    if (-not $Smtp.enabled -or -not $Smtp.allow_live) { return @{ sent = $false; reason = 'disabled_or_gate_off' } }
    if (-not ($Smtp.from -and $Smtp.host -and $Smtp.port)) { return @{ sent = $false; reason = 'incomplete_smtp_config' } }

    $mail = New-Object System.Net.Mail.MailMessage
    try {
        $mail.From = $Smtp.from
        [void]$mail.To.Add("$ToName <$ToEmail>")
        $mail.Subject = $Subject
        $mail.Body = $Body
        $mail.IsBodyHtml = $false

        $client = New-Object System.Net.Mail.SmtpClient($Smtp.host, [int]$Smtp.port)
        try {
            $client.EnableSsl = [bool]$Smtp.ssl
            if ($Smtp.user) {
                $client.Credentials = New-Object System.Net.NetworkCredential($Smtp.user, $Smtp.pass)
            } else {
                $client.UseDefaultCredentials = $true
            }
            $client.Send($mail)
            return @{ sent = $true }
        } finally {
            $client.Dispose()
        }
    } catch {
        return @{ sent = $false; reason = ('' + $_.Exception.Message) }
    } finally {
        $mail.Dispose()
    }
}

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
$smtpAttempted = 0
$smtpSent = 0
$smtpSkipped = 0
$smtpErrors = @()
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

    # Optional SMTP send (safe-by-default)
    if ($smtp.enabled) {
        $smtpAttempted++
        $result = Send-OutreachEmail -Smtp $smtp -ToName $name -ToEmail $email -Subject $subject -Body $body
        if ($result.sent) {
            $smtpSent++
            "[INFO] SMTP sent to $email" | Out-File -FilePath $runLog -Append -Encoding UTF8
        } else {
            $smtpSkipped++
            $reason = $result.reason
            if ($reason) { $smtpErrors += $reason }
            "[INFO] SMTP skipped for $email reason=${reason}" | Out-File -FilePath $runLog -Append -Encoding UTF8
        }
    }
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
    smtp          = [ordered]@{
        enabled      = $smtp.enabled
        allow_live   = $smtp.allow_live
        configured   = $smtpReady
        attempted    = $smtpAttempted
        sent         = $smtpSent
        skipped      = $smtpSkipped
        last_error   = if ($smtpErrors.Count -gt 0) { $smtpErrors[-1] } else { $null }
    }
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
