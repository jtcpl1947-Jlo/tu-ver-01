import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../firebase_options.dart';
import '../../services/session.dart';

/// Admin / Manager login with a separate email and password.
/// The very first time, it offers to create the first Admin.
class AdminLogin extends StatefulWidget {
  const AdminLogin({super.key});
  @override
  State<AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<AdminLogin> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  bool? _setupDone;
  String? _err;

  @override
  void initState() {
    super.initState();
    db.collection('config').doc('setup').get().then((d) {
      if (mounted) setState(() => _setupDone = d.exists);
    }).catchError((_) {
      if (mounted) setState(() => _setupDone = true);
    });
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: _email.text.trim(), password: _pass.text);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      setState(() => _err = e.toString().contains('invalid') ? 'Email or password is wrong.' : friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// First Admin: creates the login and the account in one go, then logs in.
  Future<void> _setup() async {
    if (_name.text.trim().isEmpty) return setState(() => _err = 'Enter your name.');
    if (!_email.text.contains('@')) return setState(() => _err = 'Enter a valid email.');
    if (_pass.text.length < 8) return setState(() => _err = 'Password must be at least 8 characters.');
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      FirebaseApp app;
      try {
        app = Firebase.app('setup');
      } catch (_) {
        app = await Firebase.initializeApp(name: 'setup', options: DefaultFirebaseOptions.currentPlatform);
      }
      final auth = FirebaseAuth.instanceFor(app: app);
      final cred = await auth.createUserWithEmailAndPassword(email: _email.text.trim(), password: _pass.text);
      final uid = cred.user!.uid;
      final fs = FirebaseFirestore.instanceFor(app: app);
      final b = fs.batch();
      b.set(fs.collection('accounts').doc(uid), {
        'role': 'admin',
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      b.set(fs.collection('config').doc('setup'), {'adminUid': uid, 'at': FieldValue.serverTimestamp()});
      await b.commit();
      await auth.signOut();
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: _email.text.trim(), password: _pass.text);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      setState(() => _err = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = _setupDone == false;
    return Scaffold(
      appBar: topBar(setup ? 'First-time setup' : 'Admin login', sub: 'JTCPL office only'),
      body: _setupDone == null
          ? const Center(child: CircularProgressIndicator())
          : PageBody(maxWidth: 460, children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: cBlueBg, borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.lock_outline, color: cBlue, size: 36),
                ),
              ),
              if (setup) ...[
                const NoteBox('No Admin exists yet. Create the first Admin login for JTCPL. This screen appears only once.',
                    tone: Tone.warn),
                TextField(controller: _name, decoration: inDec('Your name')),
              ],
              TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: inDec('Admin email')),
              TextField(
                controller: _pass,
                obscureText: true,
                decoration: inDec('Password'),
                onSubmitted: (_) => setup ? _setup() : _login(),
              ),
              if (!setup)
                const NoteBox('Admin and Manager passwords are separate from driver PINs. Managers can only view and download reports.'),
              if (_err != null) NoteBox(_err!, tone: Tone.bad),
              BigButton(setup ? 'Create Admin and log in' : 'Log in', busy: _busy, onPressed: setup ? _setup : _login),
            ]),
    );
  }
}
