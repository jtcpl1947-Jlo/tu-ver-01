import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/photos.dart';
import '../../services/records.dart';
import '../../services/session.dart';
import '../../services/tracker.dart';

class DutyEnd extends StatefulWidget {
  final String dutyId;
  final Map<String, dynamic> duty;
  const DutyEnd({super.key, required this.dutyId, required this.duty});
  @override
  State<DutyEnd> createState() => _DutyEndState();
}

class _DutyEndState extends State<DutyEnd> {
  final _km = TextEditingController();
  PickedPhoto? _photo;
  bool _busy = false;
  Map<String, dynamic>? _summary;

  double get _startKm => ((widget.duty['startKm'] as num?) ?? 0).toDouble();

  Future<void> _end() async {
    final km = parseNum(_km.text);
    if (km == null || km < _startKm) {
      return snack(context, bi('रीडिंग शुरू की रीडिंग (${fmtNum(_startKm)}) से कम नहीं हो सकती', 'Reading cannot be lower than start (${fmtNum(_startKm)})'),
          error: true);
    }
    if (_photo == null) return snack(context, bi('मीटर की फ़ोटो लें', 'Take the meter photo'), error: true);
    setState(() => _busy = true);
    try {
      final photoId = await savePhoto(_photo!, 'odometer_end');
      final start = (widget.duty['start'] as Timestamp).toDate();
      final now = DateTime.now();
      // GPS km and gaps from the day's track(s) covering this duty.
      var gpsKm = 0.0;
      final points = <dynamic>[];
      for (var day = DateTime(start.year, start.month, start.day); !day.isAfter(now); day = day.add(const Duration(days: 1))) {
        final t = await db.collection('tracks').doc(Tracker.trackId(Session.driverId, day)).get();
        final td = t.data();
        if (td != null && (td['dutyId'] == widget.dutyId || td['dutyId'] == null)) {
          gpsKm += ((td['gpsKm'] as num?) ?? 0).toDouble();
          points.addAll((td['points'] as List?) ?? []);
        }
      }
      final off = locationOffMinutes(points, start, now);
      final odoKm = km - _startKm;
      final b = db.batch();
      final data = {
        'status': 'closed',
        'end': Timestamp.fromDate(now),
        'endKm': km,
        'endPhotoId': photoId,
        'odoKm': odoKm,
        'gpsKm': double.parse(gpsKm.toStringAsFixed(1)),
        'locationOffMin': off,
      };
      b.update(db.collection('duties').doc(widget.dutyId), data);
      setLastKm(b, widget.duty['truck'] as String, km);
      await b.commit();
      await Tracker.stop();

      final diesel = await db.collection('diesel').where('driverId', isEqualTo: Session.driverId).get();
      final mine = diesel.docs.map((d) => d.data()).where((d) {
        final c = (d['createdAt'] as Timestamp?)?.toDate();
        return c != null && !c.isBefore(start);
      }).toList();
      final litres = mine.fold<double>(0, (s, d) => s + ((d['litres'] as num?) ?? 0));
      setState(() => _summary = {
            ...data,
            'start': start,
            'endAt': now,
            'litres': litres,
            'entries': mine.length,
            'pending': mine.where((d) => d['status'] == 'pending').length,
          });
    } catch (e) {
      if (mounted) snack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final truck = prettyTruck(widget.duty['truck'] as String);
    final type = widget.duty['truckType'] == 'own' ? 'Own' : 'Temp';
    final s = _summary;
    return Scaffold(
      appBar: topBar(bi('ड्यूटी ख़त्म', 'End duty'), sub: '$truck · $type'),
      body: PageBody(children: s == null ? _form() : _done(s)),
    );
  }

  List<Widget> _form() => [
        TextField(
          controller: _km,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          decoration: inDec(bi('मीटर रीडिंग (km)', 'Odometer now (km)')),
        ),
        NoteBox(bi('शुरू की रीडिंग ${fmtNum(_startKm)} km', 'Start reading ${fmtNum(_startKm)} km')),
        PhotoButton(
          photo: _photo,
          emptyText: bi('+ मीटर की फ़ोटो लें', '+ Take meter photo'),
          doneText: bi('✓ मीटर फ़ोटो', '✓ Meter photo'),
          onTap: () async {
            final p = await takePhoto();
            if (p != null) setState(() => _photo = p);
          },
        ),
        BigButton(appLang.value == 'hi' ? 'ड्यूटी ख़त्म करें' : 'End duty', sub: bi('GPS बंद होगा', 'GPS stops'), busy: _busy, onPressed: _end),
      ];

  List<Widget> _done(Map<String, dynamic> s) {
    final odo = (s['odoKm'] as num).toDouble();
    final litres = (s['litres'] as num).toDouble();
    final dur = (s['endAt'] as DateTime).difference(s['start'] as DateTime);
    return [
      NoteBox(bi('ड्यूटी ख़त्म हुई', 'Duty ended'), tone: Tone.ok),
      Label(bi('आज का सारांश', "Today's summary")),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.1,
        children: [
          Tile(fmtNum(odo), bi('मीटर km', 'Odometer km')),
          Tile(fmtNum(s['gpsKm'] as num), 'GPS km'),
          Tile('${fmtNum(litres)} L', bi('डीज़ल', 'Diesel')),
          Tile(litres > 0 ? (odo / litres).toStringAsFixed(1) : '-', bi('km/L माइलेज', 'km/L mileage')),
        ],
      ),
      KvCard([
        (bi('ड्यूटी', 'Duty'), kvText('${showTime(s['start'] as DateTime)} – ${showTime(s['endAt'] as DateTime)} · ${dur.inHours} h ${dur.inMinutes % 60} m')),
        (bi('लोकेशन बंद', 'Location off'), kvText('${s['locationOffMin']} min')),
        (bi('डीज़ल एंट्री', 'Diesel entries'), kvText('${s['entries']} · ${s['pending']} pending')),
      ]),
      BigButton(bi('होम पर जाएँ', 'Back to home'), onPressed: () => Navigator.pop(context)),
    ];
  }
}
