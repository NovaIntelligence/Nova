#Requires -Version 5.1

<#
.SYNOPSIS
Nova.Common - Shared utilities for Nova Bot Framework

.DESCRIPTION
Provides common functionality used across Nova Bot modules including:
- Centralized logging shims and helpers
- Path utilities and directory management
- Guard clauses and validation helpers
- File system operations with consistent error handling

.NOTES
Creators: Tyler McKendry & Nova
Version: 1.0.0
PowerShell: 5.1+

This module follows the Public/Private folder structure for clear API boundaries.
Public functions are exported and available to consumers.
Private functions are internal implementation details.
#>

# Dot source public and private functions
$PublicPath = Join-Path $PSScriptRoot "Public"
$PrivatePath = Join-Path $PSScriptRoot "Private"

$PublicFunctions = @()
$PrivateFunctions = @()

# Load private functions first (dependencies)
if (Test-Path $PrivatePath) {
    $PrivateFiles = Get-ChildItem -Path $PrivatePath -Filter "*.ps1" -ErrorAction SilentlyContinue
    foreach ($File in $PrivateFiles) {
        try {
            . $File.FullName
            $PrivateFunctions += $File.BaseName
        }
        catch {
            Write-Error "Failed to import private function $($File.Name): $($_.Exception.Message)"
        }
    }
}

# Load public functions
if (Test-Path $PublicPath) {
    $PublicFiles = Get-ChildItem -Path $PublicPath -Filter "*.ps1" -ErrorAction SilentlyContinue
    foreach ($File in $PublicFiles) {
        try {
            # Store functions before sourcing to detect new ones
            $FunctionsBefore = Get-Command -CommandType Function | Select-Object -ExpandProperty Name
            
            . $File.FullName
            
            # Detect newly loaded functions
            $FunctionsAfter = Get-Command -CommandType Function | Select-Object -ExpandProperty Name
            $NewFunctions = Compare-Object $FunctionsBefore $FunctionsAfter | Where-Object { $_.SideIndicator -eq '=>' } | Select-Object -ExpandProperty InputObject
            
            if ($NewFunctions) {
                $PublicFunctions += $NewFunctions
            }
        }
        catch {
            Write-Error "Failed to import public function $($File.Name): $($_.Exception.Message)"
        }
    }
}

# Export only public functions
if ($PublicFunctions.Count -gt 0) {
    Export-ModuleMember -Function $PublicFunctions
}

# Module initialization
Write-Verbose "Nova.Common module loaded. Public functions: $($PublicFunctions.Count), Private functions: $($PrivateFunctions.Count)"