#!/usr/bin/env python3
"""
Retrain YOLO model with your mealybug dataset, then export to TFLite.
Optimized for limited disk space (30GB free on D: drive)
Requires: pip install ultralytics torch
"""
from pathlib import Path
import argparse
import shutil
import gc

try:
    from ultralytics import YOLO
except ImportError:
    print("Install: pip install ultralytics")
    raise

try:
    import torch
except ImportError:
    print("Install: pip install torch")
    raise


def check_disk_space(path, required_gb=5):
    """Check if there's enough disk space."""
    try:
        import shutil
        total, used, free = shutil.disk_usage(path)
        free_gb = free // (2**30)
        if free_gb < required_gb:
            print(f"⚠ Warning: Only {free_gb}GB free on {path}. Need at least {required_gb}GB.")
            return False
        print(f"✅ {free_gb}GB free on {path} - sufficient for training")
        return True
    except:
        return True


def retrain_model():
    """Retrain YOLO model with new dataset (optimized for low disk space)."""
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent
    
    # Check disk space on D: drive
    check_disk_space(project_root, required_gb=5)
    
    # ⭐ Use your existing dataset
    data_yaml = project_root / "datasets" / "data.yaml"

    if not data_yaml.exists():
        print(f"⚠ data.yaml not found at {data_yaml}")
        return None

    # Clean up any previous training runs to save space
    prev_runs = project_root / "runs" / "retrain"
    if prev_runs.exists():
        print("🧹 Cleaning up previous training runs to save space...")
        shutil.rmtree(prev_runs, ignore_errors=True)
    
    # Quick check of dataset structure
    train_images = project_root / "datasets" / "train" / "images"
    if not train_images.exists():
        print(f"⚠ Train images folder not found at {train_images}")
        return None

    model = YOLO("yolo11n.pt")
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"📊 Training on: {device.upper()}")
    print(f"📁 Using dataset: {data_yaml}")
    print(f"🖼️  Train images: {train_images}")
    print(f"⚠️  OPTIMIZED FOR 30GB DISK SPACE: batch=4, minimal checkpoints")

    # OPTIMIZED SETTINGS FOR LOW DISK SPACE
    results = model.train(
        data=str(data_yaml),
        epochs=100,
        imgsz=640,
        batch=4,                    # Reduced from 16 (saves memory & disk space)
        patience=15,                 # Stop earlier if no improvement
        device=device,
        project=str(project_root / "runs" / "retrain"),
        name="mealybug_v2",
        exist_ok=True,
        save=False,                  # Don't save every epoch checkpoint
        save_period=0,               # Disable periodic saving
        plots=False,                 # Don't generate plots (saves ~50-100MB)
        cache=False,                 # Don't cache images in RAM
        workers=2,                    # Reduce dataloader workers
        amp=True,                     # Use mixed precision (saves memory)
    )

    print(f"✅ Training complete! Best model saved")
    
    # Force garbage collection to free memory
    gc.collect()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()
    
    return results


def export_to_tflite(weights_path=None):
    """Export retrained model to TFLite."""
    project_root = Path(__file__).resolve().parent.parent
    if weights_path is None:
        weights_path = project_root / "runs" / "retrain" / "mealybug_v2" / "weights" / "best.pt"
    weights_path = Path(weights_path)
    
    if not weights_path.exists():
        print(f"⚠ Weights not found: {weights_path}")
        print("Run retrain_model() first.")
        return

    print(f"📦 Exporting model to TFLite...")
    model = YOLO(str(weights_path))
    
    # Export to TFLite (float16 quantized, WITHOUT in-graph NMS).
    # Dart-side code already applies NMS; disabling NMS here avoids
    # extra ops (like PAD) that can fail on some TFLite runtimes.
    model.export(
        format="tflite",
        imgsz=640,
        half=True,        # Float16 quantization (smaller file)
        int8=False,
        nms=False,
    )

    out_dir = weights_path.parent
    tflite_file = out_dir / "best_float16.tflite"
    
    if tflite_file.exists():
        size_mb = tflite_file.stat().st_size / (1024 * 1024)
        print("\n" + "="*50)
        print("✅ MODEL EXPORTED SUCCESSFULLY!")
        print("="*50)
        print(f"📁 TFLite file: {tflite_file}")
        print(f"📊 File size: {size_mb:.2f} MB")
        print("\n📱 NEXT STEPS:")
        print("   1. Copy to Flutter assets:")
        print(f"      copy {tflite_file} assets\\model\\best.tflite")
        print("   2. Clean and rebuild Flutter app:")
        print("      flutter clean")
        print("      flutter pub get")
        print("      flutter build apk --release")
        print("="*50)
    else:
        print("❌ Export failed - TFLite file not found")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="PINE YOLO: train and/or export to TFLite (nms=False for phone).")
    parser.add_argument(
        "--export-only",
        metavar="PATH",
        type=Path,
        default=None,
        help="Only export this .pt file to TFLite (e.g. runs/detect/train3/weights/best.pt). Skips training.",
    )
    args = parser.parse_args()

    if args.export_only is not None:
        print("🚀 PINE YOLO – export only (TFLite with nms=False)")
        print("="*50)
        export_to_tflite(args.export_only)
    else:
        print("🚀 PINE-A-PIC YOLO Retraining (Optimized for 30GB disk space)")
        print("="*50)
        retrain_model()
        export_to_tflite()