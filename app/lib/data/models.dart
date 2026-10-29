// Modèles du domaine. Les noms de champs suivent replica/schema.sql.

enum Category {
  course('Course', 1.00, 'Prix abordables'),
  confort('Confort', 1.20, 'Voitures plus récentes'),
  unClic('Un clic', 1.10, 'Départ rapide');

  const Category(this.label, this.multiplier, this.tagline);
  final String label;
  final double multiplier;
  final String tagline;
}

class Place {
  const Place({required this.label, required this.lat, required this.lng, this.hint});
  final String label;
  final double lat;
  final double lng;
  final String? hint;

  Place copyWith({String? hint}) => Place(label: label, lat: lat, lng: lng, hint: hint ?? this.hint);
}

class RouteInfo {
  const RouteInfo({required this.distanceM, required this.durationS, required this.path});
  final int distanceM;
  final int durationS;
  final List<({double lat, double lng})> path;
}

enum RequestStatus { open, matched, cancelled, expired }

class RideRequest {
  RideRequest({
    required this.id,
    required this.riderId,
    required this.pickup,
    required this.dropoff,
    required this.category,
    required this.distanceM,
    required this.durationS,
    required this.recommendedPrice,
    required this.offeredPrice,
    required this.expiresAt,
    this.autoAccept = false,
    this.options = const {},
    this.note,
    this.priceRaiseCount = 0,
    this.status = RequestStatus.open,
    this.cancelReason,
  });

  final String id;
  final String riderId;
  final Place pickup;
  final Place dropoff;
  final Category category;
  final int distanceM;
  final int durationS;
  final int recommendedPrice;
  int offeredPrice;
  DateTime expiresAt;
  final bool autoAccept;
  final Map<String, bool> options;
  final String? note;
  int priceRaiseCount;
  RequestStatus status;
  String? cancelReason;
}

enum OfferKind { accept, counter }

enum OfferStatus { pending, chosen, rejected, withdrawn, expired }

class Offer {
  Offer({
    required this.id,
    required this.requestId,
    required this.driverId,
    required this.driverName,
    required this.rating,
    required this.completedRides,
    required this.vehicle,
    required this.plate,
    required this.price,
    required this.etaSeconds,
    required this.kind,
    required this.expiresAt,
    this.status = OfferStatus.pending,
  });

  final String id;
  final String requestId;
  final String driverId;
  final String driverName;
  final double rating;
  final int completedRides;
  final String vehicle;
  final String plate;
  int price;
  int etaSeconds;
  OfferKind kind;
  DateTime expiresAt;
  OfferStatus status;

  int get etaMinutes => (etaSeconds / 60).ceil();
}

enum RideStatus { toPickup, arrived, inProgress, completed, cancelled }

class Ride {
  Ride({
    required this.id,
    required this.request,
    required this.driverId,
    required this.driverName,
    required this.vehicle,
    required this.plate,
    required this.agreedPrice,
    required this.commission,
    required this.createdAt,
    this.status = RideStatus.toPickup,
    this.finalPrice,
    this.cancelledBy,
    this.cancelReason,
    this.passengerOnWay = false,
  });

  final String id;
  final RideRequest request;
  final String driverId;
  final String driverName;
  final String vehicle;
  final String plate;
  final int agreedPrice;
  final int commission;
  final DateTime createdAt;
  RideStatus status;
  int? finalPrice;
  String? cancelledBy;
  String? cancelReason;
  bool passengerOnWay;

  bool get isActive => status == RideStatus.toPickup || status == RideStatus.arrived || status == RideStatus.inProgress;
}

/// Demande vue par un chauffeur (équivalent de nearby_open_requests).
class OpenRequest {
  const OpenRequest({required this.request, required this.riderName, required this.riderRating, required this.pickupDistanceM});
  final RideRequest request;
  final String riderName;
  final double riderRating;
  final int pickupDistanceM;
}

enum WalletKind { topup, commission, refund, penalty }

class WalletEntry {
  WalletEntry({required this.id, required this.kind, required this.amount, required this.createdAt, this.pending = false, this.rideId});
  final String id;
  final WalletKind kind;
  final int amount; // signé : débit < 0
  final DateTime createdAt;
  final bool pending;
  final String? rideId;
}

/// Erreur métier ; `code` reprend les messages des fonctions SQL (price_too_low, ...).
class RideException implements Exception {
  const RideException(this.code);
  final String code;
  @override
  String toString() => 'RideException($code)';
}
