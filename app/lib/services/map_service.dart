import 'dart:math' as math;

import '../data/models.dart';

/// Carte, recherche d'adresses et itinéraire derrière une seule interface.
/// Prévu : Photon (adresses) et OSRM (routes) via Edge Functions ; voir replica/architecture.md.
abstract class MapService {
  Future<List<Place>> suggest(String query, {Place? near});
  Future<Place> reverse(double lat, double lng);
  Future<RouteInfo> route(Place from, Place to);
}

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
  final dp = p2 - p1, dl = (lng2 - lng1) * math.pi / 180;
  final h = math.pow(math.sin(dp / 2), 2) + math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

String _norm(String s) {
  const from = 'àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ';
  const to = 'aaaeeeeiioouuucAAAEEEEIIOOUUUC';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

/// Version hors ligne : quelques lieux d'Abidjan et de Bonoua, distance routière estimée à 1,3 × vol d'oiseau.
class FakeMapService implements MapService {
  static const places = <Place>[
    Place(label: 'Cocody, 7e Tranche', lat: 5.3560, lng: -3.9890),
    Place(label: 'Bonoua', lat: 5.2730, lng: -3.5930),
    Place(label: 'Treichville', lat: 5.2930, lng: -4.0050),
    Place(label: 'Yopougon', lat: 5.3360, lng: -4.0870),
    Place(label: 'Gare de Bassam, Treichville', lat: 5.2870, lng: -4.0050),
    Place(label: "CHU d'Angré", lat: 5.4000, lng: -3.9840),
    Place(label: 'Plateau', lat: 5.3240, lng: -4.0220),
    Place(label: 'Marcory', lat: 5.3030, lng: -3.9830),
  ];

  @override
  Future<List<Place>> suggest(String query, {Place? near}) async {
    final q = _norm(query.trim());
    if (q.isEmpty) return places.take(4).toList();
    return places.where((p) => _norm(p.label).contains(q)).toList();
  }

  @override
  Future<Place> reverse(double lat, double lng) async {
    var best = places.first;
    var bd = double.infinity;
    for (final p in places) {
      final d = haversineKm(lat, lng, p.lat, p.lng);
      if (d < bd) {
        bd = d;
        best = p;
      }
    }
    return Place(label: best.label, lat: lat, lng: lng);
  }

  @override
  Future<RouteInfo> route(Place from, Place to) async {
    final straight = haversineKm(from.lat, from.lng, to.lat, to.lng);
    final km = math.max(0.2, straight * 1.3);
    final speed = km < 15 ? 25.0 : 55.0; // km/h moyen, sans trafic : ville lente, route rapide
    final seconds = (km / speed * 3600).round();
    final mid = (lat: (from.lat + to.lat) / 2, lng: (from.lng + to.lng) / 2);
    return RouteInfo(
      distanceM: (km * 1000).round(),
      durationS: seconds,
      path: [(lat: from.lat, lng: from.lng), mid, (lat: to.lat, lng: to.lng)],
    );
  }
}
