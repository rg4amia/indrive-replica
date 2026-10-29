import 'dart:async';

import 'package:get/get.dart';

import '../data/models.dart';
import '../data/ride_repository.dart';
import 'app_controller.dart';

class DriverController extends GetxController {
  DriverController(this.app);
  final AppController app;
  RideRepository get repo => app.repo;

  final online = false.obs;
  final balance = 0.obs;
  final requests = <OpenRequest>[].obs;
  final loading = false.obs;
  final error = RxnString();
  final ride = Rxn<Ride>();
  final sentOffers = <String>{}.obs; // ids de demandes pour lesquelles une offre est partie
  final wallet = <WalletEntry>[].obs;
  final walletLoading = false.obs;

  StreamSubscription<int>? _balSub;
  StreamSubscription<Ride?>? _rideSub;
  Timer? _poll;

  @override
  void onInit() {
    super.onInit();
    _balSub = repo.watchBalance().listen((b) => balance.value = b);
    _rideSub = repo.watchDriverRide().listen((r) {
      ride.value = null;
      ride.value = r;
    });
  }

  Future<void> toggleOnline(bool v) async {
    error.value = null;
    try {
      await repo.setDriverOnline(v);
      online.value = v;
      if (v) {
        _startPolling();
      } else {
        _poll?.cancel();
        requests.clear();
      }
    } catch (e) {
      error.value = _msg(e);
    }
  }

  void _startPolling() {
    _poll?.cancel();
    refresh();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
  }

  @override
  Future<void> refresh() async {
    if (!online.value) return;
    try {
      requests.assignAll(await repo.nearbyOpenRequests());
    } catch (_) {
      error.value = 'Connexion perdue. Nouvelle tentative en cours.';
    }
  }

  /// Propose [price] pour [req] : égal au prix du passager = accepter, au-dessus = contre-offre.
  Future<bool> offer(OpenRequest req, int price) async {
    error.value = null;
    try {
      await repo.submitOffer(requestId: req.request.id, price: price, etaSeconds: 4 * 60);
      sentOffers.add(req.request.id);
      return true;
    } catch (e) {
      error.value = _msg(e);
      return false;
    }
  }

  Future<void> arrived() => _run((r) => repo.driverArrived(r.id));
  Future<void> start() => _run((r) => repo.startRide(r.id));
  Future<void> complete() => _run((r) => repo.completeRide(r.id));
  Future<void> cancel(String reason) => _run((r) => repo.cancelRide(r.id, reason));

  Future<void> _run(Future<Object?> Function(Ride) f) async {
    final r = ride.value;
    if (r == null) return;
    error.value = null;
    try {
      await f(r);
    } catch (e) {
      error.value = _msg(e);
    }
  }

  Future<void> loadWallet() async {
    walletLoading.value = true;
    try {
      wallet.assignAll(await repo.walletEntries());
    } finally {
      walletLoading.value = false;
    }
  }

  String _msg(Object e) {
    final c = e is RideException ? e.code : '';
    return switch (c) {
      'price_out_of_band' => 'Votre prix doit rester entre le prix du passager et 30 % au-dessus.',
      'balance_too_low' => 'Votre solde est insuffisant. Rechargez-le pour continuer.',
      'driver_not_ready' => 'Passez en ligne pour envoyer une offre.',
      'request_not_open' => "Cette demande n'est plus ouverte.",
      'ride_not_in_pickup' || 'ride_not_arrived' || 'ride_not_in_progress' => "Cette étape n'est plus possible. La course a changé.",
      _ => "Une erreur est survenue. Réessayez dans un instant.",
    };
  }

  @override
  void onClose() {
    _poll?.cancel();
    _balSub?.cancel();
    _rideSub?.cancel();
    super.onClose();
  }
}
