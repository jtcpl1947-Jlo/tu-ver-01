import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/session.dart';
import 'approvals.dart';
import 'drivers.dart';
import 'live_map.dart';
import 'masters.dart';
import 'reports.dart';
import 'settings.dart';

/// Driver status from today's track: on duty, location off, or off duty.
String trackState(Map<String, dynamic>? t) {
  if (t == null || t['onDuty'] != true) return 'off';
  final at = (t['lastAt'] as Timestamp?)?.toDate();
  if (at == null || DateTime.now().difference(at).inMinutes > 15) return 'lost';
  return 'on';
}

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final today = dateKey(DateTime.now());
    return Scaffold(
      appBar: topBar(
        Session.isManager ? 'JTCPL Manager' : 'JTCPL Admin',
        sub: '${Session.name} · ${showDate(DateTime.now())}',
        dark: true,
        actions: [IconButton(tooltip: 'Log out', icon: const Icon(Icons.logout), onPressed: () => Session.logout())],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('tracks').where('date', isEqualTo: today).snapshots(),
        builder: (context, ts) {
          final tracks = ts.data?.docs.map((d) => d.data()).toList() ?? [];
          final on = tracks.where((t) => trackState(t) == 'on').length;
          final lost = tracks.where((t) => trackState(t) == 'lost').toList();
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('users').where('active', isEqualTo: true).snapshots(),
            builder: (context, us) {
              final drivers = us.data?.docs.length ?? 0;
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: db.collection('diesel').where('dateKey', isEqualTo: today).snapshots(),
                builder: (context, ds) {
                  final litres = ds.data?.docs.fold<double>(0, (s, d) => s + ((d.data()['litres'] as num?) ?? 0)) ?? 0;
                  return PageBody(maxWidth: 720, children: [
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 2.3,
                      children: [
                        Tile('$on', 'On duty', color: cGreen),
                        Tile('${(drivers - on - lost.length).clamp(0, 9999)}', 'Off duty'),
                        Tile('${lost.length}', 'Location off', color: lost.isEmpty ? null : const Color(0xFFB91C1C)),
                        Tile('${fmtNum(litres)} L', 'Diesel today'),
                      ],
                    ),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: db.collection('diesel').where('status', isEqualTo: 'pending').snapshots(),
                      builder: (context, ps) {
                        final n = ps.data?.docs.length ?? 0;
                        return MenuRow(
                          icon: Icons.check_circle_outline,
                          title: 'Approvals',
                          sub: 'Diesel entries with slip and meter photos',
                          trailing: Pill(n == 0 ? 'None pending' : '$n pending', tone: n == 0 ? Tone.ok : Tone.warn),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const Approvals())),
                        );
                      },
                    ),
                    MenuRow(
                      icon: Icons.map_outlined,
                      title: 'Live map',
                      sub: 'All trucks · 5-minute updates · route history',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveMap())),
                    ),
                    MenuRow(
                      icon: Icons.person_add_alt,
                      title: 'Drivers and PINs',
                      sub: '$drivers active of 50 · add, PIN, switch off',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const Drivers())),
                    ),
                    MenuRow(
                      icon: Icons.local_shipping_outlined,
                      title: 'Trucks and pumps',
                      sub: 'Own trucks, temporary numbers, pump list',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const Masters())),
                    ),
                    MenuRow(
                      icon: Icons.bar_chart,
                      title: 'Reports',
                      sub: '5 reports · Excel / PDF',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const Reports())),
                    ),
                    if (Session.isAdmin)
                      MenuRow(
                        icon: Icons.settings_outlined,
                        title: 'Admin settings',
                        sub: 'Change password · Manager logins',
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSettings())),
                      ),
                    if (lost.isNotEmpty)
                      NoteBox(
                        'Location off: ${lost.map((t) {
                          final at = (t['lastAt'] as Timestamp?)?.toDate();
                          final m = at == null ? '?' : '${DateTime.now().difference(at).inMinutes} min';
                          return '${prettyTruck((t['truck'] ?? '') as String)} (${t['driverName']}) $m';
                        }).join(' · ')}',
                        tone: Tone.bad,
                      ),
                  ]);
                },
              );
            },
          );
        },
      ),
    );
  }
}
