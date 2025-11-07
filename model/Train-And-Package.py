from __future__ import annotations
from typing import Any, Dict, List, Optional, Sequence, Mapping, Set, Tuple, Union, cast
import numpy as np
#!/usr/bin/env python3
"""
Nova Model Training and Packaging Script
Supports both LightGBM and XGBoost for training from parquet data
Exports trained model and schema for serving
"""

import os
import json
import pickle
import argparse
import logging
from pathlib import Path
from typing import Dict, Any, Optional
from datetime import datetime

import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report, mean_squared_error, r2_score

# ML Libraries
try:
    import lightgbm as lgb
    __lightgbm_available = True
except ImportError:
    __lightgbm_available = False
    
try:
    import xgboost as xgb
    __xgboost_available = True
except ImportError:
    __xgboost_available = False

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class NovaModelTrainer:
    """Nova Model Trainer supporting LightGBM and XGBoost"""
    
    def __init__(self, 
                 model_type: str = "lightgbm",
                 task_type: str = "classification",
                 random_state: int = 42):
        """
        Initialize the trainer
        
        Args:
            model_type: "lightgbm" or "xgboost"
            task_type: "classification" or "regression"
            random_state: Random seed for reproducibility
        """
        self.model_type = model_type.lower()
        self.task_type = task_type.lower()
        self.random_state = random_state
        self.model: Optional[Any] = None
        self.feature_names = None
        self.target_column = None
        self.schema: Dict[str, Any] = {}
        
        # Validate model availability
        if self.model_type == "lightgbm" and not _lightgbm_available:
            raise ImportError("LightGBM not available. Install with: pip install lightgbm")
        elif self.model_type == "xgboost" and not _xgboost_available:
            raise ImportError("XGBoost not available. Install with: pip install xgboost")
        elif self.model_type not in ["lightgbm", "xgboost"]:
            raise ValueError(f"Unsupported model type: {self.model_type}")
            
        if self.task_type not in ["classification", "regression"]:
            raise ValueError(f"Unsupported task type: {self.task_type}")
    
    def load_data(self, data_path: str, target_column: str) -> Tuple[pd.DataFrame, pd.Series]:
        """
        Load training data from parquet file
        
        Args:
            data_path: Path to training.parquet file
            target_column: Name of the target column
            
        Returns:
            Features and target data
        """
        logger.info(f"Loading data from {data_path}")
        
        if not os.path.exists(data_path):
            raise FileNotFoundError(f"Training data not found at {data_path}")
        
        # Load parquet file
        df = pd.read_parquet(data_path)
        logger.info(f"Loaded data shape: {df.shape}")
        
        # Validate target column
        if target_column not in df.columns:
            raise ValueError(f"Target column '{target_column}' not found in data")
        
        # Split features and target
        X = df.drop(columns=[target_column])
        y = df[target_column]
        
        self.target_column = target_column
        self.feature_names = list(X.columns)
        
        logger.info(f"Features: {len(X.columns)}, Target: {target_column}")
        logger.info(f"Target distribution:\n{y.value_counts() if self.task_type == 'classification' else y.describe()}")
        
        return X, y
    
    def preprocess_data(self, X: pd.DataFrame, y: pd.Series) -> Tuple[pd.DataFrame, pd.Series]:
        """
        Preprocess the data (handle missing values, encode categoricals, etc.)
        
        Args:
            X: Feature data
            y: Target data
            
        Returns:
            Preprocessed features and target
        """
        logger.info("Preprocessing data...")
        
        # Handle missing values
        if X.isnull().sum().sum() > 0:
            logger.warning(f"Found {X.isnull().sum().sum()} missing values, filling with median/mode")
            for col in X.columns:
                if X[col].dtype in ['object', 'category']:
                    X[col] = X[col].fillna(X[col].mode().iloc[0] if not X[col].mode().empty else 'unknown')
                else:
                    X[col] = X[col].fillna(X[col].median())
        
        # Encode categorical variables
        categorical_columns = X.select_dtypes(include=['object', 'category']).columns
        if len(categorical_columns) > 0:
            logger.info(f"Encoding categorical columns: {list(categorical_columns)}")
            for col in categorical_columns:
                X[col] = pd.Categorical(X[col]).codes
        
        # Store preprocessing schema
        self.schema['feature_names'] = self.feature_names
        self.schema['categorical_columns'] = list(categorical_columns)
        self.schema['target_column'] = self.target_column
        self.schema['task_type'] = self.task_type
        self.schema['model_type'] = self.model_type
        
        return X, y
    
    def train_model(self, X: pd.DataFrame, y: pd.Series, **model_params: Any) -> None:
        """
        Train the model using specified algorithm
        
        Args:
            X: Feature data
            y: Target data
            **model_params: Additional model parameters
        """
        logger.info(f"Training {self.model_type} model for {self.task_type}")
        
        # Split data for validation
        # Split data with proper typing
        split_result = train_test_split(
            X, y, test_size=0.2, random_state=self.random_state, 
            stratify=y if self.task_type == 'classification' else None
        )
        
        if self.model_type == "lightgbm":
            self._train_lightgbm(X_train, y_train, X_val, y_val, **model_params)
        elif self.model_type == "xgboost":
            self._train_xgboost(X_train, y_train, X_val, y_val, **model_params)
        
        # Evaluate on validation set
        self._evaluate_model(X_val, y_val)
    
    def _train_lightgbm(self, X_train: pd.DataFrame, y_train: pd.Series, X_val: pd.DataFrame, y_val: pd.Series, **params: Any) -> None:
        """Train LightGBM model"""
        default_params: Dict[str, Any] = {
            'objective': 'binary' if self.task_type == 'classification' else 'regression',
            'metric': 'binary_logloss' if self.task_type == 'classification' else 'rmse',
            'boosting_type': 'gbdt',
            'num_leaves': 31,
            'learning_rate': 0.05,
            'feature_fraction': 0.9,
            'bagging_fraction': 0.8,
            'bagging_freq': 5,
            'verbose': -1,
            'random_state': self.random_state
        }
        default_params.update(params)
        
        # Create datasets
        train_data = lgb.Dataset(  # type: ignore[attr-defined]X_train, label=y_train)
        val_data = lgb.Dataset(  # type: ignore[attr-defined]X_val, label=y_val, reference=train_data)
        
        # Train model
                # Create LightGBM datasets
        train_data = lgb.Dataset(X_train, label=y_train)  # type: ignore[attr-defined]
        val_data = lgb.Dataset(X_val, label=y_val, reference=train_data)  # type: ignore[attr-defined]
        
        # Train model
        self.model = lgb.train(  # type: ignore[attr-defined]  # type: ignore[attr-defined]
            default_params,
            train_data,
            valid_sets=[val_data],
            num_boost_round=100,
            callbacks=[lgb.early_stopping(10), lgb.log_evaluation(0)]
        )
    
    def _train_xgboost(self, X_train, y_train, X_val, y_val, **params):
        """Train XGBoost model"""
        default_params: Dict[str, Any] = {
            'objective': 'binary:logistic' if self.task_type == 'classification' else 'reg:squarederror',
            'eval_metric': 'logloss' if self.task_type == 'classification' else 'rmse',
            'max_depth': 6,
            'learning_rate': 0.1,
            'subsample': 0.8,
            'colsample_bytree': 0.8,
            'random_state': self.random_state,
            'verbosity': 0
        }
        default_params.update(params)
        
        # Create DMatrix
        dtrain = xgb.DMatrix(  # type: ignore[attr-defined]X_train, label=y_train)
        dval = xgb.DMatrix(  # type: ignore[attr-defined]X_val, label=y_val)
        
        # Train model
        self.model = xgb.train(  # type: ignore[attr-defined]
            default_params,
            dtrain,
            num_boost_round=100,
            evals=[(dval, 'validation')],
            early_stopping_rounds=10,
            verbose_eval=False
        )
    
    def _evaluate_model(self, X_val, y_val):
        """Evaluate model performance"""
        logger.info("Evaluating model performance...")
        
        # Make predictions
        if self.model_type == "lightgbm":
            y_pred: Any = self.model.predict(  # type: ignore[union-attr]X_val)
        else:  # xgboost
            dval = xgb.DMatrix(  # type: ignore[attr-defined]X_val)
            y_pred: Any = self.model.predict(  # type: ignore[union-attr]dval)
        
        if self.task_type == 'classification':
            # Convert probabilities to predictions
            y_pred_array = np.asarray(y_pred)
            y_pred_class = (y_pred_array > 0.5).astype(int)
            accuracy = accuracy_score(y_val, y_pred_class)
            logger.info(f"Validation Accuracy: {accuracy:.4f}")
            logger.info(f"Classification Report:\n{classification_report(y_val, y_pred_class)}")
            
            self.schema['metrics'] = {
                'accuracy': float(accuracy),
                'validation_size': len(y_val)
            }
        else:
            # Regression metrics
            mse = mean_squared_error(y_val, y_pred)
            r2 = r2_score(y_val, y_pred)
            logger.info(f"Validation MSE: {mse:.4f}")
            logger.info(f"Validation R²: {r2:.4f}")
            
            self.schema['metrics'] = {
                'mse': float(mse),
                'r2': float(r2),
                'validation_size': len(y_val)
            }
    
    def save_model_and_schema(self, output_dir: str = "model_output"):
        """
        Save the trained model and schema to files
        
        Args:
            output_dir: Directory to save model and schema files
        """
        if self.model is None:
            raise ValueError("No model to save. Train a model first.")
        
        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)
        
        # Save model
        model_path = output_path / "model.pkl"
        with open(model_path, 'wb') as f:
            pickle.dump(self.model, f)
        logger.info(f"Model saved to {model_path}")
        
        # Update schema with metadata
        self.schema.update({
            'model_path': str(model_path),
            'training_timestamp': datetime.now().isoformat(),
            'model_version': '1.0.0',
            'nova_model_trainer_version': '1.0.0'
        })
        
        # Save schema
        schema_path = output_path / "schema.json"
        with open(schema_path, 'w') as f:
            json.dump(self.schema, f, indent=2)
        logger.info(f"Schema saved to {schema_path}")
        
        return model_path, schema_path

def main():
    """Main training script"""
    parser = argparse.ArgumentParser(description="Nova Model Training Script")
    parser.add_argument("--data", default="training.parquet", 
                       help="Path to training data parquet file")
    parser.add_argument("--target", required=True,
                       help="Target column name")
    parser.add_argument("--model-type", choices=["lightgbm", "xgboost"], 
                       default="lightgbm", help="Model type to use")
    parser.add_argument("--task-type", choices=["classification", "regression"],
                       default="classification", help="Task type")
    parser.add_argument("--output-dir", default="model_output",
                       help="Output directory for model and schema")
    parser.add_argument("--random-seed", type=int, default=42,
                       help="Random seed for reproducibility")
    
    args = parser.parse_args()
    
    try:
        # Initialize trainer
        trainer = NovaModelTrainer(
            model_type=args.model_type,
            task_type=args.task_type,
            random_state=args.random_seed
        )
        
        # Load and preprocess data
        X, y = trainer.load_data(args.data, args.target)
        X, y = trainer.preprocess_data(X, y)
        
        # Train model
        trainer.train_model(X, y)
        
        # Save model and schema
        model_path, schema_path = trainer.save_model_and_schema(args.output_dir)
        
        logger.info("Training completed successfully!")
        logger.info(f"Model saved to: {model_path}")
        logger.info(f"Schema saved to: {schema_path}")
        
    except Exception as e:
        logger.error(f"Training failed: {str(e)}")
        raise

if __name__ == "__main__":
    main()
