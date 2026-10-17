import 'package:image_picker/image_picker.dart';

import 'slip_parse.dart';

/// Slip scanning runs on the phone only. In the desktop browser drivers fill manually.
bool get scanSupported => false;

Future<SlipData?> scanSlip(XFile file) async => null;
