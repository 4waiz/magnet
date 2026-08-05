/// Magnet Rush — ATTRACT. CHARGE. BLAST.
///
/// The normal application entry point. Level 1 is reached through the home
/// screen, not through a developer harness; the renderer regression harness
/// still exists separately at `lib/dev/smoke_test.dart`.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'core/audio/audio_service.dart';
import 'core/haptics/haptics_service.dart';
import 'core/persistence/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final settings = SettingsStore();
  await settings.load();

  final haptics = HapticsService()..enabled = settings.value.hapticsEnabled;
  final audio = AudioService()
    ..sfxVolume = settings.value.soundVolume
    ..musicVolume = settings.value.musicVolume;

  // Neither is required to render a frame, so boot the UI first and let them
  // arrive when they are ready. A failure in either must not block the game.
  unawaited(
    haptics.probe().catchError(
      (Object e) => debugPrint('haptics probe failed: $e'),
    ),
  );
  unawaited(
    audio.load().catchError((Object e) => debugPrint('audio load failed: $e')),
  );

  runApp(MagnetRushApp(settings: settings, audio: audio, haptics: haptics));
}
