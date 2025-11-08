# Nova.Metrics.psm1 - Lightweight metrics collection for Nova Bot
# Provides counters, histograms, and gauges with daily rotation and Prometheus export

# Import Nova.Common for shared utilities
$CommonModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "Nova.Common\Nova.Common.psm1"
if (Test-Path $CommonModulePath) {
    Import-Module $CommonModulePath -Force
} else {
    # Fallback: try to find Nova.Common in same directory
    $FallbackPath = Join-Path $PSScriptRoot "Nova.Common\Nova.Common.psm1"
    if (Test-Path $FallbackPath) {
        Import-Module $FallbackPath -Force
    }
}

# Import legacy logging for backward compatibility
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

# Initialize metrics path using Nova.Common
$script:MetricsPath = Get-NovaModulePath -Type "Data" -ModuleName "metrics"

# Ensure metrics directory exists using Nova.Common
Confirm-DirectoryPath -Path $script:MetricsPath

function Get-MetricsFileName {
    param([DateTime]$Date = (Get-Date))
    $dateString = Convert-NovaDateTime -DateTime $Date -Format "Timestamp"
    $dateOnly = $dateString.Split('_')[0]  # Get just the date part (yyyyMMdd)
    return Join-Path $script:MetricsPath "metrics_$dateOnly.jsonl"
}

function Save-MetricsEntry {
    param(
        [string]$Type,
        [string]$Name,
        [object]$Value,
        [hashtable]$Labels = @{}
    )
    
    $entry = @{
        timestamp = Convert-NovaDateTime -DateTime (Get-Date) -Format "ISO"
        type = $Type
        name = $Name
        value = $Value
        labels = $Labels
    } | ConvertTo-Json -Compress
    
    $filename = Get-MetricsFileName
    try {
        Add-Content -Path $filename -Value $entry -Encoding UTF8
    } catch {
        Write-NovaLog -Level "Error" -Message "Failed to save metrics entry: $_" -Component "Nova.Metrics"
    }
}

function Test-RotationNeeded {
    $currentDate = (Get-Date).Date
    return $script:MetricsData.LastRotation -lt $currentDate
}

function Invoke-MetricsRotation {
    if (Test-RotationNeeded) {
        Write-NovaLog -Level "Info" -Message "Performing daily metrics rotation" -Component "Nova.Metrics"
        
        # Save current state before rotation
        $snapshot = Get-MetricsSnapshot -Raw
        Save-MetricsEntry -Type "snapshot" -Name "daily_rotation" -Value $snapshot
        
        # Reset counters and histograms, keep gauges
        $script:MetricsData.Counters = @{}
        $script:MetricsData.Histograms = @{}
        $script:MetricsData.LastRotation = (Get-Date).Date
        
        Write-NovaLog -Level "Info" -Message "Metrics rotation completed" -Component "Nova.Metrics"
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
    
    Write-NovaLog -Level "Debug" -Message "Counter '$Name' incremented by $Value (total: $($script:MetricsData.Counters[$key].Value))" -Component "Nova.Metrics"
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
    
    Write-NovaLog -Level "Debug" -Message "Histogram '$Name' observed value $Value (count: $($hist.Count), sum: $($hist.Sum))" -Component "Nova.Metrics"
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
    
    Write-NovaLog -Level "Debug" -Message "Gauge '$Name' set to $Value" -Component "Nova.Metrics"
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
        Timestamp = Convert-NovaDateTime -DateTime (Get-Date) -Format "ISO"
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

Write-NovaLog -Level "Info" -Message "Nova.Metrics module loaded successfully" -Component "Nova.Metrics"

# Export functions
Export-ModuleMember -Function Inc-Counter, Observe-Histogram, Set-Gauge, Get-MetricsSnapshot