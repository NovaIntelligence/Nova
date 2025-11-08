function Write-NovaLog {
    <#
    .SYNOPSIS
    Centralized logging function for Nova Bot modules
    
    .DESCRIPTION
    Provides consistent logging across all Nova Bot modules with automatic fallback
    to console output when the full logging system is not available.
    
    .PARAMETER Message
    The message to log
    
    .PARAMETER Level
    The log level (INFO, WARN, ERROR, DEBUG, TRACE)
    
    .PARAMETER Component
    The component or module name generating the log entry
    
    .EXAMPLE
    Write-NovaLog -Message "Operation completed" -Level "INFO" -Component "Nova.Skills"
    
    .EXAMPLE
    Write-NovaLog "Error occurred" "ERROR" "Nova.Metrics"
    #>
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [string]$Message = "",
        
        [Parameter(Position = 1)]
        [ValidateSet("TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL", "Debug", "Info", "Warning", "Error")]
        [string]$Level = "INFO",
        
        [Parameter(Position = 2)]
        [string]$Component = "Nova"
    )
    
    # Try to use the full logging system if available
    if (Get-Command "Write-NovaLog" -Module "Nova.Logging" -ErrorAction SilentlyContinue) {
        & (Get-Command "Write-NovaLog" -Module "Nova.Logging") -Level $Level.ToLower() -Module $Component -Msg $Message
        return
    }
    
    # Fallback to console output with consistent formatting
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $levelPadded = $Level.PadRight(5)
    $componentPadded = $Component.PadRight(15)
    
    $color = switch ($Level.ToUpper()) {
        "ERROR"  { "Red" }
        "FATAL"  { "DarkRed" }
        "WARN"   { "Yellow" }
        "INFO"   { "Cyan" }
        "DEBUG"  { "Gray" }
        "TRACE"  { "DarkGray" }
        default  { "White" }
    }
    
    Write-Host "[$timestamp] [$levelPadded] [$componentPadded] $Message" -ForegroundColor $color
}