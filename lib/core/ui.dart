import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ---------- Colours (same as the approved screens) ----------
const cBlue = Color(0xFF1F3A8A);
const cBlueBg = Color(0xFFE8EDFB);
const cGreen = Color(0xFF166534);
const cGreenBg = Color(0xFFDCFCE7);
const cAmber = Color(0xFF78350F);
const cAmberBg = Color(0xFFFEF3C7);
const cRed = Color(0xFF7F1D1D);
const cRedBg = Color(0xFFFEE2E2);
const cBg = Color(0xFFF6F4EF);
const cInk = Color(0xFF1A1D24);
const cMuted = Color(0xFF4B5563);
const cLine = Color(0xFFE2DED4);
const cField = Color(0xFFCFC9BC);
const cSaffron = Color(0xFFB45309);

// ---------- Language ----------
final ValueNotifier<String> appLang = ValueNotifier<String>('hi');

/// Driver labels: Hindi + English when Hindi is chosen, English only otherwise.
String bi(String hi, String en) => appLang.value == 'hi' ? '$hi · $en' : en;

// ---------- Formatting ----------
final _inNum = NumberFormat.decimalPattern('en_IN');
String fmtNum(num? v, {int dec = 0}) {
  if (v == null) return '-';
  if (dec == 0) return _inNum.format(v.round());
  return NumberFormat('#,##,##0.${'0' * dec}', 'en_IN').format(v);
}

String dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String showDate(DateTime d) => DateFormat('dd-MM-yyyy').format(d);
String showDateTime(DateTime d) => DateFormat('dd-MM-yyyy HH:mm').format(d);
String showTime(DateTime d) => DateFormat('HH:mm').format(d);

double? parseNum(String s) {
  final t = s.replaceAll(',', '').replaceAll('₹', '').trim();
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

String digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// Mobile without +91, last 10 digits.
String mobile10(String s) {
  final d = digitsOnly(s);
  return d.length > 10 ? d.substring(d.length - 10) : d;
}

// ---------- Vehicle numbers ----------
String normTruck(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

String prettyTruck(String s) {
  final n = normTruck(s);
  final m = RegExp(r'^([A-Z]{2})(\d{1,2})([A-Z]{0,3})(\d{1,4})$').firstMatch(n);
  if (m == null) return n;
  return [m.group(1), m.group(2), m.group(3), m.group(4)]
      .where((x) => x != null && x.isNotEmpty)
      .join(' ');
}

bool validTruck(String s) {
  final n = normTruck(s);
  return RegExp(r'^[A-Z]{2}\d{1,2}[A-Z]{0,3}\d{4}$').hasMatch(n) ||
      RegExp(r'^\d{2}BH\d{4}[A-Z]{1,2}$').hasMatch(n);
}

// ---------- Widgets ----------
InputDecoration inDec(String label, {String? hint, String? suffix, String? prefix}) => InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: suffix,
      prefixText: prefix,
      filled: true,
      fillColor: Colors.white,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: cField)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: cField, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: cBlue, width: 2)),
    );

class BigButton extends StatelessWidget {
  final String label;
  final String? sub;
  final VoidCallback? onPressed;
  final Color color;
  final bool outlined;
  final bool busy;
  final bool small;
  const BigButton(this.label,
      {super.key, this.sub, this.onPressed, this.color = cBlue, this.outlined = false, this.busy = false, this.small = false});

  @override
  Widget build(BuildContext context) {
    final fg = outlined ? cInk : Colors.white;
    final child = busy
        ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
        : Column(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: small ? 14.5 : 17, fontWeight: FontWeight.w700, color: fg)),
            if (sub != null)
              Text(sub!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: fg.withAlpha(220))),
          ]);
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: outlined ? Colors.white : (onPressed == null ? color.withAlpha(110) : color),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(small ? 11 : 14),
            side: outlined ? const BorderSide(color: cField, width: 1.5) : BorderSide.none),
        child: InkWell(
          borderRadius: BorderRadius.circular(small ? 11 : 14),
          onTap: busy ? null : onPressed,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: small ? 44 : 56),
            child: Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: child)),
          ),
        ),
      ),
    );
  }
}

enum Tone { info, warn, ok, bad }

Color toneBg(Tone t) => switch (t) { Tone.info => cBlueBg, Tone.warn => cAmberBg, Tone.ok => cGreenBg, Tone.bad => cRedBg };
Color toneFg(Tone t) => switch (t) {
      Tone.info => const Color(0xFF172C6B),
      Tone.warn => cAmber,
      Tone.ok => const Color(0xFF14532D),
      Tone.bad => cRed
    };

class NoteBox extends StatelessWidget {
  final String text;
  final Tone tone;
  const NoteBox(this.text, {super.key, this.tone = Tone.info});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: toneBg(tone), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(fontSize: 13, height: 1.45, color: toneFg(tone))),
      );
}

class Pill extends StatelessWidget {
  final String text;
  final Tone tone;
  const Pill(this.text, {super.key, this.tone = Tone.ok});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: toneBg(tone), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: toneFg(tone))),
      );
}

Pill statusPill(String? s) => switch (s) {
      'approved' => const Pill('Approved', tone: Tone.ok),
      'rejected' => const Pill('Rejected', tone: Tone.bad),
      _ => const Pill('Pending', tone: Tone.warn),
    };

class Box extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Box({super.key, required this.child, this.padding = const EdgeInsets.all(0)});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: cLine)),
        child: child,
      );
}

/// A white card with label / value rows.
class KvCard extends StatelessWidget {
  final List<(String, Widget)> rows;
  const KvCard(this.rows, {super.key});
  @override
  Widget build(BuildContext context) => Box(
        child: Column(children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  border: i == rows.length - 1 ? null : const Border(bottom: BorderSide(color: Color(0xFFEDEAE2)))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text(rows[i].$1, style: const TextStyle(fontSize: 14, color: cMuted))),
                const SizedBox(width: 10),
                Flexible(child: Align(alignment: Alignment.centerRight, child: rows[i].$2)),
              ]),
            ),
        ]),
      );
}

Widget kvText(String s, {Color? color}) =>
    Text(s, textAlign: TextAlign.right, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color ?? cInk));

class Label extends StatelessWidget {
  final String text;
  const Label(this.text, {super.key});
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cInk));
}

class Tile extends StatelessWidget {
  final String value;
  final String label;
  final Color? color;
  const Tile(this.value, this.label, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Box(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color ?? cInk)),
          Text(label, style: const TextStyle(fontSize: 12.5, color: cMuted)),
        ]),
      );
}

/// Tappable menu row used on the dashboards.
class MenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final Widget? trailing;
  final VoidCallback onTap;
  const MenuRow({super.key, required this.icon, required this.title, required this.sub, this.trailing, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: cLine)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: cBlueBg, borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: cBlue, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                  Text(sub, style: const TextStyle(fontSize: 12.5, color: cMuted)),
                ]),
              ),
              if (trailing != null) trailing!,
            ]),
          ),
        ),
      );
}

/// Centred, max-width page body so the app also looks right on a desktop browser.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  const PageBody({super.key, required this.children, this.maxWidth = 560});
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i != children.length - 1) const SizedBox(height: 12),
                ]
              ],
            ),
          ),
        ),
      );
}

void snack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? const Color(0xFFB91C1C) : cInk,
    behavior: SnackBarBehavior.floating,
  ));
}

Future<bool> confirmBox(BuildContext context, String title, String body, {String ok = 'Yes'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

AppBar topBar(String title, {String? sub, List<Widget>? actions, bool dark = false}) => AppBar(
      backgroundColor: dark ? cBlue : cBg,
      foregroundColor: dark ? Colors.white : cInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 4,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: dark ? Colors.white : cInk)),
        if (sub != null)
          Text(sub,
              style: TextStyle(fontSize: 13, color: dark ? const Color(0xFFDCE3F7) : cMuted, fontWeight: FontWeight.w400)),
      ]),
      actions: actions,
    );

String friendlyError(Object e) {
  final s = e.toString();
  if (s.contains('invalid-credential') || s.contains('wrong-password') || s.contains('user-not-found') || s.contains('INVALID_LOGIN')) {
    return 'Mobile number or PIN is wrong.';
  }
  if (s.contains('email-already-in-use')) return 'This login already exists.';
  if (s.contains('network')) return 'No internet. Check the connection and try again.';
  if (s.contains('permission-denied')) return 'You do not have permission for this.';
  if (s.contains('too-many-requests')) return 'Too many tries. Wait a few minutes and try again.';
  if (s.contains('weak-password')) return 'Password must be at least 6 characters.';
  return s.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '');
}
