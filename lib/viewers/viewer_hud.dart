import 'dart:ui';

import 'package:flutter/material.dart';
import '../app/theme.dart';

class HudChip {
  final String label;
  final String Function() value;
  final Color color;

  const HudChip(this.label, this.value, this.color);
}

class ViewerTool {
  final IconData icon;
  final String id;

  const ViewerTool(this.icon, this.id);
}

/// Wraps a canvas viewer with the HUD chip overlay (top-left) and the
/// floating toolbar (bottom-center), matching the design's viewer frame.
class CanvasViewerFrame extends StatefulWidget {
  final CustomPainter painter;
  final List<HudChip> hud;
  final List<ViewerTool> tools;
  final ValueChanged<String>? onTool;

  /// Combined drag+pinch gesture, for viewers that support rotating/
  /// zooming the scene (currently just the point cloud viewer). Uses
  /// Flutter's scale gesture family (not a separate pan detector)
  /// since that's the standard way to support both in one gesture
  /// without the two recognizers fighting each other.
  final GestureScaleStartCallback? onSceneScaleStart;
  final GestureScaleUpdateCallback? onSceneScaleUpdate;

  const CanvasViewerFrame({
    super.key,
    required this.painter,
    this.hud = const [],
    this.tools = const [],
    this.onTool,
    this.onSceneScaleStart,
    this.onSceneScaleUpdate,
  });

  @override
  State<CanvasViewerFrame> createState() => _CanvasViewerFrameState();
}

class _CanvasViewerFrameState extends State<CanvasViewerFrame> {
  final Set<String> _active = {};

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: canvasBackground,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.shadowDark.withValues(alpha: .12)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: widget.onSceneScaleStart,
              onScaleUpdate: widget.onSceneScaleUpdate,
              child: AnimatedBuilder(
                animation: widget.painter,
                builder: (context, _) =>
                    CustomPaint(painter: widget.painter, size: Size.infinite),
              ),
            ),
          ),
          if (widget.hud.isNotEmpty)
            Positioned(
              top: 14,
              left: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final h in widget.hud)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: _GlassPill(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              h.label,
                              style: AppText.disp(
                                size: 9,
                                weight: FontWeight.w600,
                                color: AppColors.ink3,
                                letterSpacing: .5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            AnimatedBuilder(
                              animation: widget.painter,
                              builder: (context, _) => Text(
                                h.value(),
                                style: AppText.mono(
                                  size: 12,
                                  weight: FontWeight.w600,
                                  color: h.color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (widget.tools.isNotEmpty)
            Positioned(
              bottom: 14,
              left: 0,
              right: 0,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xB8F7F5F1),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.shadowDark.withValues(alpha: .12),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final tool in widget.tools)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (_active.contains(tool.id)) {
                                      _active.remove(tool.id);
                                    } else {
                                      _active.add(tool.id);
                                    }
                                  });
                                  widget.onTool?.call(tool.id);
                                },
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: _active.contains(tool.id)
                                        ? AppColors.acc
                                        : Colors.white.withValues(alpha: .5),
                                  ),
                                  child: Icon(
                                    tool.icon,
                                    size: 20,
                                    color: _active.contains(tool.id)
                                        ? Colors.white
                                        : AppColors.ink2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  final Widget child;
  const _GlassPill({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xB8F7F5F1),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowDark.withValues(alpha: .08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
