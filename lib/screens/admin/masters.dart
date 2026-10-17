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

  Widget _addRow(TextEditingController c, String hint, VoidCallback onAdd, {bool caps = false}) => Row(children: [
        Expanded(
          child: TextField(
            controller: c,
            textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.words,
            decoration: inDec(hint),
            onSubmitted: (_) => onAdd(),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(height: 52, child: FilledButton(onPressed: onAdd, child: const Text('Add'))),
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
            return KvCard([
              for (final d in docs)
                (
                  '${prettyTruck(d.id)}\n${(d.data()['driverName'] ?? '').toString().isEmpty ? 'Not assigned' : d.data()['driverName']}',
                  (d.data()['driverName'] ?? '').toString().isEmpty ? const Pill('Free', tone: Tone.info) : const Pill('Own', tone: Tone.ok),
                ),
            ]);
          },
        ),
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
