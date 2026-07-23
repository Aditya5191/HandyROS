import 'package:flutter/material.dart';

/// A single publisher/subscriber node reference on a topic.
class NodeRef {
  final String node;
  final String host;

  const NodeRef(this.node, this.host);
}

/// QoS profile summary shown as chips in the expanded topic card.
class QosProfile {
  final String reliability;
  final String history;
  final String durability;
  final int depth;

  const QosProfile({
    required this.reliability,
    required this.history,
    required this.durability,
    required this.depth,
  });
}

/// A discovered ROS 2 topic and its live stats.
///
/// `category` drives both the icon/color treatment and which home-screen
/// filter chip a topic falls under (see FilterChipBar): image, laser,
/// cloud, tf, nav, diag, custom.
class Topic {
  final int id;
  final String name;
  final String type;
  final String category;
  final IconData icon;
  final Color color;

  final double hz;
  final String hzAvg;
  final String bandwidth;
  final String messageSize;
  final String latency;

  final QosProfile qos;

  /// Publisher/subscriber identity, when known. Live DDS discovery
  /// currently only reports counts (see [DdsTopicService]), so these
  /// may be empty even when [publisherCount]/[subscriberCount] are not.
  final List<NodeRef> publishers;
  final List<NodeRef> subscribers;
  final int publisherCount;
  final int subscriberCount;

  const Topic({
    required this.id,
    required this.name,
    required this.type,
    required this.category,
    required this.icon,
    required this.color,
    required this.hz,
    required this.hzAvg,
    required this.bandwidth,
    required this.messageSize,
    required this.latency,
    required this.qos,
    required this.publisherCount,
    required this.subscriberCount,
    this.publishers = const [],
    this.subscribers = const [],
  });

  /// Convenience constructor for mock data where the full publisher/
  /// subscriber node list is known upfront: counts are derived from it.
  Topic.withNodes({
    required this.id,
    required this.name,
    required this.type,
    required this.category,
    required this.icon,
    required this.color,
    required this.hz,
    required this.hzAvg,
    required this.bandwidth,
    required this.messageSize,
    required this.latency,
    required this.qos,
    required this.publishers,
    required this.subscribers,
  }) : publisherCount = publishers.length,
       subscriberCount = subscribers.length;
}
