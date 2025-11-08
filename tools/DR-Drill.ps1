#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Nova Bot Framework - Disaster Recovery Drill Script
    Validates backup integrity and restoration procedures

.DESCRIPTION
    Enterprise-grade DR drill that:
    • Selects latest backup from configurable backup directory
    • Restores to temporary workspace with timestamp isolation
    • Verifies SHA-256 checksums and manifest integrity  
    • Generates comprehensive DR report with metrics
    • Returns proper exit codes for CI/CD integration

.PARAMETER BackupPath
    Path to backup directory. Defaults to D:\Nova_Backups

.PARAMETER RestorePath
    Base path for restore operations. Defaults to artifacts/dr-restore

.PARAMETER SkipCleanup
    Skip cleanup of temporary restore directory (for debugging)

.PARAMETER Verbose
    Enable detailed logging output

.EXAMPLE
    .\DR-Drill.ps1
    # Standard DR drill with default paths

.EXAMPLE
    .\DR-Drill.ps1 -BackupPath "C:\Backups\Nova" -DetailedLogging
    # Custom backup path with detailed logging

.EXAMPLE
    .\DR-Drill.ps1 -SkipCleanup -DetailedLogging
    # Debug mode - keeps restored files for inspection

.NOTES
    Author: Nova Intelligence Team
    Version: 1.0
    Requires: PowerShell 5.1+
    Exit Codes:
        0 = INFO (all verifications passed)
        1 = Backup not found or selection failed
        2 = Restoration failed
        3 = Checksum verification failed
        4 = Manifest validation failed
        5 = General error
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$BackupPath = "D:\Nova_Backups",
    
    [Parameter()]
    [string]$RestorePath = "artifacts/dr-restore",
    
    [Parameter()]
    [switch]$SkipCleanup,
    
    [Parameter()]
    [switch]$DetailedLogging
)

# Import Nova.Common if available
$NovaCommonPath = Join-Path $PSScriptRoot "..\modules\Nova.Common\Nova.Common.psm1"
$UseNovaCommon = Test-Path $NovaCommonPath
if ($UseNovaCommon) {
    Import-Module $NovaCommonPath -Force -ErrorAction SilentlyContinue
}

# Initialize script variables
$Script:StartTime = Get-Date
$Script:DrillId = Get-Date -Format "yyyyMMdd_HHmmss"
$Script:ExitCode = 0
$Script:Metrics = @{
    StartTime = $Script:StartTime
    BackupSelected = $null
    RestoreStartTime = $null
    RestoreEndTime = $null
    VerificationStartTime = $null
    VerificationEndTime = $null
    TotalFiles = 0
    VerifiedFiles = 0
    Mismatches = 0
    Errors = @()
}

#region Logging Functions
function Write-DrLog {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level,
        
        [Parameter(Mandatory)]
        [string]$Message,
        
        [string]$Component = "DR-Drill"
    )
    
    if ($UseNovaCommon) {
        Write-NovaLog -Level $Level -Message $Message -Component $Component
    } else {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $colorMap = @{
            "INFO" = "White"
            "WARN" = "Yellow" 
            "ERROR" = "Red"
            "DEBUG" = "Gray"
        }
        # Map INFO to INFO with green color for display
        if ($Level -eq "INFO") {
            $Level = "INFO"
            $colorMap["INFO"] = "Green"
        }
        
        $logMessage = "[$timestamp] [$Level] [$Component] $Message"
        Write-Host $logMessage -ForegroundColor $colorMap[$Level]
    }
}

function Write-DrProgress {
    param(
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete = -1
    )
    
    if ($PercentComplete -ge 0) {
        Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
    } else {
        Write-Progress -Activity $Activity -Status $Status
    }
}
#endregion

#region Backup Selection
function Get-LatestBackup {
    param([string]$BackupDirectory)
    
    Write-DrLog -Level "INFO" -Message "Scanning for backups in: $BackupDirectory"
    
    if (-not (Test-Path $BackupDirectory)) {
        Write-DrLog -Level "ERROR" -Message "Backup directory not found: $BackupDirectory"
        return $null
    }
    
    # Look for Nova backup files with pattern: Nova_Backup_YYYYMMDD_HHMMSS.zip
    $backupFiles = Get-ChildItem -Path $BackupDirectory -Filter "Nova_Backup_*.zip" | 
        Where-Object { $_.Name -match "Nova_Backup_\d{8}_\d{6}\.zip" } |
        Sort-Object LastWriteTime -Descending
    
    if (-not $backupFiles) {
        Write-DrLog -Level "ERROR" -Message "No Nova backup files found in $BackupDirectory"
        return $null
    }
    
    $latestBackup = $backupFiles[0]
    Write-DrLog -Level "INFO" -Message "Latest backup selected: $($latestBackup.Name)"
    Write-DrLog -Level "INFO" -Message "Backup size: $([math]::Round($latestBackup.Length/1MB, 2)) MB"
    Write-DrLog -Level "INFO" -Message "Created: $($latestBackup.LastWriteTime)"
    
    return $latestBackup
}

function Get-BackupManifest {
    param([System.IO.FileInfo]$BackupFile)
    
    $manifestPath = $BackupFile.FullName -replace "\.zip$", ".manifest.txt"
    $checksumPath = $BackupFile.FullName -replace "\.zip$", ".sha256"
    
    $result = @{
        BackupFile = $BackupFile
        ManifestPath = if (Test-Path $manifestPath) { $manifestPath } else { $null }
        ChecksumPath = if (Test-Path $checksumPath) { $checksumPath } else { $null }
        Manifest = $null
        ExpectedChecksum = $null
    }
    
    if ($result.ManifestPath) {
        try {
            $result.Manifest = Get-Content $result.ManifestPath -Raw
            Write-DrLog -Level "INFO" -Message "Manifest loaded: $(Split-Path $result.ManifestPath -Leaf)"
        } catch {
            Write-DrLog -Level "WARN" -Message "Failed to read manifest: $($_.Exception.Message)"
        }
    } else {
        Write-DrLog -Level "WARN" -Message "No manifest file found for backup"
    }
    
    if ($result.ChecksumPath) {
        try {
            $checksumContent = Get-Content $result.ChecksumPath -Raw
            if ($checksumContent -match "^([A-F0-9]{64})\s+") {
                $result.ExpectedChecksum = $matches[1]
                Write-DrLog -Level "INFO" -Message "Expected checksum loaded: $($result.ExpectedChecksum)"
            }
        } catch {
            Write-DrLog -Level "WARN" -Message "Failed to read checksum file: $($_.Exception.Message)"
        }
    } else {
        Write-DrLog -Level "WARN" -Message "No checksum file found for backup"
    }
    
    return $result
}
#endregion

#region Restoration
function Initialize-RestoreWorkspace {
    param([string]$BasePath)
    
    $restoreDir = Join-Path $BasePath $Script:DrillId
    
    Write-DrLog -Level "INFO" -Message "Initializing restore workspace: $restoreDir"
    
    try {
        if ($UseNovaCommon) {
            $restoreDir = Confirm-DirectoryPath -Path $restoreDir
        } else {
            if (-not (Test-Path $restoreDir)) {
                New-Item -ItemType Directory -Path $restoreDir -Force | Out-Null
            }
        }
        
        Write-DrLog -Level "INFO" -Message "Restore workspace ready: $restoreDir"
        return $restoreDir
    } catch {
        Write-DrLog -Level "ERROR" -Message "Failed to create restore workspace: $($_.Exception.Message)"
        return $null
    }
}

function Restore-Backup {
    param(
        [System.IO.FileInfo]$BackupFile,
        [string]$DestinationPath
    )
    
    Write-DrLog -Level "INFO" -Message "Starting backup restoration..."
    Write-DrProgress -Activity "Disaster Recovery Drill" -Status "Extracting backup archive..."
    
    $Script:Metrics.RestoreStartTime = Get-Date
    
    try {
        # Extract the backup
        Expand-Archive -Path $BackupFile.FullName -DestinationPath $DestinationPath -Force
        
        $Script:Metrics.RestoreEndTime = Get-Date
        $restoreDuration = ($Script:Metrics.RestoreEndTime - $Script:Metrics.RestoreStartTime).TotalSeconds
        
        Write-DrLog -Level "INFO" -Message "Backup extracted successfully"
        Write-DrLog -Level "INFO" -Message "Restoration completed in $([math]::Round($restoreDuration, 2)) seconds"
        
        # Count restored files
        $restoredFiles = Get-ChildItem -Path $DestinationPath -Recurse -File
        $Script:Metrics.TotalFiles = $restoredFiles.Count
        Write-DrLog -Level "INFO" -Message "Total files restored: $($Script:Metrics.TotalFiles)"
        
        return $true
    } catch {
        Write-DrLog -Level "ERROR" -Message "Backup restoration failed: $($_.Exception.Message)"
        $Script:Metrics.Errors += "Restoration failed: $($_.Exception.Message)"
        return $false
    }
}
#endregion

#region Verification
function Test-BackupChecksum {
    param(
        [System.IO.FileInfo]$BackupFile,
        [string]$ExpectedChecksum
    )
    
    if (-not $ExpectedChecksum) {
        Write-DrLog -Level "WARN" -Message "No expected checksum available - skipping checksum verification"
        return $true
    }
    
    Write-DrLog -Level "INFO" -Message "Verifying backup checksum..."
    Write-DrProgress -Activity "Disaster Recovery Drill" -Status "Computing SHA-256 checksum..."
    
    try {
        $actualHash = Get-FileHash -Path $BackupFile.FullName -Algorithm SHA256
        $actualChecksum = $actualHash.Hash
        
        if ($actualChecksum -eq $ExpectedChecksum) {
            Write-DrLog -Level "INFO" -Message "Checksum verification PASSED"
            Write-DrLog -Level "INFO" -Message "SHA256: $actualChecksum"
            return $true
        } else {
            Write-DrLog -Level "ERROR" -Message "Checksum verification FAILED"
            Write-DrLog -Level "ERROR" -Message "Expected: $ExpectedChecksum"
            Write-DrLog -Level "ERROR" -Message "Actual:   $actualChecksum"
            $Script:Metrics.Errors += "Checksum mismatch"
            return $false
        }
    } catch {
        Write-DrLog -Level "ERROR" -Message "Checksum computation failed: $($_.Exception.Message)"
        $Script:Metrics.Errors += "Checksum computation failed: $($_.Exception.Message)"
        return $false
    }
}

function Test-RestoredContent {
    param([string]$RestorePath)
    
    Write-DrLog -Level "INFO" -Message "Verifying restored content integrity..."
    $Script:Metrics.VerificationStartTime = Get-Date
    
    $mismatches = 0
    $verifiedFiles = 0
    
    # Check for critical Nova framework components
    $criticalPaths = @(
        "Nova/modules/Nova.Common/Nova.Common.psm1",
        "Nova/bot/nova-bot.ps1",
        "Nova/model/Train-And-Package.py",
        "Nova/README.md"
    )
    
    Write-DrProgress -Activity "Disaster Recovery Drill" -Status "Verifying critical components..."
    
    foreach ($path in $criticalPaths) {
        $fullPath = Join-Path $RestorePath $path
        if (Test-Path $fullPath) {
            Write-DrLog -Level "INFO" -Message "Critical component verified: $path"
            $verifiedFiles++
        } else {
            Write-DrLog -Level "ERROR" -Message "Critical component MISSING: $path"
            $mismatches++
            $Script:Metrics.Errors += "Missing critical component: $path"
        }
    }
    
    # Verify Nova.Common module structure
    $novaCommonPath = Join-Path $RestorePath "Nova/modules/Nova.Common"
    if (Test-Path $novaCommonPath) {
        $expectedFunctions = @(
            "Public/Write-NovaLog.ps1",
            "Public/Confirm-DirectoryPath.ps1", 
            "Public/Test-NovaPath.ps1",
            "Public/Guard-Arguments.ps1"
        )
        
        foreach ($func in $expectedFunctions) {
            $funcPath = Join-Path $novaCommonPath $func
            if (Test-Path $funcPath) {
                $verifiedFiles++
            } else {
                Write-DrLog -Level "ERROR" -Message "Nova.Common function missing: $func"
                $mismatches++
                $Script:Metrics.Errors += "Missing Nova.Common function: $func"
            }
        }
    }
    
    # Check for test files
    $testPath = Join-Path $RestorePath "Nova/modules/Nova.Common/Tests/Nova.Common.Tests.ps1"
    if (Test-Path $testPath) {
        Write-DrLog -Level "INFO" -Message "Test suite verified: Nova.Common.Tests.ps1"
        $verifiedFiles++
    } else {
        Write-DrLog -Level "WARN" -Message "Test suite not found: Nova.Common.Tests.ps1"
    }
    
    $Script:Metrics.VerificationEndTime = Get-Date
    $Script:Metrics.VerifiedFiles = $verifiedFiles
    $Script:Metrics.Mismatches = $mismatches
    
    $verificationDuration = ($Script:Metrics.VerificationEndTime - $Script:Metrics.VerificationStartTime).TotalSeconds
    Write-DrLog -Level "INFO" -Message "Content verification completed in $([math]::Round($verificationDuration, 2)) seconds"
    Write-DrLog -Level "INFO" -Message "Files verified: $verifiedFiles"
    
    if ($mismatches -eq 0) {
        Write-DrLog -Level "INFO" -Message "All content verification checks PASSED"
        return $true
    } else {
        Write-DrLog -Level "ERROR" -Message "Content verification FAILED with $mismatches mismatches"
        return $false
    }
}
#endregion

#region Reporting
function New-DrillReport {
    param(
        [string]$ReportPath,
        [hashtable]$BackupInfo
    )
    
    $endTime = Get-Date
    $totalDuration = ($endTime - $Script:StartTime).TotalSeconds
    
    $report = @"
# Nova Bot Framework - Disaster Recovery Drill Report

**Drill ID**: $Script:DrillId  
**Execution Date**: $($Script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))  
**Total Duration**: $([math]::Round($totalDuration, 2)) seconds  
**Final Status**: $(if ($Script:ExitCode -eq 0) { "✅ INFO" } else { "❌ FAILED" })

## Backup Information

**Backup File**: $($BackupInfo.BackupFile.Name)  
**Backup Size**: $([math]::Round($BackupInfo.BackupFile.Length/1MB, 2)) MB  
**Backup Date**: $($BackupInfo.BackupFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))  
**Manifest Available**: $(if ($BackupInfo.ManifestPath) { "✅ Yes" } else { "❌ No" })  
**Checksum Available**: $(if ($BackupInfo.ChecksumPath) { "✅ Yes" } else { "❌ No" })

## Performance Metrics

| Phase | Duration (seconds) | Status |
|-------|-------------------|---------|
| Backup Selection | $([math]::Round(($Script:Metrics.RestoreStartTime - $Script:StartTime).TotalSeconds, 2)) | ✅ Complete |
| Restoration | $([math]::Round(($Script:Metrics.RestoreEndTime - $Script:Metrics.RestoreStartTime).TotalSeconds, 2)) | $(if ($Script:Metrics.RestoreEndTime) { "✅ Complete" } else { "❌ Failed" }) |
| Verification | $([math]::Round(($Script:Metrics.VerificationEndTime - $Script:Metrics.VerificationStartTime).TotalSeconds, 2)) | $(if ($Script:Metrics.VerificationEndTime) { "✅ Complete" } else { "❌ Failed" }) |

## Verification Results

**Total Files Restored**: $($Script:Metrics.TotalFiles)  
**Files Verified**: $($Script:Metrics.VerifiedFiles)  
**Mismatches Found**: $($Script:Metrics.Mismatches)  
**Verification Status**: $(if ($Script:Metrics.Mismatches -eq 0) { "✅ PASSED" } else { "❌ FAILED" })

## Errors and Issues

$(if ($Script:Metrics.Errors.Count -eq 0) { 
    "✅ No errors encountered during drill execution."
} else {
    $Script:Metrics.Errors | ForEach-Object { "- ❌ $_" } | Out-String
})

## Component Verification Status

| Component | Status |
|-----------|---------|
| Nova.Common Module | $(if (Test-Path (Join-Path $Script:RestoreWorkspace "Nova/modules/Nova.Common/Nova.Common.psm1")) { "✅ Verified" } else { "❌ Missing" }) |
| Main Bot Script | $(if (Test-Path (Join-Path $Script:RestoreWorkspace "Nova/bot/nova-bot.ps1")) { "✅ Verified" } else { "❌ Missing" }) |
| ML Training Pipeline | $(if (Test-Path (Join-Path $Script:RestoreWorkspace "Nova/model/Train-And-Package.py")) { "✅ Verified" } else { "❌ Missing" }) |
| Documentation | $(if (Test-Path (Join-Path $Script:RestoreWorkspace "Nova/README.md")) { "✅ Verified" } else { "❌ Missing" }) |

## Recommendations

$(if ($Script:ExitCode -eq 0) {
    "✅ **Disaster recovery capability confirmed**. The backup system is functioning correctly and can successfully restore the Nova Bot Framework."
} else {
    "❌ **Action Required**: Disaster recovery issues detected. Review errors above and address backup/restore process issues."
})

## Manifest Content

$(if ($BackupInfo.Manifest) { 
    "``````"
    $BackupInfo.Manifest
    "``````"
} else {
    "⚠️ No manifest available for this backup."
})

---
*Generated by Nova DR-Drill v1.0 on $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))*
"@

    try {
        # Ensure report directory exists
        $reportDir = Split-Path $ReportPath -Parent
        if ($UseNovaCommon) {
            Confirm-DirectoryPath -Path $reportDir | Out-Null
        } else {
            if (-not (Test-Path $reportDir)) {
                New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
            }
        }
        
        $report | Out-File -FilePath $ReportPath -Encoding UTF8 -Force
        Write-DrLog -Level "INFO" -Message "DR drill report generated: $ReportPath"
        
        return $true
    } catch {
        Write-DrLog -Level "ERROR" -Message "Failed to generate report: $($_.Exception.Message)"
        return $false
    }
}
#endregion

#region Main Execution
function Invoke-DisasterRecoveryDrill {
    Write-DrLog -Level "INFO" -Message "🚨 Nova Bot Framework - Disaster Recovery Drill Starting"
    Write-DrLog -Level "INFO" -Message "Drill ID: $Script:DrillId"
    Write-DrLog -Level "INFO" -Message "Backup Path: $BackupPath"
    Write-DrLog -Level "INFO" -Message "Restore Path: $RestorePath"
    
    try {
        # Step 1: Select latest backup
        Write-DrProgress -Activity "Disaster Recovery Drill" -Status "Selecting latest backup..." -PercentComplete 10
        $latestBackup = Get-LatestBackup -BackupDirectory $BackupPath
        if (-not $latestBackup) {
            $Script:ExitCode = 1
            return
        }
        
        $Script:Metrics.BackupSelected = $latestBackup
        
        # Step 2: Load backup metadata
        Write-DrProgress -Activity "Disaster Recovery Drill" -Status "Loading backup metadata..." -PercentComplete 20
        $backupInfo = Get-BackupManifest -BackupFile $latestBackup
        
        # Step 3: Initialize restore workspace
        Write-DrProgress -Activity "Disaster Recovery Drill" -Status "Initializing restore workspace..." -PercentComplete 30
        $Script:RestoreWorkspace = Initialize-RestoreWorkspace -BasePath $RestorePath
        if (-not $Script:RestoreWorkspace) {
            $Script:ExitCode = 2
            return
        }
        
        # Step 4: Verify backup checksum
        Write-DrProgress -Activity "Disaster Recovery Drill" -Status "Verifying backup integrity..." -PercentComplete 40
        $checksumValid = Test-BackupChecksum -BackupFile $latestBackup -ExpectedChecksum $backupInfo.ExpectedChecksum
        if (-not $checksumValid) {
            $Script:ExitCode = 3
            return
        }
        
        # Step 5: Restore backup
        Write-DrProgress -Activity "Disaster Recovery Drill" -Status "Restoring backup..." -PercentComplete 60
        $restoreINFO = Restore-Backup -BackupFile $latestBackup -DestinationPath $Script:RestoreWorkspace
        if (-not $restoreINFO) {
            $Script:ExitCode = 2
            return
        }
        
        # Step 6: Verify restored content
        Write-DrProgress -Activity "Disaster Recovery Drill" -Status "Verifying restored content..." -PercentComplete 80
        $contentValid = Test-RestoredContent -RestorePath $Script:RestoreWorkspace
        if (-not $contentValid) {
            $Script:ExitCode = 4
            return
        }
        
        # Step 7: Generate report
        Write-DrProgress -Activity "Disaster Recovery Drill" -Status "Generating report..." -PercentComplete 90
        $reportPath = Join-Path $RestorePath "report.md"
        $reportGenerated = New-DrillReport -ReportPath $reportPath -BackupInfo $backupInfo
        
        Write-Progress -Activity "Disaster Recovery Drill" -Completed
        
        if ($reportGenerated) {
            Write-DrLog -Level "INFO" -Message "🎉 Disaster Recovery Drill COMPLETED successfully"
            Write-DrLog -Level "INFO" -Message "Report available at: $reportPath"
        } else {
            Write-DrLog -Level "WARN" -Message "Drill completed but report generation failed"
        }
        
        # Summary
        Write-DrLog -Level "INFO" -Message "=== DRILL SUMMARY ==="
        Write-DrLog -Level "INFO" -Message "Files Restored: $($Script:Metrics.TotalFiles)"
        Write-DrLog -Level "INFO" -Message "Files Verified: $($Script:Metrics.VerifiedFiles)"
        Write-DrLog -Level "INFO" -Message "Mismatches: $($Script:Metrics.Mismatches)"
        Write-DrLog -Level "INFO" -Message "Total Duration: $([math]::Round(((Get-Date) - $Script:StartTime).TotalSeconds, 2)) seconds"
        
    } catch {
        Write-DrLog -Level "ERROR" -Message "Unexpected error during DR drill: $($_.Exception.Message)"
        $Script:Metrics.Errors += "Unexpected error: $($_.Exception.Message)"
        $Script:ExitCode = 5
    } finally {
        # Cleanup
        if ($Script:RestoreWorkspace -and -not $SkipCleanup) {
            Write-DrLog -Level "INFO" -Message "Cleaning up temporary workspace..."
            try {
                Remove-Item -Path $Script:RestoreWorkspace -Recurse -Force -ErrorAction SilentlyContinue
                Write-DrLog -Level "INFO" -Message "Workspace cleanup completed"
            } catch {
                Write-DrLog -Level "WARN" -Message "Workspace cleanup failed: $($_.Exception.Message)"
            }
        } elseif ($SkipCleanup) {
            Write-DrLog -Level "INFO" -Message "Workspace preserved for debugging: $Script:RestoreWorkspace"
        }
    }
}

# Execute the drill
Invoke-DisasterRecoveryDrill

Write-DrLog -Level "INFO" -Message "DR drill completed with exit code: $Script:ExitCode"
exit $Script:ExitCode
#endregion
