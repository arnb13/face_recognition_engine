import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'face_profile.dart';
import 'face_recognition_util.dart';
import 'recognition_config.dart';

/// Outcome of matching a probe embedding against a set of enrolled profiles.
class RecognitionResult {
  /// The best-matching profile, or null when nothing was above threshold.
  final FaceProfile? profile;

  /// Cosine similarity of the best match, in `[-1, 1]`.
  final double similarity;

  /// Whether [similarity] met the configured `matchThreshold`.
  final bool matched;

  const RecognitionResult({
    required this.profile,
    required this.similarity,
    required this.matched,
  });

  /// A result representing "no match".
  static const RecognitionResult none =
      RecognitionResult(profile: null, similarity: -1, matched: false);
}

/// High-level face recognition engine.
///
/// Wraps the MobileFaceNet TFLite interpreter and exposes the operations an app
/// needs: turn a camera frame + face rectangle into an embedding, and identify
/// an embedding against enrolled [FaceProfile]s. Face *detection* (finding the
/// rectangle) is left to your app — typically via `google_mlkit_face_detection`
/// — so this package stays detector-agnostic.
///
/// ```dart
/// final recognizer = await FaceRecognizer.create();
/// final probe = recognizer.embedFrame(rgbFrame, faceRect);
/// final result = recognizer.identify(probe, store.all);
/// if (result.matched) print('Welcome ${result.profile!.name}');
/// ```
///
/// Call [dispose] when done to release native resources.
class FaceRecognizer {
  final Interpreter _interpreter;

  /// Active configuration (thresholds, etc.). Mutable so apps can swap it.
  RecognitionConfig config;

  FaceRecognizer._(this._interpreter, this.config);

  /// Creates and initialises a recognizer.
  ///
  /// No model is bundled with the package — you must supply a MobileFaceNet
  /// (112×112 → 192-d) `.tflite` via either [modelAsset] (an asset key declared
  /// in your app's `pubspec.yaml`) or [modelBytes] (e.g. downloaded at runtime).
  /// [modelBytes] takes precedence. Throws [ArgumentError] if neither is given.
  static Future<FaceRecognizer> create({
    RecognitionConfig config = const RecognitionConfig(),
    String? modelAsset,
    Uint8List? modelBytes,
    InterpreterOptions? options,
  }) async {
    if (modelBytes == null && modelAsset == null) {
      throw ArgumentError(
          'Provide either modelAsset or modelBytes — no model is bundled.');
    }
    final interpreter = modelBytes != null
        ? Interpreter.fromBuffer(modelBytes, options: options)
        : await Interpreter.fromAsset(modelAsset!, options: options);
    return FaceRecognizer._(interpreter, config);
  }

  /// Length of the embedding vectors this engine produces.
  int get embeddingLength => FaceRecognitionUtil.embeddingLength;

  /// Embeds an already-cropped [faceSize]x[faceSize] face image.
  List<double> embed(img.Image faceImage) =>
      FaceRecognitionUtil.embed(_interpreter, faceImage);

  /// Crops [box] out of [frame], resizes to the model input, and embeds it.
  List<double> embedFrame(img.Image frame, Rect box) {
    final crop = FaceRecognitionUtil.cropFace(frame, box);
    return embed(crop);
  }

  /// Convenience: decode an NV21 [CameraImage], crop [box] and embed it.
  ///
  /// Note: [box] must be expressed in the camera image's coordinate space (not
  /// the rotated/preview space). For anything other than upright NV21 frames,
  /// decode/rotate yourself and use [embedFrame].
  List<double> embedCameraImage(CameraImage image, Rect box) {
    final frame = FaceRecognitionUtil.nv21ToImage(image);
    return embedFrame(frame, box);
  }

  /// Identifies [probe] against [profiles], returning the best match.
  ///
  /// Uses [threshold] if given, otherwise `config.matchThreshold`.
  RecognitionResult identify(
    List<double> probe,
    List<FaceProfile> profiles, {
    double? threshold,
  }) {
    final t = threshold ?? config.matchThreshold;
    FaceProfile? best;
    double bestSim = -1;
    for (final p in profiles) {
      final s = FaceRecognitionUtil.bestSimilarity(probe, p.templates);
      if (s > bestSim) {
        bestSim = s;
        best = p;
      }
    }
    if (best == null) return RecognitionResult.none;
    return RecognitionResult(
      profile: best,
      similarity: bestSim,
      matched: bestSim >= t,
    );
  }

  /// Releases the native interpreter. The instance is unusable afterwards.
  void dispose() => _interpreter.close();
}
