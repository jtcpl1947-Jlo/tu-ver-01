import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/route_map.dart';
import '../../core/ui.dart';
import '../../services/session.dart';
import 'dashboard.dart';

class LiveMap extends StatefulWidget {
  const LiveMap({super.key});
  @override
  State<LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends State<LiveMap> {
  DateTime _day = DateTime.now();
  String _filter = 'all';
  String? _selected; // track doc id

  bool get _isToday => dateKey(_day) == dateKey(DateTime.now());

  Color _color(String state) => switch (state) { 'on' => cGreen, 'lost' => const Color(0xFFB91C1C), _ => const Color(0xFF9CA3AF) };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: topBar(_isToday ? 'Live map' : 'Route history', sub: _isToday ? 'Updates every 5 minutes' : showDate(_day), actions: [
        IconButton(
          tooltip: 'Pick a day',
          icon: const Icon(Icons.calendar_month_outlined),
          onPressed: () async {
            final d = await showDatePicker(
                context: context, initialDate: _day, firstDate: DateTime(2026, 1, 1), lastDate: DateTime.now());
            if (d != null) setState(() {
              _day = d;
              _selected = null;
            });
          },
        ),
      ]),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('tracks').where('date', isEqualTo: dateKey(_day)).snapshots(),
        builder: (context, s) {
          final docs = s.data?.docs.toList() ?? [];
          docs.sort((a, b) => ((a.data()['truck'] ?? '') as String).compareTo((b.data()['truck'] ?? '') as String));
          final shown = docs.where((d) {
            final st = _isToday ? trackState(d.data()) : 'off';
            return _filter == 'all' || (_filter == 'on' && st == 'on') || (_filter == 'lost' && st == 'lost');
          }).toList();
          final sel = docs.where((d) => d.id == _selected).toList();
          final route = sel.isEmpty ? <LatLng>[] : pointsOf(sel.first.data()['points'] as List?);
          final pins = <MapPin>[
            for (final d in shown)
              if (d.data()['lastLat'] is num)
                MapPin(
                  LatLng((d.data()['lastLat'] as num).toDouble(), (d.data()['lastLng'] as num).toDouble()),
                  d.id == _selected ? cBlue : _color(_isToday ? trackState(d.data()) : 'on'),
                  size: d.id == _selected ? 18 : 14,
                  label: prettyTruck((d.data()['truck'] ?? '') as String),
                  onTap: () => setState(() => _selected = d.id),
                ),
          ];
          return PageBody(maxWidth: 900, children: [
            if (_isToday)
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'all', label: Text('All ${docs.length}')),
                  const ButtonSegment(value: 'on', label: Text('On duty')),
                  const ButtonSegment(value: 'lost', label: Text('Location off')),
                ],
                selected: {_filter},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _filter = v.first),
              ),
            RouteMap(route: route, pins: pins, height: 420),
            Wrap(spacing: 14, children: [
              if (_isToday) ...[
                _legend(cGreen, 'On duty'),
                _legend(const Color(0xFF9CA3AF), 'Off duty'),
                _legend(const Color(0xFFB91C1C), 'Location off'),
              ],
              _legend(cBlue, 'Selected · route shown'),
            ]),
            if (docs.isEmpty) NoteBox(_isToday ? 'No locations yet today.' : 'No locations on this day.'),
            if (shown.isNotEmpty)
              KvCard([
                for (final d in shown)
                  (
                    '${prettyTruck((d.data()['truck'] ?? '') as String)} · ${d.data()['driverName'] ?? ''}',
                    InkWell(
                      onTap: () => setState(() => _selected = d.id),
                      child: kvText(_lastSeen(d.data()),
                          color: _isToday && trackState(d.data()) == 'lost' ? const Color(0xFFB91C1C) : (d.id == _selected ? cBlue : null)),
                    ),
                  ),
              ]),
            const Text('Tap a truck to see its route for the day.', style: TextStyle(fontSize: 12.5, color: cMuted)),
          ]);
        },
      ),
    );
  }

  String _lastSeen(Map<String, dynamic> t) {
    final at = (t['lastAt'] as Timestamp?)?.toDate();
    final km = fmtNum((t['gpsKm'] as num?) ?? 0);
    if (at == null) return '-';
    if (!_isToday) return 'Last ${showTime(at)} · $km km';
    final m = DateTime.now().difference(at).inMinutes;
    if (trackState(t) == 'lost') return 'Last seen $m min ago';
    if (trackState(t) == 'off') return 'Off duty · $km km';
    return '${m == 0 ? 'just now' : '$m min ago'} · $km km';
  }

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(t, style: const TextStyle(fontSize: 12, color: cMuted)),
      ]);
}
