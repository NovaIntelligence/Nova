# Nova Model Training and Serving Pipeline

A complete machine learning pipeline for the Nova ecosystem with LightGBM/XGBoost training, FastAPI serving, and PowerShell integration.

## Features

- **Training Pipeline**: Supports both LightGBM and XGBoost models
- **Data Format**: Reads training data from Parquet files  
- **Model Export**: Saves trained models as `model.pkl` and schema as `schema.json`
- **FastAPI Serving**: RESTful API with `/score` endpoint for predictions
- **PowerShell Integration**: `Nova.ModelClient.psm1` module for easy integration
- **Shadow Logging**: Built-in logging for model interactions and monitoring
- **Batch Processing**: Support for single and batch predictions
- **CSV Processing**: Direct prediction from CSV files

## Quick Start

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Train a Model

```bash
# Using LightGBM (default)
python Train-And-Package.py --data training.parquet --target your_target_column

# Using XGBoost
python Train-And-Package.py --data training.parquet --target your_target_column --model-type xgboost

# For regression tasks
python Train-And-Package.py --data training.parquet --target your_target_column --task-type regression
```

### 3. Start Model Server

```bash
python serve.py --host 0.0.0.0 --port 8000
```

### 4. Use in PowerShell

```powershell
# Import the module
Import-Module "D:\Nova\Nova.ModelClient.psm1"

# Test connection
Test-NovaModelHealth

# Make predictions
$features = @{
    "feature1" = 1.5
    "feature2" = "category_a"
    "feature3" = 100
}
$prediction = Invoke-NovaModelPrediction -Features $features
```

## File Structure

```
Nova/
├── model/
│   ├── Train-And-Package.py    # Training script
│   ├── serve.py                # FastAPI serving script
│   ├── requirements.txt        # Python dependencies
│   ├── example.py             # Complete demo script
│   └── model_output/          # Generated model files
│       ├── model.pkl          # Trained model
│       └── schema.json        # Model schema and metadata
├── Nova.ModelClient.psm1      # PowerShell module
└── bot/
    └── nova-bot.ps1           # Enhanced with shadow logging
```

## Training Script (Train-And-Package.py)

### Usage

```bash
python Train-And-Package.py [OPTIONS]
```

### Options

- `--data`: Path to training parquet file (default: `training.parquet`)
- `--target`: Target column name (required)
- `--model-type`: Model type - `lightgbm` or `xgboost` (default: `lightgbm`)
- `--task-type`: Task type - `classification` or `regression` (default: `classification`)
- `--output-dir`: Output directory for model files (default: `model_output`)
- `--random-seed`: Random seed for reproducibility (default: 42)

### Example

```bash
python Train-And-Package.py \
    --data customer_data.parquet \
    --target churn_flag \
    --model-type lightgbm \
    --task-type classification \
    --output-dir models/churn_model
```

## Serving API (serve.py)

### Usage

```bash
python serve.py [OPTIONS]
```

### Options

- `--host`: Host to bind to (default: `0.0.0.0`)
- `--port`: Port to bind to (default: `8000`)
- `--model-dir`: Directory containing model files (default: `model_output`)
- `--reload`: Enable auto-reload for development
- `--log-level`: Log level (default: `info`)

### Endpoints

#### Health Check
```http
GET /health
```

#### Single Prediction
```http
POST /score
Content-Type: application/json

{
    "features": {
        "feature1": 1.5,
        "feature2": "category_a",
        "feature3": 100
    },
    "request_id": "optional-tracking-id"
}
```

#### Batch Prediction
```http
POST /score/batch
Content-Type: application/json

{
    "features": [
        {"feature1": 1.5, "feature2": "A", "feature3": 100},
        {"feature1": 2.0, "feature2": "B", "feature3": 200}
    ],
    "request_id": "optional-batch-id"
}
```

#### Model Information
```http
GET /model/info
```

#### Reload Model
```http
POST /model/reload
```

## PowerShell Module (Nova.ModelClient.psm1)

### Available Cmdlets

#### Configuration
- `Set-NovaModelEndpoint`: Set the API endpoint URL
- `Get-NovaModelEndpoint`: Get current endpoint URL  
- `Set-NovaModelLogging`: Enable/disable logging

#### Health and Status
- `Test-NovaModelHealth`: Check API health
- `Get-NovaModelInfo`: Get model information
- `Update-NovaModel`: Reload model from disk

#### Predictions
- `Invoke-NovaModelPrediction`: Single prediction
- `Invoke-NovaModelBatchPrediction`: Batch predictions
- `Invoke-NovaModelPredictionFromCsv`: Predict from CSV file

#### Logging
- `Write-NovaShadowLog`: Log model interactions

### Examples

```powershell
# Configure endpoint
Set-NovaModelEndpoint -Endpoint "http://production-server:8000"

# Single prediction
$features = @{
    "age" = 35
    "income" = 50000
    "credit_score" = 720
}
$prediction = Invoke-NovaModelPrediction -Features $features
Write-Host "Prediction: $prediction"

# Detailed response
$result = Invoke-NovaModelPrediction -Features $features -PassThru
Write-Host "Prediction: $($result.prediction), Confidence: $($result.confidence)"

# Batch predictions
$batch = @(
    @{ "age" = 25; "income" = 40000; "credit_score" = 650 },
    @{ "age" = 45; "income" = 80000; "credit_score" = 800 }
)
$predictions = Invoke-NovaModelBatchPrediction -FeaturesList $batch

# CSV processing
$results = Invoke-NovaModelPredictionFromCsv -Path "customers.csv" -OutputPath "predictions.csv"

# Health check
$health = Test-NovaModelHealth
if ($health.model_loaded) {
    Write-Host "Model is ready: $($health.model_type)"
}
```

## Shadow Logging Integration

The Nova bot now includes automatic shadow logging for model interactions:

### Configuration

Add to `config.json`:

```json
{
    "model": {
        "endpoint": "http://localhost:8000",
        "enabled": true,
        "shadow_logging": true
    }
}
```

### Features

- Automatic logging of all model predictions
- Session tracking with unique session IDs
- Metadata capture (timestamps, confidence scores, etc.)
- Configurable log destinations
- Integration with nova-bot.ps1 LLM interactions

### Log Format

```json
{
    "timestamp": "2024-11-06 10:30:45.123",
    "request_id": "uuid-here",
    "features": {"feature1": 1.5, "feature2": "A"},
    "prediction": 1,
    "confidence": 0.85,
    "metadata": {
        "component": "nova-bot",
        "interaction_type": "llm_chat",
        "session_id": "session-uuid"
    },
    "client": "NovaModelClient-PowerShell",
    "version": "1.0.0"
}
```

## Data Format Requirements

### Training Data (Parquet)

- Must be in Parquet format
- Should contain feature columns and one target column
- Categorical features will be automatically encoded
- Missing values will be handled automatically

Example structure:
```
feature1 (numeric)
feature2 (categorical)  
feature3 (numeric)
target_column (numeric for regression, binary/categorical for classification)
```

### CSV Prediction Data

- Must have same feature columns as training data
- Header row required with exact feature names
- Can contain additional columns (will be ignored)

## Monitoring and Debugging

### Log Levels

- **INFO**: General operation information
- **DEBUG**: Detailed debugging information  
- **WARNING**: Non-fatal issues
- **ERROR**: Error conditions

### Common Issues

1. **Module Import Errors**: Ensure Python dependencies are installed
2. **Port Conflicts**: Use different port with `--port` option
3. **Missing Model Files**: Ensure training completed successfully
4. **Feature Mismatch**: Verify prediction features match training schema

### Health Checks

```bash
# Test API directly
curl http://localhost:8000/health

# Test from PowerShell
Test-NovaModelHealth

# Check logs
Get-Content "logs/nova-model-$(Get-Date -Format 'yyyy-MM-dd').log"
```

## Development

### Running the Example

```bash
# Creates sample data, trains model, and starts server
python example.py
```

### Testing Changes

```bash
# Run with auto-reload for development
python serve.py --reload --log-level debug
```

### Extending the Pipeline

1. **Add New Model Types**: Extend `NovaModelTrainer` class
2. **Custom Preprocessing**: Modify `preprocess_data` method
3. **Additional Endpoints**: Add routes to FastAPI app
4. **PowerShell Cmdlets**: Add functions to the `.psm1` module

## Support

For issues and questions:
1. Check the logs for error messages
2. Verify configuration settings
3. Test with the provided example data
4. Review the API documentation at `/docs` endpoint