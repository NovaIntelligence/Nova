from typing import Protocol, Any

class Transformer(Protocol):
    def fit(self, X: Any, y: Any | None = None) -> Any: ...
    def transform(self, X: Any) -> Any: ...
    def fit_transform(self, X: Any, y: Any | None = None) -> Any: ...
from __future__ import annotations
#!/usr/bin/env python3
"""
Nova ML Training Pipeline - Train-And-Package.py
Supports LightGBM and XGBoost models with comprehensive validation
"""

import json
import pickle
import logging
import argparse
import warnings
from pathlib import Path
from typing import Dict, Any, Optional, Union, Tuple
from datetime import datetime

import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler, LabelEncoder
from sklearn.metrics import accuracy_score, precision_recall_fscore_support, roc_auc_score
from sklearn.metrics import mean_squared_error, mean_absolute_error, r2_score

# Suppress warnings for cleaner output
warnings.filterwarnings('ignore')

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


class NovaModelTrainer:
    """
    Nova ML Model Training Pipeline
    
    Supports both LightGBM and XGBoost algorithms with automatic
    preprocessing, validation, and model export capabilities.
    """
    
    def __init__(self, algorithm: str = "lightgbm", task_type: str = "auto"):
        """
        Initialize the Nova Model Trainer
        
        Args:
            algorithm: "lightgbm" or "xgboost"
            task_type: "classification", "regression", or "auto"
        """
        self.algorithm = algorithm.lower()
        self.task_type = task_type.lower()
        self.model = None
        self.preprocessors = {}
        self.feature_names = []
        self.target_column = None
        self.metadata = {}
        
        # Setup logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s'
        )
        self.logger = logging.getLogger(__name__)
        
        # Validate algorithm availability
        if self.algorithm == "lightgbm" and not LIGHTGBM_AVAILABLE:
            raise ImportError("LightGBM not available. Install with: pip install lightgbm")
        elif self.algorithm == "xgboost" and not XGBOOST_AVAILABLE:
            raise ImportError("XGBoost not available. Install with: pip install xgboost")
        elif self.algorithm not in ["lightgbm", "xgboost"]:
            raise ValueError(f"Unsupported algorithm: {self.algorithm}")
    
    def load_data(self, data_path: Union[str, Path]) -> pd.DataFrame:
        """Load training data from parquet file"""
        data_path = Path(data_path)
        
        if not data_path.exists():
            raise FileNotFoundError(f"Training data not found: {data_path}")
        
        self.logger.info(f"Loading training data from {data_path}")
        
        try:
            df = pd.read_parquet(data_path)
            self.logger.info(f"Loaded {len(df)} rows with {len(df.columns)} columns")
            return df
        except Exception as e:
            raise RuntimeError(f"Failed to load parquet data: {e}")
    
    def detect_task_type(self, y: pd.Series) -> str:
        """Auto-detect if this is a classification or regression task"""
        if self.task_type != "auto":
            return self.task_type
        
        # Check if target is numeric
        if not pd.api.types.is_numeric_dtype(y):
            return "classification"
        
        # Check number of unique values
        unique_ratio = len(y.unique()) / len(y)
        
        if unique_ratio < 0.05 or len(y.unique()) <= 20:
            return "classification"
        else:
            return "regression"
    
    def preprocess_data(self, df: pd.DataFrame, target_col: str) -> Tuple[np.ndarray, np.ndarray]:
        """
        Preprocess the data for training
        
        Args:
            df: Raw dataframe
            target_col: Name of target column
            
        Returns:
            X: Feature matrix
            y: Target array
        """
        self.logger.info("Starting data preprocessing...")
        
        if target_col not in df.columns:
            raise ValueError(f"Target column '{target_col}' not found in data")
        
        self.target_column = target_col
        
        # Separate features and target
        X = df.drop(columns=[target_col])
        y = df[target_col]
        
        # Auto-detect task type
        self.task_type = self.detect_task_type(y)
        self.logger.info(f"Detected task type: {self.task_type}")
        
        # Store original feature names
        self.feature_names = list(X.columns)
        
        # Handle missing values
        X = X.fillna(X.median() if X.select_dtypes(include=[np.number]).shape[1] > 0 else X.mode().iloc[0])
        
        # Encode categorical variables
        categorical_columns = X.select_dtypes(include=['object', 'category']).columns
        
        for col in categorical_columns:
            le = LabelEncoder()
            X[col] = le.fit_transform(X[col].astype(str))
            self.preprocessors[f"label_encoder_{col}"] = le
        
        # Scale features for better convergence
        scaler = StandardScaler()
        X_scaled = scaler.fit_transform(X)
        self.preprocessors['scaler'] = scaler
        
        # Process target variable
        if self.task_type == "classification":
            if not pd.api.types.is_numeric_dtype(y):
                le_target = LabelEncoder()
                y = le_target.fit_transform(y)
                self.preprocessors['target_encoder'] = le_target
        
        self.logger.info(f"Preprocessing complete. Features: {X_scaled.shape[1]}, Samples: {X_scaled.shape[0]}")
        
        return X_scaled, np.array(y)
    
    def train_lightgbm(self, X_train: np.ndarray, y_train: np.ndarray, 
                      X_val: np.ndarray, y_val: np.ndarray) -> Any:
        """Train LightGBM model"""
        self.logger.info("Training LightGBM model...")
        
        # Prepare datasets
        train_data = lgb.Dataset(X_train, label=y_train, feature_name=self.feature_names)
        val_data = lgb.Dataset(X_val, label=y_val, reference=train_data)
        
        # Set parameters based on task type
        if self.task_type == "classification":
            params = {
                'objective': 'binary' if len(np.unique(y_train)) == 2 else 'multiclass',
                'metric': 'binary_logloss' if len(np.unique(y_train)) == 2 else 'multi_logloss',
                'boosting_type': 'gbdt',
                'num_leaves': 31,
                'learning_rate': 0.05,
                'feature_fraction': 0.9,
                'bagging_fraction': 0.8,
                'bagging_freq': 5,
                'verbose': -1,
                'random_state': 42
            }
            
            if len(np.unique(y_train)) > 2:
                params['num_class'] = len(np.unique(y_train))
        else:
            params = {
                'objective': 'regression',
                'metric': 'rmse',
                'boosting_type': 'gbdt',
                'num_leaves': 31,
                'learning_rate': 0.05,
                'feature_fraction': 0.9,
                'bagging_fraction': 0.8,
                'bagging_freq': 5,
                'verbose': -1,
                'random_state': 42
            }
        
        # Train model
        model = lgb.train(
            params,
            train_data,
            valid_sets=[val_data],
            num_boost_round=1000,
            callbacks=[lgb.early_stopping(50), lgb.log_evaluation(0)]
        )
        
        return model
    
    def train_xgboost(self, X_train: np.ndarray, y_train: np.ndarray,
                     X_val: np.ndarray, y_val: np.ndarray) -> Any:
        """Train XGBoost model"""
        self.logger.info("Training XGBoost model...")
        
        # Set parameters based on task type
        if self.task_type == "classification":
            if len(np.unique(y_train)) == 2:
                model = xgb.XGBClassifier(
                    objective='binary:logistic',
                    eval_metric='logloss',
                    n_estimators=1000,
                    max_depth=6,
                    learning_rate=0.05,
                    subsample=0.8,
                    colsample_bytree=0.9,
                    random_state=42,
                    early_stopping_rounds=50
                )
            else:
                model = xgb.XGBClassifier(
                    objective='multi:softprob',
                    eval_metric='mlogloss',
                    n_estimators=1000,
                    max_depth=6,
                    learning_rate=0.05,
                    subsample=0.8,
                    colsample_bytree=0.9,
                    random_state=42,
                    early_stopping_rounds=50
                )
        else:
            model = xgb.XGBRegressor(
                objective='reg:squarederror',
                eval_metric='rmse',
                n_estimators=1000,
                max_depth=6,
                learning_rate=0.05,
                subsample=0.8,
                colsample_bytree=0.9,
                random_state=42,
                early_stopping_rounds=50
            )
        
        # Train model
        model.fit(
            X_train, y_train,
            eval_set=[(X_val, y_val)],
            verbose=False
        )
        
        return model
    
    def evaluate_model(self, model: Any, X_test: np.ndarray, y_test: np.ndarray) -> Dict[str, float]:
        """Evaluate model performance"""
        self.logger.info("Evaluating model performance...")
        
        if self.algorithm == "lightgbm":
            y_pred = model.predict(X_test)
            if self.task_type == "classification" and len(np.unique(y_test)) == 2:
                y_pred_binary = (y_pred > 0.5).astype(int)
            elif self.task_type == "classification":
                y_pred_binary = np.argmax(y_pred, axis=1)
            else:
                y_pred_binary = y_pred
        else:  # xgboost
            if self.task_type == "classification":
                y_pred_proba = model.predict_proba(X_test)
                y_pred_binary = model.predict(X_test)
                y_pred = y_pred_proba[:, 1] if len(np.unique(y_test)) == 2 else y_pred_proba
            else:
                y_pred = model.predict(X_test)
                y_pred_binary = y_pred
        
        metrics = {}
        
        if self.task_type == "classification":
            metrics['accuracy'] = accuracy_score(y_test, y_pred_binary)
            
            # Precision, Recall, F1
            precision, recall, f1, _ = precision_recall_fscore_support(y_test, y_pred_binary, average='weighted')
            metrics['precision'] = precision
            metrics['recall'] = recall
            metrics['f1'] = f1
            
            # ROC AUC (binary classification only)
            if len(np.unique(y_test)) == 2:
                metrics['roc_auc'] = roc_auc_score(y_test, y_pred if self.algorithm == "lightgbm" else y_pred[:, 1])
        
        else:  # regression
            metrics['mse'] = mean_squared_error(y_test, y_pred)
            metrics['mae'] = mean_absolute_error(y_test, y_pred)
            metrics['rmse'] = np.sqrt(metrics['mse'])
            metrics['r2'] = r2_score(y_test, y_pred)
        
        # Log metrics
        for metric, value in metrics.items():
            self.logger.info(f"{metric.upper()}: {value:.4f}")
        
        return metrics
    
    def train(self, data_path: Union[str, Path], target_column: str,
              test_size: float = 0.2, val_size: float = 0.2) -> Dict[str, Any]:
        """
        Main training pipeline
        
        Args:
            data_path: Path to training.parquet file
            target_column: Name of target column
            test_size: Fraction for test set
            val_size: Fraction for validation set
            
        Returns:
            Training results and metrics
        """
        # Load and preprocess data
        df = self.load_data(data_path)
        X, y = self.preprocess_data(df, target_column)
        
        # Split data
        X_temp, X_test, y_temp, y_test = train_test_split(
            X, y, test_size=test_size, random_state=42, stratify=y if self.task_type == "classification" else None
        )
        
        X_train, X_val, y_train, y_val = train_test_split(
            X_temp, y_temp, test_size=val_size/(1-test_size), random_state=42,
            stratify=y_temp if self.task_type == "classification" else None
        )
        
        self.logger.info(f"Data split - Train: {X_train.shape[0]}, Val: {X_val.shape[0]}, Test: {X_test.shape[0]}")
        
        # Train model
        if self.algorithm == "lightgbm":
            self.model = self.train_lightgbm(X_train, y_train, X_val, y_val)
        else:
            self.model = self.train_xgboost(X_train, y_train, X_val, y_val)
        
        # Evaluate model
        metrics = self.evaluate_model(self.model, X_test, y_test)
        
        # Store metadata
        self.metadata = {
            'algorithm': self.algorithm,
            'task_type': self.task_type,
            'feature_names': self.feature_names,
            'target_column': self.target_column,
            'preprocessors': list(self.preprocessors.keys()),
            'metrics': metrics,
            'training_samples': X_train.shape[0],
            'validation_samples': X_val.shape[0],
            'test_samples': X_test.shape[0],
            'num_features': X_train.shape[1],
            'trained_at': datetime.now().isoformat(),
            'model_version': "1.0.0"
        }
        
        return {
            'model': self.model,
            'metrics': metrics,
            'metadata': self.metadata
        }
    
    def save_model(self, model_path: Union[str, Path] = "model.pkl"):
        """Save trained model and preprocessors"""
        if self.model is None:
            raise ValueError("No model trained yet. Call train() first.")
        
        model_path = Path(model_path)
        
        # Package everything together
        model_package = {
            'model': self.model,
            'preprocessors': self.preprocessors,
            'metadata': self.metadata
        }
        
        with open(model_path, 'wb') as f:
            pickle.dump(model_package, f)
        
        self.logger.info(f"Model saved to {model_path}")
    
    def save_schema(self, schema_path: Union[str, Path] = "schema.json"):
        """Save model schema and metadata"""
        if self.metadata is None:
            raise ValueError("No metadata available. Train model first.")
        
        schema_path = Path(schema_path)
        
        schema = {
            'model_info': {
                'algorithm': self.metadata['algorithm'],
                'task_type': self.metadata['task_type'],
                'version': self.metadata['model_version'],
                'trained_at': self.metadata['trained_at']
            },
            'data_info': {
                'feature_names': self.metadata['feature_names'],
                'target_column': self.metadata['target_column'],
                'num_features': self.metadata['num_features'],
                'training_samples': self.metadata['training_samples']
            },
            'performance': self.metadata['metrics'],
            'preprocessing': {
                'steps': self.metadata['preprocessors'],
                'feature_scaling': 'StandardScaler' in self.metadata['preprocessors']
            }
        }
        
        with open(schema_path, 'w') as f:
            json.dump(schema, f, indent=2)
        
        self.logger.info(f"Schema saved to {schema_path}")


def main():
    """Command line interface"""
    parser = argparse.ArgumentParser(description="Nova ML Training Pipeline")
    parser.add_argument("--data", required=True, help="Path to training.parquet file")
    parser.add_argument("--target", required=True, help="Target column name")
    parser.add_argument("--algorithm", choices=["lightgbm", "xgboost"], default="lightgbm",
                       help="ML algorithm to use")
    parser.add_argument("--task", choices=["classification", "regression", "auto"], default="auto",
                       help="Task type (auto-detected if not specified)")
    parser.add_argument("--model-output", default="model.pkl", help="Output path for model")
    parser.add_argument("--schema-output", default="schema.json", help="Output path for schema")
    parser.add_argument("--test-size", type=float, default=0.2, help="Test set size (0.0-1.0)")
    parser.add_argument("--val-size", type=float, default=0.2, help="Validation set size (0.0-1.0)")
    
    args = parser.parse_args()
    
    try:
        # Initialize trainer
        trainer = NovaModelTrainer(algorithm=args.algorithm, task_type=args.task)
        
        # Train model
        results = trainer.train(
            data_path=args.data,
            target_column=args.target,
            test_size=args.test_size,
            val_size=args.val_size
        )
        
        # Save outputs
        trainer.save_model(args.model_output)
        trainer.save_schema(args.schema_output)
        
        print("\n" + "="*50)
        print("🎯 NOVA ML TRAINING COMPLETE!")
        print("="*50)
        print(f"Algorithm: {trainer.algorithm.upper()}")
        print(f"Task Type: {trainer.task_type.title()}")
        print(f"Model saved: {args.model_output}")
        print(f"Schema saved: {args.schema_output}")
        print("\nPerformance Metrics:")
        for metric, value in results['metrics'].items():
            print(f"  {metric.upper()}: {value:.4f}")
        print("="*50)
        
    except Exception as e:
        print(f"❌ Training failed: {e}")
        exit(1)


if __name__ == "__main__":
    main()