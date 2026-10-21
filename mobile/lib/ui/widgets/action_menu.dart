/// Context menus. Android shows a Material popup menu anchored to the button;
/// iOS shows a native-style action sheet, like the web build's menu but
/// idiomatic for each platform.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'common.dart';

class MenuAction {
  const MenuAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelected;
  final bool destructive;
}

Future<void> showActionMenu(
  BuildContext anchor,
  List<MenuAction> actions, {
  String? title,
}) async {
  if (actions.isEmpty) return;
  if (isIos) {
    await showCupertinoModalPopup<void>(
      context: anchor,
      builder: (ctx) => CupertinoActionSheet(
        title: title == null ? null : Text(title),
        actions: [
          for (final a in actions)
            CupertinoActionSheetAction(
              isDestructiveAction: a.destructive,
              onPressed: () {
                Navigator.of(ctx).pop();
                a.onSelected();
              },
              child: Text(a.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
    return;
  }

  final box = anchor.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final rect = RelativeRect.fromRect(
    topLeft & box.size,
    Offset.zero & overlay.size,
  );
  final scheme = Theme.of(anchor).colorScheme;

  final chosen = await showMenu<MenuAction>(
    context: anchor,
    position: rect,
    items: [
      for (final a in actions)
        PopupMenuItem<MenuAction>(
          value: a,
          child: Row(
            children: [
              Icon(
                a.icon,
                size: 20,
                color: a.destructive ? scheme.error : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Text(
                a.label,
                style: a.destructive ? TextStyle(color: scheme.error) : null,
              ),
            ],
          ),
        ),
    ],
  );
  chosen?.onSelected();
}

/// An icon button that opens [actionsBuilder]'s menu.
class ActionMenuButton extends StatelessWidget {
  const ActionMenuButton({
    super.key,
    required this.actionsBuilder,
    this.icon = Icons.more_vert_rounded,
    this.tooltip = 'More options',
    this.title,
  });

  final List<MenuAction> Function(BuildContext context) actionsBuilder;
  final IconData icon;
  final String tooltip;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (ctx) => IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: () => showActionMenu(ctx, actionsBuilder(ctx), title: title),
      ),
    );
  }
}
