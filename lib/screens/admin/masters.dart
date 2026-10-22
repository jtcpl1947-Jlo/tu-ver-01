import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/session.dart';

class Masters extends StatefulWidget {
  const Masters({super.key});
  @override
  State<Masters> createState() => _MastersState();
}

class _MastersState extends State<Masters> {
  String _tab = 'trucks';
  final _truck = TextEditingController();
  final _pump = TextEditingController();
  final _meterTruck = TextEditingController();

  Future<void> _addTruck() async {
    final n = normTruck(_truck.text);
    if (!validTruck(n)) return snack(context, 'Enter a valid vehicle number, e.g. HR 55 AB 1234', error: true);
    final ref = db.collection('trucks').doc(n);
    if ((await ref.get()).exists) {
      if (mounted) snack(context, '${prettyTruck(n)} is already in the list', error: true);
      return;
    }
    await ref.set({'number': n, 'driverId': '', 'driverName': '', 'createdAt': FieldValue.serverTimestamp()});
    _truck.clear();
    if (mounted) snack(context, 'Added ${prettyTruck(n)}');
  }

  Future<void> _addPump([String? name]) async {
    final p = (name ?? _pump.text).trim();
    if (p.length < 3) return snack(context, 'Type the pump name and place', error: true);
    await db.collection('pumps').add({'name': p, 'createdAt': FieldValue.serverTimestamp()});
    if (name == null) _pump.clear();
    if (mounted) snack(context, 'Pump added');
  }

  @override
  Widget build(BuildContext context) {
    final ro = !Session.isAdmin;
    return Scaffold(
      appBar: topBar('Trucks and pumps', sub: 'Masters'),
      body: PageBody(maxWidth: 720, children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'trucks', label: Text('Trucks')),
            ButtonSegment(value: 'pumps', label: Text('Pump list')),
          ],
          selected: {_tab},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
        if (_tab == 'trucks') ..._trucks(ro) else ..._pumps(ro),
      ]),
    );
  }

  Widget _truckRow(String id, Map<String, dynamic> t, Map<String, dynamic>? odo, bool ro) {
    final driver = (t['driverName'] ?? '').toString();
    final km = odo?['lastKm'] as num?;
    final at = (odo?['at'] as Timestamp?)?.toDate();
    final fixed = odo?['correctedBy'] != null;
    return Box(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(prettyTruck(id), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            Text(driver.isEmpty ? 'Not assigned' : driver, style: const TextStyle(fontSize: 13, color: cMuted)),
            Text(
              km == null
                  ? 'Meter: no reading yet'
                  : 'Meter: ${fmtNum(km)} km${at == null ? '' : ' · ${showDateTime(at)}'}${fixed ? ' · corrected by Admin' : ''}',
              style: const TextStyle(fontSize: 13, color: cMuted),
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          driver.isEmpty ? const Pill('Free', tone: Tone.info) : const Pill('Own', tone: Tone.ok),
          if (!ro) TextButton(onPressed: () => _correctMeter(id), child: const Text('Correct meter')),
        ]),
      ]),
    );
  }

  /// Admin sets the truck's last odometer reading (used to check the next entry).
  /// An open duty that started above the new reading is corrected too.
  Future<void> _correctMeter(String truck) async {
    final ref = db.collection('odometer').doc(truck);
    final cur = (await ref.get()).data();
    final oldKm = cur?['lastKm'] as num?;
    if (!mounted) return;
    final kmC = TextEditingController();
    final whyC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Correct meter · ${prettyTruck(truck)}'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(oldKm == null ? 'No reading saved yet.' : 'Saved last reading: ${fmtNum(oldKm)} km',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: kmC,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: inDec('Correct reading (km)', hint: 'Actual meter now, or the last correct reading'),
            ),
            const SizedBox(height: 10),
            TextField(controller: whyC, decoration: inDec('Reason', hint: 'e.g. driver typed 482500 instead of 48250')),
            const SizedBox(height: 10),
            const Text(
              'The driver\'s next entry must be above this reading. Old entries stay as they are; reject a wrong diesel entry in Approvals.',
              style: TextStyle(fontSize: 12.5, color: cMuted),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final km = parseNum(kmC.text);
    final why = whyC.text.trim();
    if (km == null || km < 0) return _err('Enter the correct reading in km.');
    if (why.isEmpty) return _err('Write the reason for the correction.');
    try {
      final b = db.batch();
      b.set(
        ref,
        {
          'lastKm': km,
          'at': FieldValue.serverTimestamp(),
          'by': 'admin',
          'correctedBy': Session.name,
          'correctedAt': FieldValue.serverTimestamp(),
          'reason': why,
          'history': FieldValue.arrayUnion([
            {'oldKm': oldKm, 'newKm': km, 'reason': why, 'by': Session.name, 'at': Timestamp.now()}
          ]),
        },
        SetOptions(merge: true),
      );
      final open = await db.collection('duties').where('truck', isEqualTo: truck).where('status', isEqualTo: 'open').get();
      var fixedDuties = 0;
      for (final d in open.docs) {
        final start = (d.data()['startKm'] as num?) ?? 0;
        if (start > km) {
          b.update(d.reference, {'startKm': km, 'startKmEntered': start, 'startKmCorrectedBy': Session.name});
          fixedDuties++;
        }
      }
      await b.commit();
      if (mounted) {
        snack(context,
            'Meter for ${prettyTruck(truck)} set to ${fmtNum(km)} km${fixedDuties > 0 ? ' · open duty start corrected' : ''}');
      }
    } catch (e) {
      _err(friendlyError(e));
    }
  }

  void _err(String m) {
    if (mounted) snack(context, m, error: true);
  }

  Widget _addRow(TextEditingController c, String hint, VoidCallback onAdd, {bool caps = false, String button = 'Add'}) => Row(children: [
        Expanded(
          child: TextField(
            controller: c,
            textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.words,
            decoration: inDec(hint),
            onSubmitted: (_) => onAdd(),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(height: 52, child: FilledButton(onPressed: onAdd, child: Text(button))),
      ]);

  List<Widget> _trucks(bool ro) => [
        if (!ro) _addRow(_truck, 'New vehicle number', _addTruck, caps: true),
        const Label('JTCPL trucks'),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('trucks').snapshots(),
          builder: (context, s) {
            final docs = s.data?.docs.toList() ?? [];
            docs.sort((a, b) => a.id.compareTo(b.id));
            if (docs.isEmpty) return const NoteBox('No trucks yet. Add each JTCPL vehicle number above.');
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db.collection('odometer').snapshots(),
              builder: (context, os) {
                final odo = {for (final o in os.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) o.id: o.data()};
                return Column(children: [
                  for (final d in docs) ...[
                    _truckRow(d.id, d.data(), odo[d.id], ro),
                    const SizedBox(height: 8),
                  ],
                ]);
              },
            );
          },
        ),
        if (!ro)
          const Text('Tap "Correct meter" if a driver entered a wrong (too high) odometer reading.',
              style: TextStyle(fontSize: 12.5, color: cMuted)),
        if (!ro) ...[
          const Label('Correct meter for any other vehicle (e.g. Temporary)'),
          _addRow(_meterTruck, 'Vehicle number', () {
            final n = normTruck(_meterTruck.text);
            if (!validTruck(n)) return snack(context, 'Enter a valid vehicle number', error: true);
            _correctMeter(n);
          }, caps: true, button: 'Correct'),
        ],
        const Label('Numbers entered under Temporary (last 7 days)'),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db
              .collection('diesel')
              .where('dateKey', isGreaterThanOrEqualTo: dateKey(DateTime.now().subtract(const Duration(days: 7))))
              .snapshots(),
          builder: (context, s) {
            final byTruck = <String, Set<String>>{};
            final inList = <String, bool>{};
            for (final d in s.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
              final x = d.data();
              if (x['truckType'] != 'temp') continue;
              final t = x['truck'] as String;
              byTruck.putIfAbsent(t, () => {}).add((x['driverName'] ?? '') as String);
              inList[t] = x['inList'] == true;
            }
            if (byTruck.isEmpty) return const NoteBox('No temporary entries in the last 7 days.');
            return KvCard([
              for (final e in byTruck.entries)
                (
                  '${prettyTruck(e.key)} · by ${e.value.join(', ')}',
                  inList[e.key] == true ? const Pill('In list', tone: Tone.ok) : const Pill('Not in list', tone: Tone.bad),
                ),
            ]);
          },
        ),
      ];

  List<Widget> _pumps(bool ro) => [
        if (!ro) _addRow(_pump, 'New pump name and place', _addPump),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('pumps').snapshots(),
          builder: (context, s) {
            final docs = s.data?.docs.toList() ?? [];
            docs.sort((a, b) => ((a.data()['name'] ?? '') as String).compareTo((b.data()['name'] ?? '') as String));
            if (docs.isEmpty) return const NoteBox('No pumps yet. Drivers will see only "Other" until you add pumps.');
            return KvCard([
              for (final d in docs)
                (
                  (d.data()['name'] ?? '') as String,
                  ro
                      ? const Pill('In list', tone: Tone.ok)
                      : IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            if (await confirmBox(context, 'Remove pump?', '${d.data()['name']} will no longer show for drivers. Old entries are kept.',
                                ok: 'Remove')) {
                              await d.reference.delete();
                            }
                          },
                        ),
                ),
            ]);
          },
        ),
        const Label('Typed by drivers as "Other"'),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('diesel').where('pumpOther', isEqualTo: true).snapshots(),
          builder: (context, s) {
            final counts = <String, int>{};
            for (final d in s.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
              final n = ((d.data()['pump'] ?? '') as String).trim();
              if (n.isNotEmpty) counts[n] = (counts[n] ?? 0) + 1;
            }
            if (counts.isEmpty) return const NoteBox('No "Other" pump names yet.');
            final list = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
            return KvCard([
              for (final e in list)
                (
                  '${e.key} · ${e.value} time${e.value == 1 ? '' : 's'}',
                  ro ? const SizedBox() : TextButton(onPressed: () => _addPump(e.key), child: const Text('Add to list')),
                ),
            ]);
          },
        ),
      ];
}
