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
