/// On-device face recognition for Flutter: MobileFaceNet embeddings, cosine
/// matching, multi-angle enrollment storage, and anti-spoofing scaffolding.
///
/// The simplest entry point is [FaceRecognitionKit], which provides two
/// ready-made camera flows: `enroll` (capture embeddings) and `detect` (match a
/// live face against supplied embeddings). For lower-level control use
/// [FaceRecognizer] (the headless engine), [FaceProfileStore] (persistent
/// enrollment) and [FaceRecognitionUtil] (raw primitives).
library;

export 'src/face_profile.dart';
export 'src/face_profile_store.dart';
export 'src/face_recognition_kit.dart';
export 'src/face_recognition_util.dart';
export 'src/face_recognizer.dart';
export 'src/recognition_config.dart';
export 'src/spoof_detector.dart';
export 'src/ui/detection_screen.dart' show DetectionScreen;
export 'src/ui/enrollment_screen.dart' show EnrollmentScreen;
export 'src/ui/results.dart';
