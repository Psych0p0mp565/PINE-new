#!/usr/bin/env python3
"""
Run Ultralytics validation on a trained .pt and print mAP + confidence stats.

Usage (after training):
  python scripts/report_val_metrics.py runs/retrain/mealybug_v2/weights/best.pt

Requires: pip install ultralytics
"""
from __future__ import annotations

import argparse
from pathlib import Path

try:
    from ultralytics import YOLO
except ImportError:
    print("Install: pip install ultralytics")
    raise


def main() -> None:
    parser = argparse.ArgumentParser(description="YOLO val: mAP + box score percentiles.")
    parser.add_argument(
        "weights",
        type=Path,
        help="Path to best.pt",
    )
    parser.add_argument(
        "--data",
        type=Path,
        default=None,
        help="data.yaml (default: <project>/datasets/data.yaml)",
    )
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parent.parent
    data_yaml = args.data or (project_root / "datasets" / "data.yaml")
    weights = args.weights.resolve()

    if not weights.is_file():
        raise SystemExit(f"Weights not found: {weights}")
    if not data_yaml.is_file():
        raise SystemExit(f"data.yaml not found: {data_yaml}")

    model = YOLO(str(weights))
    metrics = model.val(data=str(data_yaml), plots=False, verbose=False)

    # metrics.box maps / P / R — varies slightly by ultralytics version
    box = getattr(metrics, "box", None)
    if box is not None:
        print("--- Box metrics ---")
        for name in ("mp", "map50", "map"):
            v = getattr(box, name, None)
            if v is not None:
                print(f"  {name}: {float(v):.4f}")

    speed = getattr(metrics, "speed", None)
    if speed:
        print("--- Speed (ms) ---", speed)


if __name__ == "__main__":
    main()
