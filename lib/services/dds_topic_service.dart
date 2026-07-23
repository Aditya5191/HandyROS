import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../core/viewer_plugin.dart';
import '../models/live_payload.dart';
import '../models/topic.dart';
import '../native/handyros_bindings.dart';

/// Live topic list backed by real DDS discovery (handyros_core), polled
/// on an interval since Cyclone DDS delivers discovery events async.
///
/// Discovery reports topic name, type, QoS, and publisher/subscriber
/// process+host identity (all read from DDS builtin-topic metadata —
/// "process name" stands in for the real ROS 2 node name, which lives
/// in a topic payload we don't decode). Message rate/size/bandwidth/
/// latency are real for any type handyros_core has generated typed
/// bindings for (effectively every standard ROS 2 message type — see
/// CMakeLists.txt); custom project-specific types show "—" until their
/// definition is imported. These stats are opt-in per topic via
/// [watchTopic]/[unwatchTopic] rather than automatic for everything
/// discovered — some topics are camera/point-cloud streams at tens of
/// MB/s, and receiving all of them just to report a number nobody's
/// looking at is real bandwidth/memory/battery cost on a phone.
///
/// Real decoded message *field values* (not just stats) are available
/// for a smaller, fixed set of types with a dedicated Viewer screen —
/// see [watchPayload]/[unwatchPayload]/[latestPayload].
class DdsTopicService extends ChangeNotifier {
  final HandyrosBindings _bindings;
  Timer? _timer;

  List<Topic> topics = [];

  // A topic's *stats* can be wanted by two independent callers at
  // once — the topic-list card (expand/collapse) and an open Viewer
  // screen (which doesn't require its card to be expanded first, and
  // may still be open after the card collapses/scrolls off). Without
  // refcounting, whichever caller unwatches first would kill stats
  // out from under the other.
  final Map<String, int> _watchRefCounts = {};

  DdsTopicService._(this._bindings);

  /// Returns null if handyros_core isn't available on this platform —
  /// callers should fall back to [FakeTopicService] in that case. Also
  /// null under `flutter test`, so widget tests don't depend on real
  /// network/DDS state.
  static DdsTopicService? tryCreate() {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return null;
    }
    try {
      return DdsTopicService._(HandyrosBindings.open());
    } catch (_) {
      return null;
    }
  }

  bool start({
    int domainId = 0,
    Duration interval = const Duration(milliseconds: 500),
    List<String> peers = const [],
  }) {
    if (!_bindings.initialize(domainId, peers: peers)) {
      return false;
    }
    _tick();
    _timer = Timer.periodic(interval, (_) => _tick());
    return true;
  }

  void _tick() {
    _bindings.poll();
    topics = _parse(_bindings.topicsJson());
    notifyListeners();
  }

  /// Forces an immediate poll+parse instead of waiting for the next
  /// periodic tick — used by the Topics tab's manual refresh button
  /// and when the tab becomes active again after switching away.
  void refresh() => _tick();

  /// Call when a topic's detail view opens/closes. Refcounted — see
  /// [_watchRefCounts] — so it's safe to call from multiple places
  /// (a card and a Viewer screen) watching the same topic at once.
  void watchTopic(String topicName) {
    final count = (_watchRefCounts[topicName] ?? 0) + 1;
    _watchRefCounts[topicName] = count;
    if (count == 1) {
      _bindings.watchTopic(topicName);
    }
  }

  void unwatchTopic(String topicName) {
    final count = (_watchRefCounts[topicName] ?? 0) - 1;
    if (count <= 0) {
      _watchRefCounts.remove(topicName);
      _bindings.unwatchTopic(topicName);
    } else {
      _watchRefCounts[topicName] = count;
    }
  }

  /// Starts/stops decoding real message field values for one topic —
  /// only meaningful for the fixed set of types with a dedicated
  /// Viewer screen. Call when a Viewer screen opens/closes; only ever
  /// one Viewer screen is open at a time so this doesn't need the
  /// refcounting [watchTopic] does.
  void watchPayload(String topicName) => _bindings.watchPayload(topicName);
  void unwatchPayload(String topicName) => _bindings.unwatchPayload(topicName);

  /// Writer side, used by the Sensors/Teleop tabs — the app's own
  /// only writers on the DDS graph. Each publishXxx call is
  /// self-contained: the native side lazily creates a writer for
  /// [topicName] on first use and reuses it after that, so a given
  /// name should only ever be used with one of these kinds at once.
  void publishTwist(
    String topicName, {
    required double lx,
    required double ly,
    required double lz,
    required double ax,
    required double ay,
    required double az,
  }) => _bindings.publishTwist(
    topicName,
    lx: lx,
    ly: ly,
    lz: lz,
    ax: ax,
    ay: ay,
    az: az,
  );

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
  }) => _bindings.publishImu(
    topicName,
    frameId: frameId,
    ax: ax,
    ay: ay,
    az: az,
    gx: gx,
    gy: gy,
    gz: gz,
    qx: qx,
    qy: qy,
    qz: qz,
    qw: qw,
  );

  void publishNavSatFix(
    String topicName, {
    String frameId = '',
    required double latitude,
    required double longitude,
    required double altitude,
  }) => _bindings.publishNavSatFix(
    topicName,
    frameId: frameId,
    latitude: latitude,
    longitude: longitude,
    altitude: altitude,
  );

  void publishMagneticField(
    String topicName, {
    String frameId = '',
    required double x,
    required double y,
    required double z,
  }) => _bindings.publishMagneticField(
    topicName,
    frameId: frameId,
    x: x,
    y: y,
    z: z,
  );

  void publishImage(
    String topicName, {
    String frameId = '',
    required int width,
    required int height,
    required String encoding,
    bool isBigEndian = false,
    required int step,
    required Uint8List data,
  }) => _bindings.publishImage(
    topicName,
    frameId: frameId,
    width: width,
    height: height,
    encoding: encoding,
    isBigEndian: isBigEndian,
    step: step,
    data: data,
  );

  /// Call when a Sensors card or Teleop's publish toggle turns off.
  void stopPublishing(String topicName) => _bindings.stopPublishing(topicName);

  /// Parses the latest decoded payload for [topicName] into its typed
  /// model (ImuSample, ImageSample, LaserScanSample, PointCloudSample,
  /// OdomSample, a list of TfTransformSample, LogSample, or FloatSample —
  /// callers already know which, from the topic's ViewerPlugin key).
  /// Null if the type isn't decodable or no sample has arrived yet.
  Object? latestPayload(String topicName) {
    final json =
        jsonDecode(_bindings.topicPayloadJson(topicName))
            as Map<String, dynamic>;
    if (json['available'] != true) return null;
    switch (json['kind'] as String?) {
      case 'imu':
        return ImuSample.fromJson(json);
      case 'image':
        return ImageSample.fromJson(
          json,
          _bindings.topicPayloadBlob(topicName),
        );
      case 'laserScan':
        return LaserScanSample.fromJson(json);
      case 'pointCloud':
        return PointCloudSample.fromJson(
          json,
          _bindings.topicPayloadBlob(topicName),
        );
      case 'odometry':
        return OdomSample.fromJson(json);
      case 'tf':
        return parseTfTransforms(json);
      case 'string':
      case 'log':
        return LogSample.fromJson(json);
      case 'float':
        return FloatSample.fromJson(json);
      default:
        return null;
    }
  }

  List<Topic> _parse(String json) {
    final entries = jsonDecode(json) as List<dynamic>;
    var id = 0;
    return entries.map((raw) {
      final entry = raw as Map<String, dynamic>;
      final type = entry['type'] as String;
      final style = _styleFor(type);
      final publishers = _nodes(entry['publishers']);
      final subscribers = _nodes(entry['subscribers']);
      final statsAvailable = entry['statsAvailable'] as bool;
      final rateHz = (entry['rateHz'] as num).toDouble();

      return Topic(
        id: id++,
        name: entry['name'] as String,
        type: type,
        category: style.category,
        icon: style.icon,
        color: style.color,
        hz: statsAvailable ? rateHz : 0,
        hzAvg: statsAvailable ? _formatHz(rateHz) : '—',
        bandwidth: statsAvailable
            ? _formatBytesPerSec(
                (entry['bandwidthBytesPerSec'] as num).toDouble(),
              )
            : '—',
        messageSize: statsAvailable
            ? _formatBytes((entry['avgMsgSizeBytes'] as num).toDouble())
            : '—',
        latency: statsAvailable
            ? _formatLatency((entry['latencyMs'] as num).toDouble())
            : '—',
        qos: QosProfile(
          reliability: entry['reliability'] as String,
          history: entry['history'] as String,
          durability: entry['durability'] as String,
          depth: entry['depth'] as int,
        ),
        publishers: publishers,
        subscribers: subscribers,
        publisherCount: publishers.length,
        subscriberCount: subscribers.length,
      );
    }).toList();
  }

  List<NodeRef> _nodes(Object? raw) {
    final list = raw as List<dynamic>;
    return list.map((e) {
      final node = e as Map<String, dynamic>;
      return NodeRef(node['process'] as String, node['host'] as String);
    }).toList();
  }

  String _formatHz(double hz) => '${hz.toStringAsFixed(hz >= 100 ? 0 : 1)} Hz';

  String _formatBytes(double bytes) {
    if (bytes >= 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${bytes.toStringAsFixed(0)} B';
  }

  String _formatBytesPerSec(double bytesPerSec) {
    if (bytesPerSec >= 1024 * 1024)
      return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    if (bytesPerSec >= 1024)
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${bytesPerSec.toStringAsFixed(0)} B/s';
  }

  String _formatLatency(double ms) {
    if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(2)} s';
    return '${ms.toStringAsFixed(1)} ms';
  }

  ({String category, IconData icon, Color color}) _styleFor(String type) {
    final plugin = ViewerRegistry.viewerFor(type);
    if (plugin == null) {
      return (
        category: 'custom',
        icon: Icons.help_outline,
        color: AppColors.custom,
      );
    }
    if (plugin.key != 'raw') {
      return (category: plugin.key, icon: plugin.icon, color: plugin.color);
    }
    return (
      category: 'other',
      icon: Icons.data_object,
      color: AppColors.custom,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bindings.shutdown();
    super.dispose();
  }
}
