import 'dart:math';
import 'dart:typed_data';

/// Typed decoded-message models parsed from handyros_core's per-topic
/// payload JSON (+ paired binary blob for Image/PointCloud2) — see
/// TopicPayloadTracker::latestJson in handyros_core for the native
/// side of this shape. Each viewer only ever constructs the one type
/// it cares about, based on the topic's already-known ViewerPlugin key.

class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);
  static const zero = Vec3(0, 0, 0);

  factory Vec3.fromJson(Map<String, dynamic> j) => Vec3(
    (j['x'] as num).toDouble(),
    (j['y'] as num).toDouble(),
    (j['z'] as num).toDouble(),
  );
}

class Quat {
  final double x, y, z, w;
  const Quat(this.x, this.y, this.z, this.w);
  static const identity = Quat(0, 0, 0, 1);

  factory Quat.fromJson(Map<String, dynamic> j) => Quat(
    (j['x'] as num).toDouble(),
    (j['y'] as num).toDouble(),
    (j['z'] as num).toDouble(),
    (j['w'] as num).toDouble(),
  );

  /// Roll/pitch/yaw in radians (aerospace ZYX convention).
  ({double roll, double pitch, double yaw}) toEuler() {
    final sinrCosp = 2 * (w * x + y * z);
    final cosrCosp = 1 - 2 * (x * x + y * y);
    final roll = atan2(sinrCosp, cosrCosp);

    final sinp = 2 * (w * y - z * x);
    final pitch = sinp.abs() >= 1 ? (pi / 2) * sinp.sign : asin(sinp);

    final sinyCosp = 2 * (w * z + x * y);
    final cosyCosp = 1 - 2 * (y * y + z * z);
    final yaw = atan2(sinyCosp, cosyCosp);

    return (roll: roll, pitch: pitch, yaw: yaw);
  }
}

class ImuSample {
  final String frameId;
  final Quat orientation;
  final Vec3 angularVelocity;
  final Vec3 linearAcceleration;

  const ImuSample({
    required this.frameId,
    required this.orientation,
    required this.angularVelocity,
    required this.linearAcceleration,
  });

  factory ImuSample.fromJson(Map<String, dynamic> j) => ImuSample(
    frameId: j['frameId'] as String? ?? '',
    orientation: Quat.fromJson(j['orientation'] as Map<String, dynamic>),
    angularVelocity: Vec3.fromJson(
      j['angularVelocity'] as Map<String, dynamic>,
    ),
    linearAcceleration: Vec3.fromJson(
      j['linearAcceleration'] as Map<String, dynamic>,
    ),
  );
}

class ImageSample {
  final String frameId;
  final int width;
  final int height;
  final int step;
  final String encoding;
  final bool isBigEndian;
  final Uint8List bytes;

  const ImageSample({
    required this.frameId,
    required this.width,
    required this.height,
    required this.step,
    required this.encoding,
    required this.isBigEndian,
    required this.bytes,
  });

  factory ImageSample.fromJson(Map<String, dynamic> j, Uint8List bytes) =>
      ImageSample(
        frameId: j['frameId'] as String? ?? '',
        width: j['width'] as int,
        height: j['height'] as int,
        step: j['step'] as int,
        encoding: j['encoding'] as String? ?? '',
        isBigEndian: j['isBigEndian'] as bool? ?? false,
        bytes: bytes,
      );
}

class LaserScanSample {
  final String frameId;
  final double angleMin;
  final double angleMax;
  final double angleIncrement;
  final double rangeMin;
  final double rangeMax;
  final List<double> ranges;

  const LaserScanSample({
    required this.frameId,
    required this.angleMin,
    required this.angleMax,
    required this.angleIncrement,
    required this.rangeMin,
    required this.rangeMax,
    required this.ranges,
  });

  factory LaserScanSample.fromJson(Map<String, dynamic> j) => LaserScanSample(
    frameId: j['frameId'] as String? ?? '',
    angleMin: (j['angleMin'] as num).toDouble(),
    angleMax: (j['angleMax'] as num).toDouble(),
    angleIncrement: (j['angleIncrement'] as num).toDouble(),
    rangeMin: (j['rangeMin'] as num).toDouble(),
    rangeMax: (j['rangeMax'] as num).toDouble(),
    ranges: (j['ranges'] as List<dynamic>)
        .map((e) => (e as num).toDouble())
        .toList(),
  );
}

/// [xyz] is a zero-copy view over the raw blob: 4 float32 per point,
/// [x,y,z,colorBits]. [colorBits] is a same-buffer Uint32 view of the
/// same bytes — reading the color slot as raw bits (not going through
/// a float round-trip) since it's a bit-packed RGB value, not a real
/// float. Only meaningful per-point when [colorMode] == 'rgb'.
class PointCloudSample {
  final String frameId;
  final int width;
  final int height;
  final int pointCount;
  final String colorMode;
  final Float32List xyz;
  final Uint32List colorBits;

  const PointCloudSample({
    required this.frameId,
    required this.width,
    required this.height,
    required this.pointCount,
    required this.colorMode,
    required this.xyz,
    required this.colorBits,
  });

  factory PointCloudSample.fromJson(Map<String, dynamic> j, Uint8List blob) {
    final floatCount = blob.lengthInBytes ~/ 4;
    return PointCloudSample(
      frameId: j['frameId'] as String? ?? '',
      width: j['width'] as int,
      height: j['height'] as int,
      pointCount: j['pointCount'] as int,
      colorMode: j['colorMode'] as String? ?? 'none',
      xyz: blob.buffer.asFloat32List(blob.offsetInBytes, floatCount),
      colorBits: blob.buffer.asUint32List(blob.offsetInBytes, floatCount),
    );
  }
}

class OdomSample {
  final String frameId;
  final String childFrameId;
  final Vec3 position;
  final Quat orientation;
  final Vec3 linearVelocity;
  final Vec3 angularVelocity;

  const OdomSample({
    required this.frameId,
    required this.childFrameId,
    required this.position,
    required this.orientation,
    required this.linearVelocity,
    required this.angularVelocity,
  });

  factory OdomSample.fromJson(Map<String, dynamic> j) => OdomSample(
    frameId: j['frameId'] as String? ?? '',
    childFrameId: j['childFrameId'] as String? ?? '',
    position: Vec3.fromJson(j['position'] as Map<String, dynamic>),
    orientation: Quat.fromJson(j['orientation'] as Map<String, dynamic>),
    linearVelocity: Vec3.fromJson(j['linearVelocity'] as Map<String, dynamic>),
    angularVelocity: Vec3.fromJson(
      j['angularVelocity'] as Map<String, dynamic>,
    ),
  );
}

class TfTransformSample {
  final String parent;
  final String child;
  final Vec3 translation;
  final Quat rotation;

  const TfTransformSample({
    required this.parent,
    required this.child,
    required this.translation,
    required this.rotation,
  });

  factory TfTransformSample.fromJson(Map<String, dynamic> j) =>
      TfTransformSample(
        parent: j['parent'] as String? ?? '',
        child: j['child'] as String? ?? '',
        translation: Vec3.fromJson(j['translation'] as Map<String, dynamic>),
        rotation: Quat.fromJson(j['rotation'] as Map<String, dynamic>),
      );
}

List<TfTransformSample> parseTfTransforms(Map<String, dynamic> j) =>
    (j['transforms'] as List<dynamic>)
        .map((e) => TfTransformSample.fromJson(e as Map<String, dynamic>))
        .toList();

/// Covers both plain std_msgs/String (no level/name) and
/// rcl_interfaces/Log (has both) — the Terminal viewer displays
/// either uniformly.
class LogSample {
  final int? level;
  final String? name;
  final String text;

  const LogSample({this.level, this.name, required this.text});

  factory LogSample.fromJson(Map<String, dynamic> j) => LogSample(
    level: j['level'] as int?,
    name: j['name'] as String?,
    text: j['text'] as String? ?? '',
  );
}

/// Covers both std_msgs/Float32 and std_msgs/Float64 — the Graph
/// viewer treats them identically.
class FloatSample {
  final double value;
  const FloatSample(this.value);

  factory FloatSample.fromJson(Map<String, dynamic> j) =>
      FloatSample((j['value'] as num).toDouble());
}
