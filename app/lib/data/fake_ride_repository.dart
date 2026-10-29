import 'dart:async';
import 'dart:math' as math;

import 'models.dart';
import 'pricing.dart';
import 'ride_repository.dart';

/// Version hors ligne : applique les mêmes règles que replica/schema.sql (une demande ouverte par passager,
/// prix minimum, bande de contre-offre, choix atomique, commission au « Je suis là », remboursement)
/// et simule des chauffeurs et des passagers pour pouvoir jouer la boucle sans serveur.
class FakeRideRepository implements RideRepository {
  FakeRideRepository({
    this.zone = const ZoneConfig(),
    this.simulate = true,
    this.timeScale = 1.0,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _wallet.add(WalletEntry(id: _id('w'), kind: WalletKind.topup, amount: 5000, createdAt: _now()));
  }

  static const riderId = 'rider-1';
  static const driverId = 'driver-1';

  final ZoneConfig zone;
  final bool simulate;
  final double timeScale; // < 1 accélère la simulation (tests)
  final DateTime Function() _now;

  @override
  String currentUserId = riderId;

  final _rng = math.Random(7);
  var _seq = 0;
  String _id(String p) => '$p-${++_seq}';

  final _requests = <String, RideRequest>{};
  final _offers = <String, Offer>{};
  final _rides = <String, Ride>{};
  final _wallet = <WalletEntry>[];
  final _ratings = <String, int>{};
  bool _driverOnline = false;
  final _timers = <Timer>[];

  final _changes = StreamController<void>.broadcast();
  void _notify() => _changes.add(null);

  Duration _d(int ms) => Duration(milliseconds: (ms * timeScale).round());
  void _later(int ms, void Function() f) => _timers.add(Timer(_d(ms), f));

  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _changes.close();
  }

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  // ---------------------------------------------------------------- passager

  @override
  Future<RideRequest> createRideRequest({
    required Place pickup,
    required Place dropoff,
    required Category category,
    required int distanceM,
    required int durationS,
    required int price,
    bool autoAccept = false,
    Map<String, bool> options = const {},
    String? note,
  }) async {
    _expireDue();
    if (_requests.values.any((r) => r.riderId == currentUserId && r.status == RequestStatus.open)) {
      throw const RideException('request_already_open');
    }
    if (_rides.values.any((r) => r.request.riderId == currentUserId && r.isActive)) {
      throw const RideException('ride_already_active');
    }
    final rec = recommendedPrice(zone, distanceM, category);
    if (price < minimumOffer(zone, rec)) throw const RideException('price_too_low');
    final req = RideRequest(
      id: _id('req'),
      riderId: currentUserId,
      pickup: pickup,
      dropoff: dropoff,
      category: category,
      distanceM: distanceM,
      durationS: durationS,
      recommendedPrice: rec,
      offeredPrice: price,
      expiresAt: _now().add(zone.requestTtl),
      autoAccept: autoAccept,
      options: options,
      note: note,
    );
    _requests[req.id] = req;
    _notify();
    if (simulate && currentUserId == riderId) _scheduleBotOffers(req);
    return req;
  }

  @override
  Future<RideRequest> raiseRequestPrice(String requestId) async {
    final r = _openRequest(requestId, owner: true);
    r.offeredPrice += zone.raiseStep;
    r.priceRaiseCount++;
    final floor = _now().add(const Duration(seconds: 30));
    if (r.expiresAt.isBefore(floor)) r.expiresAt = floor;
    // les acceptations à l'ancien prix ne valent plus
    for (final o in _offers.values.where((o) => o.requestId == r.id && o.status == OfferStatus.pending && o.kind == OfferKind.accept && o.price < r.offeredPrice)) {
      o.status = OfferStatus.expired;
    }
    _notify();
    return r;
  }

  @override
  Future<void> cancelRequest(String requestId, String reason) async {
    final r = _openRequest(requestId, owner: true);
    r.status = RequestStatus.cancelled;
    r.cancelReason = reason;
    for (final o in _offers.values.where((o) => o.requestId == r.id && o.status == OfferStatus.pending)) {
      o.status = OfferStatus.expired;
    }
    _notify();
  }

  @override
  Stream<RideRequest> watchRequest(String requestId) => _watch(() {
        _expireDue();
        return _requests[requestId]!;
      });

  @override
  Stream<List<Offer>> watchOffers(String requestId) => _watch(() {
        _expireDue();
        final list = _offers.values.where((o) => o.requestId == requestId && o.status == OfferStatus.pending).toList()
          ..sort((a, b) => a.price != b.price ? a.price.compareTo(b.price) : a.etaSeconds.compareTo(b.etaSeconds));
        return list;
      });

  @override
  Future<Ride> chooseOffer(String offerId) async {
    _expireDue();
    final o = _offers[offerId];
    if (o == null) throw const RideException('offer_not_found');
    final req = _requests[o.requestId]!;
    if (req.riderId != currentUserId) throw const RideException('forbidden');
    if (req.status != RequestStatus.open || o.status != OfferStatus.pending) throw const RideException('offer_not_available');
    if (_rides.values.any((r) => r.isActive && r.driverId == o.driverId)) throw const RideException('driver_busy');
    final ride = Ride(
      id: _id('ride'),
      request: req,
      driverId: o.driverId,
      driverName: o.driverName,
      vehicle: o.vehicle,
      plate: o.plate,
      agreedPrice: o.price,
      commission: commissionFor(zone, o.price),
      createdAt: _now(),
    );
    _rides[ride.id] = ride;
    req.status = RequestStatus.matched;
    for (final x in _offers.values.where((x) => x.requestId == req.id && x.status == OfferStatus.pending)) {
      x.status = x.id == o.id ? OfferStatus.chosen : OfferStatus.rejected;
    }
    _notify();
    if (simulate && o.driverId != driverId) _scheduleBotRide(ride);
    return ride;
  }

  @override
  Future<void> rejectOffer(String offerId) async {
    final o = _offers[offerId];
    if (o == null || _requests[o.requestId]!.riderId != currentUserId) throw const RideException('forbidden');
    if (o.status == OfferStatus.pending) o.status = OfferStatus.rejected;
    _notify();
  }

  @override
  Future<Ride?> activeRide() async =>
      _rides.values.where((r) => r.request.riderId == currentUserId && r.isActive).firstOrNull;

  @override
  Stream<Ride> watchRide(String rideId) => _watch(() => _rides[rideId]!);

  @override
  Future<void> passengerOnWay(String rideId) async {
    final r = _rides[rideId]!;
    if (r.request.riderId != currentUserId) throw const RideException('forbidden');
    r.passengerOnWay = true;
    _notify();
  }

  @override
  Future<Ride> cancelRide(String rideId, String reason) async {
    final r = _rides[rideId];
    if (r == null || (r.request.riderId != currentUserId && r.driverId != currentUserId)) throw const RideException('forbidden');
    if (r.status != RideStatus.toPickup && r.status != RideStatus.arrived) throw const RideException('ride_not_cancellable');
    final by = r.request.riderId == currentUserId ? 'rider' : 'driver';
    r.status = RideStatus.cancelled;
    r.cancelledBy = by;
    r.cancelReason = reason;
    final refund = (by == 'rider' && !r.passengerOnWay) || (by == 'driver' && reason == 'passenger_no_show');
    if (refund) _refundCommission(r);
    _notify();
    return r;
  }

  @override
  Future<void> rateRide(String rideId, int stars, {String? comment}) async {
    final r = _rides[rideId];
    if (r == null || r.status != RideStatus.completed) throw const RideException('ride_not_completed');
    if (stars < 1 || stars > 5) throw const RideException('invalid_stars');
    _ratings['$rideId:$currentUserId'] = stars;
    _notify();
  }

  int? ratingGiven(String rideId) => _ratings['$rideId:$currentUserId'];

  @override
  Future<List<Ride>> history() async {
    final list = _rides.values.where((r) => r.request.riderId == currentUserId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  // ---------------------------------------------------------------- chauffeur

  @override
  Future<void> setDriverOnline(bool online) async {
    if (online && _balance() < 0) throw const RideException('balance_too_low');
    _driverOnline = online;
    _notify();
    if (online && simulate) _scheduleBotRequests();
  }

  @override
  Future<List<OpenRequest>> nearbyOpenRequests() async {
    _expireDue();
    if (!_driverOnline) return const [];
    final list = _requests.values.where((r) => r.status == RequestStatus.open && r.riderId != driverId).map((r) {
      return OpenRequest(
        request: r,
        riderName: r.riderId == riderId ? 'Passager' : _botRiderName(r.riderId),
        riderRating: r.riderId == riderId ? 4.96 : 4.7,
        pickupDistanceM: 400 + (r.id.hashCode.abs() % 2200),
      );
    }).toList()
      ..sort((a, b) => a.pickupDistanceM.compareTo(b.pickupDistanceM));
    return list;
  }

  @override
  Future<Offer> submitOffer({required String requestId, required int price, required int etaSeconds}) async {
    _expireDue();
    if (!_driverOnline) throw const RideException('driver_not_ready');
    if (_balance() < 0) throw const RideException('balance_too_low');
    final r = _openRequest(requestId, owner: false);
    final high = r.offeredPrice * (100 + zone.counterBandPct) ~/ 100;
    if (price < r.offeredPrice || price > high) throw const RideException('price_out_of_band');
    final kind = price == r.offeredPrice ? OfferKind.accept : OfferKind.counter;
    final existing = _offers.values.where((o) => o.requestId == requestId && o.driverId == currentUserId).firstOrNull;
    final offer = existing ??
        Offer(
          id: _id('offer'),
          requestId: requestId,
          driverId: currentUserId,
          driverName: 'Vous',
          rating: 4.9,
          completedRides: 120,
          vehicle: 'Suzuki Dzire',
          plate: 'AB 123 CD',
          price: price,
          etaSeconds: etaSeconds,
          kind: kind,
          expiresAt: r.expiresAt,
        );
    offer
      ..price = price
      ..etaSeconds = etaSeconds
      ..kind = kind
      ..expiresAt = r.expiresAt
      ..status = OfferStatus.pending;
    _offers[offer.id] = offer;
    _notify();
    if (r.autoAccept && kind == OfferKind.accept) {
      final saved = currentUserId;
      currentUserId = r.riderId;
      try {
        await chooseOffer(offer.id);
      } finally {
        currentUserId = saved;
      }
    }
    return offer;
  }

  @override
  Future<void> withdrawOffer(String offerId) async {
    final o = _offers[offerId];
    if (o != null && o.driverId == currentUserId && o.status == OfferStatus.pending) o.status = OfferStatus.withdrawn;
    _notify();
  }

  @override
  Stream<Ride?> watchDriverRide() => _watch(() => _rides.values.where((r) => r.driverId == currentUserId && r.isActive).firstOrNull);

  @override
  Future<Ride> driverArrived(String rideId) async {
    final r = _driverRide(rideId, RideStatus.toPickup, 'ride_not_in_pickup');
    r.status = RideStatus.arrived;
    _chargeCommission(r);
    _notify();
    return r;
  }

  @override
  Future<Ride> startRide(String rideId) async {
    final r = _driverRide(rideId, RideStatus.arrived, 'ride_not_arrived');
    r.status = RideStatus.inProgress;
    _notify();
    return r;
  }

  @override
  Future<Ride> completeRide(String rideId, {int? finalPrice}) async {
    final r = _driverRide(rideId, RideStatus.inProgress, 'ride_not_in_progress');
    r.status = RideStatus.completed;
    r.finalPrice = finalPrice ?? r.agreedPrice;
    _notify();
    return r;
  }

  @override
  Stream<int> watchBalance() => _watch(_balance);

  @override
  Future<List<WalletEntry>> walletEntries() async {
    _settleRefunds();
    return List.of(_wallet.reversed);
  }

  // ---------------------------------------------------------------- interne

  int _balance() {
    _settleRefunds();
    return _wallet.where((w) => !w.pending).fold(0, (s, w) => s + w.amount);
  }

  void _chargeCommission(Ride r) {
    if (r.driverId != driverId || r.commission == 0) return;
    if (_wallet.any((w) => w.rideId == r.id && w.kind == WalletKind.commission)) return; // idempotent
    _wallet.add(WalletEntry(id: _id('w'), kind: WalletKind.commission, amount: -r.commission, createdAt: _now(), rideId: r.id));
  }

  void _refundCommission(Ride r) {
    if (!_wallet.any((w) => w.rideId == r.id && w.kind == WalletKind.commission)) return;
    if (_wallet.any((w) => w.rideId == r.id && w.kind == WalletKind.refund)) return;
    _wallet.add(WalletEntry(id: _id('w'), kind: WalletKind.refund, amount: r.commission, createdAt: _now().add(refundDelay), pending: true, rideId: r.id));
  }

  /// Délai de remboursement (app_settings.refund_delay_hours = 72 par défaut).
  Duration refundDelay = const Duration(hours: 72);

  void _settleRefunds() {
    for (var i = 0; i < _wallet.length; i++) {
      final w = _wallet[i];
      if (w.pending && !w.createdAt.isAfter(_now())) {
        _wallet[i] = WalletEntry(id: w.id, kind: w.kind, amount: w.amount, createdAt: w.createdAt, rideId: w.rideId);
      }
    }
  }

  RideRequest _openRequest(String id, {required bool owner}) {
    _expireDue();
    final r = _requests[id];
    if (r == null || r.status != RequestStatus.open) throw const RideException('request_not_open');
    if (owner && r.riderId != currentUserId) throw const RideException('request_not_open');
    return r;
  }

  Ride _driverRide(String id, RideStatus expected, String code) {
    final r = _rides[id];
    if (r == null || r.driverId != currentUserId || r.status != expected) throw RideException(code);
    return r;
  }

  void _expireDue() {
    final t = _now();
    for (final r in _requests.values) {
      if (r.status == RequestStatus.open && r.expiresAt.isBefore(t)) {
        r.status = RequestStatus.expired;
        for (final o in _offers.values.where((o) => o.requestId == r.id && o.status == OfferStatus.pending)) {
          o.status = OfferStatus.expired;
        }
      }
    }
  }

  // ---------------------------------------------------------------- simulation

  static const _botDrivers = [
    ('bot-1', 'Marcel', 4.87, 3477, 'Suzuki S-Presso', 'BN 482 AA'),
    ('bot-2', 'Aimé', 4.77, 234, 'Suzuki Dzire', 'BN 118 BB'),
    ('bot-3', 'Ange', 4.92, 61, 'Toyota Yaris', 'BN 907 CC'),
  ];

  void _scheduleBotOffers(RideRequest req) {
    const delays = [2500, 6000, 11000];
    for (var i = 0; i < _botDrivers.length; i++) {
      final b = _botDrivers[i];
      _later(delays[i], () {
        if (req.status != RequestStatus.open) return;
        final counter = i == 1 || (i == 2 && _rng.nextBool());
        final price = counter ? _roundStep(req.offeredPrice * 1.1) : req.offeredPrice;
        final o = Offer(
          id: _id('offer'),
          requestId: req.id,
          driverId: b.$1,
          driverName: b.$2,
          rating: b.$3,
          completedRides: b.$4,
          vehicle: b.$5,
          plate: b.$6,
          price: price,
          etaSeconds: (3 + i * 2) * 60,
          kind: price == req.offeredPrice ? OfferKind.accept : OfferKind.counter,
          expiresAt: req.expiresAt,
        );
        _offers[o.id] = o;
        _notify();
        if (req.autoAccept && o.kind == OfferKind.accept) {
          final saved = currentUserId;
          currentUserId = req.riderId;
          chooseOffer(o.id).whenComplete(() => currentUserId = saved);
        }
      });
    }
  }

  int _roundStep(double v) => (v / zone.priceStep).round() * zone.priceStep;

  void _scheduleBotRide(Ride ride) {
    _later(6000, () {
      if (ride.status == RideStatus.toPickup) {
        ride.status = RideStatus.arrived;
        _notify();
      }
    });
    _later(12000, () {
      if (ride.status == RideStatus.arrived) {
        ride.status = RideStatus.inProgress;
        _notify();
      }
    });
    _later(22000, () {
      if (ride.status == RideStatus.inProgress) {
        ride.status = RideStatus.completed;
        ride.finalPrice = ride.agreedPrice;
        _notify();
      }
    });
  }

  String _botRiderName(String id) => id == 'bot-rider-1' ? 'Awa' : 'Koffi';

  void _scheduleBotRequests() {
    final seeds = [
      ('bot-rider-1', FakeMapSeeds.a, FakeMapSeeds.b, 3800),
      ('bot-rider-2', FakeMapSeeds.c, FakeMapSeeds.d, 2600),
    ];
    for (var i = 0; i < seeds.length; i++) {
      _later(1500 + i * 4000, () {
        if (!_driverOnline) return;
        final s = seeds[i];
        if (_requests.values.any((r) => r.riderId == s.$1 && r.status == RequestStatus.open)) return;
        final dist = 6000 + i * 4000;
        final rec = recommendedPrice(zone, dist, Category.course);
        final req = RideRequest(
          id: _id('req'),
          riderId: s.$1,
          pickup: s.$2,
          dropoff: s.$3,
          category: Category.course,
          distanceM: dist,
          durationS: dist * 2,
          recommendedPrice: rec,
          offeredPrice: s.$4,
          expiresAt: _now().add(const Duration(minutes: 3)),
        );
        _requests[req.id] = req;
        _notify();
      });
    }
  }
}

/// Lieux utilisés par la simulation de passagers.
class FakeMapSeeds {
  static const a = Place(label: 'Plateau', lat: 5.3240, lng: -4.0220);
  static const b = Place(label: 'Marcory', lat: 5.3030, lng: -3.9830);
  static const c = Place(label: 'Yopougon', lat: 5.3360, lng: -4.0870);
  static const d = Place(label: 'Treichville', lat: 5.2930, lng: -4.0050);
}
