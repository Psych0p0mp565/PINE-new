# Recent work log (past few days)

This document summarizes changes and decisions from recent development sessions: diagnostics, connectivity UX, detection quality, auth and security, localization, saved captures, release builds, troubleshooting, branding, and cloud-backed gallery persistence.

**Stack reminder:** The app uses **Supabase** (Auth, Postgres, Storage) with **`--dart-define=SUPABASE_URL`** and **`--dart-define=SUPABASE_ANON_KEY`** at build/run time. Display name in the UI is **PINYA-PIC** (formerly PINE-A-PIC in some places).

---

## 1. Diagnostics and quality gates

- Ran **`flutter pub get`**, **`flutter analyze`**, and **`flutter test`** as the baseline health check.
- **`supabase`** was added under **`dev_dependencies`** so integration tests that import the `supabase` package analyze cleanly.

---

## 2. “Online required” behavior

- Added **`NetworkReachability`** (`lib/core/network_reachability.dart`) for connectivity and optional strict host checks.
- Added **`online_required_dialog`** (`lib/widgets/online_required_dialog.dart`) with **`ensureOnline(context)`**, which:
  - Blocks only when there is **no usable network interface** (e.g. none / airplane mode).
  - **Does not** hard-block UI actions on DNS lookup failures (some networks block lookups while HTTPS still works). Strict checks remain appropriate for **background sync**, not for login/maps taps.

**Gated flows (per plan):**

- Maps / location pickers (e.g. opening **`LocationPickerScreen`**, **`LandMapScreen`** from lands, farm details, permissions).
- **Feedback** submit (before opening mail / URLs).
- **Supabase writes from UI** where applicable: profile / nickname updates, avatar upload, add/edit field, etc.

---

## 3. Mealybug detection accuracy and UX

- **`lib/utils/detection_coordinate_transform.dart`:** Normalized vs pixel coordinate handling and mapping back to original image space; unit tests in **`test/utils/detection_coordinate_transform_test.dart`**.
- **`lib/utils/image_preprocessor.dart`:** EXIF orientation via **`bakeOrientation`**, letterbox padding as **`double`** for finer transform math.
- **`lib/services/inference_service.dart`:** Uses the shared transform helper.
- **`lib/utils/bounding_box_painter.dart`:** Crosshair / corner ticks for clearer “pinpoint” visualization.
- **Result screen (`permission_screens.dart`):** Per-detection confidence (e.g. labels on markers), **average** and **highest** confidence called out for overall stats; **`AppState.bumpCapturedPhotos()`** after save so Home refreshes.

---

## 4. Login and registration

- **Login:** “**Forgot password?**” above the primary action (`/forgot-password`), button label **“Login”** (not “Sign in”).
- After successful **login** or **register**, **`SecurityPrefs.markSuccessfulLogin()`** and optional **device unlock** prompt flow.

---

## 5. Device unlock (biometric / device PIN)

- **Opt-in:** One-time prompt after first successful login/register; toggle under **Profile → Preferences** when enabled.
- **`lib/core/security_prefs.dart`:** Flags such as successful login, require unlock, prompt shown.
- **`lib/screens/device_unlock_screen.dart`** and **`lib/widgets/unlock_gate.dart`:** Gate the main experience when a session exists and unlock is required.
- **`lib/screens/intro_flow_screen.dart`:** Wraps **`MainDashboardScreen`** with **`UnlockGate`** when signed in; splash delay reduced (e.g. **650 ms** instead of a long fixed delay).

---

## 6. Profile screen

- Avatar uses **cache-busting** on **`NetworkImage`** so updated uploads show reliably.
- **SliverAppBar** style tweaks: centered title / name, more modern layout.
- **Device unlock** switch in Preferences when the user has logged in at least once.

---

## 7. Filipino language (`AppState.isFilipino`)

- **Settings** language toggle drives **`AppState`**.
- **Disease info** and related sections use conditional copy for Filipino vs English (e.g. “General Info”, “Common Diseases”, headings).

---

## 8. Saved images (Home and Captured Pictures)

- **Home → Saved Images:** Listens to **`AppState.capturedPhotosRevision`** so new saves appear immediately.
- **Thumbnails:** Tap opens an expand dialog with **InteractiveViewer**; actions to open detail.
- **Captured Pictures list:** Bottom sheet — **View details** or **Assign to a field** (offline-safe assign still respects online rules for map/field flows as implemented).
- **Local DB:** **`captured_photo`** includes **`detections_json`** (schema v7); detail screens can render overlays when JSON exists.

---

## 9. Android release builds and performance

- **R8 / missing classes:** **`androidx.window:window`** and **`window-java`** in **`android/app/build.gradle.kts`**; ProGuard **`-dontwarn`** rules for **`androidx.window.extensions`** / **`sidecar`** as in generated **`missing_rules.txt`**.
- **`INTERNET`** permission in **`AndroidManifest.xml`** for release (avoids “Failed host lookup” when permission was missing).
- **Smaller / faster installs:** **`flutter build apk --release --split-per-abi`** produces per-ABI APKs (e.g. **`app-arm64-v8a-release.apk`**).

---

## 10. Play Store

- Internal testing was discussed; **not** pursued (developer fee).

---

## 11. Automated versioning

- **`scripts/bump_pubspec_version.ps1`:** Bumps **`pubspec.yaml`** version (patch by default; **`-Minor`**, **`-Major`**). Internal numeric variables were renamed to avoid PowerShell **`switch`** name clashes with **`$Major` / `$Minor`**.
- **`scripts/build_release_auto_version.ps1`:** Optional **`flutter clean`**, bump, **`pub get`**, then **`flutter build apk`** or **`appbundle`** with `--dart-define` for Supabase.

**Android version code:** Comes from the **`+build`** segment in **`pubspec.yaml`**. **`INSTALL_FAILED_VERSION_DOWNGRADE`** means the installed app has a **higher** `versionCode` than the new APK — uninstall the old app or bump the build number.

---

## 12. Supabase configuration and startup

- **`lib/core/supabase_client.dart`:** **`tryInitFromEnv()`** — does not throw on missing env; records error state.
- **`lib/main.dart`:** If Supabase is not configured, show **`ConfigRequiredScreen`** instead of hanging.
- **Correct defines:**  
  `--dart-define=SUPABASE_URL=https://....supabase.co`  
  `--dart-define=SUPABASE_ANON_KEY=eyJ...`  
  (A bare JWT after `--dart-define=` causes “Improperly formatted define flag”.)

---

## 13. Branding

- User-visible app name updated to **PINYA-PIC** (splash, welcome, terms, tests, etc.).

---

## 14. Saved images across reinstall (account-linked)

**Goal:** After delete/reinstall, **Saved Images** still appear when the user signs in with the **same Supabase account** (Google, phone, or email — same **`auth.users`** id).

**How it works:**

1. **Upload path (unchanged concept):** Saves are still stored locally first; **`upload_queue`** + **`CloudSyncService`** upload to Storage and insert into **`public.detections`**.
2. **Link after upload:** On successful upload, the local **`captured_photo`** row is updated with **`remote_id`** (Supabase detection UUID) and **`remote_image_url`** (public Storage URL). **`DetectionService.saveDetection`** returns these via **`.insert(...).select('id, image_url').single()`**.
3. **Pull after sign-in:** **`CapturedPhotosRemoteSync`** (`lib/services/captured_photos_remote_sync.dart`) fetches **`detections`** for the current user and inserts missing rows into SQLite (placeholder **`local_image_path`** = **`DatabaseService.remoteOnlyLocalPath`** = **`_remote_`**).
4. **UI:** **`capture_thumbnail.dart`** prefers a local file when present; otherwise loads **`remote_image_url`**. Detail and export download bytes over **HTTP** when needed (**`http`** package).
5. **Assign to field:** If **`remote_id`** is set, **`DetectionService.updateDetectionFieldAssignment`** updates the cloud row.
6. **SQLite v8:** Adds **`remote_id`**, **`remote_image_url`**, and a unique index on **`(user_id, remote_id)`** where **`remote_id`** is set.

**Important limitation:** Only captures that **actually uploaded** to Supabase can be restored. Fully offline captures that never synced are still local-only and **cannot** reappear after reinstall.

**Optional gap:** Per-box **`detections_json`** is not stored in **`detections`** today; cloud-restored rows may show **count/confidence** without full historical marker JSON until a future schema addition.

---

## 15. Key files (reference)

| Area | Files |
|------|--------|
| Reachability / online dialog | `lib/core/network_reachability.dart`, `lib/widgets/online_required_dialog.dart` |
| Coordinate / preprocess | `lib/utils/detection_coordinate_transform.dart`, `lib/utils/image_preprocessor.dart`, `lib/services/inference_service.dart` |
| Security prefs / unlock | `lib/core/security_prefs.dart`, `lib/widgets/unlock_gate.dart`, `lib/screens/device_unlock_screen.dart`, `lib/screens/intro_flow_screen.dart` |
| Cloud sync upload queue | `lib/services/cloud_sync_service.dart`, `lib/services/detection_service.dart` |
| Captured photos + DB | `lib/services/database_service.dart`, `lib/services/captured_photos_remote_sync.dart` |
| Gallery UI | `lib/screens/main_dashboard_screen.dart`, `lib/screens/captured_photos_screen.dart`, `lib/screens/captured_photo_detail_screen.dart`, `lib/widgets/capture_thumbnail.dart` |
| Export | `lib/services/export_service.dart` |
| Android release | `android/app/build.gradle.kts`, `android/app/proguard-rules.pro`, `android/app/src/main/AndroidManifest.xml` |
| Version scripts | `scripts/bump_pubspec_version.ps1`, `scripts/build_release_auto_version.ps1` |
| Supabase schema (SQL) | `supabase/migrations/*.sql` |

---

## 16. Suggested commands

```powershell
# Analyze and test
flutter pub get
flutter analyze
flutter test

# Debug run with Supabase
flutter run --debug --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY

# Release APK (example — use your script for version bump + defines)
.\scripts\build_release_auto_version.ps1 -SupabaseUrl "https://....supabase.co" -SupabaseAnonKey "..." -Target apk -SplitPerAbi -Minor
```

---

*Last updated: March 2026 — reflects work through cloud gallery persistence and related fixes.*
