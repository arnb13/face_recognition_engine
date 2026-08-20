import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:face_recognition_engine/face_recognition_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FaceRecognitionUtil.cosineSimilarity', () {
    test('identical vectors -> 1.0', () {
      final v = [1.0, 2.0, 3.0];
      expect(FaceRecognitionUtil.cosineSimilarity(v, v), closeTo(1.0, 1e-9));
    });

    test('orthogonal vectors -> 0.0', () {
      expect(
        FaceRecognitionUtil.cosineSimilarity([1, 0], [0, 1]),
        closeTo(0.0, 1e-9),
      );
    });

    test('length mismatch -> -1', () {
      expect(FaceRecognitionUtil.cosineSimilarity([1, 2], [1, 2, 3]), -1);
    });

    test('zero vector -> -1', () {
      expect(FaceRecognitionUtil.cosineSimilarity([0, 0], [1, 1]), -1);
    });
  });

  group('FaceRecognitionUtil.bestSimilarity', () {
    test('returns max over templates', () {
      final probe = [1.0, 0.0];
      final templates = [
        [0.0, 1.0], // 0.0
        [1.0, 1.0], // ~0.707
      ];
      expect(
        FaceRecognitionUtil.bestSimilarity(probe, templates),
        closeTo(0.7071, 1e-3),
      );
    });

    test('no templates -> -1', () {
      expect(FaceRecognitionUtil.bestSimilarity([1, 2], const []), -1);
    });
  });

  group('RecognitionConfig', () {
    test('copyWith overrides only given fields', () {
      const base = RecognitionConfig();
      final c = base.copyWith(matchThreshold: 0.9, requireBlink: false);
      expect(c.matchThreshold, 0.9);
      expect(c.requireBlink, false);
      expect(c.enrollSamples, base.enrollSamples);
    });

    test('json round-trips', () {
      const c = RecognitionConfig(matchThreshold: 0.77, enrollSamples: 5);
      final back = RecognitionConfig.fromJson(c.toJson());
      expect(back.matchThreshold, 0.77);
      expect(back.enrollSamples, 5);
      expect(back.livenessEnabled, c.livenessEnabled);
    });

    test('fromJson falls back to defaults for missing keys', () {
      final c = RecognitionConfig.fromJson(const {});
      expect(c.matchThreshold, const RecognitionConfig().matchThreshold);
    });
  });

  group('FaceProfile', () {
    test('json round-trips with templates', () {
      const p = FaceProfile(
        id: 'a',
        name: 'Alice',
        photoPath: '/x.jpg',
        templates: [
          [0.1, 0.2],
          [0.3, 0.4],
        ],
      );
      final back = FaceProfile.fromJson(p.toJson());
      expect(back.id, 'a');
      expect(back.name, 'Alice');
      expect(back.photoPath, '/x.jpg');
      expect(back.templates.length, 2);
      expect(back.templates[1][0], closeTo(0.3, 1e-9));
    });
  });

  group('RecognitionResult.none', () {
    test('is an unmatched sentinel', () {
      expect(RecognitionResult.none.matched, false);
      expect(RecognitionResult.none.profile, isNull);
    });
  });

  group('FaceRecognitionUtil.bgra8888ToImage', () {
    /// Builds a [CameraImage] whose single BGRA plane has [padding] extra bytes
    /// on each row, so the decoder's use of `bytesPerRow` is exercised.
    CameraImage bgraImage(
      int width,
      int height,
      List<List<int>> rgbRows, {
      int padding = 0,
      int raw = FaceRecognitionUtil.rawFormatBgra8888,
      ImageFormatGroup group = ImageFormatGroup.bgra8888,
    }) {
      final stride = width * 4 + padding;
      final bytes = Uint8List(stride * height);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final rgb = rgbRows[y][x];
          final i = y * stride + x * 4;
          bytes[i] = rgb & 0xff; // B
          bytes[i + 1] = (rgb >> 8) & 0xff; // G
          bytes[i + 2] = (rgb >> 16) & 0xff; // R
          bytes[i + 3] = 0xff; // A
        }
      }
      return CameraImage.fromPlatformInterface(CameraImageData(
        format: CameraImageFormat(group, raw: raw),
        width: width,
        height: height,
        planes: [CameraImagePlane(bytes: bytes, bytesPerRow: stride)],
      ));
    }

    test('maps BGRA bytes to the right RGB channels', () {
      // 0xRRGGBB per pixel.
      final image = bgraImage(2, 1, [
        [0xFF0000, 0x0000FF],
      ]);
      final out = FaceRecognitionUtil.bgra8888ToImage(image);

      expect(out.width, 2);
      expect(out.height, 1);

      final red = out.getPixel(0, 0);
      expect([red.r, red.g, red.b], [255, 0, 0]);

      final blue = out.getPixel(1, 0);
      expect([blue.r, blue.g, blue.b], [0, 0, 255]);
    });

    test('honours row padding via bytesPerRow', () {
      final image = bgraImage(
        2,
        2,
        [
          [0x102030, 0x405060],
          [0x708090, 0xA0B0C0],
        ],
        padding: 12,
      );
      final out = FaceRecognitionUtil.bgra8888ToImage(image);

      final bottomRight = out.getPixel(1, 1);
      expect([bottomRight.r, bottomRight.g, bottomRight.b], [0xA0, 0xB0, 0xC0]);
    });
  });

  group('FaceRecognitionUtil.cameraImageToImage', () {
    CameraImage frame(int raw, ImageFormatGroup group, {int planes = 1}) {
      return CameraImage.fromPlatformInterface(CameraImageData(
        format: CameraImageFormat(group, raw: raw),
        width: 1,
        height: 1,
        planes: [
          for (int i = 0; i < planes; i++)
            CameraImagePlane(bytes: Uint8List(8), bytesPerRow: 4),
        ],
      ));
    }

    test('decodes BGRA8888 by raw format', () {
      final out = FaceRecognitionUtil.cameraImageToImage(
        frame(FaceRecognitionUtil.rawFormatBgra8888, ImageFormatGroup.bgra8888),
      );
      expect(out, isNotNull);
    });

    test('decodes NV21 even though its group is reported as unknown', () {
      // The camera plugin maps Android's NV21 (17) to ImageFormatGroup.unknown,
      // which is exactly why dispatch keys off the raw value.
      final out = FaceRecognitionUtil.cameraImageToImage(
        frame(FaceRecognitionUtil.rawFormatNv21, ImageFormatGroup.unknown),
      );
      expect(out, isNotNull);
    });

    test('falls back to the format group for unfamiliar raw values', () {
      final out = FaceRecognitionUtil.cameraImageToImage(
        frame(-1, ImageFormatGroup.bgra8888),
      );
      expect(out, isNotNull);
    });

    test('returns null for an undecodable format', () {
      final out = FaceRecognitionUtil.cameraImageToImage(
        frame(35, ImageFormatGroup.yuv420),
      );
      expect(out, isNull);
    });

    test('returns null when there are no planes', () {
      final out = FaceRecognitionUtil.cameraImageToImage(
        frame(FaceRecognitionUtil.rawFormatBgra8888, ImageFormatGroup.bgra8888,
            planes: 0),
      );
      expect(out, isNull);
    });
  });
}
