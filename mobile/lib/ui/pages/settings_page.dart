/// Settings. Ported from site/components/settings.html.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/palette.dart';
import '../../core/format.dart';
import '../../state/library_controller.dart';
import '../../state/player_controller.dart';
import '../../state/settings_controller.dart';
import '../file_picking.dart';
import '../navigation.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    final player = context.watch<PlayerController>();
    final settingsCtl = context.watch<SettingsController>();
    final s = settingsCtl.settings;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget switchRow(String label, bool value, ValueChanged<bool> onChanged, {String? subtitle}) => SwitchListTile(
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: value,
      onChanged: onChanged,
    );

    Widget segmented(List<(String, String)> options, String value, ValueChanged<String> onChanged) => SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [for (final (v, label) in options) ButtonSegment(value: v, label: Text(label))],
      selected: {value},
      onSelectionChanged: (set) => onChanged(set.first),
    );

    Widget labelled(String label, Widget control, {String? subtitle}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodyLarge),
          if (subtitle != null) Text(subtitle, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          control,
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
            children: [
              SectionCard(
                title: 'Library',
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('All data is kept on your device', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                          decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 18, color: scheme.onTertiaryContainer.withValues(alpha: 0.7)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Tracks inside app storage', style: text.bodyMedium?.copyWith(color: scheme.onTertiaryContainer)),
                                    Text(plural(lib.tracks.length, 'track'), style: text.bodySmall?.copyWith(color: scheme.onTertiaryContainer)),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove all tracks',
                                icon: Icon(Icons.delete_outline_rounded, color: scheme.onTertiaryContainer),
                                onPressed: lib.tracks.isEmpty
                                    ? null
                                    : () async {
                                        final ok = await confirmDialog(
                                          context,
                                          title: 'Remove all tracks?',
                                          body: 'Every imported track and its cover art will be removed from this device. Playlists keep their names.',
                                          confirmLabel: 'Remove all',
                                        );
                                        if (ok) {
                                          await lib.clearLibrary();
                                          if (context.mounted) showSnack(context, 'Library cleared');
                                        }
                                      },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Import tracks'),
                          onPressed: () => importTracksFlow(context, pickAudioFiles),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SectionCard(
                title: 'Appearance',
                children: [
                  labelled('Application theme', segmented(const [('auto', 'Auto'), ('dark', 'Dark'), ('light', 'Light')], s.theme, (v) => settingsCtl.update(s.copyWith(theme: v)))),
                  switchRow('Automatically pick color from currently playing song artwork', s.pickColorFromArtwork, (v) {
                    settingsCtl.update(s.copyWith(pickColorFromArtwork: v));
                    if (!v) settingsCtl.clearArtworkAccent();
                  }),
                  ListTile(
                    title: const Text('Application primary color'),
                    trailing: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (s.accent.isNotEmpty) OutlinedButton(onPressed: () => settingsCtl.update(s.copyWith(accent: '')), child: const Text('Reset')),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.colorize_rounded, size: 18),
                          label: const Text('Pick color'),
                          onPressed: () async {
                            final c = await pickAccentColor(context, current: parseHex(s.accent));
                            if (c != null) await settingsCtl.setAccent(c);
                          },
                        ),
                      ],
                    ),
                  ),
                  labelled('Motion', segmented(const [('auto', 'Auto'), ('reduced', 'Reduced'), ('full', 'Full')], s.motion, (v) => settingsCtl.update(s.copyWith(motion: v)))),
                  if (isIos)
                    switchRow(
                      'Liquid Glass',
                      s.glass != 'off',
                      (v) => settingsCtl.update(s.copyWith(glass: v ? 'auto' : 'off')),
                      subtitle: 'Glass player and tab bar on iOS 26 and later. Frosted on older iOS.',
                    ),
                ],
              ),
              const SizedBox(height: 24),
              SectionCard(
                title: 'Player',
                children: [
                  switchRow('Display volume slider inside player', s.volumeInPlayer, (v) => settingsCtl.update(s.copyWith(volumeInPlayer: v))),
                  ListTile(
                    title: const Text('Equalizer'),
                    trailing: FilledButton.tonal(onPressed: () => showEqualizerSheet(context), child: const Text('Open equalizer')),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        const Expanded(child: Text('Playback speed')),
                        Text('${player.speed}x', style: text.labelLarge),
                        SizedBox(width: 160, child: Slider(min: 0.5, max: 2, divisions: 30, value: player.speed.clamp(0.5, 2.0), onChanged: player.setSpeed)),
                        OutlinedButton(onPressed: player.speed == 1 ? null : () => player.setSpeed(1), child: const Text('Reset')),
                      ],
                    ),
                  ),
                  switchRow(
                    'Preserve pitch',
                    s.preservePitch,
                    (v) async {
                      await settingsCtl.update(s.copyWith(preservePitch: v));
                      await player.applyPlaybackSettings();
                    },
                    subtitle: Platform.isIOS ? 'iOS always preserves pitch.' : null,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SectionCard(
                title: 'Discovery',
                children: [
                  labelled(
                    'Discovery source',
                    segmented(const [('youtube', 'YouTube'), ('itunes', 'Apple previews')], s.discoverySource, (v) => settingsCtl.update(s.copyWith(discoverySource: v))),
                    subtitle: 'YouTube plays full tracks. Apple plays 30-second previews.',
                  ),
                  ListTile(
                    title: const Text('Server URL'),
                    subtitle: Text(
                      settingsCtl.serverUrl.isEmpty ? 'Not set. YouTube needs an Adi Music server that holds the API key.' : settingsCtl.serverUrl,
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _editServer(context, settingsCtl),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SectionCard(
                title: 'Export & Import',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Backup your playlists and settings to a single file, or restore them from an existing backup.', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonal(onPressed: () => _export(context, lib, settingsCtl), child: const Text('Export Backup')),
                            FilledButton.tonal(onPressed: () => _import(context, lib, settingsCtl), child: const Text('Import Backup')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SectionCard(
                title: 'About',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text.rich(
                      TextSpan(
                        style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        children: [
                          const TextSpan(text: 'Adi Music is a free, open-source music player. Your files and playlists stay on this device. '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: GestureDetector(
                              onTap: () => launchUrl(Uri.parse(AppConfig.sourceUrl), mode: LaunchMode.externalApplication),
                              child: Text('Source code', style: text.bodyMedium?.copyWith(color: scheme.primary, decoration: TextDecoration.underline)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editServer(BuildContext context, SettingsController ctl) async {
    final controller = TextEditingController(text: ctl.settings.serverUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server URL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('The address of your Adi Music server. It adds the YouTube API key so the key never ships in the app.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(hintText: 'https://music.example.com'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (result != null) await ctl.update(ctl.settings.copyWith(serverUrl: result));
  }

  Future<void> _export(BuildContext context, LibraryController lib, SettingsController ctl) async {
    final dir = await getTemporaryDirectory();
    final name = 'adimusic-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json';
    final file = File('${dir.path}/$name');
    await file.writeAsString(lib.exportBackup(ctl.settings));
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/json')], subject: name));
  }

  Future<void> _import(BuildContext context, LibraryController lib, SettingsController ctl) async {
    final raw = await pickBackupFile();
    if (raw == null || !context.mounted) return;
    final restored = lib.importBackup(raw);
    if (restored == null) {
      showSnack(context, 'That file is not a valid backup');
      return;
    }
    // Keep this device's server URL: a web backup does not carry one.
    await ctl.update(restored.copyWith(serverUrl: restored.serverUrl.isEmpty ? ctl.settings.serverUrl : null));
    if (context.mounted) showSnack(context, 'Backup restored');
  }
}
