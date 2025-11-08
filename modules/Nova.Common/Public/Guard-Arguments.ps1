function Guard-NotNull {
    <#
    .SYNOPSIS
    Guard clause for null argument validation
    
    .DESCRIPTION
    Provides consistent null argument validation with descriptive error messages.
    Used throughout Nova Bot modules for defensive programming.
    
    .PARAMETER Value
    The value to check for null
    
    .PARAMETER Name
    The name of the parameter being validated
    
    .PARAMETER Component
    Component name for logging
    
    .EXAMPLE
    Guard-NotNull -Value $inputData -Name "inputData"
    #>
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [object]$Value,
        
        [Parameter(Mandatory, Position = 1)]
        [string]$Name,
        
        [Parameter(Position = 2)]
        [string]$Component = "Nova.Common"
    )
    
    if ($null -eq $Value) {
        $errorMsg = "Parameter '$Name' cannot be null"
        Write-NovaLog -Message $errorMsg -Level "ERROR" -Component $Component
        throw [System.ArgumentNullException]::new($Name, $errorMsg)
    }
}

function Guard-NotEmpty {
    <#
    .SYNOPSIS
    Guard clause for null or empty string validation
    
    .DESCRIPTION
    Validates that string parameters are not null, empty, or whitespace-only.
    
    .PARAMETER Value
    The string value to validate
    
    .PARAMETER Name
    The name of the parameter being validated
    
    .PARAMETER Component
    Component name for logging
    
    .EXAMPLE
    Guard-NotEmpty -Value $apiKey -Name "ApiKey"
    #>
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [string]$Value,
        
        [Parameter(Mandatory, Position = 1)]
        [string]$Name,
        
        [Parameter(Position = 2)]
        [string]$Component = "Nova.Common"
    )
    
    if ([string]::IsNullOrWhiteSpace($Value)) {
        $errorMsg = "Parameter '$Name' cannot be null, empty, or whitespace"
        Write-NovaLog -Message $errorMsg -Level "ERROR" -Component $Component
        throw [System.ArgumentException]::new($errorMsg, $Name)
    }
}

function Guard-Range {
    <#
    .SYNOPSIS
    Guard clause for numeric range validation
    
    .DESCRIPTION
    Validates that numeric parameters fall within specified ranges with inclusive bounds.
    
    .PARAMETER Value
    The numeric value to validate
    
    .PARAMETER Min
    Minimum allowed value (inclusive)
    
    .PARAMETER Max
    Maximum allowed value (inclusive)
    
    .PARAMETER Name
    The name of the parameter being validated
    
    .PARAMETER Component
    Component name for logging
    
    .EXAMPLE
    Guard-Range -Value $timeout -Min 1 -Max 300 -Name "TimeoutSeconds"
    #>
    param(
        [Parameter(Position = 0)]
        [object]$Value,
        
        [Parameter(Position = 1)]
        [object]$Min,
        
        [Parameter(Position = 2)]
        [object]$Max,
        
        [Parameter(Mandatory, Position = 3)]
        [string]$Name,
        
        [Parameter()]
        [string]$Component = "Nova.Common"
    )
    
    try {
        $numValue = [double]$Value
        $numMin = [double]$Min
        $numMax = [double]$Max
    }
    catch {
        $errorMsg = "Parameter '$Name' must be numeric for range validation"
        Write-NovaLog -Message $errorMsg -Level "ERROR" -Component $Component
        throw [System.ArgumentException]::new($errorMsg, $Name)
    }
    
    if ($numValue -lt $numMin -or $numValue -gt $numMax) {
        $errorMsg = "Parameter '$Name' value $numValue is outside allowed range [$numMin, $numMax]"
        Write-NovaLog -Message $errorMsg -Level "ERROR" -Component $Component
        throw [System.ArgumentOutOfRangeException]::new($Name, $numValue, $errorMsg)
    }
}

function Guard-Path {
    <#
    .SYNOPSIS
    Guard clause for path validation
    
    .DESCRIPTION
    Validates that path parameters exist and are of the expected type (file or directory).
    
    .PARAMETER Value
    The path to validate
    
    .PARAMETER Name
    The name of the parameter being validated
    
    .PARAMETER Type
    Expected path type (File, Directory, or Any)
    
    .PARAMETER MustExist
    Whether the path must already exist
    
    .PARAMETER Component
    Component name for logging
    
    .EXAMPLE
    Guard-Path -Value $configFile -Name "ConfigFile" -Type "File" -MustExist
    #>
    param(
        [Parameter(Position = 0)]
        [string]$Value,
        
        [Parameter(Mandatory, Position = 1)]
        [string]$Name,
        
        [Parameter()]
        [ValidateSet("File", "Directory", "Any")]
        [string]$Type = "Any",
        
        [Parameter()]
        [switch]$MustExist,
        
        [Parameter()]
        [string]$Component = "Nova.Common"
    )
    
    if ([string]::IsNullOrWhiteSpace($Value)) {
        $errorMsg = "Parameter '$Name' path cannot be null or empty"
        Write-NovaLog -Message $errorMsg -Level "ERROR" -Component $Component
        throw [System.ArgumentException]::new($errorMsg, $Name)
    }
    
    if ($MustExist -and -not (Test-Path $Value)) {
        $errorMsg = "Parameter '$Name' path does not exist: $Value"
        Write-NovaLog -Message $errorMsg -Level "ERROR" -Component $Component
        throw [System.IO.FileNotFoundException]::new($errorMsg, $Value)
    }
    
    if ($Type -ne "Any" -and (Test-Path $Value)) {
        $isDirectory = (Get-Item $Value -ErrorAction SilentlyContinue) -is [System.IO.DirectoryInfo]
        
        if ($Type -eq "Directory" -and -not $isDirectory) {
            $errorMsg = "Parameter '$Name' must be a directory, but is a file: $Value"
            Write-NovaLog -Message $errorMsg -Level "ERROR" -Component $Component
            throw [System.ArgumentException]::new($errorMsg, $Name)
        }
        
        if ($Type -eq "File" -and $isDirectory) {
            $errorMsg = "Parameter '$Name' must be a file, but is a directory: $Value"
            Write-NovaLog -Message $errorMsg -Level "ERROR" -Component $Component
            throw [System.ArgumentException]::new($errorMsg, $Name)
        }
    }
}