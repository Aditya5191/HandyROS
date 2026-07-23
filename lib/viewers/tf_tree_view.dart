import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../models/tf_frame.dart';
import '../services/fake_tf_service.dart';
import 'live_payload_controller.dart';

/// Builds a displayable tree from the flat child->parent edges
/// accumulated by LivePayloadController (tf2_msgs/TFMessage only ever
/// carries a subset of transforms per message, so the full tree is a
/// running union, not something any single message contains).
List<TfFrame> _buildLiveFrames(Map<String, TfFrameState> frames) {
  final childNames = frames.keys.toSet();
  final parentToChildren = <String, List<String>>{};
  for (final entry in frames.entries) {
    parentToChildren.putIfAbsent(entry.value.parent, () => []).add(entry.key);
  }
  final roots =
      parentToChildren.keys.where((p) => !childNames.contains(p)).toList()
        ..sort();

  final result = <TfFrame>[];
  final visited = <String>{};

  void visit(String name, int depth) {
    if (visited.contains(name)) return;
    visited.add(name);
    final state = frames[name];
    final childList = List<String>.from(parentToChildren[name] ?? const [])
      ..sort();
    result.add(
      TfFrame(
        name: name,
        depth: depth,
        parent: state?.parent ?? '—',
        children: childList.isEmpty ? '—' : childList.join(', '),
        translation: state == null
            ? '—'
            : '${state.translation.x.toStringAsFixed(2)}, ${state.translation.y.toStringAsFixed(2)}, ${state.translation.z.toStringAsFixed(2)}',
        rotation: state == null
            ? '—'
            : '${state.rotation.x.toStringAsFixed(2)}, ${state.rotation.y.toStringAsFixed(2)}, '
                  '${state.rotation.z.toStringAsFixed(2)}, ${state.rotation.w.toStringAsFixed(2)}',
        rate: state == null ? '—' : '${state.rateHz.toStringAsFixed(0)} Hz',
      ),
    );
    for (final c in childList) {
      visit(c, depth + 1);
    }
  }

  for (final r in roots) {
    visit(r, 0);
  }
  for (final name in childNames) {
    if (!visited.contains(name)) {
      visit(name, 0);
    }
  }

  return result;
}

class TfTreeView extends StatefulWidget {
  final LivePayloadController controller;

  const TfTreeView({super.key, required this.controller});

  @override
  State<TfTreeView> createState() => _TfTreeViewState();
}

class _TfTreeViewState extends State<TfTreeView> {
  String? _selected;
  final List<TfFrame> _demoFrames = FakeTfService.getFrames();

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.isLive) {
      return _buildTree(
        _demoFrames,
        _selected ?? _demoFrames.first.name,
        (name) => setState(() => _selected = name),
      );
    }

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final frames = _buildLiveFrames(widget.controller.tfFrames);
        if (frames.isEmpty) {
          return Center(
            child: Text(
              'waiting for first /tf message…',
              style: AppText.mono(size: 12, color: AppColors.ink3),
            ),
          );
        }
        final selected = frames.any((f) => f.name == _selected)
            ? _selected!
            : frames.first.name;
        return _buildTree(
          frames,
          selected,
          (name) => setState(() => _selected = name),
        );
      },
    );
  }

  Widget _buildTree(
    List<TfFrame> frames,
    String selected,
    void Function(String) onSelect,
  ) {
    final detail = frames.firstWhere(
      (f) => f.name == selected,
      orElse: () => frames.first,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: panelDecoration(radius: 20),
            child: Column(
              children: [
                for (final f in frames)
                  GestureDetector(
                    onTap: () => onSelect(f.name),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      margin: EdgeInsets.only(left: f.depth * 20.0, bottom: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: selected == f.name ? AppColors.accTint : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected == f.name
                                  ? AppColors.acc
                                  : AppColors.ink3,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            f.name,
                            style: AppText.mono(
                              size: 13,
                              weight: FontWeight.w500,
                              color: selected == f.name
                                  ? AppColors.acc2
                                  : AppColors.ink,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            f.rate,
                            style: AppText.mono(
                              size: 9.5,
                              weight: FontWeight.w500,
                              color: AppColors.ink3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(17),
            decoration: panelDecoration(radius: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.name,
                  style: AppText.disp(
                    size: 14,
                    weight: FontWeight.w600,
                    color: AppColors.acc2,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _kv('PARENT', detail.parent)),
                    const SizedBox(width: 11),
                    Expanded(child: _kv('CHILDREN', detail.children)),
                  ],
                ),
                const SizedBox(height: 11),
                _kv('TRANSLATION (m)', detail.translation),
                const SizedBox(height: 11),
                _kv('ROTATION (quat)', detail.rotation),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: recessedDecoration(radius: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.disp(
              size: 9,
              weight: FontWeight.w600,
              color: AppColors.ink3,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 6),
          Text(value, style: AppText.mono(size: 12, weight: FontWeight.w500)),
        ],
      ),
    );
  }
}
