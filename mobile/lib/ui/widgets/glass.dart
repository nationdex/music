/// Surfaces for floating chrome (mini player, navigation bar, sheets).
///
/// - iOS 26 and later: real Liquid Glass (refraction, blur, specular edge) via
///   `liquid_glass_renderer`, which runs on Impeller (the default on iOS).
/// - Older iOS: frosted glass (backdrop blur over a translucent tint).
/// - Android and everything else: a solid Material 3 surface, like the web build.
///
/// Turn it off with Settings > Appearance > Liquid Glass.
library;

import 'dart:io';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:provider/provider.dart';

import '../../state/settings_controller.dart';

enum GlassTier { solid, frosted, liquid }

/// Decides the glass tier once at startup.
Future<GlassTier> detectGlassTier() async {
  if (!Platform.isIOS) return GlassTier.solid;
  try {
    final info = await DeviceInfoPlugin().iosInfo;
    final major = int.tryParse(info.systemVersion.split('.').first) ?? 0;
    return major >= 26 ? GlassTier.liquid : GlassTier.frosted;
  } catch (_) {
    return GlassTier.frosted;
  }
}

/// Provides the detected tier to [GlassSurface]s below it.
class GlassScope extends InheritedWidget {
  const GlassScope({super.key, required this.tier, required super.child});

  final GlassTier tier;

  static GlassTier of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassScope>()?.tier ??
      GlassTier.solid;

  @override
  bool updateShouldNotify(GlassScope old) => old.tier != tier;
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 28,
    this.padding,
    this.solidColor,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  /// Fill used when glass is unavailable or turned off. Defaults to `surfaceContainerHigh`.
  final Color? solidColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final off = context.select<SettingsController, bool>(
      (s) => s.settings.glass == 'off',
    );
    final tier = off ? GlassTier.solid : GlassScope.of(context);
    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    switch (tier) {
      case GlassTier.liquid:
        return LiquidGlass.withOwnLayer(
          settings: LiquidGlassSettings(
            thickness: 16,
            blur: 8,
            glassColor: scheme.surfaceContainer.withValues(alpha: 0.28),
            lightIntensity: 0.6,
            saturation: 1.3,
          ),
          shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
          child: content,
        );
      case GlassTier.frosted:
        final radius = BorderRadius.circular(borderRadius);
        return ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainer.withValues(alpha: 0.72),
                borderRadius: radius,
                border: Border.all(
                  color: scheme.onSurface.withValues(alpha: 0.08),
                ),
              ),
              child: content,
            ),
          ),
        );
      case GlassTier.solid:
        return Material(
          color: solidColor ?? scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(borderRadius),
          clipBehavior: Clip.antiAlias,
          child: content,
        );
    }
  }
}
