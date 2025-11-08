function Convert-NovaDateTime {
    <#
    .SYNOPSIS
    Standardized datetime formatting for Nova Bot
    
    .DESCRIPTION
    Provides consistent datetime conversion and formatting across Nova Bot modules.
    Supports multiple input formats and standardized output formats.
    
    .PARAMETER DateTime
    The datetime to format. Accepts DateTime objects, strings, or null
    
    .PARAMETER Format
    Output format type
    
    .PARAMETER TimeZone
    Optional timezone for conversion (default: local)
    
    .OUTPUTS
    Formatted datetime string or null
    
    .EXAMPLE
    Convert-NovaDateTime -DateTime (Get-Date) -Format "Timestamp"
    Returns: 20251024_143022
    
    .EXAMPLE
    Convert-NovaDateTime -DateTime "2025-01-24T14:30:22Z" -Format "Display"  
    Returns: 01/24/2025 14:30:22
    #>
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        $DateTime,
        
        [Parameter(Position = 1)]
        [ValidateSet("Timestamp", "Display", "ISO", "Log", "Filename")]
        [string]$Format = "Display",
        
        [Parameter()]
        [string]$TimeZone = "Local"
    )
    
    # Handle null input
    if ($null -eq $DateTime) {
        return $null
    }
    
    # Convert to DateTime object if needed
    try {
        if ($DateTime -is [string]) {
            $dateObj = [DateTime]::Parse($DateTime)
        } elseif ($DateTime -is [DateTime]) {
            $dateObj = $DateTime
        } else {
            Write-Warning "Invalid datetime input: $DateTime"
            return $null
        }
    }
    catch {
        Write-Warning "Failed to parse datetime '$DateTime': $($_.Exception.Message)"
        return $null
    }
    
    # Apply timezone conversion if specified
    if ($TimeZone -ne "Local" -and $TimeZone -ne "UTC") {
        try {
            $tz = [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone)
            $dateObj = [TimeZoneInfo]::ConvertTime($dateObj, $tz)
        }
        catch {
            Write-Warning "Invalid timezone '$TimeZone', using local time"
        }
    }
    
    # Format based on type
    switch ($Format) {
        "Timestamp" { 
            return $dateObj.ToString("yyyyMMdd_HHmmss")
        }
        "Display" { 
            return $dateObj.ToString("MM/dd/yyyy HH:mm:ss")
        }
        "ISO" { 
            return $dateObj.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        "Log" { 
            return $dateObj.ToString("yyyy-MM-dd HH:mm:ss.fff")
        }
        "Filename" { 
            return $dateObj.ToString("yyyy-MM-dd_HH-mm-ss")
        }
        default { 
            return $dateObj.ToString()
        }
    }
}