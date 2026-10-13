#!/usr/bin/env python3
"""
tools/train_posture.py - Posture Classifier trainer with held-out validation and diversity gating.

Features:
- Reads exported features CSV and session split manifest.
- Enforces data diversity gate: requires >= 3 distinct recording sessions to prevent overfitting/leakage.
- Trains MLPClassifier (2x64, ReLU) on training split.
- Reports per-class precision, recall, F1, class balance, and confusion matrix on held-out split only.
- Exports Core ML (.mlmodel) via coremltools MIL builder when diversity gate passes.
"""

import os
import sys
import json
import csv
import argparse
from typing import List, Dict, Tuple, Any

import numpy as np
from sklearn.neural_network import MLPClassifier
from sklearn.metrics import classification_report, confusion_matrix

POSTURE_CLASSES = ["none", "open_palm", "pinch", "two_fingers", "fist"]
CLASS_TO_IDX = {c: i for i, c in enumerate(POSTURE_CLASSES)}


def load_dataset(features_csv: str, split_json: str) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, List[str], List[str]]:
    if not os.path.exists(features_csv):
        raise FileNotFoundError(f"Features file not found: {features_csv}")
    if not os.path.exists(split_json):
        raise FileNotFoundError(f"Split file not found: {split_json}")

    with open(split_json, "r", encoding="utf-8") as f:
        split_meta = json.load(f)

    train_files = set(split_meta.get("train_files", []))
    test_files = set(split_meta.get("test_files", []))

    X_train_list: List[List[float]] = []
    y_train_list: List[int] = []
    X_test_list: List[List[float]] = []
    y_test_list: List[int] = []

    train_sessions_seen: set = set()
    test_sessions_seen: set = set()

    with open(features_csv, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        # header: source_file, split, frame_index, timestamp, raw_label, posture_class, feat_0, ...
        meta_cols = 6

        for row in reader:
            if len(row) <= meta_cols:
                continue
            src_file = row[0]
            split_tag = row[1]
            cls_name = row[5]

            cls_idx = CLASS_TO_IDX.get(cls_name, 0)
            feats = [float(x) for x in row[meta_cols:]]

            if src_file in train_files or split_tag == "train":
                X_train_list.append(feats)
                y_train_list.append(cls_idx)
                train_sessions_seen.add(src_file)
            else:
                X_test_list.append(feats)
                y_test_list.append(cls_idx)
                test_sessions_seen.add(src_file)

    X_train = np.array(X_train_list, dtype=np.float32) if X_train_list else np.empty((0, 56), dtype=np.float32)
    y_train = np.array(y_train_list, dtype=np.int64) if y_train_list else np.empty((0,), dtype=np.int64)
    X_test = np.array(X_test_list, dtype=np.float32) if X_test_list else np.empty((0, 56), dtype=np.float32)
    y_test = np.array(y_test_list, dtype=np.int64) if y_test_list else np.empty((0,), dtype=np.int64)

    return X_train, y_train, X_test, y_test, sorted(list(train_sessions_seen)), sorted(list(test_sessions_seen))


def export_coreml_model(mlp: MLPClassifier, output_path: str, n_features: int = 56, n_classes: int = 5):
    """
    Builds and saves a Core ML NeuralNetwork model using coremltools MIL builder.
    """
    try:
        import coremltools as ct
        from coremltools.converters.mil import Builder as mb
    except ImportError as e:
        print(f"[Error] coremltools not available: {e}")
        return False

    w0 = mlp.coefs_[0].T.astype(np.float32)       # (hidden1, in_features)
    b0 = mlp.intercepts_[0].astype(np.float32)   # (hidden1,)
    w1 = mlp.coefs_[1].T.astype(np.float32)       # (hidden2, hidden1)
    b1 = mlp.intercepts_[1].astype(np.float32)   # (hidden2,)
    w2 = mlp.coefs_[2].T.astype(np.float32)       # (n_classes, hidden2)
    b2 = mlp.intercepts_[2].astype(np.float32)   # (n_classes,)

    @mb.program(input_specs=[mb.TensorSpec(shape=(1, n_features), dtype=ct.converters.mil.mil.types.fp32)])
    def prog(features):
        x = mb.linear(x=features, weight=w0, bias=b0)
        x = mb.relu(x=x)
        x = mb.linear(x=x, weight=w1, bias=b1)
        x = mb.relu(x=x)
        x = mb.linear(x=x, weight=w2, bias=b2)
        probs = mb.softmax(x=x, axis=-1)
        return probs

    mlmodel = ct.convert(prog, convert_to="neuralnetwork")
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    mlmodel.save(output_path)
    print(f"[CoreML] Successfully exported model to {output_path}")
    return True


def main():
    parser = argparse.ArgumentParser(description="Train posture classifier with held-out validation.")
    parser.add_argument("--features", default="tools/data/features.csv", help="Path to features CSV")
    parser.add_argument("--split", default="tools/data/split.json", help="Path to split manifest JSON")
    parser.add_argument("--model-out", default="GestureFlowApp/Sources/GestureFlow/Resources/PostureClassifier.mlmodel", help="CoreML model output path")
    parser.add_argument("--min-sessions", type=int, default=3, help="Minimum distinct sessions required to pass diversity gate")
    parser.add_argument("--force", action="store_true", help="Force training and export even if diversity gate fails (for synthetic test verification only)")
    args = parser.parse_args()

    X_train, y_train, X_test, y_test, train_sessions, test_sessions = load_dataset(args.features, args.split)

    total_sessions = len(set(train_sessions + test_sessions))
    print("=================================================================")
    print("           GESTUREFLOW POSTURE CLASSIFIER TRAINER                ")
    print("=================================================================")
    print(f"Total distinct recording sessions found: {total_sessions}")
    print(f"  - Train sessions ({len(train_sessions)}): {train_sessions}")
    print(f"  - Test sessions  ({len(test_sessions)}): {test_sessions}")
    print(f"Train samples: {len(X_train)} | Held-out test samples: {len(X_test)}")

    diversity_passed = total_sessions >= args.min_sessions
    if not diversity_passed:
        print("\n" + "=" * 69)
        print(f"!!! INSUFFICIENT DIVERSITY: {total_sessions} session(s) found (< {args.min_sessions} required) !!!")
        print("Refusing to export posture model without sufficient dataset diversity.")
        print("Real diverse data required: run 'GestureFlow --guided' across multiple")
        print("sessions, subjects, and lighting conditions before model export.")
        print("=" * 69 + "\n")
        if not args.force:
            print("[Info] Data gate halted model export as specified in WP7.2.")
            return

    if len(X_train) == 0:
        print("[Error] No training samples found. Export features first.")
        return

    # Check class representation
    train_counts = {POSTURE_CLASSES[i]: int(np.sum(y_train == i)) for i in range(len(POSTURE_CLASSES))}
    print("\nTraining Class Distribution:")
    for c, cnt in train_counts.items():
        print(f"  - {c:12s}: {cnt:5d}")

    # Train MLPClassifier
    print("\nTraining MLPClassifier (2x64, ReLU)...")
    mlp = MLPClassifier(
        hidden_layer_sizes=(64, 64),
        activation="relu",
        max_iter=300,
        random_state=42,
        early_stopping=True if len(X_train) >= 50 else False,
    )
    mlp.fit(X_train, y_train)
    print(f"Training completed in {mlp.n_iter_} iterations.")

    # Held-out evaluation
    if len(X_test) > 0:
        y_pred = mlp.predict(X_test)
        print("\n================ Held-out Test Set Performance ================")
        present_classes = sorted(list(set(y_test) | set(y_pred)))
        target_names = [POSTURE_CLASSES[i] for i in present_classes]
        report = classification_report(y_test, y_pred, labels=present_classes, target_names=target_names, zero_division=0)
        print(report)

        cm = confusion_matrix(y_test, y_pred, labels=present_classes)
        print("Confusion Matrix:")
        print(f"{'':12s} " + " ".join([f"{name[:6]:>7s}" for name in target_names]))
        for idx, row in enumerate(cm):
            row_str = " ".join([f"{val:7d}" for val in row])
            print(f"{target_names[idx]:12s} {row_str}")
        print("================================================================")
    else:
        print("[Notice] Held-out test set is empty.")

    # Model export
    if diversity_passed or args.force:
        print(f"\nExporting Core ML model to {args.model_out}...")
        export_coreml_model(mlp, args.model_out, n_features=X_train.shape[1], n_classes=len(POSTURE_CLASSES))


if __name__ == "__main__":
    main()
