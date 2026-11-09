#!/usr/bin/env python3
"""
tools/train_intent.py - Train Causal Intent Classifier with held-out validation and CoreML export.

Input: 560D sliding-window feature vectors (10 frames x 56D) from tools/data/intent_features.csv
Classes:
  0: idle
  1: hover
  2: pre_click
  3: drag
  4: scroll
"""

import os
import sys
import json
import csv
import argparse
import subprocess
import numpy as np
from sklearn.neural_network import MLPClassifier
from sklearn.metrics import classification_report, confusion_matrix

INTENT_CLASSES = ["idle", "hover", "pre_click", "drag", "scroll"]
CLASS_TO_IDX = {c: i for i, c in enumerate(INTENT_CLASSES)}
WINDOW_SIZE = 10
N_FEATURES = WINDOW_SIZE * 56  # 560


def load_dataset(features_csv: str, split_json: str):
    if not os.path.isfile(features_csv):
        raise FileNotFoundError(f"Features file not found: {features_csv}")
    if not os.path.isfile(split_json):
        raise FileNotFoundError(f"Split file not found: {split_json}")

    with open(split_json, "r") as f:
        split_data = json.load(f)

    train_files = set(split_data.get("train", []))
    test_files = set(split_data.get("test", []))

    X_train_list, y_train_list = [], []
    X_test_list, y_test_list = [], []
    train_sessions_seen, test_sessions_seen = set(), set()

    with open(features_csv, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        meta_cols = 5  # source_file, split, frame_index, timestamp, intent

        for row in reader:
            if len(row) <= meta_cols:
                continue
            src_file = row[0]
            split_tag = row[1]
            intent_name = row[4]

            cls_idx = CLASS_TO_IDX.get(intent_name, 0)
            feats = [float(x) for x in row[meta_cols:]]

            if src_file in train_files or split_tag == "train":
                X_train_list.append(feats)
                y_train_list.append(cls_idx)
                train_sessions_seen.add(src_file)
            else:
                X_test_list.append(feats)
                y_test_list.append(cls_idx)
                test_sessions_seen.add(src_file)

    X_train = np.array(X_train_list, dtype=np.float32) if X_train_list else np.empty((0, N_FEATURES), dtype=np.float32)
    y_train = np.array(y_train_list, dtype=np.int64) if y_train_list else np.empty((0,), dtype=np.int64)
    X_test = np.array(X_test_list, dtype=np.float32) if X_test_list else np.empty((0, N_FEATURES), dtype=np.float32)
    y_test = np.array(y_test_list, dtype=np.int64) if y_test_list else np.empty((0,), dtype=np.int64)

    return X_train, y_train, X_test, y_test, sorted(list(train_sessions_seen)), sorted(list(test_sessions_seen))


def export_coreml_model(mlp: MLPClassifier, output_path: str, n_features: int = 560, n_classes: int = 5):
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

    # Compile with xcrun coremlcompiler if available
    try:
        out_dir = os.path.dirname(os.path.abspath(output_path))
        subprocess.run(["xcrun", "coremlcompiler", "compile", output_path, out_dir], check=True, capture_output=True)
        print(f"[CoreML] Successfully compiled to .mlmodelc in {out_dir}")
    except Exception as e:
        print(f"[CoreML] Note: xcrun coremlcompiler skipped or returned: {e}")

    return True


def main():
    parser = argparse.ArgumentParser(description="Train Causal Intent Classifier with held-out validation.")
    parser.add_argument("--features", default="tools/data/intent_features.csv", help="Path to intent features CSV")
    parser.add_argument("--split", default="tools/data/intent_split.json", help="Path to intent split manifest JSON")
    parser.add_argument("--model-out", default="GestureFlowApp/Resources/IntentClassifier.mlmodel", help="CoreML output path")
    args = parser.parse_args()

    X_train, y_train, X_test, y_test, train_sessions, test_sessions = load_dataset(args.features, args.split)

    total_sessions = len(set(train_sessions + test_sessions))
    print("=================================================================")
    print("        GESTUREFLOW CAUSAL INTENT CLASSIFIER TRAINER             ")
    print("=================================================================")
    print(f"Total distinct recording sessions: {total_sessions}")
    print(f"  - Train sessions ({len(train_sessions)}): {train_sessions}")
    print(f"  - Test sessions  ({len(test_sessions)}): {test_sessions}")
    print(f"Train samples: {len(X_train)} | Held-out test samples: {len(X_test)}")

    if len(X_train) == 0:
        print("[Error] No training samples found. Run tools/generate_intent_sequences.py first.")
        return

    train_counts = {INTENT_CLASSES[i]: int(np.sum(y_train == i)) for i in range(len(INTENT_CLASSES))}
    print("\nTraining Class Distribution:")
    for c, cnt in train_counts.items():
        print(f"  - {c:12s}: {cnt:5d}")

    # Train MLPClassifier (128x64, ReLU)
    print("\nTraining MLPClassifier (128x64, ReLU) on 560D temporal sliding windows...")
    mlp = MLPClassifier(
        hidden_layer_sizes=(128, 64),
        activation="relu",
        max_iter=300,
        random_state=42,
        early_stopping=True if len(X_train) >= 100 else False,
    )
    mlp.fit(X_train, y_train)
    print(f"Training completed in {mlp.n_iter_} iterations.")

    # Held-out evaluation
    if len(X_test) > 0:
        y_pred = mlp.predict(X_test)
        print("\n================ Held-out Test Set Performance ================")
        present_classes = sorted(list(set(y_test) | set(y_pred)))
        target_names = [INTENT_CLASSES[i] for i in present_classes]
        report = classification_report(y_test, y_pred, labels=present_classes, target_names=target_names, zero_division=0)
        print(report)

        cm = confusion_matrix(y_test, y_pred, labels=present_classes)
        print("Confusion Matrix:")
        header_line = " " * 12 + " ".join([f"{c[:7]:>7}" for c in target_names])
        print(header_line)
        for i, row in enumerate(cm):
            row_str = " ".join([f"{val:7d}" for val in row])
            print(f"{target_names[i]:12s} {row_str}")

    # Export Core ML model
    print("\nExporting Core ML model...")
    export_coreml_model(mlp, args.model_out, n_features=N_FEATURES, n_classes=len(INTENT_CLASSES))


if __name__ == "__main__":
    main()
