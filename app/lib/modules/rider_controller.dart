import 'dart:async';

import 'package:get/get.dart';

import '../data/models.dart';
import '../data/pricing.dart';
import '../data/ride_repository.dart';
import '../services/map_service.dart';
import 'app_controller.dart';

enum RiderPhase { browse, planning, searching, ride, rating }

class RiderController extends GetxController {
  RiderController(this.app);
  final AppController app;
  RideRepository get repo => app.repo;
  MapService get map => app.map;
  ZoneConfig zone = const ZoneConfig();

  final phase = RiderPhase.browse.obs;
  final pickup = Rxn<Place>();
  final dropoff = Rxn<Place>();
  final category = Category.course.obs;
  final route = Rxn<RouteInfo>();
  final routeLoading = false.obs;
  final price = 0.obs;
  final autoAccept = false.obs;
  final extraPassengers = false.obs;
  final childSeat = false.obs;
  final note = ''.obs;
  final error = RxnString();
  final busy = false.obs;

  final request = Rxn<RideRequest>();
  final offers = <Offer>[].obs;
  final ride = Rxn<Ride>();
  final remaining = 0.obs; // secondes avant l'expiration de la demande
  final stars = 0.obs;
  final history = <Ride>[].obs;
  final historyLoading = false.obs;
  final historyError = RxnString();

  StreamSubscription<RideRequest>? _reqSub;
  StreamSubscription<List<Offer>>? _offSub;
  StreamSubscription<Ride>? _rideSub;
  Timer? _tick;

  @override
  void onInit() {
    super.onInit();
    // Position simulée : l'original utilise le GPS.
    pickup.value = FakeMapService.places.first.copyWith(hint: 'Porte d\'entrée');
  }

  int recommendedFor(Category c) {
    final r = route.value;
    return r == null ? 0 : recommendedPrice(zone, r.distanceM, c);
  }

  int get minPrice => minimumOffer(zone, recommendedFor(category.value));
  bool get isOpen => request.value?.status == RequestStatus.open;
  bool get expired => request.value?.status == RequestStatus.expired;

  Future<void> setDestination(Place p) async {
    dropoff.value = p;
    await _loadRoute();
  }

  Future<void> setPickup(Place p) async {
    pickup.value = p;
    if (dropoff.value != null) await _loadRoute();
  }

  Future<void> _loadRoute() async {
    error.value = null;
    routeLoading.value = true;
    try {
      route.value = await map.route(pickup.value!, dropoff.value!);
      price.value = recommendedFor(category.value);
      phase.value = RiderPhase.planning;
    } catch (e) {
      error.value = "Impossible de calculer l'itinéraire. Vérifiez votre connexion.";
    } finally {
      routeLoading.value = false;
    }
  }

  void selectCategory(Category c) {
    category.value = c;
    price.value = recommendedFor(c);
  }

  void changePrice(int v) => price.value = v;

  Future<void> search() async {
    if (busy.value) return;
    error.value = null;
    busy.value = true;
    try {
      final r = route.value!;
      final req = await repo.createRideRequest(
        pickup: pickup.value!,
        dropoff: dropoff.value!,
        category: category.value,
        distanceM: r.distanceM,
        durationS: r.durationS,
        price: price.value,
        autoAccept: autoAccept.value,
        options: {'extra_passengers': extraPassengers.value, 'child_seat': childSeat.value},
        note: note.value.trim().isEmpty ? null : note.value.trim(),
      );
      _watchRequest(req);
    } catch (e) {
      error.value = _msg(e);
    } finally {
      busy.value = false;
    }
  }

  String _msg(Object e) => e is RideException ? _friendly(e.code) : "Une erreur est survenue. Réessayez dans un instant.";

  String _friendly(String c) => switch (c) {
        'request_already_open' => 'Vous avez déjà une demande en cours.',
        'price_too_low' => 'Ce prix est trop bas pour ce trajet. Augmentez-le.',
        'offer_not_available' => "Cette offre n'est plus disponible.",
        'driver_busy' => 'Ce chauffeur vient de prendre une autre course.',
        'request_not_open' => "Cette demande n'est plus ouverte.",
        'ride_already_active' => 'Vous avez déjà une course en cours.',
        _ => "Une erreur est survenue. Réessayez dans un instant.",
      };

  void _watchRequest(RideRequest req) {
    request.value = req;
    offers.clear();
    phase.value = RiderPhase.searching;
    _reqSub?.cancel();
    _offSub?.cancel();
    _reqSub = repo.watchRequest(req.id).listen((r) async {
      request.value = null; // force la mise à jour de l'observable (même instance)
      request.value = r;
      if (r.status == RequestStatus.matched && ride.value == null) {
        final active = await repo.activeRide();
        if (active != null) _watchRide(active);
      }
    });
    _offSub = repo.watchOffers(req.id).listen((l) => offers.assignAll(l));
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final r = request.value;
      remaining.value = r == null ? 0 : r.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 9999);
    });
    remaining.value = req.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 9999);
  }

  Future<void> raisePrice() async {
    final r = request.value;
    if (r == null || busy.value) return;
    try {
      await repo.raiseRequestPrice(r.id);
      price.value = r.offeredPrice;
    } catch (e) {
      error.value = _msg(e);
    }
  }

  /// Nouvelle recherche après expiration, avec un prix plus élevé si demandé.
  Future<void> relaunch({int raiseBy = 0}) async {
    _stopRequest();
    price.value = (request.value?.offeredPrice ?? price.value) + raiseBy;
    request.value = null;
    await search();
  }

  Future<void> choose(Offer o) async {
    if (busy.value) return;
    busy.value = true;
    error.value = null;
    try {
      final r = await repo.chooseOffer(o.id);
      _watchRide(r);
    } catch (e) {
      error.value = _msg(e);
    } finally {
      busy.value = false;
    }
  }

  Future<void> reject(Offer o) async {
    try {
      await repo.rejectOffer(o.id);
    } catch (e) {
      error.value = _msg(e);
    }
  }

  void _watchRide(Ride r) {
    ride.value = r;
    phase.value = RiderPhase.ride;
    _reqSub?.cancel();
    _offSub?.cancel();
    _tick?.cancel();
    _rideSub?.cancel();
    _rideSub = repo.watchRide(r.id).listen((x) {
      ride.value = null;
      ride.value = x;
      if (x.status == RideStatus.completed) phase.value = RiderPhase.rating;
    });
  }

  Future<void> passengerOnWay() async {
    final r = ride.value;
    if (r == null) return;
    try {
      await repo.passengerOnWay(r.id);
    } catch (e) {
      error.value = _msg(e);
    }
  }

  Future<void> cancelSearch(String reason) async {
    final r = request.value;
    if (r == null) return;
    try {
      await repo.cancelRequest(r.id, reason);
    } catch (_) {
      // déjà fermée : on revient simplement à la planification
    }
    _stopRequest();
    request.value = null;
    phase.value = RiderPhase.planning;
  }

  Future<void> cancelRide(String reason) async {
    final r = ride.value;
    if (r == null) return;
    try {
      await repo.cancelRide(r.id, reason);
    } catch (e) {
      error.value = _msg(e);
    }
  }

  Future<void> submitRating() async {
    final r = ride.value;
    if (r != null && stars.value > 0) {
      try {
        await repo.rateRide(r.id, stars.value);
      } catch (_) {
        // la note n'est pas bloquante pour terminer
      }
    }
    reset();
  }

  void reset() {
    _stopRequest();
    _rideSub?.cancel();
    request.value = null;
    ride.value = null;
    offers.clear();
    dropoff.value = null;
    route.value = null;
    stars.value = 0;
    error.value = null;
    autoAccept.value = false;
    phase.value = RiderPhase.browse;
  }

  void _stopRequest() {
    _reqSub?.cancel();
    _offSub?.cancel();
    _tick?.cancel();
  }

  Future<void> loadHistory() async {
    historyLoading.value = true;
    historyError.value = null;
    try {
      history.assignAll(await repo.history());
    } catch (_) {
      historyError.value = "Impossible de charger l'historique.";
    } finally {
      historyLoading.value = false;
    }
  }

  @override
  void onClose() {
    _stopRequest();
    _rideSub?.cancel();
    super.onClose();
  }
}
