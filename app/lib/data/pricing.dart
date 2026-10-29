import 'models.dart';

/// Paramètres de zone ; valeurs de départ identiques à celles des tests SQL (Abidjan).
class ZoneConfig {
  const ZoneConfig({
    this.baseFare = 500,
    this.pricePerKm = 250,
    this.minFare = 1000,
    this.priceStep = 50,
    this.raiseStep = 100,
    this.counterBandPct = 30,
    this.minOfferPctOfRecommended = 70,
    this.requestTtl = const Duration(seconds: 60),
    this.commissionBps = 1000,
    this.trafficFactor = 1.0,
  });

  final int baseFare;
  final int pricePerKm;
  final int minFare;
  final int priceStep;
  final int raiseStep;
  final int counterBandPct;
  final int minOfferPctOfRecommended;
  final Duration requestTtl;
  final int commissionBps;
  final double trafficFactor;
}

/// Même formule que recommended_price() dans schema.sql.
int recommendedPrice(ZoneConfig z, int distanceM, Category c) {
  final raw = (z.baseFare + (distanceM / 1000.0) * z.pricePerKm);
  final base = raw < z.minFare ? z.minFare.toDouble() : raw;
  return ((base * c.multiplier) / z.priceStep).round() * z.priceStep;
}

int minimumOffer(ZoneConfig z, int recommended) => recommended * z.minOfferPctOfRecommended ~/ 100;

int commissionFor(ZoneConfig z, int price) => (price * z.commissionBps / 10000).round();
