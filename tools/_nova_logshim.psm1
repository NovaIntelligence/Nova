# _nova_logshim.psm1 - Centralized logging for Nova Bot
# Provides consistent logging interface across all Nova components

$script:LogPath = "D:\Nova\bot\logs"
$script:LogLevel = "INFO"

# Ensure log directory exists
if (-not (Test-Path $script:LogPath)) {
    New-Item -ItemType Directory -Path $script:LogPath -Force | Out-Null
}

function Get-LogFileName {
    param([string]$Component = "nova")
    $date = Get-Date -Format "yyyyMMdd"
    return Join-Path $script:LogPath "${Component}_${date}.log"
}

function Write-NovaLog {
    <#
    .SYNOPSIS
    Write a log entry to the Nova log system
    
    .PARAMETER Message
    The log message
    
    .PARAMETER Level
    Log level: DEBUG, INFO, WARN, ERROR, FATAL
    
    .PARAMETER Component
    Component name (default: nova)
    
    .EXAMPLE
    Write-NovaLog -Message "Service started" -Level "INFO" -Component "Dashboard"
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR", "FATAL")]
        [string]$Level = "INFO",
        
        [string]$Component = "nova"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level] [$Component] $Message"
    
    # Write to console with colors
    $color = switch ($Level) {
        "DEBUG" { "Gray" }
        "INFO"  { "White" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
        "FATAL" { "Magenta" }
        default { "White" }
    }
    
    Write-Host $logEntry -ForegroundColor $color
    
    # Write to log file
    try {
        $logFile = Get-LogFileName -Component $Component
        Add-Content -Path $logFile -Value $logEntry -Encoding UTF8
    }
    catch {
        Write-Host "Failed to write to log file: $_" -ForegroundColor Red
    }
}

function Set-NovaLogLevel {
    param(
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR", "FATAL")]
        [string]$Level
    )
    $script:LogLevel = $Level
    Write-NovaLog -Message "Log level set to $Level" -Level "INFO" -Component "LogShim"
}

function Get-NovaLogLevel {
    return $script:LogLevel
}

# Export functions
Export-ModuleMember -Function Write-NovaLog, Set-NovaLogLevel, Get-NovaLogLevel

# Initialize
Write-NovaLog -Message "Nova LogShim initialized" -Level "INFO" -Component "LogShim"