import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'app_config.dart';
import 'app_tokens.dart';
import 'theme.dart';

enum PinKind { pickup, dropoff, driver }

class MapPin {
  const MapPin(this.kind, this.lat, this.lng);
  final PinKind kind;
  final double lat;
  final double lng;
}

/// Carte plein cadre. Décorative pour les lecteurs d'écran : l'état du trajet est dans la feuille.
class MapCanvas extends StatelessWidget {
  const MapCanvas({super.key, required this.pins, this.path = const [], this.bottomPadding = 0});
  final List<MapPin> pins;
  final List<({double lat, double lng})> path;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final pts = [for (final x in pins) LatLng(x.lat, x.lng), for (final x in path) LatLng(x.lat, x.lng)];
    final fit = pts.length >= 2
        ? CameraFit.coordinates(coordinates: pts, padding: EdgeInsets.fromLTRB(48, 160, 48, 48 + bottomPadding), maxZoom: 16)
        : null;
    return ExcludeSemantics(
      child: FlutterMap(
        key: ValueKey(Object.hashAll([for (final x in pts) x.latitude, for (final x in pts) x.longitude])),
        options: MapOptions(
          initialCenter: pts.isEmpty ? const LatLng(5.34, -4.02) : pts.first,
          initialZoom: 14,
          initialCameraFit: fit,
          backgroundColor: p.surface,
        ),
        children: [
          if (AppConfig.tileUrl != null)
            TileLayer(urlTemplate: AppConfig.tileUrl!, userAgentPackageName: AppConfig.tileUserAgent),
          if (path.length >= 2)
            PolylineLayer(polylines: [
              Polyline(points: [for (final x in path) LatLng(x.lat, x.lng)], strokeWidth: 5, color: p.text),
            ]),
          MarkerLayer(markers: [
            for (final x in pins)
              Marker(
                point: LatLng(x.lat, x.lng),
                width: AppSize.mapPin,
                height: AppSize.mapPin,
                child: _Pin(x.kind),
              ),
          ]),
        ],
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin(this.kind);
  final PinKind kind;
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final (icon, bg, fg) = switch (kind) {
      PinKind.pickup => (Icons.person_pin_circle, p.text, p.bg),
      PinKind.dropoff => (Icons.flag, p.text, p.bg),
      PinKind.driver => (Icons.directions_car, p.accent, p.onAccent),
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Icon(icon, color: fg, size: 24),
    );
  }
}
