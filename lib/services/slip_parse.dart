/// Values read from a diesel slip. Any field may be missing.
class SlipData {
  double? litres;
  double? rate;
  double? amount;
  String? slipNo;
  String? date; // dd-MM-yyyy
  String? pumpText;
  int found = 0;
}

double? _num(String? s) => s == null ? null : double.tryParse(s.replaceAll(',', ''));

/// Reads common Indian fuel-slip layouts (IOCL, HP, BPCL, Nayara, Reliance, private pumps).
SlipData parseSlip(String raw) {
  final d = SlipData();
  final text = raw.replaceAll('\r', '');
  final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final flat = lines.join('\n');

  RegExpMatch? m;

  m = RegExp(r'(?:volume|vol|qty|quantity|litres?|liters?|ltrs?|ltr)\s*(?:\(l\))?\s*[:\-=]?\s*([\d,]+\.?\d*)', caseSensitive: false)
      .firstMatch(flat);
  m ??= RegExp(r'([\d,]+\.\d{1,3})\s*(?:l|ltr|ltrs|litres?)\b', caseSensitive: false).firstMatch(flat);
  d.litres = _num(m?.group(1));

  m = RegExp(r'(?:rate|price|rs\s*/\s*l|₹\s*/\s*l|unit\s*price)\s*(?:\(rs/l\))?\s*[:\-=]?\s*(?:rs\.?|₹|inr)?\s*([\d,]+\.?\d*)',
          caseSensitive: false)
      .firstMatch(flat);
  d.rate = _num(m?.group(1));

  m = RegExp(r'(?:amount|amt|sale|total|value|net\s*amt)\s*(?:\(rs\))?\s*[:\-=]?\s*(?:rs\.?|₹|inr)?\s*([\d,]+\.?\d*)',
          caseSensitive: false)
      .firstMatch(flat);
  d.amount = _num(m?.group(1));

  m = RegExp(r'(?:bill|receipt|invoice|txn|trans(?:action)?|slip|memo)\s*(?:no|number|id|#)?\.?\s*[:\-]?\s*([A-Z0-9][A-Z0-9\-/]{1,})',
          caseSensitive: false)
      .firstMatch(flat);
  d.slipNo = m?.group(1);

  m = RegExp(r'\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})\b').firstMatch(flat);
  if (m != null) {
    var y = m.group(3)!;
    if (y.length == 2) y = '20$y';
    d.date = '${m.group(1)!.padLeft(2, '0')}-${m.group(2)!.padLeft(2, '0')}-$y';
  }

  final pumpWords = RegExp(
      r'(fuel|petro|filling|service\s*station|station|indian\s*oil|iocl|bharat|bpcl|hindustan|hpcl|\bhp\b|nayara|reliance|jio-bp|shell|essar|kisan)',
      caseSensitive: false);
  for (final l in lines.take(8)) {
    if (pumpWords.hasMatch(l) && RegExp(r'[A-Za-z]{3,}').hasMatch(l) && !RegExp(r'welcome|thank', caseSensitive: false).hasMatch(l)) {
      d.pumpText = l;
      break;
    }
  }

  // Fill one missing value from the other two.
  if (d.amount == null && d.litres != null && d.rate != null) d.amount = double.parse((d.litres! * d.rate!).toStringAsFixed(2));
  if (d.litres == null && d.amount != null && d.rate != null && d.rate! > 0) {
    d.litres = double.parse((d.amount! / d.rate!).toStringAsFixed(2));
  }
  if (d.rate == null && d.amount != null && d.litres != null && d.litres! > 0) {
    d.rate = double.parse((d.amount! / d.litres!).toStringAsFixed(2));
  }

  d.found = [d.litres, d.rate, d.amount, d.slipNo, d.date, d.pumpText].where((x) => x != null).length;
  return d;
}

/// Picks the saved pump whose name best matches the slip text.
String? matchPump(String? slipText, List<String> pumps) {
  if (slipText == null) return null;
  final t = slipText.toLowerCase();
  String? best;
  var bestScore = 0;
  for (final p in pumps) {
    final words = p.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 3).toList();
    final score = words.where(t.contains).length;
    if (score > bestScore) {
      bestScore = score;
      best = p;
    }
  }
  return bestScore >= 1 ? best : null;
}
