import 'dart:math';

import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../core/viewer_plugin.dart';
import '../models/topic.dart';
import '../services/dds_topic_service.dart';
import '../viewers/canvas_painters.dart';
import '../viewers/imu_readout.dart';
import '../viewers/live_payload_controller.dart';
import '../viewers/odom_readout.dart';
import '../viewers/raw_echo_view.dart';
import '../viewers/terminal_view.dart';
import '../viewers/tf_tree_view.dart';
import '../viewers/viewer_hud.dart';

class ViewerScreen extends StatefulWidget {
  final Topic topic;
  final ViewerPlugin plugin;
  final DdsTopicService? dds;

  const ViewerScreen({
    super.key,
    required this.topic,
    required this.plugin,
    this.dds,
  });

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen>
    with SingleTickerProviderStateMixin {
  late final LivePayloadController _controller = LivePayloadController(
    dds: widget.dds,
    topic: widget.topic,
    vsync: this,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plugin = widget.plugin;
    final topic = widget.topic;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: AppColors.card,
                      boxShadow: raisedShadowSm,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.of(context).maybePop(),
                        child: Icon(
                          Icons.arrow_back,
                          size: 22,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plugin.label,
                          style: AppText.disp(
                            size: 17,
                            weight: FontWeight.w600,
                            letterSpacing: -.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          topic.name,
                          style: AppText.mono(
                            size: 11,
                            weight: FontWeight.w500,
                            color: AppColors.ink3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _body(plugin.key)),
          ],
        ),
      ),
    );
  }

  Widget _body(String key) {
    final c = _controller;
    switch (key) {
      case 'image':
        return CanvasViewerFrame(
          painter: ImageScenePainter(c),
          hud: [
            HudChip(
              'RES',
              () => c.isLive
                  ? (c.image == null
                        ? '—'
                        : '${c.image!.width}×${c.image!.height}')
                  : '1920×1080',
              AppColors.ink,
            ),
            HudChip(
              'FPS',
              () => c.isLive
                  ? (c.liveTopic?.hzAvg ?? '—')
                  : c.sim!.imgFps.toStringAsFixed(1),
              AppColors.ok,
            ),
            HudChip(
              'LAT',
              () => c.isLive ? (c.liveTopic?.latency ?? '—') : '12 ms',
              AppColors.amber,
            ),
          ],
          tools: const [
            ViewerTool(Icons.fullscreen, 'fullscreen'),
            ViewerTool(Icons.zoom_in, 'zoom'),
            ViewerTool(Icons.photo_camera, 'shot'),
            ViewerTool(Icons.grid_on, 'grid'),
          ],
        );
      case 'imu':
        return Column(
          children: [
            Expanded(
              child: CanvasViewerFrame(
                painter: ImuOrientationPainter(c),
                hud: [
                  HudChip(
                    'RATE',
                    () => c.isLive ? (c.liveTopic?.hzAvg ?? '—') : '100 Hz',
                    AppColors.sec,
                  ),
                  HudChip(
                    'FRAME',
                    () => c.isLive ? (c.imu?.frameId ?? '—') : 'imu_link',
                    AppColors.ink,
                  ),
                ],
              ),
            ),
            ImuReadoutGrid(controller: c),
          ],
        );
      case 'laser':
        return CanvasViewerFrame(
          painter: LaserScanPainter(c),
          hud: [
            HudChip(
              'CLOSEST',
              () => c.isLive
                  ? _closestRange(c)
                  : '${c.sim!.laserMin.toStringAsFixed(2)} m',
              AppColors.red,
            ),
            HudChip(
              'RANGE',
              () => c.isLive
                  ? (c.laserScan == null
                        ? '—'
                        : '${c.laserScan!.rangeMin.toStringAsFixed(1)}–${c.laserScan!.rangeMax.toStringAsFixed(1)} m')
                  : '0.1–4 m',
              AppColors.ink,
            ),
            HudChip(
              'PTS',
              () => c.isLive ? '${c.laserScan?.ranges.length ?? 0}' : '180',
              AppColors.lime,
            ),
          ],
          tools: const [
            ViewerTool(Icons.zoom_in, 'zoom'),
            ViewerTool(Icons.open_with, 'pan'),
            ViewerTool(Icons.center_focus_strong, 'center'),
          ],
        );
      case 'cloud':
        return CanvasViewerFrame(
          painter: PointCloudPainter(c),
          hud: [
            HudChip(
              'PTS',
              () => c.isLive ? '${c.pointCloud?.pointCount ?? 0}' : '986',
              AppColors.pink,
            ),
            HudChip(
              'MODE',
              () => c.isLive
                  ? (c.pointCloud?.colorMode == 'rgb' ? 'RGB' : 'HEIGHT')
                  : 'HEIGHT',
              AppColors.ink,
            ),
            HudChip(
              'FPS',
              () => c.isLive ? (c.liveTopic?.hzAvg ?? '—') : '15',
              AppColors.ok,
            ),
          ],
          tools: const [
            ViewerTool(Icons.threed_rotation, 'rotate'),
            ViewerTool(Icons.palette, 'rgb'),
            ViewerTool(Icons.gradient, 'intensity'),
            ViewerTool(Icons.invert_colors, 'bg'),
          ],
          onSceneScaleStart: (_) => c.startCloudZoomGesture(),
          onSceneScaleUpdate: (details) {
            c.rotateCloud(
              details.focalPointDelta.dx * 0.01,
              -details.focalPointDelta.dy * 0.01,
            );
            c.updateCloudZoom(details.scale);
          },
        );
      case 'odom':
        return Column(
          children: [
            Expanded(
              child: CanvasViewerFrame(
                painter: OdomTrailPainter(c),
                hud: [
                  HudChip(
                    'DIST',
                    () => c.isLive
                        ? '${_trailDistance(c).toStringAsFixed(1)} m'
                        : '${(c.sim!.trail.length * 0.01).toStringAsFixed(1)} m',
                    AppColors.amber,
                  ),
                  HudChip(
                    'FRAME',
                    () => c.isLive ? (c.odom?.frameId ?? '—') : 'odom',
                    AppColors.ink,
                  ),
                ],
                tools: const [
                  ViewerTool(Icons.zoom_in, 'zoom'),
                  ViewerTool(Icons.open_with, 'pan'),
                  ViewerTool(Icons.delete_sweep, 'clear'),
                ],
              ),
            ),
            OdomReadoutGrid(controller: c),
          ],
        );
      case 'graph':
        return CanvasViewerFrame(
          painter: GraphPainter(c),
          hud: [
            HudChip(
              'VALUE',
              () => c.isLive
                  ? (c.lastFloat?.value.toStringAsFixed(2) ?? '—')
                  : c.sim!.graphVal.toStringAsFixed(1),
              AppColors.pri,
            ),
            HudChip(
              'MIN',
              () => c.isLive ? _historyMin(c) : '12.0',
              AppColors.blue,
            ),
            HudChip(
              'MAX',
              () => c.isLive ? _historyMax(c) : '88.4',
              AppColors.pink,
            ),
          ],
        );
      case 'tf':
        return TfTreeView(controller: c);
      case 'terminal':
        return TerminalView(controller: c);
      case 'raw':
      default:
        return RawEchoView(controller: c);
    }
  }

  static String _closestRange(LivePayloadController c) {
    final scan = c.laserScan;
    if (scan == null) return '—';
    double? minR;
    for (final r in scan.ranges) {
      if (r.isFinite && r >= scan.rangeMin && r <= scan.rangeMax) {
        if (minR == null || r < minR) minR = r;
      }
    }
    return minR == null ? '—' : '${minR.toStringAsFixed(2)} m';
  }

  static double _trailDistance(LivePayloadController c) {
    final trail = c.odomTrail;
    double d = 0;
    for (var i = 1; i < trail.length; i++) {
      final dx = trail[i].x - trail[i - 1].x, dy = trail[i].y - trail[i - 1].y;
      d += sqrt(dx * dx + dy * dy);
    }
    return d;
  }

  static String _historyMin(LivePayloadController c) {
    if (c.floatHistory.isEmpty) return '—';
    return c.floatHistory.reduce((a, b) => a < b ? a : b).toStringAsFixed(2);
  }

  static String _historyMax(LivePayloadController c) {
    if (c.floatHistory.isEmpty) return '—';
    return c.floatHistory.reduce((a, b) => a > b ? a : b).toStringAsFixed(2);
  }
}
