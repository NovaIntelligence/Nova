# Nova.Metrics.psm1 - Lightweight metrics collection for Nova Bot
# Provides counters, histograms, and gauges with daily rotation and Prometheus export

# Import logging
if (Test-Path "$PSScriptRoot\..\bot\tools\_nova_logshim.psm1") {
    Import-Module "$PSScriptRoot\..\bot\tools\_nova_logshim.psm1" -Force
} elseif (Test-Path "$PSScriptRoot\..\tools\_nova_logshim.psm1") {
    Import-Module "$PSScriptRoot\..\tools\_nova_logshim.psm1" -Force
}

# Global metrics storage
$script:MetricsData = @{
    Counters = @{}
    Histograms = @{}
    Gauges = @{}
    LastRotation = (Get-Date).Date
}

$script:MetricsPath = "D:\Nova\bot\data\metrics"

# Ensure metrics directory exists
if (-not (Test-Path $script:MetricsPath)) {
    New-Item -ItemType Directory -Path $script:MetricsPath -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    if (Get-Command "Write-NovaLog" -ErrorAction SilentlyContinue) {
        Write-NovaLog -Message $Message -Level $Level -Component "Nova.Metrics"
    } else {
        Write-Host "[$Level] $(Get-Date -Format 'HH:mm:ss') Nova.Metrics: $Message"
    }
}

function Get-MetricsFileName {
    param([DateTime]$Date = (Get-Date))
    return Join-Path $script:MetricsPath "metrics_$($Date.ToString('yyyyMMdd')).jsonl"
}

function Save-MetricsEntry {
    param(
        [string]$Type,
        [string]$Name,
        [object]$Value,
        [hashtable]$Labels = @{}
    )
    
    $entry = @{
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        type = $Type
        name = $Name
        value = $Value
        labels = $Labels
    } | ConvertTo-Json -Compress
    
    $filename = Get-MetricsFileName
    try {
        Add-Content -Path $filename -Value $entry -Encoding UTF8
    } catch {
        Write-Log "Failed to save metrics entry: $_" -Level "ERROR"
    }
}

function Test-RotationNeeded {
    $currentDate = (Get-Date).Date
    return $script:MetricsData.LastRotation -lt $currentDate
}

function Invoke-MetricsRotation {
    if (Test-RotationNeeded) {
        Write-Log "Performing daily metrics rotation"
        
        # Save current state before rotation
        $snapshot = Get-MetricsSnapshot -Raw
        Save-MetricsEntry -Type "snapshot" -Name "daily_rotation" -Value $snapshot
        
        # Reset counters and histograms, keep gauges
        $script:MetricsData.Counters = @{}
        $script:MetricsData.Histograms = @{}
        $script:MetricsData.LastRotation = (Get-Date).Date
        
        Write-Log "Metrics rotation completed"
    }
}

function Inc-Counter {
    <#
    .SYNOPSIS
    Increment a counter metric
    
    .PARAMETER Name
    Name of the counter
    
    .PARAMETER Value
    Amount to increment (default: 1)
    
    .PARAMETER Labels
    Optional labels hashtable
    
    .EXAMPLE
    Inc-Counter -Name "signals_seen" -Value 1
    Inc-Counter -Name "errors" -Labels @{type="connection"}
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [int]$Value = 1,
        
        [hashtable]$Labels = @{}
    )
    
    Invoke-MetricsRotation
    
    $key = if ($Labels.Count -gt 0) { "$Name|$($Labels.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } | Sort-Object | Join-String -Separator ',')" } else { $Name }
    
    if (-not $script:MetricsData.Counters.ContainsKey($key)) {
        $script:MetricsData.Counters[$key] = @{ Value = 0; Labels = $Labels; Name = $Name }
    }
    
    $script:MetricsData.Counters[$key].Value += $Value
    Save-MetricsEntry -Type "counter" -Name $Name -Value $Value -Labels $Labels
    
    Write-Log "Counter '$Name' incremented by $Value (total: $($script:MetricsData.Counters[$key].Value))"
}

function Observe-Histogram {
    <#
    .SYNOPSIS
    Record a histogram observation
    
    .PARAMETER Name
    Name of the histogram
    
    .PARAMETER Value
    Value to observe
    
    .PARAMETER Labels
    Optional labels hashtable
    
    .EXAMPLE
    Observe-Histogram -Name "latency_ms" -Value 150
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [double]$Value,
        
        [hashtable]$Labels = @{}
    )
    
    Invoke-MetricsRotation
    
    $key = if ($Labels.Count -gt 0) { "$Name|$($Labels.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } | Sort-Object | Join-String -Separator ',')" } else { $Name }
    
    if (-not $script:MetricsData.Histograms.ContainsKey($key)) {
        $script:MetricsData.Histograms[$key] = @{
            Name = $Name
            Labels = $Labels
            Values = @()
            Count = 0
            Sum = 0
        }
    }
    
    $hist = $script:MetricsData.Histograms[$key]
    $hist.Values += $Value
    $hist.Count++
    $hist.Sum += $Value
    
    # Keep only last 1000 values for memory efficiency
    if ($hist.Values.Count -gt 1000) {
        $hist.Values = $hist.Values | Select-Object -Last 1000
    }
    
    Save-MetricsEntry -Type "histogram" -Name $Name -Value $Value -Labels $Labels
    
    Write-Log "Histogram '$Name' observed value $Value (count: $($hist.Count), sum: $($hist.Sum))"
}

function Set-Gauge {
    <#
    .SYNOPSIS
    Set a gauge metric value
    
    .PARAMETER Name
    Name of the gauge
    
    .PARAMETER Value
    Value to set
    
    .PARAMETER Labels
    Optional labels hashtable
    
    .EXAMPLE
    Set-Gauge -Name "uptime_seconds" -Value 3600
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [double]$Value,
        
        [hashtable]$Labels = @{}
    )
    
    Invoke-MetricsRotation
    
    $key = if ($Labels.Count -gt 0) { "$Name|$($Labels.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } | Sort-Object | Join-String -Separator ',')" } else { $Name }
    
    $script:MetricsData.Gauges[$key] = @{
        Name = $Name
        Labels = $Labels
        Value = $Value
        Timestamp = Get-Date
    }
    
    Save-MetricsEntry -Type "gauge" -Name $Name -Value $Value -Labels $Labels
    
    Write-Log "Gauge '$Name' set to $Value"
}

function Get-MetricsSnapshot {
    <#
    .SYNOPSIS
    Get current metrics snapshot
    
    .PARAMETER Format
    Output format: 'Prometheus', 'Json', or 'Raw' (default: Raw)
    
    .EXAMPLE
    Get-MetricsSnapshot -Format Prometheus
    #>
    param(
        [ValidateSet('Prometheus', 'Json', 'Raw')]
        [string]$Format = 'Raw'
    )
    
    Invoke-MetricsRotation
    
    $snapshot = @{
        Timestamp = (Get-Date).ToUniversalTime().ToString('o')
        Counters = @{}
        Histograms = @{}
        Gauges = @{}
    }
    
    # Process counters
    foreach ($entry in $script:MetricsData.Counters.GetEnumerator()) {
        $snapshot.Counters[$entry.Key] = $entry.Value
    }
    
    # Process histograms with calculations
    foreach ($entry in $script:MetricsData.Histograms.GetEnumerator()) {
        $hist = $entry.Value
        $values = $hist.Values | Sort-Object
        
        $snapshot.Histograms[$entry.Key] = @{
            Name = $hist.Name
            Labels = $hist.Labels
            Count = $hist.Count
            Sum = $hist.Sum
            Min = if ($values.Count -gt 0) { $values[0] } else { 0 }
            Max = if ($values.Count -gt 0) { $values[-1] } else { 0 }
            Mean = if ($hist.Count -gt 0) { $hist.Sum / $hist.Count } else { 0 }
            P50 = if ($values.Count -gt 0) { $values[[math]::Floor($values.Count * 0.5)] } else { 0 }
            P95 = if ($values.Count -gt 0) { $values[[math]::Floor($values.Count * 0.95)] } else { 0 }
            P99 = if ($values.Count -gt 0) { $values[[math]::Floor($values.Count * 0.99)] } else { 0 }
        }
    }
    
    # Process gauges
    foreach ($entry in $script:MetricsData.Gauges.GetEnumerator()) {
        $snapshot.Gauges[$entry.Key] = $entry.Value
    }
    
    switch ($Format) {
        'Prometheus' {
            return ConvertTo-PrometheusFormat $snapshot
        }
        'Json' {
            return $snapshot | ConvertTo-Json -Depth 10
        }
        default {
            return $snapshot
        }
    }
}

function ConvertTo-PrometheusFormat {
    param([hashtable]$Snapshot)
    
    $output = @()
    $output += "# Nova Bot Metrics"
    $output += "# Generated at $($snapshot.Timestamp)"
    $output += ""
    
    # Counters
    foreach ($entry in $Snapshot.Counters.GetEnumerator()) {
        $counter = $entry.Value
        $labelStr = if ($counter.Labels.Count -gt 0) {
            $labelPairs = $counter.Labels.GetEnumerator() | ForEach-Object { "$($_.Key)=""$($_.Value)""" }
            "{$($labelPairs -join ',')}"
        } else { "" }
        
        $output += "# TYPE $($counter.Name) counter"
        $output += "$($counter.Name)$labelStr $($counter.Value)"
    }
    
    if ($Snapshot.Counters.Count -gt 0) { $output += "" }
    
    # Histograms
    foreach ($entry in $Snapshot.Histograms.GetEnumerator()) {
        $hist = $entry.Value
        $labelStr = if ($hist.Labels.Count -gt 0) {
            $labelPairs = $hist.Labels.GetEnumerator() | ForEach-Object { "$($_.Key)=""$($_.Value)""" }
            "{$($labelPairs -join ',')}"
        } else { "" }
        
        $output += "# TYPE $($hist.Name) histogram"
        $output += "$($hist.Name)_count$labelStr $($hist.Count)"
        $output += "$($hist.Name)_sum$labelStr $($hist.Sum)"
        $output += "$($hist.Name)_min$labelStr $($hist.Min)"
        $output += "$($hist.Name)_max$labelStr $($hist.Max)"
        $output += "$($hist.Name)_mean$labelStr $([math]::Round($hist.Mean, 2))"
    }
    
    if ($Snapshot.Histograms.Count -gt 0) { $output += "" }
    
    # Gauges
    foreach ($entry in $Snapshot.Gauges.GetEnumerator()) {
        $gauge = $entry.Value
        $labelStr = if ($gauge.Labels.Count -gt 0) {
            $labelPairs = $gauge.Labels.GetEnumerator() | ForEach-Object { "$($_.Key)=""$($_.Value)""" }
            "{$($labelPairs -join ',')}"
        } else { "" }
        
        $output += "# TYPE $($gauge.Name) gauge"
        $output += "$($gauge.Name)$labelStr $($gauge.Value)"
    }
    
    return $output -join "`n"
}

# Initialize some default metrics
Inc-Counter -Name "restarts" -Value 0
Set-Gauge -Name "uptime_seconds" -Value 0

Write-Log "Nova.Metrics module loaded successfully"

# Export functions
Export-ModuleMember -Function Inc-Counter, Observe-Histogram, Set-Gauge, Get-MetricsSnapshot