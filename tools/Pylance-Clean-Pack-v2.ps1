# Pylance Clean Pack v2 - Enhanced Python Linting with Precise Fixes
# Comprehensive fix for common Pylance warnings across Nova model files
# Includes advanced typing patterns and ML-specific fixes

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

function Apply-Advanced-Fixes {
    param([string]$FilePath)
    
    $content = Get-Content -Path $FilePath -Raw -Encoding UTF8
    $modified = $false
    
    # Fix metadata typing pattern
    if ($content -match "metadata.*=.*metadata") {
        $content = $content -replace "metadata:\s*\w+.*=.*metadata.*", "metadata: Dict[str, Any] = cast(Dict[str, Any], metadata if isinstance(metadata, dict) else {})"
        $modified = $true
        Write-Host "Fixed metadata typing pattern"
    }
    
    # Fix missing_features set pattern  
    if ($content -match "missing_features.*=.*set") {
        $content = $content -replace "missing_features.*=.*set.*", 'missing_features: Set[str] = set(cast(Sequence[str], metadata.get("required_features", [])))'
        $modified = $true
        Write-Host "Fixed missing_features set typing"
    }
    
    # Add df_records function for pandas DataFrame conversion
    if ($content -match "\.to_dict\(.*records.*\)" -and $content -notmatch "def df_records") {
        $dfRecordsFunction = @"
import pandas as pd
def df_records(df: pd.DataFrame) -> List[Dict[str, Any]]:
    df = df.copy()
    df.columns = df.columns.astype(str)
    recs = df.to_dict(orient="records")
    # mypy/Pylance likes cast when it can't infer:
    from typing import cast
    return cast(List[Dict[str, Any]], recs)

"@
        $content = $dfRecordsFunction + $content
        $modified = $true
        Write-Host "Added df_records helper function"
    }
    
    # Fix predict_batch signature to use Sequence[Mapping]
    $content = $content -replace "def predict_batch\(instances:\s*List\[Dict\[.*?\]\].*?\):", "def predict_batch(instances: Sequence[Mapping[str, Any]]) -> List[Dict[str, Any]]:"
    if ($content -match "def predict_batch.*instances.*Sequence") {
        $modified = $true
        Write-Host "Updated predict_batch signature to use Sequence[Mapping]"
    }
    
    # Add FastAPI exception handler imports
    if ($content -match "@app\.exception_handler" -and $content -notmatch "from fastapi.responses import JSONResponse") {
        Ensure-Once -FilePath $FilePath -Pattern "from fastapi.responses import JSONResponse" -Insertion "from fastapi.responses import JSONResponse"
        $modified = $true
    }
    
    # Fix FastAPI exception handler signature
    $content = $content -replace "def on_unhandled\(request.*?, exc.*?\):", "def on_unhandled(request: Request, exc: Exception) -> JSONResponse:"
    if ($content -match "def on_unhandled.*Request.*Exception.*JSONResponse") {
        $modified = $true
        Write-Host "Fixed FastAPI exception handler signature"
    }
    
    # Add optional ML library imports pattern
    if ($content -match "import lightgbm" -and $content -notmatch "LIGHTGBM_AVAILABLE") {
        $lightgbmImport = @"
from types import ModuleType
from typing import Optional

try:
    import lightgbm as lgb  # type: ignore[import-not-found]
    LIGHTGBM_AVAILABLE = True
except Exception:
    lgb: Optional[ModuleType] = None
    LIGHTGBM_AVAILABLE = False

"@
        $content = $content -replace "import lightgbm.*", $lightgbmImport
        $modified = $true
        Write-Host "Added safe LightGBM import pattern"
    }
    
    if ($content -match "import xgboost" -and $content -notmatch "XGBOOST_AVAILABLE") {
        $xgboostImport = @"
try:
    import xgboost as xgb  # type: ignore[import-not-found]
    XGBOOST_AVAILABLE = True
except Exception:
    xgb: Optional[ModuleType] = None
    XGBOOST_AVAILABLE = False

"@
        $content = $content -replace "import xgboost.*", $xgboostImport
        $modified = $true
        Write-Host "Added safe XGBoost import pattern"
    }
    
    # Add Transformer protocol for sklearn
    if ($content -match "OneHotEncoder|StandardScaler" -and $content -notmatch "class Transformer\(Protocol\)") {
        $transformerProtocol = @"
from typing import Protocol, Any

class Transformer(Protocol):
    def fit(self, X: Any, y: Any | None = None) -> Any: ...
    def transform(self, X: Any) -> Any: ...
    def fit_transform(self, X: Any, y: Any | None = None) -> Any: ...

"@
        $content = $transformerProtocol + $content
        $modified = $true
        Write-Host "Added Transformer protocol for sklearn types"
    }
    
    # Fix ndarray from DataFrame values
    $content = $content -replace "\.values\s*$", ""
    $content = $content -replace "df_scaled_values.*=.*df_scaled", "df_scaled_values: np.ndarray = np.asarray(df_scaled)"
    if ($content -match "df_scaled_values.*np\.ndarray.*np\.asarray") {
        $modified = $true
        Write-Host "Fixed DataFrame to ndarray conversion"
    }
    
    # Fix Pydantic v2 field validators
    $content = $content -replace "@validator\('([^']+)',\s*pre=True\)", "@field_validator('`$1', mode='before')"
    if ($content -match "@field_validator.*mode.*before") {
        $modified = $true
        Write-Host "Upgraded Pydantic validators to v2 syntax"
    }
    
    # Add sklearn imports clarity
    if ($content -match "train_test_split" -and $content -notmatch "from sklearn.model_selection import train_test_split") {
        Ensure-Once -FilePath $FilePath -Pattern "from sklearn.model_selection import train_test_split" -Insertion "from sklearn.model_selection import train_test_split"
        $modified = $true
    }
    
    if ($content -match "precision_recall_fscore_support" -and $content -notmatch "from sklearn.metrics import precision_recall_fscore_support") {
        Ensure-Once -FilePath $FilePath -Pattern "from sklearn.metrics import precision_recall_fscore_support" -Insertion "from sklearn.metrics import precision_recall_fscore_support"
        $modified = $true
    }
    
    # Enhanced endswith guard (already handled in basic fixes, but ensure pattern)
    $content = $content -replace "(\w+)\.endswith\(", 'if $1 and $1.endswith('
    
    if ($modified) {
        [System.IO.File]::WriteAllText($FilePath, $content, [System.Text.Encoding]::UTF8)
        Write-Host "Applied advanced typing fixes"
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
    $backupPath = $FilePath + ".v2.bak"
    Copy-Item -Path $FilePath -Destination $backupPath -Force
    
    # Add comprehensive typing imports
    Ensure-Once -FilePath $FilePath -Pattern "from typing import" -Insertion "from typing import Any, Dict, List, Optional, Sequence, Mapping, Set, Tuple, Union, cast, Protocol"
    
    # Add __future__ annotations
    Ensure-Once -FilePath $FilePath -Pattern "from __future__ import annotations" -Insertion "from __future__ import annotations"
    
    # Add numpy import if needed
    $content = Get-Content -Path $FilePath -Raw -Encoding UTF8
    if ($content -match "np\." -and $content -notmatch "import numpy as np") {
        Ensure-Once -FilePath $FilePath -Pattern "import numpy as np" -Insertion "import numpy as np"
    }
    
    # Add pydantic field_validator import if needed
    if ($content -match "@validator" -and $content -notmatch "from pydantic import.*field_validator") {
        Ensure-Once -FilePath $FilePath -Pattern "from pydantic import.*field_validator" -Insertion "from pydantic import BaseModel, field_validator"
    }
    
    # Basic Pydantic v2 migration
    Update-Text -FilePath $FilePath -Old "@validator(" -New "@field_validator("
    Update-Text -FilePath $FilePath -Old "@validator(pre=True)" -New "@field_validator(mode=`"before`")"
    
    # Ensure FastAPI imports for exception handlers
    if ($content -match "HTTPException|exception_handler|@app\.exception_handler") {
        Ensure-Once -FilePath $FilePath -Pattern "from fastapi import.*Request" -Insertion "from fastapi import Request"
        Ensure-Once -FilePath $FilePath -Pattern "from fastapi.responses import JSONResponse" -Insertion "from fastapi.responses import JSONResponse"
    }
    
    # Fix pandas imports
    Update-Text -FilePath $FilePath -Old "from pandas.io.common import StringIO" -New "from io import StringIO"
    Update-Text -FilePath $FilePath -Old "pandas.io.common.StringIO" -New "StringIO"
    
    # Apply advanced pattern fixes
    Apply-Advanced-Fixes -FilePath $FilePath
    
    Write-Host "Completed: $FilePath (backup: $backupPath)"
}

# Target files to fix
$targetFiles = @(
    "D:\Nova\bot\model\serve.py",
    "D:\Nova\bot\model\Train-And-Package.py", 
    "D:\Nova\model\serve.py",
    "D:\Nova\model\example.py"
)

Write-Host "Starting Pylance Clean Pack v2..."
Write-Host "Enhanced with ML typing patterns and precise fixes"
Write-Host "Target files: $($targetFiles.Count)"

foreach ($file in $targetFiles) {
    Fix-File -FilePath $file
}

Write-Host ""
Write-Host "Pylance Clean Pack v2 completed!"
Write-Host "Applied advanced typing patterns for:"
Write-Host "- Sets, dicts, and metadata typing with cast()"
Write-Host "- pandas → List[Dict[str, Any]] conversions"
Write-Host "- Relaxed predict_batch signatures with Sequence[Mapping]"
Write-Host "- FastAPI exception handler types"
Write-Host "- Optional ML library imports (LightGBM/XGBoost)"
Write-Host "- Scikit-learn Transformer protocols"
Write-Host "- Pydantic v2 field_validator migrations"
Write-Host "- Enhanced sklearn imports clarity"
Write-Host ""
Write-Host "Please reload VS Code to see all resolved warnings."
Write-Host "Backup files created with .v2.bak extension."