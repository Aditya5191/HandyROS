import 'package:flutter/material.dart';
import '../app/theme.dart';

class SearchBarWidget extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const SearchBarWidget({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: recessedDecoration(radius: 17),
      child: Row(
        children: [
          Icon(Icons.search, color: AppColors.ink3, size: 20),
          const SizedBox(width: 11),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: AppText.body(
                size: 14,
                weight: FontWeight.w500,
                color: AppColors.ink,
              ),
              cursorColor: AppColors.acc,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search topics, types, nodes',
                hintStyle: AppText.body(
                  size: 14,
                  weight: FontWeight.w500,
                  color: AppColors.ink3,
                ),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return GestureDetector(
                onTap: () {
                  controller.clear();
                  onChanged('');
                },
                child: Icon(Icons.close, color: AppColors.ink3, size: 19),
              );
            },
          ),
        ],
      ),
    );
  }
}
