# Learn-Nightly.ps1 - Nova Bot Nightly Learning Loop
# Creators: Tyler McKendry & Nova
# 
# Processes daily logs and memory notes to create structured lessons and update knowledge base

param(
    [string]$Date = (Get-Date -Format "yyyy-MM-dd"),
    [switch]$CreateScheduledTask,
    [switch]$Verbose
)

# Import required modules
$LogShimPath = Join-Path $PSScriptRoot "_nova_logshim.psm1"
if (Test-Path $LogShimPath) {
    Import-Module $LogShimPath -Force
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    if (Get-Command "Write-NovaLog" -ErrorAction SilentlyContinue) {
        Write-NovaLog -Message $Message -Level $Level -Component "Learn-Nightly"
    } else {
        Write-Host "[$Level] $(Get-Date -Format 'HH:mm:ss') Learn-Nightly: $Message"
    }
}

function Get-TodaysLogs {
    param([string]$TargetDate)
    
    Write-Log "Collecting logs for $TargetDate"
    
    $logs = @()
    $logPatterns = @(
        "D:\Nova\bot\data\metrics\*.jsonl",
        "D:\Nova\logs\*.log",
        "D:\Nova\bot\logs\*.jsonl"
    )
    
    foreach ($pattern in $logPatterns) {
        if (Test-Path (Split-Path $pattern -Parent)) {
            $files = Get-ChildItem $pattern -ErrorAction SilentlyContinue | Where-Object {
                $_.LastWriteTime.ToString("yyyy-MM-dd") -eq $TargetDate
            }
            
            foreach ($file in $files) {
                Write-Log "Processing log file: $($file.Name)"
                try {
                    $content = Get-Content $file.FullName -Raw
                    $logs += @{
                        Source = $file.Name
                        Content = $content
                        Path = $file.FullName
                    }
                }
                catch {
                    Write-Log "Failed to read $($file.FullName): $_" -Level "WARN"
                }
            }
        }
    }
    
    Write-Log "Collected $($logs.Count) log files"
    return $logs
}

function Get-MemoryNotes {
    param([string]$TargetDate)
    
    Write-Log "Collecting memory notes"
    
    $notes = @()
    $memoryPaths = @(
        "D:\Nova\bot\memory",
        "D:\Nova\memory"
    )
    
    foreach ($path in $memoryPaths) {
        if (Test-Path $path) {
            $files = Get-ChildItem "$path\*.md", "$path\*.txt" -Recurse -ErrorAction SilentlyContinue | Where-Object {
                $_.LastWriteTime.ToString("yyyy-MM-dd") -eq $TargetDate
            }
            
            foreach ($file in $files) {
                Write-Log "Processing memory note: $($file.Name)"
                try {
                    $content = Get-Content $file.FullName -Raw
                    $notes += @{
                        Source = $file.Name
                        Content = $content
                        Path = $file.FullName
                    }
                }
                catch {
                    Write-Log "Failed to read $($file.FullName): $_" -Level "WARN"
                }
            }
        }
    }
    
    Write-Log "Collected $($notes.Count) memory notes"
    return $notes
}

function Invoke-OpenAISummarization {
    param(
        [array]$Logs,
        [array]$Notes,
        [string]$Date
    )
    
    $apiKey = $env:NOVA_OPENAI_KEY
    if (-not $apiKey) {
        Write-Log "NOVA_OPENAI_KEY not found, using heuristic fallback" -Level "WARN"
        return $null
    }
    
    Write-Log "Using OpenAI for intelligent summarization"
    
    # Prepare combined content
    $logContent = ($Logs | ForEach-Object { "=== $($_.Source) ===`n$($_.Content)`n" }) -join "`n"
    $noteContent = ($Notes | ForEach-Object { "=== $($_.Source) ===`n$($_.Content)`n" }) -join "`n"
    
    $prompt = @"
Analyze the following Nova Bot logs and memory notes from $Date and create a structured learning summary:

LOGS:
$logContent

NOTES:
$noteContent

Please create a structured summary with these sections:
1. SIGNALS: Key patterns, metrics, or events observed
2. FAILURES: Errors, issues, or problems that occurred  
3. REMEDIES: Solutions applied or recommended fixes
4. NEW RULES: Derived principles or rules for future operations

Format as markdown with clear headers and bullet points. Focus on actionable insights.
"@

    try {
        $headers = @{
            'Authorization' = "Bearer $apiKey"
            'Content-Type' = 'application/json'
        }
        
        $body = @{
            model = "gpt-3.5-turbo"
            messages = @(
                @{
                    role = "system"
                    content = "You are Nova Bot's learning system. Analyze logs and create structured learning summaries."
                },
                @{
                    role = "user"  
                    content = $prompt
                }
            )
            max_tokens = 2000
            temperature = 0.3
        } | ConvertTo-Json -Depth 10
        
        $response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" -Method POST -Headers $headers -Body $body
        
        if ($response.choices -and $response.choices[0].message.content) {
            Write-Log "OpenAI summarization successful"
            return $response.choices[0].message.content
        }
    }
    catch {
        Write-Log "OpenAI API call failed: $_" -Level "ERROR"
    }
    
    return $null
}

function Invoke-HeuristicSummarization {
    param(
        [array]$Logs,
        [array]$Notes,
        [string]$Date
    )
    
    Write-Log "Performing heuristic summarization"
    
    # Simple pattern-based analysis
    $allContent = ($Logs + $Notes | ForEach-Object { $_.Content }) -join " "
    
    # Extract common patterns
    $errors = ($allContent | Select-String -Pattern "\[ERROR\]|\bfail|\berror\b|\bexception\b" -AllMatches).Matches.Count
    $warnings = ($allContent | Select-String -Pattern "\[WARN\]|\bwarning\b" -AllMatches).Matches.Count
    $successes = ($allContent | Select-String -Pattern "\[INFO\]|\bsuccess\b|\bcomplete\b|\bok\b" -AllMatches).Matches.Count
    
    # Generate summary
    $summary = @"
# Nova Bot Learning Summary - $Date
*Creators: Tyler McKendry & Nova*

## SIGNALS
- Total log entries processed: $($Logs.Count + $Notes.Count)
- Error indicators detected: $errors
- Warning indicators detected: $warnings  
- Success indicators detected: $successes

## FAILURES
- Detected $errors potential error conditions in logs
- System stability: $(if ($errors -lt 5) { "Good" } elseif ($errors -lt 20) { "Moderate" } else { "Needs attention" })

## REMEDIES
- Continue monitoring error patterns
- Review logs with high error counts
- Maintain current successful operations

## NEW RULES
- Monitor error-to-success ratio (current: $(if ($successes -gt 0) { [math]::Round($errors/$successes, 2) } else { "N/A" }))
- Focus on reducing warning indicators
- Preserve successful operational patterns

*Generated using heuristic analysis*
"@

    return $summary
}

function New-LessonFile {
    param(
        [string]$Date,
        [string]$Summary
    )
    
    $lessonsDir = "D:\Nova\bot\memory\lessons"
    $lessonFile = Join-Path $lessonsDir "$Date.md"
    
    Write-Log "Creating lesson file: $lessonFile"
    
    # Ensure summary has proper header
    if ($Summary -notmatch "Creators: Tyler McKendry & Nova") {
        $Summary = "# Nova Bot Learning Summary - $Date`n*Creators: Tyler McKendry & Nova*`n`n" + $Summary
    }
    
    Set-Content -Path $lessonFile -Value $Summary -Encoding UTF8
    
    Write-Log "Lesson file created successfully"
    return $lessonFile
}

function Update-KnowledgeBase {
    param(
        [string]$Date,
        [string]$Summary
    )
    
    $knowledgeFile = "D:\Nova\bot\memory\knowledge.jsonl"
    
    Write-Log "Updating knowledge base"
    
    # Extract rules from summary
    $rules = @()
    if ($Summary -match "## NEW RULES(.*?)(?=##|\z)") {
        $rulesSection = $matches[1]
        $rules = $rulesSection -split "`n" | Where-Object { $_ -match "^-\s*(.+)" } | ForEach-Object {
            $matches[1].Trim()
        }
    }
    
    # Create knowledge entry
    $knowledgeEntry = @{
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        date = $Date
        topic = "daily_learning"
        rules = $rules
        summary_length = $Summary.Length
        generated_by = "Learn-Nightly.ps1"
    }
    
    # Check if entry for today already exists
    $existingEntries = @()
    if (Test-Path $knowledgeFile) {
        $existingEntries = Get-Content $knowledgeFile | Where-Object { $_ -and $_.Trim() } | ForEach-Object {
            try { $_ | ConvertFrom-Json } catch { $null }
        } | Where-Object { $_ -and $_.date -ne $Date }
    }
    
    # Add new entry
    $allEntries = $existingEntries + $knowledgeEntry
    
    # Write back to file
    $allEntries | ForEach-Object { $_ | ConvertTo-Json -Compress } | Set-Content $knowledgeFile -Encoding UTF8
    
    Write-Log "Knowledge base updated with $($rules.Count) new rules"
}

function New-ScheduledTask {
    Write-Log "Creating scheduled task for nightly learning"
    
    $taskName = "Nova-NightlyLearning"
    $scriptPath = $PSCommandPath
    
    # Remove existing task if it exists
    try {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}
    
    # Create new task
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -Daily -At "23:50"
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Nova Bot Nightly Learning Loop"
    
    Write-Log "Scheduled task '$taskName' created successfully"
}

# Main execution
try {
    Write-Log "Starting nightly learning loop for $Date"
    
    if ($CreateScheduledTask) {
        New-ScheduledTask
        return
    }
    
    # Collect data
    $logs = Get-TodaysLogs -TargetDate $Date
    $notes = Get-MemoryNotes -TargetDate $Date
    
    if ($logs.Count -eq 0 -and $notes.Count -eq 0) {
        Write-Log "No logs or notes found for $Date" -Level "WARN"
        return
    }
    
    # Generate summary
    $summary = Invoke-OpenAISummarization -Logs $logs -Notes $notes -Date $Date
    
    if (-not $summary) {
        $summary = Invoke-HeuristicSummarization -Logs $logs -Notes $notes -Date $Date
    }
    
    # Create outputs
    $lessonFile = New-LessonFile -Date $Date -Summary $summary
    Update-KnowledgeBase -Date $Date -Summary $summary
    
    Write-Log "Nightly learning completed successfully"
    Write-Log "Lesson file: $lessonFile"
    
    if ($Verbose) {
        Write-Host "`nLesson Summary:" -ForegroundColor Cyan
        Write-Host $summary
    }
}
catch {
    Write-Log "Nightly learning failed: $_" -Level "ERROR"
    exit 1
}