import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../core/ui.dart';
import 'session.dart';

/// Sends the phone's location every 5 minutes while the driver is on duty.
/// On Android it runs as a foreground service with a notification, so it keeps
/// working when the screen is off. Firestore queues writes offline and sends
/// them when the network returns.
class Tracker {
  static const interval = Duration(minutes: 5);
  static StreamSubscription<Position>? _sub;
  static Timer? _timer;
  static DateTime? _lastSent;
  static Position? _lastPos;
  static String _dutyId = '';
  static String _truck = '';
  static String _truckType = '';

  static bool _active = false;
  static bool get running => _active;

  static String trackId(String driverId, DateTime d) => '${driverId}_${DateFormat('yyyyMMdd').format(d)}';

  /// Returns null when location can be used, otherwise a message for the driver.
  static Future<String?> checkPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return bi('फ़ोन की लोकेशन बंद है। चालू करें।', 'Phone location is off. Turn it on.');
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      return bi('लोकेशन की अनुमति दें, नहीं तो ड्यूटी शुरू नहीं होगी।',
          'Allow location permission. Duty cannot start without it.');
    }
    return null;
  }

  static Future<Position?> currentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  static Future<void> start({required String dutyId, required String truck, required String truckType}) async {
    await stop(markOff: false);
    _active = true;
    _dutyId = dutyId;
    _truck = truck;
    _truckType = truckType;
    _lastSent = null;

    final LocationSettings settings;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: interval,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'TU Ver 01 · ड्यूटी चालू',
          notificationText: 'हर 5 मिनट लोकेशन भेजी जा रही है · Location shared every 5 minutes',
          enableWakeLock: true,
        ),
      );
    } else {
      settings = const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 0);
    }

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(_onPosition, onError: (_) {});
    // Backup timer: some phones and browsers only report when the position changes.
    _timer = Timer.periodic(interval, (_) async {
      final p = await currentPosition();
      if (p != null) _onPosition(p, force: true);
    });
    final first = await currentPosition();
    if (first != null) _onPosition(first, force: true);
  }

  static void _onPosition(Position p, {bool force = false}) {
    final now = DateTime.now();
    if (!force && _lastSent != null && now.difference(_lastSent!) < const Duration(minutes: 4, seconds: 30)) return;
    if (force && _lastSent != null && now.difference(_lastSent!) < const Duration(minutes: 4)) return;
    _lastSent = now;
    _send(p, now);
  }

  static Future<void> _send(Position p, DateTime now) async {
    var addKm = 0.0;
    if (_lastPos != null) {
      final m = Geolocator.distanceBetween(_lastPos!.latitude, _lastPos!.longitude, p.latitude, p.longitude);
      final hours = now.difference(_lastPos!.timestamp).inSeconds / 3600.0;
      final speed = hours > 0 ? (m / 1000) / hours : 0;
      if (speed < 130) addKm = m / 1000; // ignore GPS jumps
    }
    _lastPos = p;
    final id = trackId(Session.driverId, now);
    try {
      await db.collection('tracks').doc(id).set({
        'driverId': Session.driverId,
        'driverName': Session.name,
        'truck': _truck,
        'truckType': _truckType,
        'dutyId': _dutyId,
        'date': dateKey(now),
        'onDuty': true,
        'lastLat': p.latitude,
        'lastLng': p.longitude,
        'lastAt': Timestamp.fromDate(now),
        'gpsKm': FieldValue.increment(double.parse(addKm.toStringAsFixed(3))),
        'points': FieldValue.arrayUnion([
          {'lat': p.latitude, 'lng': p.longitude, 't': Timestamp.fromDate(now)}
        ]),
      }, SetOptions(merge: true));
    } catch (_) {
      // Firestore keeps the write and retries when online.
    }
  }

  static Future<void> stop({bool markOff = true}) async {
    _active = false;
    await _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
    _lastPos = null;
    if (markOff && Session.driverId.isNotEmpty) {
      try {
        await db.collection('tracks').doc(trackId(Session.driverId, DateTime.now())).set(
          {'onDuty': false, 'driverId': Session.driverId, 'date': dateKey(DateTime.now())},
          SetOptions(merge: true),
        );
      } catch (_) {}
    }
  }
}

/// Minutes without a location update during a duty (gaps over 15 minutes count).
int locationOffMinutes(List<dynamic> points, DateTime start, DateTime end) {
  final times = points
      .map((p) => (p as Map)['t'])
      .whereType<Timestamp>()
      .map((t) => t.toDate())
      .where((t) => !t.isBefore(start) && !t.isAfter(end))
      .toList()
    ..sort();
  final all = [start, ...times, end];
  var off = 0;
  for (var i = 1; i < all.length; i++) {
    final gap = all[i].difference(all[i - 1]).inMinutes;
    if (gap > 15) off += gap - 5;
  }
  return off;
}
