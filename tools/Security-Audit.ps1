# Security-Audit.ps1 - Nova Bot Security Assessment Tool
# Creators: Tyler McKendry & Nova

param(
    [switch]$Comprehensive,
    [switch]$Quick,
    [string]$Output,
    [ValidateSet("Console", "JSON", "CSV")]$OutputFormat = "Console",
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"
$VerbosePreference = if ($Verbose) { "Continue" } else { "SilentlyContinue" }

# Initialize security audit structure
$script:SecurityAudit = @{
    Metadata = @{
        Timestamp = Get-Date
        Version = "1.0.0"
        ProjectRoot = Split-Path -Parent $PSScriptRoot
        AuditLevel = if ($Comprehensive) { "Comprehensive" } elseif ($Quick) { "Quick" } else { "Standard" }
    }
    Categories = @{}
    Summary = @{
        TotalIssues = 0
        CriticalIssues = 0
        HighIssues = 0
        MediumIssues = 0
        LowIssues = 0
        SecurityScore = 0
        Grade = ""
        Recommendations = @()
    }
}

# Security patterns and rules
$script:SecurityRules = @{
    Credentials = @{
        Patterns = @(
            @{ Pattern = "password\s*=\s*['\"](?!.*\$)[^'\"]{3,}['\"]"; Severity = "Critical"; Description = "Hardcoded password detected" },
            @{ Pattern = "api[_-]?key\s*=\s*['\"](?!.*\$)[^'\"]{10,}['\"]"; Severity = "Critical"; Description = "Hardcoded API key detected" },
            @{ Pattern = "secret\s*=\s*['\"](?!.*\$)[^'\"]{8,}['\"]"; Severity = "High"; Description = "Hardcoded secret detected" },
            @{ Pattern = "token\s*=\s*['\"](?!.*\$)[^'\"]{20,}['\"]"; Severity = "High"; Description = "Hardcoded token detected" },
            @{ Pattern = "connectionstring\s*=\s*['\"](?!.*\$)[^'\"]{10,}['\"]"; Severity = "Critical"; Description = "Hardcoded connection string detected" }
        )
    }
    
    Injection = @{
        Patterns = @(
            @{ Pattern = "Invoke-Expression\s*\`$"; Severity = "High"; Description = "Dynamic code execution with user input" },
            @{ Pattern = "iex\s*\`$"; Severity = "High"; Description = "Dynamic code execution with user input" },
            @{ Pattern = "&\s*\`$[a-zA-Z]"; Severity = "Medium"; Description = "Variable command execution" },
            @{ Pattern = "Start-Process.*\`$"; Severity = "Medium"; Description = "Dynamic process execution" }
        )
    }
    
    FileSystem = @{
        Patterns = @(
            @{ Pattern = "Remove-Item.*-Recurse.*-Force"; Severity = "High"; Description = "Dangerous recursive file deletion" },
            @{ Pattern = "rm\s.*-rf"; Severity = "High"; Description = "Dangerous recursive file deletion" },
            @{ Pattern = "Format-Volume|Format-Disk"; Severity = "Critical"; Description = "Disk formatting command" },
            @{ Pattern = "\.\.[\\/].*\.\.[\\/]"; Severity = "Medium"; Description = "Directory traversal pattern" }
        )
    }
    
    Network = @{
        Patterns = @(
            @{ Pattern = "http://(?!localhost|127\.0\.0\.1)"; Severity = "Medium"; Description = "Unencrypted HTTP connection" },
            @{ Pattern = "Invoke-WebRequest.*-SkipCertificateCheck"; Severity = "High"; Description = "Certificate validation bypassed" },
            @{ Pattern = "curl.*-k|wget.*--no-check-certificate"; Severity = "High"; Description = "Certificate validation bypassed" },
            @{ Pattern = "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"; Severity = "Low"; Description = "Hardcoded IP address" }
        )
    }
    
    Execution = @{
        Patterns = @(
            @{ Pattern = "Set-ExecutionPolicy.*Bypass.*-Force"; Severity = "High"; Description = "Execution policy bypass" },
            @{ Pattern = "Set-ExecutionPolicy.*Unrestricted"; Severity = "Medium"; Description = "Unrestricted execution policy" },
            @{ Pattern = "powershell.*-EncodedCommand"; Severity = "Medium"; Description = "Encoded PowerShell command" },
            @{ Pattern = "-noprofile.*-windowstyle.*hidden"; Severity = "Medium"; Description = "Hidden PowerShell execution" }
        )
    }
}

# Color scheme
$script:Colors = @{
    Critical = "Red"
    High = "Magenta"
    Medium = "Yellow"
    Low = "Cyan"
    Info = "White"
    Good = "Green"
    Header = "Blue"
}

function Write-SecurityLog {
    param(
        [string]$Message,
        [ValidateSet("Critical", "High", "Medium", "Low", "Info", "Good", "Header")]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = $script:Colors[$Level]
    
    Write-Host "[$timestamp] $Message" -ForegroundColor $color
    Write-Verbose $Message
}

function Get-SecurityGrade {
    param([int]$Score)
    
    switch ($Score) {
        { $_ -ge 90 } { return "A+" }
        { $_ -ge 85 } { return "A" }
        { $_ -ge 80 } { return "A-" }
        { $_ -ge 75 } { return "B+" }
        { $_ -ge 70 } { return "B" }
        { $_ -ge 65 } { return "B-" }
        { $_ -ge 60 } { return "C+" }
        { $_ -ge 55 } { return "C" }
        { $_ -ge 50 } { return "C-" }
        default { return "F" }
    }
}

function Test-CredentialSecurity {
    Write-SecurityLog "Scanning for credential exposure..." -Level "Info"
    
    $issues = @()
    $projectRoot = $script:SecurityAudit.Metadata.ProjectRoot
    
    # Get all PowerShell and config files
    $targetFiles = Get-ChildItem -Path $projectRoot -Recurse -Include "*.ps1", "*.psm1", "*.psd1", "*.config", "*.json", "*.yml", "*.yaml" |
        Where-Object { -not $_.FullName.Contains("Archive") -and -not $_.FullName.Contains(".git") }
    
    Write-SecurityLog "Scanning $($targetFiles.Count) files for credential patterns..." -Level "Info"
    
    foreach ($file in $targetFiles) {
        try {
            $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
            if ([string]::IsNullOrWhiteSpace($content)) { continue }
            
            foreach ($rule in $script:SecurityRules.Credentials.Patterns) {
                if ($content -match $rule.Pattern) {
                    $matches = [regex]::Matches($content, $rule.Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    
                    foreach ($match in $matches) {
                        # Get line number
                        $lines = $content.Substring(0, $match.Index) -split "`n"
                        $lineNumber = $lines.Count
                        
                        $issues += @{
                            Category = "Credentials"
                            Severity = $rule.Severity
                            Description = $rule.Description
                            File = $file.FullName.Replace($projectRoot, "").TrimStart("\")
                            LineNumber = $lineNumber
                            Match = $match.Value.Substring(0, [Math]::Min($match.Value.Length, 50)) + "..."
                            Recommendation = "Move credential to environment variable or secure storage"
                        }
                    }
                }
            }
        } catch {
            Write-SecurityLog "Error scanning file $($file.FullName): $($_.Exception.Message)" -Level "Medium"
        }
    }
    
    return @{
        Issues = $issues
        FilesScanned = $targetFiles.Count
        IssuesFound = $issues.Count
    }
}

function Test-CodeInjectionVulnerabilities {
    Write-SecurityLog "Scanning for code injection vulnerabilities..." -Level "Info"
    
    $issues = @()
    $projectRoot = $script:SecurityAudit.Metadata.ProjectRoot
    
    $psFiles = Get-ChildItem -Path $projectRoot -Recurse -Include "*.ps1", "*.psm1" |
        Where-Object { -not $_.FullName.Contains("Archive") -and -not $_.FullName.Contains(".git") }
    
    foreach ($file in $psFiles) {
        try {
            $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
            if ([string]::IsNullOrWhiteSpace($content)) { continue }
            
            foreach ($rule in $script:SecurityRules.Injection.Patterns) {
                if ($content -match $rule.Pattern) {
                    $matches = [regex]::Matches($content, $rule.Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    
                    foreach ($match in $matches) {
                        $lines = $content.Substring(0, $match.Index) -split "`n"
                        $lineNumber = $lines.Count
                        
                        $issues += @{
                            Category = "Code Injection"
                            Severity = $rule.Severity
                            Description = $rule.Description
                            File = $file.FullName.Replace($projectRoot, "").TrimStart("\")
                            LineNumber = $lineNumber
                            Match = $match.Value
                            Recommendation = "Validate and sanitize all user inputs before execution"
                        }
                    }
                }
            }
        } catch {
            Write-SecurityLog "Error scanning file $($file.FullName): $($_.Exception.Message)" -Level "Medium"
        }
    }
    
    return @{
        Issues = $issues
        FilesScanned = $psFiles.Count
        IssuesFound = $issues.Count
    }
}

function Test-FileSystemSecurity {
    Write-SecurityLog "Scanning for file system security issues..." -Level "Info"
    
    $issues = @()
    $projectRoot = $script:SecurityAudit.Metadata.ProjectRoot
    
    $psFiles = Get-ChildItem -Path $projectRoot -Recurse -Include "*.ps1", "*.psm1" |
        Where-Object { -not $_.FullName.Contains("Archive") -and -not $_.FullName.Contains(".git") }
    
    foreach ($file in $psFiles) {
        try {
            $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
            if ([string]::IsNullOrWhiteSpace($content)) { continue }
            
            foreach ($rule in $script:SecurityRules.FileSystem.Patterns) {
                if ($content -match $rule.Pattern) {
                    $matches = [regex]::Matches($content, $rule.Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    
                    foreach ($match in $matches) {
                        $lines = $content.Substring(0, $match.Index) -split "`n"
                        $lineNumber = $lines.Count
                        
                        $issues += @{
                            Category = "File System"
                            Severity = $rule.Severity
                            Description = $rule.Description
                            File = $file.FullName.Replace($projectRoot, "").TrimStart("\")
                            LineNumber = $lineNumber
                            Match = $match.Value
                            Recommendation = "Add proper validation and confirmation prompts for destructive operations"
                        }
                    }
                }
            }
        } catch {
            Write-SecurityLog "Error scanning file $($file.FullName): $($_.Exception.Message)" -Level "Medium"
        }
    }
    
    return @{
        Issues = $issues
        FilesScanned = $psFiles.Count
        IssuesFound = $issues.Count
    }
}

function Test-NetworkSecurity {
    Write-SecurityLog "Scanning for network security issues..." -Level "Info"
    
    $issues = @()
    $projectRoot = $script:SecurityAudit.Metadata.ProjectRoot
    
    $allFiles = Get-ChildItem -Path $projectRoot -Recurse -Include "*.ps1", "*.psm1", "*.config", "*.json", "*.yml" |
        Where-Object { -not $_.FullName.Contains("Archive") -and -not $_.FullName.Contains(".git") }
    
    foreach ($file in $allFiles) {
        try {
            $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
            if ([string]::IsNullOrWhiteSpace($content)) { continue }
            
            foreach ($rule in $script:SecurityRules.Network.Patterns) {
                if ($content -match $rule.Pattern) {
                    $matches = [regex]::Matches($content, $rule.Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    
                    foreach ($match in $matches) {
                        $lines = $content.Substring(0, $match.Index) -split "`n"
                        $lineNumber = $lines.Count
                        
                        $issues += @{
                            Category = "Network Security"
                            Severity = $rule.Severity
                            Description = $rule.Description
                            File = $file.FullName.Replace($projectRoot, "").TrimStart("\")
                            LineNumber = $lineNumber
                            Match = $match.Value
                            Recommendation = "Use HTTPS connections and proper certificate validation"
                        }
                    }
                }
            }
        } catch {
            Write-SecurityLog "Error scanning file $($file.FullName): $($_.Exception.Message)" -Level "Medium"
        }
    }
    
    return @{
        Issues = $issues
        FilesScanned = $allFiles.Count
        IssuesFound = $issues.Count
    }
}

function Test-ExecutionSecurity {
    Write-SecurityLog "Scanning for execution security issues..." -Level "Info"
    
    $issues = @()
    $projectRoot = $script:SecurityAudit.Metadata.ProjectRoot
    
    $psFiles = Get-ChildItem -Path $projectRoot -Recurse -Include "*.ps1", "*.psm1" |
        Where-Object { -not $_.FullName.Contains("Archive") -and -not $_.FullName.Contains(".git") }
    
    foreach ($file in $psFiles) {
        try {
            $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
            if ([string]::IsNullOrWhiteSpace($content)) { continue }
            
            foreach ($rule in $script:SecurityRules.Execution.Patterns) {
                if ($content -match $rule.Pattern) {
                    $matches = [regex]::Matches($content, $rule.Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    
                    foreach ($match in $matches) {
                        $lines = $content.Substring(0, $match.Index) -split "`n"
                        $lineNumber = $lines.Count
                        
                        $issues += @{
                            Category = "Execution Security"
                            Severity = $rule.Severity
                            Description = $rule.Description
                            File = $file.FullName.Replace($projectRoot, "").TrimStart("\")
                            LineNumber = $lineNumber
                            Match = $match.Value
                            Recommendation = "Use proper execution policies and avoid bypassing security controls"
                        }
                    }
                }
            }
        } catch {
            Write-SecurityLog "Error scanning file $($file.FullName): $($_.Exception.Message)" -Level "Medium"
        }
    }
    
    return @{
        Issues = $issues
        FilesScanned = $psFiles.Count
        IssuesFound = $issues.Count
    }
}

function Test-PermissionsSecurity {
    if (-not $Comprehensive) { return @{ Issues = @(); Message = "Skipped in non-comprehensive mode" } }
    
    Write-SecurityLog "Checking file and directory permissions..." -Level "Info"
    
    $issues = @()
    $projectRoot = $script:SecurityAudit.Metadata.ProjectRoot
    
    try {
        # Check for world-writable files
        $files = Get-ChildItem -Path $projectRoot -Recurse -File | Where-Object { -not $_.FullName.Contains("Archive") }
        
        foreach ($file in $files) {
            try {
                $acl = Get-Acl $file.FullName -ErrorAction SilentlyContinue
                if ($acl) {
                    $worldWritable = $acl.Access | Where-Object { 
                        $_.IdentityReference -eq "Everyone" -and 
                        $_.AccessControlType -eq "Allow" -and 
                        ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Write)
                    }
                    
                    if ($worldWritable) {
                        $issues += @{
                            Category = "Permissions"
                            Severity = "Medium"
                            Description = "World-writable file detected"
                            File = $file.FullName.Replace($projectRoot, "").TrimStart("\")
                            LineNumber = 0
                            Match = "Everyone: Write"
                            Recommendation = "Restrict file permissions to authorized users only"
                        }
                    }
                }
            } catch {
                # Skip files we can't access
            }
        }
    } catch {
        Write-SecurityLog "Error checking permissions: $($_.Exception.Message)" -Level "Medium"
    }
    
    return @{
        Issues = $issues
        FilesScanned = $files.Count
        IssuesFound = $issues.Count
    }
}

function Invoke-SecurityAudit {
    Write-SecurityLog "Starting Nova Security Audit..." -Level "Header"
    
    $auditTests = @(
        @{ Name = "Credential Security"; Test = { Test-CredentialSecurity } },
        @{ Name = "Code Injection"; Test = { Test-CodeInjectionVulnerabilities } },
        @{ Name = "File System Security"; Test = { Test-FileSystemSecurity } },
        @{ Name = "Network Security"; Test = { Test-NetworkSecurity } },
        @{ Name = "Execution Security"; Test = { Test-ExecutionSecurity } }
    )
    
    if ($Comprehensive) {
        $auditTests += @{ Name = "Permissions"; Test = { Test-PermissionsSecurity } }
    }
    
    $allIssues = @()
    
    foreach ($test in $auditTests) {
        Write-SecurityLog "Running $($test.Name) audit..." -Level "Info"
        
        try {
            $result = & $test.Test
            
            $script:SecurityAudit.Categories[$test.Name] = @{
                Issues = $result.Issues
                FilesScanned = if ($result.FilesScanned) { $result.FilesScanned } else { 0 }
                IssuesFound = $result.IssuesFound
                Message = if ($result.Message) { $result.Message } else { "" }
            }
            
            $allIssues += $result.Issues
            
        } catch {
            Write-SecurityLog "Error in $($test.Name): $($_.Exception.Message)" -Level "High"
            
            $script:SecurityAudit.Categories[$test.Name] = @{
                Issues = @()
                FilesScanned = 0
                IssuesFound = 0
                Message = "Error during scan: $($_.Exception.Message)"
            }
        }
    }
    
    # Calculate summary statistics
    $criticalCount = ($allIssues | Where-Object { $_.Severity -eq "Critical" }).Count
    $highCount = ($allIssues | Where-Object { $_.Severity -eq "High" }).Count
    $mediumCount = ($allIssues | Where-Object { $_.Severity -eq "Medium" }).Count
    $lowCount = ($allIssues | Where-Object { $_.Severity -eq "Low" }).Count
    
    $script:SecurityAudit.Summary.TotalIssues = $allIssues.Count
    $script:SecurityAudit.Summary.CriticalIssues = $criticalCount
    $script:SecurityAudit.Summary.HighIssues = $highCount
    $script:SecurityAudit.Summary.MediumIssues = $mediumCount
    $script:SecurityAudit.Summary.LowIssues = $lowCount
    
    # Calculate security score (100 - penalty points)
    $penalties = ($criticalCount * 20) + ($highCount * 10) + ($mediumCount * 5) + ($lowCount * 1)
    $script:SecurityAudit.Summary.SecurityScore = [Math]::Max(0, 100 - $penalties)
    $script:SecurityAudit.Summary.Grade = Get-SecurityGrade $script:SecurityAudit.Summary.SecurityScore
    
    # Generate recommendations
    $recommendations = @()
    if ($criticalCount -gt 0) { $recommendations += "URGENT: Address $criticalCount critical security issues immediately" }
    if ($highCount -gt 0) { $recommendations += "Address $highCount high-severity security issues" }
    if ($mediumCount -gt 5) { $recommendations += "Review and address medium-severity security issues" }
    if ($allIssues.Count -eq 0) { $recommendations += "Excellent! No security issues detected" }
    
    $script:SecurityAudit.Summary.Recommendations = $recommendations
    
    Write-SecurityLog "Security Audit Complete!" -Level "Header"
}

function Format-ConsoleOutput {
    $audit = $script:SecurityAudit
    
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor $script:Colors.Header
    Write-Host "║                    NOVA SECURITY AUDIT                       ║" -ForegroundColor $script:Colors.Header  
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor $script:Colors.Header
    Write-Host ""
    
    # Summary
    $scoreColor = if ($audit.Summary.SecurityScore -ge 80) { "Good" } 
                 elseif ($audit.Summary.SecurityScore -ge 60) { "Medium" }
                 else { "Critical" }
    
    Write-Host "🛡️  SECURITY SCORE: " -NoNewline -ForegroundColor $script:Colors.Info
    Write-Host "$($audit.Summary.SecurityScore)/100" -NoNewline -ForegroundColor $script:Colors[$scoreColor]
    Write-Host " (" -NoNewline -ForegroundColor $script:Colors.Info
    Write-Host "$($audit.Summary.Grade)" -NoNewline -ForegroundColor $script:Colors[$scoreColor]
    Write-Host ")" -ForegroundColor $script:Colors.Info
    
    Write-Host "📊 TOTAL ISSUES: $($audit.Summary.TotalIssues)" -ForegroundColor $script:Colors.Info
    Write-Host "🔴 CRITICAL: $($audit.Summary.CriticalIssues)" -ForegroundColor $script:Colors.Critical
    Write-Host "🟠 HIGH: $($audit.Summary.HighIssues)" -ForegroundColor $script:Colors.High
    Write-Host "🟡 MEDIUM: $($audit.Summary.MediumIssues)" -ForegroundColor $script:Colors.Medium
    Write-Host "🔵 LOW: $($audit.Summary.LowIssues)" -ForegroundColor $script:Colors.Low
    Write-Host "📅 AUDITED: $($audit.Metadata.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor $script:Colors.Info
    Write-Host ""
    
    # Category Breakdown
    Write-Host "📋 CATEGORY BREAKDOWN:" -ForegroundColor $script:Colors.Header
    Write-Host "─" * 60 -ForegroundColor $script:Colors.Info
    
    foreach ($category in $audit.Categories.GetEnumerator()) {
        $name = $category.Key.PadRight(25)
        $issueCount = $category.Value.IssuesFound
        $filesScanned = $category.Value.FilesScanned
        
        $statusColor = if ($issueCount -eq 0) { "Good" }
                      elseif ($issueCount -le 2) { "Medium" }
                      else { "High" }
        
        Write-Host "  $name" -NoNewline -ForegroundColor $script:Colors.Info
        Write-Host "$issueCount issues" -NoNewline -ForegroundColor $script:Colors[$statusColor]
        Write-Host " ($filesScanned files scanned)" -ForegroundColor Gray
        
        if ($category.Value.Message) {
            Write-Host "    • $($category.Value.Message)" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    
    # Issues Detail (if not quick mode)
    if (-not $Quick -and $audit.Summary.TotalIssues -gt 0) {
        Write-Host "🔍 SECURITY ISSUES FOUND:" -ForegroundColor $script:Colors.Header
        Write-Host "─" * 60 -ForegroundColor $script:Colors.Info
        
        $issuesByCategory = @{}
        foreach ($category in $audit.Categories.GetEnumerator()) {
            if ($category.Value.Issues.Count -gt 0) {
                $issuesByCategory[$category.Key] = $category.Value.Issues
            }
        }
        
        foreach ($categoryName in $issuesByCategory.Keys) {
            Write-Host ""
            Write-Host "📂 $categoryName" -ForegroundColor $script:Colors.Header
            
            $categoryIssues = $issuesByCategory[$categoryName] | Sort-Object { 
                switch ($_.Severity) {
                    "Critical" { 4 }
                    "High" { 3 }
                    "Medium" { 2 }
                    "Low" { 1 }
                }
            } -Descending
            
            foreach ($issue in $categoryIssues) {
                $severityColor = $script:Colors[$issue.Severity]
                Write-Host "  [$($issue.Severity)] " -NoNewline -ForegroundColor $severityColor
                Write-Host "$($issue.Description)" -ForegroundColor $script:Colors.Info
                Write-Host "    📄 File: $($issue.File):$($issue.LineNumber)" -ForegroundColor Gray
                if ($issue.Match -and $issue.Match.Length -lt 100) {
                    Write-Host "    🔍 Match: $($issue.Match)" -ForegroundColor Gray
                }
                Write-Host "    💡 $($issue.Recommendation)" -ForegroundColor Yellow
                Write-Host ""
            }
        }
    }
    
    # Recommendations
    if ($audit.Summary.Recommendations.Count -gt 0) {
        Write-Host "💡 RECOMMENDATIONS:" -ForegroundColor $script:Colors.Header
        Write-Host "─" * 60 -ForegroundColor $script:Colors.Info
        
        for ($i = 0; $i -lt $audit.Summary.Recommendations.Count; $i++) {
            Write-Host "  $($i + 1). $($audit.Summary.Recommendations[$i])" -ForegroundColor Yellow
        }
        Write-Host ""
    }
}

function Export-SecurityAuditJson {
    param([string]$Path)
    
    $jsonOutput = $script:SecurityAudit | ConvertTo-Json -Depth 10
    
    if ($Path) {
        Set-Content -Path $Path -Value $jsonOutput -Encoding UTF8
        Write-SecurityLog "Security audit exported to: $Path" -Level "Good"
    } else {
        return $jsonOutput
    }
}

function Export-SecurityAuditCsv {
    param([string]$Path)
    
    $allIssues = @()
    foreach ($category in $script:SecurityAudit.Categories.GetEnumerator()) {
        foreach ($issue in $category.Value.Issues) {
            $allIssues += [PSCustomObject]@{
                Category = $category.Key
                Severity = $issue.Severity
                Description = $issue.Description
                File = $issue.File
                LineNumber = $issue.LineNumber
                Match = $issue.Match
                Recommendation = $issue.Recommendation
                Timestamp = $script:SecurityAudit.Metadata.Timestamp.ToString('yyyy-MM-dd HH:mm:ss')
            }
        }
    }
    
    if ($Path) {
        $allIssues | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
        Write-SecurityLog "Security audit CSV exported to: $Path" -Level "Good"
    } else {
        return $allIssues
    }
}

# Main execution
try {
    Invoke-SecurityAudit
    
    switch ($OutputFormat) {
        "Console" { 
            Format-ConsoleOutput 
        }
        "JSON" { 
            if ($Output) {
                Export-SecurityAuditJson -Path $Output
            } else {
                Export-SecurityAuditJson
            }
        }
        "CSV" { 
            if ($Output) {
                Export-SecurityAuditCsv -Path $Output
            } else {
                $csvFile = Join-Path $script:SecurityAudit.Metadata.ProjectRoot "security-audit.csv"
                Export-SecurityAuditCsv -Path $csvFile
                Write-SecurityLog "CSV report saved to: $csvFile" -Level "Good"
            }
        }
    }
    
    $statusLevel = if ($script:SecurityAudit.Summary.CriticalIssues -gt 0) { "Critical" }
                  elseif ($script:SecurityAudit.Summary.HighIssues -gt 0) { "High" }
                  elseif ($script:SecurityAudit.Summary.TotalIssues -gt 0) { "Medium" }
                  else { "Good" }
    
    Write-SecurityLog "Security Audit Complete! Score: $($script:SecurityAudit.Summary.SecurityScore)/100 ($($script:SecurityAudit.Summary.Grade)) - $($script:SecurityAudit.Summary.TotalIssues) issues found" -Level $statusLevel
    
    # Exit with appropriate code for CI/CD
    if ($script:SecurityAudit.Summary.CriticalIssues -gt 0) {
        exit 2  # Critical issues
    } elseif ($script:SecurityAudit.Summary.HighIssues -gt 0) {
        exit 1  # High issues
    } else {
        exit 0  # Success
    }
    
} catch {
    Write-Error "Security Audit failed: $($_.Exception.Message)"
    exit 3
}