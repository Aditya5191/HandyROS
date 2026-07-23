import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _InitializeNative =
    Bool Function(Uint32 domainId, Pointer<Utf8> peersCsv);
typedef _VoidFnNative = Void Function();
typedef _TopicsJsonNative = Pointer<Utf8> Function();
typedef _FreeStringNative = Void Function(Pointer<Utf8>);
typedef _WatchTopicNative = Void Function(Pointer<Utf8> topicName);
typedef _PayloadJsonNative = Pointer<Utf8> Function(Pointer<Utf8> topicName);
typedef _PayloadBlobNative =
    Pointer<Uint8> Function(Pointer<Utf8> topicName, Pointer<Uint64> outLen);
typedef _FreeBlobNative = Void Function(Pointer<Uint8>);

typedef _PublishTwistNative =
    Void Function(
      Pointer<Utf8> topicName,
      Double lx,
      Double ly,
      Double lz,
      Double ax,
      Double ay,
      Double az,
    );
typedef _PublishTwistDart =
    void Function(
      Pointer<Utf8> topicName,
      double lx,
      double ly,
      double lz,
      double ax,
      double ay,
      double az,
    );
typedef _PublishImuNative =
    Void Function(
      Pointer<Utf8> topicName,
      Pointer<Utf8> frameId,
      Double ax,
      Double ay,
      Double az,
      Double gx,
      Double gy,
      Double gz,
      Double qx,
      Double qy,
      Double qz,
      Double qw,
    );
typedef _PublishImuDart =
    void Function(
      Pointer<Utf8> topicName,
      Pointer<Utf8> frameId,
      double ax,
      double ay,
      double az,
      double gx,
      double gy,
      double gz,
      double qx,
      double qy,
      double qz,
      double qw,
    );
typedef _PublishNavSatFixNative =
    Void Function(
      Pointer<Utf8> topicName,
      Pointer<Utf8> frameId,
      Double latitude,
      Double longitude,
      Double altitude,
    );
typedef _PublishNavSatFixDart =
    void Function(
      Pointer<Utf8> topicName,
      Pointer<Utf8> frameId,
      double latitude,
      double longitude,
      double altitude,
    );
typedef _PublishMagneticFieldNative =
    Void Function(
      Pointer<Utf8> topicName,
      Pointer<Utf8> frameId,
      Double x,
      Double y,
      Double z,
    );
typedef _PublishMagneticFieldDart =
    void Function(
      Pointer<Utf8> topicName,
      Pointer<Utf8> frameId,
      double x,
      double y,
      double z,
    );
typedef _PublishImageNative =
    Void Function(
      Pointer<Utf8> topicName,
      Pointer<Utf8> frameId,
      Uint32 width,
      Uint32 height,
      Pointer<Utf8> encoding,
      Bool isBigEndian,
      Uint32 step,
      Pointer<Uint8> data,
      Uint64 dataLen,
    );
typedef _PublishImageDart =
    void Function(
      Pointer<Utf8> topicName,
      Pointer<Utf8> frameId,
      int width,
      int height,
      Pointer<Utf8> encoding,
      bool isBigEndian,
      int step,
      Pointer<Uint8> data,
      int dataLen,
    );
typedef _PublishStopNative = Void Function(Pointer<Utf8> topicName);

/// dart:ffi bridge to handyros_core's C API (see handyros_core/include/handyros.h).
///
/// Only built/bundled for Linux desktop so far — this is the seam for
/// discovering real ROS 2 topics; Android/iOS packaging of the native
/// lib is future work (see CLAUDE.md).
class HandyrosBindings {
  final DynamicLibrary _lib;

  late final bool Function(int domainId, Pointer<Utf8> peersCsv) _initialize =
      _lib.lookupFunction<_InitializeNative, bool Function(int, Pointer<Utf8>)>(
        'handyros_initialize',
      );
  late final void Function() shutdown = _lib
      .lookupFunction<_VoidFnNative, void Function()>('handyros_shutdown');
  late final void Function() poll = _lib
      .lookupFunction<_VoidFnNative, void Function()>('handyros_poll');
  late final Pointer<Utf8> Function() _topicsJson = _lib
      .lookupFunction<_TopicsJsonNative, Pointer<Utf8> Function()>(
        'handyros_topics_json',
      );
  late final void Function(Pointer<Utf8>) _freeString = _lib
      .lookupFunction<_FreeStringNative, void Function(Pointer<Utf8>)>(
        'handyros_free_string',
      );
  late final void Function(Pointer<Utf8>) _watchTopic = _lib
      .lookupFunction<_WatchTopicNative, void Function(Pointer<Utf8>)>(
        'handyros_watch_topic',
      );
  late final void Function(Pointer<Utf8>) _unwatchTopic = _lib
      .lookupFunction<_WatchTopicNative, void Function(Pointer<Utf8>)>(
        'handyros_unwatch_topic',
      );
  late final void Function(Pointer<Utf8>) _watchPayload = _lib
      .lookupFunction<_WatchTopicNative, void Function(Pointer<Utf8>)>(
        'handyros_watch_payload',
      );
  late final void Function(Pointer<Utf8>) _unwatchPayload = _lib
      .lookupFunction<_WatchTopicNative, void Function(Pointer<Utf8>)>(
        'handyros_unwatch_payload',
      );
  late final Pointer<Utf8> Function(Pointer<Utf8>) _topicPayloadJson = _lib
      .lookupFunction<
        _PayloadJsonNative,
        Pointer<Utf8> Function(Pointer<Utf8>)
      >('handyros_topic_payload_json');
  late final Pointer<Uint8> Function(Pointer<Utf8>, Pointer<Uint64>)
  _topicPayloadBlob = _lib
      .lookupFunction<
        _PayloadBlobNative,
        Pointer<Uint8> Function(Pointer<Utf8>, Pointer<Uint64>)
      >('handyros_topic_payload_blob');
  late final void Function(Pointer<Uint8>) _freeBlob = _lib
      .lookupFunction<_FreeBlobNative, void Function(Pointer<Uint8>)>(
        'handyros_free_blob',
      );

  late final _PublishTwistDart _publishTwist = _lib
      .lookupFunction<_PublishTwistNative, _PublishTwistDart>(
        'handyros_publish_twist',
      );
  late final _PublishImuDart _publishImu = _lib
      .lookupFunction<_PublishImuNative, _PublishImuDart>(
        'handyros_publish_imu',
      );
  late final _PublishNavSatFixDart _publishNavSatFix = _lib
      .lookupFunction<_PublishNavSatFixNative, _PublishNavSatFixDart>(
        'handyros_publish_nav_sat_fix',
      );
  late final _PublishMagneticFieldDart _publishMagneticField = _lib
      .lookupFunction<_PublishMagneticFieldNative, _PublishMagneticFieldDart>(
        'handyros_publish_magnetic_field',
      );
  late final _PublishImageDart _publishImage = _lib
      .lookupFunction<_PublishImageNative, _PublishImageDart>(
        'handyros_publish_image',
      );
  late final void Function(Pointer<Utf8>) _publishStop = _lib
      .lookupFunction<_PublishStopNative, void Function(Pointer<Utf8>)>(
        'handyros_publish_stop',
      );

  HandyrosBindings._(this._lib);

  /// Throws if the native library can't be found/loaded on this platform.
  factory HandyrosBindings.open() => HandyrosBindings._(_openLibrary());

  static DynamicLibrary _openLibrary() {
    const libName = 'libhandyros_core.so';

    final override = Platform.environment['HANDYROS_CORE_LIB'];
    if (override != null) {
      return DynamicLibrary.open(override);
    }

    if (Platform.isAndroid) {
      return DynamicLibrary.open(libName);
    }
    if (Platform.isLinux) {
      // Dev-loop convenience: `flutter run -d linux` is run from the
      // repo root, and the native lib isn't packaged into the bundle
      // yet, so look next to its CMake build output first.
      final devPath = '${Directory.current.path}/handyros_core/build/$libName';
      if (File(devPath).existsSync()) {
        return DynamicLibrary.open(devPath);
      }
      return DynamicLibrary.open(libName);
    }
    throw UnsupportedError('handyros_core has no build for this platform yet');
  }

  /// [peers] are extra host IPs to reach via unicast discovery, used
  /// alongside multicast — needed on networks that don't forward
  /// multicast between Wi-Fi clients (phone hotspots, plenty of
  /// consumer routers with client isolation).
  bool initialize(int domainId, {List<String> peers = const []}) {
    final peersPtr = peers.join(',').toNativeUtf8();
    try {
      return _initialize(domainId, peersPtr);
    } finally {
      calloc.free(peersPtr);
    }
  }

  /// JSON array of currently known topics — see handyros.h for the shape.
  String topicsJson() {
    final ptr = _topicsJson();
    if (ptr == nullptr) return '[]';
    try {
      return ptr.toDartString();
    } finally {
      _freeString(ptr);
    }
  }

  /// Starts/stops measuring real rate/size/bandwidth/latency for one
  /// topic. Not automatic for every discovered topic — see handyros.h.
  void watchTopic(String topicName) =>
      _withNativeString(topicName, _watchTopic);
  void unwatchTopic(String topicName) =>
      _withNativeString(topicName, _unwatchTopic);

  /// Starts/stops decoding real message field values for one topic —
  /// only meaningful for the fixed set of types with a dedicated
  /// Viewer screen. See handyros.h.
  void watchPayload(String topicName) =>
      _withNativeString(topicName, _watchPayload);
  void unwatchPayload(String topicName) =>
      _withNativeString(topicName, _unwatchPayload);

  /// Decoded fields for the latest sample of [topicName], as JSON —
  /// see handyros_topic_payload_json in handyros.h for the shape.
  String topicPayloadJson(String topicName) {
    final namePtr = topicName.toNativeUtf8();
    try {
      final ptr = _topicPayloadJson(namePtr);
      if (ptr == nullptr) return '{"available":false,"supported":false}';
      try {
        return ptr.toDartString();
      } finally {
        _freeString(ptr);
      }
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Raw binary payload paired with [topicPayloadJson] (image pixel
  /// bytes, or pre-extracted point cloud float32 tuples) — empty if
  /// the type has no blob component or no sample has arrived yet.
  /// Copies into a Dart-owned buffer before releasing native memory.
  Uint8List topicPayloadBlob(String topicName) {
    final namePtr = topicName.toNativeUtf8();
    final lenPtr = calloc<Uint64>();
    try {
      final blobPtr = _topicPayloadBlob(namePtr, lenPtr);
      if (blobPtr == nullptr) return Uint8List(0);
      try {
        final len = lenPtr.value;
        return Uint8List.fromList(blobPtr.asTypedList(len));
      } finally {
        _freeBlob(blobPtr);
      }
    } finally {
      calloc.free(namePtr);
      calloc.free(lenPtr);
    }
  }

  /// Publishes one geometry_msgs/Twist sample on [topicName] (creating
  /// its writer lazily on first use). See handyros.h.
  void publishTwist(
    String topicName, {
    required double lx,
    required double ly,
    required double lz,
    required double ax,
    required double ay,
    required double az,
  }) {
    final namePtr = topicName.toNativeUtf8();
    try {
      _publishTwist(namePtr, lx, ly, lz, ax, ay, az);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Publishes one sensor_msgs/Imu sample on [topicName]. [qx..qw]
  /// default to the identity quaternion if the caller has no fused
  /// orientation estimate to report.
  void publishImu(
    String topicName, {
    String frameId = '',
    required double ax,
    required double ay,
    required double az,
    required double gx,
    required double gy,
    required double gz,
    double qx = 0,
    double qy = 0,
    double qz = 0,
    double qw = 1,
  }) {
    final namePtr = topicName.toNativeUtf8();
    final framePtr = frameId.toNativeUtf8();
    try {
      _publishImu(namePtr, framePtr, ax, ay, az, gx, gy, gz, qx, qy, qz, qw);
    } finally {
      calloc.free(namePtr);
      calloc.free(framePtr);
    }
  }

  /// Publishes one sensor_msgs/NavSatFix sample on [topicName].
  void publishNavSatFix(
    String topicName, {
    String frameId = '',
    required double latitude,
    required double longitude,
    required double altitude,
  }) {
    final namePtr = topicName.toNativeUtf8();
    final framePtr = frameId.toNativeUtf8();
    try {
      _publishNavSatFix(namePtr, framePtr, latitude, longitude, altitude);
    } finally {
      calloc.free(namePtr);
      calloc.free(framePtr);
    }
  }

  /// Publishes one sensor_msgs/MagneticField sample on [topicName].
  void publishMagneticField(
    String topicName, {
    String frameId = '',
    required double x,
    required double y,
    required double z,
  }) {
    final namePtr = topicName.toNativeUtf8();
    final framePtr = frameId.toNativeUtf8();
    try {
      _publishMagneticField(namePtr, framePtr, x, y, z);
    } finally {
      calloc.free(namePtr);
      calloc.free(framePtr);
    }
  }

  /// Publishes one sensor_msgs/Image sample on [topicName]. [data]
  /// must already match [encoding]/[step] (e.g. tightly packed rgb8).
  void publishImage(
    String topicName, {
    String frameId = '',
    required int width,
    required int height,
    required String encoding,
    bool isBigEndian = false,
    required int step,
    required Uint8List data,
  }) {
    final namePtr = topicName.toNativeUtf8();
    final framePtr = frameId.toNativeUtf8();
    final encodingPtr = encoding.toNativeUtf8();
    final dataPtr = calloc<Uint8>(data.length);
    try {
      dataPtr.asTypedList(data.length).setAll(0, data);
      _publishImage(
        namePtr,
        framePtr,
        width,
        height,
        encodingPtr,
        isBigEndian,
        step,
        dataPtr,
        data.length,
      );
    } finally {
      calloc.free(namePtr);
      calloc.free(framePtr);
      calloc.free(encodingPtr);
      calloc.free(dataPtr);
    }
  }

  /// Deletes the writer for [topicName] (whichever publish* kind
  /// created it). Call when a Sensors card or Teleop's publish toggle
  /// turns off.
  void stopPublishing(String topicName) =>
      _withNativeString(topicName, _publishStop);

  void _withNativeString(String value, void Function(Pointer<Utf8>) call) {
    final ptr = value.toNativeUtf8();
    try {
      call(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
}
