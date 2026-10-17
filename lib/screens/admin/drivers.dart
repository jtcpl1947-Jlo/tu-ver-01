import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/ui.dart';
import '../../services/session.dart';

DateTime? _parseDate(String s) {
  try {
    return DateFormat('dd-MM-yyyy').parseStrict(s.trim());
  } catch (_) {
    return null;
  }
}

class Drivers extends StatelessWidget {
  const Drivers({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: topBar('Drivers and PINs', sub: 'Capacity 50 drivers'),
      floatingActionButton: Session.isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverForm())),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add driver'),
            )
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('users').snapshots(),
        builder: (context, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final docs = s.data!.docs.toList()
            ..sort((a, b) => ((a.data()['name'] ?? '') as String).compareTo((b.data()['name'] ?? '') as String));
          final active = docs.where((d) => d.data()['active'] == true).length;
          return PageBody(maxWidth: 720, children: [
            Text('$active active · ${docs.length} total · ${max(0, 50 - active)} places free',
                style: const TextStyle(color: cMuted)),
            if (docs.isEmpty) const NoteBox('No drivers yet. Tap "Add driver" to add the first one.'),
            for (final d in docs) _row(context, d.id, d.data()),
            const SizedBox(height: 60),
          ]);
        },
      ),
    );
  }

  Widget _row(BuildContext context, String id, Map<String, dynamic> d) {
    final exp = _parseDate((d['dlExpiry'] ?? '') as String);
    final days = exp?.difference(DateTime.now()).inDays;
    Widget pill;
    if (d['active'] != true) {
      pill = const Pill('Switched off', tone: Tone.bad);
    } else if (days != null && days < 0) {
      pill = const Pill('DL expired', tone: Tone.bad);
    } else if (days != null && days <= 30) {
      pill = Pill('DL expires $days days', tone: Tone.warn);
    } else {
      pill = const Pill('Active', tone: Tone.ok);
    }
    final truck = (d['ownTruck'] ?? '') as String;
    return MenuRow(
      icon: Icons.person_outline,
      title: (d['name'] ?? '') as String,
      sub: '${d['mobile'] ?? ''} · ${truck.isEmpty ? 'No own truck' : prettyTruck(truck)}',
      trailing: pill,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DriverForm(driverId: id, data: d))),
    );
  }
}

/// Add a driver (with unique PIN) or edit one.
class DriverForm extends StatefulWidget {
  final String? driverId;
  final Map<String, dynamic>? data;
  const DriverForm({super.key, this.driverId, this.data});
  @override
  State<DriverForm> createState() => _DriverFormState();
}

class _DriverFormState extends State<DriverForm> {
  late final _name = TextEditingController(text: widget.data?['name'] as String? ?? '');
  late final _mob = TextEditingController(text: widget.data?['mobile'] as String? ?? '');
  late final _dl = TextEditingController(text: widget.data?['dlNo'] as String? ?? '');
  late final _dlx = TextEditingController(text: widget.data?['dlExpiry'] as String? ?? '');
  final _pin = TextEditingController();
  late String _truck = widget.data?['ownTruck'] as String? ?? '';
  String? _pinMsg;
  bool _pinOk = false;
  bool _busy = false;

  bool get _isNew => widget.driverId == null;
  bool get _ro => !Session.isAdmin;

  Future<void> _checkPin() async {
    final p = digitsOnly(_pin.text);
    if (p.length != 6) {
      setState(() {
        _pinOk = false;
        _pinMsg = p.isEmpty ? null : 'PIN must be 6 digits.';
      });
      return;
    }
    final d = await db.collection('pins').doc(p).get();
    if (!mounted || digitsOnly(_pin.text) != p) return;
    setState(() {
      _pinOk = !d.exists;
      _pinMsg = d.exists ? 'PIN $p is already used by ${d.data()?['name']}. Choose another PIN.' : '✓ PIN $p is free. Share it with the driver privately.';
    });
  }

  Future<void> _generate() async {
    final r = Random.secure();
    for (var i = 0; i < 20; i++) {
      final p = (100000 + r.nextInt(900000)).toString();
      final d = await db.collection('pins').doc(p).get();
      if (!d.exists) {
        _pin.text = p;
        break;
      }
    }
    await _checkPin();
  }

  String? _validate({required bool needPin}) {
    if (_name.text.trim().isEmpty) return 'Enter the driver name.';
    if (mobile10(_mob.text).length != 10) return 'Enter a 10-digit mobile number.';
    if (_dlx.text.trim().isNotEmpty && _parseDate(_dlx.text) == null) return 'DL expiry must be dd-mm-yyyy.';
    if (needPin && (!_pinOk || digitsOnly(_pin.text).length != 6)) return 'Choose a free 6-digit PIN.';
    return null;
  }

  /// Gives the truck to this driver and removes it from its previous driver.
  Future<void> _assignTruck(WriteBatch b, String driverId, String name) async {
    final old = widget.data?['ownTruck'] as String? ?? '';
    if (old.isNotEmpty && old != _truck) {
      b.set(db.collection('trucks').doc(old), {'driverId': '', 'driverName': ''}, SetOptions(merge: true));
    }
    if (_truck.isEmpty) return;
    final t = await db.collection('trucks').doc(_truck).get();
    final prev = t.data()?['driverId'] as String? ?? '';
    if (prev.isNotEmpty && prev != driverId) {
      b.update(db.collection('users').doc(prev), {'ownTruck': ''});
    }
    b.set(db.collection('trucks').doc(_truck), {'driverId': driverId, 'driverName': name}, SetOptions(merge: true));
  }

  Future<void> _saveNew() async {
    final err = _validate(needPin: true);
    if (err != null) return snack(context, err, error: true);
    setState(() => _busy = true);
    try {
      final pin = digitsOnly(_pin.text);
      final mob = mobile10(_mob.text);
      final name = _name.text.trim();
      final uid = await createLogin(driverEmail(pin), driverPassword(mob));
      final ref = db.collection('users').doc();
      final b = db.batch();
      b.set(ref, {
        'name': name,
        'mobile': mob,
        'dlNo': _dl.text.trim(),
        'dlExpiry': _dlx.text.trim(),
        'ownTruck': _truck,
        'active': true,
        'pin': pin,
        'uid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      b.set(db.collection('accounts').doc(uid), {'role': 'driver', 'driverId': ref.id, 'name': name, 'active': true});
      b.set(db.collection('pins').doc(pin), {'driverId': ref.id, 'uid': uid, 'name': name});
      await _assignTruck(b, ref.id, name);
      await b.commit();
      if (mounted) {
        snack(context, 'Driver added. Login: mobile $mob + PIN $pin');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        snack(context, e.toString().contains('email-already-in-use') ? 'This PIN is already used. Choose another PIN.' : friendlyError(e),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveEdit() async {
    final err = _validate(needPin: false);
    if (err != null) return snack(context, err, error: true);
    setState(() => _busy = true);
    try {
      final id = widget.driverId!;
      final name = _name.text.trim();
      final b = db.batch();
      b.update(db.collection('users').doc(id), {
        'name': name,
        'dlNo': _dl.text.trim(),
        'dlExpiry': _dlx.text.trim(),
        'ownTruck': _truck,
      });
      final uid = widget.data?['uid'] as String?;
      if (uid != null && uid.isNotEmpty) b.update(db.collection('accounts').doc(uid), {'name': name});
      await _assignTruck(b, id, name);
      await b.commit();
      if (mounted) {
        snack(context, 'Saved');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) snack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// New PIN (and/or new mobile) means a new login; the old one is switched off.
  Future<void> _resetPin() async {
    final err = _validate(needPin: true);
    if (err != null) return snack(context, err, error: true);
    final pin = digitsOnly(_pin.text);
    final mob = mobile10(_mob.text);
    if (!await confirmBox(context, 'Give new PIN?', 'The old PIN stops working. The driver logs in with mobile $mob and PIN $pin.')) return;
    setState(() => _busy = true);
    try {
      final id = widget.driverId!;
      final name = _name.text.trim();
      final uid = await createLogin(driverEmail(pin), driverPassword(mob));
      final b = db.batch();
      final oldUid = widget.data?['uid'] as String?;
      final oldPin = widget.data?['pin'] as String?;
      if (oldUid != null && oldUid.isNotEmpty) b.update(db.collection('accounts').doc(oldUid), {'active': false});
      if (oldPin != null && oldPin.isNotEmpty) b.delete(db.collection('pins').doc(oldPin));
      b.set(db.collection('accounts').doc(uid), {'role': 'driver', 'driverId': id, 'name': name, 'active': widget.data?['active'] == true});
      b.set(db.collection('pins').doc(pin), {'driverId': id, 'uid': uid, 'name': name});
      b.update(db.collection('users').doc(id), {'pin': pin, 'uid': uid, 'mobile': mob});
      await b.commit();
      if (mounted) {
        snack(context, 'New PIN set. Login: mobile $mob + PIN $pin');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        snack(context, e.toString().contains('email-already-in-use') ? 'This PIN is already used. Choose another PIN.' : friendlyError(e),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleActive() async {
    final on = widget.data?['active'] == true;
    if (!await confirmBox(context, on ? 'Switch off driver?' : 'Switch on driver?',
        on ? 'The driver cannot log in until switched on again. Records are kept.' : 'The driver can log in again.')) {
      return;
    }
    final b = db.batch();
    b.update(db.collection('users').doc(widget.driverId), {'active': !on});
    final uid = widget.data?['uid'] as String?;
    if (uid != null && uid.isNotEmpty) b.update(db.collection('accounts').doc(uid), {'active': !on});
    await b.commit();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: topBar(_isNew ? 'Add driver' : (_ro ? 'Driver' : 'Edit driver'),
          sub: _isNew ? 'Unique PIN for each driver' : 'PIN ${widget.data?['pin'] ?? '-'}'),
      body: PageBody(children: [
        TextField(controller: _name, readOnly: _ro, decoration: inDec('Driver name')),
        TextField(
          controller: _mob,
          readOnly: _ro,
          keyboardType: TextInputType.phone,
          decoration: inDec('Mobile', prefix: '+91 ', hint: _isNew ? null : 'Changing mobile needs a new PIN'),
        ),
        Row(children: [
          Expanded(child: TextField(controller: _dl, readOnly: _ro, decoration: inDec('DL number'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _dlx, readOnly: _ro, decoration: inDec('DL expiry', hint: 'dd-mm-yyyy'))),
        ]),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('trucks').snapshots(),
          builder: (context, s) {
            final trucks = s.data?.docs.toList() ?? [];
            trucks.sort((a, b) => a.id.compareTo(b.id));
            final ids = trucks.map((t) => t.id).toSet();
            return DropdownButtonFormField<String>(
              value: ids.contains(_truck) || _truck.isEmpty ? _truck : '',
              isExpanded: true,
              decoration: inDec('Own truck'),
              items: [
                const DropdownMenuItem(value: '', child: Text('None')),
                for (final t in trucks)
                  DropdownMenuItem(
                    value: t.id,
                    child: Text(
                      '${prettyTruck(t.id)}${(t.data()['driverName'] ?? '').toString().isNotEmpty && t.data()['driverId'] != widget.driverId ? ' (now ${t.data()['driverName']})' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _ro ? null : (v) => setState(() => _truck = v ?? ''),
            );
          },
        ),
        if (!_ro) ...[
          Label(_isNew ? 'Allocate PIN (6 digits, unique)' : 'Give a new PIN'),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _pin,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(letterSpacing: 4, fontWeight: FontWeight.w700, fontSize: 18),
                decoration: inDec('PIN'),
                onChanged: (_) => _checkPin(),
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: OutlinedButton(onPressed: _generate, child: const Text('Generate')),
            ),
          ]),
          if (_pinMsg != null) NoteBox(_pinMsg!, tone: _pinOk ? Tone.ok : Tone.bad),
          if (_isNew)
            BigButton('Save driver', busy: _busy, onPressed: _saveNew)
          else ...[
            BigButton('Save changes', busy: _busy, onPressed: _saveEdit),
            BigButton('Set new PIN', outlined: true, busy: _busy, onPressed: _resetPin),
            BigButton(widget.data?['active'] == true ? 'Switch off driver' : 'Switch on driver',
                outlined: true, onPressed: _busy ? null : _toggleActive),
          ],
        ],
      ]),
    );
  }
}
