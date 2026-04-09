#!/usr/bin/env python3
"""
Run this in your Python environment to prepare for YOLO retraining.
Organize your dataset before running scripts/retrain_yolo.py.
"""
from pathlib import Path

# Ensure datasets directory exists
DATASET_DIR = Path(__file__).resolve().parent.parent / "datasets" / "retrain"
DATASET_DIR.mkdir(parents=True, exist_ok=True)

print("📸 To improve detection accuracy:")
print("1. Collect 100+ new mealybug images from your gallery")
print("2. Use Roboflow or LabelImg to annotate with bounding boxes")
print("3. Export in YOLO format (.zip from Roboflow)")
print("4. Unpack into datasets/:")
print(f"     python scripts/extract_dataset_zip.py <your_export.zip>")
print("   Then train + export TFLite:")
print(f"     python scripts/retrain_yolo.py")
print()
print(f"   Legacy manual folder (optional): {DATASET_DIR}")
print()
print("YOLO dataset structure:")
print("  retrain/")
print("    images/")
print("      train/")
print("      val/")
print("    labels/")
print("      train/")
print("      val/")
print("    data.yaml  (class names, paths)")
