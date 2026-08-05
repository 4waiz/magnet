/// Application shell.
///
/// Deliberately a [WidgetsApp], not a [MaterialApp]: nothing in Magnet Rush
/// uses Material components, and pulling in the Material theme would only
/// invite default styling back into a game that is meant to look bespoke.
library;

import 'package:flutter/widgets.dart';

import '../core/audio/audio_service.dart';
import '../core/haptics/haptics_service.dart';
import '../core/persistence/settings_store.dart';
import '../features/home/home_screen.dart';
import '../shared/theme/mr_theme.dart';

class MagnetRushApp extends StatelessWidget {
  const MagnetRushApp({
    super.key,
    required this.settings,
    required this.audio,
    required this.haptics,
  });

  final SettingsStore settings;
  final AudioService audio;
  final HapticsService haptics;

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'Magnet Rush',
      debugShowCheckedModeBanner: false,
      color: MrColors.background,
      textStyle: MrType.body,
      pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder builder) =>
          PageRouteBuilder<T>(
            settings: s,
            transitionDuration: const Duration(milliseconds: 280),
            pageBuilder: (context, _, _) => builder(context),
            transitionsBuilder: (_, anim, _, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
      home: HomeScreen(settings: settings, audio: audio, haptics: haptics),
    );
  }
}
