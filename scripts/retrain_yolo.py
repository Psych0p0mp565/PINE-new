#!/usr/bin/env python3
"""
Retrain YOLO model with your mealybug dataset, then export to TFLite.
Optimized for limited disk space (30GB free on D: drive).
Default 50 epochs per run; use --resume with a higher --epochs for more total (e.g. 100).
After a finished run, Ultralytics strips last.pt; this script continues with an extra training leg automatically.
Requires: pip install ultralytics torch
"""
from __future__ import annotations

from pathlib import Path
import argparse
import importlib.util
import sys
import shutil
import gc
import re

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


def _auto_batch_size() -> int:
    """Pick a safe default batch size for GPU VRAM (YOLO11n @ 640 is tight on 4GB)."""
    if not torch.cuda.is_available():
        return 2
    try:
        gb = torch.cuda.get_device_properties(0).total_memory / (1024**3)
    except Exception:
        return 2
    if gb < 6.0:
        return 1
    if gb < 10.0:
        return 2
    return 4


def _gpu_vram_gb() -> float | None:
    if not torch.cuda.is_available():
        return None
    try:
        return float(torch.cuda.get_device_properties(0).total_memory / (1024**3))
    except Exception:
        return None


def _patch_ultralytics_val_batch_no_double() -> object:
    """Ultralytics doubles val batch for detect (train batch 1 → val batch 2), which OOMs on 4GB GPUs.

    Returns the original BaseTrainer._build_train_pipeline for restoration.
    """
    import math

    from ultralytics.engine.trainer import BaseTrainer
    from ultralytics.utils import LOCAL_RANK

    _orig = BaseTrainer._build_train_pipeline

    def _patched(self):
        batch_size = self.batch_size // max(self.world_size, 1)
        self.train_loader = self.get_dataloader(
            self.data["train"], batch_size=batch_size, rank=LOCAL_RANK, mode="train"
        )
        self.test_loader = self.get_dataloader(
            self.data.get("val") or self.data.get("test"),
            batch_size=batch_size,
            rank=LOCAL_RANK,
            mode="val",
        )
        self.accumulate = max(round(self.args.nbs / self.batch_size), 1)
        weight_decay = self.args.weight_decay * self.batch_size * self.accumulate / self.args.nbs
        iterations = math.ceil(len(self.train_loader.dataset) / max(self.batch_size, self.args.nbs)) * self.epochs
        self.optimizer = self.build_optimizer(
            model=self.model,
            name=self.args.optimizer,
            lr=self.args.lr0,
            momentum=self.args.momentum,
            decay=weight_decay,
            iterations=iterations,
        )
        self._setup_scheduler()

    BaseTrainer._build_train_pipeline = _patched
    return _orig


def _restore_ultralytics_val_batch(orig) -> None:
    from ultralytics.engine.trainer import BaseTrainer

    BaseTrainer._build_train_pipeline = orig


def _patch_detection_val_no_rect() -> object:
    """Ultralytics defaults to rect=True for val; square val reduces worst-case VRAM on 4GB GPUs."""

    from ultralytics.data import build_yolo_dataset
    from ultralytics.models.yolo.detect.train import DetectionTrainer
    from ultralytics.utils.torch_utils import unwrap_model

    _orig = DetectionTrainer.build_dataset

    def _patched(self, img_path: str, mode: str = "train", batch: int | None = None):
        gs = max(int(unwrap_model(self.model).stride.max()), 32)
        # Original uses rect=True for val only; forcing False avoids rare OOM on small GPUs.
        return build_yolo_dataset(self.args, img_path, batch, self.data, mode=mode, rect=False, stride=gs)

    DetectionTrainer.build_dataset = _patched
    return _orig


def _restore_detection_build_dataset(orig) -> None:
    from ultralytics.models.yolo.detect.train import DetectionTrainer

    DetectionTrainer.build_dataset = orig


def _load_extract_module():
    """Load scripts/extract_dataset_zip.py as a module (works when cwd != scripts/)."""
    script_dir = Path(__file__).resolve().parent
    path = script_dir / "extract_dataset_zip.py"
    spec = importlib.util.spec_from_file_location("extract_dataset_zip", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _default_last_checkpoint(project_root: Path) -> Path:
    return project_root / "runs" / "retrain" / "mealybug_v2" / "weights" / "last.pt"


def _torch_load_ckpt(path: Path) -> dict:
    """Load an Ultralytics .pt checkpoint as a dict (needs full dict, not weights_only)."""
    try:
        return torch.load(path, map_location="cpu", weights_only=False)
    except TypeError:
        return torch.load(path, map_location="cpu")


def _checkpoint_optimizer_present(ckpt: dict) -> bool:
    opt = ckpt.get("optimizer")
    if opt is None:
        return False
    if isinstance(opt, dict) and len(opt) == 0:
        return False
    return True


def _checkpoint_can_ultralytics_resume(ckpt: dict) -> bool:
    """Ultralytics strips last.pt/best.pt at end of training (epoch=-1, no optimizer). Those cannot resume."""
    ep = ckpt.get("epoch", -1)
    try:
        ep_i = int(ep) if ep is not None else -1
    except (TypeError, ValueError):
        ep_i = -1
    return ep_i >= 0 and _checkpoint_optimizer_present(ckpt)


def _last_epoch_from_results_csv(csv_path: Path) -> int:
    """Latest completed epoch (1-based, as in Ultralytics CSV first column). Returns 0 if missing/invalid."""
    if not csv_path.is_file():
        return 0
    try:
        line = csv_path.read_text(encoding="utf-8").splitlines()[-1]
    except OSError:
        return 0
    if not line.strip() or line.lower().startswith("epoch"):
        return 0
    m = re.match(r"^\s*(\d+)", line)
    return int(m.group(1)) if m else 0


def _bump_train_args_epochs_in_checkpoint(path: Path, new_total_epochs: int) -> None:
    """Ultralytics check_resume() reloads train_args from disk and ignores CLI epochs; patch the file."""
    ckpt = _torch_load_ckpt(path)
    ta = ckpt.get("train_args")
    if not isinstance(ta, dict):
        return
    prev = int(ta.get("epochs") or 0)
    if new_total_epochs <= prev:
        return
    ta = dict(ta)
    ta["epochs"] = int(new_total_epochs)
    ckpt["train_args"] = ta
    torch.save(ckpt, path)
    print(
        f"⚙️  Checkpoint train_args.epochs {prev} → {new_total_epochs} "
        f"(Ultralytics resume does not apply CLI --epochs)."
    )


def _archive_results_csv_for_new_leg(csv_path: Path) -> Path | None:
    """Rename results.csv so a non-resume train leg does not delete prior metrics via trainer init."""
    if not csv_path.is_file():
        return None
    leg = _last_epoch_from_results_csv(csv_path)
    dest = csv_path.with_name(f"results_epochs_1_to_{leg}.csv")
    n = 0
    while dest.exists():
        n += 1
        dest = csv_path.with_name(f"results_epochs_1_to_{leg}_{n}.csv")
    csv_path.rename(dest)
    print(f"📁 Archived prior run metrics as {dest.name} (new leg will write a fresh results.csv).")
    return dest


def retrain_model(
    *,
    data_yaml: Path | None = None,
    epochs: int = 50,
    batch: int | None = None,
    imgsz: int = 640,
    resume: Path | None = None,
):
    """Retrain YOLO model with new dataset (optimized for low disk space).

    Use ``epochs=50`` (default) per run for shorter sessions; then ``resume=last.pt`` with a higher
    ``epochs`` (e.g. 100) to continue toward a total epoch budget without starting over.
    """
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent
    
    # Check disk space on D: drive
    check_disk_space(project_root, required_gb=5)
    
    resolved_yaml = (data_yaml or (project_root / "datasets" / "data.yaml")).resolve()
    if not resolved_yaml.is_file():
        print(f"⚠ data.yaml not found at {resolved_yaml}")
        return None

    ckpt_path = resume.resolve() if resume is not None else None
    if ckpt_path is not None and not ckpt_path.is_file():
        print(f"⚠ Resume checkpoint not found: {ckpt_path}")
        return None

    # Clean up previous run only when starting fresh (resume needs weights/ and args).
    prev_runs = project_root / "runs" / "retrain"
    if ckpt_path is None and prev_runs.exists():
        print("🧹 Cleaning up previous training runs to save space...")
        shutil.rmtree(prev_runs, ignore_errors=True)
    results_csv = project_root / "runs" / "retrain" / "mealybug_v2" / "results.csv"
    use_ultra_resume = False
    effective_epochs = epochs

    if ckpt_path is not None:
        ckpt_dict = _torch_load_ckpt(ckpt_path)
        if _checkpoint_can_ultralytics_resume(ckpt_dict):
            use_ultra_resume = True
            print(f"▶ Resuming from {ckpt_path} (total target epochs={epochs})")
            _bump_train_args_epochs_in_checkpoint(ckpt_path, epochs)
        else:
            completed = _last_epoch_from_results_csv(results_csv)
            if completed <= 0 and isinstance(ckpt_dict.get("train_args"), dict):
                completed = int(ckpt_dict["train_args"].get("epochs") or 0)
            if epochs <= completed:
                print(
                    f"⚠ Already at {completed} epochs; requested total {epochs} is not greater. Nothing to train."
                )
                return None
            effective_epochs = epochs - completed
            print(
                f"▶ Finished run detected (optimizer stripped in {ckpt_path.name}). "
                f"Training {effective_epochs} more epochs toward {epochs} total."
            )
            _archive_results_csv_for_new_leg(results_csv)

    # Quick check of dataset structure (paths in yaml are relative to its directory)
    yaml_dir = resolved_yaml.parent
    train_images = yaml_dir / "train" / "images"
    if not train_images.exists():
        print(f"⚠ Train images folder not found at {train_images}")
        return None

    model = YOLO(str(ckpt_path)) if ckpt_path is not None else YOLO("yolo11n.pt")
    device = "cuda" if torch.cuda.is_available() else "cpu"
    eff_batch = batch if batch is not None else _auto_batch_size()
    print(f"📊 Training on: {device.upper()}")
    print(f"📁 Using dataset: {resolved_yaml}")
    print(f"🖼️  Train images: {train_images}")
    ep_note = f"{effective_epochs} this leg → {epochs} total" if effective_epochs != epochs else str(epochs)
    print(
        f"⚙️  epochs={ep_note}, batch={eff_batch}, imgsz={imgsz} "
        f"(4GB GPUs need batch 1; override with --batch / --imgsz if OOM)"
    )
    if ckpt_path is None:
        print(
            "💡 Shorter runs: default is 50 epochs. For 100 total: second run "
            "`python scripts/retrain_yolo.py --resume --epochs 100`"
        )

    if torch.cuda.is_available():
        torch.cuda.empty_cache()

    vram = _gpu_vram_gb()
    # Ultralytics uses 2× batch for val (detect) → train batch 1 becomes val batch 2 → common 4GB OOM in validator.
    # Do not rely only on VRAM detection; apply whenever train batch is small.
    low_vram = vram is None or vram < 10.0
    tight_batch = eff_batch <= 2
    _bt_orig = None
    _bd_orig = None
    if device == "cuda" and tight_batch:
        _bt_orig = _patch_ultralytics_val_batch_no_double()
        print("⚙️  Val batch = train batch (Ultralytics default 2× val disabled for small train batch).")
    if device == "cuda" and low_vram and tight_batch:
        _bd_orig = _patch_detection_val_no_rect()
        print("⚙️  Validation uses square images (rectangular val off) to reduce VRAM spikes.")

    train_workers = 0 if (device == "cuda" and low_vram) else 2
    train_kwargs: dict = dict(
        data=str(resolved_yaml),
        epochs=effective_epochs,
        imgsz=imgsz,
        batch=eff_batch,
        patience=15,
        device=device,
        project=str(project_root / "runs" / "retrain"),
        name="mealybug_v2",
        exist_ok=True,
        resume=bool(ckpt_path) and use_ultra_resume,
        save=True,
        save_period=-1,
        plots=False,
        cache=False,
        workers=train_workers,
        amp=True,
    )
    if device == "cuda" and low_vram:
        train_kwargs["max_det"] = 100
        train_kwargs["overlap_mask"] = False

    try:
        results = model.train(**train_kwargs)
    finally:
        if _bd_orig is not None:
            _restore_detection_build_dataset(_bd_orig)
        if _bt_orig is not None:
            _restore_ultralytics_val_batch(_bt_orig)

    print(f"✅ Training complete! Best model saved")
    
    # Force garbage collection to free memory
    gc.collect()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()
    
    return results


def export_to_tflite(weights_path=None, *, imgsz: int = 640):
    """Export retrained model to TFLite.

    Requires TensorFlow + tf_keras in the venv (Ultralytics uses ONNX → SavedModel → TFLite).
    On Python 3.13, pinned TF 2.19 is unavailable on PyPI; use e.g.:
    ``pip install "tensorflow>=2.20,<2.22" "tf_keras>=2.21,<2.22" onnxruntime``
    Install into the same venv as Ultralytics (not only user site-packages).
    """
    project_root = Path(__file__).resolve().parent.parent
    if weights_path is None:
        weights_path = project_root / "runs" / "retrain" / "mealybug_v2" / "weights" / "best.pt"
    weights_path = Path(weights_path)
    
    if not weights_path.exists():
        print(f"⚠ Weights not found: {weights_path}")
        print("Run retrain_model() first.")
        return

    print(f"📦 Exporting model to TFLite (imgsz={imgsz})...")
    model = YOLO(str(weights_path))
    
    # Export to TFLite (float16 quantized, WITHOUT in-graph NMS).
    # Dart-side code already applies NMS; disabling NMS here avoids
    # extra ops (like PAD) that can fail on some TFLite runtimes.
    model.export(
        format="tflite",
        imgsz=imgsz,
        half=True,        # Float16 quantization (smaller file)
        int8=False,
        nms=False,
    )

    out_dir = weights_path.parent
    tflite_file = out_dir / "best_float16.tflite"
    if not tflite_file.exists():
        nested = out_dir / "best_saved_model" / "best_float16.tflite"
        if nested.exists():
            shutil.copy2(nested, tflite_file)
    if not tflite_file.exists():
        for p in out_dir.rglob("best_float16.tflite"):
            shutil.copy2(p, tflite_file)
            break

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
    parser.add_argument(
        "--from-zip",
        type=Path,
        default=None,
        help="Extract a Roboflow YOLO .zip into datasets/ before training (see extract_dataset_zip.py).",
    )
    parser.add_argument(
        "--no-dataset-backup",
        action="store_true",
        help="With --from-zip: remove datasets/ without datasets.bak.* backup.",
    )
    parser.add_argument(
        "--data",
        type=Path,
        default=None,
        help="Path to data.yaml (default: <project>/datasets/data.yaml).",
    )
    parser.add_argument(
        "--epochs",
        type=int,
        default=50,
        help="Epoch budget: default 50 per run. Fresh start: trains 1..N. With --resume: N is total epochs (e.g. 100 after a 50-epoch run).",
    )
    parser.add_argument(
        "--resume",
        nargs="?",
        const="__default__",
        default=None,
        metavar="LAST_PT",
        help="Continue toward a higher total epoch count (e.g. --epochs 100). Uses true resume if interrupted; "
        "after a finished run, continues from stripped last.pt with a new leg (prior results.csv archived).",
    )
    parser.add_argument(
        "--no-export",
        action="store_true",
        help="Skip TFLite export after training (e.g. first chunk of a split run).",
    )
    parser.add_argument(
        "--batch",
        type=int,
        default=None,
        help="Batch size (default: auto from GPU VRAM; use 1 on 4GB if you still see OOM).",
    )
    parser.add_argument(
        "--imgsz",
        type=int,
        default=640,
        help="Train/val image size (default 640; try 512 with --batch 1 if OOM).",
    )
    args = parser.parse_args()

    if args.export_only is not None:
        print("🚀 PINE YOLO – export only (TFLite with nms=False)")
        print("="*50)
        export_to_tflite(args.export_only, imgsz=args.imgsz)
    else:
        print("🚀 PINE-A-PIC YOLO Retraining (Optimized for 30GB disk space)")
        print("="*50)
        project_root = Path(__file__).resolve().parent.parent
        if args.from_zip is not None:
            mod = _load_extract_module()
            mod.extract_roboflow_zip(
                args.from_zip,
                project_root / "datasets",
                backup=not args.no_dataset_backup,
            )
        resume_path: Path | None = None
        if args.resume == "__default__":
            resume_path = _default_last_checkpoint(project_root)
        elif args.resume is not None:
            resume_path = Path(args.resume)
        train_out = retrain_model(
            data_yaml=args.data,
            epochs=args.epochs,
            batch=args.batch,
            imgsz=args.imgsz,
            resume=resume_path,
        )
        if train_out is None:
            print("❌ Training did not complete (preflight error or missing paths).", file=sys.stderr)
            sys.exit(1)
        if not args.no_export:
            export_to_tflite(imgsz=args.imgsz)
        else:
            print(
                "\n📌 Skipped TFLite (--no-export).\n"
                "   Next chunk:  python scripts/retrain_yolo.py --resume --epochs 100 --no-export\n"
                "   (use your real total in --epochs; first chunk was --epochs 50)\n"
                "   When done:    python scripts/retrain_yolo.py --export-only runs/retrain/mealybug_v2/weights/best.pt"
            )