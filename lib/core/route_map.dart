import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'ui.dart';

/// Default view: Delhi NCR - Rajasthan corridor.
const kDefaultCenter = LatLng(28.0, 76.6);

List<LatLng> pointsOf(List<dynamic>? raw) {
  final list = (raw ?? [])
      .whereType<Map>()
      .where((p) => p['lat'] is num && p['lng'] is num)
      .toList()
    ..sort((a, b) {
      final ta = (a['t'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      final tb = (b['t'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      return ta.compareTo(tb);
    });
  return list.map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())).toList();
}

class MapPin {
  final LatLng point;
  final Color color;
  final String? label;
  final double size;
  final VoidCallback? onTap;
  const MapPin(this.point, this.color, {this.label, this.size = 16, this.onTap});
}

/// OpenStreetMap with an optional route line and pins (free, no billing).
class RouteMap extends StatelessWidget {
  final List<LatLng> route;
  final List<MapPin> pins;
  final double height;
  const RouteMap({super.key, this.route = const [], this.pins = const [], this.height = 300});

  @override
  Widget build(BuildContext context) {
    final all = [...route, ...pins.map((p) => p.point)];
    final MapOptions options;
    if (all.length >= 2) {
      options = MapOptions(
        initialCameraFit: CameraFit.bounds(bounds: LatLngBounds.fromPoints(all), padding: const EdgeInsets.all(36), maxZoom: 15),
      );
    } else {
      options = MapOptions(initialCenter: all.isNotEmpty ? all.first : kDefaultCenter, initialZoom: all.isNotEmpty ? 13 : 7);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: height,
        decoration: BoxDecoration(border: Border.all(color: cLine), borderRadius: BorderRadius.circular(14)),
        child: Stack(children: [
          FlutterMap(
            key: ValueKey('${all.length}_${all.isNotEmpty ? all.last : ''}'),
            options: options,
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.jtcpl.tuver01',
              ),
              if (route.length >= 2)
                PolylineLayer(polylines: [Polyline(points: route, strokeWidth: 4.5, color: cBlue)]),
              MarkerLayer(markers: [
                for (final p in route.length > 2 ? route.sublist(0, route.length - 1) : <LatLng>[])
                  Marker(
                    point: p,
                    width: 8,
                    height: 8,
                    child: Container(decoration: const BoxDecoration(color: cBlue, shape: BoxShape.circle)),
                  ),
                for (final p in pins)
                  Marker(
                    point: p.point,
                    width: p.label == null ? p.size + 6 : 170,
                    height: p.size + 6,
                    alignment: p.label == null ? Alignment.center : Alignment.centerRight,
                    child: GestureDetector(
                      onTap: p.onTap,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: p.size,
                          height: p.size,
                          decoration: BoxDecoration(
                              color: p.color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)),
                        ),
                        if (p.label != null) ...[
                          const SizedBox(width: 4),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(color: Colors.white.withAlpha(230), borderRadius: BorderRadius.circular(5)),
                              child: Text(p.label!,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: p.color)),
                            ),
                          ),
                        ],
                      ]),
                    ),
                  ),
              ]),
            ],
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.white.withAlpha(220),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: const Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 10, color: cMuted)),
            ),
          ),
        ]),
      ),
    );
  }
}
