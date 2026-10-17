import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/session.dart';

class AdminSettings extends StatefulWidget {
  const AdminSettings({super.key});
  @override
  State<AdminSettings> createState() => _AdminSettingsState();
}

class _AdminSettingsState extends State<AdminSettings> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _mName = TextEditingController();
  final _mEmail = TextEditingController();
  final _mPass = TextEditingController();
  String _mRole = 'manager';
  bool _busy = false;

  Future<void> _changePassword() async {
    if (_new.text.length < 8) return snack(context, 'New password must be at least 8 characters.', error: true);
    setState(() => _busy = true);
    try {
      final u = FirebaseAuth.instance.currentUser!;
      await u.reauthenticateWithCredential(EmailAuthProvider.credential(email: u.email!, password: _old.text));
      await u.updatePassword(_new.text);
      _old.clear();
      _new.clear();
      if (mounted) snack(context, 'Password changed');
    } catch (e) {
      if (mounted) snack(context, e.toString().contains('invalid') ? 'Current password is wrong.' : friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addLogin() async {
    if (_mName.text.trim().isEmpty || !_mEmail.text.contains('@')) return snack(context, 'Enter name and a valid email.', error: true);
    if (_mPass.text.length < 8) return snack(context, 'Password must be at least 8 characters.', error: true);
    setState(() => _busy = true);
    try {
      final uid = await createLogin(_mEmail.text.trim(), _mPass.text);
      await db.collection('accounts').doc(uid).set({
        'role': _mRole,
        'name': _mName.text.trim(),
        'email': _mEmail.text.trim(),
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) snack(context, '${_mRole == 'admin' ? 'Admin' : 'Manager'} login created for ${_mEmail.text.trim()}');
      _mName.clear();
      _mEmail.clear();
      _mPass.clear();
    } catch (e) {
      if (mounted) snack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: topBar('Admin settings'),
      body: PageBody(children: [
        const Label('Change my password'),
        TextField(controller: _old, obscureText: true, decoration: inDec('Current password')),
        TextField(controller: _new, obscureText: true, decoration: inDec('New password (8+ characters)')),
        BigButton('Change password', small: true, busy: _busy, onPressed: _changePassword),
        const Divider(height: 28),
        const Label('Add office login'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'manager', label: Text('Manager (view only)')),
            ButtonSegment(value: 'admin', label: Text('Admin')),
          ],
          selected: {_mRole},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _mRole = s.first),
        ),
        TextField(controller: _mName, decoration: inDec('Name')),
        TextField(controller: _mEmail, keyboardType: TextInputType.emailAddress, decoration: inDec('Email')),
        TextField(controller: _mPass, obscureText: true, decoration: inDec('Password (8+ characters)')),
        BigButton('Create login', small: true, busy: _busy, onPressed: _addLogin),
        const Label('Office logins'),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('accounts').where('role', whereIn: ['admin', 'manager']).snapshots(),
          builder: (context, s) {
            final docs = s.data?.docs ?? [];
            return KvCard([
              for (final d in docs)
                (
                  '${d.data()['name']} · ${d.data()['email'] ?? ''}\n${d.data()['role'] == 'admin' ? 'Admin' : 'Manager'}',
                  d.id == Session.uid
                      ? const Pill('You', tone: Tone.info)
                      : TextButton(
                          onPressed: () => d.reference.update({'active': d.data()['active'] != true}),
                          child: Text(d.data()['active'] == true ? 'Switch off' : 'Switch on'),
                        ),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}
