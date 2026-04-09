# How to run PINE after cloning from GitHub

This project is a **Flutter** app (primary target **Android**). Follow the steps below on your machine after you clone the repository.

---

## 1. Prerequisites

Install the following before you continue:

| Tool | Notes |
|------|--------|
| **Git** | To clone the repo. |
| **Flutter SDK** | Stable channel recommended. Run `flutter doctor` and fix any issues it reports. |
| **Android toolchain** | Android Studio (or SDK + platform tools), an **Android emulator** or a **physical device** with USB debugging. |
| **Dart SDK** | Bundled with Flutter; this project expects **`>=3.2.0 <4.0.0`** (see `pubspec.yaml`). |

Verify:

```bash
flutter --version
flutter doctor -v
```

---

## 2. Clone the repository

Replace the URL with your fork or the upstream repo URL.

```bash
git clone https://github.com/YOUR_USERNAME/PINE-new.git
cd PINE-new
```

(Use the actual folder name shown after clone if it differs.)

---

## 3. Install dependencies

This repository does **not** commit `pubspec.lock` (it is listed in `.gitignore`). After clone, resolve packages locally:

```bash
flutter pub get
```

If you see errors about missing packages, run `flutter pub get` again from the project root (where `pubspec.yaml` lives).

---

## 4. Supabase configuration (required for cloud features)

The app initializes **Supabase** at startup using **compile-time** environment variables:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

If these are **not** provided, the app starts with a **configuration screen** instead of the full dashboard (`ConfigRequiredScreen` in `lib/main.dart`).

### Run with Supabase (recommended)

From the project root, pass both values as `--dart-define` (replace with your project URL and anon key from the Supabase dashboard):

**PowerShell (Windows)**

```powershell
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=your_anon_key_here
```

**bash (macOS / Linux / Git Bash)**

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your_anon_key_here
```

**VS Code / Android Studio:** Add the same `--dart-define=...` pairs to your run configuration’s **additional arguments** for the Flutter launch target.

### Run without Supabase (limited)

You can still run `flutter run` with no defines to open the app UI, but you will only see the **configuration required** flow until valid Supabase credentials are provided.

---

## 5. Run the app on a device or emulator

1. Start an Android emulator, or connect a phone with **USB debugging** enabled.
2. List devices:

   ```bash
   flutter devices
   ```

3. Run:

   ```bash
   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
   ```

   To target a specific device:

   ```bash
   flutter run -d <device_id> --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
   ```

The first build can take several minutes.

---

## 6. Model and offline inference

The TensorFlow Lite model is bundled under `assets/model/` (see `pubspec.yaml`). **No download step is required** for inference after `flutter pub get` and a successful build.

---

## 7. Release build (optional)

To produce a release APK (Android):

```bash
flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

Output is typically under `build/app/outputs/flutter-apk/`.

---

## 8. Common issues

| Problem | What to try |
|--------|-------------|
| `flutter` not found | Add Flutter’s `bin` directory to your `PATH`, or use the full path to `flutter`. |
| No devices | Start an emulator, plug in a device, accept the USB debugging prompt, run `flutter devices`. |
| Gradle / Android build errors | Open **Android Studio** once to install missing SDK components; run `flutter doctor --android-licenses` and accept licenses. |
| `pub get` fails | Check network; ensure you are on a supported Flutter/Dart version and run `flutter upgrade` if needed. |
| App shows “configuration required” | Supabase URL/key were not passed at **run** or **build** time; add `--dart-define` as above. |

---

## 9. Quick reference (copy-paste)

```bash
git clone <YOUR_REPO_URL>
cd <REPO_FOLDER>
flutter pub get
flutter doctor
flutter run --dart-define=SUPABASE_URL=<URL> --dart-define=SUPABASE_ANON_KEY=<KEY>
```

Replace `<URL>` and `<KEY>` with your Supabase project values.

---

## 10. What changed recently (changelog-style)

Everything is in **one file:** **[`docs/RECENT_WORK_LOG.md`](docs/RECENT_WORK_LOG.md)**

- **Part I (§17–23):** 30 March 2026 → 9 April 2026 — YOLO retrain, TFLite export, automation scripts, map/severity, release checks.  
- **Part II (§1–16):** Earlier work (before 30 Mar 2026).

Training and export: **`scripts/retrain_yolo.py`**, **`scripts/requirements-export.txt`**.
