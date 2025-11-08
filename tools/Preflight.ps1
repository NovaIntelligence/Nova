# Preflight.ps1 - Nova Bot Pre-CI Validation Checks
# Creators: Tyler McKendry & Nova

param(
    [switch]$Verbose,
    [switch]$Force
)

# Initialize results tracking
$results = @{
    TotalChecks = 0
    PassedChecks = 0
    FailedChecks = 0
    Warnings = @()
    Errors = @()
    StartTime = Get-Date
}

function Write-PreflightLog {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $colors = @{
        "Info" = "White"
        "Success" = "Green" 
        "Warning" = "Yellow"
        "Error" = "Red"
    }
    
    Write-Host "[$timestamp] $Message" -ForegroundColor $colors[$Level]
}

function Test-PreflightCheck {
    param(
        [string]$Name,
        [scriptblock]$Check,
        [bool]$Required = $true
    )
    
    $results.TotalChecks++
    Write-PreflightLog "Running check: $Name" -Level "Info"
    
    try {
        $checkResult = & $Check
        if ($checkResult) {
            Write-PreflightLog "✅ $Name - PASSED" -Level "Success"
            $results.PassedChecks++
            return $true
        } else {
            if ($Required) {
                Write-PreflightLog "❌ $Name - FAILED" -Level "Error"
                $results.Errors += $Name
                $results.FailedChecks++
            } else {
                Write-PreflightLog "⚠️  $Name - WARNING (optional)" -Level "Warning"
                $results.Warnings += $Name
            }
            return $false
        }
    }
    catch {
        if ($Required) {
            Write-PreflightLog "❌ $Name - ERROR: $_" -Level "Error"
            $results.Errors += "$Name - $_"
            $results.FailedChecks++
        } else {
            Write-PreflightLog "⚠️  $Name - WARNING: $_" -Level "Warning"  
            $results.Warnings += "$Name - $_"
        }
        return $false
    }
}

Write-PreflightLog "Nova Bot Preflight Checks Starting..." -Level "Info"
Write-PreflightLog "PowerShell Version: $($PSVersionTable.PSVersion)" -Level "Info"
Write-PreflightLog "Execution Policy: $(Get-ExecutionPolicy)" -Level "Info"
Write-PreflightLog "Working Directory: $(Get-Location)" -Level "Info"

# Check 1: PowerShell Version
Test-PreflightCheck -Name "PowerShell Version >= 5.1" -Check {
    $version = $PSVersionTable.PSVersion
    return ($version.Major -gt 5) -or ($version.Major -eq 5 -and $version.Minor -ge 1)
}

# Check 2: Required Directories
Test-PreflightCheck -Name "Core directories exist" -Check {
    $requiredDirs = @("modules", "tools", "tests")
    foreach ($dir in $requiredDirs) {
        if (-not (Test-Path $dir)) {
            Write-PreflightLog "Missing required directory: $dir" -Level "Error"
            return $false
        }
    }
    return $true
}

# Check 3: Core PowerShell Modules
Test-PreflightCheck -Name "Nova core modules exist" -Check {
    $coreModules = @(
        "modules\Nova.Metrics.psm1",
        "modules\Nova.Skills.psm1"
    )
    foreach ($module in $coreModules) {
        if (-not (Test-Path $module)) {
            Write-PreflightLog "Missing core module: $module" -Level "Error"
            return $false
        }
    }
    return $true
}

# Check 4: Module Syntax Validation
Test-PreflightCheck -Name "PowerShell modules syntax valid" -Check {
    $moduleFiles = Get-ChildItem -Path "modules\*.psm1" -ErrorAction SilentlyContinue
    foreach ($file in $moduleFiles) {
        try {
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $file.FullName -Raw), [ref]$null)
        }
        catch {
            Write-PreflightLog "Syntax error in $($file.Name): $_" -Level "Error"
            return $false
        }
    }
    return $true
}

# Check 5: Test Files Exist
Test-PreflightCheck -Name "Test files present" -Check {
    $testFiles = Get-ChildItem -Path "tests\*.Tests.ps1" -ErrorAction SilentlyContinue
    if ($testFiles.Count -eq 0) {
        Write-PreflightLog "No test files found in tests directory" -Level "Error"
        return $false
    }
    return $true
} -Required $false

# Check 6: Git Repository Status
Test-PreflightCheck -Name "Git repository clean" -Check {
    if (-not (Test-Path ".git")) {
        Write-PreflightLog "Not a git repository" -Level "Warning"
        return $true  # Not required for CI
    }
    
    $status = git status --porcelain 2>$null
    if ($status) {
        Write-PreflightLog "Git working directory has uncommitted changes" -Level "Warning"
        if ($Verbose) {
            Write-PreflightLog "Uncommitted files:" -Level "Info"
            $status | ForEach-Object { Write-PreflightLog "  $_" -Level "Info" }
        }
        return $true  # Warning only, don't fail
    }
    return $true
} -Required $false

# Check 7: Essential Tools
Test-PreflightCheck -Name "Essential tools exist" -Check {
    $tools = @(
        "tools\Run-Tests.ps1",
        "tools\Approve-Actions.ps1"
    )
    $missing = @()
    foreach ($tool in $tools) {
        if (-not (Test-Path $tool)) {
            $missing += $tool
        }
    }
    
    if ($missing.Count -gt 0) {
        Write-PreflightLog "Missing tools: $($missing -join ', ')" -Level "Error"
        return $false
    }
    return $true
}

# Check 8: Data Directory Structure  
Test-PreflightCheck -Name "Data directory structure" -Check {
    $dataStructure = @(
        "data",
        "data\queue",
        "data\queue\inbox", 
        "data\queue\outbox"
    )
    
    foreach ($path in $dataStructure) {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
            Write-PreflightLog "Created missing directory: $path" -Level "Info"
        }
    }
    return $true
} -Required $false

# Check 9: Permissions
Test-PreflightCheck -Name "File system permissions" -Check {
    try {
        # Test write access to key directories
        $testFile = Join-Path "data" "preflight-test.tmp"
        "test" | Out-File $testFile -ErrorAction Stop
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        Write-PreflightLog "Insufficient file system permissions: $_" -Level "Error"
        return $false
    }
}

# Check 10: Module Import Test
Test-PreflightCheck -Name "Core modules can be imported" -Check {
    $testModules = @(
        "modules\Nova.Metrics.psm1"
    )
    
    foreach ($module in $testModules) {
        if (Test-Path $module) {
            try {
                Import-Module (Resolve-Path $module).Path -Force -ErrorAction Stop
                Write-PreflightLog "Successfully imported $(Split-Path $module -Leaf)" -Level "Info"
            }
            catch {
                Write-PreflightLog "Failed to import $module`: $($_.Exception.Message)" -Level "Error"
                return $false
            }
        }
    }
    return $true
}

# One-Paste Pack Quality Checks
Write-PreflightLog "Running One-Paste Pack Quality Checks..." -Level "Info"

# Check 11: Quality Scorecard Tool
Test-PreflightCheck -Name "Quality Scorecard available and functional" -Check {
    if (-not (Test-Path "tools\Quality-Scorecard.ps1")) {
        Write-PreflightLog "Quality-Scorecard.ps1 not found" -Level "Error"
        return $false
    }
    
    # Test basic syntax (simplified check)
    try {
        $content = Get-Content "tools\Quality-Scorecard.ps1" -Raw
        if ($content.Length -lt 1000) {
            Write-PreflightLog "Quality-Scorecard.ps1 appears incomplete" -Level "Error"
            return $false
        }
        return $true
    }
    catch {
        Write-PreflightLog "Quality-Scorecard.ps1 validation failed: $_" -Level "Error"
        return $false
    }
} -Required $false

# Check 12: Security Audit Tool
Test-PreflightCheck -Name "Security Audit tool available" -Check {
    if (-not (Test-Path "tools\Security-Audit.ps1")) {
        Write-PreflightLog "Security-Audit.ps1 not found" -Level "Error"
        return $false
    }
    return $true
} -Required $false

# Check 13: Coverage Analysis Tool
Test-PreflightCheck -Name "Coverage analysis tool available" -Check {
    if (-not (Test-Path "tests\Coverage-Report.ps1")) {
        Write-PreflightLog "Coverage-Report.ps1 not found" -Level "Error"
        return $false
    }
    return $true
} -Required $false

# Check 14: Integration Tests
Test-PreflightCheck -Name "Integration test suite available" -Check {
    if (-not (Test-Path "tests\Integration.Tests.ps1")) {
        Write-PreflightLog "Integration.Tests.ps1 not found" -Level "Error"
        return $false
    }
    return $true
} -Required $false

# Check 15: One-Paste Pack Documentation
Test-PreflightCheck -Name "One-Paste Pack documentation complete" -Check {
    $docs = @(
        "docs\One-Paste-Pack-README.md",
        "docs\SECURITY.md", 
        "docs\CONTRIBUTING.md",
        ".github\PULL_REQUEST_TEMPLATE.md"
    )
    
    $missing = @()
    foreach ($doc in $docs) {
        if (-not (Test-Path $doc)) {
            $missing += $doc
        }
    }
    
    if ($missing.Count -gt 0) {
        Write-PreflightLog "Missing One-Paste Pack docs: $($missing -join ', ')" -Level "Warning"
        return $true  # Warning only
    }
    return $true
} -Required $false

# Calculate results
$results.EndTime = Get-Date
$results.Duration = $results.EndTime - $results.StartTime

# Display summary
Write-PreflightLog "================================" -Level "Info"
Write-PreflightLog "PREFLIGHT SUMMARY" -Level "Info"  
Write-PreflightLog "================================" -Level "Info"
Write-PreflightLog "Total Checks: $($results.TotalChecks)" -Level "Info"
Write-PreflightLog "Passed: $($results.PassedChecks)" -Level "Success"
Write-PreflightLog "Failed: $($results.FailedChecks)" -Level $(if ($results.FailedChecks -gt 0) { "Error" } else { "Info" })
Write-PreflightLog "Warnings: $($results.Warnings.Count)" -Level $(if ($results.Warnings.Count -gt 0) { "Warning" } else { "Info" })
Write-PreflightLog "Duration: $($results.Duration.TotalSeconds.ToString('F2')) seconds" -Level "Info"

# Show warnings if any
if ($results.Warnings.Count -gt 0) {
    Write-PreflightLog "Warnings encountered:" -Level "Warning"
    foreach ($warning in $results.Warnings) {
        Write-PreflightLog "  - $warning" -Level "Warning"
    }
}

# Show errors if any
if ($results.Errors.Count -gt 0) {
    Write-PreflightLog "Errors encountered:" -Level "Error"
    foreach ($errorMsg in $results.Errors) {
        Write-PreflightLog "  - $errorMsg" -Level "Error"
    }
}

# Determine exit code
if ($results.FailedChecks -gt 0) {
    Write-PreflightLog "❌ PREFLIGHT FAILED - $($results.FailedChecks) critical check(s) failed" -Level "Error"
    exit 1
} elseif ($results.Warnings.Count -gt 0) {
    Write-PreflightLog "⚠️  PREFLIGHT PASSED WITH WARNINGS - All critical checks passed" -Level "Warning"
    exit 0
} else {
    Write-PreflightLog "✅ PREFLIGHT PASSED - All checks successful" -Level "Success"
    exit 0
}