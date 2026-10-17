import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/route_map.dart';
import '../../core/ui.dart';
import '../../services/session.dart';
import '../../services/tracker.dart';

/// The driver sees his own location, last update time and today's route.
class MyLocation extends StatelessWidget {
  const MyLocation({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('tracks').doc(Tracker.trackId(Session.driverId, DateTime.now())).snapshots(),
      builder: (context, s) {
        final d = s.data?.data();
        final route = pointsOf(d?['points'] as List?);
        final lastAt = (d?['lastAt'] as Timestamp?)?.toDate();
        final onDuty = d?['onDuty'] == true;
        final mins = lastAt == null ? null : DateTime.now().difference(lastAt).inMinutes;
        final fresh = onDuty && mins != null && mins <= 15;
        return Scaffold(
          appBar: topBar(
            bi('मेरी लोकेशन', 'My location'),
            sub: d == null ? null : '${prettyTruck((d['truck'] ?? '') as String)} · ${onDuty ? bi('ड्यूटी चालू', 'On duty') : bi('ड्यूटी बंद', 'Off duty')}',
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(child: Pill(fresh ? 'GPS ON' : 'GPS OFF', tone: fresh ? Tone.ok : Tone.bad)),
              ),
            ],
          ),
          body: PageBody(children: [
            RouteMap(
              route: route,
              height: 340,
              pins: [
                if (route.isNotEmpty) MapPin(route.first, cGreen, size: 14),
                if (route.isNotEmpty) MapPin(route.last, cBlue, size: 18, label: bi('आप यहाँ', 'You')),
              ],
            ),
            if (d == null)
              NoteBox(bi('आज की कोई लोकेशन नहीं। ड्यूटी शुरू करने पर दिखेगी।', 'No location today yet. It appears after you start duty.'))
            else
              KvCard([
                (bi('आख़िरी अपडेट', 'Last update'),
                    kvText(lastAt == null ? '-' : '${showTime(lastAt)} · ${mins == 0 ? bi('अभी', 'just now') : '$mins ${bi('मिनट पहले', 'min ago')}'}')),
                (bi('आज GPS km', 'GPS km today'), kvText(fmtNum((d['gpsKm'] as num?) ?? 0))),
                (bi('आज के पॉइंट', 'Points today'), kvText('${route.length}')),
              ]),
            NoteBox(bi('नीले बिंदु हर 5 मिनट की लोकेशन हैं। आप सिर्फ़ अपनी गाड़ी देखते हैं।',
                'Blue dots are your 5-minute location points. You see only your own truck.')),
          ]),
        );
      },
    );
  }
}
