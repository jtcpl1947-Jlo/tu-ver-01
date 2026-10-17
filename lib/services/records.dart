import 'package:cloud_firestore/cloud_firestore.dart';

import 'session.dart';

/// Last odometer reading saved for a truck (any driver), or null.
Future<double?> lastKm(String truck) async {
  final d = await db.collection('odometer').doc(truck).get();
  return (d.data()?['lastKm'] as num?)?.toDouble();
}

/// Batch write that keeps the truck's last odometer reading up to date.
void setLastKm(WriteBatch b, String truck, double km) {
  b.set(
    db.collection('odometer').doc(truck),
    {'lastKm': km, 'at': FieldValue.serverTimestamp(), 'by': Session.driverId},
    SetOptions(merge: true),
  );
}
