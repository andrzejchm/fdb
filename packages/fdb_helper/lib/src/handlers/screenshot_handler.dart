import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'handler_utils.dart';

Future<developer.ServiceExtensionResponse> handleScreenshot(
  String method,
  Map<String, String> params,
) async {
  ui.Scene? scene;
  ui.Image? image;
  try {
    final renderViews = WidgetsBinding.instance.renderViews;
    if (renderViews.isEmpty) {
      return errorResponse('No render views available');
    }

    final view = renderViews.first;
    final flutterView = view.flutterView;

    // Ensure the frame is painted before capturing.
    // ignore: invalid_use_of_protected_member
    if (view.debugNeedsPaint || view.layer == null) {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
    }

    // ignore: invalid_use_of_protected_member
    final layer = view.layer;
    if (layer == null) {
      return errorResponse('Render view layer is null');
    }

    // Capture at physical pixel resolution.
    final size = flutterView.physicalSize;
    final width = size.width.ceil();
    final height = size.height.ceil();

    if (width <= 0 || height <= 0) {
      return errorResponse('Invalid view size: ${width}x$height');
    }

    if (!layer.attached) {
      return errorResponse('Render view layer is detached');
    }

    final builder = ui.SceneBuilder();
    layer.addToScene(builder);
    scene = builder.build();
    image = await scene.toImage(width, height);

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      return errorResponse('Failed to encode image as PNG');
    }

    final base64Data = base64Encode(byteData.buffer.asUint8List());
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'screenshot': base64Data}),
    );
  } catch (e) {
    return errorResponse('Screenshot failed: $e');
  } finally {
    scene?.dispose();
    image?.dispose();
  }
}
