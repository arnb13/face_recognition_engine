import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Passive (single-frame) texture/CNN anti-spoofing detector.
///
/// Loads a TFLite classifier that scores a face crop as live vs. spoof (print /
/// screen-replay / mask) from one frame, with no user action.
///
/// ── Bring your own model ───────────────────────────────────────────────────
/// No model is bundled with this package. A good open option is a MiniFASNet
/// from the "Silent-Face-Anti-Spoofing" project converted to `.tflite`. Add the
/// file to **your app's** assets, declare it in your app `pubspec.yaml`, and
/// pass its key as [modelAsset]. The model-specific knobs below (input size,
/// normalization, output layout, the "live" class index) all depend on the
/// model you ship — the defaults match a common 80×80 / 3-class (print, live,
/// replay) MiniFASNet export.
///
/// The detector fails *open*: if the model is missing or inference throws,
/// [liveProbability] returns `null` and the caller skips the spoof gate so the
/// app keeps working. Tighten this to fail-closed once you trust your model.
class SpoofDetector {
  /// Asset key of the model to load (in the consuming app's assets, or a
  /// `packages/<pkg>/...` key). There is no default — anti-spoofing is opt-in.
  final String modelAsset;

  /// Square input resolution the model expects (MiniFASNet = 80).
  final int inputSize;

  /// How much to expand the face box (about its centre) before cropping, so the
  /// model also sees bezels/paper edges — strong spoof cues. 1.0 = tight.
  final double cropScale;

  /// Number of output classes (2 = live/spoof, 3 = print/live/replay).
  final int numClasses;

  /// Index of the "live/real" class within the output vector.
  final int liveIndex;

  /// Whether to apply softmax to the raw outputs before reading [liveIndex].
  /// Set false if your model already outputs probabilities.
  final bool applySoftmax;

  /// Per-channel input normalization: `value = pixel / 255 * scale - shift`.
  /// Defaults give the [0,1] range. For [-1,1] use scale 2, shift 1.
  final double normScale;
  final double normShift;

  SpoofDetector({
    required this.modelAsset,
    this.inputSize = 80,
    this.cropScale = 2.7,
    this.numClasses = 3,
    this.liveIndex = 1,
    this.applySoftmax = true,
    this.normScale = 1.0,
    this.normShift = 0.0,
  });

  Interpreter? _interpreter;
  bool _loaded = false;
  String? loadError;

  bool get isAvailable => _loaded;

  /// Attempts to load the model. Never throws — inspect [isAvailable] /
  /// [loadError] afterwards.
  Future<void> load() async {
    try {
      _interpreter = await Interpreter.fromAsset(modelAsset);
      _loaded = true;
      loadError = null;
    } catch (e) {
      _loaded = false;
      loadError = e.toString();
    }
  }

  /// Returns the model's estimated probability the face is a live person, in
  /// `[0, 1]`. Returns `null` when the model is unavailable or inference fails,
  /// signalling the caller to skip the spoof gate.
  ///
  /// [frame] is the upright RGB frame; [faceBox] is the face rectangle in that
  /// frame's coordinate space.
  double? liveProbability(img.Image frame, Rect faceBox) {
    final interpreter = _interpreter;
    if (interpreter == null || !_loaded) return null;
    try {
      final img.Image crop = _marginCrop(frame, faceBox, cropScale);
      final img.Image resized =
          img.copyResize(crop, width: inputSize, height: inputSize);

      final input = _toInputTensor(resized);
      final output = List.generate(1, (_) => List.filled(numClasses, 0.0));
      interpreter.run(input, output);

      final scores = applySoftmax ? _softmax(output[0]) : output[0];
      final idx = liveIndex.clamp(0, scores.length - 1);
      return scores[idx].toDouble();
    } catch (_) {
      return null;
    }
  }

  /// Crops [box] expanded by [scale] about its centre, clamped to [frame].
  img.Image _marginCrop(img.Image frame, Rect box, double scale) {
    final double cx = box.left + box.width / 2;
    final double cy = box.top + box.height / 2;
    final double side = max(box.width, box.height) * scale;

    final int x = (cx - side / 2).round().clamp(0, frame.width - 1);
    final int y = (cy - side / 2).round().clamp(0, frame.height - 1);
    final int w = side.round().clamp(1, frame.width - x);
    final int h = side.round().clamp(1, frame.height - y);

    return img.copyCrop(frame, x: x, y: y, width: w, height: h);
  }

  /// Builds the `[1, inputSize, inputSize, 3]` float input tensor (NHWC).
  Object _toInputTensor(img.Image image) {
    final buffer = Float32List(1 * inputSize * inputSize * 3);
    int i = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final p = image.getPixel(x, y);
        buffer[i++] = p.r / 255.0 * normScale - normShift;
        buffer[i++] = p.g / 255.0 * normScale - normShift;
        buffer[i++] = p.b / 255.0 * normScale - normShift;
      }
    }
    return buffer.reshape([1, inputSize, inputSize, 3]);
  }

  List<double> _softmax(List<double> logits) {
    final double m = logits.reduce(max);
    double sum = 0;
    final exps = List<double>.filled(logits.length, 0);
    for (int i = 0; i < logits.length; i++) {
      exps[i] = exp(logits[i] - m);
      sum += exps[i];
    }
    if (sum == 0) return logits;
    for (int i = 0; i < exps.length; i++) {
      exps[i] /= sum;
    }
    return exps;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _loaded = false;
  }
}
