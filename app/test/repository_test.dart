import 'package:flutter_test/flutter_test.dart';
import 'package:vtc_app/data/fake_ride_repository.dart';
import 'package:vtc_app/data/models.dart';
import 'package:vtc_app/data/pricing.dart';
import 'package:vtc_app/services/map_service.dart';

const a = Place(label: 'A', lat: 5.356, lng: -3.989);
const b = Place(label: 'B', lat: 5.40, lng: -3.95);

Future<RideRequest> req(FakeRideRepository r, {int price = 3000}) =>
    r.createRideRequest(pickup: a, dropoff: b, category: Category.course, distanceM: 8000, durationS: 900, price: price);

void main() {
  late DateTime clock;
  late FakeRideRepository repo;
  setUp(() {
    clock = DateTime(2026, 11, 2, 12);
    repo = FakeRideRepository(simulate: false, now: () => clock);
  });
  tearDown(() => repo.dispose());

  test('prix recommandé identique à la formule SQL (8 km, Course = 2500)', () {
    expect(recommendedPrice(const ZoneConfig(), 8000, Category.course), 2500);
    expect(recommendedPrice(const ZoneConfig(), 8000, Category.confort), 3000);
  });

  test('une seule demande ouverte, prix minimum', () async {
    await req(repo);
    expect(() => req(repo), throwsA(isA<RideException>().having((e) => e.code, 'code', 'request_already_open')));
  });

  test('prix trop bas refusé', () {
    expect(() => req(repo, price: 10), throwsA(isA<RideException>().having((e) => e.code, 'code', 'price_too_low')));
  });

  test('contre-offre : hors bande refusée, dans la bande acceptée', () async {
    final r = await req(repo);
    repo.currentUserId = FakeRideRepository.driverId;
    await repo.setDriverOnline(true);
    expect(() => repo.submitOffer(requestId: r.id, price: 99999, etaSeconds: 120),
        throwsA(isA<RideException>().having((e) => e.code, 'code', 'price_out_of_band')));
    expect(() => repo.submitOffer(requestId: r.id, price: 2000, etaSeconds: 120),
        throwsA(isA<RideException>().having((e) => e.code, 'code', 'price_out_of_band')));
    final o = await repo.submitOffer(requestId: r.id, price: 3300, etaSeconds: 120);
    expect(o.kind, OfferKind.counter);
  });

  test('choix : une seule course, second choix refusé', () async {
    final r = await req(repo);
    repo.currentUserId = FakeRideRepository.driverId;
    await repo.setDriverOnline(true);
    final o = await repo.submitOffer(requestId: r.id, price: 3300, etaSeconds: 120);
    repo.currentUserId = FakeRideRepository.riderId;
    final ride = await repo.chooseOffer(o.id);
    expect(ride.agreedPrice, 3300);
    expect(ride.commission, 330);
    expect(() => repo.chooseOffer(o.id), throwsA(isA<RideException>().having((e) => e.code, 'code', 'offer_not_available')));
  });

  test('« Je suis là » débite une seule fois ; annulation passager avant « je viens » rembourse en attente', () async {
    final r = await req(repo);
    repo.currentUserId = FakeRideRepository.driverId;
    await repo.setDriverOnline(true);
    final o = await repo.submitOffer(requestId: r.id, price: 3300, etaSeconds: 120);
    repo.currentUserId = FakeRideRepository.riderId;
    final ride = await repo.chooseOffer(o.id);
    repo.currentUserId = FakeRideRepository.driverId;
    expect(await repo.watchBalance().first, 5000);
    await repo.driverArrived(ride.id);
    expect(() => repo.driverArrived(ride.id), throwsA(isA<RideException>()));
    expect(await repo.watchBalance().first, 4670);
    repo.currentUserId = FakeRideRepository.riderId;
    await repo.cancelRide(ride.id, 'changed_mind');
    repo.currentUserId = FakeRideRepository.driverId;
    expect(await repo.watchBalance().first, 4670, reason: 'remboursement encore en attente');
    clock = clock.add(const Duration(hours: 73));
    expect(await repo.watchBalance().first, 5000);
    final kinds = (await repo.walletEntries()).map((w) => w.kind).toList();
    expect(kinds.where((k) => k == WalletKind.commission).length, 1);
    expect(kinds.where((k) => k == WalletKind.refund).length, 1);
  });

  test('annulation passager après « je viens » : pas de remboursement', () async {
    final r = await req(repo);
    repo.currentUserId = FakeRideRepository.driverId;
    await repo.setDriverOnline(true);
    final o = await repo.submitOffer(requestId: r.id, price: 3000, etaSeconds: 120);
    repo.currentUserId = FakeRideRepository.riderId;
    final ride = await repo.chooseOffer(o.id);
    await repo.passengerOnWay(ride.id);
    repo.currentUserId = FakeRideRepository.driverId;
    await repo.driverArrived(ride.id);
    repo.currentUserId = FakeRideRepository.riderId;
    await repo.cancelRide(ride.id, 'changed_mind');
    clock = clock.add(const Duration(days: 5));
    repo.currentUserId = FakeRideRepository.driverId;
    expect(await repo.watchBalance().first, 4700);
  });

  test('augmenter le prix invalide les acceptations à l\'ancien prix', () async {
    final r = await req(repo);
    repo.currentUserId = FakeRideRepository.driverId;
    await repo.setDriverOnline(true);
    final o = await repo.submitOffer(requestId: r.id, price: 3000, etaSeconds: 120);
    repo.currentUserId = FakeRideRepository.riderId;
    await repo.raiseRequestPrice(r.id);
    expect(r.offeredPrice, 3100);
    expect(o.status, OfferStatus.expired);
  });

  test('expiration de la demande', () async {
    final r = await req(repo);
    clock = clock.add(const Duration(seconds: 61));
    expect((await repo.watchRequest(r.id).first).status, RequestStatus.expired);
    await req(repo); // une nouvelle demande est de nouveau possible
  });

  test('acceptation automatique : le premier chauffeur au prix devient la course', () async {
    final r = await repo.createRideRequest(
        pickup: a, dropoff: b, category: Category.course, distanceM: 8000, durationS: 900, price: 3000, autoAccept: true);
    repo.currentUserId = FakeRideRepository.driverId;
    await repo.setDriverOnline(true);
    await repo.submitOffer(requestId: r.id, price: 3000, etaSeconds: 120);
    expect(r.status, RequestStatus.matched);
    expect(await repo.watchDriverRide().first, isNotNull);
  });

  test('FakeMapService : Bonoua trouvé sans accent, itinéraire plausible', () async {
    final m = FakeMapService();
    expect((await m.suggest('bonoua')).single.label, 'Bonoua');
    expect((await m.suggest('angre')).single.label, "CHU d'Angré");
    final route = await m.route(FakeMapService.places[0], FakeMapService.places[1]);
    expect(route.distanceM / 1000, inInclusiveRange(50, 65));
  });
}
