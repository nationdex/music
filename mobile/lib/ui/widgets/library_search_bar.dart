/// The rounded search row used at the top of every library page.
library;

import 'package:flutter/material.dart';

class LibrarySearchBar extends StatelessWidget {
  const LibrarySearchBar({super.key, required this.controller, required this.hint, required this.onChanged, this.actions = const [], this.onSubmitted, this.radius = 16});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<Widget> actions;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              style: text.bodyMedium,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurface.withValues(alpha: 0.6)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                prefixIcon: null,
              ),
            ),
          ),
          if (actions.isNotEmpty) ...[
            Container(width: 1, height: 24, color: scheme.outlineVariant),
            const SizedBox(width: 4),
            ...actions,
          ],
        ],
      ),
    );
  }
}
