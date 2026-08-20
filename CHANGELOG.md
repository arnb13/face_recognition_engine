## 1.1.0

Minor rather than patch: the dependency and SDK floors below are breaking for
apps on older Flutter or Android.

### Dependencies

- Upgraded to `camera` ^0.12.0, `google_mlkit_face_detection` ^0.15.1 and
  `image` ^4.9.2.
- **Raised minimum requirements** to match: Flutter 3.44 / Dart 3.12, Android
  `minSdkVersion 24` (was 21, required by `camera`), and iOS deployment target
  15.5 (required by `google_mlkit_face_detection`). The README now states these
  in a Requirements table.

### Example

- The example is now runnable: added `android/` and `ios/` projects with camera
  permission (`CAMERA`, `NSCameraUsageDescription`), `minSdk 24`, iOS deployment
  target 15.5, and the Gradle JVM-target block. Drop a MobileFaceNet `.tflite`
  into `example/assets/` — the directory is declared as a whole, so no pubspec
  edit is needed — and `flutter run`. See `example/README.md`.
- Stopped tracking (and therefore publishing) `.flutter-plugins-dependencies`,
  a generated file that embeds absolute local paths.

### Documented

- Added an Android **JVM target mismatch** section to the README. `tflite_flutter`
  compiles Java at 11 and `camera_android_camerax` at 17, while their Kotlin
  tasks default to the toolchain, which AGP rejects — consuming apps need a
  `subprojects` block pinning both to 17, placed before Flutter's generated
  `evaluationDependsOn(":app")` line.

### Fixed

- **iOS support for the bundled camera screens.** `EnrollmentScreen` and
  `DetectionScreen` previously always requested and decoded NV21, an Android
  format; on iOS the BGRA8888 frames were misread and embeddings were garbage.
  They now stream NV21 on Android and BGRA8888 on iOS.
- Added `FaceRecognitionUtil.bgra8888ToImage` (honours row padding via
  `bytesPerRow`) and `FaceRecognitionUtil.cameraImageToImage`, which picks the
  decoder from the frame's raw pixel format and returns null for formats it
  cannot decode.
- `FaceRecognizer.embedCameraImage` now decodes NV21 *and* BGRA8888, and throws
  `UnsupportedError` on other formats instead of embedding mis-decoded pixels.
- Fixed the `FaceRecognizer` dartdoc sample, which called `create()` with no
  arguments — that throws, since a model must be supplied.
- Reworked the README: badges, a features table, an accurate screenshots
  section, documented defaults for `RecognitionConfig` and `SpoofDetector`, and
  a new section on how guided enrollment picks its poses.
- Fixed incorrect README guidance: `EnrollmentResult.photoJpg` (encoded JPEG
  bytes) is not interchangeable with `FaceProfileStore.savePhoto` (which takes a
  decoded `img.Image`) — both routes are now shown.

## 1.0.3

- Added a screenshots section to the README showing the enrollment, liveness and
  live-recognition screens.

## 1.0.2

- Reordered the pub.dev screenshots so the identified-result dialog comes first
  and is used as the package thumbnail.

## 1.0.1

- Fixed the enrollment status text running two prompts together while capturing,
  e.g. "Hold still — capturing Turn your head right". It now reads
  "Hold still — capturing the right profile".
- Added screenshots of the enrollment, liveness and live-recognition flows to the
  pub.dev listing.

## 1.0.0

First public release.

- `FaceRecognitionKit.enroll(context, ...)` — opens a guided multi-angle camera
  and returns the captured embeddings (+ a front-pose JPEG) as an
  `EnrollmentResult`.
- `FaceRecognitionKit.detect(context, candidates: ...)` — opens a live camera,
  runs the configured liveness / anti-spoofing checks, and returns the matched
  `FaceProfile` as a `DetectionResult`.
- `EnrollmentScreen` / `DetectionScreen` widgets for custom navigation.
- `FaceRecognizer` — headless engine: load a model, embed a frame, identify
  probes.
- `FaceProfileStore` — file-backed multi-angle enrollment storage.
- `RecognitionConfig` — immutable, JSON-serialisable thresholds for recognition
  and liveness / anti-spoofing; drives both flows.
- `SpoofDetector` — passive texture/CNN anti-spoofing (bring your own model).
- `FaceRecognitionUtil` — low-level NV21 decode, crop, embed and cosine-match
  primitives.
- **No model is bundled** — supply a MobileFaceNet `.tflite` (112×112 → 192-d)
  via `modelAsset:` or `modelBytes:`. See the README "Model & license" section.
