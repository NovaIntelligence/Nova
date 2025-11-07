from fastapi.responses import JSONResponse
from fastapi import Request
from __future__ import annotations
#!/usr/bin/env python3
"""
Nova Model Serving API
FastAPI-based model serving with /score endpoint
Supports both LightGBM and XGBoost models
"""

import os
import json
import pickle
import logging
from pathlib import Path
from typing import Dict, List, Any, Optional, Union
from datetime import datetime

import pandas as pd
import numpy as np
from fastapi import FastAPI, HTTPException, Depends, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, validator
import uvicorn

# ML Libraries
try:
    import lightgbm as lgb
    LIGHTGBM_AVAILABLE = True
except ImportError:
    LIGHTGBM_AVAILABLE = False
    
try:
    import xgboost as xgb
    XGBOOST_AVAILABLE = True
except ImportError:
    XGBOOST_AVAILABLE = False

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Global model and schema storage
MODEL = None
SCHEMA = None
MODEL_LOADED = False

# Pydantic models for API
class PredictionRequest(BaseModel):
    """Request model for prediction endpoint"""
    features: Dict[str, Union[float, int, str]] = Field(
        ..., 
        description="Feature values as key-value pairs"
    )
    request_id: Optional[str] = Field(
        None,
        description="Optional request ID for tracking"
    )
    
    @field_validator('features')
    def validate_features(cls, v):
        if not v:
            raise ValueError("Features cannot be empty")
        return v

class BatchPredictionRequest(BaseModel):
    """Request model for batch prediction endpoint"""
    features: List[Dict[str, Union[float, int, str]]] = Field(
        ...,
        description="List of feature dictionaries for batch prediction"
    )
    request_id: Optional[str] = Field(
        None,
        description="Optional request ID for tracking"
    )
    
    @field_validator('features')
    def validate_features(cls, v):
        if not v:
            raise ValueError("Features list cannot be empty")
        if len(v) > 1000:  # Limit batch size
            raise ValueError("Batch size cannot exceed 1000 samples")
        return v

class PredictionResponse(BaseModel):
    """Response model for prediction endpoint"""
    prediction: Union[float, int, List[float]]
    confidence: Optional[float] = None
    request_id: Optional[str] = None
    model_version: str
    timestamp: str
    processing_time_ms: float

class BatchPredictionResponse(BaseModel):
    """Response model for batch prediction endpoint"""
    predictions: List[Union[float, int, List[float]]]
    confidences: Optional[List[float]] = None
    request_id: Optional[str] = None
    model_version: str
    timestamp: str
    processing_time_ms: float
    batch_size: int

class HealthResponse(BaseModel):
    """Response model for health check endpoint"""
    status: str
    model_loaded: bool
    model_type: Optional[str] = None
    model_version: Optional[str] = None
    uptime: str
    timestamp: str

class NovaModelServer:
    """Nova Model Server for handling ML predictions"""
    
    def __init__(self, model_dir: str = "model_output"):
        """
        Initialize the model server
        
        Args:
            model_dir: Directory containing model.pkl and schema.json
        """
        self.model_dir = Path(model_dir)
        self.model = None
        self.schema = None
        self.start_time = datetime.now()
        self.prediction_count = 0
        
    def load_model(self):
        """Load the trained model and schema"""
        global MODEL, SCHEMA, MODEL_LOADED
        
        model_path = self.model_dir / "model.pkl"
        schema_path = self.model_dir / "schema.json"
        
        if not model_path.exists():
            raise FileNotFoundError(f"Model file not found: {model_path}")
        if not schema_path.exists():
            raise FileNotFoundError(f"Schema file not found: {schema_path}")
        
        # Load schema
        with open(schema_path, 'r') as f:
            self.schema = json.load(f)
        SCHEMA = self.schema
        
        # Load model
        with open(model_path, 'rb') as f:
            self.model = pickle.load(f)
        MODEL = self.model
        
        MODEL_LOADED = True
        logger.info(f"Model loaded successfully: {self.schema['model_type']} "
                   f"for {self.schema['task_type']}")
        logger.info(f"Model version: {self.schema.get('model_version', 'unknown')}")
        logger.info(f"Features: {len(self.schema['feature_names'])}")
        
    def preprocess_features(self, features: Dict[str, Any]) -> pd.DataFrame:
        """
        Preprocess input features according to training schema
        
        Args:
            features: Raw feature dictionary
            
        Returns:
            Preprocessed DataFrame ready for prediction
        """
        if not SCHEMA:
            raise RuntimeError("Schema not loaded")
        
        # Create DataFrame from features
        df = pd.DataFrame([features])
        
        # Ensure all required features are present
        required_features = set(SCHEMA['feature_names'])
        provided_features = set(features.keys())
        
        missing_features = required_features - provided_features
        if missing_features:
            raise ValueError(f"Missing required features: {missing_features}")
        
        # Remove extra features not in training data
        extra_features = provided_features - required_features
        if extra_features:
            logger.warning(f"Ignoring extra features: {extra_features}")
            df = df[SCHEMA['feature_names']]
        else:
            # Reorder columns to match training order
            df = df[SCHEMA['feature_names']]
        
        # Handle categorical encoding (same as training)
        if 'categorical_columns' in SCHEMA:
            for col in SCHEMA['categorical_columns']:
                if col in df.columns:
                    # Convert to string first, then to categorical codes
                    df[col] = pd.Categorical(df[col].astype(str)).codes
        
        # Handle missing values (fill with 0 for inference)
        df = df.fillna(0)
        
        return df
    
    def predict(self, features: Dict[str, Any]) -> tuple:
        """
        Make a single prediction
        
        Args:
            features: Feature dictionary
            
        Returns:
            Tuple of (prediction, confidence)
        """
        if not MODEL_LOADED:
            raise RuntimeError("Model not loaded")
        
        # Preprocess features
        X = self.preprocess_features(features)
        
        # Make prediction based on model type
        if SCHEMA['model_type'] == 'lightgbm':
            pred = MODEL.predict(X)[0]
        else:  # xgboost
            dmatrix = xgb.DMatrix(X)
            pred = MODEL.predict(dmatrix)[0]
        
        # Calculate confidence and format prediction
        if SCHEMA['task_type'] == 'classification':
            confidence = abs(pred - 0.5) * 2  # Distance from decision boundary
            prediction = int(pred > 0.5)
        else:
            confidence = None
            prediction = float(pred)
        
        self.prediction_count += 1
        return prediction, confidence
    
    def predict_batch(self, features_list: List[Dict[str, Any]]) -> tuple:
        """
        Make batch predictions
        
        Args:
            features_list: List of feature dictionaries
            
        Returns:
            Tuple of (predictions, confidences)
        """
        if not MODEL_LOADED:
            raise RuntimeError("Model not loaded")
        
        # Preprocess all features
        df_list = [self.preprocess_features(features) for features in features_list]
        X = pd.concat(df_list, ignore_index=True)
        
        # Make predictions based on model type
        if SCHEMA['model_type'] == 'lightgbm':
            predictions = MODEL.predict(X)
        else:  # xgboost
            dmatrix = xgb.DMatrix(X)
            predictions = MODEL.predict(dmatrix)
        
        # Process predictions and confidences
        if SCHEMA['task_type'] == 'classification':
            confidences = [abs(pred - 0.5) * 2 for pred in predictions]
            predictions = [int(pred > 0.5) for pred in predictions]
        else:
            confidences = None
            predictions = [float(pred) for pred in predictions]
        
        self.prediction_count += len(features_list)
        return predictions, confidences

# Initialize the model server
model_server = NovaModelServer()

# Create FastAPI app
app = FastAPI(
    title="Nova Model Serving API",
    description="FastAPI-based model serving for Nova ML models",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup_event():
    """Load model on startup"""
    try:
        model_server.load_model()
        logger.info("Model server started successfully")
    except Exception as e:
        logger.error(f"Failed to load model on startup: {e}")
        # Don't raise here to allow server to start and show error in health check

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    uptime = datetime.now() - model_server.start_time
    
    return HealthResponse(
        status="healthy" if MODEL_LOADED else "unhealthy",
        model_loaded=MODEL_LOADED,
        model_type=SCHEMA.get('model_type') if SCHEMA else None,
        model_version=SCHEMA.get('model_version') if SCHEMA else None,
        uptime=str(uptime),
        timestamp=datetime.now().isoformat()
    )

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "message": "Nova Model Serving API",
        "status": "running",
        "docs": "/docs",
        "health": "/health",
        "score": "/score"
    }

@app.post("/score", response_model=PredictionResponse)
async def score(request: PredictionRequest):
    """
    Score a single sample
    
    Args:
        request: Prediction request with features
        
    Returns:
        Prediction response
    """
    start_time = datetime.now()
    
    try:
        # Make prediction
        prediction, confidence = model_server.predict(request.features)
        
        # Calculate processing time
        processing_time = (datetime.now() - start_time).total_seconds() * 1000
        
        return PredictionResponse(
            prediction=prediction,
            confidence=confidence,
            request_id=request.request_id,
            model_version=SCHEMA.get('model_version', 'unknown'),
            timestamp=datetime.now().isoformat(),
            processing_time_ms=round(processing_time, 2)
        )
        
    except Exception as e:
        logger.error(f"Prediction error: {e}")
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/score/batch", response_model=BatchPredictionResponse)
async def score_batch(request: BatchPredictionRequest):
    """
    Score multiple samples in batch
    
    Args:
        request: Batch prediction request with list of features
        
    Returns:
        Batch prediction response
    """
    start_time = datetime.now()
    
    try:
        # Make batch predictions
        predictions, confidences = model_server.predict_batch(request.features)
        
        # Calculate processing time
        processing_time = (datetime.now() - start_time).total_seconds() * 1000
        
        return BatchPredictionResponse(
            predictions=predictions,
            confidences=confidences,
            request_id=request.request_id,
            model_version=SCHEMA.get('model_version', 'unknown'),
            timestamp=datetime.now().isoformat(),
            processing_time_ms=round(processing_time, 2),
            batch_size=len(request.features)
        )
        
    except Exception as e:
        logger.error(f"Batch prediction error: {e}")
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/model/info")
async def model_info():
    """Get model information"""
    if not MODEL_LOADED:
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    return {
        "model_type": SCHEMA['model_type'],
        "task_type": SCHEMA['task_type'],
        "feature_names": SCHEMA['feature_names'],
        "target_column": SCHEMA['target_column'],
        "model_version": SCHEMA.get('model_version', 'unknown'),
        "training_timestamp": SCHEMA.get('training_timestamp'),
        "metrics": SCHEMA.get('metrics', {}),
        "prediction_count": model_server.prediction_count
    }

@app.post("/model/reload")
async def reload_model():
    """Reload the model from disk"""
    try:
        model_server.load_model()
        return {"message": "Model reloaded successfully"}
    except Exception as e:
        logger.error(f"Model reload error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

def main():
    """Run the server"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Nova Model Serving API")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
    parser.add_argument("--port", type=int, default=8000, help="Port to bind to")
    parser.add_argument("--model-dir", default="model_output", 
                       help="Directory containing model.pkl and schema.json")
    parser.add_argument("--reload", action="store_true", 
                       help="Enable auto-reload for development")
    parser.add_argument("--log-level", default="info",
                       choices=["debug", "info", "warning", "error"],
                       help="Log level")
    
    args = parser.parse_args()
    
    # Update model directory
    model_server.model_dir = Path(args.model_dir)
    
    # Run server
    uvicorn.run(
        "serve:app",
        host=args.host,
        port=args.port,
        reload=args.reload,
        log_level=args.log_level
    )

if __name__ == "__main__":
    main()