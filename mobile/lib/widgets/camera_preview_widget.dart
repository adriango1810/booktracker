import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class CameraPreviewWidget extends StatelessWidget {
  final CameraController cameraController;

  const CameraPreviewWidget({
    super.key,
    required this.cameraController,
  });

  @override
  Widget build(BuildContext context) {
    if (!cameraController.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }

    // Fill the screen without stretching (BoxFit.cover behaviour).
    final mediaSize = MediaQuery.sizeOf(context);
    final previewAspect = cameraController.value.aspectRatio;
    // In portrait the controller aspect is still sensor-oriented (w/h).
    var scale = mediaSize.aspectRatio * previewAspect;
    if (scale < 1) scale = 1 / scale;

    return ClipRect(
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.center,
        child: Center(
          child: AspectRatio(
            aspectRatio: 1 / previewAspect,
            child: CameraPreview(cameraController),
          ),
        ),
      ),
    );
  }
}
