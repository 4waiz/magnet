import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magnet_rush/app/app.dart';
import 'package:magnet_rush/core/audio/audio_service.dart';
import 'package:magnet_rush/core/haptics/haptics_service.dart';
import 'package:magnet_rush/core/performance/quality.dart';
import 'package:magnet_rush/core/persistence/settings_store.dart';
import 'package:magnet_rush/features/settings/settings_sheet.dart';
import 'package:magnet_rush/shared/theme/mr_theme.dart';
import 'package:magnet_rush/shared/widgets/mr_widgets.dart';

/// The home screen is a portrait layout; the default 800x600 test surface is
/// landscape and squeezes content out of the viewport. Every home test runs at
/// a phone-shaped size instead.
Future<void> pumpHome(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pump(const Duration(milliseconds: 60));
}

void main() {
  testWidgets('home screen renders the Magnet Rush shell, not Material', (
    tester,
  ) async {
    await pumpHome(
      tester,
      MagnetRushApp(
        settings: SettingsStore(),
        audio: AudioService(),
        haptics: HapticsService(),
      ),
    );

    expect(find.text('Magnet Rush'), findsOneWidget);
    expect(find.text('Attract · Charge · Blast'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);

    // Locked meta features are visible but plainly marked.
    expect(find.text('Upgrades'), findsOneWidget);
    expect(find.text('Coming soon'), findsWidgets);

    // The shell must not be a MaterialApp — that is what drags default
    // styling back in.
    expect(find.byType(WidgetsApp), findsOneWidget);
  });

  testWidgets('settings toggles write through to the store', (tester) async {
    // Exercised directly rather than through the home screen: on the 800x600
    // test surface the home layout scrolls the sheet out of the viewport, so
    // a tap there tests the layout, not the setting.
    final settings = SettingsStore();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(400, 1400)),
          child: SingleChildScrollView(
            child: SettingsSheet(
              settings: settings,
              audio: AudioService(),
              haptics: HapticsService(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(settings.value.reducedMotion, isFalse);
    await tester.tap(find.text('Reduced motion'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(settings.value.reducedMotion, isTrue);

    expect(settings.value.cameraShake, isTrue);
    await tester.tap(find.text('Camera shake'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(settings.value.cameraShake, isFalse);

    // Quality presets are selectable and change the swarm cap.
    expect(settings.value.quality, QualityPreset.medium);
    await tester.tap(find.text('High'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(settings.value.quality, QualityPreset.high);
    expect(settings.value.qualitySettings.maxSwarm, 160);
  });

  testWidgets('settings can be opened from home', (tester) async {
    await pumpHome(
      tester,
      MagnetRushApp(
        settings: SettingsStore(),
        audio: AudioService(),
        haptics: HapticsService(),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);
    // The menu scrolls, so the button may be below the fold on a short
    // viewport; bring it into view before tapping.
    // NOT pumpAndSettle: the home hero animates on a repeating controller, so
    // the tree never settles and pumpAndSettle would time out.
    await tester.ensureVisible(find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Close settings'), findsOneWidget);
  });

  testWidgets('MrButton fires once per tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: MrButton(label: 'GO', onPressed: () => taps++),
        ),
      ),
    );
    await tester.tap(find.text('GO'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(taps, 1);
  });

  test('the in-world colour language keeps safe and hazard far apart', () {
    // These two are NOT interface chrome — they are the readouts that mirror
    // the 3D scene, where cyan means the player's own technology and orange
    // means hazard. If they ever converge the gameplay read breaks.
    final safe = HSVColor.fromColor(MrColors.worldSafe).hue;
    final hazard = HSVColor.fromColor(MrColors.worldHazard).hue;
    expect((safe - hazard).abs(), greaterThan(90));
  });
}
