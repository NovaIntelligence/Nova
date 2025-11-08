# Pylance Clean Pack v1 - Universal Python Linting Cleanup
# Comprehensive fix for common Pylance warnings across Nova model files

$ErrorActionPreference = "Continue"

function Update-Text {
    param([string]$FilePath, [string]$Old, [string]$New)
    if (-not (Test-Path $FilePath)) { return }
    
    $content = Get-Content -Path $FilePath -Raw -Encoding UTF8
    if ($content -match [regex]::Escape($Old)) {
        Write-Host "Applying fix in $FilePath"
        $content = $content -replace [regex]::Escape($Old), $New
        [System.IO.File]::WriteAllText($FilePath, $content, [System.Text.Encoding]::UTF8)
    }
}

function Ensure-Once {
    param([string]$FilePath, [string]$Pattern, [string]$Insertion)
    if (-not (Test-Path $FilePath)) { return }
    
    $content = Get-Content -Path $FilePath -Raw -Encoding UTF8
    if (-not ($content -match $Pattern)) {
        Write-Host "Adding $Insertion to $FilePath"
        $content = $Insertion + "`n" + $content
        [System.IO.File]::WriteAllText($FilePath, $content, [System.Text.Encoding]::UTF8)
    }
}

function Fix-File {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        Write-Host "File not found: $FilePath"
        return
    }
    
    Write-Host "Processing: $FilePath"
    
    # Create backup
    $backupPath = $FilePath + ".bak"
    Copy-Item -Path $FilePath -Destination $backupPath -Force
    
    # Add typing imports if not present
    Ensure-Once -FilePath $FilePath -Pattern "from typing import" -Insertion "from typing import Any, Dict, List, Optional, Sequence, Mapping, Set, Tuple, Union, cast"
    
    # Add __future__ annotations
    Ensure-Once -FilePath $FilePath -Pattern "from __future__ import annotations" -Insertion "from __future__ import annotations"
    
    # Pydantic v2 migration: @validator -> @field_validator
    Update-Text -FilePath $FilePath -Old "@validator(" -New "@field_validator("
    Update-Text -FilePath $FilePath -Old "@validator(pre=True)" -New "@field_validator(mode=`"before`")"
    
    # Ensure FastAPI Request import for exception handlers
    if ((Get-Content -Path $FilePath -Raw) -match "HTTPException|exception_handler") {
        Ensure-Once -FilePath $FilePath -Pattern "from fastapi import.*Request" -Insertion "from fastapi import Request"
    }
    
    # Fix pandas imports
    Update-Text -FilePath $FilePath -Old "from pandas.io.common import StringIO" -New "from io import StringIO"
    Update-Text -FilePath $FilePath -Old "pandas.io.common.StringIO" -New "StringIO"
    
    # Fix potential null reference on .endswith()
    $content = Get-Content -Path $FilePath -Raw -Encoding UTF8
    $content = $content -replace "(\w+)\.endswith\(", 'if $1 and $1.endswith('
    [System.IO.File]::WriteAllText($FilePath, $content, [System.Text.Encoding]::UTF8)
    
    Write-Host "Completed: $FilePath (backup: $backupPath)"
}

# Target files to fix
$targetFiles = @(
    "D:\Nova\bot\model\serve.py",
    "D:\Nova\bot\model\Train-And-Package.py", 
    "D:\Nova\model\serve.py",
    "D:\Nova\model\example.py"
)

Write-Host "Starting Pylance Clean Pack v1..."
Write-Host "Target files: $($targetFiles.Count)"

foreach ($file in $targetFiles) {
    Fix-File -FilePath $file
}

Write-Host ""
Write-Host "Pylance Clean Pack v1 completed!"
Write-Host "Please reload VS Code to see the resolved warnings."
Write-Host "Backup files created with .bak extension for safety."