# Build-PlatyPS.ps1 - PowerShell Module Documentation Generator
# Creators: Tyler McKendry & Nova
# Generates comprehensive PowerShell module help using PlatyPS for all Nova modules

[CmdletBinding()]
param(
    [string]$ModulesPath = "..\..\modules",
    [string]$OutputPath = ".\out",
    [switch]$Force,
    [switch]$Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Initialize logging
function Write-DocLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "INFO"  { "Cyan" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

Write-DocLog "Starting PowerShell documentation generation with PlatyPS" "INFO"

try {
    # Ensure PlatyPS is available
    if (-not (Get-Module -ListAvailable -Name PlatyPS)) {
        Write-DocLog "Installing PlatyPS module..." "INFO"
        Install-Module -Name PlatyPS -Force -Scope CurrentUser -AllowClobber
    }
    
    Import-Module PlatyPS -Force
    Write-DocLog "PlatyPS module loaded successfully" "SUCCESS"
    
    # Resolve paths
    $ModulesPath = Resolve-Path $ModulesPath -ErrorAction Stop
    Write-DocLog "Modules path: $ModulesPath" "INFO"
    
    # Create output directory
    if (Test-Path $OutputPath) {
        if ($Force) {
            Remove-Item -Path $OutputPath -Recurse -Force
            Write-DocLog "Cleaned existing output directory" "INFO"
        }
    }
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    $OutputPath = Resolve-Path $OutputPath
    Write-DocLog "Output path: $OutputPath" "INFO"
    
    # Discover PowerShell modules
    $moduleFiles = Get-ChildItem -Path $ModulesPath -Filter "*.ps1" | Where-Object { 
        $_.Name -match "^Nova\." -and $_.Name -ne "Nova.Tests.ps1" 
    }
    
    if ($moduleFiles.Count -eq 0) {
        Write-DocLog "No Nova modules found in $ModulesPath" "WARN"
        return
    }
    
    Write-DocLog "Found $($moduleFiles.Count) Nova modules to document" "INFO"
    
    # Track documentation statistics
    $stats = @{
        ModulesProcessed = 0
        FunctionsDocumented = 0
        Errors = 0
    }
    
    # Process each module
    foreach ($moduleFile in $moduleFiles) {
        $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($moduleFile.Name)
        Write-DocLog "Processing module: $moduleName" "INFO"
        
        try {
            # Create module output directory
            $moduleOutputPath = Join-Path $OutputPath $moduleName
            New-Item -ItemType Directory -Path $moduleOutputPath -Force | Out-Null
            
            # Import module temporarily for documentation extraction
            $moduleContent = Get-Content -Path $moduleFile.FullName -Raw
            
            # Check if module has exportable functions
            if ($moduleContent -match "function\s+(\w+-\w+|\w+)") {
                Write-DocLog "  Found functions in $moduleName, importing for documentation..." "INFO"
                
                # Import the module in a safe way
                $tempModule = $null
                try {
                    # Use Import-Module with -Force to ensure clean import
                    $tempModule = Import-Module $moduleFile.FullName -Force -PassThru -ErrorAction Stop
                    
                    if ($tempModule) {
                        Write-DocLog "  Module imported successfully: $($tempModule.Name)" "SUCCESS"
                        
                        # Get exported functions
                        $exportedFunctions = Get-Command -Module $tempModule.Name -CommandType Function -ErrorAction SilentlyContinue
                        
                        if ($exportedFunctions) {
                            Write-DocLog "  Found $($exportedFunctions.Count) exported functions" "INFO"
                            
                            # Generate markdown help
                            try {
                                New-MarkdownHelp -Module $tempModule.Name -OutputFolder $moduleOutputPath -Force -ErrorAction Stop
                                Write-DocLog "  ✅ Markdown help generated for $moduleName" "SUCCESS"
                                
                                # Generate external help (XML)
                                $externalHelpPath = Join-Path $moduleOutputPath "en-US"
                                New-Item -ItemType Directory -Path $externalHelpPath -Force | Out-Null
                                
                                New-ExternalHelp -Path $moduleOutputPath -OutputPath $externalHelpPath -Force -ErrorAction Stop
                                Write-DocLog "  ✅ External help (XML) generated for $moduleName" "SUCCESS"
                                
                                $stats.FunctionsDocumented += $exportedFunctions.Count
                                
                                # Create module index
                                $indexContent = @"
# $moduleName Documentation

## Overview
PowerShell module: **$moduleName**
Generated on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')

## Functions
$($exportedFunctions | ForEach-Object { "- [$($_.Name)](./$($_.Name).md)" } | Out-String)

## Files
- [Module Source](../../modules/$($moduleFile.Name))
- [External Help](./en-US/$moduleName-help.xml)

## Usage Example
``````powershell
# Import the module
Import-Module "modules\$($moduleFile.Name)" -Force

# List available functions
Get-Command -Module $moduleName
``````
"@
                                $indexContent | Out-File -FilePath (Join-Path $moduleOutputPath "README.md") -Encoding UTF8
                                Write-DocLog "  ✅ Module index created for $moduleName" "SUCCESS"
                                
                            }
                            catch {
                                Write-DocLog "  ❌ Failed to generate help for $moduleName`: $($_.Exception.Message)" "ERROR"
                                $stats.Errors++
                            }
                        }
                        else {
                            Write-DocLog "  ⚠️ No exported functions found in $moduleName" "WARN"
                        }
                    }
                }
                catch {
                    Write-DocLog "  ❌ Failed to import $moduleName`: $($_.Exception.Message)" "ERROR"
                    $stats.Errors++
                }
                finally {
                    # Clean up imported module
                    if ($tempModule -and (Get-Module -Name $tempModule.Name -ErrorAction SilentlyContinue)) {
                        Remove-Module -Name $tempModule.Name -Force -ErrorAction SilentlyContinue
                        Write-DocLog "  🧹 Cleaned up module: $($tempModule.Name)" "INFO"
                    }
                }
            }
            else {
                Write-DocLog "  ⚠️ No functions found in $moduleName, creating placeholder documentation" "WARN"
                
                # Create placeholder documentation for modules without functions
                $placeholderContent = @"
# $moduleName

## Status
This module does not currently export any public functions.

## File Location
- [Module Source](../../modules/$($moduleFile.Name))

Generated on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')
"@
                $placeholderContent | Out-File -FilePath (Join-Path $moduleOutputPath "README.md") -Encoding UTF8
            }
            
            $stats.ModulesProcessed++
        }
        catch {
            Write-DocLog "❌ Failed to process module $moduleName`: $($_.Exception.Message)" "ERROR"
            $stats.Errors++
        }
    }
    
    # Generate main index
    Write-DocLog "Creating main PowerShell documentation index..." "INFO"
    $mainIndexContent = @"
# Nova PowerShell Modules Documentation

Generated on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')

## Modules Overview

$($moduleFiles | ForEach-Object {
    $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    "- [$moduleName](./$moduleName/README.md) - $($_.Name)"
} | Out-String)

## Documentation Statistics
- **Modules Processed**: $($stats.ModulesProcessed)
- **Functions Documented**: $($stats.FunctionsDocumented) 
- **Errors Encountered**: $($stats.Errors)

## Build Information
- **PlatyPS Version**: $(Get-Module PlatyPS | Select-Object -ExpandProperty Version)
- **PowerShell Version**: $($PSVersionTable.PSVersion)
- **Build Date**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')

## Usage
These documentation files are generated automatically from the PowerShell module source files.
To regenerate this documentation, run:

``````powershell
.\docs\ps\Build-PlatyPS.ps1 -Force
``````
"@
    
    $mainIndexContent | Out-File -FilePath (Join-Path $OutputPath "README.md") -Encoding UTF8
    
    # Generate summary report
    Write-DocLog "" "INFO"
    Write-DocLog "📊 PowerShell Documentation Build Summary:" "SUCCESS"
    Write-DocLog "   Modules Processed: $($stats.ModulesProcessed)" "INFO"
    Write-DocLog "   Functions Documented: $($stats.FunctionsDocumented)" "INFO"
    Write-DocLog "   Errors: $($stats.Errors)" "INFO"
    Write-DocLog "   Output Directory: $OutputPath" "INFO"
    
    if ($stats.Errors -eq 0) {
        Write-DocLog "🎉 PowerShell documentation generation completed successfully!" "SUCCESS"
    } else {
        Write-DocLog "⚠️ Documentation generation completed with $($stats.Errors) errors" "WARN"
    }
    
    # Create build manifest
    $manifest = @{
        BuildDate = Get-Date -Format 'o'
        ModulesProcessed = $stats.ModulesProcessed
        FunctionsDocumented = $stats.FunctionsDocumented
        Errors = $stats.Errors
        PlatyPSVersion = (Get-Module PlatyPS).Version.ToString()
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        OutputPath = $OutputPath.Path
    }
    
    $manifest | ConvertTo-Json -Depth 2 | Out-File -FilePath (Join-Path $OutputPath "build-manifest.json") -Encoding UTF8
    Write-DocLog "Build manifest saved to build-manifest.json" "INFO"
}
catch {
    Write-DocLog "💥 Fatal error during PowerShell documentation generation: $($_.Exception.Message)" "ERROR"
    Write-DocLog "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}