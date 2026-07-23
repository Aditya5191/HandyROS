import 'package:flutter/material.dart';
import '../app/theme.dart';

/// Describes a registered viewer plugin: which message types it can
/// visualize, and how it should be presented (icon/color/label).
///
/// This mirrors the `registry` in the HandyROS.dc.html design mockup.
/// Drives which screen opens when a user taps "Visualize" on a topic;
/// see LivePayloadController for which of these types actually get
/// real decoded field values vs. topic-metadata-only ('raw' fallback).
class ViewerPlugin {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  final bool builtIn;
  final List<String> types;
  final IconData visualizeIcon;
  final String visualizeLabel;

  const ViewerPlugin({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.builtIn,
    required this.types,
    required this.visualizeIcon,
    required this.visualizeLabel,
  });
}

abstract class ViewerRegistry {
  static final List<ViewerPlugin> plugins = [
    ViewerPlugin(
      key: 'image',
      label: 'Image Viewer',
      icon: Icons.photo_camera,
      color: AppColors.pri,
      builtIn: true,
      types: ['sensor_msgs/msg/Image', 'sensor_msgs/msg/CompressedImage'],
      visualizeIcon: Icons.visibility,
      visualizeLabel: 'Open Image Viewer',
    ),
    ViewerPlugin(
      key: 'imu',
      label: 'IMU Viewer',
      icon: Icons.threed_rotation,
      color: AppColors.sec,
      builtIn: true,
      types: ['sensor_msgs/msg/Imu'],
      visualizeIcon: Icons.explore,
      visualizeLabel: 'Open IMU Viewer',
    ),
    ViewerPlugin(
      key: 'laser',
      label: 'Laser Viewer',
      icon: Icons.radar,
      color: AppColors.lime,
      builtIn: true,
      types: ['sensor_msgs/msg/LaserScan'],
      visualizeIcon: Icons.radar,
      visualizeLabel: 'Open Laser Viewer',
    ),
    ViewerPlugin(
      key: 'cloud',
      label: 'Point Cloud Viewer',
      icon: Icons.scatter_plot,
      color: AppColors.pink,
      builtIn: true,
      types: ['sensor_msgs/msg/PointCloud2'],
      visualizeIcon: Icons.view_in_ar,
      visualizeLabel: 'Open 3D Viewer',
    ),
    ViewerPlugin(
      key: 'odom',
      label: 'Odometry Viewer',
      icon: Icons.my_location,
      color: AppColors.amber,
      builtIn: true,
      types: ['nav_msgs/msg/Odometry'],
      visualizeIcon: Icons.route,
      visualizeLabel: 'Open Odometry Viewer',
    ),
    ViewerPlugin(
      key: 'tf',
      label: 'TF Viewer',
      icon: Icons.account_tree,
      color: AppColors.blue,
      builtIn: true,
      types: ['tf2_msgs/msg/TFMessage'],
      visualizeIcon: Icons.account_tree,
      visualizeLabel: 'Open TF Tree',
    ),
    ViewerPlugin(
      key: 'terminal',
      label: 'Terminal Viewer',
      icon: Icons.terminal,
      color: AppColors.ok,
      builtIn: true,
      types: ['std_msgs/msg/String', 'rcl_interfaces/msg/Log'],
      visualizeIcon: Icons.terminal,
      visualizeLabel: 'Open Terminal',
    ),
    ViewerPlugin(
      key: 'graph',
      label: 'Graph Viewer',
      icon: Icons.show_chart,
      color: AppColors.pri,
      builtIn: true,
      types: [
        'std_msgs/msg/Float32',
        'std_msgs/msg/Float64',
        'sensor_msgs/msg/BatteryState',
      ],
      visualizeIcon: Icons.show_chart,
      visualizeLabel: 'Open Live Graph',
    ),
    ViewerPlugin(
      key: 'raw',
      label: 'Raw Echo',
      icon: Icons.data_object,
      color: AppColors.custom,
      builtIn: false,
      types: ['* any decodable message'],
      visualizeIcon: Icons.data_object,
      visualizeLabel: 'Echo Raw Message',
    ),
  ];

  /// Interface packages bundled with a standard ROS 2 install — types
  /// from any other package are project-specific custom definitions we
  /// have no way to interpret without one being imported.
  static const _knownPackages = {
    'std_msgs',
    'std_srvs',
    'sensor_msgs',
    'geometry_msgs',
    'nav_msgs',
    'tf2_msgs',
    'rcl_interfaces',
    'rosgraph_msgs',
    'diagnostic_msgs',
    'action_msgs',
    'actionlib_msgs',
    'builtin_interfaces',
    'shape_msgs',
    'trajectory_msgs',
    'visualization_msgs',
    'vision_msgs',
    'lifecycle_msgs',
    'statistics_msgs',
    'rmw_dds_common',
    'composition_interfaces',
  };

  /// Returns the plugin that should visualize [type], the raw-echo
  /// fallback if none match but the type is from a package we
  /// recognize, or null if it's a project-specific custom type we
  /// can't interpret at all (routes to the Unknown Type screen).
  static ViewerPlugin? viewerFor(String type) {
    for (final p in plugins) {
      if (p.key == 'raw') continue;
      if (p.types.contains(type)) return p;
    }
    final package = type.split('/').first;
    if (!_knownPackages.contains(package)) {
      return null;
    }
    return plugins.firstWhere((p) => p.key == 'raw');
  }
}
