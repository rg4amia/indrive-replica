import 'package:get/get.dart';

import '../data/fake_ride_repository.dart';
import '../data/ride_repository.dart';
import '../services/map_service.dart';

enum AppMode { rider, driver }

/// Services partagés et mode courant (passager ou chauffeur), comme le bouton « Mode conducteur » de l'original.
class AppController extends GetxController {
  AppController({RideRepository? repo, MapService? map})
      : repo = repo ?? FakeRideRepository(),
        map = map ?? FakeMapService();

  final RideRepository repo;
  final MapService map;
  final mode = AppMode.rider.obs;
  final unreadNotifications = 2.obs;

  void switchMode(AppMode m) {
    if (mode.value == m) return;
    mode.value = m;
    repo.currentUserId = m == AppMode.rider ? FakeRideRepository.riderId : FakeRideRepository.driverId;
    Get.offAllNamed(m == AppMode.rider ? '/home' : '/driver');
  }

  @override
  void onClose() {
    final r = repo;
    if (r is FakeRideRepository) r.dispose();
    super.onClose();
  }
}
