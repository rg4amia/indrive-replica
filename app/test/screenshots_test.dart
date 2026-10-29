// Génère replica/clone-screens/*.png avec la vraie police Roboto du SDK Flutter.
// Lancer : SHOTS=1 flutter test --update-goldens test/screenshots_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vtc_app/core/app_config.dart';
import 'package:vtc_app/data/fake_ride_repository.dart';
import 'package:vtc_app/main.dart';
import 'package:vtc_app/modules/app_controller.dart';
import 'package:vtc_app/modules/driver_controller.dart';
import 'package:vtc_app/modules/rider_controller.dart';
import 'package:vtc_app/services/map_service.dart';

Future<void> _loadFonts() async {
  final sdk = File(Platform.resolvedExecutable).parent.parent.parent; // .../bin/cache/dart-sdk/bin/dart -> flutter/
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? sdk.parent.parent.path}/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String f) async => ByteData.view(File('$dir/$f').readAsBytesSync().buffer);
  final roboto = FontLoader('Roboto')
    ..addFont(read('Roboto-Regular.ttf'))
    ..addFont(read('Roboto-Medium.ttf'))
    ..addFont(read('Roboto-Bold.ttf'));
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(read('MaterialIcons-Regular.otf'));
  await icons.load();
}

Future<void> _boot(WidgetTester t, {FakeRideRepository? repo}) async {
  AppConfig.tileUrl = null;
  t.view.physicalSize = const Size(390 * 2, 844 * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  Get.reset();
  registerControllers(app: AppController(repo: repo ?? FakeRideRepository()));
  await t.pumpWidget(RepaintBoundary(key: const ValueKey('shot'), child: const VtcApp(skipRegister: true)));
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> _shot(WidgetTester t, String name) =>
    expectLater(find.byKey(const ValueKey('shot')), matchesGoldenFile('../../replica/clone-screens/$name.png'));

Future<void> _end(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  Get.deleteAll(force: true);
  Get.reset();
  await t.pump(const Duration(seconds: 70));
}

void main() {
  // Ne tourne que sur demande : SHOTS=1 flutter test --update-goldens test/screenshots_test.dart
  if (Platform.environment['SHOTS'] != '1') return;
  setUpAll(_loadFonts);

  testWidgets('captures passager', (t) async {
    await _boot(t);
    final c = Get.find<RiderController>();
    await _shot(t, 'S05-accueil');

    await c.setDestination(FakeMapService.places[1]);
    await t.pump(const Duration(milliseconds: 100));
    await _shot(t, 'S07-tarif');

    await c.search();
    await t.pump(const Duration(milliseconds: 200));
    await _shot(t, 'S08a-recherche');

    await t.pump(const Duration(seconds: 7));
    await _shot(t, 'S08b-offres');

    await c.choose(c.offers.first);
    await t.pump(const Duration(milliseconds: 200));
    await _shot(t, 'S09-chauffeur-en-route');

    await t.pump(const Duration(seconds: 25));
    await _shot(t, 'S11-fin-de-course');
    await _end(t);
  });

  testWidgets('captures chauffeur', (t) async {
    await _boot(t);
    Get.find<AppController>().switchMode(AppMode.driver);
    await t.pumpAndSettle();
    await _shot(t, 'S19-chauffeur-hors-ligne');
    await Get.find<DriverController>().toggleOnline(true);
    await t.pump(const Duration(seconds: 4));
    await _shot(t, 'S20-demandes');
    await _end(t);
  });
}
