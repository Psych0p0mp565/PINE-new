#!/usr/bin/env python3
"""
Unpack a Roboflow (or similar) YOLO-format zip into <project>/datasets/.

Typical zip layout: data.yaml, train/images, train/labels, valid/..., test/...
If the archive has a single top-level folder that contains data.yaml, contents
are hoisted into datasets/.
"""
from __future__ import annotations

import argparse
import shutil
import time
import zipfile
from pathlib import Path


def extract_roboflow_zip(
    zip_path: Path,
    datasets_dir: Path,
    *,
    backup: bool = True,
) -> None:
    zip_path = zip_path.resolve()
    datasets_dir = datasets_dir.resolve()

    if not zip_path.is_file():
        raise FileNotFoundError(f"Zip not found: {zip_path}")

    project_root = datasets_dir.parent
    if datasets_dir.exists():
        if backup:
            bak = project_root / f"datasets.bak.{int(time.time())}"
            shutil.move(str(datasets_dir), str(bak))
            print(f"Backed up existing datasets/ to {bak}")
        else:
            shutil.rmtree(datasets_dir)
            print(f"Removed existing {datasets_dir}")

    datasets_dir.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(datasets_dir)

    # Hoist single-root folder if data.yaml is not at datasets_dir root.
    yaml_here = (datasets_dir / "data.yaml").is_file()
    if not yaml_here:
        subdirs = [p for p in datasets_dir.iterdir() if p.is_dir()]
        if len(subdirs) == 1 and (subdirs[0] / "data.yaml").is_file():
            inner = subdirs[0]
            for item in inner.iterdir():
                shutil.move(str(item), str(datasets_dir / item.name))
            inner.rmdir()
            print(f"Hoisted dataset from nested folder: {inner.name}")

    if not (datasets_dir / "data.yaml").is_file():
        raise RuntimeError(
            f"No data.yaml under {datasets_dir} after extract. "
            "Check that the zip is a YOLO export."
        )

    train_img = datasets_dir / "train" / "images"
    if not train_img.is_dir():
        raise RuntimeError(f"Expected train images at {train_img}")

    n_train = len(list(train_img.glob("*")))
    print(f"OK: data.yaml + train/images ({n_train} files) at {datasets_dir}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract Roboflow YOLO zip into PINE datasets/ folder.",
    )
    parser.add_argument(
        "zip_path",
        type=Path,
        help="Path to the .zip (e.g. mealybug.v5-5th.yolov11.zip)",
    )
    parser.add_argument(
        "--no-backup",
        action="store_true",
        help="Delete existing datasets/ without moving it to datasets.bak.*",
    )
    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent
    datasets_dir = project_root / "datasets"

    extract_roboflow_zip(
        args.zip_path,
        datasets_dir,
        backup=not args.no_backup,
    )


if __name__ == "__main__":
    main()
