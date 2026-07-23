import 'dart:typed_data';

/// Everything convertYuv420ToRgb needs, bundled into one object so it
/// can be handed to compute() (which passes a single argument to a
/// top-level function on a background isolate).
class Yuv420ToRgbRequest {
  final int width;
  final int height;
  final Uint8List yBytes;
  final int yStride;
  final Uint8List uBytes;
  final int uStride;
  final int uPixelStride;
  final Uint8List vBytes;
  final int vStride;
  final int vPixelStride;

  const Yuv420ToRgbRequest({
    required this.width,
    required this.height,
    required this.yBytes,
    required this.yStride,
    required this.uBytes,
    required this.uStride,
    required this.uPixelStride,
    required this.vBytes,
    required this.vStride,
    required this.vPixelStride,
  });
}

/// Converts a phone camera's YUV420 frame to tightly packed RGB8
/// bytes — sensor_msgs/Image's most portable encoding, since raw YUV
/// planes aren't something the rest of the ROS ecosystem can consume
/// directly. Meant to run via `compute()` on a background isolate:
/// per-frame conversion at even a throttled camera rate is real CPU
/// work, and this app already has a documented past incident about
/// per-frame work causing UI-thread jank.
Uint8List convertYuv420ToRgb(Yuv420ToRgbRequest req) {
  final out = Uint8List(req.width * req.height * 3);
  var outIndex = 0;
  for (var y = 0; y < req.height; y++) {
    final yRow = y * req.yStride;
    final uvRow = (y >> 1) * req.uStride;
    for (var x = 0; x < req.width; x++) {
      final yValue = req.yBytes[yRow + x];
      final uvIndex = uvRow + (x >> 1) * req.uPixelStride;
      final uValue = req.uBytes[uvIndex] - 128;
      final vValue = req.vBytes[uvIndex] - 128;

      // ITU-R BT.601 YUV -> RGB.
      final r = (yValue + 1.402 * vValue).round().clamp(0, 255);
      final g = (yValue - 0.344136 * uValue - 0.714136 * vValue).round().clamp(
        0,
        255,
      );
      final b = (yValue + 1.772 * uValue).round().clamp(0, 255);

      out[outIndex++] = r;
      out[outIndex++] = g;
      out[outIndex++] = b;
    }
  }
  return out;
}
