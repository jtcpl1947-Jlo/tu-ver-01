import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Desktop browser: downloads the file through the browser.
Future<String> saveBytes(Uint8List bytes, String fileName, String mime) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement;
  a.href = url;
  a.download = fileName;
  web.document.body!.appendChild(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
  return 'Downloaded $fileName';
}
