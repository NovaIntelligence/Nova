# Nova.Common Module

A centralized PowerShell module containing shared utility functions used across Nova Bot components.

## Overview

Nova.Common provides consistent, reusable functions for:
- **Logging**: Standardized logging with fallback mechanisms
- **Path Management**: Directory validation and Nova-specific path resolution  
- **Data Validation**: Guard clauses and argument validation
- **DateTime Handling**: Consistent datetime formatting across formats
- **Output Formatting**: Standardized data presentation (tables, JSON, etc.)
- **Retry Logic**: Robust retry patterns with configurable backoff

## Installation

The module is automatically available when Nova Bot is installed. To manually import:

```powershell
Import-Module "D:\Nova\modules\Nova.Common\Nova.Common.psm1"
```

## Public Functions

### Write-NovaLog
Centralized logging with automatic fallback to console output.

```powershell
Write-NovaLog -Level "Info" -Message "Operation completed" -Component "MyModule"
Write-NovaLog -Level "Error" -Message "Failed to process" -Component "MyModule" -ErrorRecord $_
```

### Confirm-DirectoryPath
Ensures directories exist, creating them if necessary.

```powershell
Confirm-DirectoryPath -Path "D:\Nova\data\exports"
Confirm-DirectoryPath -Path $configDir -ErrorAction Stop
```

### Test-NovaPath
Enhanced path validation with type checking.

```powershell
if (Test-NovaPath -Path $inputFile -Type "File") {
    # Process file
}

$isValidDir = Test-NovaPath -Path $dataDir -Type "Directory" -MustExist
```

### Guard-Arguments
Comprehensive argument validation functions.

```powershell
# Null checks
Guard-NotNull -Value $config -Name "Configuration"

# Empty string validation  
Guard-NotEmpty -Value $apiKey -Name "ApiKey"

# Range validation
Guard-Range -Value $timeout -Min 1 -Max 300 -Name "TimeoutSeconds"

# Path validation
Guard-Path -Value $logFile -Name "LogFile" -Type "File"
```

### Get-NovaModulePath
Standardized path resolution for Nova Bot directories.

```powershell
$dataDir = Get-NovaModulePath -Type "Data" -ModuleName "Skills"
$logsDir = Get-NovaModulePath -Type "Logs" 
$configFile = Get-NovaModulePath -Type "Config" -ModuleName "Metrics"
```

### Convert-NovaDateTime
Consistent datetime formatting across Nova Bot.

```powershell
$timestamp = Convert-NovaDateTime -DateTime (Get-Date) -Format "Timestamp"  # 20251024_143022
$display = Convert-NovaDateTime -DateTime $date -Format "Display"          # 01/24/2025 14:30:22
$filename = Convert-NovaDateTime -DateTime $date -Format "Filename"        # 2025-01-24_14-30-22
```

### Format-NovaOutput
Standardized data presentation with multiple formats.

```powershell
$results | Format-NovaOutput -Format "Table" -Properties "Name", "Status"
$data | Format-NovaOutput -Format "JSON" -Title "API Response"
$items | Format-NovaOutput -Format "Summary"
```

### Invoke-NovaRetry
Robust retry logic with configurable strategies.

```powershell
$result = Invoke-NovaRetry -ScriptBlock { 
    Get-WebContent -Url $apiUrl 
} -MaxRetries 3 -DelaySeconds 2 -ExponentialBackoff

# Retry only specific errors
Invoke-NovaRetry -ScriptBlock { 
    Test-Connection $server 
} -RetryOn @("TimeoutException", "NetworkException")
```

## Architecture

### Module Structure
```
Nova.Common/
├── Nova.Common.psm1          # Main module file
├── Public/                   # Public functions (exported)
│   ├── Write-NovaLog.ps1
│   ├── Confirm-DirectoryPath.ps1  
│   ├── Test-NovaPath.ps1
│   ├── Guard-Arguments.ps1
│   ├── Get-NovaModulePath.ps1
│   ├── Convert-NovaDateTime.ps1
│   ├── Format-NovaOutput.ps1
│   └── Invoke-NovaRetry.ps1
├── Private/                  # Internal helpers (not exported)
│   └── CommonHelpers.ps1
└── Tests/                    # Pester test suite
    └── Nova.Common.Tests.ps1
```

### Design Principles

1. **Consistency**: All functions follow Nova Bot naming and parameter conventions
2. **Resilience**: Comprehensive error handling with graceful fallbacks
3. **Flexibility**: Configurable behavior through parameters
4. **Performance**: Efficient implementations with minimal overhead
5. **Testing**: Full test coverage with Pester v5

## Usage Examples

### Basic Logging Setup
```powershell
Import-Module Nova.Common

# Simple logging
Write-NovaLog -Level "Info" -Message "Starting operation" -Component "DataProcessor"

# Error logging with details
try {
    # Some operation
} catch {
    Write-NovaLog -Level "Error" -Message "Processing failed" -Component "DataProcessor" -ErrorRecord $_
}
```

### Path Management
```powershell
# Ensure required directories exist
$dataDir = Get-NovaModulePath -Type "Data" -ModuleName "Reports"
Confirm-DirectoryPath -Path $dataDir

# Validate input paths
Guard-Path -Value $inputFile -Name "InputFile" -Type "File" -MustExist

if (Test-NovaPath -Path $outputDir -Type "Directory") {
    # Safe to write files
}
```

### Robust Operations
```powershell
# API call with retry logic
$response = Invoke-NovaRetry -ScriptBlock {
    Invoke-RestMethod -Uri $apiUrl -Headers $headers
} -MaxRetries 5 -ExponentialBackoff

# Format and display results
$response.data | Format-NovaOutput -Format "Table" -Title "API Results"
```

## Integration

### Module Dependencies
Nova.Common is designed to be dependency-free and can be imported into any PowerShell session. It provides the foundation for other Nova Bot modules:

- **Nova.Skills** - Uses logging, path management, and validation
- **Nova.Metrics** - Uses datetime formatting and output formatting  
- **Nova.StateMachine** - Uses retry logic and guard clauses

### Backward Compatibility
Functions maintain backward compatibility through:
- Parameter validation with sensible defaults
- Graceful fallbacks for missing dependencies
- Console output when logging subsystems are unavailable

## Testing

Run the complete test suite:

```powershell
cd "D:\Nova\modules\Nova.Common\Tests"
Invoke-Pester -Path "Nova.Common.Tests.ps1" -Output Detailed
```

## Contributing

When adding new shared utilities:

1. **Public Functions**: Place in `Public/` folder with proper documentation
2. **Private Helpers**: Place in `Private/` folder for internal use
3. **Tests**: Add comprehensive tests to `Tests/Nova.Common.Tests.ps1`
4. **Documentation**: Update this README with usage examples

### Function Guidelines

```powershell
function Verb-NovaNoun {
    <#
    .SYNOPSIS
    Brief description
    
    .DESCRIPTION  
    Detailed description of functionality
    
    .PARAMETER ParamName
    Parameter description
    
    .OUTPUTS
    Output description
    
    .EXAMPLE
    Usage example with expected output
    #>
    param(
        [Parameter(Mandatory)]
        [string]$RequiredParam,
        
        [Parameter()]
        [string]$OptionalParam = "Default"
    )
    
    # Implementation with error handling
    try {
        # Logic here
    }
    catch {
        Write-NovaLog -Level "Error" -Message "Operation failed: $($_.Exception.Message)" -Component "Nova.Common"
        throw
    }
}
```

## Version History

- **v1.0.0** - Initial release with core utility functions
- **v1.1.0** - Added retry logic and enhanced datetime formatting  
- **v1.2.0** - Improved output formatting with multiple format support