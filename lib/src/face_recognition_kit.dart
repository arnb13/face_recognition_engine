import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'face_profile.dart';
import 'recognition_config.dart';
import 'ui/detection_screen.dart';
import 'ui/enrollment_screen.dart';
import 'ui/results.dart';

/// One-call entry points for the two camera flows.
///
/// - [enroll] opens a guided multi-angle camera and returns the captured face
///   embeddings (you decide how to store them).
/// - [detect] opens a live camera, runs the configured liveness / anti-spoofing
///   checks, and matches the face against embeddings you supply.
///
/// Both flows are driven entirely by a [RecognitionConfig] (thresholds,
/// liveness challenges, passive spoof gate). Make sure camera permissions are
/// granted before calling these.
class FaceRecognitionKit {
  FaceRecognitionKit._();

  /// Opens the guided enrollment camera and returns the result, or null if the
  /// user backs out.
  ///
  /// [config] controls `enrollSamples` (how many angles) and the face-size
  /// quality gate. Supply the MobileFaceNet model via [modelAsset] (an asset key
  /// in your app's pubspec) or [modelBytes]; one is required.
  static Future<EnrollmentResult?> enroll(
    BuildContext context, {
    RecognitionConfig config = const RecognitionConfig(),
    String? modelAsset,
    Uint8List? modelBytes,
    String title = 'Enroll Face',
    Color? accentColor,
  }) {
    return Navigator.of(context).push<EnrollmentResult>(
      MaterialPageRoute(
        builder: (_) => EnrollmentScreen(
          config: config,
          modelAsset: modelAsset,
          modelBytes: modelBytes,
          title: title,
          accentColor: accentColor,
        ),
      ),
    );
  }

  /// Opens the live recognition camera and returns the matched face, or null if
  /// the user cancels or the liveness check fails.
  ///
  /// [candidates] are the enrolled people to match against — pass the
  /// [FaceProfile]s you stored from [enroll]. Supply the MobileFaceNet model via
  /// [modelAsset] or [modelBytes] (one required). [config] controls the match
  /// threshold, the liveness challenges and the passive spoof gate. Supply
  /// [spoofModelAsset] (an asset key) to enable the passive texture model when
  /// `config.passiveSpoofEnabled` is true.
  static Future<DetectionResult?> detect(
    BuildContext context, {
    required List<FaceProfile> candidates,
    RecognitionConfig config = const RecognitionConfig(),
    String? modelAsset,
    Uint8List? modelBytes,
    String? spoofModelAsset,
    String title = 'Live Recognition',
    Color? accentColor,
  }) {
    return Navigator.of(context).push<DetectionResult>(
      MaterialPageRoute(
        builder: (_) => DetectionScreen(
          candidates: candidates,
          config: config,
          modelAsset: modelAsset,
          modelBytes: modelBytes,
          spoofModelAsset: spoofModelAsset,
          title: title,
          accentColor: accentColor,
        ),
      ),
    );
  }
}
