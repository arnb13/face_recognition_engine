# face_recognition_engine example

A minimal app exercising the two camera flows: **Enroll** captures multi-angle
embeddings, **Detect** gates on liveness and matches a live face against them.
Enrolled people are kept in memory only — a real app would persist them, e.g.
with the bundled `FaceProfileStore`.

## Running it

**1. Add a model.** No model ships with the package or this example; a
pre-trained `.tflite`'s weights carry their own license. Drop a MobileFaceNet
model (112×112×3 float input → 192-d output) at:

```
example/assets/mobilefacenet.tflite
```

The whole `assets/` folder is declared in `pubspec.yaml`, so no pubspec edit is
needed. See the package README's "Model & license" section for sourcing notes.

**2. Run on a device.** The camera is not available on simulators/emulators in
any useful way here, so use real hardware:

```sh
cd example
flutter run
```

Camera permission is declared for both platforms (`CAMERA` in the Android
manifest, `NSCameraUsageDescription` in `Info.plist`) and the `camera` plugin
prompts for it on first use.

## Platform configuration already applied

These are set up in this example, and your own app will need the equivalent:

| | |
| --- | --- |
| `android/app/build.gradle.kts` | `minSdk = 24` — required by `camera` 0.12 |
| `android/build.gradle.kts` | JVM target pinned to 17 across subprojects (see below) |
| `android/app/src/main/AndroidManifest.xml` | `android.permission.CAMERA` |
| `ios/Runner.xcodeproj` | `IPHONEOS_DEPLOYMENT_TARGET = 15.5` — required by ML Kit |
| `ios/Runner/Info.plist` | `NSCameraUsageDescription` |

### The JVM target block

`tflite_flutter` compiles Java at 11 and `camera_android_camerax` at 17, while
their Kotlin tasks default to the toolchain — AGP rejects the mismatch with
*"Inconsistent JVM-target compatibility detected"*. The `subprojects` block near
the top of `android/build.gradle.kts` pins both to 17.

It has to sit **above** the generated `subprojects { project.evaluationDependsOn(":app") }`
block: that line forces early evaluation, and `afterEvaluate` throws if
registered afterwards.

## What to expect

- **Enroll** walks three poses — look straight ahead, turn right, turn left —
  capturing one embedding each, then returns to the home screen reporting how
  many angles were stored.
- **Detect** asks for a liveness challenge (a blink by default), then shows the
  matched name and cosine similarity, or `Unknown` with the best score.

Both return `null` if you back out, and `detect` also returns `null` if the
liveness check times out and you dismiss the retry dialog.
