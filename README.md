# face_recognition_engine

On-device face recognition for Flutter. MobileFaceNet embeddings (112×112 →
192-d) with cosine matching, guided multi-angle enrollment, liveness /
anti-spoofing, and ready-made camera UI — all running locally, no server.

Two one-call flows do the heavy lifting:

- **`FaceRecognitionKit.enroll(context)`** — opens a guided camera and returns
  the face embeddings.
- **`FaceRecognitionKit.detect(context, candidates: …)`** — opens a live camera,
  runs liveness / anti-spoof checks, and matches against embeddings you supply.

The ML Kit face detector ships with the package. The **MobileFaceNet model is
not bundled** — you supply your own `.tflite` (see
[Model & license](#model--license)) — which keeps the package tiny and avoids
redistributing weights of uncertain provenance. Lower-level pieces are available
if you want to build your own UI.

## Features

- 📸 **Ready-made camera screens** — guided multi-angle enrollment + live
  recognition, behind two function calls.
- 🧠 **Bring-your-own model** — load any MobileFaceNet `.tflite` from an asset
  or `Uint8List`; nothing heavy bundled.
- 🛡️ **Liveness & anti-spoofing** — blink / head-turn / smile challenges
  (optionally randomized) plus a passive texture/CNN `SpoofDetector` (BYO model).
- 👥 **Multi-angle enrollment** — several templates per person; optional
  file-backed persistence (`FaceProfileStore`).
- 🔍 **1:N identification** — match a probe against all enrolled people by best
  cosine similarity.
- ⚙️ **One config object** — `RecognitionConfig` drives both flows (thresholds,
  challenges, spoof gate); immutable, `copyWith`, JSON-serialisable.

## Screenshots

From the [example app](example/lib/main.dart) — the guided enrollment and live
recognition screens are what `enroll()` and `detect()` open for you.

| Identified | Guided enrollment | Capturing a pose |
| --- | --- | --- |
| ![Match dialog showing the identified person and similarity](screenshots/1-identified-result.jpg) | ![Enrollment camera tracking the face and prompting the next pose](screenshots/2-enroll-front.jpg) | ![Enrollment holding still while a turned pose is recorded](screenshots/3-enroll-right.jpg) |

| Final angle | Liveness challenge | Unknown face |
| --- | --- | --- |
| ![Third enrollment angle captured, all three poses stored](screenshots/4-enroll-left.jpg) | ![Live recognition prompting the user to blink](screenshots/5-liveness-check.jpg) | ![Live recognition rejecting an unenrolled face as Unknown](screenshots/6-live-detection.jpg) |

## Install

```yaml
dependencies:
  face_recognition_engine: ^1.0.0
```

### Platform setup

This package uses the camera and TensorFlow Lite. Follow the platform setup for
[`camera`](https://pub.dev/packages/camera#installation) and
[`tflite_flutter`](https://pub.dev/packages/tflite_flutter#installation) — most
importantly camera permissions in `AndroidManifest.xml` / `Info.plist`, and on
Android `minSdkVersion 21`.

### Provide a model

No model ships with the package. Add a MobileFaceNet `.tflite` (112×112 input →
192-d output) to your app and declare it:

```yaml
flutter:
  assets:
    - assets/mobilefacenet.tflite
```

Then pass its asset key (or raw bytes) to the calls below via `modelAsset:`
(or `modelBytes:`). See [Model & license](#model--license) for sourcing notes.

## Quick start

```dart
import 'package:face_recognition_engine/face_recognition_engine.dart';

const config = RecognitionConfig(matchThreshold: 0.8, enrollSamples: 3);
const model = 'assets/mobilefacenet.tflite'; // your bundled model

// 1. ENROLL — opens the guided camera, returns embeddings.
final enrolled =
    await FaceRecognitionKit.enroll(context, config: config, modelAsset: model);
if (enrolled != null) {
  final profile = FaceProfile(
    id: 'alice',
    name: 'Alice',
    photoPath: '',            // optionally persist enrolled.photoJpg
    templates: enrolled.templates,
  );
  // Persist `profile` (e.g. with FaceProfileStore, or your own storage).
}

// 2. DETECT — opens the live camera, gates on liveness, matches a face.
final match = await FaceRecognitionKit.detect(
  context,
  candidates: myEnrolledProfiles,   // List<FaceProfile>
  config: config,
  modelAsset: model,
);
if (match != null) {
  print('Welcome ${match.profile.name} '
      '(${(match.similarity * 100).toStringAsFixed(1)}%)');
}
```

Both calls return `null` if the user backs out (and `detect` also returns `null`
when the liveness check fails).

### Persisting enrollments

The package doesn't persist for you, but `FaceProfileStore` is provided if you
want a ready-made file-backed store:

```dart
final store = FaceProfileStore();
await store.load();
await store.add(profile);
// ...later: pass store.all as `candidates` to detect().
```

It also offers `findDuplicate`, `mergeInto` (re-enroll and cap templates),
`removeById`, and `clear`. You can persist `enrolled.photoJpg` yourself and set
`photoPath`, or call `FaceProfileStore.savePhoto`.

### Configuring liveness & anti-spoofing

Everything is on `RecognitionConfig`, passed to both flows:

```dart
const config = RecognitionConfig(
  matchThreshold: 0.8,
  livenessEnabled: true,
  randomizeLiveness: true,   // pick one challenge at random per attempt
  requireBlink: true,
  requireHeadTurn: false,
  requireSmile: true,
  livenessTimeoutSec: 20,
  passiveSpoofEnabled: false, // set true + pass spoofModelAsset to detect()
);
```

### Headless engine (build your own UI)

If you don't want the bundled screens, drive `FaceRecognizer` directly:

```dart
final recognizer =
    await FaceRecognizer.create(config: config, modelAsset: model);
final probe = recognizer.embedFrame(rgbFrame, faceRect); // your own detection
final result = recognizer.identify(probe, profiles);
```

### Anti-spoofing

Active-liveness thresholds (blink / head-turn / smile) live in
`RecognitionConfig` for you to drive your own UI challenges. For passive,
single-frame spoof detection, supply a TFLite model (e.g. a MiniFASNet from
Silent-Face-Anti-Spoofing) and use `SpoofDetector`:

```dart
final spoof = SpoofDetector(modelAsset: 'assets/antispoof.tflite');
await spoof.load(); // fails open: isAvailable == false if missing
final pLive = spoof.liveProbability(rgbFrame, faceRect); // null => skip gate
```

## API surface

| Type | Purpose |
| --- | --- |
| `FaceRecognitionKit` | `enroll` / `detect` — the two camera flows |
| `EnrollmentResult` | Captured templates + front-pose JPEG |
| `DetectionResult` | Matched profile + similarity |
| `EnrollmentScreen` / `DetectionScreen` | The screen widgets, for custom navigation |
| `FaceRecognizer` | Load model, embed frames, identify probes (headless) |
| `RecognitionResult` | Best match + similarity + `matched` flag |
| `FaceProfile` | One enrolled person (name, photo, templates) |
| `FaceProfileStore` | Persistent, file-backed enrollment store |
| `RecognitionConfig` | Immutable thresholds (recognition + liveness) |
| `SpoofDetector` | Passive texture/CNN anti-spoof (BYO model) |
| `FaceRecognitionUtil` | Low-level decode / crop / embed / cosine |

## Notes & limitations

- **Coordinate spaces.** `embedFrame`/`embedCameraImage` expect the face `Rect`
  in the *decoded RGB frame's* coordinates. Front cameras are mirrored and
  preview frames are often rotated — map your detector's boxes accordingly.
- **`embedCameraImage`** assumes upright single-plane NV21. For other formats or
  rotations, decode/rotate yourself and call `embedFrame`.
- The bundled screens are deliberately simple; for full control over the camera
  preview and prompts, build your own UI on top of `FaceRecognizer`.

## Model & license

- **The package code** (everything under `lib/`) is licensed under the
  [MIT License](LICENSE) — © 2026 Nafis Hasrat Arnob.
- **No model is bundled.** You supply a MobileFaceNet `.tflite` (112×112 input →
  192-d output) yourself, which keeps this package free of weights whose
  redistribution terms can't be guaranteed.

### Sourcing a model

MobileFaceNet was introduced in Chen *et al.*, ["MobileFaceNets: Efficient CNNs
for Accurate Real-time Face Verification on Mobile
Devices"](https://arxiv.org/abs/1804.07573) (2018). The *architecture* is free to
implement, but a pre-trained `.tflite`'s **weights carry their own license** —
and many copies circulating online ship with no license at all (which, by
default, means "all rights reserved" — not safe to redistribute).

Before using a model in a product, confirm its license. Safer routes:

- Train/convert your own from a clearly-licensed implementation (e.g. an
  Apache-2.0 MobileFaceNet repo) and keep its `LICENSE` alongside.
- Use a model you have explicit rights to.

Load it with `modelAsset:` (an asset key) or `modelBytes:` on `FaceRecognitionKit`
and `FaceRecognizer.create`.

No anti-spoofing model is bundled either — `SpoofDetector` is bring-your-own (a
MiniFASNet from
[Silent-Face-Anti-Spoofing](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing)
is a common choice; check its license too).
