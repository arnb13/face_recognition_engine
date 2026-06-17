import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

const Map<DeviceOrientation, int> _orientations = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

/// An ML Kit [InputImage] for a camera frame, paired with the rotation
/// (degrees) that must be applied to the decoded RGB frame to make it upright.
class CameraInputImage {
  final InputImage inputImage;
  final int rotationDegrees;
  const CameraInputImage(this.inputImage, this.rotationDegrees);
}

/// Builds the ML Kit [InputImage] for a streamed [image], handling sensor
/// orientation, device orientation and front-camera compensation. Returns null
/// when the frame format/orientation is unsupported.
CameraInputImage? inputImageFromCameraImage(
  CameraImage image,
  CameraController controller,
  CameraDescription camera,
) {
  final sensorOrientation = camera.sensorOrientation;
  InputImageRotation? rotation;
  if (Platform.isIOS) {
    rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
  } else {
    var rotationCompensation = _orientations[controller.value.deviceOrientation];
    if (rotationCompensation == null) return null;
    if (camera.lensDirection == CameraLensDirection.front) {
      rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
    } else {
      rotationCompensation =
          (sensorOrientation - rotationCompensation + 360) % 360;
    }
    rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
  }
  if (rotation == null) return null;

  final format = InputImageFormatValue.fromRawValue(image.format.raw);
  if (format == null ||
      (Platform.isAndroid && format != InputImageFormat.nv21) ||
      (Platform.isIOS && format != InputImageFormat.bgra8888)) {
    return null;
  }

  if (image.planes.length != 1) return null;
  final plane = image.planes.first;

  final inputImage = InputImage.fromBytes(
    bytes: plane.bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: plane.bytesPerRow,
    ),
  );
  return CameraInputImage(inputImage, rotation.rawValue);
}
