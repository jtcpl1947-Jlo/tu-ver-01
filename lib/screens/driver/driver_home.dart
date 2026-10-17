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
  String _type = 'own';
  final _temp = TextEditingController();
  bool? _tempInList;
  String _checked = '';

  Stream<QuerySnapshot<Map<String, dynamic>>> get _openDuty => db
      .collection('duties')
      .where('driverId', isEqualTo: Session.driverId)
      .where('status', isEqualTo: 'open')
      .snapshots();

  Future<void> _checkTemp() async {
    final n = normTruck(_temp.text);
    if (!validTruck(n)) {
      setState(() => _tempInList = null);
      return;
    }
    if (n == _checked) return;
    _checked = n;
    final d = await db.collection('trucks').doc(n).get();
    if (mounted && _checked == n) setState(() => _tempInList = d.exists);
  }

  /// Returns the selected truck, or null after showing why it is not ready.
  TruckChoice? _selected() {
    if (_type == 'own') {
      if (Session.ownTruck.isEmpty) {
        snack(context, bi('Admin ने आपकी गाड़ी नहीं जोड़ी है। Temporary चुनें।', 'Admin has not assigned your own truck. Choose Temporary.'), error: true);
        return null;
      }
      return TruckChoice(Session.ownTruck, 'own', true);
    }
    final n = normTruck(_temp.text);
    if (!validTruck(n)) {
      snack(context, bi('सही गाड़ी नंबर लिखें, जैसे HR 55 AB 1234', 'Enter a valid vehicle number, e.g. HR 55 AB 1234'), error: true);
      return null;
    }
    return TruckChoice(n, 'temp', _tempInList ?? false);
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
      Label(bi('आज कौन सी गाड़ी?', 'Which truck today?')),
      _truckOption(
        'own',
        Session.ownTruck.isEmpty ? bi('गाड़ी नहीं जुड़ी', 'Not assigned') : prettyTruck(Session.ownTruck),
        bi('मेरी गाड़ी', 'Own truck (from Admin)'),
        const Pill('Own', tone: Tone.ok),
      ),
      _truckOption('temp', 'Temporary', bi('दूसरी गाड़ी · गाड़ी नंबर लिखें', 'Type the vehicle number'),
          const Pill('Temp', tone: Tone.warn)),
      if (_type == 'temp') ...[
        TextField(
          controller: _temp,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1),
          decoration: inDec(bi('गाड़ी नंबर', 'Temporary vehicle number'), hint: 'RJ 14 GC 5521'),
          onChanged: (_) => _checkTemp(),
        ),
        if (_tempInList == true)
          Text(bi('✓ JTCPL list में है', '✓ Found in JTCPL vehicle list'),
              style: const TextStyle(color: Color(0xFF14532D), fontWeight: FontWeight.w600, fontSize: 13)),
        if (_tempInList == false)
          Text(bi('यह नंबर JTCPL list में नहीं है। Admin को दिखेगा।', 'Not in the JTCPL list. Admin will be told.'),
              style: const TextStyle(color: cAmber, fontWeight: FontWeight.w600, fontSize: 13)),
      ],
      BigButton(
        appLang.value == 'hi' ? 'ड्यूटी शुरू करें' : 'Start duty',
        sub: bi('GPS शुरू होगा', 'GPS starts'),
        color: cGreen,
        onPressed: () {
          final t = _selected();
          if (t != null) Navigator.push(context, MaterialPageRoute(builder: (_) => DutyStart(truck: t)));
        },
      ),
      Row(children: [
        Expanded(
          child: _square(Icons.local_gas_station_outlined, bi('डीज़ल भरें', 'Add diesel'), () {
            final t = _selected();
            if (t != null) Navigator.push(context, MaterialPageRoute(builder: (_) => DieselForm(truck: t)));
          }),
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
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => DieselForm(truck: truck, dutyId: open.id)))),
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

  Widget _truckOption(String value, String title, String sub, Widget pill) {
    final on = _type == value;
    return Material(
      color: on ? cBlueBg : Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14), side: BorderSide(color: on ? cBlue : cLine, width: on ? 2 : 1.5)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _type = value),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(on ? Icons.radio_button_checked : Icons.radio_button_off, color: on ? cBlue : cField),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: .5)),
                Text(sub, style: const TextStyle(fontSize: 12.5, color: cMuted)),
              ]),
            ),
            pill,
          ]),
        ),
      ),
    );
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
