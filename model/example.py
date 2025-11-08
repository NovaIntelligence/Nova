#!/usr/bin/env python3
from __future__ import annotations
"""
Example usage of Nova Model Training and Serving Pipeline
This script demonstrates how to:
1. Create sample training data
2. Train a model
3. Start the serving API
4. Make predictions via PowerShell
"""

import pandas as pd
import numpy as np
from pathlib import Path
import subprocess
import sys
import time

def create_sample_data():
    """Create sample training data for demonstration"""
    print("Creating sample training data...")
    
    # Generate synthetic data
    np.random.seed(42)
    n_samples = 1000
    
    # Features
    feature1 = np.random.normal(0, 1, n_samples)
    feature2 = np.random.choice(['A', 'B', 'C'], n_samples)
    feature3 = np.random.uniform(0, 100, n_samples)
    feature4 = np.random.randint(1, 10, n_samples)
    
    # Target (binary classification)
    # Create some meaningful relationships
    target = (
        (feature1 > 0) & 
        (feature2 == 'A') & 
        (feature3 > 50)
    ).astype(int)
    
    # Add some noise
    noise = np.random.random(n_samples) < 0.1
    target = target ^ noise  # Flip 10% of labels
    
    # Create DataFrame
    df = pd.DataFrame({
        'feature1': feature1,
        'feature2': feature2,
        'feature3': feature3,
        'feature4': feature4,
        'target': target
    })
    
    # Save as parquet
    df.to_parquet('training.parquet', index=False)
    print(f"Created training.parquet with {len(df)} samples")
    print(f"Target distribution: {df['target'].value_counts().to_dict()}")
    
    return df

def train_model():
    """Train the model using the training script"""
    print("\nTraining model...")
    
    cmd = [
        sys.executable, 'Train-And-Package.py',
        '--data', 'training.parquet',
        '--target', 'target',
        '--model-type', 'lightgbm',
        '--task-type', 'classification'
    ]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode == 0:
        print("Model training completed successfully!")
        print(result.stdout)
    else:
        print("Model training failed!")
        print(result.stderr)
        return False
    
    return True

def start_server():
    """Start the model serving API"""
    print("\nStarting model server...")
    print("Note: This will start the server in the background.")
    print("Use 'Stop-Process -Name python' in PowerShell to stop it later.")
    
    cmd = [
        sys.executable, 'serve.py',
        '--host', '0.0.0.0',
        '--port', '8000'
    ]
    
    # Start server in background
    process = subprocess.Popen(cmd)
    print(f"Server started with PID: {process.pid}")
    
    # Wait a moment for server to start
    time.sleep(3)
    
    return process

def test_api():
    """Test the API using requests"""
    print("\nTesting API...")
    
    try:
        import requests
        
        # Test health endpoint
        response = requests.get('http://localhost:8000/health', timeout=5)
        if response.status_code == 200:
            health = response.json()
            print(f"Health check: {health['status']}")
            print(f"Model loaded: {health['model_loaded']}")
        
        # Test prediction endpoint
        test_features = {
            'feature1': 1.5,
            'feature2': 'A',
            'feature3': 75.0,
            'feature4': 5
        }
        
        response = requests.post(
            'http://localhost:8000/score',
            json={'features': test_features},
            timeout=5
        )
        
        if response.status_code == 200:
            result = response.json()
            print(f"Prediction: {result['prediction']}")
            print(f"Confidence: {result['confidence']}")
        else:
            print(f"Prediction failed: {response.status_code}")
            
    except ImportError:
        print("Requests library not available. Install with: pip install requests")
    except Exception as e:
        print(f"API test failed: {e}")

def show_powershell_examples():
    """Show PowerShell usage examples"""
    print("\n" + "="*60)
    print("POWERSHELL USAGE EXAMPLES")
    print("="*60)
    
    print("""
# Import the Nova Model Client module
Import-Module "D:\\Nova\\Nova.ModelClient.psm1"

# Test the model health
Test-NovaModelHealth

# Make a single prediction
$features = @{
    "feature1" = 1.5
    "feature2" = "A" 
    "feature3" = 75.0
    "feature4" = 5
}
$prediction = Invoke-NovaModelPrediction -Features $features
Write-Host "Prediction: $prediction"

# Get detailed response
$result = Invoke-NovaModelPrediction -Features $features -PassThru
Write-Host "Prediction: $($result.prediction), Confidence: $($result.confidence)"

# Make batch predictions
$features1 = @{ "feature1" = 1.5; "feature2" = "A"; "feature3" = 75.0; "feature4" = 5 }
$features2 = @{ "feature1" = -1.0; "feature2" = "B"; "feature3" = 25.0; "feature4" = 2 }
$predictions = Invoke-NovaModelBatchPrediction -FeaturesList @($features1, $features2)

# Predict from CSV file
# First create a CSV with columns: feature1,feature2,feature3,feature4
# Then use:
$results = Invoke-NovaModelPredictionFromCsv -Path "test_data.csv"
$results | Export-Csv -Path "predictions.csv" -NoTypeInformation

# Get model information
Get-NovaModelInfo
""")

def main():
    """Main demonstration script"""
    print("Nova Model Pipeline Demo")
    print("=" * 50)
    
    # Check if we're in the right directory
    if not Path('Train-And-Package.py').exists():
        print("Error: Please run this script from the model directory")
        print("Expected files: Train-And-Package.py, serve.py")
        return
    
    # Create sample data
    df = create_sample_data()
    
    # Train model
    if not train_model():
        return
    
    # Check if model files were created
    if not Path('model_output/model.pkl').exists():
        print("Error: Model files not found!")
        return
    
    print("\nModel training completed successfully!")
    print("Files created:")
    print("- model_output/model.pkl")
    print("- model_output/schema.json")
    
    # Ask if user wants to start server
    response = input("\nStart the model server? (y/n): ").lower().strip()
    if response == 'y':
        process = start_server()
        test_api()
        show_powershell_examples()
        
        print(f"\nServer is running on http://localhost:8000")
        print(f"API docs available at: http://localhost:8000/docs")
        print(f"Use 'taskkill /PID {process.pid}' to stop the server")
    else:
        print("\nTo start the server later, run:")
        print("python serve.py --host 0.0.0.0 --port 8000")
        show_powershell_examples()

if __name__ == "__main__":
    main()