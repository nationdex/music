/// Dialogs and sheets: confirm, new playlist, add to playlist, accent colour, equalizer.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/palette.dart';
import '../../data/models.dart';
import '../../state/library_controller.dart';
import '../../state/player_controller.dart';
import 'common.dart';

Future<bool> confirmDialog(BuildContext context, {required String title, required String body, required String confirmLabel}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Asks for a playlist name. Returns null when cancelled.
Future<String?> promptPlaylistName(BuildContext context) {
  return showDialog<String>(context: context, builder: (ctx) => const _NewPlaylistDialog());
}

class _NewPlaylistDialog extends StatefulWidget {
  const _NewPlaylistDialog();

  @override
  State<_NewPlaylistDialog> createState() => _NewPlaylistDialogState();
}

class _NewPlaylistDialogState extends State<_NewPlaylistDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('New playlist'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Name'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (v) => v.trim().isEmpty ? null : Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: valid ? () => Navigator.pop(context, _controller.text.trim()) : null, child: const Text('Create')),
      ],
    );
  }
}

/// Create a playlist (and optionally add [track] to it) after asking for a name.
Future<void> createPlaylistFlow(BuildContext context, {Track? track}) async {
  final name = await promptPlaylistName(context);
  if (name == null || !context.mounted) return;
  final lib = context.read<LibraryController>();
  final id = lib.createPlaylist(name);
  if (track != null) {
    lib.addTrackToPlaylist(track, id);
    showSnack(context, 'Added to “$name”');
  } else {
    showSnack(context, 'Playlist “$name” created');
  }
}

Future<void> showAddToPlaylistSheet(BuildContext context, Track track) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final lib = ctx.watch<LibraryController>();
      final lists = lib.customPlaylists;
      final text = Theme.of(ctx).textTheme;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: Text('Add to playlist', style: text.titleLarge)),
              Flexible(
                child: lists.isEmpty
                    ? Padding(padding: const EdgeInsets.all(24), child: Text('No playlists yet.', style: text.bodyMedium))
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final pl in lists)
                            ListTile(
                              leading: const Icon(Icons.queue_music_rounded),
                              title: Text(pl.name),
                              onTap: () {
                                final name = lib.addTrackToPlaylist(track, pl.id);
                                Navigator.pop(ctx);
                                if (name != null) showSnack(context, 'Added to “$name”');
                              },
                            ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New playlist'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      createPlaylistFlow(context, track: track);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Picks an accent colour from a hue grid, or by hex. Returns null when cancelled.
Future<Color?> pickAccentColor(BuildContext context, {Color? current}) {
  return showDialog<Color>(context: context, builder: (ctx) => _AccentDialog(current: current));
}

class _AccentDialog extends StatefulWidget {
  const _AccentDialog({this.current});
  final Color? current;

  @override
  State<_AccentDialog> createState() => _AccentDialogState();
}

class _AccentDialogState extends State<_AccentDialog> {
  late final TextEditingController _hex = TextEditingController(text: colorToHex(widget.current ?? const Color(0xFFC0000C)));
  late Color _picked = widget.current ?? const Color(0xFFC0000C);

  static final _swatches = [for (var h = 0; h < 360; h += 30) hslToColor(h.toDouble(), 70, 46)];

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Primary color'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final c in _swatches)
                  Semantics(
                    button: true,
                    label: 'Color ${colorToHex(c)}',
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _picked = c;
                        _hex.text = colorToHex(c);
                      }),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: colorToHex(c) == colorToHex(_picked) ? scheme.onSurface : Colors.transparent, width: 3),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _hex,
              decoration: InputDecoration(
                labelText: 'Hex color',
                prefixIcon: Padding(padding: const EdgeInsets.all(12), child: CircleAvatar(backgroundColor: _picked)),
              ),
              maxLength: 7,
              onChanged: (v) {
                final c = parseHex(v);
                if (c != null) setState(() => _picked = c);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, _picked), child: const Text('Apply')),
      ],
    );
  }
}

Future<void> showEqualizerSheet(BuildContext context) {
  return showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (ctx) => const _EqualizerSheet());
}

class _EqualizerSheet extends StatelessWidget {
  const _EqualizerSheet();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget body;
    if (!player.eqPlatformSupported) {
      body = Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'The equalizer is available on Android only. iOS does not let apps process the audio of the system player.',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    } else if (!player.eqSupported) {
      body = const Padding(padding: EdgeInsets.all(24), child: Text('This device does not provide an equalizer.'));
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final name in eqPresets.keys)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(name), selected: player.eqPreset == name, onSelected: (_) => player.applyEqPreset(name)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: Row(
              children: [
                for (var i = 0; i < player.eqBands.length; i++)
                  Expanded(
                    child: Column(
                      children: [
                        Text('${player.eqBands[i].gain > 0 ? '+' : ''}${player.eqBands[i].gain.round()}', style: text.labelSmall),
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Slider(
                              min: player.eqMinDb,
                              max: player.eqMaxDb,
                              value: player.eqBands[i].gain.clamp(player.eqMinDb, player.eqMaxDb),
                              onChanged: (v) => player.setEqBand(i, v),
                            ),
                          ),
                        ),
                        Text(player.eqBands[i].label, style: text.labelSmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Row(
              children: [
                Expanded(child: Text('Equalizer', style: text.titleLarge)),
                if (player.eqSupported) TextButton(onPressed: () => player.applyEqPreset('Flat'), child: const Text('Reset')),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ],
            ),
          ),
          body,
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
