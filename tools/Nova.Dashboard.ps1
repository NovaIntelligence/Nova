# Nova.Dashboard.ps1 - Lightweight HTTP dashboard for Nova Bot metrics
# Provides /metrics (Prometheus) and /status (HTML) endpoints on localhost:8765

param(
    [switch]$SelfTest,
    [switch]$DaemonMode,
    [int]$Port = 8765,
    [string]$ListenHost = "localhost"
)

$ErrorActionPreference = "Stop"

# Import modules
$MetricsModule = Join-Path $PSScriptRoot "..\modules\Nova.Metrics.psm1"
if (Test-Path $MetricsModule) {
    Import-Module $MetricsModule -Force
} else {
    Write-Error "Nova.Metrics.psm1 not found at $MetricsModule"
    exit 1
}

if (Test-Path "$PSScriptRoot\_nova_logshim.psm1") {
    Import-Module "$PSScriptRoot\_nova_logshim.psm1" -Force
} elseif (Test-Path "$PSScriptRoot\..\bot\tools\_nova_logshim.psm1") {
    Import-Module "$PSScriptRoot\..\bot\tools\_nova_logshim.psm1" -Force
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    if (Get-Command "Write-NovaLog" -ErrorAction SilentlyContinue) {
        Write-NovaLog -Message $Message -Level $Level -Component "Nova.Dashboard"
    } else {
        Write-Host "[$Level] $(Get-Date -Format 'HH:mm:ss') Nova.Dashboard: $Message"
    }
}

function Get-StatusHtml {
    $snapshot = Get-MetricsSnapshot -Format Raw
    $uptime = if ($snapshot.Gauges.ContainsKey("uptime_seconds")) { 
        [math]::Round($snapshot.Gauges["uptime_seconds"].Value) 
    } else { 0 }
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Nova Bot Dashboard</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { background: #2c3e50; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .metrics-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .metric-card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .metric-title { font-size: 18px; font-weight: bold; color: #2c3e50; margin-bottom: 15px; }
        .metric-value { font-size: 24px; font-weight: bold; color: #27ae60; }
        .metric-label { font-size: 12px; color: #7f8c8d; text-transform: uppercase; }
        .timestamp { color: #95a5a6; font-size: 12px; }
        pre { background: #ecf0f1; padding: 10px; border-radius: 4px; overflow-x: auto; font-size: 12px; }
        .status-ok { color: #27ae60; }
        .status-warning { color: #f39c12; }
        .status-error { color: #e74c3c; }
    </style>
    <meta http-equiv="refresh" content="30">
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Nova Bot Dashboard</h1>
            <p>Real-time metrics and system status</p>
            <p class="timestamp">Last updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC') | Uptime: $uptime seconds</p>
        </div>
        
        <div class="metrics-grid">
            <div class="metric-card">
                <div class="metric-title">📊 Counters</div>
"@

    # Add counters
    if ($snapshot.Counters.Count -gt 0) {
        foreach ($entry in $snapshot.Counters.GetEnumerator()) {
            $counter = $entry.Value
            $html += "<div class='metric-label'>$($counter.Name)</div>"
            $html += "<div class='metric-value'>$($counter.Value)</div><br>"
        }
    } else {
        $html += "<div class='metric-label'>No counters recorded</div>"
    }
    
    $html += @"
            </div>
            
            <div class="metric-card">
                <div class="metric-title">📈 Histograms</div>
"@

    # Add histograms
    if ($snapshot.Histograms.Count -gt 0) {
        foreach ($entry in $snapshot.Histograms.GetEnumerator()) {
            $hist = $entry.Value
            $html += "<div class='metric-label'>$($hist.Name)</div>"
            $html += "<div class='metric-value'>$($hist.Count) samples</div>"
            $html += "<small>Mean: $([math]::Round($hist.Mean, 2))ms, P95: $([math]::Round($hist.P95, 2))ms</small><br><br>"
        }
    } else {
        $html += "<div class='metric-label'>No histograms recorded</div>"
    }
    
    $html += @"
            </div>
            
            <div class="metric-card">
                <div class="metric-title">🎯 Gauges</div>
"@

    # Add gauges
    if ($snapshot.Gauges.Count -gt 0) {
        foreach ($entry in $snapshot.Gauges.GetEnumerator()) {
            $gauge = $entry.Value
            $statusClass = if ($gauge.Name -eq "uptime_seconds" -and $gauge.Value -gt 60) { "status-ok" } else { "status-warning" }
            $html += "<div class='metric-label'>$($gauge.Name)</div>"
            $html += "<div class='metric-value $statusClass'>$($gauge.Value)</div><br>"
        }
    } else {
        $html += "<div class='metric-label'>No gauges recorded</div>"
    }
    
    $html += @"
            </div>
            
            <div class="metric-card">
                <div class="metric-title">🔗 API Endpoints</div>
                <div class='metric-label'>Prometheus Metrics</div>
                <div><a href="/metrics" target="_blank">/metrics</a></div><br>
                <div class='metric-label'>JSON Snapshot</div>
                <div><a href="/metrics?format=json" target="_blank">/metrics?format=json</a></div><br>
                <div class='metric-label'>Status Dashboard</div>
                <div><a href="/status" target="_blank">/status</a> (this page)</div>
            </div>
        </div>
        
        <div class="metric-card" style="margin-top: 20px;">
            <div class="metric-title">📋 Raw Metrics Snapshot</div>
            <pre>$(Get-MetricsSnapshot -Format Json)</pre>
        </div>
    </div>
</body>
</html>
"@
    
    return $html
}

function Start-HttpListener {
    param(
        [string]$Prefix = "http://localhost:8765/"
    )
    
    Write-Log "Starting HTTP listener on $Prefix"
    
    # Create HttpListener
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add($Prefix)
    
    try {
        $listener.Start()
        Write-Log "HTTP listener started successfully"
        
        # Update metrics
        Inc-Counter -Name "restarts" -Value 1
        $startTime = Get-Date
        
        Write-Log "Listening for requests... (Press Ctrl+C to stop)"
        
        while ($listener.IsListening) {
            # Update uptime gauge
            $uptime = (Get-Date) - $startTime
            Set-Gauge -Name "uptime_seconds" -Value $uptime.TotalSeconds
            
            # Wait for request
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response
            
            $url = $request.Url.AbsolutePath
            Write-Log "Request: $($request.HttpMethod) $url from $($request.RemoteEndPoint)"
            
            # Route requests
            try {
                switch ($url) {
                    "/metrics" {
                        $format = if ($request.QueryString["format"] -eq "json") { "Json" } else { "Prometheus" }
                        $content = Get-MetricsSnapshot -Format $format
                        $contentType = if ($format -eq "Json") { "application/json" } else { "text/plain" }
                        
                        $response.ContentType = "$contentType; charset=utf-8"
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($content)
                        $response.ContentLength64 = $buffer.Length
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                        
                        Inc-Counter -Name "requests_served" -Labels @{endpoint="metrics"; format=$format}
                    }
                    
                    "/status" {
                        $content = Get-StatusHtml
                        $response.ContentType = "text/html; charset=utf-8"
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($content)
                        $response.ContentLength64 = $buffer.Length
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                        
                        Inc-Counter -Name "requests_served" -Labels @{endpoint="status"}
                    }
                    
                    "/" {
                        # Redirect to /status
                        $response.StatusCode = 302
                        $response.Headers.Add("Location", "/status")
                        
                        Inc-Counter -Name "requests_served" -Labels @{endpoint="redirect"}
                    }
                    
                    default {
                        $response.StatusCode = 404
                        $content = "Not Found: $url"
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($content)
                        $response.ContentLength64 = $buffer.Length
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                        
                        Inc-Counter -Name "requests_served" -Labels @{endpoint="404"}
                    }
                }
                
                $response.StatusCode = if ($response.StatusCode -eq 0) { 200 } else { $response.StatusCode }
            }
            catch {
                Write-Log "Error handling request: $_" -Level "ERROR"
                Inc-Counter -Name "errors" -Labels @{type="request_handling"}
                
                $response.StatusCode = 500
                $content = "Internal Server Error"
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($content)
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            finally {
                $response.Close()
            }
        }
    }
    catch {
        Write-Log "HTTP listener error: $_" -Level "ERROR"
        Inc-Counter -Name "errors" -Labels @{type="listener"}
        throw
    }
    finally {
        if ($listener.IsListening) {
            $listener.Stop()
            Write-Log "HTTP listener stopped"
        }
        $listener.Dispose()
    }
}

function Invoke-SelfTest {
    Write-Host "🚀 Nova Dashboard Self-Test" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Test metrics module
    Write-Host "Testing metrics module..." -ForegroundColor Yellow
    try {
        # Generate some test metrics
        Inc-Counter -Name "signals_seen" -Value 5
        Inc-Counter -Name "contracts_executed" -Value 2
        Inc-Counter -Name "errors" -Value 1 -Labels @{type="test"}
        
        Observe-Histogram -Name "latency_ms" -Value 150
        Observe-Histogram -Name "latency_ms" -Value 200
        Observe-Histogram -Name "latency_ms" -Value 75
        
        Set-Gauge -Name "uptime_seconds" -Value 3600
        
        Write-Host "✅ Metrics module working" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Metrics module error: $_" -ForegroundColor Red
        return
    }
    
    # Test metrics formats
    Write-Host ""
    Write-Host "Testing metrics formats..." -ForegroundColor Yellow
    try {
        $prometheus = Get-MetricsSnapshot -Format Prometheus
        $json = Get-MetricsSnapshot -Format Json
        
        Write-Host "✅ Prometheus format: $($prometheus.Split("`n").Count) lines" -ForegroundColor Green
        Write-Host "✅ JSON format: $($json.Length) characters" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Format error: $_" -ForegroundColor Red
        return
    }
    
    # Display URLs
    Write-Host ""
    Write-Host "🌐 Dashboard URLs:" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host "Status Dashboard:    http://localhost:8765/status" -ForegroundColor White
    Write-Host "Prometheus Metrics:  http://localhost:8765/metrics" -ForegroundColor White
    Write-Host "JSON Metrics:        http://localhost:8765/metrics?format=json" -ForegroundColor White
    Write-Host ""
    
    # Display sample metrics
    Write-Host "📊 Sample Metrics Dump:" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host $prometheus -ForegroundColor White
    
    Write-Host ""
    Write-Host "✅ Self-test completed successfully!" -ForegroundColor Green
    Write-Host "Run with -DaemonMode to start the HTTP server" -ForegroundColor Yellow
}

# Main execution
try {
    if ($SelfTest) {
        Invoke-SelfTest
    }
    elseif ($DaemonMode) {
        Write-Log "Starting Nova Dashboard in daemon mode on ${ListenHost}:${Port}"
        Start-HttpListener -Prefix "http://${ListenHost}:${Port}/"
    }
    else {
        Write-Host "Nova Dashboard - Usage:" -ForegroundColor Cyan
        Write-Host "  -SelfTest    Run self-test and show sample output" -ForegroundColor White
        Write-Host "  -DaemonMode  Start HTTP listener (Ctrl+C to stop)" -ForegroundColor White
        Write-Host "  -Port        Port number (default: 8765)" -ForegroundColor White
        Write-Host "  -ListenHost  Host address (default: localhost)" -ForegroundColor White
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Yellow
        Write-Host "  .\Nova.Dashboard.ps1 -SelfTest" -ForegroundColor Gray
        Write-Host "  .\Nova.Dashboard.ps1 -DaemonMode" -ForegroundColor Gray
        Write-Host "  .\Nova.Dashboard.ps1 -DaemonMode -Port 9090" -ForegroundColor Gray
        Write-Host "  .\Nova.Dashboard.ps1 -DaemonMode -ListenHost 0.0.0.0" -ForegroundColor Gray
    }
}
catch {
    Write-Log "Fatal error: $_" -Level "ERROR"
    Inc-Counter -Name "errors" -Labels @{type="fatal"}
    exit 1
}
