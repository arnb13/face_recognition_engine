import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Draws a detected face rectangle on top of a [CameraPreview], mapping ML Kit
/// image coordinates onto the preview (accounting for rotation and front-camera
/// mirroring). Shared by the enrollment and detection screens.
class FaceBoxPainter extends CustomPainter {
  final Rect rect;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;
  final Color color;

  FaceBoxPainter({
    required this.rect,
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
    required this.color,
  });

  double _translateX(double x, Size canvas) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        return x * canvas.width / imageSize.height;
      case InputImageRotation.rotation270deg:
        return canvas.width - x * canvas.width / imageSize.height;
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        if (lensDirection == CameraLensDirection.back) {
          return x * canvas.width / imageSize.width;
        }
        return canvas.width - x * canvas.width / imageSize.width;
    }
  }

  double _translateY(double y, Size canvas) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return y * canvas.height / imageSize.width;
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return y * canvas.height / imageSize.height;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize == Size.zero) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color;

    final left = _translateX(rect.left, size);
    final right = _translateX(rect.right, size);
    final top = _translateY(rect.top, size);
    final bottom = _translateY(rect.bottom, size);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(min(left, right), top, max(left, right), bottom),
        const Radius.circular(8),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant FaceBoxPainter oldDelegate) {
    return oldDelegate.rect != rect || oldDelegate.color != color;
  }
}
