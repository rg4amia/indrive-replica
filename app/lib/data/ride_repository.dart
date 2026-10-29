import 'models.dart';

/// Contrat de la couche de données. Chaque méthode correspond à une fonction de replica/schema.sql
/// (nom entre crochets). L'implémentation Supabase remplacera la version factice sans toucher aux écrans.
abstract class RideRepository {
  String get currentUserId;
  set currentUserId(String value);

  // --- passager
  /// [create_ride_request]
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
  });

  /// [raise_request_price]
  Future<RideRequest> raiseRequestPrice(String requestId);

  /// [cancel_request]
  Future<void> cancelRequest(String requestId, String reason);

  /// État de la demande en direct.
  Stream<RideRequest> watchRequest(String requestId);

  /// [list_offers] + Realtime sur offers.
  Stream<List<Offer>> watchOffers(String requestId);

  /// [choose_offer]
  Future<Ride> chooseOffer(String offerId);

  /// [reject_offer]
  Future<void> rejectOffer(String offerId);

  /// Course active du passager, si elle existe (utile après une acceptation automatique).
  Future<Ride?> activeRide();

  Stream<Ride> watchRide(String rideId);

  /// [passenger_on_way]
  Future<void> passengerOnWay(String rideId);

  /// [cancel_ride]
  Future<Ride> cancelRide(String rideId, String reason);

  Future<void> rateRide(String rideId, int stars, {String? comment});

  /// Historique du passager (table rides).
  Future<List<Ride>> history();

  // --- chauffeur
  /// [set_driver_online]
  Future<void> setDriverOnline(bool online);

  /// [nearby_open_requests]
  Future<List<OpenRequest>> nearbyOpenRequests();

  /// [submit_offer]
  Future<Offer> submitOffer({required String requestId, required int price, required int etaSeconds});

  /// [withdraw_offer]
  Future<void> withdrawOffer(String offerId);

  /// Course active du chauffeur, si elle existe.
  Stream<Ride?> watchDriverRide();

  /// [driver_arrived]
  Future<Ride> driverArrived(String rideId);

  /// [start_ride]
  Future<Ride> startRide(String rideId);

  /// [complete_ride]
  Future<Ride> completeRide(String rideId, {int? finalPrice});

  Stream<int> watchBalance();
  Future<List<WalletEntry>> walletEntries();
}
