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
}
