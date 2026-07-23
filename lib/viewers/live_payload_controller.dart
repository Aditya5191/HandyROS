import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';

import '../models/live_payload.dart';
import '../models/topic.dart';
import '../services/dds_topic_service.dart';
import 'sim_clock.dart';

typedef _ImageConvertArgs = (
  Uint8List bytes,
  int width,
  int height,
  int step,
  String encoding,
  bool isBigEndian,
);

/// Runs off the UI thread via [compute] — converting a raw ROS pixel
/// buffer to RGBA8888 for `ui.decodeImageFromPixels` is real per-frame
/// CPU work (a few hundred KB–MB, several times a second for a live
/// camera feed) that would otherwise jank the UI thread, the same
/// resource-conscious reasoning behind the topic-list overload fix.
/// Returns null for an encoding with no decoder (caller shows an
/// honest "unsupported encoding" state rather than garbage pixels).
Uint8List? _convertImageToRgba(_ImageConvertArgs args) {
  final (bytes, w, h, step, encoding, isBigEndian) = args;
  final out = Uint8List(w * h * 4);

  switch (encoding) {
    case 'rgb8':
    case 'bgr8':
      final swap = encoding == 'bgr8';
      for (int y = 0; y < h; y++) {
        final rowStart = y * step;
        for (int x = 0; x < w; x++) {
          final si = rowStart + x * 3;
          if (si + 2 >= bytes.length) continue;
          final di = (y * w + x) * 4;
          out[di] = swap ? bytes[si + 2] : bytes[si];
          out[di + 1] = bytes[si + 1];
          out[di + 2] = swap ? bytes[si] : bytes[si + 2];
          out[di + 3] = 255;
        }
      }
      return out;

    case 'rgba8':
    case 'bgra8':
      final swap = encoding == 'bgra8';
      for (int y = 0; y < h; y++) {
        final rowStart = y * step;
        for (int x = 0; x < w; x++) {
          final si = rowStart + x * 4;
          if (si + 3 >= bytes.length) continue;
          final di = (y * w + x) * 4;
          out[di] = swap ? bytes[si + 2] : bytes[si];
          out[di + 1] = bytes[si + 1];
          out[di + 2] = swap ? bytes[si] : bytes[si + 2];
          out[di + 3] = bytes[si + 3];
        }
      }
      return out;

    case 'mono8':
      for (int y = 0; y < h; y++) {
        final rowStart = y * step;
        for (int x = 0; x < w; x++) {
          final si = rowStart + x;
          if (si >= bytes.length) continue;
          final di = (y * w + x) * 4;
          final v = bytes[si];
          out[di] = v;
          out[di + 1] = v;
          out[di + 2] = v;
          out[di + 3] = 255;
        }
      }
      return out;

    case 'mono16':
    case '16UC1':
      {
        // Depth-ish single-channel data has no fixed display range, so
        // auto-normalize this frame's actual min..max to 0..255. 0 is
        // treated as "no return" (common sensor convention) and drawn
        // black rather than folded into the normalization range.
        int minV = 0xFFFF, maxV = 0;
        int readU16(int si) => isBigEndian
            ? (bytes[si] << 8) | bytes[si + 1]
            : bytes[si] | (bytes[si + 1] << 8);
        for (int y = 0; y < h; y++) {
          final rowStart = y * step;
          for (int x = 0; x < w; x++) {
            final si = rowStart + x * 2;
            if (si + 1 >= bytes.length) continue;
            final v = readU16(si);
            if (v == 0) continue;
            if (v < minV) minV = v;
            if (v > maxV) maxV = v;
          }
        }
        final range = (maxV - minV).clamp(1, 0xFFFF);
        for (int y = 0; y < h; y++) {
          final rowStart = y * step;
          for (int x = 0; x < w; x++) {
            final si = rowStart + x * 2;
            if (si + 1 >= bytes.length) continue;
            final di = (y * w + x) * 4;
            final v = readU16(si);
            final g = v == 0 ? 0 : (((v - minV) * 255) ~/ range);
            out[di] = g;
            out[di + 1] = g;
            out[di + 2] = g;
            out[di + 3] = 255;
          }
        }
        return out;
      }

    case '32FC1':
      {
        final byteData = ByteData.sublistView(bytes);
        final endian = isBigEndian ? Endian.big : Endian.little;
        double minV = double.infinity, maxV = double.negativeInfinity;
        for (int y = 0; y < h; y++) {
          final rowStart = y * step;
          for (int x = 0; x < w; x++) {
            final si = rowStart + x * 4;
            if (si + 3 >= bytes.length) continue;
            final v = byteData.getFloat32(si, endian);
            if (!v.isFinite || v <= 0) continue;
            if (v < minV) minV = v;
            if (v > maxV) maxV = v;
          }
        }
        final range = maxV - minV;
        final safeRange = (range.isFinite && range > 0) ? range : 1.0;
        for (int y = 0; y < h; y++) {
          final rowStart = y * step;
          for (int x = 0; x < w; x++) {
            final si = rowStart + x * 4;
            if (si + 3 >= bytes.length) continue;
            final di = (y * w + x) * 4;
            final v = byteData.getFloat32(si, endian);
            final g = (!v.isFinite || v <= 0)
                ? 0
                : (((v - minV) / safeRange) * 255).clamp(0, 255).toInt();
            out[di] = g;
            out[di + 1] = g;
            out[di + 2] = g;
            out[di + 3] = 255;
          }
        }
        return out;
      }

    default:
      return null;
  }
}

class TfFrameState {
  final String parent;
  final Vec3 translation;
  final Quat rotation;
  final DateTime lastSeen;
  final double rateHz;

  const TfFrameState({
    required this.parent,
    required this.translation,
    required this.rotation,
    required this.lastSeen,
    required this.rateHz,
  });
}

class LogEntry {
  final DateTime timestamp;
  final LogSample sample;
  const LogEntry(this.timestamp, this.sample);
}

/// Feeds a Viewer screen with real decoded message data, polling
/// handyros_core at 10Hz (deliberately capped — this is an inspection
/// tool, not real-time video, and matches the resource-conscious
/// approach taken for the topic-list overload fix earlier). A single
/// "latest sample" from the native side isn't enough for widgets that
/// need history (odometry trail, scrolling graph/terminal, the TF
/// tree) — that accumulation happens here, client-side.
///
/// When no native DDS layer is available (`dds` is null — unsupported
/// platform, or `flutter test`), falls back to the old synthetic
/// [SimClock] demo so the app is still browsable; [isLive] tells
/// widgets which mode they're in so they can render the fake
/// procedural scene the same way they always have.
class LivePayloadController extends ChangeNotifier {
  final DdsTopicService? _dds;
  final Topic topic;
  final SimClock? sim;

  Timer? _timer;

  ImuSample? imu;
  ImageSample? image;
  ui.Image? decodedImage;
  String? imageDecodeError;
  int _imageDecodeToken = 0;
  LaserScanSample? laserScan;
  PointCloudSample? pointCloud;
  OdomSample? odom;
  LogSample? lastLog;
  FloatSample? lastFloat;

  final List<({double x, double y})> odomTrail = [];
  final List<double> floatHistory = [];
  final List<LogEntry> logLines = [];
  final Map<String, TfFrameState> tfFrames = {};

  // Point cloud viewing angle/zoom — user-controlled via drag/pinch on
  // the canvas (see PointCloudPainter + the gesture wiring in
  // ViewerScreen), not tied to real data. Defaults match the old fixed
  // viewing angle so the cloud looks the same before anyone touches it.
  double cloudYaw = 0.5;
  double cloudPitch = 0.0;
  double cloudZoom = 1.0;
  double? _zoomGestureStart;

  void rotateCloud(double dYaw, double dPitch) {
    cloudYaw += dYaw;
    cloudPitch = (cloudPitch + dPitch).clamp(-1.4, 1.4);
    notifyListeners();
  }

  /// Call once when a pinch gesture begins, before any [updateCloudZoom]
  /// calls — Flutter's scale details are cumulative *since the gesture
  /// started*, not per-frame, so applying them relative to whatever
  /// zoom was current at that moment (not the latest notifyListeners
  /// rebuild, which can happen many times per gesture at 10Hz) avoids
  /// the zoom runaway multiplying a cumulative factor every frame would
  /// cause.
  void startCloudZoomGesture() => _zoomGestureStart = cloudZoom;

  void updateCloudZoom(double cumulativeScaleSinceGestureStart) {
    final start = _zoomGestureStart ?? cloudZoom;
    cloudZoom = (start * cumulativeScaleSinceGestureStart).clamp(0.3, 4.0);
    notifyListeners();
  }

  bool get isLive => _dds != null;

  /// Up-to-date rate/size/bandwidth/latency for this topic (the same
  /// stats the topic list shows), re-looked-up on every tick rather
  /// than frozen at the moment the Viewer screen opened.
  Topic? get liveTopic {
    final dds = _dds;
    if (dds == null) return null;
    for (final t in dds.topics) {
      if (t.name == topic.name) return t;
    }
    return null;
  }

  LivePayloadController({
    required DdsTopicService? dds,
    required this.topic,
    required TickerProvider vsync,
  }) : _dds = dds,
       sim = dds == null ? (SimClock()..start(vsync)) : null {
    final ddsLocal = _dds;
    if (ddsLocal != null) {
      ddsLocal.watchTopic(topic.name);
      ddsLocal.watchPayload(topic.name);
      _tick();
      _timer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _tick(),
      );
    } else {
      sim!.addListener(notifyListeners);
    }
  }

  void _tick() {
    final dds = _dds;
    if (dds == null) return;
    final payload = dds.latestPayload(topic.name);
    switch (payload) {
      case ImuSample s:
        imu = s;
      case ImageSample s:
        image = s;
        unawaited(_decodeImage(s));
      case LaserScanSample s:
        laserScan = s;
      case PointCloudSample s:
        pointCloud = s;
      case OdomSample s:
        odom = s;
        odomTrail.add((x: s.position.x, y: s.position.y));
        if (odomTrail.length > 260) {
          odomTrail.removeAt(0);
        }
      case List<TfTransformSample> transforms:
        final now = DateTime.now();
        for (final t in transforms) {
          final prev = tfFrames[t.child];
          final elapsedMs = prev == null
              ? 0
              : now.difference(prev.lastSeen).inMilliseconds;
          final rateHz = (prev == null || elapsedMs <= 0)
              ? (prev?.rateHz ?? 0.0)
              : 1000 / elapsedMs;
          tfFrames[t.child] = TfFrameState(
            parent: t.parent,
            translation: t.translation,
            rotation: t.rotation,
            lastSeen: now,
            rateHz: rateHz,
          );
        }
      case LogSample s:
        lastLog = s;
        logLines.add(LogEntry(DateTime.now(), s));
        if (logLines.length > 200) {
          logLines.removeAt(0);
        }
      case FloatSample s:
        lastFloat = s;
        floatHistory.add(s.value);
        if (floatHistory.length > 120) {
          floatHistory.removeAt(0);
        }
      case null:
        break;
    }
    notifyListeners();
  }

  Future<void> _decodeImage(ImageSample s) async {
    final token = ++_imageDecodeToken;
    final rgba = await compute(_convertImageToRgba, (
      s.bytes,
      s.width,
      s.height,
      s.step,
      s.encoding,
      s.isBigEndian,
    ));
    if (token != _imageDecodeToken) {
      return; // superseded by a newer frame while we were decoding
    }
    if (rgba == null) {
      imageDecodeError = 'No decoder for encoding "${s.encoding}"';
      notifyListeners();
      return;
    }
    ui.decodeImageFromPixels(rgba, s.width, s.height, ui.PixelFormat.rgba8888, (
      img,
    ) {
      if (token != _imageDecodeToken) {
        img.dispose();
        return;
      }
      imageDecodeError = null;
      final old = decodedImage;
      decodedImage = img;
      old?.dispose();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    decodedImage?.dispose();
    final dds = _dds;
    if (dds != null) {
      dds.unwatchPayload(topic.name);
      dds.unwatchTopic(topic.name);
    } else {
      sim?.dispose();
    }
    super.dispose();
  }
}
