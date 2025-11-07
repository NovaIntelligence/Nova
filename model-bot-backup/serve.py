import pandas as pd
def df_records(df: pd.DataFrame) -> List[Dict[str, Any]]:
    df = df.copy()
    df.columns = df.columns.astype(str)
    recs = df.to_dict(orient="records")
    # mypy/Pylance likes cast when it can't infer:
    from typing import cast
    return cast(List[Dict[str, Any]], recs)
from fastapi import Request
from __future__ import annotations
#!/usr/bin/env python3
"""
Nova ML Model Server - serve.py
FastAPI-based serving with /score, /health, and /batch endpoints
"""

import json
import pickle
import logging
import traceback
from pathlib import Path
from typing import Dict, List, Any, Optional, Union
from datetime import datetime

import pandas as pd
import numpy as np
from fastapi import FastAPI, HTTPException, BackgroundTasks, UploadFile, File
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
import uvicorn

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class PredictionRequest(BaseModel):
    """Single prediction request schema"""
    features: Dict[str, Union[float, int, str]] = Field(..., description="Feature values for prediction")
    model_version: Optional[str] = Field(None, description="Specific model version to use")


class PredictionResponse(BaseModel):
    """Single prediction response schema"""
    prediction: Union[float, int, List[float]] = Field(..., description="Model prediction")
    probability: Optional[Union[float, List[float]]] = Field(None, description="Prediction probability (classification only)")
    model_version: str = Field(..., description="Model version used")
    timestamp: str = Field(..., description="Prediction timestamp")


class BatchPredictionRequest(BaseModel):
    """Batch prediction request schema"""
    instances: List[Dict[str, Union[float, int, str]]] = Field(..., description="List of feature dictionaries")
    model_version: Optional[str] = Field(None, description="Specific model version to use")


class BatchPredictionResponse(BaseModel):
    """Batch prediction response schema"""
    predictions: List[Union[float, int, List[float]]] = Field(..., description="List of predictions")
    probabilities: Optional[List[Union[float, List[float]]]] = Field(None, description="List of prediction probabilities")
    model_version: str = Field(..., description="Model version used")
    timestamp: str = Field(..., description="Prediction timestamp")
    processed_count: int = Field(..., description="Number of instances processed")


class HealthResponse(BaseModel):
    """Health check response schema"""
    status: str = Field(..., description="Service status")
    model_loaded: bool = Field(..., description="Whether model is loaded")
    model_version: Optional[str] = Field(None, description="Current model version")
    uptime_seconds: float = Field(..., description="Service uptime in seconds")
    last_prediction: Optional[str] = Field(None, description="Timestamp of last prediction")


class NovaModelServer:
    """
    Nova ML Model Server
    
    Loads trained models and provides FastAPI endpoints for inference
    """
    
    def __init__(self, model_path: Union[str, Path] = "model.pkl"):
        """Initialize the model server"""
        self.model_path = Path(model_path)
        self.model = None
        self.preprocessors = {}
        self.metadata = {}
        self.start_time = datetime.now()
        self.last_prediction_time = None
        self.prediction_count = 0
        
        # Load model on initialization
        self.load_model()
    
    def load_model(self):
        """Load the trained model and preprocessors"""
        try:
            if not self.model_path.exists():
                raise FileNotFoundError(f"Model file not found: {self.model_path}")
            
            logger.info(f"Loading model from {self.model_path}")
            
            with open(self.model_path, 'rb') as f:
                model_package = pickle.load(f)
            
            self.model = model_package['model']
            self.preprocessors = model_package['preprocessors']
            self.metadata = model_package['metadata']
            
            logger.info(f"Model loaded successfully: {self.metadata['algorithm']} {self.metadata['task_type']}")
            logger.info(f"Features: {len(self.metadata['feature_names'])}, Version: {self.metadata.get('model_version', 'unknown')}")
            
        except Exception as e:
            logger.error(f"Failed to load model: {e}")
            raise RuntimeError(f"Model loading failed: {e}")
    
    def preprocess_features(self, features: Dict[str, Any]) -> np.ndarray:
        """
        Preprocess input features to match training format
        
        Args:
            features: Dictionary of feature name -> value pairs
            
        Returns:
            Preprocessed feature array ready for prediction
        """
        try:
            # Convert to DataFrame
            df = pd.DataFrame([features])
            
            # Ensure all expected features are present
            missing_features: Set[str] = set(cast(Sequence[str], metadata.get("required_features", [])))
            if missing_features:
                raise ValueError(f"Missing features: {missing_features}")
            
            # Reorder columns to match training order
            df = df[self.metadata['feature_names']]
            
            # Apply preprocessing steps
            # Handle categorical encoding
            for col in df.columns:
                encoder_key = f"label_encoder_{col}"
                if encoder_key in self.preprocessors:
                    encoder = self.preprocessors[encoder_key]
                    try:
                        df[col] = encoder.transform(df[col].astype(str))
                    except ValueError:
                        # Handle unseen categories by using the most frequent class
                        logger.warning(f"Unseen category in {col}, using mode")
                        df[col] = encoder.transform([encoder.classes_[0]])[0]
            
            # Apply scaling
            if 'scaler' in self.preprocessors:
                scaler = self.preprocessors['scaler']
                df_scaled = scaler.transform(df)
            else:
                df_scaled = df.values
            
            return df_scaled
            
        except Exception as e:
            logger.error(f"Preprocessing failed: {e}")
            raise ValueError(f"Feature preprocessing error: {e}")
    
    def predict_single(self, features: Dict[str, Any]) -> Dict[str, Any]:
        """
        Make a single prediction
        
        Args:
            features: Feature dictionary
            
        Returns:
            Prediction result with probabilities if applicable
        """
        if self.model is None:
            raise RuntimeError("Model not loaded")
        
        try:
            # Preprocess features
            X = self.preprocess_features(features)
            
            # Make prediction
            if self.metadata['algorithm'] == 'lightgbm':
                prediction = self.model.predict(X)[0]
                
                # Handle probabilities for classification
                if self.metadata['task_type'] == 'classification':
                    # For binary classification
                    if len(np.unique(prediction)) == 2 or isinstance(prediction, (int, float)):
                        if isinstance(prediction, (int, float)):
                            probability = float(prediction) if prediction <= 1.0 else None
                            prediction = int(prediction > 0.5) if probability is not None else int(prediction)
                        else:
                            probability = None
                    else:
                        # Multi-class - prediction is already class probabilities
                        probability = prediction.tolist() if hasattr(prediction, 'tolist') else [float(prediction)]
                        prediction = int(np.argmax(prediction))
                else:
                    probability = None
                    prediction = float(prediction)
                    
            else:  # xgboost
                if self.metadata['task_type'] == 'classification':
                    prediction = int(self.model.predict(X)[0])
                    prediction_proba = self.model.predict_proba(X)[0]
                    if len(prediction_proba) == 2:
                        probability = float(prediction_proba[1])  # Probability of positive class
                    else:
                        probability = prediction_proba.tolist()
                else:
                    prediction = float(self.model.predict(X)[0])
                    probability = None
            
            # Update tracking
            self.last_prediction_time = datetime.now()
            self.prediction_count += 1
            
            result = {
                'prediction': prediction,
                'probability': probability,
                'model_version': self.metadata.get('model_version', 'unknown'),
                'timestamp': self.last_prediction_time.isoformat()
            }
            
            logger.info(f"Prediction made: {prediction} (prob: {probability})")
            return result
            
        except Exception as e:
            logger.error(f"Prediction failed: {e}")
            raise RuntimeError(f"Prediction error: {e}")
    
    def predict_batch(self, instances: List[Dict[str, Any]]) -> Dict[str, Any]:
        """
        Make batch predictions
        
        Args:
            instances: List of feature dictionaries
            
        Returns:
            Batch prediction results
        """
        if self.model is None:
            raise RuntimeError("Model not loaded")
        
        try:
            predictions = []
            probabilities = []
            
            for instance in instances:
                result = self.predict_single(instance)
                predictions.append(result['prediction'])
                if result['probability'] is not None:
                    probabilities.append(result['probability'])
            
            batch_result = {
                'predictions': predictions,
                'probabilities': probabilities if probabilities else None,
                'model_version': self.metadata.get('model_version', 'unknown'),
                'timestamp': datetime.now().isoformat(),
                'processed_count': len(predictions)
            }
            
            logger.info(f"Batch prediction completed: {len(predictions)} instances")
            return batch_result
            
        except Exception as e:
            logger.error(f"Batch prediction failed: {e}")
            raise RuntimeError(f"Batch prediction error: {e}")
    
    def get_health_status(self) -> Dict[str, Any]:
        """Get server health status"""
        uptime = (datetime.now() - self.start_time).total_seconds()
        
        return {
            'status': 'healthy' if self.model is not None else 'unhealthy',
            'model_loaded': self.model is not None,
            'model_version': self.metadata.get('model_version', 'unknown') if self.model else None,
            'uptime_seconds': uptime,
            'last_prediction': self.last_prediction_time.isoformat() if self.last_prediction_time else None,
            'prediction_count': self.prediction_count,
            'algorithm': self.metadata.get('algorithm', 'unknown') if self.model else None,
            'task_type': self.metadata.get('task_type', 'unknown') if self.model else None
        }


# Initialize the server
server = NovaModelServer()

# Create FastAPI app
app = FastAPI(
    title="Nova ML Model Server",
    description="FastAPI-based machine learning model serving with LightGBM/XGBoost support",
    version="1.0.0"
)


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    try:
        health_data = server.get_health_status()
        return HealthResponse(**health_data)
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(status_code=500, detail=f"Health check failed: {e}")


@app.post("/score", response_model=PredictionResponse)
async def score_single(request: PredictionRequest):
    """Single prediction endpoint"""
    try:
        result = server.predict_single(request.features)
        return PredictionResponse(**result)
    except ValueError as e:
        logger.error(f"Invalid input: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Prediction failed: {e}")
        raise HTTPException(status_code=500, detail=f"Prediction failed: {e}")


@app.post("/batch", response_model=BatchPredictionResponse)
async def score_batch(request: BatchPredictionRequest):
    """Batch prediction endpoint"""
    try:
        if not request.instances:
            raise ValueError("No instances provided for batch prediction")
        
        if len(request.instances) > 1000:
            raise ValueError("Batch size too large (max 1000 instances)")
        
        result = server.predict_batch(request.instances)
        return BatchPredictionResponse(**result)
    except ValueError as e:
        logger.error(f"Invalid batch input: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Batch prediction failed: {e}")
        raise HTTPException(status_code=500, detail=f"Batch prediction failed: {e}")


@app.post("/batch/csv")
async def score_csv(file: UploadFile = File(...)):
    """CSV batch prediction endpoint"""
    try:
        if not file.if filename and if filename and filename.endswith('.csv'):
            raise ValueError("File must be a CSV")
        
        # Read CSV
        contents = await file.read()
        df = pd.read_csv(pd.io.common.StringIO(contents.decode('utf-8')))
        
        # Convert to list of dictionaries
        instances = df.to_dict('records')
        
        if len(instances) > 1000:
            raise ValueError("CSV too large (max 1000 rows)")
        
        # Make predictions
        result = server.predict_batch(instances)
        
        # Add predictions to original dataframe
        df['prediction'] = result['predictions']
        if result['probabilities']:
            df['probability'] = result['probabilities']
        
        # Return as JSON
        return {
            'predictions': result,
            'data_with_predictions': df.to_dict('records')
        }
        
    except ValueError as e:
        logger.error(f"Invalid CSV input: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"CSV prediction failed: {e}")
        raise HTTPException(status_code=500, detail=f"CSV prediction failed: {e}")


@app.get("/model/info")
async def model_info():
    """Get model information"""
    try:
        if server.model is None:
            raise HTTPException(status_code=503, detail="Model not loaded")
        
        return {
            'algorithm': server.metadata.get('algorithm', 'unknown'),
            'task_type': server.metadata.get('task_type', 'unknown'),
            'model_version': server.metadata.get('model_version', 'unknown'),
            'feature_names': server.metadata.get('feature_names', []),
            'num_features': server.metadata.get('num_features', 0),
            'trained_at': server.metadata.get('trained_at', 'unknown'),
            'training_samples': server.metadata.get('training_samples', 0)
        }
    except Exception as e:
        logger.error(f"Model info failed: {e}")
        raise HTTPException(status_code=500, detail=f"Model info failed: {e}")


@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """Global exception handler"""
    logger.error(f"Unhandled exception: {exc}")
    logger.error(traceback.format_exc())
    return JSONResponse(
        status_code=500,
        content={
            "detail": "Internal server error",
            "type": type(exc).__name__,
            "timestamp": datetime.now().isoformat()
        }
    )


def main():
    """Run the server"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Nova ML Model Server")
    parser.add_argument("--model", default="model.pkl", help="Path to model file")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
    parser.add_argument("--port", type=int, default=8000, help="Port to bind to")
    parser.add_argument("--workers", type=int, default=1, help="Number of worker processes")
    parser.add_argument("--reload", action="store_true", help="Enable auto-reload for development")
    
    args = parser.parse_args()
    
    # Update server model path
    global server
    server = NovaModelServer(model_path=args.model)
    
    print(f"🚀 Starting Nova ML Model Server")
    print(f"📍 Model: {args.model}")
    print(f"🌐 URL: http://{args.host}:{args.port}")
    print(f"📚 Docs: http://{args.host}:{args.port}/docs")
    print(f"🔍 Health: http://{args.host}:{args.port}/health")
    
    uvicorn.run(
        "serve:app",
        host=args.host,
        port=args.port,
        workers=args.workers,
        reload=args.reload
    )


if __name__ == "__main__":
    main()