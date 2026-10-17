import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'download_io.dart' if (dart.library.js_interop) 'download_web.dart';

/// A report ready to show and download. Cells are numbers or text.
class ReportData {
  final String title;
  final List<String> header;
  final List<List<Object?>> rows;
  ReportData(this.title, this.header, this.rows);
}

Future<String> downloadExcel(ReportData r, String fileName) async {
  final ex = Excel.createExcel();
  final sheetName = ex.getDefaultSheet() ?? 'Sheet1';
  final sheet = ex[sheetName];
  sheet.appendRow([TextCellValue(r.title)]);
  sheet.appendRow(r.header.map<CellValue?>((h) => TextCellValue(h)).toList());
  for (final row in r.rows) {
    sheet.appendRow(row.map<CellValue?>((c) {
      if (c == null) return null;
      if (c is int) return IntCellValue(c);
      if (c is num) return DoubleCellValue(c.toDouble());
      return TextCellValue(c.toString());
    }).toList());
  }
  final bytes = ex.encode();
  if (bytes == null) throw 'Could not make the Excel file.';
  return saveBytes(Uint8List.fromList(bytes), '$fileName.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
}

Future<String> downloadPdf(ReportData r, String fileName, String subtitle) async {
  final doc = pw.Document();
  String cell(Object? c) {
    if (c == null) return '';
    if (c is double) return c.toStringAsFixed(c == c.roundToDouble() ? 0 : 2);
    return c.toString();
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(24),
    build: (_) => [
      pw.Text('JTCPL · TU Ver 01 · ${r.title}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 2),
      pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9)),
      pw.SizedBox(height: 10),
      pw.TableHelper.fromTextArray(
        headers: r.header.map((h) => h.replaceAll('₹', 'Rs')).toList(),
        data: r.rows.map((row) => row.map(cell).toList()).toList(),
        headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 7.5),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellAlignment: pw.Alignment.centerLeft,
      ),
    ],
  ));
  final bytes = await doc.save();
  return saveBytes(bytes, '$fileName.pdf', 'application/pdf');
}
