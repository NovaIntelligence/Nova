function Get-NovaModulePath {
    <#
    .SYNOPSIS
    Gets standardized paths for Nova Bot modules
    
    .DESCRIPTION
    Provides consistent path resolution for common Nova Bot directories
    and files. Handles both development and deployment scenarios.
    
    .PARAMETER Type
    The type of path to retrieve
    
    .PARAMETER ModuleName
    Optional module name for module-specific paths
    
    .OUTPUTS
    String path to the requested location
    
    .EXAMPLE
    Get-NovaModulePath -Type "Data"
    Returns: D:\Nova\data
    
    .EXAMPLE  
    Get-NovaModulePath -Type "Logs" -ModuleName "Skills"
    Returns: D:\Nova\logs\skills.log
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet("Root", "Data", "Logs", "Config", "Modules", "Tools", "Tests")]
        [string]$Type,
        
        [Parameter(Position = 1)]
        [string]$ModuleName
    )
    
    # Determine Nova root directory
    $novaRoot = $PSScriptRoot
    
    # If PSScriptRoot is empty (when called from tests), use default
    if ([string]::IsNullOrWhiteSpace($novaRoot)) {
        $novaRoot = "D:\Nova"
    } else {
        # Walk up directory tree to find Nova.ps1
        while ($novaRoot -and -not (Test-Path (Join-Path $novaRoot "Nova.ps1"))) {
            $parent = Split-Path $novaRoot -Parent
            if ($parent -eq $novaRoot -or [string]::IsNullOrWhiteSpace($parent)) {
                # Reached root without finding Nova.ps1, use default
                $novaRoot = "D:\Nova"
                break
            }
            $novaRoot = $parent
        }
    }
    
    # Ensure we have a valid root path
    if ([string]::IsNullOrWhiteSpace($novaRoot)) {
        $novaRoot = "D:\Nova"
    }
    
    # Build paths based on type
    switch ($Type) {
        "Root" { 
            return $novaRoot 
        }
        "Data" { 
            $path = Join-Path $novaRoot "data"
            if ($ModuleName) {
                $path = Join-Path $path $ModuleName.ToLower()
            }
            return $path
        }
        "Logs" { 
            $path = Join-Path $novaRoot "logs"
            if ($ModuleName) {
                return Join-Path $path "$($ModuleName.ToLower()).log"
            }
            return $path
        }
        "Config" { 
            $path = Join-Path $novaRoot "config"
            if ($ModuleName) {
                return Join-Path $path "$($ModuleName.ToLower()).json"
            }
            return $path
        }
        "Modules" { 
            $path = Join-Path $novaRoot "modules"
            if ($ModuleName) {
                return Join-Path $path "Nova.$ModuleName"
            }
            return $path
        }
        "Tools" { 
            return Join-Path $novaRoot "tools"
        }
        "Tests" { 
            return Join-Path $novaRoot "tests"
        }
    }
}