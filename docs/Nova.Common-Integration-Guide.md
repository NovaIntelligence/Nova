# Nova.Common Integration Guide

## Overview

This guide provides step-by-step instructions for migrating existing Nova Bot modules to use the centralized Nova.Common utilities, along with best practices and examples.

## Migration Strategy

### 1. Assessment Phase

Before migrating a module, identify opportunities for Nova.Common integration:

```powershell
# Search for duplicate logging patterns
grep -r "Write-Host.*ForegroundColor" your-module.ps1

# Find path operations that could be centralized
grep -r "Test-Path.*New-Item" your-module.ps1

# Locate custom retry logic
grep -r "for.*retry\|while.*attempt" your-module.ps1
```

### 2. Import Nova.Common

Add the import statement at the top of your module:

```powershell
# For modules in Nova Bot framework
Import-Module (Join-Path $PSScriptRoot "..\modules\Nova.Common\Nova.Common.psm1") -Force

# For external scripts
$NovaCommonPath = "D:\Nova\modules\Nova.Common\Nova.Common.psm1"
if (Test-Path $NovaCommonPath) {
    Import-Module $NovaCommonPath -Force
}
```

### 3. Migration Patterns

#### **Replace Custom Logging**

**Before:**
```powershell
function Write-CustomLog {
    param([string]$Message, [string]$Level = "Info")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colorMap = @{"Info"="White"; "Warning"="Yellow"; "Error"="Red"}
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colorMap[$Level]
}
```

**After:**
```powershell
# Simply use Nova.Common
Write-NovaLog -Level "INFO" -Message $Message -Context "YourModule"
```

#### **Replace Path Validation**

**Before:**
```powershell
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
}
```

**After:**
```powershell
$LogDir = Confirm-DirectoryPath -Path $LogDir
```

#### **Replace Input Validation**

**Before:**
```powershell
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "ApiKey parameter cannot be null or empty"
}
```

**After:**
```powershell
Guard-NotNull -Value $ApiKey -ParameterName "ApiKey"
```

#### **Replace Retry Logic**

**Before:**
```powershell
$maxAttempts = 3
$attempt = 0
$success = $false

while (-not $success -and $attempt -lt $maxAttempts) {
    try {
        $attempt++
        $result = Invoke-RestMethod -Uri $endpoint
        $success = $true
    } catch {
        if ($attempt -ge $maxAttempts) { throw }
        Start-Sleep -Seconds (2 * $attempt)
    }
}
```

**After:**
```powershell
$result = Invoke-NovaRetry -ScriptBlock {
    Invoke-RestMethod -Uri $endpoint
} -MaxAttempts 3 -DelaySeconds 2
```

## Best Practices

### 1. Gradual Migration

Don't migrate everything at once. Start with:
1. **Logging functions** - highest impact, lowest risk
2. **Path operations** - common source of bugs
3. **Input validation** - improves reliability
4. **Retry logic** - last, as it may require testing

### 2. Backward Compatibility

Maintain backward compatibility during migration:

```powershell
# Use Nova.Common if available, fallback to local implementation
if (Get-Command Write-NovaLog -ErrorAction SilentlyContinue) {
    Write-NovaLog -Level "INFO" -Message $msg
} else {
    Write-Host $msg -ForegroundColor Green
}
```

### 3. Context Usage

Always provide meaningful context for logging:

```powershell
# Good - specific context helps debugging
Write-NovaLog -Level "ERROR" -Message "API call failed" -Context "ModelPromotion"

# Better - include relevant details
Write-NovaLog -Level "ERROR" -Message "API call failed: $($_.Exception.Message)" -Context "ModelPromotion-Deploy"
```

### 4. Error Handling

Combine Nova.Common functions with proper error handling:

```powershell
try {
    Guard-NotNull -Value $ConfigPath -ParameterName "ConfigPath"
    $configDir = Confirm-DirectoryPath -Path (Split-Path $ConfigPath -Parent)
    
    $config = Invoke-NovaRetry -ScriptBlock {
        Get-Content $ConfigPath | ConvertFrom-Json
    } -MaxAttempts 2
    
    Write-NovaLog -Level "SUCCESS" -Message "Configuration loaded successfully" -Context "Startup"
} catch {
    Write-NovaLog -Level "ERROR" -Message "Failed to load configuration: $($_.Exception.Message)" -Context "Startup"
    throw
}
```

## Migration Checklist

### Pre-Migration
- [ ] Identify duplicate code patterns in your module
- [ ] Review existing error handling and logging
- [ ] Plan migration phases (start with low-risk items)
- [ ] Backup current module

### During Migration
- [ ] Import Nova.Common module
- [ ] Replace logging functions with `Write-NovaLog`
- [ ] Replace path operations with `Test-NovaPath` and `Confirm-DirectoryPath`
- [ ] Replace input validation with `Guard-*` functions
- [ ] Add meaningful context to all logging calls
- [ ] Test each change incrementally

### Post-Migration
- [ ] Run existing tests to ensure compatibility
- [ ] Update module documentation
- [ ] Remove obsolete custom functions
- [ ] Add integration tests for Nova.Common usage
- [ ] Monitor logs for any issues

## Common Migration Scenarios

### Test Scripts

```powershell
# Before
Write-Host "✅ PASS: $TestName" -ForegroundColor Green
Write-Host "❌ FAIL: $TestName" -ForegroundColor Red

# After  
Write-NovaLog -Level "SUCCESS" -Message "PASS: $TestName" -Context "Testing"
Write-NovaLog -Level "ERROR" -Message "FAIL: $TestName" -Context "Testing"
```

### Deployment Scripts

```powershell
# Before
if (-not (Test-Path $DeployDir)) {
    New-Item -ItemType Directory -Force -Path $DeployDir | Out-Null
}
Write-Host "Deploying to $DeployDir..." -ForegroundColor Cyan

# After
$DeployDir = Confirm-DirectoryPath -Path $DeployDir  
Write-NovaLog -Level "INFO" -Message "Deploying to $DeployDir..." -Context "Deployment"
```

### Configuration Loading

```powershell
# Before
if (-not (Test-Path $ConfigFile)) {
    throw "Configuration file not found: $ConfigFile"
}

# After
Guard-PathExists -Path $ConfigFile -PathType "File" -ParameterName "ConfigFile"
# or
if (-not (Test-NovaPath -Path $ConfigFile -Type "File")) {
    Write-NovaLog -Level "ERROR" -Message "Configuration file not found: $ConfigFile" -Context "Config"
    throw "Configuration file not found"
}
```

## Performance Considerations

Nova.Common functions are optimized for performance:
- **Write-NovaLog**: Async file operations, minimal overhead
- **Path functions**: Cached results where appropriate
- **Retry logic**: Exponential backoff prevents resource waste
- **Validation**: Early exit on success cases

## Troubleshooting

### Module Import Issues

```powershell
# Debug module loading
$NovaCommonPath = Join-Path $PSScriptRoot "..\modules\Nova.Common\Nova.Common.psm1"
Write-Host "Checking Nova.Common at: $NovaCommonPath"
Write-Host "Path exists: $(Test-Path $NovaCommonPath)"

if (Test-Path $NovaCommonPath) {
    Import-Module $NovaCommonPath -Force -Verbose
} else {
    Write-Warning "Nova.Common not found - using fallback methods"
}
```

### Function Not Available

```powershell
# Check if function is loaded
if (Get-Command Write-NovaLog -ErrorAction SilentlyContinue) {
    Write-Host "Nova.Common loaded successfully"
    Get-Command -Module Nova.Common
} else {
    Write-Host "Nova.Common not loaded"
}
```

## Examples Repository

Find complete migration examples in the `examples/` directory:
- `examples/migration/before-after-logging.ps1`
- `examples/migration/before-after-validation.ps1` 
- `examples/migration/before-after-retry.ps1`

## Support

For migration assistance:
1. Review the [Nova.Common README](../modules/Nova.Common/README.md)
2. Check the [test examples](../modules/Nova.Common/Tests/Nova.Common.Tests.ps1)
3. Open an issue for complex migration scenarios

---

*This guide helps ensure consistent, maintainable code across the Nova Bot framework through effective use of Nova.Common utilities.*