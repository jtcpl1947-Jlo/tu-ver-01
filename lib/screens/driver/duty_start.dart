import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/photos.dart';
import '../../services/records.dart';
import '../../services/session.dart';
import '../../services/tracker.dart';
import 'driver_home.dart';

class DutyStart extends StatefulWidget {
  final TruckChoice truck;
  const DutyStart({super.key, required this.truck});
  @override
  State<DutyStart> createState() => _DutyStartState();
}

class _DutyStartState extends State<DutyStart> {
  final _km = TextEditingController();
  PickedPhoto? _photo;
  double? _last;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    lastKm(widget.truck.number).then((v) {
      if (mounted) setState(() {
        _last = v;
        _loaded = true;
      });
    });
  }

  Future<void> _start() async {
    final km = parseNum(_km.text);
    if (km == null || km <= 0) return snack(context, bi('मीटर रीडिंग लिखें', 'Enter the odometer reading'), error: true);
    if (_last != null && km < _last!) {
      return snack(context, bi('रीडिंग पिछली (${fmtNum(_last)}) से कम नहीं हो सकती', 'Reading cannot be lower than last (${fmtNum(_last)})'),
          error: true);
    }
    if (_photo == null) return snack(context, bi('मीटर की फ़ोटो लें', 'Take the meter photo'), error: true);
    final perm = await Tracker.checkPermission();
    if (perm != null) {
      if (mounted) snack(context, perm, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final photoId = await savePhoto(_photo!, 'odometer_start');
      final pos = await Tracker.currentPosition();
      final now = DateTime.now();
      final ref = db.collection('duties').doc();
      final b = db.batch();
      b.set(ref, {
        'driverId': Session.driverId,
        'driverName': Session.name,
        'uid': Session.uid,
        'truck': widget.truck.number,
        'truckType': widget.truck.type,
        'inList': widget.truck.inList,
        'status': 'open',
        'dateKey': dateKey(now),
        'start': Timestamp.fromDate(now),
        'startKm': km,
        'startPhotoId': photoId,
        'prevKm': _last,
        'startLat': pos?.latitude,
        'startLng': pos?.longitude,
      });
      setLastKm(b, widget.truck.number, km);
      await b.commit();
      await Tracker.start(dutyId: ref.id, truck: widget.truck.number, truckType: widget.truck.type);
      if (mounted) {
        snack(context, bi('ड्यूटी शुरू हुई', 'Duty started'));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) snack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final km = parseNum(_km.text);
    final t = widget.truck;
    return Scaffold(
      appBar: topBar(bi('ड्यूटी शुरू', 'Start duty'), sub: '${prettyTruck(t.number)} · ${t.type == 'own' ? 'Own' : 'Temp'}'),
      body: PageBody(children: [
        TextField(
          controller: _km,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          decoration: inDec(bi('मीटर रीडिंग (km)', 'Odometer now (km)')),
          onChanged: (_) => setState(() {}),
        ),
        if (_loaded)
          _last == null
              ? NoteBox(bi('इस गाड़ी की पहली रीडिंग', 'First reading for this truck'))
              : (km != null && km < _last!)
                  ? NoteBox(bi('पिछली रीडिंग ${fmtNum(_last)} km है। नई रीडिंग कम है — मान्य नहीं।',
                      'Last reading ${fmtNum(_last)} km. New reading is lower — not allowed.'), tone: Tone.bad)
                  : NoteBox(bi('पिछली रीडिंग ${fmtNum(_last)} km', 'Last reading ${fmtNum(_last)} km'), tone: Tone.ok),
        Label(bi('मीटर की फ़ोटो (ज़रूरी)', 'Meter photo (required)')),
        PhotoButton(
          photo: _photo,
          emptyText: bi('+ मीटर की फ़ोटो लें', '+ Take meter photo'),
          doneText: bi('✓ फ़ोटो ली गई', '✓ Photo taken'),
          onTap: () async {
            final p = await takePhoto();
            if (p != null) setState(() => _photo = p);
          },
        ),
        NoteBox(bi('ड्यूटी चालू रहने तक हर 5 मिनट में लोकेशन भेजी जाएगी। नेटवर्क न हो तो बाद में भेजी जाएगी।',
            'Location is sent every 5 minutes while on duty; saved and sent later if there is no network.')),
        BigButton(appLang.value == 'hi' ? 'ड्यूटी शुरू करें' : 'Start duty', color: cGreen, busy: _busy, onPressed: _start),
      ]),
    );
  }
}
