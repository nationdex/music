/// Track rows, the seek bar and transport buttons.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../state/library_controller.dart';
import '../../state/player_controller.dart';
import 'action_menu.dart';
import 'common.dart';
import 'dialogs.dart';

List<MenuAction> trackMenuActions(BuildContext context, Track track) {
  final player = context.read<PlayerController>();
  final lib = context.read<LibraryController>();
  return [
    MenuAction(
      icon: Icons.play_arrow_rounded,
      label: 'Play next',
      onSelected: () => showSnack(context, player.playNext(track) ? 'Playing next' : 'Playing “${track.name}”'),
    ),
    MenuAction(
      icon: Icons.queue_music_rounded,
      label: 'Add to queue',
      onSelected: () => showSnack(context, player.addToQueue(track) ? 'Added to queue' : 'Playing “${track.name}”'),
    ),
    MenuAction(icon: Icons.playlist_add_rounded, label: 'Add to playlist', onSelected: () => showAddToPlaylistSheet(context, track)),
    MenuAction(
      icon: Icons.delete_outline_rounded,
      label: 'Remove from library',
      destructive: true,
      onSelected: () async {
        final ok = await confirmDialog(
          context,
          title: 'Remove from library?',
          body: '“${track.name}” will be removed from this device.',
          confirmLabel: 'Remove',
        );
        if (ok) {
          await lib.removeTrack(track);
          if (context.mounted) showSnack(context, 'Removed “${track.name}”');
        }
      },
    ),
  ];
}

/// One row of a track list: artwork, title and artist, favourite, options, duration.
class TrackTile extends StatelessWidget {
  const TrackTile({super.key, required this.track, required this.onTap, this.showAlbum = false});

  final Track track;
  final VoidCallback onTap;

  /// Wide layouts show the album column like the web build's `md:` grid.
  final bool showAlbum;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final current = context.select<PlayerController, bool>((p) => p.isCurrent(track));
    final playing = context.select<PlayerController, bool>((p) => p.isCurrent(track) && p.isPlaying);
    final favorite = context.select<LibraryController, bool>((l) => l.isFavorite(track));
    final lib = context.read<LibraryController>();

    return InkWell(
      onTap: onTap,
      onLongPress: () => showActionMenu(context, trackMenuActions(context, track), title: track.name),
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 72,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 4),
          child: Row(
            children: [
              Artwork(track: track, size: 40, overlay: current ? NowPlayingOverlay(playing: playing) : null),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall?.copyWith(color: current ? scheme.primary : scheme.onSurface)),
                    Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (showAlbum) ...[
                const SizedBox(width: 12),
                Expanded(flex: 3, child: Text(track.album, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
              ],
              if (track.stored && MediaQuery.sizeOf(context).width >= 600)
                Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.check_rounded, size: 16, color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
              IconButton(
                tooltip: favorite ? 'Remove from favorites' : 'Add to favorites',
                icon: Icon(favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: favorite ? scheme.primary : scheme.onSurfaceVariant),
                onPressed: () => lib.toggleFavorite(track),
              ),
              ActionMenuButton(tooltip: 'Track options', title: track.name, actionsBuilder: (ctx) => trackMenuActions(ctx, track)),
              SizedBox(
                width: 48,
                child: Text(formatTime(track.duration), textAlign: TextAlign.right, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seek slider with elapsed and total time, driven by the player's position notifier.
class SeekBar extends StatefulWidget {
  const SeekBar({super.key, this.compact = false});

  final bool compact;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final text = Theme.of(context).textTheme.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final hasTrack = context.select<PlayerController, bool>((p) => p.currentTrack != null);

    return ValueListenableBuilder<Duration>(
      valueListenable: player.duration,
      builder: (context, duration, _) => ValueListenableBuilder<Duration>(
        valueListenable: player.position,
        builder: (context, position, _) {
          final total = duration.inMilliseconds / 1000;
          final max = total > 0 ? total : 1.0;
          final value = (_drag ?? position.inMilliseconds / 1000).clamp(0.0, max).toDouble();
          return Row(
            children: [
              SizedBox(width: 44, child: Text(formatTime(value), style: text)),
              Expanded(
                child: Slider(
                  value: value,
                  max: max,
                  onChanged: hasTrack ? (v) => setState(() => _drag = v) : null,
                  onChangeEnd: (v) {
                    setState(() => _drag = null);
                    player.seekTo(Duration(milliseconds: (v * 1000).round()));
                  },
                ),
              ),
              SizedBox(width: 44, child: Text(formatTime(total), textAlign: TextAlign.right, style: text)),
            ],
          );
        },
      ),
    );
  }
}

/// Shuffle, previous, play/pause, next, repeat.
class TransportControls extends StatelessWidget {
  const TransportControls({super.key, this.large = false});

  final bool large;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    final iconSize = large ? 32.0 : 24.0;

    Widget toggle({required IconData icon, required bool on, required String label, required VoidCallback onPressed}) => IconButton(
      tooltip: label,
      isSelected: on,
      icon: Icon(icon, size: iconSize),
      style: IconButton.styleFrom(foregroundColor: on ? scheme.primary : scheme.onSurfaceVariant),
      onPressed: onPressed,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        toggle(icon: Icons.shuffle_rounded, on: player.shuffle, label: player.shuffle ? 'Disable shuffle' : 'Enable shuffle', onPressed: player.toggleShuffle),
        IconButton(tooltip: 'Previous', iconSize: iconSize + 4, icon: const Icon(Icons.skip_previous_rounded), onPressed: player.previousTrack),
        const SizedBox(width: 4),
        IconButton.filled(
          tooltip: player.isPlaying ? 'Pause' : 'Play',
          iconSize: iconSize + 8,
          style: IconButton.styleFrom(minimumSize: Size.square(large ? 72 : 56)),
          icon: player.isLoading && player.currentTrack != null
              ? SizedBox(width: iconSize, height: iconSize, child: CircularProgressIndicator(strokeWidth: 3, color: scheme.onPrimary))
              : Icon(player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
          onPressed: player.togglePlay,
        ),
        const SizedBox(width: 4),
        IconButton(tooltip: 'Next', iconSize: iconSize + 4, icon: const Icon(Icons.skip_next_rounded), onPressed: player.nextTrack),
        toggle(
          icon: player.repeat == RepeatSetting.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
          on: player.repeat != RepeatSetting.off,
          label: 'Repeat: ${player.repeat.name}',
          onPressed: player.cycleRepeat,
        ),
      ],
    );
  }
}
