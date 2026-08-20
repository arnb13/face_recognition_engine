import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Pure, stateless helpers for face recognition: frame decoding, face cropping,
/// MobileFaceNet embedding and similarity scoring.
///
/// These are the low-level primitives the rest of the package is built on. Most
/// callers should use [FaceRecognizer] instead, which wires the model loading
/// and matching together, but these are exposed for advanced use.
class FaceRecognitionUtil {
  FaceRecognitionUtil._();

  /// Side length (px) of the square crop MobileFaceNet expects.
  static const int faceSize = 112;

  /// Length of the embedding vector MobileFaceNet produces.
  static const int embeddingLength = 192;

  /// `android.graphics.ImageFormat.NV21`, as reported by `CameraImage.format.raw`.
  static const int rawFormatNv21 = 17;

  /// `kCVPixelFormatType_32BGRA`, as reported by `CameraImage.format.raw`.
  static const int rawFormatBgra8888 = 1111970369;

  /// Decodes a single-plane NV21 [CameraImage] to an RGB [img.Image].
  ///
  /// This is the typical format delivered by `CameraController` image streams
  /// on Android when configured with `ImageFormatGroup.nv21`.
  static img.Image nv21ToImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final Uint8List bytes = image.planes.first.bytes;
    final int yStride = image.planes.first.bytesPerRow;
    final int uvStart = yStride * height;

    final out = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      final int yRow = y * yStride;
      final int uvRow = uvStart + (y >> 1) * yStride;
      for (int x = 0; x < width; x++) {
        final int yVal = bytes[yRow + x] & 0xff;
        final int uvIndex = uvRow + (x & ~1);
        final int v = (bytes[uvIndex] & 0xff) - 128;
        final int u = (bytes[uvIndex + 1] & 0xff) - 128;

        final int r = (yVal + 1.370705 * v).round().clamp(0, 255);
        final int g =
            (yVal - 0.337633 * u - 0.698001 * v).round().clamp(0, 255);
        final int b = (yVal + 1.732446 * u).round().clamp(0, 255);

        out.setPixelRgb(x, y, r, g, b);
      }
    }
    return out;
  }

  /// Decodes a single-plane BGRA8888 [CameraImage] to an RGB [img.Image].
  ///
  /// This is the format `CameraController` delivers on iOS when configured
  /// with `ImageFormatGroup.bgra8888`. Rows may be padded, so the plane's
  /// `bytesPerRow` is honoured rather than assuming `width * 4`.
  static img.Image bgra8888ToImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final plane = image.planes.first;
    final Uint8List bytes = plane.bytes;
    final int stride = plane.bytesPerRow;

    final out = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      final int row = y * stride;
      for (int x = 0; x < width; x++) {
        final int i = row + (x << 2);
        // Byte order is B, G, R, A.
        out.setPixelRgb(x, y, bytes[i + 2], bytes[i + 1], bytes[i]);
      }
    }
    return out;
  }

  /// Decodes a streamed [CameraImage] to RGB, choosing the decoder from the
  /// frame's platform pixel format: NV21 on Android, BGRA8888 on iOS.
  ///
  /// Returns null for any other format, so callers can skip the frame instead
  /// of feeding the model mis-decoded pixels. Note the returned image is in the
  /// sensor's orientation — rotate it (as the bundled screens do) before
  /// cropping with a box from an upright-oriented detector.
  static img.Image? cameraImageToImage(CameraImage image) {
    if (image.planes.isEmpty) return null;

    // Dispatch on the raw platform constant, not `format.group`: the camera
    // plugin maps Android's NV21 (17) to ImageFormatGroup.unknown, so the
    // group alone cannot tell NV21 apart from an unsupported format.
    final raw = image.format.raw;
    if (raw == rawFormatNv21) return nv21ToImage(image);
    if (raw == rawFormatBgra8888) return bgra8888ToImage(image);

    // Unfamiliar raw value: fall back to the comparable group where it is
    // specific enough to identify the layout.
    switch (image.format.group) {
      case ImageFormatGroup.nv21:
        return nv21ToImage(image);
      case ImageFormatGroup.bgra8888:
        return bgra8888ToImage(image);
      default:
        return null;
    }
  }

  /// Crops [box] out of [frame] (clamped to bounds) and resizes to the
  /// model's expected [faceSize]x[faceSize] input.
  static img.Image cropFace(img.Image frame, Rect box) {
    final int x = box.left.toInt().clamp(0, frame.width - 1);
    final int y = box.top.toInt().clamp(0, frame.height - 1);
    final int w = box.width.toInt().clamp(1, frame.width - x);
    final int h = box.height.toInt().clamp(1, frame.height - y);

    final img.Image crop = img.copyCrop(frame, x: x, y: y, width: w, height: h);
    return img.copyResize(crop, width: faceSize, height: faceSize);
  }

  /// Converts a [faceSize]x[faceSize] image to the normalized float input
  /// tensor expected by MobileFaceNet.
  static Float32List imageToByteListFloat32(img.Image image) {
    final buffer = Float32List(1 * faceSize * faceSize * 3);
    int index = 0;
    for (int y = 0; y < faceSize; y++) {
      for (int x = 0; x < faceSize; x++) {
        final pixel = image.getPixel(x, y);
        buffer[index++] = (pixel.r - 127.5) / 127.5;
        buffer[index++] = (pixel.g - 127.5) / 127.5;
        buffer[index++] = (pixel.b - 127.5) / 127.5;
      }
    }
    return buffer;
  }

  /// Runs [interpreter] on a [faceSize]x[faceSize] [image] and returns the
  /// embedding vector.
  static List<double> embed(Interpreter interpreter, img.Image image) {
    final input =
        imageToByteListFloat32(image).reshape([1, faceSize, faceSize, 3]);
    final output = List.generate(1, (_) => List.filled(embeddingLength, 0.0));
    interpreter.run(input, output);
    return output[0].map((e) => e.toDouble()).toList();
  }

  /// Cosine similarity between two equal-length vectors, in [-1, 1].
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return -1;
    double dot = 0, na = 0, nb = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return -1;
    return dot / (sqrt(na) * sqrt(nb));
  }

  /// Best (max) cosine similarity of [probe] against any enrolled
  /// [templates]. Returns -1 when there are no templates.
  static double bestSimilarity(
    List<double> probe,
    List<List<double>> templates,
  ) {
    double best = -1;
    for (final t in templates) {
      final s = cosineSimilarity(probe, t);
      if (s > best) best = s;
    }
    return best;
  }
}
