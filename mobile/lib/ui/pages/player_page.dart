/// The full player. Ported from site/components/player.html: now playing on one
/// side, queue / history / lyrics on the other (a bottom sheet on phones).
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../state/library_controller.dart';
import '../../state/player_controller.dart';
import '../../state/settings_controller.dart';
import '../chrome.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/glass.dart';
import '../widgets/track_widgets.dart';

enum PlayerTab { queue, history, lyrics }

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  PlayerTab _tab = PlayerTab.queue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<PlayerController>();
      if (p.lyricsStatus == LyricsStatus.idle && p.currentTrack != null) p.fetchLyrics();
    });
  }

  void _selectTab(PlayerTab tab) {
    setState(() => _tab = tab);
    if (tab == PlayerTab.lyrics) {
      final p = context.read<PlayerController>();
      if (p.lyricsStatus == LyricsStatus.idle && p.currentTrack != null) p.fetchLyrics();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final track = context.select<PlayerController, Track?>((p) => p.currentTrack);
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _ArtworkWash(track: track),
          SafeArea(
            child: wide
                ? Row(
                    children: [
                      const Expanded(child: _NowPlaying()),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                          child: Card(
                            color: scheme.surfaceContainer.withValues(alpha: 0.9),
                            child: Column(
                              children: [
                                Padding(padding: const EdgeInsets.all(12), child: _TabSwitcher(tab: _tab, onChanged: _selectTab)),
                                Expanded(child: _PanelFor(tab: _tab)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      const Expanded(child: _NowPlaying()),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: GlassSurface(
                          borderRadius: 28,
                          padding: const EdgeInsets.all(6),
                          child: Row(
                            children: [
                              for (final t in PlayerTab.values)
                                Expanded(
                                  child: TextButton.icon(
                                    icon: Icon(switch (t) {
                                      PlayerTab.queue => Icons.queue_music_rounded,
                                      PlayerTab.history => Icons.history_rounded,
                                      PlayerTab.lyrics => Icons.lyrics_outlined,
                                    }),
                                    label: Text(switch (t) {
                                      PlayerTab.queue => 'Queue',
                                      PlayerTab.history => 'History',
                                      PlayerTab.lyrics => 'Lyrics',
                                    }),
                                    onPressed: () {
                                      _selectTab(t);
                                      _openSheet(context, t);
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _openSheet(BuildContext context, PlayerTab tab) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => _SheetBody(initial: tab),
      ),
    );
  }
}

class _SheetBody extends StatefulWidget {
  const _SheetBody({required this.initial});
  final PlayerTab initial;

  @override
  State<_SheetBody> createState() => _SheetBodyState();
}

class _SheetBodyState extends State<_SheetBody> {
  late PlayerTab _tab = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _TabSwitcher(
            tab: _tab,
            onChanged: (t) {
              setState(() => _tab = t);
              final p = context.read<PlayerController>();
              if (t == PlayerTab.lyrics && p.lyricsStatus == LyricsStatus.idle && p.currentTrack != null) p.fetchLyrics();
            },
          ),
        ),
        Expanded(child: _PanelFor(tab: _tab)),
      ],
    );
  }
}

class _TabSwitcher extends StatelessWidget {
  const _TabSwitcher({required this.tab, required this.onChanged});

  final PlayerTab tab;
  final ValueChanged<PlayerTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<PlayerTab>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: PlayerTab.queue, label: Text('Queue')),
        ButtonSegment(value: PlayerTab.history, label: Text('History')),
        ButtonSegment(value: PlayerTab.lyrics, label: Text('Lyrics')),
      ],
      selected: {tab},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _PanelFor extends StatelessWidget {
  const _PanelFor({required this.tab});
  final PlayerTab tab;

  @override
  Widget build(BuildContext context) => switch (tab) {
    PlayerTab.queue => const _QueuePanel(),
    PlayerTab.history => const _HistoryPanel(),
    PlayerTab.lyrics => const _LyricsPanel(),
  };
}

/// Blurred artwork behind the page.
class _ArtworkWash extends StatelessWidget {
  const _ArtworkWash({required this.track});
  final Track? track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lib = context.read<LibraryController>();
    ImageProvider? image;
    if (track != null) {
      final f = lib.artworkFileFor(track!);
      image = f != null ? FileImage(f) : (track!.artworkUrl != null ? NetworkImage(track!.artworkUrl!) : null);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: scheme.surface),
        if (image != null)
          Opacity(
            opacity: 0.35,
            child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60, tileMode: TileMode.clamp), child: Image(image: image, fit: BoxFit.cover, gaplessPlayback: true)),
          ),
      ],
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final lib = context.watch<LibraryController>();
    final settings = context.watch<SettingsController>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final track = player.currentTrack;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Row(
            children: [
              IconButton(tooltip: 'Back', icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32), onPressed: () => Navigator.of(context).maybePop()),
              Expanded(child: Text('Player', style: text.titleLarge)),
              IconButton(tooltip: 'Open equalizer', icon: const Icon(Icons.equalizer_rounded), onPressed: () => showEqualizerSheet(context)),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
              child: LayoutBuilder(
                builder: (_, c) {
                  final side = c.biggest.shortestSide.clamp(120.0, 420.0);
                  return Container(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 32, offset: const Offset(0, 12))]),
                    child: Artwork(track: track, size: side, radius: 24, icon: Icons.music_note_rounded),
                  );
                },
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Expanded(
                child: track == null
                    ? Text('Nothing playing', style: text.titleLarge?.copyWith(color: scheme.onSurfaceVariant))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
              ),
              if (track != null)
                IconButton(
                  tooltip: lib.isFavorite(track) ? 'Remove from favorites' : 'Add to favorites',
                  icon: Icon(lib.isFavorite(track) ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: lib.isFavorite(track) ? scheme.primary : scheme.onSurfaceVariant),
                  onPressed: () => lib.toggleFavorite(track),
                ),
            ],
          ),
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: SeekBar()),
        const TransportControls(large: true),
        if (settings.settings.volumeInPlayer)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Toggle mute',
                  icon: Icon(player.muted || player.volume == 0 ? Icons.volume_off_rounded : (player.volume < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded)),
                  onPressed: player.toggleMute,
                ),
                Expanded(child: Slider(value: player.muted ? 0 : player.volume, onChanged: player.setVolume)),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, required this.current, required this.onTap, this.trailing});

  final Track track;
  final bool current;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      minTileHeight: 64,
      leading: Artwork(track: track, size: 44),
      title: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: current ? scheme.primary : null)),
      subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    if (player.queue.isEmpty) {
      return const EmptyState(title: 'Your queue is empty', icon: Icons.queue_music_rounded);
    }
    final text = Theme.of(context).textTheme;
    return ListView.builder(
      itemCount: player.queue.length,
      itemBuilder: (_, i) {
        final t = player.queue[i];
        return _TrackRow(
          track: t,
          current: i == player.queuePos,
          onTap: () => player.playQueueIndex(i),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatTime(t.duration), style: text.bodyMedium),
              IconButton(tooltip: 'Remove from queue', icon: const Icon(Icons.close_rounded), onPressed: i == player.queuePos ? null : () => player.removeFromQueue(i)),
            ],
          ),
        );
      },
    );
  }
}

class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel();

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    final player = context.read<PlayerController>();
    if (lib.history.isEmpty) return const EmptyState(title: 'Nothing played yet', icon: Icons.history_rounded);
    return ListView.builder(
      itemCount: lib.history.length,
      itemBuilder: (_, i) => _TrackRow(track: lib.history[i], current: player.isCurrent(lib.history[i]), onTap: () => player.playFromList(lib.history, i)),
    );
  }
}

class _LyricsPanel extends StatefulWidget {
  const _LyricsPanel();

  @override
  State<_LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<_LyricsPanel> {
  List<GlobalKey> _keys = const [];
  late final PlayerController _player = context.read<PlayerController>();

  @override
  void initState() {
    super.initState();
    _player.activeLyricIndex.addListener(_scrollToActive);
  }

  @override
  void dispose() {
    _player.activeLyricIndex.removeListener(_scrollToActive);
    super.dispose();
  }

  void _scrollToActive() {
    final i = _player.activeLyricIndex.value;
    if (i < 0 || i >= _keys.length) return;
    final ctx = _keys[i].currentContext;
    if (ctx == null) return;
    final reduced = context.read<SettingsController>().reducedMotion(context);
    Scrollable.ensureVisible(ctx, alignment: 0.4, duration: reduced ? Duration.zero : const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (player.currentTrack == null) return const EmptyState(title: 'Play a track to see its lyrics', icon: Icons.lyrics_outlined);
    switch (player.lyricsStatus) {
      case LyricsStatus.idle:
      case LyricsStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case LyricsStatus.none:
        return const EmptyState(title: 'No lyrics found for this track', icon: Icons.lyrics_outlined);
      case LyricsStatus.plain:
        return SingleChildScrollView(padding: const EdgeInsets.all(24), child: Text(player.lyricsContent, style: text.bodyLarge?.copyWith(height: 1.7)));
      case LyricsStatus.synced:
        if (_keys.length != player.lyricLines.length) _keys = List.generate(player.lyricLines.length, (_) => GlobalKey());
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: ValueListenableBuilder<int>(
            valueListenable: player.activeLyricIndex,
            builder: (_, active, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < player.lyricLines.length; i++)
                  InkWell(
                    key: _keys[i],
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => player.seekToLine(player.lyricLines[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        opacity: i == active ? 1 : 0.4,
                        child: Text(
                          player.lyricLines[i].text.isEmpty ? '·' : player.lyricLines[i].text,
                          style: text.headlineSmall?.copyWith(color: i == active ? scheme.onSurface : scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
    }
  }
}
