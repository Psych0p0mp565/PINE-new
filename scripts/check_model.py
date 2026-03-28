#!/usr/bin/env python3
"""
Pre-flight check for PINE: verifies trained model, export, and Flutter asset.
Run from project root with venv activated:
  python scripts/check_model.py
"""
import os
import sys
from pathlib import Path

# Project root = parent of scripts/
ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)

def ok(msg):
    print(f"  [OK] {msg}")

def fail(msg):
    print(f"  [FAIL] {msg}")

def section(title):
    print(f"\n--- {title} ---")

def main():
    errors = []

    # 1. Check training weights exist
    section("1. Trained weights (.pt)")
    candidates = [
        ROOT / "runs" / "detect" / "train" / "weights" / "best.pt",
        ROOT / "runs" / "detect" / "train" / "weights" / "last.pt",
        ROOT / "runs" / "detect" / "train2" / "weights" / "best.pt",
        ROOT / "runs" / "detect" / "train2" / "weights" / "last.pt",
    ]
    best_pt = None
    for p in candidates:
        if p.exists():
            best_pt = p
            ok(f"Found: {p.relative_to(ROOT)}")
            break
    if not best_pt:
        fail("No best.pt or last.pt found in runs/detect/train/weights or train2/weights")
        errors.append("Missing trained weights")
    else:
        print(f"  Use for export: {best_pt}")

    # 2. Quick model load check (catches missing deps / wrong format)
    section("2. Model load check")
    if best_pt:
        try:
            from ultralytics import YOLO
            model = YOLO(str(best_pt))
            ok("Model loads successfully")
        except Exception as e:
            fail(f"Load error: {e}")
            errors.append(str(e))

    # 3. TFLite export
    section("3. TFLite export")
    tflite_path = (best_pt.parent / "best_float16.tflite") if best_pt else None
    if best_pt and (tflite_path is None or not tflite_path.exists()):
        print("  Exporting to TFLite...")
        try:
            from ultralytics import YOLO
            model = YOLO(str(best_pt))
            model.export(format="tflite", imgsz=640, half=True)
            found = list(best_pt.parent.glob("*.tflite"))
            if found:
                tflite_path = found[0]
                ok(f"Exported: {tflite_path.relative_to(ROOT)}")
            else:
                fail("Export did not create a .tflite file in weights folder")
                errors.append("TFLite export failed")
        except Exception as e:
            fail(f"Export error: {e}")
            errors.append(str(e))
    else:
        if best_pt:
            existing = list(best_pt.parent.glob("*.tflite"))
            if existing:
                tflite_path = existing[0]
                ok(f"Already exists: {tflite_path.relative_to(ROOT)}")

    # 4. Flutter asset
    section("4. Flutter asset")
    asset_dir = ROOT / "assets" / "model"
    asset_file = asset_dir / "best.tflite"
    if tflite_path and tflite_path.exists():
        if not asset_file.exists():
            fail(f"Copy TFLite to app: copy \"{tflite_path}\" \"{asset_file}\"")
            errors.append("best.tflite not in assets/model/")
        else:
            ok(f"Asset present: assets/model/best.tflite")
        if not asset_dir.exists():
            fail("assets/model/ directory missing")
            errors.append("assets/model/ missing")
    else:
        fail("No TFLite file to copy (run export first)")

    # 5. Data config (classes match)
    section("5. Dataset config")
    data_yaml = ROOT / "datasets" / "data.yaml"
    if data_yaml.exists():
        ok("datasets/data.yaml exists")
    else:
        fail("datasets/data.yaml not found")
        errors.append("data.yaml missing")

    # Summary
    section("Summary")
    if errors:
        print("  Errors found:", len(errors))
        for e in errors:
            print(f"    - {e}")
        print("\n  Fix the items above, then run the app.")
        return 1
    print("  All checks passed. You can run: flutter run")
    return 0

if __name__ == "__main__":
    sys.exit(main())
