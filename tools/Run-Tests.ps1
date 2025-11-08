# Run-Tests.ps1 - Nova Bot Test Runner

param(
    [double]$MinPassRate = 0.80,
    [switch]$Detailed
)

Write-Host "Nova Bot Test Suite Runner" -ForegroundColor Cyan
Write-Host "=" * 40 -ForegroundColor Cyan

# Import Pester v5 explicitly
Import-Module Pester -MinimumVersion 5.0 -Force

$testPath = Join-Path $PSScriptRoot "..\tests\FailureInjection.Tests.ps1"
Write-Host "Running tests from: $testPath" -ForegroundColor Gray

try {
    $result = Invoke-Pester -Path $testPath -PassThru
    
    $passRate = if ($result.TotalCount -gt 0) { 
        $result.PassedCount / $result.TotalCount 
    } else { 0 }
    
    Write-Host "`nTest Results:" -ForegroundColor Cyan
    Write-Host "  Total: $($result.TotalCount)" -ForegroundColor White
    Write-Host "  Passed: $($result.PassedCount)" -ForegroundColor Green  
    Write-Host "  Failed: $($result.FailedCount)" -ForegroundColor Red
    Write-Host "  Pass Rate: $([math]::Round($passRate * 100, 2))%" -ForegroundColor $(if ($passRate -ge $MinPassRate) { "Green" } else { "Red" })
    
    # Check for critical failures
    $criticalFailed = @()
    if ($result.Failed) {
        foreach ($failed in $result.Failed) {
            if ($failed.Block.Tag -contains "Critical") {
                $criticalFailed += $failed.Name
            }
        }
    }
    
    if ($criticalFailed.Count -gt 0) {
        Write-Host "`nCritical Failures:" -ForegroundColor Red
        foreach ($critical in $criticalFailed) {
            Write-Host "  - $critical" -ForegroundColor Red
        }
        exit 2
    }
    
    if ($passRate -lt $MinPassRate) {
        Write-Host "`nFAILED: Pass rate $([math]::Round($passRate * 100, 2))% below required $($MinPassRate * 100)%" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "`nSUCCESS: All tests passed requirements" -ForegroundColor Green
    exit 0
}
catch {
    Write-Error "Test execution failed: $_"
    exit 3
}
