import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/session.dart';
import '../admin/admin_login.dart';

class DriverLogin extends StatefulWidget {
  const DriverLogin({super.key});
  @override
  State<DriverLogin> createState() => _DriverLoginState();
}

class _DriverLoginState extends State<DriverLogin> {
  final _mob = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  String? _err;

  Future<void> _login() async {
    final m = mobile10(_mob.text);
    final p = digitsOnly(_pin.text);
    if (m.length != 10) return setState(() => _err = bi('10 अंकों का मोबाइल नंबर लिखें', 'Enter the 10-digit mobile number'));
    if (p.length != 6) return setState(() => _err = bi('6 अंकों का PIN लिखें', 'Enter the 6-digit PIN'));
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: driverEmail(p), password: driverPassword(m));
    } catch (e) {
      setState(() => _err = bi('मोबाइल नंबर या PIN गलत है', friendlyError(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hi = appLang.value == 'hi';
    return Scaffold(
      body: PageBody(maxWidth: 460, children: [
        const SizedBox(height: 24),
        Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: cSaffron, borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.local_shipping_outlined, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('TU Ver 01', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
              Text('Jagdamba Transport Carriers Pvt Ltd', style: TextStyle(fontSize: 13.5, color: cMuted)),
            ]),
          ),
        ]),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'en', label: Text('English')),
            ButtonSegment(value: 'hi', label: Text('हिन्दी')),
          ],
          selected: {appLang.value},
          showSelectedIcon: false,
          onSelectionChanged: (s) => appLang.value = s.first,
        ),
        Text(hi ? 'ड्राइवर लॉगिन · Driver login' : 'Driver login', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        TextField(
          controller: _mob,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          decoration: inDec(bi('मोबाइल नंबर', 'Mobile number'), prefix: '+91 '),
        ),
        TextField(
          controller: _pin,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          style: const TextStyle(fontSize: 20, letterSpacing: 8, fontWeight: FontWeight.w700),
          decoration: inDec(bi('PIN (6 अंक)', 'PIN given by Admin')),
          onSubmitted: (_) => _login(),
        ),
        NoteBox(bi('PIN हर ड्राइवर का अलग है और Admin देता है। PIN भूल गए? Admin से नया PIN लें।',
            'Each driver has a unique PIN from Admin. Forgot it? Ask Admin for a new PIN.')),
        if (_err != null) NoteBox(_err!, tone: Tone.bad),
        BigButton(hi ? 'लॉगिन करें' : 'Log in', sub: hi ? 'Log in' : null, busy: _busy, onPressed: _login),
        Center(
          child: TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminLogin())),
            child: const Text('Admin login →', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}
