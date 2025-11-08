function Test-NovaPath {
    <#
    .SYNOPSIS
    Enhanced path validation with Nova-specific logic
    
    .DESCRIPTION
    Provides enhanced path testing with common validation patterns used
    throughout Nova Bot modules. Includes safety checks and logging.
    
    .PARAMETER Path
    The path to test
    
    .PARAMETER Type
    The expected path type (File, Directory, Any)
    
    .PARAMETER Required
    Whether the path must exist (throws if not found)
    
    .PARAMETER Component
    Component name for logging
    
    .OUTPUTS
    Boolean indicating if path exists and matches criteria
    
    .EXAMPLE
    Test-NovaPath -Path "D:\Nova\data\metrics" -Type Directory
    
    .EXAMPLE  
    Test-NovaPath -Path "config.json" -Type File -Required -Component "Nova.Skills"
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,
        
        [Parameter(Position = 1)]
        [ValidateSet("File", "Directory", "Any")]
        [string]$Type = "Any",
        
        [switch]$Required,
        
        [string]$Component = "Nova.Common"
    )
    
    # Basic existence check
    $exists = Test-Path -Path $Path
    
    if (-not $exists) {
        if ($Required) {
            $errorMsg = "Required path not found: $Path"
            Write-NovaLog -Message $errorMsg -Level "ERROR" -Component $Component
            throw [System.IO.FileNotFoundException]::new($errorMsg)
        }
        
        Write-NovaLog -Message "Path does not exist: $Path" -Level "DEBUG" -Component $Component
        return $false
    }
    
    # Type-specific validation
    if ($Type -ne "Any") {
        $item = Get-Item -Path $Path -ErrorAction SilentlyContinue
        
        switch ($Type) {
            "File" {
                if ($item.PSIsContainer) {
                    if ($Required) {
                        $errorMsg = "Expected file but found directory: $Path"
                        Write-NovaLog -Message $errorMsg -Level "ERROR" -Component $Component
                        throw [System.ArgumentException]::new($errorMsg)
                    }
                    return $false
                }
            }
            "Directory" {
                if (-not $item.PSIsContainer) {
                    if ($Required) {
                        $errorMsg = "Expected directory but found file: $Path"
                        Write-NovaLog -Message $errorMsg -Level "ERROR" -Component $Component
                        throw [System.ArgumentException]::new($errorMsg)
                    }
                    return $false
                }
            }
        }
    }
    
    return $true
}