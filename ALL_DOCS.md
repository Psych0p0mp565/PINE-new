# Combined documentation

> **Backend:** The app uses **Supabase** (Auth, Postgres, Storage). Older sections below may still mention Firebase/Firestore; treat those as historical unless updated.

This file combines all project Markdown documents that previously lived across the repo.

**Changelog / session log (single file):** **`docs/RECENT_WORK_LOG.md`** — Part I = 30 Mar–9 Apr 2026; Part II = earlier. (Maintained separately so this combined file does not need frequent regeneration.)

---

## Source: `README.md`

# 🌱 PINE - Pest Identification on Native Environments

[![Flutter](https://img.shields.io/badge/Flutter-3.41.2-blue)](https://flutter.dev)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](CONTRIBUTING.md)

Offline Android mobile application for detecting tiny agricultural pests (e.g., mealybugs) on plant leaves using YOLO11 + TensorFlow Lite. Optimized for low-end devices (3GB RAM).

## ✨ Features

- 📱 **Fully Offline** - No internet required for inference
- 🎯 **Small Object Detection** - Optimized for tiny pests like mealybugs
- 📸 **Real-time Camera** - Live detection with bounding boxes
- 🗺️ **Geo-tagging** - Map integration for field data
- 💾 **Local Storage** - Save detection results with SQLite
- ⚡ **Lightweight** - Runs smoothly on 3GB RAM devices

## 🏗️ Tech Stack

| Layer | Technology |
|-------|------------|
| Dataset Management | [Roboflow](https://roboflow.com) |
| Model Training | [YOLO11](https://github.com/ultralytics/ultralytics) (Ultralytics) |
| Export Format | TensorFlow Lite (Float16 quantized) |
| Mobile Framework | [Flutter](https://flutter.dev) 3.41.2 |
| Inference Engine | [tflite_flutter](https://pub.dev/packages/tflite_flutter) |

## 📁 Project Structure

```
PINE/
├── lib/
│   ├── main.dart
│   ├── core/           # Constants and configuration
│   ├── screens/        # UI screens (detection, maps)
│   ├── services/       # Camera, inference, geolocation
│   ├── models/         # Data models
│   └── utils/          # Image processing, bounding boxes
├── assets/
│   └── model/          # Place your trained model here
│       └── best.tflite
├── android/            # Native Android configuration
├── pubspec.yaml        # Dependencies
└── SETUP_GUIDE.md      # Complete setup instructions
```

## 🚀 Quick Start

### Prerequisites
- Flutter SDK (3.x)
- Android Studio with SDK
- Java JDK 17

### 1. Clone & Install
```bash
git clone <your-repo-url>
cd PINE
flutter pub get
```

### 2. Add Your Model
```bash
# After training your YOLO11 model, export to TFLite
yolo export model=runs/detect/train/weights/best.pt format=tflite imgsz=640 half=True

# Copy to assets (Windows PowerShell)
copy runs\detect\train\weights\best_float16.tflite assets\model\best.tflite

# Or on macOS/Linux:
# cp runs/detect/train/weights/best_float16.tflite assets/model/best.tflite
```

### 3. Run on Device/Emulator
```bash
# Start emulator (API 34 recommended)
flutter emulators --launch pixel_6_final

# Run the app
flutter run
```

## 🎯 Model Specifications

| Parameter | Value |
|-----------|-------|
| **Model Variant** | yolo11n |
| **Input Resolution** | 640×640 |
| **Quantization** | Float16 |
| **Confidence Threshold** | 0.25–0.35 |
| **NMS Threshold** | 0.45 |
| **Output Format** | Bounding boxes + class confidences |

## 🧪 Testing Features

| Feature | How to Test |
|---------|-------------|
| Camera Detection | Point at sample images |
| Bounding Boxes | Check overlay accuracy |
| Map Integration | Navigate to Lands tab |
| Geolocation | Grant permission, check location |
| Database | Save and retrieve detections |

## ⚙️ Configuration

Key configuration files:
- `lib/core/constants.dart` - Model paths, thresholds
- `android/app/build.gradle` - SDK versions (minSdk 21, targetSdk 34/36)
- `pubspec.yaml` - Dependencies

## 🔧 Troubleshooting

| Issue | Solution |
|-------|----------|
| **BaseVariant error** | Check Kotlin (1.9.24), AGP (8.6.0), Gradle (8.7) |
| **Emulator crashes** | Use API 34, set RAM to 1024MB, cold boot |
| **ADB not detecting device** | `adb kill-server` then `adb start-server` |
| **Model not loading** | Verify path in `constants.dart` |

## 📚 Documentation

- [Complete Setup Guide](docs/COMPLETE_SETUP_GUIDE.md) - Full installation and Firebase setup
- [SETUP_GUIDE.md](SETUP_GUIDE.md) - Quick setup
- [COMPLETE_SETUP_SUMMARY.md](COMPLETE_SETUP_SUMMARY.md) - Environment reference
- [Contributing](CONTRIBUTING.md) - How to contribute

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Ultralytics for YOLO11
- Flutter team for the framework
- [Your Professor] for guidance

---
⭐ Star this repo if you find it useful!

---

## Source: `ARCHITECTURE.md`

## PINE Architecture Overview

PINE is an offline-first Flutter application for detecting tiny agricultural pests on pineapple plants using on-device YOLO TFLite inference, with optional Firebase-backed cloud sync and analytics.

### High-level layers

- **Presentation (`lib/screens`)**
  - Flutter `Widget`s for user flows:
    - Onboarding, login/register, profile, settings.
    - Detection flow (`DetectionScreen`) and related navigation (`HomeScreen`, dashboards).
    - Fields/lands management and disease/education content.
- **Services (`lib/services`)**
  - Infrastructure and domain-oriented helpers:
    - Camera (`CameraService`) for image capture.
    - Inference (`InferenceService`) for YOLO TFLite execution.
    - Database (`DatabaseService`) for SQLite persistence of lands and detections.
    - Geo (`GeoService`) for GPS acquisition and `GeoFenceService` for point-in-polygon checks.
    - Image storage (`ImageStorageService`) for storing captured images on device.
    - Orchestration (`DetectionFlowController`) for end-to-end detection capture and persistence.
    - Dashboard helpers (`DashboardStatsCalculator`) for aggregating detection statistics.
- **Core (`lib/core`)**
  - Cross-cutting concerns:
    - Theming (`theme.dart`).
    - Model configuration (`config.dart`, constants).
    - Simple dependency injection via `ServiceLocator`.
    - Global app state via `AppState` (e.g., auth flags).
- **Models (`lib/models`)**
  - Data models representing:
    - `DetectionRecord`, `DetectionResult`, detection boxes.
    - `Land` and `LatLngPoint` for geofencing.

### Key data flows

#### 1. Detection flow (camera → inference → DB → UI)

1. User navigates to `DetectionScreen`.
2. `DetectionFlowController` coordinates:
   - Capture image bytes from `CameraService`.
   - Run YOLO inference via `InferenceService` (separate isolate).
   - Acquire GPS via `GeoService` (with last-known fallback and explicit errors).
   - Geo-fence the point against local lands via `GeoFenceService`.
   - Save image to on-device storage (`ImageStorageService`).
   - Persist a `DetectionRecord` into SQLite through `DatabaseService`.
3. `DetectionScreen` receives a `DetectionFlowOutcome` and:
   - Updates UI state (image preview, bounding boxes, inference time).
   - Displays geo info and land association or a clear error if GPS fails.

#### 2. Offline data flow (SQLite + Firestore)

- Local spatial and detection data:
  - Stored in SQLite (`DatabaseService`) and used for:
    - Geo-fencing land boundaries.
    - Local history and analytics.
- Cloud-backed views:
  - Firestore is initialized in `main.dart` with a bounded cache and used by screens such as `MainDashboardScreen` for:
    - User profile and dashboard metrics (`detections`, `fields` collections).
  - See `docs/OFFLINE_STRATEGY.md` for details on the offline strategy and Firestore cache sizing.

### Dependency injection and state management

- **DI**
  - `ServiceLocator` (`lib/core/service_locator.dart`) provides a tiny service registry.
  - Core services (camera, inference, DB, geo, geofence, image storage) are registered in `main.dart` at startup.
  - `DetectionFlowController` resolves services from the locator when explicit instances are not provided, enabling easier testing and replacement.
- **State management**
  - Screens primarily use local `StatefulWidget` state for view-specific concerns.
  - `AppState` (`lib/core/app_state.dart`) is a `ChangeNotifier` exposed via `ChangeNotifierProvider` at the root (`main.dart`), enabling reactive updates for app-wide flags (for example, login state influencing greetings on the dashboard).

### Invariants and design principles

- Detection records are only persisted with valid GPS coordinates; failures surface as user-visible errors (no `(0,0)` fallbacks).
- SQLite is the authoritative offline store for lands and detections; Firestore acts as a cloud projection and analytics source.
- Expensive operations (model inference) are offloaded to isolates; IO-heavy flows are orchestrated in services rather than embedded directly in widgets.

---

## Source: `CONTRIBUTING.md`

# Contributing to PINE

Thank you for your interest in contributing to PINE (Pest Identification on Native Environments).

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/PINE.git`
3. Follow [SETUP_GUIDE.md](SETUP_GUIDE.md) for installation

## Development Workflow

1. Create a feature branch: `git checkout -b feature/your-feature`
2. Make your changes
3. Test thoroughly: `flutter test`
4. Run the linter: `flutter analyze`
5. Commit with clear messages: `git commit -m "Add: brief description"`
6. Push and create a Pull Request: `git push origin feature/your-feature`

## Code Style

- Follow Flutter lint rules in `analysis_options.yaml`
- Use meaningful variable and function names
- Add comments for complex logic
- Update documentation (README, SETUP_GUIDE) for new features

## Reporting Issues

- Use [GitHub Issues](https://github.com/YOUR_TEAM/PINE/issues)
- Include device/emulator details (e.g. API level, RAM)
- Attach error logs or screenshots when possible
- Check existing issues before opening a new one

## Pull Request Guidelines

- Keep PRs focused on a single feature or fix
- Test on both emulator and physical device when relevant
- Ensure `flutter analyze` passes
- Request review from a maintainer

## Model & Large Files

- Do **not** commit large model files (>100MB) to the repo
- Use shared drive or cloud storage and document the link/version
- Document model version and training date in code or docs

---

For detailed setup (Gradle, Kotlin, emulator), see [SETUP_GUIDE.md](SETUP_GUIDE.md).

---

## Source: `SETUP_GUIDE.md`

(Full contents preserved from original `SETUP_GUIDE.md`.)

---

## Source: `COMPLETE_SETUP_SUMMARY.md`

(Full contents preserved from original `COMPLETE_SETUP_SUMMARY.md`.)

---

## Source: `docs/COMPLETE_SETUP_GUIDE.md`

(Full contents preserved from original `docs/COMPLETE_SETUP_GUIDE.md`.)

---

## Source: `docs/OFFLINE_STRATEGY.md`

## Offline Data Strategy for PINE

This document describes how SQLite and Firestore are used together for offline data in the PINE app.

### 1. Local SQLite database (authoritative offline store)

- The `DatabaseService` (`lib/services/database_service.dart`) manages a local SQLite database (`pine.db`) with:
  - `land` table for land polygons and metadata.
  - `detection` table for detection records (image path, GPS, land reference, bug count, confidence, timestamp).
- This database is the **authoritative offline store** for:
  - Land boundaries used by geo-fencing.
  - Historical detection records shown in local history views.

### 2. Firestore (cloud sync and analytics)

- Firestore is used for:
  - User profile and metadata (`users` collection).
  - Cross-device analytics, dashboard metrics, and potentially mirrored detection/field data.
- Firestore persistence is enabled with a **bounded cache** (`50 MB`) in `lib/main.dart`:
  - This prevents unbounded disk growth while still allowing offline reads for recently-used data.

### 3. Interaction between SQLite and Firestore

- The current app design treats:
  - **SQLite** as the source of truth for land geometry and detection records created on-device.
  - **Firestore** as a cloud-backed projection used by dashboards and multi-device experiences.
- Where data is mirrored (e.g., detections/fields), the intended flow is:
  1. Write to SQLite for immediate offline durability.
  2. Sync to Firestore via dedicated services (to be extended as needed).
  3. Use Firestore snapshots primarily for aggregated views and summaries.

### 4. Firestore cache sizing rationale

- Firestore persistence is configured with:
  - `persistenceEnabled: true`
  - `cacheSizeBytes: 50 * 1024 * 1024` (≈ 50 MB)
- Rationale:
  - Keep enough recent data for smooth offline UX in low-connectivity field environments.
  - Avoid unbounded growth that could impact low-end Android devices targeted by PINE.

### 5. Future extensions

- As cloud sync for lands/detections evolves, keep this invariant:
  - **SQLite remains the authoritative offline store**, with clear, one-way or bidirectional sync rules to Firestore.
  - Firestore rules enforce least-privilege access and validate mirrored data against expected shapes.

---

## Source: `firebase/SECURITY_RULES_CHECKLIST.md`

## Firebase Security Rules Checklist for PINE

This document outlines how to audit and maintain secure Firebase rules for the PINE app. Use it alongside the rules configured in the Firebase console.

### 1. Firestore rules

- **Principle of least privilege**
  - Restrict read/write access by authenticated user identity (e.g. `request.auth != null`).
  - Use per-collection rules that enforce ownership on documents (e.g. `resource.data.ownerId == request.auth.uid`).
- **Collections to review**
  - `fields`, `detections`, and any additional tables referenced by the app.
- **Recommended checks**
  - No collection is world-readable or world-writable.
  - Writes validate required fields, types, and allowed value ranges.
  - Queries are restricted to indexed fields and user-owned data where appropriate.

### 2. Storage rules

- Ensure only authenticated users can upload or read files unless explicitly intended public.
- Scope reads/writes to paths associated with the authenticated user or team.
- Enforce content-type checks where possible (e.g. images only for detection uploads).

### 3. Authentication hardening

- Disable sign-in providers that are not used by the app.
- Enable protections such as:
  - Email verification where applicable.
  - Reasonable throttling / rate limiting for sign-in attempts.

### 4. Operational checklist

- Maintain separate Firebase projects for development and production.
- Document the active ruleset for each environment.
- Re-run this checklist whenever:
  - New collections or Storage buckets are added.
  - The data model changes.
  - Access patterns for existing screens are significantly modified.

---

## Source: `scripts/README.md`

# YOLO retraining scripts

## Prerequisites

- Python 3.8+
- GPU recommended (CUDA) for faster training

```bash
pip install ultralytics torch
```

## 1. Prepare dataset

- Put mealybug images in `datasets/retrain/images/train` and `images/val`.
- Annotate with [Roboflow](https://roboflow.com/) or [LabelImg](https://github.com/HumanSignal/labelImg) in YOLO format.
- Create `datasets/retrain/data.yaml` with class names and paths.

## 2. Retrain

```bash
cd D:\PINE
python scripts/retrain_yolo.py
```

## 3. Use new model in app

Copy the exported TFLite file to the app:

```powershell
copy runs\retrain\mealybug_v2\weights\best_float16.tflite assets\model\best.tflite
```

Then rebuild the Flutter app.

---

## Source: `scripts/fix_tflite_export.md`

# Fix TFLite export (NumPy/TensorFlow conflict)

The export failed because of mixed NumPy versions and TensorFlow's requirements.

## Option A: Clean venv and re-export (recommended)

**1. Close the current terminal and open a new one.**

**2. Activate venv and remove conflicting packages:**
```powershell
cd D:\PINE
.\venv\Scripts\Activate.ps1
pip uninstall numpy scipy tensorflow tensorboard keras -y
```

**3. Remove leftover NumPy folders** (if they exist):
```powershell
Remove-Item -Recurse -Force "D:\PINE\venv\Lib\site-packages\~umpy" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "D:\PINE\venv\Lib\site-packages\~umpy.libs" -ErrorAction SilentlyContinue
```

**4. Install a compatible set** (TensorFlow 2.19 needs NumPy < 2.2):
```powershell
pip install "numpy>=1.26,<2.2"
pip install tensorflow>=2.18,<=2.19
```

**5. Run export again:**
```powershell
yolo export model=runs/detect/train3/weights/best.pt format=tflite imgsz=640 half=True
```

**6. If it still fails with the same NumPy error**, install NumPy 2.1.3 explicitly and reinstall scipy:
```powershell
pip install numpy==2.1.3
pip install --force-reinstall scipy
yolo export model=runs/detect/train3/weights/best.pt format=tflite imgsz=640 half=True
```

---

## Option B: Export ONNX then convert (skip TensorFlow)

If Option A keeps failing, you can export to ONNX (no TensorFlow), then convert to TFLite using another tool, or use the ONNX model with an ONNX runtime on device. For Flutter we need TFLite, so Option A is simpler.

---

## After export succeeds

```powershell
copy runs\detect\train3\weights\best_float16.tflite assets\model\best.tflite
flutter run
```

---

## Source: `assets/model/README.md`

# Model Directory

Place your trained YOLO 11 TensorFlow Lite model here.

**Required file:** `best.tflite`

## Export from Ultralytics (must use `nms=False`)

The app does NMS in Dart. Export **without** in-graph NMS to avoid TFLite PAD errors on device.

From project root with venv activated:

**Option A – use the retrain script (recommended):**

```powershell
# Full run: train then export
python scripts/retrain_yolo.py

# Export only (if you already have best.pt)
python scripts/retrain_yolo.py --export-only runs/retrain/mealybug_v2/weights/best.pt
# or: python scripts/retrain_yolo.py --export-only runs/detect/train3/weights/best.pt
```

Then copy the printed path into assets:

```powershell
copy runs\retrain\mealybug_v2\weights\best_float16.tflite assets\model\best.tflite
```

**Option B – yolo CLI (must pass nms=False):**

```powershell
yolo export model=runs/detect/train3/weights/best.pt format=tflite imgsz=640 half=True nms=False
copy runs\detect\train3\weights\best_float16.tflite assets\model\best.tflite
```

Then: `flutter clean`, `flutter pub get`, then run or build.

See **SETUP_GUIDE.md** (Part 4) for full steps and troubleshooting.

## Requirements

- Format: TensorFlow Lite
- Quantization: Float16 (recommended)
- Input size: 640x640
- Variant: yolo11n (or your trained model)

## Class labels (multi-class models)

If your model has **more than one class**, you must keep labels in sync in two places:

1. **`assets/labels/labels.txt`** – one label per line, in the **same order** as the class indices used during training (e.g. class 0 = first line, class 1 = second line).
2. **`lib/services/inference_service.dart`** – the `InferenceService.classLabels` list (e.g. `List<String> classLabels = ['mealybug', 'aphid'];`) must match the same order.

The app uses the class index from the model output to look up the label; wrong order will show incorrect names on detections.

---

## Source: `assets/tiles/README.md`

# Offline Map Tiles

For fully offline map rendering, add an MBTiles file here (e.g., `map.mbtiles`).

Download MBTiles from:
- https://protomaps.com/downloads
- https://openmaptiles.org/

Without MBTiles, the map will use OpenStreetMap tiles (requires network on first load).

