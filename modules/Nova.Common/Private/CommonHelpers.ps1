# Private helper functions for Nova.Common module

function Get-NovaRootPath {
    <#
    .SYNOPSIS
    Internal helper to find Nova Bot root directory
    
    .DESCRIPTION
    Searches upward from current location to find Nova.ps1 file
    #>
    param(
        [string]$StartPath = $PSScriptRoot
    )
    
    $current = $StartPath
    while ($current -and -not (Test-Path (Join-Path $current "Nova.ps1"))) {
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) {
            return "D:\Nova"  # Default fallback
        }
        $current = $parent
    }
    
    return $current
}

function Test-NovaComponent {
    <#
    .SYNOPSIS
    Internal helper to validate component names
    
    .DESCRIPTION
    Ensures component names follow Nova Bot conventions
    #>
    param(
        [string]$ComponentName
    )
    
    if ([string]::IsNullOrWhiteSpace($ComponentName)) {
        return $false
    }
    
    # Component names should be alphanumeric with dots/hyphens
    return $ComponentName -match '^[A-Za-z0-9\.\-_]+$'
}

function ConvertTo-NovaLogLevel {
    <#
    .SYNOPSIS
    Internal helper to normalize log levels
    
    .DESCRIPTION
    Converts various log level formats to standard Nova levels
    #>
    param(
        [string]$Level
    )
    
    switch ($Level.ToLower()) {
        { $_ -in @("debug", "dbg", "d", "verbose", "v") } { return "Debug" }
        { $_ -in @("info", "information", "i") } { return "Info" }
        { $_ -in @("warn", "warning", "w") } { return "Warning" }
        { $_ -in @("error", "err", "e") } { return "Error" }
        { $_ -in @("critical", "crit", "c", "fatal", "f") } { return "Critical" }
        default { return "Info" }
    }
}

function Get-NovaTimestamp {
    <#
    .SYNOPSIS
    Internal helper for consistent timestamps
    
    .DESCRIPTION
    Returns standardized timestamp for internal Nova operations
    #>
    return Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
}

function Format-NovaError {
    <#
    .SYNOPSIS
    Internal helper for consistent error formatting
    
    .DESCRIPTION
    Formats error objects consistently for Nova logging
    #>
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )
    
    if (-not $ErrorRecord) {
        return "Unknown error occurred"
    }
    
    $formatted = @{
        Message = $ErrorRecord.Exception.Message
        Type = $ErrorRecord.Exception.GetType().Name
        Line = $ErrorRecord.InvocationInfo.ScriptLineNumber
        Column = $ErrorRecord.InvocationInfo.OffsetInLine
        Script = Split-Path $ErrorRecord.InvocationInfo.ScriptName -Leaf
    }
    
    return "[$($formatted.Type)] $($formatted.Message) at $($formatted.Script):$($formatted.Line):$($formatted.Column)"
}