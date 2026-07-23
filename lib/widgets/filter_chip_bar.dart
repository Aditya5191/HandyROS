import 'package:flutter/material.dart';
import '../app/theme.dart';

class FilterChipDef {
  final String id;
  final String label;

  const FilterChipDef(this.id, this.label);
}

const List<FilterChipDef> kFilterChips = [
  FilterChipDef('all', 'All'),
  FilterChipDef('image', 'Images'),
  FilterChipDef('laser', 'Laser'),
  FilterChipDef('cloud', 'Clouds'),
  FilterChipDef('tf', 'TF'),
  FilterChipDef('nav', 'Navigation'),
  FilterChipDef('active', 'Active'),
];

class FilterChipBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const FilterChipBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      // Fades chips out at the left/right edges instead of a hard clip
      // as they scroll under the screen margin — a softer scroll
      // affordance matching the rest of the app's rounded/soft language.
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0, 0.045, 0.955, 1],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 3, 20, 14),
          itemCount: kFilterChips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 9),
          itemBuilder: (context, index) {
            final chip = kFilterChips[index];
            final on = chip.id == selected;
            return GestureDetector(
              onTap: () => onSelected(chip.id),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: on
                    ? recessedDecoration(base: AppColors.accTint, radius: 15)
                    : BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        color: AppColors.card,
                        boxShadow: raisedShadowSm,
                      ),
                alignment: Alignment.center,
                child: Transform.translate(
                  offset: const Offset(0, -1.5),
                  child: Text(
                    chip.label,
                    style: AppText.disp(
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: on ? AppColors.acc2 : AppColors.ink2,
                      letterSpacing: .2,
                    ),
                    overflow: TextOverflow.visible,
                    softWrap: false,
                    strutStyle: const StrutStyle(
                      fontSize: 12.5,
                      height: 1,
                      forceStrutHeight: true,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
