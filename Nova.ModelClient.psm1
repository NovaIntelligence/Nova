#
# Nova.ModelClient.psm1
# PowerShell module for interacting with Nova Model Serving API
# Provides easy-to-use cmdlets for model predictions and management
#

# Module variables
$Script:DefaultModelEndpoint = "http://localhost:8000"
$Script:DefaultTimeout = 30
$Script:LoggingEnabled = $true

#region Helper Functions

function Write-NovaLog {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Debug")]
        [string]$Level = "Info",
        [string]$Source = "NovaModelClient"
    )
    
    if (-not $Script:LoggingEnabled) { return }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] [$Source] $Message"
    
    switch ($Level) {
        "Error" { Write-Error $logMessage }
        "Warning" { Write-Warning $logMessage }
        "Debug" { Write-Debug $logMessage }
        default { Write-Information $logMessage -InformationAction Continue }
    }
}

function Invoke-NovaRestMethod {
    param(
        [string]$Uri,
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method = "Get",
        [hashtable]$Headers = @{},
        [object]$Body = $null,
        [int]$TimeoutSec = $Script:DefaultTimeout
    )
    
    try {
        $params = @{
            Uri = $Uri
            Method = $Method
            Headers = $Headers
            TimeoutSec = $TimeoutSec
            ContentType = "application/json"
        }
        
        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
        }
        
        Write-NovaLog "Making request to: $Uri" -Level Debug
        $response = Invoke-RestMethod @params
        Write-NovaLog "Request successful" -Level Debug
        
        return $response
    }
    catch {
        Write-NovaLog "Request failed: $($_.Exception.Message)" -Level Error
        throw
    }
}

#endregion

#region Configuration Functions

<#
.SYNOPSIS
Sets the default Nova Model API endpoint.

.DESCRIPTION
Configures the default endpoint URL for Nova Model API calls. 
This setting affects all subsequent cmdlet calls unless overridden.

.PARAMETER Endpoint
The base URL of the Nova Model API (e.g., "http://localhost:8000")

.EXAMPLE
Set-NovaModelEndpoint -Endpoint "http://production-server:8000"
#>
function Set-NovaModelEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint
    )
    
    $Script:DefaultModelEndpoint = $Endpoint.TrimEnd('/')
    Write-NovaLog "Model endpoint set to: $Script:DefaultModelEndpoint"
}

<#
.SYNOPSIS
Gets the current Nova Model API endpoint.

.DESCRIPTION
Returns the currently configured Nova Model API endpoint URL.

.EXAMPLE
Get-NovaModelEndpoint
#>
function Get-NovaModelEndpoint {
    [CmdletBinding()]
    param()
    
    return $Script:DefaultModelEndpoint
}

<#
.SYNOPSIS
Enables or disables Nova Model Client logging.

.DESCRIPTION
Controls whether the Nova Model Client writes log messages.

.PARAMETER Enabled
Whether to enable logging (default: $true)

.EXAMPLE
Set-NovaModelLogging -Enabled $false
#>
function Set-NovaModelLogging {
    [CmdletBinding()]
    param(
        [bool]$Enabled = $true
    )
    
    $Script:LoggingEnabled = $Enabled
    Write-NovaLog "Logging $(if($Enabled){'enabled'}else{'disabled'})"
}

#endregion

#region Health and Status Functions

<#
.SYNOPSIS
Checks the health status of the Nova Model API.

.DESCRIPTION
Performs a health check against the Nova Model API endpoint and returns 
status information including model load status and uptime.

.PARAMETER Endpoint
The Nova Model API endpoint URL. If not specified, uses the default endpoint.

.EXAMPLE
Test-NovaModelHealth

.EXAMPLE
Test-NovaModelHealth -Endpoint "http://server:8000"
#>
function Test-NovaModelHealth {
    [CmdletBinding()]
    param(
        [string]$Endpoint = $Script:DefaultModelEndpoint
    )
    
    try {
        $uri = "$Endpoint/health"
        $response = Invoke-NovaRestMethod -Uri $uri
        
        Write-NovaLog "Health check successful - Status: $($response.status)"
        return $response
    }
    catch {
        Write-NovaLog "Health check failed: $($_.Exception.Message)" -Level Error
        throw
    }
}

<#
.SYNOPSIS
Gets information about the loaded Nova model.

.DESCRIPTION
Retrieves detailed information about the currently loaded model including
features, metrics, and prediction statistics.

.PARAMETER Endpoint
The Nova Model API endpoint URL. If not specified, uses the default endpoint.

.EXAMPLE
Get-NovaModelInfo
#>
function Get-NovaModelInfo {
    [CmdletBinding()]
    param(
        [string]$Endpoint = $Script:DefaultModelEndpoint
    )
    
    try {
        $uri = "$Endpoint/model/info"
        $response = Invoke-NovaRestMethod -Uri $uri
        
        Write-NovaLog "Model info retrieved successfully"
        return $response
    }
    catch {
        Write-NovaLog "Failed to get model info: $($_.Exception.Message)" -Level Error
        throw
    }
}

<#
.SYNOPSIS
Reloads the Nova model from disk.

.DESCRIPTION
Triggers the Nova Model API to reload the model and schema from disk.
Useful when the model files have been updated.

.PARAMETER Endpoint
The Nova Model API endpoint URL. If not specified, uses the default endpoint.

.EXAMPLE
Update-NovaModel
#>
function Update-NovaModel {
    [CmdletBinding()]
    param(
        [string]$Endpoint = $Script:DefaultModelEndpoint
    )
    
    try {
        $uri = "$Endpoint/model/reload"
        $response = Invoke-NovaRestMethod -Uri $uri -Method Post
        
        Write-NovaLog "Model reloaded successfully"
        return $response
    }
    catch {
        Write-NovaLog "Failed to reload model: $($_.Exception.Message)" -Level Error
        throw
    }
}

#endregion

#region Prediction Functions

<#
.SYNOPSIS
Makes a prediction using the Nova model.

.DESCRIPTION
Sends feature data to the Nova Model API for scoring and returns the prediction
along with confidence scores and metadata.

.PARAMETER Features
Hashtable containing the feature values for prediction.

.PARAMETER RequestId
Optional request ID for tracking purposes.

.PARAMETER Endpoint
The Nova Model API endpoint URL. If not specified, uses the default endpoint.

.PARAMETER PassThru
Returns the raw API response instead of just the prediction value.

.EXAMPLE
$features = @{
    "feature1" = 1.5
    "feature2" = "category_a"
    "feature3" = 100
}
$prediction = Invoke-NovaModelPrediction -Features $features

.EXAMPLE
$result = Invoke-NovaModelPrediction -Features $features -PassThru
Write-Host "Prediction: $($result.prediction), Confidence: $($result.confidence)"
#>
function Invoke-NovaModelPrediction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Features,
        
        [string]$RequestId,
        
        [string]$Endpoint = $Script:DefaultModelEndpoint,
        
        [switch]$PassThru
    )
    
    try {
        $body = @{
            features = $Features
        }
        
        if ($RequestId) {
            $body.request_id = $RequestId
        }
        
        $uri = "$Endpoint/score"
        $response = Invoke-NovaRestMethod -Uri $uri -Method Post -Body $body
        
        Write-NovaLog "Prediction completed - Request ID: $($response.request_id)"
        
        if ($PassThru) {
            return $response
        } else {
            return $response.prediction
        }
    }
    catch {
        Write-NovaLog "Prediction failed: $($_.Exception.Message)" -Level Error
        throw
    }
}

<#
.SYNOPSIS
Makes batch predictions using the Nova model.

.DESCRIPTION
Sends multiple feature sets to the Nova Model API for batch scoring and returns
the predictions along with confidence scores and metadata.

.PARAMETER FeaturesList
Array of hashtables, each containing feature values for prediction.

.PARAMETER RequestId
Optional request ID for tracking purposes.

.PARAMETER Endpoint
The Nova Model API endpoint URL. If not specified, uses the default endpoint.

.PARAMETER PassThru
Returns the raw API response instead of just the prediction values.

.EXAMPLE
$features1 = @{ "feature1" = 1.5; "feature2" = "category_a" }
$features2 = @{ "feature1" = 2.0; "feature2" = "category_b" }
$predictions = Invoke-NovaModelBatchPrediction -FeaturesList @($features1, $features2)

.EXAMPLE
$result = Invoke-NovaModelBatchPrediction -FeaturesList $featuresList -PassThru
foreach ($i in 0..($result.predictions.Count - 1)) {
    Write-Host "Sample $i: Prediction=$($result.predictions[$i]), Confidence=$($result.confidences[$i])"
}
#>
function Invoke-NovaModelBatchPrediction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable[]]$FeaturesList,
        
        [string]$RequestId,
        
        [string]$Endpoint = $Script:DefaultModelEndpoint,
        
        [switch]$PassThru
    )
    
    try {
        if ($FeaturesList.Count -gt 1000) {
            throw "Batch size cannot exceed 1000 samples"
        }
        
        $body = @{
            features = $FeaturesList
        }
        
        if ($RequestId) {
            $body.request_id = $RequestId
        }
        
        $uri = "$Endpoint/score/batch"
        $response = Invoke-NovaRestMethod -Uri $uri -Method Post -Body $body
        
        Write-NovaLog "Batch prediction completed - $($response.batch_size) samples processed"
        
        if ($PassThru) {
            return $response
        } else {
            return $response.predictions
        }
    }
    catch {
        Write-NovaLog "Batch prediction failed: $($_.Exception.Message)" -Level Error
        throw
    }
}

#endregion

#region CSV and File Functions

<#
.SYNOPSIS
Makes predictions from CSV data.

.DESCRIPTION
Loads feature data from a CSV file and makes predictions using the Nova model.
Returns results with the original data plus prediction columns.

.PARAMETER Path
Path to the CSV file containing feature data.

.PARAMETER Endpoint
The Nova Model API endpoint URL. If not specified, uses the default endpoint.

.PARAMETER OutputPath
Optional path to save results as CSV. If not specified, returns objects.

.PARAMETER BatchSize
Number of rows to process in each batch (default: 100, max: 1000).

.EXAMPLE
$results = Invoke-NovaModelPredictionFromCsv -Path "features.csv"

.EXAMPLE
Invoke-NovaModelPredictionFromCsv -Path "features.csv" -OutputPath "results.csv"
#>
function Invoke-NovaModelPredictionFromCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [string]$Endpoint = $Script:DefaultModelEndpoint,
        
        [string]$OutputPath,
        
        [int]$BatchSize = 100
    )
    
    try {
        if (-not (Test-Path $Path)) {
            throw "CSV file not found: $Path"
        }
        
        if ($BatchSize -lt 1 -or $BatchSize -gt 1000) {
            throw "BatchSize must be between 1 and 1000"
        }
        
        Write-NovaLog "Loading CSV data from: $Path"
        $data = Import-Csv -Path $Path
        
        if ($data.Count -eq 0) {
            throw "CSV file is empty or has no data rows"
        }
        
        Write-NovaLog "Processing $($data.Count) rows in batches of $BatchSize"
        
        $results = @()
        $totalBatches = [Math]::Ceiling($data.Count / $BatchSize)
        
        for ($batch = 0; $batch -lt $totalBatches; $batch++) {
            $startIdx = $batch * $BatchSize
            $endIdx = [Math]::Min($startIdx + $BatchSize - 1, $data.Count - 1)
            $batchData = $data[$startIdx..$endIdx]
            
            Write-NovaLog "Processing batch $($batch + 1)/$totalBatches (rows $($startIdx + 1)-$($endIdx + 1))"
            
            # Convert to hashtables for API
            $featuresList = @()
            foreach ($row in $batchData) {
                $features = @{}
                $row.PSObject.Properties | ForEach-Object {
                    # Try to convert numeric values
                    $value = $_.Value
                    if ($value -match '^\d+$') {
                        $value = [int]$value
                    } elseif ($value -match '^\d*\.\d+$') {
                        $value = [double]$value
                    }
                    $features[$_.Name] = $value
                }
                $featuresList += $features
            }
            
            # Make batch prediction
            $response = Invoke-NovaModelBatchPrediction -FeaturesList $featuresList -PassThru -Endpoint $Endpoint
            
            # Combine original data with predictions
            for ($i = 0; $i -lt $batchData.Count; $i++) {
                $result = $batchData[$i] | Select-Object *, 
                    @{Name="Prediction"; Expression={$response.predictions[$i]}},
                    @{Name="Confidence"; Expression={if($response.confidences){$response.confidences[$i]}else{$null}}},
                    @{Name="ModelVersion"; Expression={$response.model_version}},
                    @{Name="PredictionTimestamp"; Expression={$response.timestamp}}
                
                $results += $result
            }
        }
        
        Write-NovaLog "Prediction completed for all $($data.Count) rows"
        
        if ($OutputPath) {
            $results | Export-Csv -Path $OutputPath -NoTypeInformation
            Write-NovaLog "Results saved to: $OutputPath"
            return @{
                ResultsPath = $OutputPath
                TotalRows = $results.Count
                BatchesProcessed = $totalBatches
            }
        } else {
            return $results
        }
    }
    catch {
        Write-NovaLog "CSV prediction failed: $($_.Exception.Message)" -Level Error
        throw
    }
}

#endregion

#region Shadow Logging Functions

<#
.SYNOPSIS
Logs model prediction activity for shadow monitoring.

.DESCRIPTION
Creates detailed logs of model prediction requests and responses for 
monitoring, auditing, and performance analysis.

.PARAMETER Features
The input features used for prediction.

.PARAMETER Prediction
The model prediction result.

.PARAMETER Confidence
The prediction confidence score.

.PARAMETER RequestId
Optional request ID for tracking.

.PARAMETER LogPath
Path to the shadow log file. If not specified, uses default location.

.PARAMETER Metadata
Additional metadata to include in the log entry.

.EXAMPLE
Write-NovaShadowLog -Features $features -Prediction $result.prediction -Confidence $result.confidence
#>
function Write-NovaShadowLog {
    [CmdletBinding()]
    param(
        [hashtable]$Features,
        [object]$Prediction,
        [double]$Confidence,
        [string]$RequestId,
        [string]$LogPath,
        [hashtable]$Metadata = @{}
    )
    
    try {
        if (-not $LogPath) {
            $logDir = Join-Path $env:TEMP "NovaModel\ShadowLogs"
            if (-not (Test-Path $logDir)) {
                New-Item -ItemType Directory -Force -Path $logDir | Out-Null
            }
            $LogPath = Join-Path $logDir "shadow-$(Get-Date -Format 'yyyy-MM-dd').log"
        }
        
        $logEntry = @{
            timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
            request_id = $RequestId
            features = $Features
            prediction = $Prediction
            confidence = $Confidence
            metadata = $Metadata
            client = "NovaModelClient-PowerShell"
            version = "1.0.0"
        }
        
        $logLine = ($logEntry | ConvertTo-Json -Compress -Depth 10)
        Add-Content -Path $LogPath -Value $logLine -Encoding UTF8
        
        Write-NovaLog "Shadow log entry written to: $LogPath" -Level Debug
    }
    catch {
        Write-NovaLog "Failed to write shadow log: $($_.Exception.Message)" -Level Warning
    }
}

#endregion

#region Module Initialization

# Set module-level variables on import
$Script:DefaultModelEndpoint = "http://localhost:8000"
$Script:DefaultTimeout = 30
$Script:LoggingEnabled = $true

Write-NovaLog "Nova.ModelClient module loaded successfully"

#endregion

# Export module functions
Export-ModuleMember -Function @(
    'Set-NovaModelEndpoint',
    'Get-NovaModelEndpoint', 
    'Set-NovaModelLogging',
    'Test-NovaModelHealth',
    'Get-NovaModelInfo',
    'Update-NovaModel',
    'Invoke-NovaModelPrediction',
    'Invoke-NovaModelBatchPrediction',
    'Invoke-NovaModelPredictionFromCsv',
    'Write-NovaShadowLog'
)