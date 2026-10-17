import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/photos.dart';
import '../../services/session.dart';

const flagText = {
  'amount_mismatch': 'Litres × rate does not match amount',
  'mileage_unusual': 'Mileage outside normal range',
  'pump_other': 'Pump typed as Other',
  'temp_not_in_list': 'Temporary number not in JTCPL list',
};

class Approvals extends StatelessWidget {
  const Approvals({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: topBar('Approvals', sub: 'Pending diesel entries'),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('diesel').where('status', isEqualTo: 'pending').snapshots(),
        builder: (context, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final docs = s.data!.docs.toList()
            ..sort((a, b) => ((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
                .compareTo((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
          return PageBody(maxWidth: 720, children: [
            if (docs.isEmpty) const NoteBox('Nothing pending. All diesel entries are checked.', tone: Tone.ok),
            for (var i = 0; i < docs.length; i++)
              MenuRow(
                icon: Icons.local_gas_station_outlined,
                title: '${prettyTruck(docs[i].data()['truck'] as String)} · ${fmtNum(docs[i].data()['litres'] as num?)} L',
                sub: '${docs[i].data()['driverName']} · ${docs[i].data()['date']} · ₹${fmtNum(docs[i].data()['amount'] as num?)}',
                trailing: ((docs[i].data()['flags'] as List?) ?? []).isEmpty
                    ? const Pill('Checks OK', tone: Tone.ok)
                    : Pill('${(docs[i].data()['flags'] as List).length} to check', tone: Tone.bad),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => EntryDetail(id: docs[i].id, data: docs[i].data(), position: '${i + 1} of ${docs.length}')),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class EntryDetail extends StatefulWidget {
  final String id;
  final Map<String, dynamic> data;
  final String position;
  const EntryDetail({super.key, required this.id, required this.data, this.position = ''});
  @override
  State<EntryDetail> createState() => _EntryDetailState();
}

class _EntryDetailState extends State<EntryDetail> {
  final _why = TextEditingController();
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    if (!approve && _why.text.trim().isEmpty) return snack(context, 'Write the reason for rejecting', error: true);
    setState(() => _busy = true);
    try {
      await db.collection('diesel').doc(widget.id).update({
        'status': approve ? 'approved' : 'rejected',
        'reason': approve ? '' : _why.text.trim(),
        'decidedBy': Session.name,
        'decidedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        snack(context, approve ? 'Approved' : 'Rejected');
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
    final d = widget.data;
    final flags = ((d['flags'] as List?) ?? []).cast<String>();
    final litres = (d['litres'] as num?) ?? 0, rate = (d['rate'] as num?) ?? 0, amount = (d['amount'] as num?) ?? 0;
    final created = (d['createdAt'] as Timestamp?)?.toDate();
    final pending = d['status'] == 'pending';
    return Scaffold(
      appBar: topBar(pending ? 'Approve entry' : 'Diesel entry', sub: widget.position.isEmpty ? null : widget.position, actions: [
        Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: statusPill(d['status'] as String?))),
      ]),
      body: PageBody(maxWidth: 720, children: [
        Row(children: [
          Expanded(child: StoredPhoto(d['slipPhotoId'] as String?, label: 'Slip photo', height: 170)),
          const SizedBox(width: 10),
          Expanded(child: StoredPhoto(d['meterPhotoId'] as String?, label: 'Meter photo', height: 170)),
        ]),
        KvCard([
          ('Driver', kvText((d['driverName'] ?? '') as String)),
          (
            'Truck',
            Wrap(spacing: 6, alignment: WrapAlignment.end, children: [
              kvText(prettyTruck(d['truck'] as String)),
              Pill(d['truckType'] == 'own' ? 'Own' : 'Temp', tone: d['truckType'] == 'own' ? Tone.ok : Tone.warn),
            ])
          ),
          ('Pump', kvText('${d['pump']}${d['pumpOther'] == true ? ' (Other)' : ''}')),
          ('Slip no. · Date', kvText('${d['slipNo'] ?? '-'} · ${d['date'] ?? '-'}')),
          ('Litres × Rate', kvText('${fmtNum(litres, dec: 2)} × ₹${fmtNum(rate, dec: 2)} = ₹${fmtNum(amount, dec: 2)}')),
          ('Odometer', kvText('${fmtNum(d['odometer'] as num?)} km')),
          ('Entry by', kvText(d['entryMode'] == 'scan' ? 'Slip scan' : 'Filled manually')),
          ('Saved at', kvText(created == null ? '-' : showDateTime(created))),
          ('GPS at entry', kvText(d['lat'] == null ? 'Not available' : '${(d['lat'] as num).toStringAsFixed(5)}, ${(d['lng'] as num).toStringAsFixed(5)}')),
        ]),
        Box(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _check(!flags.contains('amount_mismatch'), 'Litres × rate = ₹${fmtNum(litres * rate, dec: 2)} vs slip ₹${fmtNum(amount, dec: 2)}'),
            _check(true,
                d['prevKm'] == null ? 'First odometer reading for this truck' : 'Odometer higher than last (${fmtNum(d['prevKm'] as num?)})'),
            if (d['kmSinceLast'] != null)
              _check(!flags.contains('mileage_unusual'),
                  '${fmtNum(d['kmSinceLast'] as num?)} km since last entry · ${d['mileage'] ?? '-'} km/L'),
            if (flags.contains('pump_other')) _check(false, flagText['pump_other']!),
            if (flags.contains('temp_not_in_list')) _check(false, flagText['temp_not_in_list']!),
          ]),
        ),
        if (!pending && (d['reason'] ?? '').toString().isNotEmpty) NoteBox('Reason: ${d['reason']}', tone: Tone.bad),
        if (pending && Session.isAdmin) ...[
          TextField(controller: _why, decoration: inDec('Reason if rejecting', hint: 'e.g. slip photo not clear')),
          Row(children: [
            Expanded(child: BigButton('Reject', outlined: true, busy: _busy, onPressed: () => _decide(false))),
            const SizedBox(width: 10),
            Expanded(child: BigButton('Approve', color: cGreen, busy: _busy, onPressed: () => _decide(true))),
          ]),
        ],
      ]),
    );
  }

  Widget _check(bool ok, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: ok ? cGreen : const Color(0xFFB91C1C), shape: BoxShape.circle),
            child: Icon(ok ? Icons.check : Icons.priority_high, size: 12, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
        ]),
      );
}
