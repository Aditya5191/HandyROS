import 'package:flutter/material.dart';

/// Set from main() via AppSettings, and whenever the user changes the
/// theme in Settings — read directly rather than via BuildContext
/// because CustomPainters (every canvas viewer) have no context to
/// look up Theme.of() with, only a Canvas.
class AppBrightness {
  static Brightness current = Brightness.light;
}

/// "Calm" design tokens — a warm, neumorphic (soft-UI) palette:
/// raised/inset dual-shadow surfaces instead of flat bordered cards.
/// Dynamic per [AppBrightness.current], not compile-time constants, so
/// they can't be used inside `const` widget constructors. There is no
/// longer a separate always-dark "instrument screen" look for canvas
/// viewers/terminal/raw echo — those are recessed warm panels now,
/// like everything else, matching the calmer overall aesthetic.
abstract class AppColors {
  static bool get _dark => AppBrightness.current == Brightness.dark;

  // Base surfaces. `card` is deliberately *lighter* than `bg` (not a
  // border, a raised-shadow pair against `bg` is what makes it read
  // as embossed) — `raised` is a third, even-lighter tone used only
  // for the icon-badge gradient's light stop.
  static Color get bg =>
      _dark ? const Color(0xFF1B1C1A) : const Color(0xFFE7E4DE);
  static Color get card =>
      _dark ? const Color(0xFF232522) : const Color(0xFFEDEAE4);
  static Color get raised =>
      _dark ? const Color(0xFF272924) : const Color(0xFFEFECE6);

  // The two neumorphic shadow colors: a darker-than-surface one and a
  // lighter-than-surface one, combined as a matched pair everywhere
  // (see [raisedShadow]/[raisedShadowSm] and [recessedDecoration]). A
  // pure-white highlight (right for the light palette) would look
  // garish on the dark palette, so the dark pair uses a muted lighter
  // warm gray instead of true white.
  static Color get shadowDark =>
      _dark ? const Color(0xFF0E0F0D) : const Color(0xFFC8C4BB);
  static Color get shadowLight =>
      _dark ? const Color(0xFF34362F) : const Color(0xFFFFFFFF);

  static Color get ink =>
      _dark ? const Color(0xFFEDEBE6) : const Color(0xFF34322D);
  static Color get ink2 =>
      _dark ? const Color(0xFFA29C90) : const Color(0xFF7D786F);
  static Color get ink3 =>
      _dark ? const Color(0xFF6E6A61) : const Color(0xFFA9A49A);
  static Color get line =>
      _dark ? const Color(0x12EDEBE6) : const Color(0x12343229);

  static const acc = Color(0xFF5E8B82);
  static const acc2 = Color(0xFF4D766E);
  static Color get accTint =>
      _dark ? const Color(0x335E8B82) : const Color(0x245E8B82);

  // Category colors — kept under their old names to avoid renaming
  // every call site, values updated to the new palette. `pri` and the
  // Image/Graph viewer category are the same color as `acc` (that's
  // what the design uses for both).
  static const pri = acc; // image, graph
  static const sec = Color(0xFF8878A6); // imu
  static const lime = Color(0xFF7F9B6B); // laser
  static const pink = Color(0xFFB3806E); // cloud
  static const amber = Color(0xFFC2A05A); // odom / nav
  static const blue = Color(0xFF6B83A6); // tf
  static const ok = Color(0xFF6F9080); // terminal
  static const custom = Color(0xFF9A958C); // raw / fallback
  static const red = Color(
    0xFFA8574A,
  ); // destructive/error — not in the reference design, kept in-palette
}

/// Canvas viewer background — a slightly lighter recessed well than
/// `bg`, theme-aware (used to be a fixed always-dark "instrument
/// screen" regardless of app theme; the reference design replaces
/// that with a recessed panel like everything else).
Color get canvasBackground =>
    Color.lerp(AppColors.bg, AppColors.shadowLight, 0.35)!;

abstract class AppGradients {
  /// Fixed neutral gradient used for every icon badge, regardless of
  /// category — the category color goes on the icon glyph itself, not
  /// the badge background (that's how the reference design does it,
  /// a change from the old per-color-tinted badge background).
  static LinearGradient get iconBadge => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.raised,
      Color.lerp(AppColors.card, AppColors.shadowDark, 0.18)!,
    ],
  );
}

/// The two-shadow "raised"/embossed look used for cards, pills, and
/// buttons throughout. Static per surface (only changes on
/// expand/collapse, never animated per-frame) and capped at the
/// reference design's own blur radii — cost scales with blur, and
/// this list is exactly what a prior revision's jank came from
/// stacking *more* of ("multiple blurred glow shadows per card was
/// the main source of scroll jank on the topic list"). Each
/// `ListView.builder` item using this should sit in its own
/// `RepaintBoundary` so shadow rasterization doesn't cascade across
/// siblings during scroll.
List<BoxShadow> get raisedShadow => [
  BoxShadow(
    color: AppColors.shadowDark,
    offset: const Offset(6, 6),
    blurRadius: 15,
  ),
  BoxShadow(
    color: AppColors.shadowLight.withValues(alpha: .85),
    offset: const Offset(-5, -5),
    blurRadius: 13,
  ),
];

/// A much tighter version for small, tightly-packed elements (filter
/// chips, QoS pills, icon buttons) — the regular scale's offset+blur
/// reach (~20px) exceeds the gap between adjacent chips (9px), so
/// neighboring shadows visually collide into a blurry halo instead of
/// each chip reading as its own separate raised pill. Also drops the
/// highlight to well under full white — at 44px scale a 100%-opaque
/// white glow reads as a stray bright edge rather than a subtle emboss.
List<BoxShadow> get raisedShadowSm => [
  BoxShadow(
    color: AppColors.shadowDark.withValues(alpha: .8),
    offset: const Offset(2, 2),
    blurRadius: 4,
  ),
  BoxShadow(
    color: AppColors.shadowLight.withValues(alpha: .6),
    offset: const Offset(-1.5, -1.5),
    blurRadius: 3,
  ),
];

/// Deeper raised shadow used for an *expanded* topic card specifically
/// (the reference design lifts it further than the resting `raised`).
List<BoxShadow> get raisedShadowLg => [
  BoxShadow(
    color: AppColors.shadowDark,
    offset: const Offset(8, 8),
    blurRadius: 20,
  ),
  BoxShadow(
    color: AppColors.shadowLight.withValues(alpha: .85),
    offset: const Offset(-6, -6),
    blurRadius: 15,
  ),
];

/// Raised card/pill/button surface — the default "everything sits on
/// this" decoration, replacing the old flat bordered-card look.
BoxDecoration panelDecoration({
  Color? color,
  double radius = 18,
  bool small = false,
  bool expanded = false,
}) {
  return BoxDecoration(
    color: color ?? AppColors.card,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: expanded
        ? raisedShadowLg
        : (small ? raisedShadowSm : raisedShadow),
  );
}

/// Recessed/"pressed-in"/engraved surface — search bars, canvas viewer
/// backgrounds, stat-grid wells, segmented-control tracks. A true
/// inset shadow pair. Flutter's own `BoxShadow(blurStyle: BlurStyle.inner)`
/// looked backwards in practice — a hazy *outer* glow, not an engraved
/// edge — because `BoxDecoration`'s painter never clips it to the box;
/// [_RecessedBoxDecoration] does the clip-then-masked-hole painting by
/// hand instead (the tried-and-tested inset-shadow technique — clip to
/// the rounded rect, then draw the shadow color everywhere *outside* a
/// shifted, blurred copy of that same rect, which reads as a shadow
/// falling inward from the edge).
BoxDecoration recessedDecoration({Color? base, double radius = 15}) {
  return _RecessedBoxDecoration(
    color: base ?? AppColors.bg,
    borderRadius: BorderRadius.circular(radius),
    shadows: [
      _InsetShadow(
        color: AppColors.shadowDark.withValues(alpha: .9),
        offset: const Offset(3, 3),
        blurRadius: 5,
      ),
      _InsetShadow(
        color: AppColors.shadowLight.withValues(alpha: .8),
        offset: const Offset(-2, -2),
        blurRadius: 4,
      ),
    ],
  );
}

class _InsetShadow {
  final Color color;
  final Offset offset;
  final double blurRadius;
  const _InsetShadow({
    required this.color,
    required this.offset,
    required this.blurRadius,
  });
}

class _RecessedBoxDecoration extends BoxDecoration {
  final List<_InsetShadow> shadows;

  const _RecessedBoxDecoration({
    required Color color,
    required BorderRadius borderRadius,
    required this.shadows,
  }) : super(color: color, borderRadius: borderRadius);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _RecessedBoxPainter(this);
}

class _RecessedBoxPainter extends BoxPainter {
  final _RecessedBoxDecoration decoration;
  _RecessedBoxPainter(this.decoration);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size!;
    final rect = offset & size;
    final rrect = (decoration.borderRadius as BorderRadius).toRRect(rect);

    canvas.drawRRect(rrect, Paint()..color = decoration.color!);

    canvas.save();
    canvas.clipRRect(rrect);
    for (final s in decoration.shadows) {
      final reach = s.blurRadius + s.offset.distance + size.longestSide;
      final outer = rect.inflate(reach);
      canvas.drawDRRect(
        RRect.fromRectAndRadius(outer, Radius.zero),
        rrect.shift(s.offset),
        Paint()
          ..color = s.color
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            BoxShadow(blurRadius: s.blurRadius).blurSigma,
          ),
      );
    }
    canvas.restore();
  }
}

/// Frosted-glass overlay used for HUD chips / tool rows floating over
/// a canvas viewer, and the bottom nav bar.
BoxDecoration glassDecoration({double radius = 16}) {
  return BoxDecoration(
    color: AppColors.card.withValues(alpha: .72),
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: AppColors.shadowDark.withValues(alpha: .18),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

/// Instrument Sans / JetBrains Mono are bundled as local assets (see
/// pubspec.yaml), not fetched at runtime via google_fonts — the phone
/// has no internet access while connected to a ROS DDS network (the
/// whole point of the app), so a runtime font fetch fails outright
/// there. Both are variable fonts, so a single asset per family
/// covers every weight used via TextStyle.fontWeight as normal.
abstract class AppText {
  static TextStyle disp({
    double size = 14,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: 'InstrumentSans',
    fontSize: size,
    fontWeight: weight,
    color: color ?? AppColors.ink,
    letterSpacing: letterSpacing,
  );

  static TextStyle mono({
    double size = 12,
    FontWeight weight = FontWeight.w600,
    Color? color,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: size,
    fontWeight: weight,
    color: color ?? AppColors.ink,
    letterSpacing: letterSpacing,
  );

  static TextStyle body({
    double size = 13,
    FontWeight weight = FontWeight.w500,
    Color? color,
  }) => TextStyle(
    fontFamily: 'InstrumentSans',
    fontSize: size,
    fontWeight: weight,
    color: color ?? AppColors.ink2,
  );
}

class HandyTheme {
  // Deliberately built from fixed literals, not the dynamic AppColors
  // getters — each ThemeData describes one mode outright, rather than
  // reading a "current mode" that these definitions would otherwise
  // be responsible for driving (MaterialApp picks between the two via
  // `themeMode`; AppBrightness.current is kept in sync separately,
  // for CustomPainters that have no Theme.of(context) to read).
  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFE7E4DE),
    fontFamily: 'InstrumentSans',
    colorScheme: const ColorScheme.light(
      primary: AppColors.acc,
      secondary: AppColors.sec,
      surface: Color(0xFFEDEAE4),
      error: AppColors.red,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFE7E4DE),
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'InstrumentSans',
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Color(0xFF34322D),
      ),
      iconTheme: IconThemeData(color: Color(0xFF34322D)),
    ),
    cardColor: const Color(0xFFEDEAE4),
    dividerColor: const Color(0x12343229),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    useMaterial3: true,
  );

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF1B1C1A),
    fontFamily: 'InstrumentSans',
    colorScheme: const ColorScheme.dark(
      primary: AppColors.acc,
      secondary: AppColors.sec,
      surface: Color(0xFF232522),
      error: AppColors.red,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1B1C1A),
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'InstrumentSans',
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Color(0xFFEDEBE6),
      ),
      iconTheme: IconThemeData(color: Color(0xFFEDEBE6)),
    ),
    cardColor: const Color(0xFF232522),
    dividerColor: const Color(0x12EDEBE6),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    useMaterial3: true,
  );
}
