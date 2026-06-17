import 'dart:typed_data';

import '../face_profile.dart';

/// Result of a guided enrollment session.
///
/// The package does not persist anything — it hands you the captured
/// [templates] (one embedding per guided angle) and an optional [photoJpg] of
/// the front pose. Store them however you like, e.g. wrapped in a
/// [FaceProfile].
class EnrollmentResult {
  /// One embedding per captured angle.
  final List<List<double>> templates;

  /// JPEG bytes of a roomy crop of the front pose, or null if none captured.
  final Uint8List? photoJpg;

  const EnrollmentResult({required this.templates, this.photoJpg});
}

/// Result of a successful recognition: the matched [profile] and the cosine
/// [similarity] of the match. `detect` returns null instead of this when the
/// user cancels or the liveness check fails.
class DetectionResult {
  final FaceProfile profile;
  final double similarity;

  const DetectionResult({required this.profile, required this.similarity});
}
