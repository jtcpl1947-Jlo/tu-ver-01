import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/ui.dart';
import 'session.dart';

/// A photo taken in the app but not saved yet.
class PickedPhoto {
  final XFile file;
  final Uint8List bytes;
  final DateTime at;
  PickedPhoto(this.file, this.bytes, this.at);
}

/// Opens the camera on a phone, or a file chooser on a desktop browser.
/// The photo is shrunk to about 100-200 KB.
Future<PickedPhoto?> takePhoto() async {
  final x = await ImagePicker().pickImage(
    source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
    maxWidth: 1000,
    maxHeight: 1400,
    imageQuality: 55,
  );
  if (x == null) return null;
  final b = await x.readAsBytes();
  return PickedPhoto(x, b, DateTime.now());
}

/// Saves the photo in Firestore (photos collection) and returns its id.
/// Test phase only: later photos move to free object storage.
Future<String> savePhoto(PickedPhoto p, String kind) async {
  if (p.bytes.length > 750000) {
    throw 'Photo is too large. Take it again a little further away.';
  }
  final ref = db.collection('photos').doc();
  await ref.set({
    'uid': Session.uid,
    'driverId': Session.driverId,
    'kind': kind,
    'data': base64Encode(p.bytes),
    'at': Timestamp.fromDate(p.at),
  });
  return ref.id;
}

/// Shows a stored photo.
class StoredPhoto extends StatelessWidget {
  final String? id;
  final String label;
  final double height;
  const StoredPhoto(this.id, {super.key, required this.label, this.height = 140});

  @override
  Widget build(BuildContext context) {
    if (id == null || id!.isEmpty) return _frame(Text('$label: none', style: const TextStyle(color: cMuted)));
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: db.collection('photos').doc(id).get(),
      builder: (c, s) {
        if (!s.hasData) return _frame(const CircularProgressIndicator(strokeWidth: 2));
        final d = s.data!.data();
        if (d == null) return _frame(Text('$label: not found', style: const TextStyle(color: cMuted)));
        final bytes = base64Decode(d['data'] as String);
        return GestureDetector(
          onTap: () => showDialog(
            context: context,
            builder: (_) => Dialog(child: InteractiveViewer(child: Image.memory(bytes))),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(children: [
              Image.memory(bytes, height: height, width: double.infinity, fit: BoxFit.cover),
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                  child: Text('$label · tap to zoom', style: const TextStyle(color: Colors.white, fontSize: 11)),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _frame(Widget child) => Container(
        height: height,
        decoration: BoxDecoration(color: const Color(0xFFF3F1EC), borderRadius: BorderRadius.circular(12), border: Border.all(color: cLine)),
        child: Center(child: child),
      );
}

/// Button that shows "take photo" or "photo taken".
class PhotoButton extends StatelessWidget {
  final PickedPhoto? photo;
  final String emptyText;
  final String doneText;
  final VoidCallback onTap;
  final double height;
  const PhotoButton({super.key, required this.photo, required this.emptyText, required this.doneText, required this.onTap, this.height = 64});

  @override
  Widget build(BuildContext context) {
    final done = photo != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: done ? cGreenBg : const Color(0xFFFBFAF7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: done ? const Color(0xFF86EFAC) : cField, width: 1.5),
        ),
        child: Row(children: [
          if (done)
            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(photo!.bytes, width: 44, height: 44, fit: BoxFit.cover))
          else
            const Icon(Icons.photo_camera_outlined, color: cMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(done ? '$doneText ${showTime(photo!.at)} · retake' : emptyText,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: done ? const Color(0xFF14532D) : cMuted)),
          ),
        ]),
      ),
    );
  }
}
