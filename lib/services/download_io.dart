import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';

/// Phone: saves the file to the Downloads folder.
Future<String> saveBytes(Uint8List bytes, String fileName, String mime) async {
  final dot = fileName.lastIndexOf('.');
  final name = dot > 0 ? fileName.substring(0, dot) : fileName;
  final ext = dot > 0 ? fileName.substring(dot + 1) : '';
  await FileSaver.instance.saveFile(
    name: name,
    bytes: bytes,
    ext: ext,
    mimeType: ext == 'pdf' ? MimeType.pdf : MimeType.microsoftExcel,
  );
  return 'Saved $fileName to Downloads';
}
