import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'slip_parse.dart';

/// Reads the slip text on the phone with Google ML Kit (free, works offline).
bool get scanSupported => true;

Future<SlipData?> scanSlip(XFile file) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(file.path));
    return parseSlip(result.text);
  } finally {
    await recognizer.close();
  }
}
