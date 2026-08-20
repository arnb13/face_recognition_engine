import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../face_profile.dart';
import '../face_recognition_util.dart';
import '../face_recognizer.dart';
import '../recognition_config.dart';
import '../spoof_detector.dart';
import 'camera_utils.dart';
import 'face_overlay_painter.dart';
import 'results.dart';

/// Full-screen live recognition with liveness / anti-spoofing gating.
///
/// Streams frames, runs the configured liveness challenges (blink / head-turn /
/// smile, optionally randomized) and the optional passive spoof model, then
/// matches the live face against [candidates]. Pops with a [DetectionResult] on
/// a confirmed match, or null if cancelled / liveness failed. Prefer launching
/// it via `FaceRecognitionKit.detect`.
class DetectionScreen extends StatefulWidget {
  final List<FaceProfile> candidates;
  final RecognitionConfig config;

  /// Asset key of the MobileFaceNet model (declared in your app's pubspec), or
  /// supply [modelBytes] instead. One of the two is required.
  final String? modelAsset;
  final Uint8List? modelBytes;
  final String? spoofModelAsset;
  final String title;
  final Color? accentColor;

  const DetectionScreen({
    super.key,
    required this.candidates,
    this.config = const RecognitionConfig(),
    this.modelAsset,
    this.modelBytes,
    this.spoofModelAsset,
    this.title = 'Live Recognition',
    this.accentColor,
  });

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
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

  late final RecognitionConfig _cfg;
  late final double _matchThreshold;
  late final double _minFaceWidthFraction;
  late final bool _livenessEnabled;
  late final bool _randomizeLiveness;
  late final bool _poolBlink;
  late final bool _poolHeadTurn;
  late final bool _poolSmile;

  // Active challenges for the current attempt (re-picked on each retry).
  bool _requireBlink = false;
  bool _requireHeadTurn = false;
  bool _requireSmile = false;

  SpoofDetector? _spoofDetector;
  bool _spoofModelMissing = false;

  // Liveness state.
  bool _livenessPassed = false;
  bool _livenessFailed = false;
  bool _blinkDone = false;
  bool _headTurnDone = false;
  bool _smileDone = false;
  bool _eyeOpenSeen = false;
  bool _eyeCloseSeen = false;
  DateTime? _livenessStart;

  bool _isBusy = false;
  bool _matched = false;
  String _status = 'Initializing camera...';

  Rect? _faceRect;
  Size _imageSize = Size.zero;
  InputImageRotation _rotation = InputImageRotation.rotation0deg;
  int _rotationDegrees = 0;

  @override
  void initState() {
    super.initState();
    _cfg = widget.config;
    _matchThreshold = _cfg.matchThreshold;
    _minFaceWidthFraction = _cfg.minFaceWidthFraction;
    _livenessEnabled = _cfg.livenessEnabled;
    _randomizeLiveness = _cfg.randomizeLiveness;
    _poolBlink = _cfg.requireBlink;
    _poolHeadTurn = _cfg.requireHeadTurn;
    _poolSmile = _cfg.requireSmile;

    _pickChallenges();
    _livenessPassed = !_livenessEnabled ||
        (!_requireBlink && !_requireHeadTurn && !_requireSmile);

    _init();
  }

  /// Selects the active liveness challenge(s) for this attempt. With
  /// randomization on and more than one in the pool, exactly one is chosen at
  /// random so a pre-recorded attack can't anticipate the prompt.
  void _pickChallenges() {
    bool blink = _poolBlink;
    bool head = _poolHeadTurn;
    bool smile = _poolSmile;

    if (_livenessEnabled && _randomizeLiveness) {
      final pool = <String>[
        if (blink) 'blink',
        if (head) 'head',
        if (smile) 'smile',
      ];
      if (pool.length > 1) {
        final pick = pool[Random().nextInt(pool.length)];
        blink = pick == 'blink';
        head = pick == 'head';
        smile = pick == 'smile';
      }
    }

    _requireBlink = blink;
    _requireHeadTurn = head;
    _requireSmile = smile;
  }

  Future<void> _init() async {
    if (widget.candidates.isEmpty) {
      setState(() => _status = 'No candidates provided.');
      return;
    }
    try {
      _recognizer = await FaceRecognizer.create(
        config: _cfg,
        modelAsset: widget.modelAsset,
        modelBytes: widget.modelBytes,
      );

      if (_cfg.passiveSpoofEnabled && widget.spoofModelAsset != null) {
        final detector = SpoofDetector(modelAsset: widget.spoofModelAsset!);
        await detector.load();
        if (detector.isAvailable) {
          _spoofDetector = detector;
        } else {
          _spoofModelMissing = true;
        }
      }

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

      _livenessStart = DateTime.now();
      setState(
          () => _status = _livenessPassed ? 'Scanning...' : _livenessHint());
      await controller.startImageStream(_processFrame);
    } catch (e) {
      if (mounted) setState(() => _status = 'Camera error: $e');
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_isBusy || _matched || _livenessFailed || !mounted) return;
    _isBusy = true;
    try {
      final input = inputImageFromCameraImage(image, _controller!, _camera!);
      if (input == null) return;
      _rotationDegrees = input.rotationDegrees;

      final faces = await _faceDetector.processImage(input.inputImage);
      if (faces.isEmpty) {
        if (mounted) {
          setState(() {
            _faceRect = null;
            _status = _livenessPassed ? 'Scanning...' : _livenessHint();
          });
        }
        return;
      }

      final face = faces.first;
      if (mounted) {
        setState(() {
          _faceRect = face.boundingBox;
          _imageSize = input.inputImage.metadata!.size;
          _rotation = input.inputImage.metadata!.rotation;
        });
      }

      if (!_livenessPassed) {
        _updateLiveness(face);
        if (!_livenessPassed) return;
      }

      await _matchFace(image, face.boundingBox);
    } catch (_) {
    } finally {
      _isBusy = false;
    }
  }

  // ---- Liveness ----------------------------------------------------------

  void _updateLiveness(Face face) {
    final start = _livenessStart;
    if (start != null &&
        DateTime.now().difference(start).inSeconds >=
            _cfg.livenessTimeoutSec) {
      _onLivenessFailed();
      return;
    }

    if (_requireBlink && !_blinkDone) {
      final left = face.leftEyeOpenProbability;
      final right = face.rightEyeOpenProbability;
      if (left != null && right != null) {
        final openProb = (left + right) / 2;
        if (openProb >= _cfg.eyeOpenThreshold) {
          if (_eyeCloseSeen) {
            _blinkDone = true;
          } else {
            _eyeOpenSeen = true;
          }
        } else if (openProb <= _cfg.eyeClosedThreshold && _eyeOpenSeen) {
          _eyeCloseSeen = true;
        }
      }
    }

    if (_requireHeadTurn && !_headTurnDone) {
      final yaw = face.headEulerAngleY;
      if (yaw != null && yaw.abs() >= _cfg.headTurnThreshold) {
        _headTurnDone = true;
      }
    }

    if (_requireSmile && !_smileDone) {
      final smile = face.smilingProbability;
      if (smile != null && smile >= _cfg.smileThreshold) {
        _smileDone = true;
      }
    }

    final passed = (!_requireBlink || _blinkDone) &&
        (!_requireHeadTurn || _headTurnDone) &&
        (!_requireSmile || _smileDone);

    if (mounted) {
      setState(() {
        _livenessPassed = passed;
        _status = passed ? 'Liveness OK — hold still...' : _livenessHint();
      });
    } else {
      _livenessPassed = passed;
    }
  }

  String _livenessHint() {
    if (_requireBlink && !_blinkDone) return 'Blink your eyes';
    if (_requireHeadTurn && !_headTurnDone) return 'Slowly turn your head';
    if (_requireSmile && !_smileDone) return 'Please smile';
    return 'Hold still...';
  }

  Future<void> _onLivenessFailed() async {
    _livenessFailed = true;
    try {
      await _controller?.stopImageStream();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _status = 'Liveness check failed');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.gpp_bad, color: Colors.red, size: 40),
        title: const Text('Liveness Failed'),
        content: const Text(
          'Could not confirm a live person in time. Please try again and '
          'follow the on-screen prompts.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(); // returns null from detect()
            },
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _restartLiveness();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _restartLiveness() async {
    _livenessFailed = false;
    _blinkDone = false;
    _headTurnDone = false;
    _smileDone = false;
    _eyeOpenSeen = false;
    _eyeCloseSeen = false;
    _pickChallenges();
    _livenessPassed = !_livenessEnabled ||
        (!_requireBlink && !_requireHeadTurn && !_requireSmile);
    _livenessStart = DateTime.now();
    if (mounted) {
      setState(
          () => _status = _livenessPassed ? 'Scanning...' : _livenessHint());
    }
    try {
      if (_controller != null && !_controller!.value.isStreamingImages) {
        await _controller!.startImageStream(_processFrame);
      }
    } catch (_) {}
  }

  // ---- Matching ----------------------------------------------------------

  Future<void> _matchFace(CameraImage image, Rect box) async {
    final recognizer = _recognizer;
    if (recognizer == null) return;

    if (box.width / _imageSize.width < _minFaceWidthFraction) {
      if (mounted) setState(() => _status = 'Move a bit closer');
      return;
    }

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

    final detector = _spoofDetector;
    if (detector != null) {
      final live = detector.liveProbability(frame, box);
      if (live != null && live < _cfg.spoofLiveThreshold) {
        if (mounted) {
          setState(() => _status =
              'Spoof suspected (${(live * 100).toStringAsFixed(0)}% live)');
        }
        return;
      }
    }

    final embedding = recognizer.embedFrame(frame, box);
    final result = recognizer.identify(
      embedding,
      widget.candidates,
      threshold: _matchThreshold,
    );

    if (result.matched && result.profile != null) {
      await _onMatched(result.profile!, result.similarity);
    } else if (mounted) {
      setState(() => _status =
          'Unknown (best ${(result.similarity * 100).toStringAsFixed(1)}%)');
    }
  }

  Future<void> _onMatched(FaceProfile profile, double similarity) async {
    _matched = true;
    try {
      await _controller?.stopImageStream();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _status =
        '${profile.name} (${(similarity * 100).toStringAsFixed(1)}%)');
    Navigator.of(context).pop(
      DetectionResult(profile: profile, similarity: similarity),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.close();
    _recognizer?.dispose();
    _spoofDetector?.dispose();
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
                          color: _matched ? Colors.green : accent,
                        ),
                ),
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),
          if (_spoofModelMissing)
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade800,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Anti-spoof model not found — passive check skipped.',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _status,
                  style: TextStyle(
                    color: _matched ? Colors.green : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
