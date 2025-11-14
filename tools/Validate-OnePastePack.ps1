# One-Paste Pack Validation Script
# Creators: Tyler McKendry & Nova

[CmdletBinding()]
param()

Write-Host "=== One-Paste Pack Validation ===" -ForegroundColor Cyan

$validationResults = @()
$allPassed = $true

# Test 1: Check file existence
Write-Host "`n1. Checking file existence..." -ForegroundColor Yellow
$requiredFiles = @(
    "tools\Quality-Scorecard.ps1",
    "tools\Security-Audit.ps1", 
    "tests\Coverage-Report.ps1",
    "scripts\Setup-LocalDev.ps1",
    "tests\Integration.Tests.ps1",
    ".github\workflows\scorecard.yml",
    "docs\One-Paste-Pack-README.md",
    "docs\SECURITY.md",
    "docs\CONTRIBUTING.md",
    ".github\PULL_REQUEST_TEMPLATE.md"
)

foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        Write-Host "✅ $file" -ForegroundColor Green
        $validationResults += [PSCustomObject]@{ Test = $file; Status = "PASS"; Message = "File exists" }
    } else {
        Write-Host "❌ $file" -ForegroundColor Red
        $validationResults += [PSCustomObject]@{ Test = $file; Status = "FAIL"; Message = "File missing" }
        $allPassed = $false
    }
}

# Test 2: PowerShell syntax validation
Write-Host "`n2. Checking PowerShell syntax..." -ForegroundColor Yellow
$psFiles = @(
    "tools\Quality-Scorecard.ps1",
    "tools\Security-Audit.ps1",
    "tests\Coverage-Report.ps1", 
    "scripts\Setup-LocalDev.ps1",
    "tests\Integration.Tests.ps1"
)

foreach ($file in $psFiles) {
    if (Test-Path $file) {
        try {
            $errors = @()
            $tokens = @()
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $file -Raw), [ref]$errors)
            
            if ($errors.Count -eq 0) {
                Write-Host "✅ $file syntax" -ForegroundColor Green
                $validationResults += [PSCustomObject]@{ Test = "$file syntax"; Status = "PASS"; Message = "No syntax errors" }
            } else {
                Write-Host "❌ $file syntax ($($errors.Count) errors)" -ForegroundColor Red
                $validationResults += [PSCustomObject]@{ Test = "$file syntax"; Status = "FAIL"; Message = "$($errors.Count) syntax errors" }
                $allPassed = $false
            }
        } catch {
            Write-Host "❌ $file syntax (validation failed)" -ForegroundColor Red
            $validationResults += [PSCustomObject]@{ Test = "$file syntax"; Status = "FAIL"; Message = "Validation failed: $($_.Exception.Message)" }
            $allPassed = $false
        }
    }
}

# Test 3: Directory structure check
Write-Host "`n3. Checking directory structure..." -ForegroundColor Yellow
$requiredDirs = @("tools", "tests", "scripts", "docs", ".github", ".github\workflows")
foreach ($dir in $requiredDirs) {
    if (Test-Path $dir -PathType Container) {
        Write-Host "✅ Directory: $dir" -ForegroundColor Green
        $validationResults += [PSCustomObject]@{ Test = "Directory $dir"; Status = "PASS"; Message = "Directory exists" }
    } else {
        Write-Host "❌ Directory: $dir" -ForegroundColor Red  
        $validationResults += [PSCustomObject]@{ Test = "Directory $dir"; Status = "FAIL"; Message = "Directory missing" }
        $allPassed = $false
    }
}

# Results Summary
Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
$passCount = ($validationResults | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = ($validationResults | Where-Object { $_.Status -eq "FAIL" }).Count
$totalCount = $validationResults.Count

Write-Host "Total Tests: $totalCount" -ForegroundColor White
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red

if ($allPassed) {
    Write-Host "`n🎉 All validations passed! One-Paste Pack is ready." -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n⚠️  Some validations failed. Please review the results above." -ForegroundColor Yellow
    Write-Host "`nFailed tests:" -ForegroundColor Red
    $validationResults | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "  - $($_.Test): $($_.Message)" -ForegroundColor Red
    }
    exit 1
}