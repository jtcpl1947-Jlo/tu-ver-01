import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/session.dart';
import '../../services/tracker.dart';
import 'diesel_form.dart';
import 'duty_end.dart';
import 'duty_start.dart';
import 'my_location.dart';

/// The truck a driver is working on: own (from Admin) or temporary (typed).
class TruckChoice {
  final String number; // normalised, e.g. HR55AB1234
  final String type; // own | temp
  final bool inList;
  const TruckChoice(this.number, this.type, this.inList);
}

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});
  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  /// Picks up truck changes made by Admin while the app is open.
  @override
  void initState() {
    super.initState();
    _profileSub = db.collection('users').doc(Session.driverId).snapshots().listen((d) {
      final t = (d.data()?['ownTruck'] ?? '') as String;
      if (t != Session.ownTruck && mounted) setState(() => Session.ownTruck = t);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _openDuty => db
      .collection('duties')
      .where('driverId', isEqualTo: Session.driverId)
      .where('status', isEqualTo: 'open')
      .snapshots();

  /// Duty is always on the driver's own truck (from Admin).
  TruckChoice? _ownTruck() {
    if (Session.ownTruck.isEmpty) {
      snack(context, bi('Admin ने आपकी गाड़ी नहीं जोड़ी है। Admin से कहें।', 'Admin has not assigned your own truck. Ask Admin.'), error: true);
      return null;
    }
    return TruckChoice(Session.ownTruck, 'own', true);
  }

  String _resumedFor = '';

  void _resumeTracking(Map<String, dynamic> duty, String id) {
    if (Tracker.running || _resumedFor == id) return;
    _resumedFor = id;
    Tracker.start(dutyId: id, truck: duty['truck'] as String, truckType: duty['truckType'] as String);
  }

  @override
  Widget build(BuildContext context) {
    final hi = appLang.value == 'hi';
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _openDuty,
      builder: (context, snap) {
        final open = (snap.data?.docs.isNotEmpty ?? false) ? snap.data!.docs.first : null;
        if (open != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _resumeTracking(open.data(), open.id));
        }
        return Scaffold(
          appBar: topBar(
            hi ? 'नमस्ते, ${Session.name}' : 'Hello, ${Session.name}',
            sub: open != null ? bi('ड्यूटी चालू', 'On duty') : bi('ड्यूटी बंद', 'Off duty'),
            dark: true,
            actions: [
              IconButton(
                tooltip: 'Language',
                icon: const Icon(Icons.translate),
                onPressed: () => appLang.value = hi ? 'en' : 'hi',
              ),
              IconButton(
                tooltip: 'Log out',
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  if (open != null) {
                    snack(context, bi('पहले ड्यूटी ख़त्म करें', 'End duty before logging out'), error: true);
                    return;
                  }
                  await Session.logout();
                },
              ),
            ],
          ),
          body: PageBody(children: open != null ? _onDuty(open) : _offDuty()),
        );
      },
    );
  }

  List<Widget> _offDuty() {
    return [
      Box(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(bi('मेरी गाड़ी', 'My truck'), style: const TextStyle(fontSize: 13, color: cMuted)),
              Text(Session.ownTruck.isEmpty ? bi('गाड़ी नहीं जुड़ी', 'Not assigned') : prettyTruck(Session.ownTruck),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1)),
            ]),
          ),
          const Pill('Own', tone: Tone.ok),
        ]),
      ),
      BigButton(
        appLang.value == 'hi' ? 'ड्यूटी शुरू करें' : 'Start duty',
        sub: bi('GPS शुरू होगा', 'GPS starts'),
        color: cGreen,
        onPressed: () {
          final t = _ownTruck();
          if (t != null) Navigator.push(context, MaterialPageRoute(builder: (_) => DutyStart(truck: t)));
        },
      ),
      Row(children: [
        Expanded(
          child: _square(Icons.local_gas_station_outlined, bi('डीज़ल भरें', 'Add diesel'),
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DieselForm()))),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _square(Icons.place_outlined, bi('मेरी लोकेशन', 'My location'),
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyLocation()))),
        ),
      ]),
      const _TodayCard(),
      NoteBox(bi('लोकेशन "हमेशा चालू" और बैटरी सेवर बंद रखें', 'Keep location "Allow all the time" and battery saver off.'),
          tone: Tone.warn),
    ];
  }

  List<Widget> _onDuty(QueryDocumentSnapshot<Map<String, dynamic>> open) {
    final d = open.data();
    final start = (d['start'] as Timestamp?)?.toDate();
    final truck = TruckChoice(d['truck'] as String, d['truckType'] as String, d['inList'] == true);
    return [
      Box(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(bi('ड्यूटी चालू', 'On duty'), style: const TextStyle(fontSize: 13, color: cMuted)),
              Text(prettyTruck(truck.number), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1)),
              if (start != null)
                Text('${bi('शुरू', 'Started')} ${showTime(start)} · ${fmtNum(d['startKm'] as num?)} km',
                    style: const TextStyle(fontSize: 13, color: cMuted)),
            ]),
          ),
          Pill(truck.type == 'own' ? 'Own' : 'Temp', tone: truck.type == 'own' ? Tone.ok : Tone.warn),
        ]),
      ),
      Row(children: [
        Expanded(
          child: _square(Icons.local_gas_station_outlined, bi('डीज़ल भरें', 'Add diesel'),
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => DieselForm(dutyId: open.id)))),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _square(Icons.place_outlined, bi('मेरी लोकेशन', 'My location'),
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyLocation()))),
        ),
      ]),
      const _TodayCard(),
      NoteBox(bi('हर 5 मिनट में लोकेशन भेजी जा रही है। ऐप बंद न करें।', 'Location is sent every 5 minutes. Do not force-close the app.')),
      BigButton(
        appLang.value == 'hi' ? 'ड्यूटी ख़त्म करें' : 'End duty',
        sub: bi('GPS बंद होगा', 'GPS stops'),
        outlined: true,
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DutyEnd(dutyId: open.id, duty: d))),
      ),
    ];
  }

  Widget _square(IconData icon, String label, VoidCallback onTap) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: cLine)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: cBlueBg, borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: cBlue),
              ),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

/// Today's km, diesel and the last diesel entry status.
class _TodayCard extends StatelessWidget {
  const _TodayCard();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('diesel').where('driverId', isEqualTo: Session.driverId).snapshots(),
      builder: (context, ds) {
        final docs = ds.data?.docs.map((d) => d.data()).toList() ?? [];
        docs.sort((a, b) => ((b['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
            .compareTo((a['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
        final today = dateKey(DateTime.now());
        final litres = docs.where((d) => d['dateKey'] == today).fold<double>(0, (s, d) => s + ((d['litres'] as num?) ?? 0));
        final last = docs.isNotEmpty ? docs.first : null;
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: db.collection('tracks').doc(Tracker.trackId(Session.driverId, DateTime.now())).snapshots(),
          builder: (context, ts) {
            final gpsKm = (ts.data?.data()?['gpsKm'] as num?) ?? 0;
            return KvCard([
              (bi('आज GPS km', 'GPS km today'), kvText(fmtNum(gpsKm))),
              (bi('आज डीज़ल', 'Diesel today'), kvText('${fmtNum(litres, dec: litres % 1 == 0 ? 0 : 1)} L')),
              (
                bi('पिछली एंट्री', 'Last entry'),
                last == null
                    ? kvText('-')
                    : Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                        kvText('${last['date']} · ${fmtNum(last['litres'] as num?)} L'),
                        statusPill(last['status'] as String?),
                      ])
              ),
            ]);
          },
        );
      },
    );
  }
}
