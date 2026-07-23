import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/theme.dart';
import '../core/viewer_plugin.dart';
import '../models/topic.dart';
import '../services/app_settings.dart';
import '../services/dds_topic_service.dart';
import '../services/fake_topic_service.dart';
import '../widgets/filter_chip_bar.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/topic_card.dart';
import 'unknown_type_screen.dart';
import 'viewer_screen.dart';

/// The Topics tab — no longer its own Scaffold/AppBar since it now
/// lives inside AppShell's bottom-nav tab stack. [dds] is owned/started
/// by AppShell (shared with the Sensors/Teleop tabs), not by this
/// screen — null on a platform with no native DDS layer. [active]
/// mirrors this tab being the one currently selected — used to force
/// a fresh poll the moment the user switches back to it, on top of
/// the DdsTopicService's own continuous background polling.
class HomeScreen extends StatefulWidget {
  final AppSettings settings;
  final DdsTopicService? dds;
  final bool active;

  const HomeScreen({
    super.key,
    required this.settings,
    required this.dds,
    required this.active,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DdsTopicService? _dds;
  List<Topic> _topics = [];
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _filter = 'all';

  final GlobalKey _headerKey = GlobalKey();
  double _headerHeight = 190;

  @override
  void initState() {
    super.initState();
    _dds = widget.dds;
    if (_dds != null) {
      _topics = _dds!.topics;
      _dds!.addListener(_onDdsUpdate);
    } else {
      // No native DDS layer on this platform (or init failed) — fall
      // back to mock data so the UI is still browsable.
      _topics = FakeTopicService.getTopics();
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      _dds?.refresh();
    }
  }

  // Re-measured after every build (not just once) — the very first
  // post-layout frame on Android can briefly report a bogus near-zero
  // window size before the platform hands Flutter real MediaQuery
  // metrics, which made a one-shot measurement in initState lock in a
  // garbage height forever. Re-checking each build self-corrects once
  // real metrics arrive, and is a no-op (no further setState) once the
  // value has settled.
  void _measureHeader() {
    final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final h = box.size.height;
    if (h > 0 && (h - _headerHeight).abs() > .5 && mounted) {
      setState(() => _headerHeight = h);
    }
  }

  void _onDdsUpdate() => setState(() => _topics = _dds!.topics);

  @override
  void dispose() {
    _dds?.removeListener(_onDdsUpdate);
    _searchController.dispose();
    super.dispose();
  }

  List<Topic> get _filtered {
    final q = _query.trim().toLowerCase();
    return _topics.where((t) {
      final matchesFilter = switch (_filter) {
        'all' => true,
        'active' => t.hz > 0,
        _ => t.category == _filter,
      };
      if (!matchesFilter) return false;
      if (q.isEmpty) return true;
      final haystack =
          ('${t.name} ${t.type} '
                  '${t.publishers.map((p) => p.node).join(' ')} '
                  '${t.subscribers.map((s) => s.node).join(' ')}')
              .toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _toast('Copied: $text');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink.withValues(alpha: .92),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        margin: const EdgeInsets.only(bottom: 100, left: 60, right: 60),
        duration: const Duration(milliseconds: 1700),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: AppText.disp(
            size: 12,
            weight: FontWeight.w600,
            color: AppColors.bg,
          ),
        ),
      ),
    );
  }

  void _onTopicExpandChanged(String topicName, bool expanded) {
    if (expanded) {
      _dds?.watchTopic(topicName);
    } else {
      _dds?.unwatchTopic(topicName);
    }
  }

  void _visualize(Topic topic) {
    final plugin = ViewerRegistry.viewerFor(topic.type);
    if (plugin == null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => UnknownTypeScreen(topic: topic)),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ViewerScreen(topic: topic, plugin: plugin, dds: _dds),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final topics = _filtered;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeader());

    return Stack(
      children: [
        Positioned.fill(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.only(top: _headerHeight),
              child: topics.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 42,
                            color: AppColors.ink3,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No matching topics',
                            style: AppText.body(
                              size: 13,
                              color: AppColors.ink2,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
                      itemCount: topics.length,
                      itemBuilder: (context, index) => RepaintBoundary(
                        child: TopicCard(
                          topic: topics[index],
                          onCopy: _copy,
                          onVisualize: _visualize,
                          onExpandChanged: _onTopicExpandChanged,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            // ShaderMask fades the blur+tint together (not just the
            // tint) over the header's own last ~12% — a scrolling card
            // sliding under the header softens into sharpness instead
            // of hitting a flat-color fade with a still-hard blur edge
            // underneath it.
            child: ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.black, Colors.transparent],
                stops: [0, 0.88, 1],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    key: _headerKey,
                    color: AppColors.bg.withValues(alpha: .55),
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ROS 2 · Humble',
                                    style: AppText.body(
                                      size: 13,
                                      weight: FontWeight.w500,
                                      color: AppColors.ink3,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Topics',
                                    style: AppText.disp(
                                      size: 26,
                                      weight: FontWeight.w600,
                                      letterSpacing: -.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _LivePill(
                              count: _topics.length,
                              onRefresh: () => _dds?.refresh(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SearchBarWidget(
                          controller: _searchController,
                          onChanged: (v) => setState(() => _query = v),
                        ),
                        const SizedBox(height: 3),
                        FilterChipBar(
                          selected: _filter,
                          onSelected: (f) => setState(() => _filter = f),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LivePill extends StatefulWidget {
  final int count;
  final VoidCallback onRefresh;
  const _LivePill({required this.count, required this.onRefresh});

  @override
  State<_LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<_LivePill> with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  @override
  void dispose() {
    _pulse.dispose();
    _spin.dispose();
    super.dispose();
  }

  void _handleRefresh() {
    widget.onRefresh();
    _spin.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: panelDecoration(radius: 16, small: true),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween(
              begin: 1.0,
              end: .55,
            ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.acc,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${widget.count} live',
            style: AppText.mono(
              size: 11,
              weight: FontWeight.w500,
              color: AppColors.ink2,
            ),
          ),
          const SizedBox(width: 7),
          GestureDetector(
            onTap: _handleRefresh,
            behavior: HitTestBehavior.opaque,
            child: RotationTransition(
              turns: Tween(begin: 0.0, end: 1.0).animate(_spin),
              child: Icon(Icons.refresh, size: 14, color: AppColors.ink3),
            ),
          ),
        ],
      ),
    );
  }
}
