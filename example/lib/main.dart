import 'package:face_recognition_engine/face_recognition_engine.dart';
import 'package:flutter/material.dart';

/// Demonstrates the two camera flows: [FaceRecognitionKit.enroll] and
/// [FaceRecognitionKit.detect]. Enrolled people are kept in memory here; a real
/// app would persist them (e.g. with the bundled [FaceProfileStore]).
///
/// Before running:
///  - Add a MobileFaceNet `.tflite` (112×112 → 192-d) to this example's assets
///    and declare it in `example/pubspec.yaml`, then set [_modelAsset] to match.
///  - Grant camera permission (wire up `permission_handler` or similar).
void main() => runApp(const ExampleApp());

/// Asset key of your MobileFaceNet model — no model is bundled with the package.
const String _modelAsset = 'assets/mobilefacenet.tflite';

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'face_recognition_engine example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Shared, app-wide configuration for both flows.
  static const _config = RecognitionConfig(
    matchThreshold: 0.8,
    enrollSamples: 3,
    livenessEnabled: true,
    requireBlink: true,
  );

  final List<FaceProfile> _people = [];
  String _log = 'Enroll someone, then detect.';

  Future<void> _enroll() async {
    final result = await FaceRecognitionKit.enroll(
      context,
      config: _config,
      modelAsset: _modelAsset,
    );
    if (result == null) {
      setState(() => _log = 'Enrollment cancelled.');
      return;
    }
    _people.add(FaceProfile(
      id: 'p${_people.length + 1}',
      name: 'Person ${_people.length + 1}',
      photoPath: '', // could persist result.photoJpg and store the path
      templates: result.templates,
    ));
    setState(() => _log =
        'Enrolled Person ${_people.length} with ${result.templates.length} angles.');
  }

  Future<void> _detect() async {
    if (_people.isEmpty) {
      setState(() => _log = 'Enroll someone first.');
      return;
    }
    final result = await FaceRecognitionKit.detect(
      context,
      candidates: _people,
      config: _config,
      modelAsset: _modelAsset,
    );
    setState(() => _log = result == null
        ? 'No match / cancelled.'
        : 'Matched ${result.profile.name} '
            '(${(result.similarity * 100).toStringAsFixed(1)}%)');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('face_recognition_engine')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_log, textAlign: TextAlign.center),
            ),
            FilledButton.icon(
              onPressed: _enroll,
              icon: const Icon(Icons.person_add),
              label: const Text('Enroll'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _detect,
              icon: const Icon(Icons.face_retouching_natural),
              label: const Text('Detect'),
            ),
          ],
        ),
      ),
    );
  }
}
