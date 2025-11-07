param([switch]$SelfTest)

$MetricsModule = Join-Path $PSScriptRoot "..\modules\Nova.Metrics.psm1"
if (Test-Path $MetricsModule) {
    Import-Module $MetricsModule -Force
}

function Invoke-SelfTest {
    Write-Host "Nova Dashboard Self-Test" -ForegroundColor Cyan
    Write-Host "Testing metrics..." -ForegroundColor Yellow
    
    Inc-Counter -Name "signals_seen" -Value 5
    Inc-Counter -Name "contracts_executed" -Value 2
    Observe-Histogram -Name "latency_ms" -Value 150
    Set-Gauge -Name "uptime_seconds" -Value 3600
    
    Write-Host "Metrics created" -ForegroundColor Green
    Write-Host ""
    Write-Host "URLs:" -ForegroundColor Cyan
    Write-Host "http://localhost:8765/status"
    Write-Host "http://localhost:8765/metrics"
    Write-Host ""
    Write-Host "Sample Metrics:" -ForegroundColor Cyan
    $metrics = Get-MetricsSnapshot -Format Prometheus
    Write-Host $metrics
    Write-Host "Self-test completed!" -ForegroundColor Green
}

if ($SelfTest) {
    Invoke-SelfTest
} else {
    Write-Host "Nova Dashboard - Run with -SelfTest to test"
}
