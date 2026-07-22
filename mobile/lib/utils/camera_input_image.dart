import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// Converts [CameraImage] frames to ML Kit [InputImage].
///
/// Android YUV_420_888 planes almost always have row padding and UV
/// `bytesPerPixel == 2`; copying planes blindly produces garbage for ML Kit.
class CameraInputImage {
  static final _orientations = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  static InputImage? fromCameraImage(
    CameraImage image,
    CameraController controller, {
    bool cropToCenter = false,
    double cropRatio = 0.7,
  }) {
    try {
      final rotation = _getImageRotation(controller);

      if (image.format.group == ImageFormatGroup.yuv420) {
        final nv21 = yuv420ToNv21(image);
        if (nv21 == null) return null;

        var bytes = nv21;
        var width = image.width;
        var height = image.height;

        // Crop only after a correct NV21 buffer exists.
        if (cropToCenter) {
          final cropped = cropNv21Center(bytes, width, height, cropRatio);
          if (cropped != null) {
            bytes = cropped.bytes;
            width = cropped.width;
            height = cropped.height;
          }
        }

        return InputImage.fromBytes(
          bytes: bytes,
          metadata: InputImageMetadata(
            size: Size(width.toDouble(), height.toDouble()),
            rotation: rotation,
            format: InputImageFormat.nv21,
            bytesPerRow: width,
          ),
        );
      }

      if (image.format.group == ImageFormatGroup.bgra8888 &&
          image.planes.isNotEmpty) {
        final plane = image.planes.first;
        return InputImage.fromBytes(
          bytes: plane.bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: rotation,
            format: InputImageFormat.bgra8888,
            bytesPerRow: plane.bytesPerRow,
          ),
        );
      }

      return null;
    } catch (e, st) {
      debugPrint('CameraInputImage conversion failed: $e\n$st');
      return null;
    }
  }

  static InputImageRotation rotationFor({required CameraController controller}) {
    return _getImageRotation(controller);
  }

  static InputImageRotation _getImageRotation(CameraController controller) {
    final camera = controller.description;
    final sensorOrientation = camera.sensorOrientation;
    final deviceOrientation = controller.value.deviceOrientation;
    final rotationCompensation = _orientations[deviceOrientation] ?? 0;

    late int rotation;
    if (Platform.isAndroid) {
      if (camera.lensDirection == CameraLensDirection.front) {
        rotation = (sensorOrientation + rotationCompensation) % 360;
        rotation = (360 - rotation) % 360;
      } else {
        rotation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
    } else {
      rotation = sensorOrientation;
    }

    return InputImageRotationValue.fromRawValue(rotation) ??
        InputImageRotation.rotation0deg;
  }

  /// Builds contiguous NV21 (YYYY... VUVU...) respecting plane strides.
  static Uint8List? yuv420ToNv21(CameraImage image) {
    if (image.planes.length < 3) return null;

    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yRowStride = yPlane.bytesPerRow;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;

    final out = Uint8List(width * height + width * height ~/ 2);
    var outIndex = 0;

    for (var row = 0; row < height; row++) {
      final rowStart = row * yRowStride;
      for (var col = 0; col < width; col++) {
        out[outIndex++] = yPlane.bytes[rowStart + col];
      }
    }

    // NV21 = VU interleaved.
    for (var row = 0; row < height ~/ 2; row++) {
      final uRowStart = row * uvRowStride;
      final vRowStart = row * vPlane.bytesPerRow;
      for (var col = 0; col < width ~/ 2; col++) {
        final uvOffset = col * uvPixelStride;
        out[outIndex++] = vPlane.bytes[vRowStart + uvOffset];
        out[outIndex++] = uPlane.bytes[uRowStart + uvOffset];
      }
    }

    return out;
  }

  static CroppedNv21? cropNv21Center(
    Uint8List nv21,
    int width,
    int height,
    double ratio,
  ) {
    final cropW = (width * ratio).round() & ~1;
    final cropH = (height * ratio).round() & ~1;
    if (cropW < 2 || cropH < 2) return null;

    final left = ((width - cropW) / 2).round() & ~1;
    final top = ((height - cropH) / 2).round() & ~1;
    final cropped = Uint8List(cropW * cropH + cropW * cropH ~/ 2);

    for (var row = 0; row < cropH; row++) {
      final src = (top + row) * width + left;
      final dst = row * cropW;
      cropped.setRange(dst, dst + cropW, nv21, src);
    }

    final ySize = width * height;
    final cropYSize = cropW * cropH;
    final uvTop = top ~/ 2;
    final uvLeft = left;

    for (var row = 0; row < cropH ~/ 2; row++) {
      final src = ySize + (uvTop + row) * width + uvLeft;
      final dst = cropYSize + row * cropW;
      cropped.setRange(dst, dst + cropW, nv21, src);
    }

    return CroppedNv21(bytes: cropped, width: cropW, height: cropH);
  }
}

class CroppedNv21 {
  final Uint8List bytes;
  final int width;
  final int height;

  CroppedNv21({
    required this.bytes,
    required this.width,
    required this.height,
  });
}
