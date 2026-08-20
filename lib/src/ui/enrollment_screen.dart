import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../face_recognition_util.dart';
import '../face_recognizer.dart';
import '../recognition_config.dart';
import 'camera_utils.dart';
import 'face_overlay_painter.dart';
import 'results.dart';

/// One angle the user is guided to present during enrollment.
class _PoseStep {
  /// Imperative prompt shown while the user is getting into the pose,
  /// e.g. "Turn your head right".
  final String label;

  /// Noun form of the same pose, e.g. "the right profile". Reads correctly
  /// when embedded in a sentence such as "Hold still, capturing ...".
  final String poseName;

  final IconData icon;

  /// True when the head pose (yaw = `headEulerAngleY`, pitch =
  /// `headEulerAngleX`, both degrees) satisfies this step.
  final bool Function(double yaw, double pitch) matches;

  const _PoseStep(this.label, this.poseName, this.icon, this.matches);
}

/// Full-screen guided, auto-capturing multi-angle enrollment.
///
/// Walks the user through a few head poses and captures one face embedding per
/// pose, then pops with an [EnrollmentResult]. Pops with null if dismissed.
/// Prefer launching it via `FaceRecognitionKit.enroll`.
class EnrollmentScreen extends StatefulWidget {
  final RecognitionConfig config;

  /// Asset key of the MobileFaceNet model (declared in your app's pubspec), or
  /// supply [modelBytes] instead. One of the two is required.
  final String? modelAsset;
  final Uint8List? modelBytes;
  final String title;
  final Color? accentColor;

  const EnrollmentScreen({
    super.key,
    this.config = const RecognitionConfig(),
    this.modelAsset,
    this.modelBytes,
    this.title = 'Enroll Face',
    this.accentColor,
  });

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  // Pose thresholds for enrollment (degrees). Modest so they are easy to hit
  // while still producing meaningfully different angles.
  static const double _yawTarget = 15;
  static const double _pitchTarget = 12;

  // Frames the pose must hold before capture, to avoid a blurry in-between shot.
  static const int _requiredStableFrames = 5;

  static final List<_PoseStep> _allSteps = [
    _PoseStep('Look straight ahead', 'the front view', Icons.face,
        (yaw, pitch) => yaw.abs() < 8 && pitch.abs() < 12),
    // Front camera is mirrored, so a turn to the user's right yields a negative
    // yaw (and vice-versa). Map prompts to the user's real direction.
    _PoseStep('Turn your head right', 'the right profile', Icons.arrow_forward,
        (yaw, pitch) => yaw <= -_yawTarget),
    _PoseStep('Turn your head left', 'the left profile', Icons.arrow_back,
        (yaw, pitch) => yaw >= _yawTarget),
    _PoseStep('Tilt your head up', 'the upward tilt', Icons.arrow_upward,
        (yaw, pitch) => pitch >= _pitchTarget),
    _PoseStep('Tilt your head down', 'the downward tilt', Icons.arrow_downward,
        (yaw, pitch) => pitch <= -_pitchTarget),
  ];

  CameraController? _controller;
  CameraDescription? _camera;
  FaceRecognizer? _recognizer;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableClassification: true,
      enableTracking: true,
    ),
  );

  late final List<_PoseStep> _steps;
  late final double _minFaceWidthFraction;

  final List<List<double>> _collected = [];
  img.Image? _photoImage;
  int _stepIndex = 0;
  int _stableFrames = 0;
  bool _flash = false;

  bool _isBusy = false;
  bool _done = false;
  String _status = 'Initializing camera...';

  Rect? _faceRect;
  Size _imageSize = Size.zero;
  InputImageRotation _rotation = InputImageRotation.rotation0deg;
  int _rotationDegrees = 0;

  @override
  void initState() {
    super.initState();
    final samples = widget.config.enrollSamples.clamp(1, _allSteps.length);
    _steps = _allSteps.take(samples).toList();
    _minFaceWidthFraction = widget.config.minFaceWidthFraction;
    _init();
  }

  Future<void> _init() async {
    try {
      _recognizer = await FaceRecognizer.create(
        config: widget.config,
        modelAsset: widget.modelAsset,
        modelBytes: widget.modelBytes,
      );

      final cameras = await availableCameras();
      _camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        _camera!,
        ResolutionPreset.medium,
        enableAudio: false,
        // NV21 on Android, BGRA8888 on iOS — the two layouts
        // FaceRecognitionUtil.cameraImageToImage can decode.
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted) return;

      setState(() => _status = _steps.first.label);
      await controller.startImageStream(_processFrame);
    } catch (e) {
      if (mounted) setState(() => _status = 'Camera error: $e');
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_isBusy || _done || !mounted) return;
    _isBusy = true;
    try {
      final input =
          inputImageFromCameraImage(image, _controller!, _camera!);
      if (input == null) return;
      _rotationDegrees = input.rotationDegrees;

      final faces = await _faceDetector.processImage(input.inputImage);
      if (faces.isEmpty) {
        _stableFrames = 0;
        if (mounted) {
          setState(() {
            _faceRect = null;
            _status = 'Position your face in the frame';
          });
        }
        return;
      }

      final face = faces.first;
      final frameSize = input.inputImage.metadata!.size;
      if (mounted) {
        setState(() {
          _faceRect = face.boundingBox;
          _imageSize = frameSize;
          _rotation = input.inputImage.metadata!.rotation;
        });
      }

      final faceWidthFraction = face.boundingBox.width / frameSize.width;
      if (faceWidthFraction < _minFaceWidthFraction) {
        _stableFrames = 0;
        if (mounted) setState(() => _status = 'Move a bit closer');
        return;
      }

      final step = _steps[_stepIndex];
      final yaw = face.headEulerAngleY ?? 0;
      final pitch = face.headEulerAngleX ?? 0;

      if (step.matches(yaw, pitch)) {
        _stableFrames++;
        if (_stableFrames >= _requiredStableFrames) {
          await _captureCurrentStep(image, face.boundingBox);
        } else if (mounted) {
          setState(() => _status = 'Hold still — capturing ${step.poseName}');
        }
      } else {
        _stableFrames = 0;
        if (mounted) setState(() => _status = step.label);
      }
    } catch (_) {
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _captureCurrentStep(CameraImage image, Rect box) async {
    final recognizer = _recognizer;
    if (recognizer == null) return;

    final decoded = FaceRecognitionUtil.cameraImageToImage(image);
    if (decoded == null) {
      if (mounted) {
        setState(() => _status = 'Unsupported camera frame format');
      }
      return;
    }

    img.Image frame = decoded;
    if (_rotationDegrees != 0) {
      frame = img.copyRotate(frame, angle: _rotationDegrees);
    }
    final embedding = recognizer.embedFrame(frame, box);

    _collected.add(embedding);
    _photoImage ??= _photoCrop(frame, box);
    _stableFrames = 0;

    if (mounted) setState(() => _flash = true);
    await Future.delayed(const Duration(milliseconds: 350));
    if (mounted) setState(() => _flash = false);

    if (_stepIndex + 1 >= _steps.length) {
      await _finish();
    } else {
      _stepIndex++;
      if (mounted) setState(() => _status = _steps[_stepIndex].label);
    }
  }

  Future<void> _finish() async {
    _done = true;
    try {
      await _controller?.stopImageStream();
    } catch (_) {}
    if (!mounted) return;

    final photo = _photoImage;
    final result = EnrollmentResult(
      templates: List<List<double>>.from(_collected),
      photoJpg: photo == null ? null : img.encodeJpg(photo, quality: 90),
    );
    Navigator.of(context).pop(result);
  }

  /// A roomy (margin-padded) square crop around [box], resized for a thumbnail.
  img.Image _photoCrop(img.Image frame, Rect box) {
    const double scale = 1.5;
    final double cx = box.left + box.width / 2;
    final double cy = box.top + box.height / 2;
    final double side =
        (box.width > box.height ? box.width : box.height) * scale;
    final int x = (cx - side / 2).round().clamp(0, frame.width - 1);
    final int y = (cy - side / 2).round().clamp(0, frame.height - 1);
    final int w = side.round().clamp(1, frame.width - x);
    final int h = side.round().clamp(1, frame.height - y);
    final crop = img.copyCrop(frame, x: x, y: y, width: w, height: h);
    return img.copyResize(crop, width: 240, height: 240);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.close();
    _recognizer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? Theme.of(context).colorScheme.primary;
    final controller = _controller;
    final bool ready = controller != null && controller.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: accent),
        title: Text(
          widget.title,
          style: TextStyle(
              color: accent, fontWeight: FontWeight.bold, fontSize: 17),
        ),
      ),
      body: Stack(
        children: [
          if (ready)
            Center(
              child: CameraPreview(
                controller,
                child: CustomPaint(
                  painter: _faceRect == null
                      ? null
                      : FaceBoxPainter(
                          rect: _faceRect!,
                          imageSize: _imageSize,
                          rotation: _rotation,
                          lensDirection: _camera!.lensDirection,
                          color: _flash ? Colors.green : accent,
                        ),
                ),
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),
          if (_flash)
            const Positioned.fill(
              child: ColoredBox(color: Color(0x3300FF66)),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_steps.length, (i) {
                final captured = i < _collected.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: captured ? Colors.green : Colors.white24,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                );
              }),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_done && _stepIndex < _steps.length)
                    Icon(_steps[_stepIndex].icon,
                        color: Colors.white, size: 40),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_collected.length}/${_steps.length}  •  $_status',
                      style: TextStyle(
                        color: _done ? Colors.green : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
