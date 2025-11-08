# Pylance Clean Pack v3 - Targeted Fix for Remaining Errors
# Focus on the specific issues in D:\Nova\model\Train-And-Package.py

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

function Apply-Targeted-Fixes {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        Write-Host "File not found: $FilePath"
        return
    }
    
    Write-Host "Applying targeted fixes to: $FilePath"
    
    # Create backup
    $backupPath = $FilePath + ".v3.bak"
    Copy-Item -Path $FilePath -Destination $backupPath -Force
    
    $content = Get-Content -Path $FilePath -Raw -Encoding UTF8
    
    # Fix constant redefinition issue
    $content = $content -replace "LIGHTGBM_AVAILABLE = False", "_lightgbm_available = False"
    $content = $content -replace "XGBOOST_AVAILABLE = False", "_xgboost_available = False"
    $content = $content -replace "LIGHTGBM_AVAILABLE = True", "_lightgbm_available = True"
    $content = $content -replace "XGBOOST_AVAILABLE = True", "_xgboost_available = True"
    
    # Fix model_params typing
    $content = $content -replace "\*\*model_params\) -> None:", "**model_params: Any) -> None:"
    
    # Fix schema typing
    $content = $content -replace "self\.schema = \{\}", "self.schema: Dict[str, Any] = {}"
    
    # Add explicit typing for train_test_split results
    $trainTestSplitPattern = "X_train, X_val, y_train, y_val = train_test_split\("
    if ($content -match [regex]::Escape($trainTestSplitPattern)) {
        $replacement = @"
        # Type-annotated train_test_split results
        split_result = train_test_split(
"@
        $content = $content -replace [regex]::Escape($trainTestSplitPattern), $replacement
        
        # Add the unpacking with type annotations
        $content = $content -replace "(\s+)split_result = train_test_split\(.*?\)", @"
`$1split_result = train_test_split(
            X, y, test_size=0.2, random_state=42, stratify=y if self.task_type == 'classification' else None
        )
        X_train: pd.DataFrame = split_result[0]
        X_val: pd.DataFrame = split_result[1] 
        y_train: pd.Series = split_result[2]
        y_val: pd.Series = split_result[3]
"@
    }
    
    # Fix default_params typing
    $content = $content -replace "default_params = \{", "default_params: Dict[str, Any] = {"
    
    # Add proper model typing
    $content = $content -replace "self\.model = None", "self.model: Optional[Any] = None"
    
    # Fix ML library availability checks
    $content = $content -replace "if LIGHTGBM_AVAILABLE:", "if _lightgbm_available:"
    $content = $content -replace "if XGBOOST_AVAILABLE:", "if _xgboost_available:"
    
    # Add type ignores for ML library calls
    $content = $content -replace "lgb\.Dataset\(", "lgb.Dataset(  # type: ignore[attr-defined]"
    $content = $content -replace "lgb\.train\(", "lgb.train(  # type: ignore[attr-defined]"
    $content = $content -replace "xgb\.DMatrix\(", "xgb.DMatrix(  # type: ignore[attr-defined]"
    $content = $content -replace "xgb\.train\(", "xgb.train(  # type: ignore[attr-defined]"
    
    # Fix y_pred typing issues
    $content = $content -replace "y_pred = self\.model\.predict\(", "y_pred: Any = self.model.predict(  # type: ignore[union-attr]"
    
    # Fix prediction comparison 
    $content = $content -replace "y_pred_class = \(y_pred > 0\.5\)\.astype\(int\)", @"
y_pred_array = np.asarray(y_pred)
            y_pred_class = (y_pred_array > 0.5).astype(int)
"@
    
    # Add necessary imports at top
    $importsToAdd = @"
from __future__ import annotations
from typing import Any, Dict, List, Optional, Sequence, Mapping, Set, Tuple, Union, cast
import numpy as np

"@
    
    if ($content -notmatch "from __future__ import annotations") {
        $content = $importsToAdd + $content
    }
    
    [System.IO.File]::WriteAllText($FilePath, $content, [System.Text.Encoding]::UTF8)
    
    Write-Host "Completed targeted fixes: $FilePath (backup: $backupPath)"
}

# Target the problematic file
$targetFile = "D:\Nova\model\Train-And-Package.py"

Write-Host "Starting Pylance Clean Pack v3 - Targeted Fixes..."

Apply-Targeted-Fixes -FilePath $targetFile

Write-Host ""
Write-Host "Pylance Clean Pack v3 completed!"
Write-Host "Fixed specific issues in Train-And-Package.py:"
Write-Host "- Constant redefinition (LIGHTGBM_AVAILABLE → _lightgbm_available)"
Write-Host "- Model parameter typing (**model_params: Any)"
Write-Host "- Schema dictionary typing (Dict[str, Any])"
Write-Host "- Train/test split result typing"
Write-Host "- ML library type ignores"
Write-Host "- Prediction array conversion"
Write-Host ""
Write-Host "Please reload VS Code to see resolved warnings."