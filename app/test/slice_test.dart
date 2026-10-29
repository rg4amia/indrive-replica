import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vtc_app/core/app_config.dart';
import 'package:vtc_app/data/fake_ride_repository.dart';
import 'package:vtc_app/data/models.dart';
import 'package:vtc_app/services/map_service.dart';
import 'package:vtc_app/main.dart';
import 'package:vtc_app/modules/app_controller.dart';
import 'package:vtc_app/modules/driver_controller.dart';
import 'package:vtc_app/modules/rider_controller.dart';

Future<void> boot(WidgetTester t, {FakeRideRepository? repo}) async {
  AppConfig.tileUrl = null;
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  Get.reset();
  registerControllers(app: AppController(repo: repo ?? FakeRideRepository()));
  await t.pumpWidget(const VtcApp(skipRegister: true));
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> finish(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  Get.deleteAll(force: true);
  Get.reset();
  await t.pump(const Duration(seconds: 70));
}

void main() {
  testWidgets('passager : de la destination à la note, boucle complète', (t) async {
    await boot(t);
    expect(find.text('Où allez-vous, et pour combien ?'), findsOneWidget);

    await t.tap(find.text('Où allez-vous, et pour combien ?'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'bonoua');
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Bonoua').last);
    await t.pumpAndSettle();

    // S07 : tarif recommandé, trois catégories
    expect(find.text('Chercher des offres'), findsOneWidget);
    expect(find.text('Confort'), findsOneWidget);
    final c = Get.find<RiderController>();
    expect(c.price.value, greaterThan(10000));

    await t.tap(find.text('Chercher des offres'));
    await t.pump(const Duration(milliseconds: 100));
    // S08 : en attente, squelette puis offres
    expect(find.textContaining('Nous cherchons'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    expect(find.text('Accepter'), findsOneWidget);
    expect(find.text('Marcel'), findsOneWidget);

    await t.tap(find.text('Accepter'));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Votre chauffeur arrive'), findsOneWidget);

    await t.pump(const Duration(seconds: 7));
    expect(find.text('Votre chauffeur est là'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    expect(find.text('Course en cours'), findsOneWidget);
    await t.pump(const Duration(seconds: 11));
    expect(find.text('Course terminée'), findsOneWidget);

    await t.tap(find.bySemanticsLabel('5 sur 5'));
    await t.pump();
    await t.tap(find.text('Envoyer ma note'));
    await t.pump();
    expect(find.text('Où allez-vous, et pour combien ?'), findsOneWidget);
    await finish(t);
  });

  testWidgets('passager : prix trop bas bloque la recherche', (t) async {
    await boot(t);
    final c = Get.find<RiderController>();
    await t.tap(find.text('Où allez-vous, et pour combien ?'));
    await t.pumpAndSettle();
    await t.tap(find.text('Treichville').last);
    await t.pumpAndSettle();
    c.changePrice(300);
    await t.pump();
    expect(find.textContaining('Trop bas'), findsOneWidget);
    await t.tap(find.text('Chercher des offres'), warnIfMissed: false);
    await t.pump();
    expect(c.request.value, isNull);
    await finish(t);
  });

  testWidgets('passager : aucune offre, la demande expire et propose de relancer', (t) async {
    final repo = FakeRideRepository(simulate: false);
    await boot(t, repo: repo);
    final c = Get.find<RiderController>();
    await c.setDestination(const FakePlace().yopougon);
    await t.pump();
    await c.search();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Nous cherchons'), findsOneWidget);
    c.request.value!.expiresAt = DateTime.now().subtract(const Duration(seconds: 1));
    repo.currentUserId = FakeRideRepository.riderId;
    await repo.nearbyOpenRequests(); // déclenche l'expiration côté dépôt
    await t.pump(const Duration(seconds: 2));
    expect(find.text("Aucune offre pour l'instant"), findsOneWidget);
    expect(find.textContaining('Relancer à'), findsOneWidget);
    await finish(t);
  });

  testWidgets('passager : annulation de la recherche avec motif', (t) async {
    await boot(t, repo: FakeRideRepository(simulate: false));
    final c = Get.find<RiderController>();
    await c.setDestination(const FakePlace().yopougon);
    await t.pump();
    await c.search();
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.text('Annuler la demande'));
    await t.pumpAndSettle();
    expect(find.text('Annuler votre demande ?'), findsOneWidget);
    await t.tap(find.text('Oui, annuler'));
    await t.pumpAndSettle();
    await t.tap(find.text("Aucun chauffeur n'a répondu"));
    await t.pumpAndSettle();
    expect(c.phase.value, RiderPhase.planning);
    expect(find.text('Chercher des offres'), findsOneWidget);
    await finish(t);
  });

  testWidgets('chauffeur : en ligne, demande, offre, choix par le passager, course et commission', (t) async {
    final repo = FakeRideRepository();
    await boot(t, repo: repo);
    final app = Get.find<AppController>();
    app.switchMode(AppMode.driver);
    await t.pumpAndSettle();
    expect(find.text('Vous êtes hors ligne'), findsOneWidget);

    await t.tap(find.text('Passer en ligne'));
    await t.pump(const Duration(seconds: 4)); // demandes simulées à 1,5 s, rafraîchissement toutes les 3 s
    expect(find.textContaining('demande'), findsWidgets);
    expect(find.text('Accepter'), findsWidgets);

    // un passager publie une demande ; le chauffeur la voit au prochain rafraîchissement
    final d = Get.find<DriverController>();
    expect(d.balance.value, 5000);
    await t.tap(find.text('Accepter').first);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Offre envoyée'), findsOneWidget);

    // le passager (simulé) choisit cette offre
    final offer = (await repo.watchOffers(d.sentOffers.first).first).firstWhere((o) => o.driverId == FakeRideRepository.driverId);
    repo.currentUserId = 'bot-rider-1';
    await repo.chooseOffer(offer.id).catchError((_) => throw 'choix refusé');
    repo.currentUserId = FakeRideRepository.driverId;
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('En route vers le passager'), findsOneWidget);

    await t.tap(find.text('Je suis là'));
    await t.pump(const Duration(milliseconds: 100));
    expect(d.balance.value, lessThan(5000), reason: 'la commission est prélevée à « Je suis là »');
    await t.tap(find.text('Démarrer la course'));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.text('Terminer la course'));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Passer en ligne'), findsNothing);
    await finish(t);
  });

  testWidgets('chauffeur : contre-offre hors bande affiche une erreur claire', (t) async {
    final repo = FakeRideRepository(simulate: false);
    await boot(t, repo: repo);
    final d = Get.find<DriverController>();
    final r = Get.find<RiderController>();
    await r.setDestination(const FakePlace().yopougon);
    await r.search();
    Get.find<AppController>().switchMode(AppMode.driver);
    await t.pumpAndSettle();
    await d.toggleOnline(true);
    await t.pump(const Duration(milliseconds: 100));
    final ok = await d.offer(d.requests.first, d.requests.first.request.offeredPrice * 2);
    expect(ok, isFalse);
    expect(d.error.value, contains('30 %'));
    await finish(t);
  });

  testWidgets('menu : accès à l\'historique vide puis plein', (t) async {
    await boot(t, repo: FakeRideRepository(simulate: false));
    await t.tap(find.bySemanticsLabel('Ouvrir le menu'));
    await t.pumpAndSettle();
    expect(find.text('Mon profil'), findsOneWidget);
    await t.tap(find.text('Mes courses'));
    await t.pumpAndSettle();
    expect(find.text('Pas encore de course'), findsOneWidget);
    await finish(t);
  });
}

/// Lieux de test.
class FakePlace {
  const FakePlace();
  Place get yopougon => FakeMapService.places[3];
}
