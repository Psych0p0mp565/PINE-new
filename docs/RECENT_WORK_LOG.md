# Recent work log (single file)

This is the **one** project changelog-style document. **If you are updating a paper**, read **Handoff for another agent** (below the stack reminder) first. The body has two parts:

| Part | Date scope | Sections |
|------|------------|----------|
| **Part I** | **30 March 2026 → 9 April 2026** (present) | **§17–§23** — YOLO retrain (**§17.7** val metrics), TFLite export, bundled model, map/severity, keys, commands |
| **Part II** | **Earlier** (through late March 2026, before 30 Mar; days not exact) | **§1–§16**, **§15a** — connectivity, detection UX, auth, gallery, Android, Supabase, etc.; §15a = compact manuscript bullets |

**Stack reminder:** The app uses **Supabase** (Auth, Postgres, Storage) with **`--dart-define=SUPABASE_URL`** and **`--dart-define=SUPABASE_ANON_KEY`** at build/run time. Display name in the UI is **PINYA-PIC** (formerly PINE-A-PIC in some places).

---

## Handoff for another agent — updating the paper / manuscript

**Purpose:** This file is the **primary factual source** for what was implemented in the **PINYA-PIC** (mealybug detection) mobile system: training pipeline, mobile deployment, cloud sync, and UI/analytics. Use it to refresh **Abstract**, **Methods**, **System description**, **Limitations**, and **Reproducibility** without guessing from code alone.

**How to read the two parts**

| Part | Use for the paper |
|------|-------------------|
| **Part I (§17–23)** | **Experiments / deployment:** YOLO11 retraining on 4 GB GPU, Ultralytics workarounds, TFLite export chain, bundled model, Flutter verification, **map + severity** UX, commands. |
| **Part II (§1–16)** | **Application / infrastructure:** connectivity gating, detection UX and preprocessing, auth, gallery, Android release, Supabase, remote restore of captures, branding. |

**One-paragraph system summary (starter for Abstract / intro refresh)**  
PINYA-PIC is a **Flutter** Android client that runs **single-class mealybug detection** with a **YOLO11n** model exported to **float16 TFLite** (input **640×640**). **Non-maximum suppression** and score filtering run **on-device in Dart**, not in the TFLite graph, for delegate compatibility. Captures can sync to **Supabase** (Postgres + object storage); a **map view** aggregates detections spatially and visualizes a **derived severity score** from bug count and mean confidence. Training used a **Roboflow**-hosted dataset (see **Data provenance** below) with **Ultralytics 8.4.21** on a **consumer laptop GPU (~4 GB VRAM)** with **VRAM-specific** validation and resume fixes.

**Contributions checklist (map these to your paper’s contribution bullets; rephrase in your voice)**

1. **Resource-constrained training:** Practical mitigations for **4 GB VRAM** (validation batch not doubled, rectangular val disabled under thresholds, low-VRAM train kwargs) and **Windows** long-run reliability; **chunked epochs** (e.g. 50 then continue to 100) with **documented resume/continuation** behavior when Ultralytics **strips the optimizer** after a finished leg.
2. **Mobile deployment path:** **ONNX → TensorFlow SavedModel (onnx2tf) → TFLite float16** under **Python 3.13**, with pinned **TensorFlow / tf_keras** and **`nms=False` export** so **NMS stays in the app**.
3. **On-device inference policy:** Centralized thresholds in **`AppConstants`** (**detection** display threshold, **NMS IoU**, **max detections**, optional **temperature scaling** placeholder at **1.0**).
4. **Field analytics UX:** Map layer with optional grid, markers with **severity-based** color/glow from a **saturating** function of count × confidence.
5. **Cloud-backed persistence:** Account-linked restore of uploaded captures after reinstall; explicit **limitation** that unsynced offline rows are not restored (see Part II §14).

**Methods — training (facts to cite or paraphrase)**

- **Task:** Object detection, **one class**: mealybug (`nc: 1` in `datasets/data.yaml`).
- **Base weights:** **YOLO11n** (nano), from **`yolo11n.pt`** (Ultralytics hub/cache).
- **Image size:** **640** default (script and app **`inputSize`**); reduction to **512** documented as OOM fallback.
- **Typical train kwargs (script):** **AMP** on, **patience 15**, **plots** off, **cache** off, **save_period** −1; batch often **1** on 4 GB at 640.
- **Dataset layout:** YAML under **`datasets/`**; train/val paths relative to YAML directory. Observed split sizes (version-dependent): **~2328** train / **~665** val images (see §17).
- **Mixed labels:** Roboflow exports may include **segmentation** annotations; **detect** training uses **boxes only**.

**Methods — TFLite export**

- Chain: **PyTorch `.pt` → ONNX → SavedModel (onnx2tf) → TFLite**; default **float16**, **`nms=False`**.
- **Rationale for app-side NMS:** Avoid TFLite ops (e.g. **PAD**) that fail on some **mobile delegates** when NMS is embedded in the graph.

**Methods — on-device inference (Dart; `lib/core/constants.dart` + `InferenceService`)**

| Parameter | Value in code | Paper note |
|-----------|----------------|------------|
| Input resolution | **640×640** | Must match training/export unless all three are changed together. |
| Display / filter threshold | **0.30** | Scores are **0–1** after unified handling; comment in code warns very high thresholds erase small-pest hits. |
| NMS IoU | **0.45** | Standard YOLO-style post-process in app. |
| Max boxes after NMS | **50** | Caps cost on low-end devices. |
| Confidence temperature | **1.0** | No calibration applied by default; §17 / todos mention optional future **temperature scaling** from validation data. |

**Methods — preprocessing (high level)**  
Letterboxing / padding to model input, **EXIF orientation** baking where applicable, and **coordinate mapping** back to full-resolution image space for overlays (Part II §3; tests under **`test/utils/detection_coordinate_transform_test.dart`**).

**Methods — map severity (for Results / Methods on analytics)**  
Let **b** = bug count (non-negative integer), **c** = confidence in **0…100** (clamped). Define **raw** = **b × (c/100)**. Severity in **[0, 1]**:

\[
s = 1 - e^{-\mathrm{raw}/k}, \quad k = 8
\]

(Implemented as **`severity01`** in **`lib/utils/severity_score.dart`**.) UI maps **s** to **color** (green → yellow → orange → red) and **glow radius / alpha** (`glowRadiusPx`, `glowAlpha`).

**Data provenance (cite the dataset, not only “custom”)**  
`datasets/data.yaml` includes **Roboflow** metadata: workspace **`pine3`**, project **`mealybug-y4fsp`**, **version 5**, license **CC BY 4.0**, universe URL on **roboflow.com**. Adapt paper wording to your citation style (dataset card + license).

**Reproducibility — software pins (reference machine, Part I)**

| Component | Version / note |
|-----------|----------------|
| Python | **3.13** |
| PyTorch | **2.6+cu124** |
| Ultralytics | **8.4.21** |
| Export stack | See **`scripts/requirements-export.txt`** (TensorFlow **2.20–2.21.x**, **tf_keras**, **onnxruntime**) |
| Flutter checks | **24** tests passed, **1** skipped; **analyze** clean (see §19) |

**Reported validation metrics (Ultralytics, filled from this machine — April 2026)**  

These numbers come from **`metrics/*`** columns in Ultralytics **`results.csv`** during training. They reflect the **validation split** in **`datasets/data.yaml`** (**`../valid/images`**), **not** an independent evaluation pass on **`test/images`** unless you run a separate eval. **Artifacts are local** (`runs/retrain/…` is typically **gitignored**); regenerate on another machine by retraining or by keeping CSV exports with the paper’s supplementary material.

**Training schedule:** **Leg 1** = epochs **1–50** (archived copy: **`runs/retrain/mealybug_v2/results_epochs_1_to_50.csv`**). **Leg 2** = continuation toward 100 total; **`runs/retrain/mealybug_v2/results.csv`** contained epochs **1–49** (UI counter restarts per §17.5). **Combined** = **99** completed epochs. The archived leg-1 file had **duplicate rows per epoch** on disk; figures below use **one row per epoch** (last line wins per epoch index).

| Leg | Row | Precision | Recall | mAP@0.5 | mAP@0.5:0.95 |
|-----|-----|-----------|--------|---------|---------------|
| 1 | **Best** (epoch **34** by mAP@0.5) | **0.614** | **0.443** | **0.493** | **0.227** |
| 1 | **Last** (epoch **50**) | 0.635 | 0.420 | 0.479 | 0.232 |
| 2 | **Best** (epoch **34** by mAP@0.5) | **0.667** | **0.462** | **0.526** | **0.247** |
| 2 | **Last** (epoch **49**) | 0.642 | 0.438 | 0.501 | 0.245 |

**Suggested primary headline for the paper (validation during training):** **mAP@0.5 = 0.526** (52.6%), **mAP@0.5:0.95 = 0.247** (24.7%) at **precision 0.667** / **recall 0.462**, at **leg 2, epoch 34** (best **mAP@0.5** over both legs). If the journal wants **final-epoch** numbers instead, use the **leg 2, epoch 49** row.

Duplicate §17.7 in Part I repeats this table for engineers who skip the Handoff block.

**Limitations / Discussion (safe to lift)**

- **VRAM:** Training and validation behavior tuned for **~4 GB**; not representative of datacenter runs.
- **Resume semantics:** Second training “leg” may show epoch UI **1…N** while continuing from prior weights; clarify if the paper describes training procedure.
- **Cloud restore:** Only **uploaded** rows return after reinstall; **per-box JSON** may not round-trip from server (Part II §14).
- **Metrics:** The table above is **validation-on-the-training-run**, not a separate **test-set** benchmark. For **`test/images`**, run an explicit **`model.val(split='test')`** (or export best weights and evaluate with your protocol) and add those numbers separately.

**Do not invent (for the updating agent)**

- Use the **Reported validation metrics** table for training-val figures; do **not** fabricate **test-set** or external-benchmark scores without running eval.
- **APK size** (~85 MB monolithic) and **model size** (~5.1–5.4 MB) are **build artifacts**; re-measure if the paper needs exact MB after changes.
- **Play Store** internal testing was **not** pursued (fee); check wording if the paper claims store distribution.

**Suggested mapping: log → paper sections**

| Paper section | Primary log sections |
|---------------|----------------------|
| Dataset / annotation | Part I §17; **Handoff** data provenance; `datasets/data.yaml` |
| Model / training + val metrics | Part I §17–§17.7; **Handoff** reported metrics |
| Mobile optimization / export | Part I §18, §19 |
| Inference / thresholds | **Handoff** table; Part II §3; `AppConstants` |
| Backend / user data | Part II §12, §14 |
| UI / field tool | Part I §20; Part II §2, §8 |
| Reproducibility | Part I §23; **Handoff** pins |

---

# Part I — 30 March 2026 through 9 April 2026 (present)

---

## 17. YOLO11 retraining (`scripts/retrain_yolo.py`) — 4 GB GPU

**Goal:** Retrain **mealybug** detection with Ultralytics **YOLO11** on **`datasets/data.yaml`** (paths inside YAML are relative to the YAML’s directory, usually **`datasets/`**), on **~4 GB VRAM**, using **50-epoch chunks** and continuation toward **100+** total epochs.

**Hardware / software (reference machine):** **RTX 3050 Ti Laptop**, **4096 MiB** VRAM; **Python 3.13**; **PyTorch 2.6+cu124**; **Ultralytics 8.4.21** (pip may advertise newer 8.4.x; training still ran on 8.4.21).

**Run layout (Ultralytics):**

| Item | Value |
|------|--------|
| Base checkpoint | **`yolo11n.pt`** (auto-downloaded, cached) |
| Single-class detect | `nc=1` (mealybug); pretrained head overridden from COCO 80-class |
| `project` / `name` | **`runs/retrain`**, **`mealybug_v2`** |
| Outputs | **`runs/retrain/mealybug_v2/weights/{last,best}.pt`**, **`results.csv`**, **`args.yaml`** |
| Fresh start | Script may **`rmtree(runs/retrain)`** when **not** resuming (frees disk) |

**Other train kwargs (non-default highlights):** **`amp=True`**, **`patience=15`**, **`plots=False`**, **`cache=False`**, **`exist_ok=True`**, **`save_period=-1`** (no periodic epoch snapshots). Batch default is **auto from VRAM** (typically **1** on 4 GB at **imgsz 640**).

**Dataset warnings (expected):** Ultralytics may log **mixed box/segment** labels — for **detect** training, **only boxes** are used; segments are dropped. Train/val sizes observed: **~2328** train images, **~665** val images (exact counts depend on dataset version).

### 17.1 Validation OOM mitigations

- **`_patch_ultralytics_val_batch_no_double()`** — Patches **`ultralytics.engine.trainer.BaseTrainer._build_train_pipeline`**: val dataloader **`batch_size`** matches train (Ultralytics otherwise tends to **double** val batch for detect, e.g. train **1** → val **2**, which **OOMs on 4 GB** during validation). Applied when **`device == "cuda"`** and **effective train batch ≤ 2** (not only a VRAM heuristic).
- **`_patch_detection_val_no_rect()`** — Patches **`DetectionTrainer.build_dataset`** so **`rect=False`** for val when **CUDA + VRAM &lt; 10 GB + batch ≤ 2** (square val reduces worst-case VRAM). Restored in **`finally`** alongside the train-pipeline patch.
- **Low-VRAM `model.train` kwargs:** **`max_det=100`**, **`overlap_mask=False`**, **`workers=0`** when `low_vram` (fewer loader processes, less peak memory).
- **CLI:** **`--epochs`** (default **50**), **`--batch`**, **`--imgsz`** (default **640**), **`--data`** (default **`datasets/data.yaml`**), **`--no-export`**, **`--resume [path]`** (omit path → default **`runs/retrain/mealybug_v2/weights/last.pt`**), **`--export-only`**, **`--from-zip`** (delegates to **`extract_dataset_zip.py`**).

### 17.2 Reliable training on Windows

- **IDE/agent terminals** can detach or kill long processes (~2 min in one case, mid–epoch 1). Prefer a **dedicated console** for multi-hour runs.
- **Example (separate window):**  
  `Start-Process powershell -ArgumentList '-NoExit','-File','D:\PINE\scripts\wait_first_50_then_resume_100.ps1' -WorkingDirectory 'D:\PINE'`  
  or run **`python scripts/retrain_yolo.py ...`** directly in **Windows Terminal / cmd**.

**Monitoring:** Watch **`GPU_mem`** in the epoch table; **`results.csv`** first column is **1-based epoch**; optional **TensorBoard** on **`runs/retrain`** if enabled in your Ultralytics version (this project often uses **`plots=False`**).

**Validation noise:** **`WARNING NMS time limit … exceeded`** during val is a **slow NMS** warning (many instances on val set), not necessarily a failure.

### 17.3 Automation scripts

- **`scripts/train_50_then_100.ps1`** — **`$Root`** = parent of **`scripts/`**; **`$Py`** = **`.venv\Scripts\python.exe`**; phase 1 **`--epochs 50 --no-export`**, phase 2 **`--resume --epochs 100 --no-export`**; stops on non-zero **`$LASTEXITCODE`**; prints **`--export-only`** hint at end.
- **`scripts/wait_first_50_then_resume_100.ps1`** — **Params:** **`-TotalEpochs`** (default **100**), **`-FirstChunkEpochs`** (default **50**), **`-PollSeconds`** (default **60**), **`-MaxWaitHours`** (default **48**). Uses **`Get-CimInstance Win32_Process`** for **`python.exe`** whose **`CommandLine`** contains **`retrain_yolo`**. Parses latest epoch from **`results.csv`** last line (numeric first field; skips header). **Debounce:** **20 s** after idle before launching phase 2. **Guard:** any **`runs/retrain/mealybug_v2/results_epochs_1_to_*.csv`** → exit (leg-2 **`results.csv`** restarts at epoch **1** and would otherwise look like “chunk 1” again).

### 17.4 Python exit codes

- **`retrain_yolo.py`** imports **`sys`** and **`sys.exit(1)`** when **`retrain_model()`** returns **`None`** (missing **`data.yaml`**, bad resume path, missing train images, etc.) so PowerShell chaining sees failure.

### 17.5 Resume after a *completed* first run (`strip_optimizer`)

**Symptoms:** **`AssertionError`** from **`ultralytics.engine.trainer.BaseTrainer.resume_training`**: e.g. *“…training to 50 epochs is finished, nothing to resume… start a new training without resuming”*; logged **`engine\trainer`** args may still show **`epochs=50`** despite passing **`--epochs 100`**.

**Root cause (two parts):**

1. **`final_eval`** calls **`strip_optimizer(self.last)`** (`ultralytics.utils.torch_utils`): **`epoch` → -1**, optimizer/EMA/scaler cleared — **`last.pt` is no longer a true resume checkpoint.
2. **`BaseTrainer.check_resume()`** rebuilds **`self.args`** from checkpoint **`train_args`**; only a **fixed allowlist** of keys is merged from CLI overrides — **`epochs` is not** in that list, so **`--epochs 100` never applied** on resume.

**Fixes in `retrain_yolo.py` (helper names):**

| Situation | Behavior |
|-----------|----------|
| **`_checkpoint_can_ultralytics_resume()`** true (`epoch >= 0`, optimizer present) | **`_bump_train_args_epochs_in_checkpoint(path, requested_total)`** — `torch.load` / `torch.save`, mutates **`train_args["epochs"]`** in the **`.pt`** file |
| Stripped / finished (else branch) | **`_last_epoch_from_results_csv()`**, **`_archive_results_csv_for_new_leg()`** → **`model.train(resume=False, epochs=extra)`** with **`extra = target_total - completed`** |

**Leg-2 UI:** Ultralytics shows **`1/50…50/50`** for the second leg; that is **epochs 51–100** of **total** training effort, not a reset of the model’s learning from zero.

### 17.6 If training still OOMs

- Try **`--imgsz 512`** (and **`--batch 1`**) on the same mitigations.
- Ensure no other GPU-heavy apps; close browsers using GPU acceleration if needed.
- **Resume** from **`last.pt`** after a crash only if the checkpoint is **not** yet stripped (mid-run); after a **completed** run use the **continuation leg** path above.

### 17.7 Validation metrics logged (Ultralytics `results.csv`)

**Split:** **`val`** as in **`datasets/data.yaml`** (same images used for per-epoch validation during training). **Not** a one-off **`test`** split unless you evaluate separately.

**Leg 1** (**50** epochs): archived **`runs/retrain/mealybug_v2/results_epochs_1_to_50.csv`**. On this machine the saved archive contained **duplicate lines per epoch**; numbers below use **one row per epoch** (last occurrence per epoch index).

**Leg 2** (**49** epochs in the captured **`results.csv`**): **`runs/retrain/mealybug_v2/results.csv`** (epoch column **1…49** in the UI; continuation after leg 1). **Total** completed epochs = **99**.

| Leg | | Precision | Recall | mAP@0.5 | mAP@0.5:0.95 |
|-----|--|-----------|--------|---------|---------------|
| 1 | Best (epoch **34**) | 0.614 | 0.443 | **0.493** | 0.227 |
| 1 | Last (epoch **50**) | 0.635 | 0.420 | 0.479 | 0.232 |
| 2 | Best (epoch **34**) | 0.667 | 0.462 | **0.526** | **0.247** |
| 2 | Last (epoch **49**) | 0.642 | 0.438 | 0.501 | 0.245 |

**Best over both legs (by mAP@0.5):** leg **2**, epoch **34** — **mAP@0.5 = 0.526**, **mAP@0.5:0.95 = 0.247**, P = **0.667**, R = **0.462**.

Full wording for a manuscript (val vs test caveats, gitignore, dedupe note) is in the **Handoff** section: **Reported validation metrics**.

---

## 18. TFLite export (Python 3.13 + Ultralytics)

**Pipeline:** PyTorch **`.pt`** → **ONNX** (slimmed) → **TensorFlow SavedModel** (**onnx2tf**, uses **`tf_keras`**) → **TFLite** (float16 in our default).

**Failure modes seen:**

- Ultralytics **`requirements:`** step tried **`pip install "tensorflow>=2.0.0,<=2.19.0"`** — **no matching wheel** on **Python 3.13** (only **2.20+** listed on PyPI) → **`No module named 'tensorflow'`**.
- After installing TF in **`.venv`**, **`ModuleNotFoundError: No module named 'tf_keras'`** because auto-install sometimes targeted **user** site-packages (**“Defaulting to user installation because normal site-packages is not writeable”**) while the **venv** interpreter did not see those packages.

**Fix (install into project venv, same interpreter as Ultralytics):**

```text
pip install "tensorflow>=2.20,<2.22" "tf_keras>=2.21,<2.22" onnxruntime
```

**`scripts/requirements-export.txt`** encodes the same pins for reproducibility.

**`export_to_tflite()`** (`retrain_yolo.py`): loads **`YOLO(weights_path)`**, calls **`model.export(format="tflite", imgsz=..., half=True, int8=False, nms=False)`**. **`nms=False`** so **NMS runs in Dart** (`InferenceService` / app code) — avoids TFLite ops (e.g. **PAD**) that break on some mobile delegates. After export, Ultralytics may write **`best_float16.tflite`** under **`weights/best_saved_model/`**; the script **copies** (or **rglob** finds) it to **`weights/best_float16.tflite`** so success text and **`copy`** instructions match.

**Side artifacts:** **`best.onnx`**, **`best_saved_model/`** directory, optional **`best_float32.tflite`**; calibration zip may download on first int8-related paths (we use **float16**, not int8).

**Export runs on CPU** in typical logs (`torch ... CPU`) — GPU not required for export.

---

## 19. Bundled model and release checks

**Flutter constants:** **`lib/core/constants.dart`** — **`AppConstants.modelPath = 'assets/model/best.tflite'`**, **`inputSize = 640`**. **`AppConfig`** (`lib/core/config.dart`) defaults match these. If you ever train/export at **`imgsz ≠ 640`**, update **`inputSize`** and letterbox behavior consistently.

**Asset pipeline:** **`pubspec.yaml`** lists **`assets/model/`**; place **`best.tflite`** there (copy from **`runs/retrain/mealybug_v2/weights/best_float16.tflite`** after export). Typical bundled size **~5.1–5.4 MB** (float16).

**Verification runs (reported):**

| Step | Result |
|------|--------|
| **`flutter pub get`** | OK |
| **`flutter test`** | **24 passed**, **1 skipped** (integration / Supabase-dependent) |
| **`flutter analyze`** | **No issues found** |
| **`flutter build apk --release`** | Success; **`build/app/outputs/flutter-apk/app-release.apk`** ~**85 MB** (monolithic, includes model + maps stack) |

**Smaller APKs:** **`flutter build apk --release --split-per-abi`** or **`scripts/build_release_auto_version.ps1 -SplitPerAbi`** → per-ABI outputs under **`build/app/outputs/flutter-apk/`** (e.g. **`app-arm64-v8a-release.apk`**).

**Android:** **`android/app/build.gradle.kts`** — **`compileSdk`/`targetSdk` 36**, **`minSdk`** from Flutter template, **Java/Kotlin 21**; **`release`** may still use **debug `signingConfig`** — replace for **Play Store** uploads.

---

## 20. Detections map and severity (Flutter)

- **`lib/utils/severity_score.dart`** — **`severity01(bugCount, confidencePct, {k=8})`**: raw **`bugCount × (confidencePct/100)`**, then **`1 - exp(-raw/k)`** saturating in **[0,1]**; **`severityColor`**, **`glowRadiusPx`**, **`glowAlpha`** for UI. **LaTeX-style definition and contribution framing** for the manuscript are in the **Handoff** section at the top (“Methods — map severity”).
- **`lib/widgets/severity_glow_marker.dart`** — Marker chrome from severity score.
- **`lib/screens/detections_map_screen.dart`** — Imports **`map_tiles`**, **`supabase_client`**, **`captured_photo_detail_screen`**; **`flutter_map`** + **`latlong2`**; optional **`fieldId`/`fieldName`**; **grid overlay** (toggle, **`_cellSizeM`** meters, equirectangular helpers); fetches detection rows when Supabase is available; navigates to detail.
- **Related edits:** **`permission_screens.dart`**, **`field_detail_screen.dart`**, **`captured_photo_detail_screen.dart`**, **`feedback_form_screen.dart`**, **`pubspec.yaml`** — navigation entry points, **confidence scale** alignment (**0–1** vs **0–100**) across **map**, **cloud sync**, and **saved capture** paths where unified. For the paper: **model outputs and stored JSON** are treated as **0–1** probabilities where applicable; **severity** and some **UI labels** expect **percent (0–100)**—the updating agent should describe this **explicit normalization** if Methods discuss the map score.

---

## 21. Documentation (this period)

- **`docs/RECENT_WORK_LOG.md`** — Single changelog file: **Part I** (§17–23) = **30 Mar–9 Apr 2026**; **Part II** (§1–16) = earlier work. Previously split content from **`WORK_LOG_2026-03-30_onward.md`** was **merged here** and that file **removed**.
- **`RUN.md`** §10 — Points here; mentions Part I vs Part II.
- **`ALL_DOCS.md`** — Top banner points here for session-style updates (combined **`ALL_DOCS.md`** is not auto-regenerated when this log changes).

---

## 22. Key paths — Part I (30 Mar → present)

| Area | Paths |
|------|--------|
| Train / export | `scripts/retrain_yolo.py`, `scripts/requirements-export.txt` |
| Automation | `scripts/train_50_then_100.ps1`, `scripts/wait_first_50_then_resume_100.ps1` |
| Run artifacts | `runs/retrain/mealybug_v2/` (`weights/`, `results.csv`, `results_epochs_1_to_*.csv`) |
| App model | `assets/model/best.tflite` |
| Map / severity | `lib/utils/severity_score.dart`, `lib/widgets/severity_glow_marker.dart`, `lib/screens/detections_map_screen.dart` |

**Python helpers in `retrain_yolo.py` (Part I–related):** `_torch_load_ckpt`, `_checkpoint_can_ultralytics_resume`, `_checkpoint_optimizer_present`, `_last_epoch_from_results_csv`, `_bump_train_args_epochs_in_checkpoint`, `_archive_results_csv_for_new_leg`, `_patch_ultralytics_val_batch_no_double`, `_restore_ultralytics_val_batch`, `_patch_detection_val_no_rect`, `_restore_detection_build_dataset`, `_default_last_checkpoint`, `_load_extract_module` / **`--from-zip`**.

---

## 23. Command cheat sheet — Part I

```powershell
# --- Training (from repo root; adjust D:\PINE if needed) ---
D:\PINE\.venv\Scripts\python.exe D:\PINE\scripts\retrain_yolo.py --epochs 50 --no-export
D:\PINE\.venv\Scripts\python.exe D:\PINE\scripts\retrain_yolo.py --resume --epochs 100 --no-export

# Optional overrides
# D:\PINE\.venv\Scripts\python.exe D:\PINE\scripts\retrain_yolo.py --epochs 50 --batch 1 --imgsz 640 --no-export

# --- Export ---
D:\PINE\.venv\Scripts\python.exe -m pip install -r D:\PINE\scripts\requirements-export.txt
D:\PINE\.venv\Scripts\python.exe D:\PINE\scripts\retrain_yolo.py --export-only D:\PINE\runs\retrain\mealybug_v2\weights\best.pt
# Copy artifact into Flutter bundle:
# copy D:\PINE\runs\retrain\mealybug_v2\weights\best_float16.tflite D:\PINE\assets\model\best.tflite

# --- Automation (PowerShell) ---
# Set-Location D:\PINE
# .\scripts\train_50_then_100.ps1
# .\scripts\wait_first_50_then_resume_100.ps1
# Optional: -TotalEpochs 100 -FirstChunkEpochs 50 -PollSeconds 60 -MaxWaitHours 48

# --- Flutter / Android ---
cd D:\PINE
flutter pub get
flutter test
flutter analyze
flutter build apk --release
# flutter build apk --release --split-per-abi
# Release with version bump + defines (example): .\scripts\build_release_auto_version.ps1 -SupabaseUrl "..." -SupabaseAnonKey "..." -Target apk -SplitPerAbi -Minor
```

---

# Part II — Earlier work (before 30 March 2026)

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
6. **`SQLite v8`:** Adds **`remote_id`**, **`remote_image_url`**, and a unique index on **`(user_id, remote_id)`** where **`remote_id`** is set.

**Important limitation:** Only captures that **actually uploaded** to Supabase can be restored. Fully offline captures that never synced are still local-only and **cannot** reappear after reinstall.

**Optional gap:** Per-box **`detections_json`** is not stored in **`detections`** today; cloud-restored rows may show **count/confidence** without full historical marker JSON until a future schema addition.

---

## 15. Key files — Part II (reference)

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

## 15a. Part II — manuscript-oriented bullets (system description)

Use with the **Handoff** section; avoids re-scanning every §1–14.

- **Quality gates:** `flutter analyze` / `flutter test` as baseline; **`supabase`** in **`dev_dependencies`** so tests importing the client type-check under analyzer.
- **Connectivity model:** **`NetworkReachability`** + **`ensureOnline`**: block when **no usable network interface**; avoid hard-blocking map/login on **DNS-only** failures (strict checks reserved for sync).
- **Detection pipeline:** Shared **letterbox + EXIF** preprocessing (**`image_preprocessor.dart`**), **NMS + thresholding + coordinate remap** in **`inference_service.dart`** (see **`AppConstants`** for numeric policy), **bounding box painter** UX tweaks, result screen shows **per-box**, **average**, and **max** confidence.
- **Security UX:** Optional **biometric / device PIN** gate after login; **`SecurityPrefs`** + **`UnlockGate`** + shorter intro delay.
- **i18n:** Filipino toggle via **`AppState.isFilipino`** for disease/info copy.
- **Gallery:** Reactive home list (**`capturedPhotosRevision`**), thumbnails with **InteractiveViewer**, assign-to-field flow; local **SQLite** holds **`detections_json`** (schema v7+) for overlays.
- **Android shipping:** **R8** / **Window** dependencies and **ProGuard dontwarn**; **`INTERNET`** in manifest; **split-per-ABI** for smaller APKs.
- **Versioning:** **`bump_pubspec_version.ps1`** / **`build_release_auto_version.ps1`**; **`+build`** drives **versionCode**; downgrade install errors explained in §11.
- **Supabase:** Lazy init (**`tryInitFromEnv`**); **`ConfigRequiredScreen`** if env missing; defines must be **well-formed** (JWT not bare).
- **Cloud continuity:** Upload queue + **`CapturedPhotosRemoteSync`**; SQLite **v8** **`remote_id` / `remote_image_url`**; thumbnail prefers local file else network URL; **limitation** on never-synced captures and **optional gap** on cloud **per-box JSON** (§14).

---

## 16. Suggested commands — Part II

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

*Last updated: April 2026 — **Handoff** includes **filled validation metrics** (mAP@0.5 / mAP@0.5:0.95 from `results.csv`, legs 1–2). **Part I** §17.7 duplicates the table. CSVs live under **`runs/retrain/`** (usually not in git). For line-level history, use **`git log`** and diffs.*
