import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/ui.dart';
import 'firebase_options.dart';
import 'screens/admin/dashboard.dart';
import 'screens/driver/driver_home.dart';
import 'screens/driver/login.dart';
import 'services/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const TuApp());
}

class TuApp extends StatelessWidget {
  const TuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: appLang,
      builder: (_, __, ___) => MaterialApp(
        title: 'TU Ver 01',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: cBlue, primary: cBlue, surface: cBg),
          scaffoldBackgroundColor: cBg,
          fontFamilyFallback: const ['Noto Sans Devanagari', 'Noto Sans'],
        ),
        home: const AuthGate(),
      ),
    );
  }
}

/// Opens the login screen, the driver app or the admin app.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const _Loading();
        if (snap.data == null) return const DriverLogin();
        return FutureBuilder<String?>(
          key: ValueKey(snap.data!.uid),
          future: Session.load(),
          builder: (context, s) {
            if (s.connectionState != ConnectionState.done) return const _Loading();
            if (s.hasError || s.data != null) {
              final msg = s.hasError ? friendlyError(s.error!) : s.data!;
              return _Blocked(msg);
            }
            if (Session.role == 'driver') return const DriverHome();
            return const AdminDashboard();
          },
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _Blocked extends StatelessWidget {
  final String msg;
  const _Blocked(this.msg);
  @override
  Widget build(BuildContext context) => Scaffold(
        body: PageBody(children: [
          const SizedBox(height: 60),
          NoteBox(msg, tone: Tone.bad),
          BigButton('Log out', onPressed: () => Session.logout()),
        ]),
      );
}
