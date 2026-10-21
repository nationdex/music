/// The equalizer: presets, a live response curve, ten bands, preamp, and custom presets. Same
/// controls as the web build; on Android the ten-band curve is mapped onto the bands the device has.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/eq_math.dart';
import '../../state/player_controller.dart';
import 'common.dart';

Future<void> showEqualizerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => const _EqualizerSheet(),
  );
}

class _EqualizerSheet extends StatefulWidget {
  const _EqualizerSheet();

  @override
  State<_EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends State<_EqualizerSheet> {
  final _name = TextEditingController();
  bool _naming = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save(PlayerController p) async {
    final error = await p.saveEqPreset(_name.text);
    if (!mounted) return;
    if (error != null) {
      showSnack(context, error);
      return;
    }
    setState(() {
      _naming = false;
      _name.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final eq = p.eq;

    Widget header({bool showSwitch = true}) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 12, 8),
      child: Row(
        children: [
          Expanded(child: Text('Equalizer', style: text.titleLarge)),
          if (showSwitch) Switch(value: eq.enabled, onChanged: p.setEqEnabled),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );

    if (!p.eqPlatformSupported || !p.eqSupported) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header(showSwitch: false),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Text(
                p.eqPlatformSupported
                    ? 'This device does not provide an equalizer.'
                    : 'The equalizer is available on Android only. iOS does not let apps process the audio of the system player.',
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final dim = eq.enabled ? 1.0 : 0.5;
    final preamp = p.eqPreamp;

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header(),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  if (eq.preset == 'Custom')
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text('Custom'), selected: true),
                    ),
                  for (final name in [...eqPresets.keys, ...eq.custom.keys])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(name),
                        selected: eq.preset == name,
                        onSelected: (_) => p.applyEqPreset(name),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Opacity(
              opacity: dim,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  height: 96,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CustomPaint(
                      painter: _CurvePainter(
                        gains: eq.enabled ? eq.gains : eqPresets['Flat']!,
                        preamp: eq.enabled ? eq.effectivePreamp : 0,
                        line: scheme.primary,
                        grid: scheme.outlineVariant,
                        label: scheme.onSurfaceVariant,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Opacity(
              opacity: dim,
              child: SizedBox(
                height: 200,
                child: Row(
                  children: [
                    for (var i = 0; i < eqFrequencies.length; i++)
                      Expanded(
                        child: GestureDetector(
                          onDoubleTap: () => p.setEqBand(i, 0),
                          child: Column(
                            children: [
                              Text(
                                '${eq.gains[i] > 0 ? '+' : ''}${eq.gains[i].round()}',
                                style: text.labelSmall,
                              ),
                              Expanded(
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: Slider(
                                    min: -eqRange,
                                    max: eqRange,
                                    divisions: 24,
                                    value: eq.gains[i],
                                    onChanged: (v) => p.setEqBand(i, v),
                                  ),
                                ),
                              ),
                              Text(
                                eqLabels[i].replaceAll('Hz', ''),
                                style: text.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Opacity(
              opacity: dim,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 16, 0),
                child: Row(
                  children: [
                    Text('Preamp', style: text.labelLarge),
                    Expanded(
                      child: Slider(
                        min: -eqRange,
                        max: eqRange,
                        divisions: 48,
                        value: preamp.clamp(-eqRange, eqRange),
                        onChanged: eq.auto ? null : p.setEqPreamp,
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        '${preamp > 0 ? '+' : ''}${preamp.toStringAsFixed(1)} dB',
                        textAlign: TextAlign.right,
                        style: text.labelSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Auto'),
                      selected: eq.auto,
                      onSelected: (_) => p.toggleEqAuto(),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
              child: Text(
                'Applied to the ${p.eqDeviceFrequencies.length} bands your device offers. Auto lowers the volume by the biggest boost so loud presets do not distort.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _naming
                  ? Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _name,
                            autofocus: true,
                            maxLength: 24,
                            decoration: const InputDecoration(
                              labelText: 'Preset name',
                              counterText: '',
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _save(p),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: _name.text.trim().isEmpty
                              ? null
                              : () => _save(p),
                          child: const Text('Save'),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _naming = false),
                          child: const Text('Cancel'),
                        ),
                      ],
                    )
                  : Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: p.resetEq,
                          child: const Text('Reset'),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _naming = true),
                          child: const Text('Save preset'),
                        ),
                        if (eq.custom.containsKey(eq.preset))
                          TextButton(
                            onPressed: p.deleteEqPreset,
                            child: const Text('Delete preset'),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The combined frequency response of the ten bands, from 20 Hz to 20 kHz on a log axis.
class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.gains,
    required this.preamp,
    required this.line,
    required this.grid,
    required this.label,
  });

  final List<double> gains;
  final double preamp;
  final Color line, grid, label;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.8;
    for (final f in [0.25, 0.5, 0.75]) {
      canvas.drawLine(
        Offset(0, size.height * f),
        Offset(size.width, size.height * f),
        gridPaint,
      );
    }
    final dbs = responseDb(gains, logFreqs(), preamp: preamp);
    final path = Path();
    for (var i = 0; i < dbs.length; i++) {
      final x = i / (dbs.length - 1) * size.width;
      final y =
          size.height / 2 -
          dbs[i].clamp(-eqRange, eqRange) / eqRange * size.height / 2;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );
    for (final (text, dy) in [('+12 dB', 4.0), ('-12 dB', size.height - 16)]) {
      (TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: label, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout()).paint(canvas, Offset(8, dy));
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.gains != gains || old.preamp != preamp || old.line != line;
}
