import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/photos.dart';
import '../../services/records.dart';
import '../../services/scan.dart';
import '../../services/session.dart';
import '../../services/tracker.dart';
import 'driver_home.dart';

const kOther = '__other__';

class DieselForm extends StatefulWidget {
  final String? dutyId;
  const DieselForm({super.key, this.dutyId});
  @override
  State<DieselForm> createState() => _DieselFormState();
}

class _DieselFormState extends State<DieselForm> {
  // Own truck by default; Temporary (typed number) is for diesel entries only.
  String _type = Session.ownTruck.isEmpty ? 'temp' : 'own';
  final _temp = TextEditingController();
  bool? _tempInList;
  String _lastFor = '';
  String _mode = 'scan';
  String? _pump;
  final _other = TextEditingController();
  final _slipNo = TextEditingController();
  final _date = TextEditingController(text: showDate(DateTime.now()));
  final _litres = TextEditingController();
  final _rate = TextEditingController();
  final _amount = TextEditingController();
  final _km = TextEditingController();
  PickedPhoto? _slip;
  PickedPhoto? _meter;
  double? _last;
  bool _busy = false;
  bool _scanning = false;
  String? _scanMsg;
  List<String> _pumps = [];

  /// The truck this entry is for, or null if the typed number is not valid yet.
  TruckChoice? get _truck {
    if (_type == 'own') return Session.ownTruck.isEmpty ? null : TruckChoice(Session.ownTruck, 'own', true);
    final n = normTruck(_temp.text);
    return validTruck(n) ? TruckChoice(n, 'temp', _tempInList ?? false) : null;
  }

  /// Loads the last odometer reading (and list check) for the selected truck.
  Future<void> _refreshTruck() async {
    final t = _truck;
    final key = t == null ? '' : '${t.type}:${t.number}';
    if (key == _lastFor) return;
    _lastFor = key;
    setState(() {
      _last = null;
      if (_type == 'temp') _tempInList = null;
    });
    if (t == null) return;
    final km = await lastKm(t.number);
    bool? inList;
    if (t.type == 'temp') inList = (await db.collection('trucks').doc(t.number).get()).exists;
    if (!mounted || _lastFor != key) return;
    setState(() {
      _last = km;
      if (t.type == 'temp') _tempInList = inList;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshTruck());
  }

  Future<void> _scan() async {
    final p = await takePhoto();
    if (p == null) return;
    setState(() {
      _slip = p;
      _scanMsg = null;
    });
    if (!scanSupported) {
      setState(() => _scanMsg = bi('स्लिप पढ़ना सिर्फ़ फ़ोन ऐप में होता है। नीचे खुद भरें।',
          'Slip reading works in the phone app only. Fill the details below.'));
      return;
    }
    setState(() => _scanning = true);
    try {
      final d = await scanSlip(p.file);
      if (d == null || d.found == 0) {
        _scanMsg = bi('स्लिप पढ़ी नहीं जा सकी। खुद भरें।', 'Could not read the slip. Fill the details yourself.');
      } else {
        if (d.litres != null) _litres.text = d.litres!.toString();
        if (d.rate != null) _rate.text = d.rate!.toString();
        if (d.amount != null) _amount.text = d.amount!.toString();
        if (d.slipNo != null) _slipNo.text = d.slipNo!;
        if (d.date != null) _date.text = d.date!;
        final match = matchPump(d.pumpText, _pumps);
        if (match != null) {
          _pump = match;
        } else if (d.pumpText != null) {
          _pump = kOther;
          _other.text = d.pumpText!;
        }
        _scanMsg = bi('${d.found} चीज़ें पढ़ी गईं। हर खाना जाँचें।', '${d.found} details read. Check every field.');
      }
    } catch (_) {
      _scanMsg = bi('स्लिप पढ़ी नहीं जा सकी। खुद भरें।', 'Could not read the slip. Fill the details yourself.');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  ({bool amountOk, bool kmOk, bool milOk, double? calc, double? run, double? mil}) _tally() {
    final l = parseNum(_litres.text), r = parseNum(_rate.text), a = parseNum(_amount.text), km = parseNum(_km.text);
    final calc = (l != null && r != null) ? l * r : null;
    final amountOk = calc != null && a != null && (calc - a).abs() <= 5;
    final kmOk = km != null && (_last == null || km > _last!);
    final run = (km != null && _last != null) ? km - _last! : null;
    final mil = (run != null && l != null && l > 0) ? run / l : null;
    final milOk = mil == null || (mil >= 2.5 && mil <= 7);
    return (amountOk: amountOk, kmOk: kmOk, milOk: milOk, calc: calc, run: run, mil: mil);
  }

  Future<void> _save() async {
    final l = parseNum(_litres.text), r = parseNum(_rate.text), a = parseNum(_amount.text), km = parseNum(_km.text);
    final truck = _truck;
    String? err;
    if (truck == null) {
      err = _type == 'own'
          ? bi('Admin ने आपकी गाड़ी नहीं जोड़ी है। Temporary चुनें।', 'No own truck assigned. Choose Temporary.')
          : bi('सही गाड़ी नंबर लिखें, जैसे HR 55 AB 1234', 'Enter a valid vehicle number, e.g. HR 55 AB 1234');
    }
    if (_pump == null || (_pump == kOther && _other.text.trim().isEmpty)) err ??= bi('पंप चुनें या नाम लिखें', 'Choose a pump or type its name');
    if (l == null || l <= 0) err ??= bi('लीटर लिखें', 'Enter litres');
    if (r == null || r <= 0) err ??= bi('रेट लिखें', 'Enter rate');
    if (a == null || a <= 0) err ??= bi('रकम लिखें', 'Enter amount');
    if (km == null || km <= 0) err ??= bi('मीटर km लिखें', 'Enter odometer km');
    if (km != null && _last != null && km <= _last!) {
      err ??= bi('मीटर रीडिंग पिछली (${fmtNum(_last)}) से ज़्यादा होनी चाहिए', 'Odometer must be higher than last (${fmtNum(_last)})');
    }
    if (_slip == null) err ??= bi('स्लिप की फ़ोटो लें', 'Take the slip photo');
    if (_meter == null) err ??= bi('मीटर की फ़ोटो लें', 'Take the meter photo');
    if (err != null) return snack(context, err, error: true);
    final tr = truck!;

    final t = _tally();
    final flags = <String>[
      if (!t.amountOk) 'amount_mismatch',
      if (!t.milOk) 'mileage_unusual',
      if (_pump == kOther) 'pump_other',
      if (tr.type == 'temp' && !tr.inList) 'temp_not_in_list',
    ];
    setState(() => _busy = true);
    try {
      final slipId = await savePhoto(_slip!, 'diesel_slip');
      final meterId = await savePhoto(_meter!, 'odometer_diesel');
      final pos = await Tracker.currentPosition();
      final now = DateTime.now();
      final b = db.batch();
      b.set(db.collection('diesel').doc(), {
        'driverId': Session.driverId,
        'driverName': Session.name,
        'uid': Session.uid,
        'dutyId': tr.type == 'own' ? widget.dutyId : null,
        'truck': tr.number,
        'truckType': tr.type,
        'inList': tr.inList,
        'pump': _pump == kOther ? _other.text.trim() : _pump,
        'pumpOther': _pump == kOther,
        'slipNo': _slipNo.text.trim(),
        'date': _date.text.trim(),
        'dateKey': dateKey(now),
        'litres': l,
        'rate': r,
        'amount': a,
        'odometer': km,
        'prevKm': _last,
        'kmSinceLast': t.run,
        'mileage': t.mil == null ? null : double.parse(t.mil!.toStringAsFixed(2)),
        'entryMode': _mode,
        'slipPhotoId': slipId,
        'meterPhotoId': meterId,
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'flags': flags,
        'status': 'pending',
        'createdAt': Timestamp.fromDate(now),
      });
      setLastKm(b, tr.number, km!);
      await b.commit();
      if (mounted) {
        snack(context, bi('सेव हुआ। Admin मंज़ूरी देगा।', 'Saved. Sent to Admin for approval.'));
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
    final t = _truck;
    final tally = _tally();
    return Scaffold(
      appBar: topBar(bi('डीज़ल एंट्री', 'Diesel entry'),
          sub: t == null ? null : '${prettyTruck(t.number)} · ${t.type == 'own' ? 'Own' : 'Temp'}'),
      body: PageBody(children: [
        Label(bi('किस गाड़ी में डीज़ल?', 'Diesel for which truck?')),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
                value: 'own',
                enabled: Session.ownTruck.isNotEmpty,
                label: Text(Session.ownTruck.isEmpty ? 'Own' : '${bi('मेरी', 'Own')} ${prettyTruck(Session.ownTruck)}')),
            const ButtonSegment(value: 'temp', label: Text('Temporary')),
          ],
          selected: {_type},
          showSelectedIcon: false,
          onSelectionChanged: (v) {
            setState(() => _type = v.first);
            _refreshTruck();
          },
        ),
        if (_type == 'temp') ...[
          TextField(
            controller: _temp,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: 1),
            decoration: inDec(bi('गाड़ी नंबर', 'Temporary vehicle number'), hint: 'UP 14 LT 5281'),
            onChanged: (_) => _refreshTruck(),
          ),
          if (_tempInList == true)
            Text(bi('✓ JTCPL list में है', '✓ Found in JTCPL vehicle list'),
                style: const TextStyle(color: Color(0xFF14532D), fontWeight: FontWeight.w600, fontSize: 13)),
          if (_tempInList == false)
            Text(bi('यह नंबर JTCPL list में नहीं है। Admin को दिखेगा।', 'Not in the JTCPL list. Admin will be told.'),
                style: const TextStyle(color: cAmber, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'scan', label: Text(bi('स्लिप स्कैन', 'Scan slip'))),
            ButtonSegment(value: 'manual', label: Text(bi('खुद भरें', 'Fill manually'))),
          ],
          selected: {_mode},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        if (_mode == 'scan')
          _scanning
              ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
              : PhotoButton(
                  photo: _slip,
                  emptyText: bi('+ स्लिप की फ़ोटो लें, ऐप पढ़ेगा', '+ Photograph the slip; the app reads it'),
                  doneText: bi('✓ स्लिप स्कैन हुई', '✓ Slip scanned'),
                  onTap: _scan,
                )
        else ...[
          NoteBox(bi('सारी जानकारी खुद भरें। स्लिप की फ़ोटो फिर भी ज़रूरी है।', 'Type all details. Slip photo is still required.')),
          PhotoButton(
            photo: _slip,
            emptyText: bi('+ स्लिप की फ़ोटो', '+ Add slip photo'),
            doneText: bi('✓ स्लिप फ़ोटो', '✓ Slip photo'),
            onTap: () async {
              final p = await takePhoto();
              if (p != null) setState(() => _slip = p);
            },
          ),
        ],
        if (_scanMsg != null && _mode == 'scan') NoteBox(_scanMsg!, tone: Tone.warn),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('pumps').snapshots(),
          builder: (context, s) {
            _pumps = (s.data?.docs.map((d) => (d.data()['name'] ?? '') as String).where((n) => n.isNotEmpty).toList() ?? [])..sort();
            final value = (_pump == null || _pump == kOther || _pumps.contains(_pump)) ? _pump : null;
            return DropdownButtonFormField<String>(
              value: value,
              isExpanded: true,
              decoration: inDec(bi('पंप', 'Pump')),
              items: [
                for (final p in _pumps) DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: kOther, child: Text(bi('Other · दूसरा पंप', 'Other (type name)'))),
              ],
              onChanged: (v) => setState(() => _pump = v),
            );
          },
        ),
        if (_pump == kOther)
          TextField(controller: _other, decoration: inDec(bi('पंप का नाम लिखें', 'Type pump name'), hint: 'e.g. Jai Ambe Filling Station, Shahpura')),
        _two(
          TextField(controller: _slipNo, decoration: inDec(bi('स्लिप नंबर', 'Slip no.'))),
          TextField(controller: _date, decoration: inDec(bi('तारीख', 'Date'), hint: 'dd-mm-yyyy')),
        ),
        _two(
          _numField(_litres, bi('लीटर', 'Litres')),
          _numField(_rate, bi('रेट ₹/L', 'Rate ₹/L')),
        ),
        _numField(_amount, bi('रकम ₹ (स्लिप पर)', 'Amount ₹ (on slip)')),
        _two(
          _numField(_km, bi('मीटर km', 'Odometer km')),
          PhotoButton(
            photo: _meter,
            height: 56,
            emptyText: bi('+ मीटर फ़ोटो', '+ Meter photo'),
            doneText: '✓',
            onTap: () async {
              final p = await takePhoto();
              if (p != null) setState(() => _meter = p);
            },
          ),
        ),
        Box(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(bi('मिलान', 'Auto-tally'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            const SizedBox(height: 6),
            _check(
              tally.calc == null ? null : tally.amountOk,
              tally.calc == null
                  ? bi('लीटर और रेट लिखें', 'Enter litres and rate')
                  : '${_litres.text} L × ₹${_rate.text} = ₹${fmtNum(tally.calc, dec: 2)}'
                      '${tally.amountOk ? bi(' · स्लिप से मेल', ' · matches slip') : bi(' · स्लिप पर ₹${_amount.text}', ' · slip says ₹${_amount.text}')}',
            ),
            _check(
              parseNum(_km.text) == null ? null : tally.kmOk,
              _last == null
                  ? bi('इस गाड़ी की पहली मीटर रीडिंग', 'First odometer reading for this truck')
                  : tally.kmOk
                      ? bi('मीटर पिछली (${fmtNum(_last)}) से ज़्यादा', 'Odometer higher than last (${fmtNum(_last)})')
                      : bi('मीटर पिछली (${fmtNum(_last)}) से कम — मान्य नहीं', 'Odometer lower than last (${fmtNum(_last)}) — not allowed'),
            ),
            if (tally.run != null && tally.kmOk)
              _check(
                tally.milOk,
                '${fmtNum(tally.run)} km ${bi('पिछली एंट्री से', 'since last entry')} · ${tally.mil?.toStringAsFixed(1) ?? '-'} km/L'
                '${tally.milOk ? '' : bi(' · असामान्य, Admin जाँचेगा', ' · unusual, Admin will check')}',
              ),
          ]),
        ),
        BigButton(appLang.value == 'hi' ? 'सेव करें' : 'Save', sub: bi('Admin की मंज़ूरी के लिए', 'Goes to Admin for approval'),
            color: cGreen, busy: _busy, onPressed: _save),
      ]),
    );
  }

  Widget _numField(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: inDec(label),
        onChanged: (_) => setState(() {}),
      );

  Widget _two(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: a),
        const SizedBox(width: 10),
        Expanded(child: b),
      ]);

  Widget _check(bool? ok, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
                color: ok == null ? cField : (ok ? cGreen : const Color(0xFFB91C1C)), shape: BoxShape.circle),
            child: Icon(ok == false ? Icons.priority_high : Icons.check, size: 12, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ]),
      );
}
