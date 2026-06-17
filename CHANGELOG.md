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
