# Setup-LocalDev.ps1 - Nova Bot One-Click Local Development Setup
# Creators: Tyler McKendry & Nova

param(
    [switch]$Verbose,
    [switch]$Debug,
    [switch]$Force,
    [switch]$SkipDependencies,
    [switch]$SkipTests
)

$ErrorActionPreference = "Continue"
$VerbosePreference = if ($Verbose) { "Continue" } else { "SilentlyContinue" }
$DebugPreference = if ($Debug) { "Continue" } else { "SilentlyContinue" }

# Initialize setup tracking
$script:SetupResults = @{
    StartTime = Get-Date
    Steps = @()
    Warnings = @()
    Errors = @()
    Success = $true
}

# Color scheme
$script:Colors = @{
    Success = "Green"
    Info = "Cyan"
    Warning = "Yellow"
    Error = "Red"
    Header = "Magenta"
}

function Write-SetupLog {
    param(
        [string]$Message,
        [ValidateSet("Success", "Info", "Warning", "Error", "Header")]$Level = "Info",
        [switch]$NoTimestamp
    )
    
    $color = $script:Colors[$Level]
    
    if (-not $NoTimestamp) {
        $timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "[$timestamp] " -NoNewline -ForegroundColor Gray
    }
    
    Write-Host $Message -ForegroundColor $color
    Write-Verbose $Message
    Write-Debug $Message
}

function Add-SetupStep {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Message = ""
    )
    
    $script:SetupResults.Steps += @{
        Name = $Name
        Status = $Status
        Message = $Message
        Timestamp = Get-Date
    }
    
    if ($Status -eq "Failed") {
        $script:SetupResults.Success = $false
        $script:SetupResults.Errors += $Message
    } elseif ($Status -eq "Warning") {
        $script:SetupResults.Warnings += $Message
    }
}

function Test-AdminPrivileges {
    try {
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Test-PowerShellVersion {
    Write-SetupLog "Checking PowerShell version..." -Level "Info"
    
    $psVersion = $PSVersionTable.PSVersion
    $requiredVersion = [version]"5.1"
    
    if ($psVersion -ge $requiredVersion) {
        Write-SetupLog "✅ PowerShell $psVersion (>= $requiredVersion required)" -Level "Success"
        Add-SetupStep -Name "PowerShell Version" -Status "Passed" -Message "Version $psVersion"
        return $true
    } else {
        Write-SetupLog "❌ PowerShell $psVersion is too old. Minimum required: $requiredVersion" -Level "Error"
        Add-SetupStep -Name "PowerShell Version" -Status "Failed" -Message "Version $psVersion < $requiredVersion"
        return $false
    }
}

function Test-GitInstallation {
    Write-SetupLog "Checking Git installation..." -Level "Info"
    
    try {
        $gitVersion = git --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-SetupLog "✅ Git installed: $gitVersion" -Level "Success"
            Add-SetupStep -Name "Git Installation" -Status "Passed" -Message $gitVersion
            return $true
        }
    } catch {}
    
    Write-SetupLog "❌ Git not found. Please install Git from https://git-scm.com/" -Level "Error"
    Add-SetupStep -Name "Git Installation" -Status "Failed" -Message "Git not found in PATH"
    return $false
}

function Initialize-DirectoryStructure {
    Write-SetupLog "Creating directory structure..." -Level "Info"
    
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $directories = @(
        "bot\logs",
        "bot\config", 
        "bot\data",
        "bot\data\metrics",
        "tools",
        "tests",
        "docs",
        "scripts",
        "logs",
        "data",
        "ci-artifacts",
        "ci-artifacts\logs",
        "ci-artifacts\coverage",
        "quality-artifacts",
        "quality-artifacts\reports",
        "quality-artifacts\badges"
    )
    
    $createdDirs = 0
    $existingDirs = 0
    
    foreach ($dir in $directories) {
        $fullPath = Join-Path $projectRoot $dir
        
        try {
            if (-not (Test-Path $fullPath)) {
                New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
                Write-SetupLog "  📁 Created: $dir" -Level "Info"
                $createdDirs++
            } else {
                $existingDirs++
                Write-Debug "Directory exists: $dir"
            }
        } catch {
            Write-SetupLog "  ❌ Failed to create: $dir - $($_.Exception.Message)" -Level "Error"
            Add-SetupStep -Name "Directory Creation" -Status "Failed" -Message "Failed to create $dir"
            return $false
        }
    }
    
    Write-SetupLog "✅ Directory structure ready ($createdDirs created, $existingDirs existing)" -Level "Success"
    Add-SetupStep -Name "Directory Structure" -Status "Passed" -Message "$createdDirs created, $existingDirs existing"
    return $true
}

function Install-PowerShellModules {
    if ($SkipDependencies) {
        Write-SetupLog "Skipping PowerShell module installation (SkipDependencies)" -Level "Warning"
        return $true
    }
    
    Write-SetupLog "Installing PowerShell modules..." -Level "Info"
    
    $modules = @(
        @{ Name = "Pester"; MinVersion = "5.0"; Description = "Testing framework" },
        @{ Name = "PSScriptAnalyzer"; MinVersion = "1.18"; Description = "Code analysis" }
    )
    
    $installedCount = 0
    $skippedCount = 0
    
    foreach ($module in $modules) {
        try {
            Write-SetupLog "  Checking $($module.Name)..." -Level "Info"
            
            $existing = Get-Module -Name $module.Name -ListAvailable | Where-Object { $_.Version -ge [version]$module.MinVersion }
            
            if ($existing -and -not $Force) {
                Write-SetupLog "  ✅ $($module.Name) v$($existing[0].Version) already installed" -Level "Success"
                $skippedCount++
                continue
            }
            
            Write-SetupLog "  📦 Installing $($module.Name) (>= $($module.MinVersion))..." -Level "Info"
            
            Install-Module -Name $module.Name -MinimumVersion $module.MinVersion -Force -SkipPublisherCheck -Scope CurrentUser -AllowClobber
            
            # Verify installation
            $installed = Get-Module -Name $module.Name -ListAvailable | Where-Object { $_.Version -ge [version]$module.MinVersion }
            if ($installed) {
                Write-SetupLog "  ✅ $($module.Name) v$($installed[0].Version) installed successfully" -Level "Success"
                $installedCount++
            } else {
                throw "Module verification failed"
            }
            
        } catch {
            Write-SetupLog "  ❌ Failed to install $($module.Name): $($_.Exception.Message)" -Level "Error"
            Add-SetupStep -Name "Module Installation" -Status "Failed" -Message "Failed to install $($module.Name)"
            return $false
        }
    }
    
    Write-SetupLog "✅ PowerShell modules ready ($installedCount installed, $skippedCount existing)" -Level "Success"
    Add-SetupStep -Name "PowerShell Modules" -Status "Passed" -Message "$installedCount installed, $skippedCount existing"
    return $true
}

function Set-ExecutionPolicy {
    Write-SetupLog "Configuring PowerShell execution policy..." -Level "Info"
    
    try {
        $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
        
        if ($currentPolicy -in @("Restricted", "AllSigned")) {
            Write-SetupLog "  Current policy: $currentPolicy (restrictive)" -Level "Warning"
            
            if (Test-AdminPrivileges) {
                Write-SetupLog "  Setting execution policy to RemoteSigned..." -Level "Info"
                Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
                $newPolicy = Get-ExecutionPolicy -Scope CurrentUser
                Write-SetupLog "  ✅ Execution policy updated: $newPolicy" -Level "Success"
            } else {
                Write-SetupLog "  Setting execution policy to Bypass for CurrentUser..." -Level "Info"
                Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force
                $newPolicy = Get-ExecutionPolicy -Scope CurrentUser
                Write-SetupLog "  ✅ Execution policy updated: $newPolicy" -Level "Success"
            }
        } else {
            Write-SetupLog "  ✅ Execution policy acceptable: $currentPolicy" -Level "Success"
        }
        
        Add-SetupStep -Name "Execution Policy" -Status "Passed" -Message "Policy: $(Get-ExecutionPolicy -Scope CurrentUser)"
        return $true
        
    } catch {
        Write-SetupLog "  ❌ Failed to configure execution policy: $($_.Exception.Message)" -Level "Error"
        Add-SetupStep -Name "Execution Policy" -Status "Failed" -Message $_.Exception.Message
        return $false
    }
}

function Initialize-GitRepository {
    Write-SetupLog "Checking Git repository..." -Level "Info"
    
    $projectRoot = Split-Path -Parent $PSScriptRoot
    
    try {
        Set-Location $projectRoot
        
        # Check if we're in a Git repository
        $gitStatus = git status 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-SetupLog "  ✅ Git repository detected" -Level "Success"
            
            # Check for remote
            $remotes = git remote 2>$null
            if ($remotes) {
                Write-SetupLog "  ✅ Git remote configured: $(git remote get-url origin 2>$null)" -Level "Success"
            } else {
                Write-SetupLog "  ⚠️  No Git remote configured" -Level "Warning"
            }
            
            Add-SetupStep -Name "Git Repository" -Status "Passed" -Message "Repository initialized with remote"
            return $true
            
        } else {
            Write-SetupLog "  📦 Initializing Git repository..." -Level "Info"
            git init
            
            # Create .gitignore if it doesn't exist
            $gitignorePath = Join-Path $projectRoot ".gitignore"
            if (-not (Test-Path $gitignorePath)) {
                $gitignoreContent = @"
# Logs and temporary files
*.log
logs/
ci-artifacts/
quality-artifacts/
test-results.xml
coverage-report.html
quality-scorecard.html
security-audit.csv

# PowerShell specific
*.ps1xml
*.pssc
*.psc1

# OS generated files
Thumbs.db
.DS_Store
desktop.ini

# IDE files
.vscode/
.idea/

# Dependencies
node_modules/
packages/

# Build outputs
dist/
build/
"@
                Set-Content -Path $gitignorePath -Value $gitignoreContent -Encoding UTF8
                Write-SetupLog "  📄 Created .gitignore" -Level "Info"
            }
            
            Write-SetupLog "  ✅ Git repository initialized" -Level "Success"
            Add-SetupStep -Name "Git Repository" -Status "Passed" -Message "Repository initialized"
            return $true
        }
        
    } catch {
        Write-SetupLog "  ❌ Git repository setup failed: $($_.Exception.Message)" -Level "Error"
        Add-SetupStep -Name "Git Repository" -Status "Failed" -Message $_.Exception.Message
        return $false
    }
}

function Test-NovaComponents {
    Write-SetupLog "Testing Nova components..." -Level "Info"
    
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $testsPassed = 0
    $testsFailed = 0
    
    # Test essential scripts exist
    $essentialFiles = @(
        "tools\Preflight.ps1",
        "tools\Quality-Scorecard.ps1", 
        "tools\Security-Audit.ps1",
        "tests\Coverage-Report.ps1"
    )
    
    foreach ($file in $essentialFiles) {
        $filePath = Join-Path $projectRoot $file
        if (Test-Path $filePath) {
            Write-SetupLog "  ✅ $file" -Level "Success"
            $testsPassed++
        } else {
            Write-SetupLog "  ❌ Missing: $file" -Level "Error"
            $testsFailed++
        }
    }
    
    # Test that scripts are executable
    try {
        $preflightPath = Join-Path $projectRoot "tools\Preflight.ps1"
        if (Test-Path $preflightPath) {
            Write-SetupLog "  🧪 Testing Preflight.ps1..." -Level "Info"
            
            $result = powershell -ExecutionPolicy Bypass -File $preflightPath -ErrorAction Stop 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-SetupLog "  ✅ Preflight.ps1 executable" -Level "Success"
                $testsPassed++
            } else {
                Write-SetupLog "  ⚠️  Preflight.ps1 returned exit code $LASTEXITCODE" -Level "Warning"
            }
        }
    } catch {
        Write-SetupLog "  ❌ Preflight.ps1 test failed: $($_.Exception.Message)" -Level "Error"
        $testsFailed++
    }
    
    if ($testsFailed -eq 0) {
        Write-SetupLog "✅ Nova components ready ($testsPassed tests passed)" -Level "Success"
        Add-SetupStep -Name "Nova Components" -Status "Passed" -Message "$testsPassed tests passed"
        return $true
    } else {
        Write-SetupLog "❌ Nova components incomplete ($testsFailed tests failed)" -Level "Error"
        Add-SetupStep -Name "Nova Components" -Status "Failed" -Message "$testsFailed tests failed"
        return $false
    }
}

function Run-InitialTests {
    if ($SkipTests) {
        Write-SetupLog "Skipping initial tests (SkipTests)" -Level "Warning"
        return $true
    }
    
    Write-SetupLog "Running initial validation tests..." -Level "Info"
    
    $projectRoot = Split-Path -Parent $PSScriptRoot
    
    try {
        # Run quality scorecard
        Write-SetupLog "  🏆 Running Quality Scorecard..." -Level "Info"
        $scorecardResult = powershell -ExecutionPolicy Bypass -File (Join-Path $projectRoot "tools\Quality-Scorecard.ps1") -Quick 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-SetupLog "  ✅ Quality Scorecard completed" -Level "Success"
        } else {
            Write-SetupLog "  ⚠️  Quality Scorecard returned warnings" -Level "Warning"
        }
        
        # Run security audit  
        Write-SetupLog "  🛡️  Running Security Audit..." -Level "Info"
        $securityResult = powershell -ExecutionPolicy Bypass -File (Join-Path $projectRoot "tools\Security-Audit.ps1") -Quick 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-SetupLog "  ✅ Security Audit completed" -Level "Success"
        } else {
            Write-SetupLog "  ⚠️  Security Audit found issues" -Level "Warning"
        }
        
        # Run coverage report (without tests)
        Write-SetupLog "  📊 Running Coverage Analysis..." -Level "Info"
        $coverageResult = powershell -ExecutionPolicy Bypass -File (Join-Path $projectRoot "tests\Coverage-Report.ps1") 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-SetupLog "  ✅ Coverage Analysis completed" -Level "Success"
        } else {
            Write-SetupLog "  ⚠️  Coverage Analysis returned warnings" -Level "Warning"
        }
        
        Write-SetupLog "✅ Initial tests completed" -Level "Success"
        Add-SetupStep -Name "Initial Tests" -Status "Passed" -Message "Quality, Security, and Coverage tests completed"
        return $true
        
    } catch {
        Write-SetupLog "❌ Initial tests failed: $($_.Exception.Message)" -Level "Error"
        Add-SetupStep -Name "Initial Tests" -Status "Failed" -Message $_.Exception.Message
        return $false
    }
}

function Show-SetupSummary {
    $results = $script:SetupResults
    $duration = (Get-Date) - $results.StartTime
    
    Write-Host ""
    Write-SetupLog "╔══════════════════════════════════════════════════════════════╗" -Level "Header" -NoTimestamp
    Write-SetupLog "║                    NOVA SETUP COMPLETE                       ║" -Level "Header" -NoTimestamp
    Write-SetupLog "╚══════════════════════════════════════════════════════════════╝" -Level "Header" -NoTimestamp
    Write-Host ""
    
    # Overall status
    if ($results.Success) {
        Write-SetupLog "🎉 Setup Status: SUCCESS" -Level "Success"
    } else {
        Write-SetupLog "❌ Setup Status: FAILED" -Level "Error"
    }
    
    Write-SetupLog "⏱️  Duration: $($duration.ToString('mm\:ss'))" -Level "Info"
    Write-SetupLog "📊 Steps: $($results.Steps.Count) total" -Level "Info"
    
    # Step summary
    $passed = ($results.Steps | Where-Object { $_.Status -eq "Passed" }).Count
    $failed = ($results.Steps | Where-Object { $_.Status -eq "Failed" }).Count  
    $warnings = ($results.Steps | Where-Object { $_.Status -eq "Warning" }).Count
    
    Write-SetupLog "   ✅ Passed: $passed" -Level "Success"
    if ($failed -gt 0) {
        Write-SetupLog "   ❌ Failed: $failed" -Level "Error"
    }
    if ($warnings -gt 0) {
        Write-SetupLog "   ⚠️  Warnings: $warnings" -Level "Warning"
    }
    
    Write-Host ""
    
    # Detailed step results
    Write-SetupLog "📋 SETUP STEPS:" -Level "Header"
    foreach ($step in $results.Steps) {
        $statusIcon = switch ($step.Status) {
            "Passed" { "✅" }
            "Failed" { "❌" }
            "Warning" { "⚠️ " }
        }
        
        $statusColor = switch ($step.Status) {
            "Passed" { "Success" }
            "Failed" { "Error" }
            "Warning" { "Warning" }
        }
        
        Write-SetupLog "  $statusIcon $($step.Name): $($step.Message)" -Level $statusColor
    }
    
    Write-Host ""
    
    # Next steps
    if ($results.Success) {
        Write-SetupLog "🚀 NEXT STEPS:" -Level "Header"
        Write-SetupLog "  1. Run quality check:" -Level "Info"
        Write-SetupLog "     powershell -ExecutionPolicy Bypass -File tools\Quality-Scorecard.ps1" -Level "Info"
        Write-SetupLog ""
        Write-SetupLog "  2. Run security audit:" -Level "Info"
        Write-SetupLog "     powershell -ExecutionPolicy Bypass -File tools\Security-Audit.ps1" -Level "Info"
        Write-SetupLog ""
        Write-SetupLog "  3. Run tests with coverage:" -Level "Info"
        Write-SetupLog "     powershell -ExecutionPolicy Bypass -File tests\Coverage-Report.ps1 -RunTests" -Level "Info"
        Write-SetupLog ""
        Write-SetupLog "  4. Start Nova Bot:" -Level "Info"
        Write-SetupLog "     cd bot && powershell -ExecutionPolicy Bypass -File nova-bot.ps1 -SmokeTest" -Level "Info"
        Write-Host ""
        Write-SetupLog "📖 For detailed instructions, see: docs\One-Paste-Pack-README.md" -Level "Info"
    } else {
        Write-SetupLog "🔧 TROUBLESHOOTING:" -Level "Header"
        Write-SetupLog "  • Check error messages above" -Level "Error"
        Write-SetupLog "  • Run with -Verbose for detailed logging" -Level "Info"
        Write-SetupLog "  • Run with -Debug for maximum detail" -Level "Info"
        Write-SetupLog "  • Use -Force to reinstall dependencies" -Level "Info"
    }
}

# Main execution
try {
    Write-SetupLog "╔══════════════════════════════════════════════════════════════╗" -Level "Header" -NoTimestamp
    Write-SetupLog "║                    NOVA DEV SETUP                            ║" -Level "Header" -NoTimestamp  
    Write-SetupLog "╚══════════════════════════════════════════════════════════════╝" -Level "Header" -NoTimestamp
    Write-Host ""
    
    Write-SetupLog "Starting Nova Local Development Setup..." -Level "Info"
    Write-SetupLog "Project Root: $(Split-Path -Parent $PSScriptRoot)" -Level "Info"
    
    if (Test-AdminPrivileges) {
        Write-SetupLog "Running with Administrator privileges" -Level "Success"
    } else {
        Write-SetupLog "Running without Administrator privileges (some steps may be limited)" -Level "Warning"
    }
    
    Write-Host ""
    
    # Execute setup steps
    $setupSteps = @(
        { Test-PowerShellVersion },
        { Test-GitInstallation },
        { Set-ExecutionPolicy },
        { Initialize-DirectoryStructure },
        { Install-PowerShellModules },
        { Initialize-GitRepository },
        { Test-NovaComponents },
        { Run-InitialTests }
    )
    
    $stepNumber = 1
    foreach ($step in $setupSteps) {
        Write-SetupLog "Step $stepNumber/$($setupSteps.Count): " -Level "Header" -NoTimestamp
        $stepResult = & $step
        $stepNumber++
        
        if (-not $stepResult -and -not $Force) {
            Write-SetupLog "Setup step failed. Use -Force to continue despite errors." -Level "Error"
            break
        }
        
        Write-Host ""
    }
    
    Show-SetupSummary
    
    if ($script:SetupResults.Success) {
        Write-SetupLog "🎉 Nova development environment is ready!" -Level "Success"
        exit 0
    } else {
        Write-SetupLog "❌ Setup completed with errors. Please review and retry." -Level "Error"
        exit 1
    }
    
} catch {
    Write-SetupLog "❌ Setup failed with exception: $($_.Exception.Message)" -Level "Error"
    Write-SetupLog "Stack trace: $($_.ScriptStackTrace)" -Level "Error"
    exit 2
}