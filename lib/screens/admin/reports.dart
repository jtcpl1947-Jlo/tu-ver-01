import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/ui.dart';
import '../../services/export.dart';
import '../../services/session.dart';
import 'approvals.dart';

const reportNames = {
  'diesel': '1. Diesel report',
  'trip': '2. Daily trip report',
  'mileage': '3. Truck mileage report',
  'temp': '4. Temporary truck report',
  'exc': '5. Exception report',
};

class Reports extends StatefulWidget {
  const Reports({super.key});
  @override
  State<Reports> createState() => _ReportsState();
}

class _ReportsState extends State<Reports> {
  String _type = 'diesel';
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _driver = '';
  String _truck = '';
  ReportData? _data;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  String _dmy(String key) {
    try {
      return showDate(DateTime.parse(key));
    } catch (_) {
      return key;
    }
  }

  bool _keep(Map<String, dynamic> d) =>
      (_driver.isEmpty || d['driverId'] == _driver) && (_truck.isEmpty || d['truck'] == _truck);

  Future<List<Map<String, dynamic>>> _fetch(String col) async {
    final q = await db
        .collection(col)
        .where('dateKey', isGreaterThanOrEqualTo: dateKey(_from))
        .where('dateKey', isLessThanOrEqualTo: dateKey(_to))
        .get();
    final list = q.docs.map((d) => d.data()).where(_keep).toList();
    list.sort((a, b) {
      final c = ((a['dateKey'] ?? '') as String).compareTo((b['dateKey'] ?? '') as String);
      if (c != 0) return c;
      final ta = ((a['createdAt'] ?? a['start']) as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      final tb = ((b['createdAt'] ?? b['start']) as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      return ta.compareTo(tb);
    });
    return list;
  }

  String _status(String? s) => switch (s) { 'approved' => 'Approved', 'rejected' => 'Rejected', _ => 'Pending' };

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final title = reportNames[_type]!;
      ReportData r;
      switch (_type) {
        case 'diesel': {
          final rows = await _fetch('diesel');
          r = ReportData(title, [
            'Date', 'Slip no.', 'Truck no.', 'Own/Temp', 'Driver', 'Pump', 'Litres', 'Rate ₹/L', 'Amount ₹', 'Odometer', 'Km since last', 'km/L', 'Status'
          ], [
            for (final d in rows)
              [
                d['date'], d['slipNo'], prettyTruck(d['truck'] as String), d['truckType'] == 'own' ? 'Own' : 'Temp', d['driverName'],
                d['pump'], d['litres'], d['rate'], d['amount'], d['odometer'], d['kmSinceLast'], d['mileage'], _status(d['status'] as String?)
              ]
          ]);
        }
        case 'trip': {
          final rows = await _fetch('duties');
          r = ReportData(title, [
            'Date', 'Driver', 'Truck no.', 'Own/Temp', 'Duty start', 'Duty end', 'Start km', 'End km', 'Odometer km', 'GPS km', 'Difference km', 'Location off (min)'
          ], [
            for (final d in rows)
              [
                _dmy(d['dateKey'] as String),
                d['driverName'],
                prettyTruck(d['truck'] as String),
                d['truckType'] == 'own' ? 'Own' : 'Temp',
                (d['start'] as Timestamp?) == null ? '' : showTime((d['start'] as Timestamp).toDate()),
                (d['end'] as Timestamp?) == null ? 'On duty' : showTime((d['end'] as Timestamp).toDate()),
                d['startKm'],
                d['endKm'],
                d['odoKm'],
                d['gpsKm'],
                (d['odoKm'] is num && d['gpsKm'] is num) ? double.parse(((d['odoKm'] as num) - (d['gpsKm'] as num)).toStringAsFixed(1)) : null,
                d['locationOffMin'],
              ]
          ]);
        }
        case 'mileage': {
          final rows = await _fetch('diesel');
          final groups = <String, List<Map<String, dynamic>>>{};
          for (final d in rows) {
            final month = (d['dateKey'] as String).substring(0, 7);
            groups.putIfAbsent('$month|${d['truck']}', () => []).add(d);
          }
          final keys = groups.keys.toList()..sort();
          r = ReportData(title, ['Month', 'Truck no.', 'Total km', 'Litres', 'Amount ₹', 'Avg km/L', 'Fills', 'Drivers who filled'], [
            for (final k in keys)
              () {
                final g = groups[k]!;
                final km = g.fold<double>(0, (s, d) => s + ((d['kmSinceLast'] as num?) ?? 0));
                final litres = g.fold<double>(0, (s, d) => s + ((d['litres'] as num?) ?? 0));
                final amount = g.fold<double>(0, (s, d) => s + ((d['amount'] as num?) ?? 0));
                final who = <String, int>{};
                final temp = <String, bool>{};
                for (final d in g) {
                  final n = (d['driverName'] ?? '') as String;
                  who[n] = (who[n] ?? 0) + 1;
                  if (d['truckType'] == 'temp') temp[n] = true;
                }
                return [
                  DateFormat('MMM yyyy').format(DateTime.parse('${k.split('|')[0]}-01')),
                  prettyTruck(k.split('|')[1]),
                  km,
                  double.parse(litres.toStringAsFixed(2)),
                  double.parse(amount.toStringAsFixed(2)),
                  litres > 0 && km > 0 ? double.parse((km / litres).toStringAsFixed(2)) : null,
                  g.length,
                  who.entries.map((e) => '${e.key} (${e.value}${temp[e.key] == true ? ' Temp' : ''})').join(', '),
                ];
              }()
          ]);
        }
        case 'temp': {
          final rows = (await _fetch('diesel')).where((d) => d['truckType'] == 'temp').toList();
          r = ReportData(title, ['Date', 'Vehicle no. (typed)', 'In JTCPL list?', 'Driver', 'Pump', 'Litres', 'Amount ₹', 'Odometer', 'Status'], [
            for (final d in rows)
              [
                d['date'], prettyTruck(d['truck'] as String), d['inList'] == true ? 'Yes' : 'No', d['driverName'], d['pump'], d['litres'],
                d['amount'], d['odometer'], _status(d['status'] as String?)
              ]
          ]);
        }
        default: {
          final diesel = await _fetch('diesel');
          final duties = await _fetch('duties');
          final out = <List<Object?>>[];
          for (final d in diesel) {
            for (final f in ((d['flags'] as List?) ?? []).cast<String>()) {
              final detail = switch (f) {
                'amount_mismatch' =>
                  '${d['litres']} L × ₹${d['rate']} = ₹${fmtNum(((d['litres'] as num) * (d['rate'] as num)), dec: 2)}, slip ₹${d['amount']}',
                'mileage_unusual' => '${d['mileage']} km/L over ${fmtNum(d['kmSinceLast'] as num?)} km',
                'pump_other' => '${d['pump']}',
                _ => 'Typed by driver',
              };
              out.add([d['date'], d['driverName'], prettyTruck(d['truck'] as String), flagText[f] ?? f, detail, 'Check']);
            }
          }
          for (final d in duties) {
            final odo = (d['odoKm'] as num?)?.toDouble();
            final gps = (d['gpsKm'] as num?)?.toDouble();
            if (odo != null && gps != null && odo > 0) {
              final gap = (odo - gps).abs();
              if (gap > 10 && gap / odo > 0.05) {
                out.add([_dmy(d['dateKey'] as String), d['driverName'], prettyTruck(d['truck'] as String), 'Odometer vs GPS gap',
                  '${fmtNum(gap)} km ${odo > gps ? 'more on meter' : 'more on GPS'}', 'Check']);
              }
            }
            final off = (d['locationOffMin'] as num?) ?? 0;
            if (off > 30) {
              out.add([_dmy(d['dateKey'] as String), d['driverName'], prettyTruck(d['truck'] as String), 'Location off', '$off min on duty', 'Call driver']);
            }
          }
          r = ReportData(title, ['Date', 'Driver', 'Truck no.', 'Exception', 'Detail', 'Action'], out);
        }
      }
      setState(() => _data = r);
    } catch (e) {
      if (mounted) snack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _cell(Object? c) {
    if (c == null) return '';
    if (c is int) return fmtNum(c);
    if (c is double) return c == c.roundToDouble() ? fmtNum(c) : fmtNum(c, dec: 2);
    return c.toString();
  }

  String get _fileName => '${reportNames[_type]!.substring(3).replaceAll(' ', '_')}_${dateKey(_from)}_to_${dateKey(_to)}';
  String get _subtitle => '${showDate(_from)} to ${showDate(_to)}${_driver.isEmpty ? '' : ' · one driver'}${_truck.isEmpty ? '' : ' · ${prettyTruck(_truck)}'}';

  Future<void> _download(bool excel) async {
    final d = _data;
    if (d == null) return;
    try {
      final msg = excel ? await downloadExcel(d, _fileName) : await downloadPdf(d, _fileName, _subtitle);
      if (mounted) snack(context, msg);
    } catch (e) {
      if (mounted) snack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _pick(bool from) async {
    final d = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime.now(),
    );
    if (d == null) return;
    setState(() {
      if (from) {
        _from = d;
        if (_to.isBefore(d)) _to = d;
      } else {
        _to = d;
        if (_from.isAfter(d)) _from = d;
      }
    });
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: topBar('Reports', sub: 'View or download'),
      body: PageBody(maxWidth: 1100, children: [
        DropdownButtonFormField<String>(
          value: _type,
          decoration: inDec('Report'),
          items: [for (final e in reportNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) {
            setState(() => _type = v!);
            _run();
          },
        ),
        Row(children: [
          Expanded(child: _dateBox('From', _from, () => _pick(true))),
          const SizedBox(width: 10),
          Expanded(child: _dateBox('To', _to, () => _pick(false))),
        ]),
        Row(children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db.collection('users').snapshots(),
              builder: (context, s) {
                final users = s.data?.docs.toList() ?? [];
                users.sort((a, b) => ((a.data()['name'] ?? '') as String).compareTo((b.data()['name'] ?? '') as String));
                return DropdownButtonFormField<String>(
                  value: users.any((u) => u.id == _driver) ? _driver : '',
                  isExpanded: true,
                  decoration: inDec('Driver'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All drivers')),
                    for (final u in users) DropdownMenuItem(value: u.id, child: Text((u.data()['name'] ?? '') as String, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    setState(() => _driver = v ?? '');
                    _run();
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db.collection('trucks').snapshots(),
              builder: (context, s) {
                final ids = (s.data?.docs.map((t) => t.id).toList() ?? [])..sort();
                return DropdownButtonFormField<String>(
                  value: ids.contains(_truck) ? _truck : '',
                  isExpanded: true,
                  decoration: inDec('Truck'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All trucks')),
                    for (final t in ids) DropdownMenuItem(value: t, child: Text(prettyTruck(t))),
                  ],
                  onChanged: (v) {
                    setState(() => _truck = v ?? '');
                    _run();
                  },
                );
              },
            ),
          ),
        ]),
        if (_busy) const LinearProgressIndicator(),
        if (d != null) ...[
          Text('${d.rows.length} row${d.rows.length == 1 ? '' : 's'} · $_subtitle', style: const TextStyle(color: cMuted, fontSize: 13)),
          Box(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 48,
                columnSpacing: 18,
                headingRowColor: WidgetStateProperty.all(const Color(0xFFF3F1EC)),
                columns: [for (final h in d.header) DataColumn(label: Text(h, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)))],
                rows: [
                  for (final r in d.rows)
                    DataRow(cells: [for (final c in r) DataCell(Text(_cell(c), style: const TextStyle(fontSize: 12.5)))]),
                ],
              ),
            ),
          ),
          if (d.rows.isEmpty) const NoteBox('No records for these filters.'),
          Row(children: [
            Expanded(child: BigButton('Download Excel', small: true, onPressed: d.rows.isEmpty ? null : () => _download(true))),
            const SizedBox(width: 10),
            Expanded(child: BigButton('Download PDF', small: true, outlined: true, onPressed: d.rows.isEmpty ? null : () => _download(false))),
          ]),
        ],
      ]),
    );
  }

  Widget _dateBox(String label, DateTime d, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(decoration: inDec(label), child: Text(showDate(d), style: const TextStyle(fontSize: 15.5))),
      );
}
