import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

final FirebaseFirestore db = FirebaseFirestore.instance;

/// Who is logged in.
///
/// Firestore layout:
///   accounts/{authUid}  role (driver|admin|manager), driverId, name, active
///   users/{driverId}    driver profile (name, mobile, dlNo, dlExpiry, ownTruck, active)
///   pins/{pin}          driverId, uid, name  (keeps PINs unique)
///   trucks/{NO}         number, driverId, driverName
///   pumps/{id}          name
///   odometer/{NO}       lastKm, at
///   duties/{id}         one duty (start/end km, truck, own/temp)
///   diesel/{id}         one diesel entry
///   tracks/{driverId_yyyyMMdd}  GPS points for one driver for one day
///   photos/{id}         compressed photo (slip / meter)
///   config/setup        exists once the first Admin is created
class Session {
  static String uid = '';
  static String role = '';
  static String name = '';
  static String driverId = '';
  static String mobile = '';
  static String ownTruck = '';

  static bool get isAdmin => role == 'admin';
  static bool get isManager => role == 'manager';
  static bool get isStaff => isAdmin || isManager;

  /// Loads the account after Firebase sign-in. Returns an error text or null.
  static Future<String?> load() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return 'Not logged in.';
    final acc = await db.collection('accounts').doc(u.uid).get();
    if (!acc.exists) return 'This login is not set up in TU Ver 01.';
    final a = acc.data()!;
    if (a['active'] != true) return 'This login is switched off. Contact JTCPL Admin.';
    uid = u.uid;
    role = (a['role'] ?? '') as String;
    name = (a['name'] ?? '') as String;
    driverId = (a['driverId'] ?? '') as String;
    mobile = '';
    ownTruck = '';
    if (role == 'driver') {
      final p = await db.collection('users').doc(driverId).get();
      if (!p.exists || p.data()!['active'] != true) return 'This driver is switched off. Contact JTCPL Admin.';
      final d = p.data()!;
      name = (d['name'] ?? name) as String;
      mobile = (d['mobile'] ?? '') as String;
      ownTruck = (d['ownTruck'] ?? '') as String;
    }
    return null;
  }

  static Future<void> logout() async {
    uid = role = name = driverId = mobile = ownTruck = '';
    await FirebaseAuth.instance.signOut();
  }
}

// ---------- Login emails ----------
// A driver's Firebase login is built from the unique PIN, so Firebase itself
// refuses a second account with the same PIN.
String driverEmail(String pin) => 'p$pin@tuver01.app';
String driverPassword(String mobile) => 'm$mobile';

/// Creates a Firebase login without logging the Admin out (uses a second app instance).
Future<String> createLogin(String email, String password) async {
  FirebaseApp app;
  try {
    app = Firebase.app('secondary');
  } catch (_) {
    app = await Firebase.initializeApp(name: 'secondary', options: DefaultFirebaseOptions.currentPlatform);
  }
  final auth = FirebaseAuth.instanceFor(app: app);
  final cred = await auth.createUserWithEmailAndPassword(email: email, password: password);
  final id = cred.user!.uid;
  await auth.signOut();
  return id;
}
