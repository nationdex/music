/// Small shared widgets: artwork, empty states, section cards, snackbars.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/library_controller.dart';

void showSnack(BuildContext context, String message, {SnackBarAction? action}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        duration: const Duration(seconds: 4),
      ),
    );
}

/// Cover art for a track, with the web build's music-note placeholder.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    this.track,
    this.size = 40,
    this.radius = 4,
    this.circle = false,
    this.icon = Icons.music_note_rounded,
    this.overlay,
  });

  final Track? track;
  final double size;
  final double radius;
  final bool circle;
  final IconData icon;

  /// Painted over the image, e.g. the "now playing" marker.
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lib = context.read<LibraryController>();
    final t = track;

    ImageProvider? image;
    if (t != null) {
      final file = lib.artworkFileFor(t);
      if (file != null) {
        final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
        image = ResizeImage(FileImage(file), width: px, allowUpscaling: false);
      } else if (t.artworkUrl != null && t.artworkUrl!.isNotEmpty) {
        image = NetworkImage(t.artworkUrl!);
      }
    }

    final shape = circle ? BoxShape.circle : BoxShape.rectangle;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        shape: shape,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null)
            Image(
              image: image,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Icon(
                icon,
                size: size * 0.55,
                color: scheme.onSecondaryContainer,
              ),
            )
          else
            Icon(icon, size: size * 0.55, color: scheme.onSecondaryContainer),
          ?overlay,
        ],
      ),
    );
  }
}

/// "Now playing" marker drawn over artwork.
class NowPlayingOverlay extends StatelessWidget {
  const NowPlayingOverlay({
    super.key,
    required this.playing,
    this.iconSize = 20,
  });

  final bool playing;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.scrim.withValues(alpha: 0.5),
      child: Icon(
        playing ? Icons.volume_up_rounded : Icons.play_arrow_rounded,
        size: iconSize,
        color: scheme.primary,
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.actions = const [],
  });

  final String title;
  final String? message;
  final IconData? icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 72,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                title,
                style: text.titleLarge?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const SizedBox(height: 4),
                Text(
                  message!,
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Titled rounded card used by Settings (`.card` in the web build).
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                title!,
                style: text.titleSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 || title == null)
              if (i > 0) const Divider(),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// True on iOS, where menus are action sheets and chrome uses glass.
bool get isIos => Platform.isIOS;
