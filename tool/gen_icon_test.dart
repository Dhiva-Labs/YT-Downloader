// Generates the launcher icon PNGs. Run with:
//   flutter test tool/gen_icon_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generate launcher icons', () async {
    await _write('assets/icon/icon.png', _drawIcon(withBackground: true));
    await _write(
        'assets/icon/icon_fg.png', _drawIcon(withBackground: false));
  });
}

ui.Picture _drawIcon({required bool withBackground}) {
  const size = 1024.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  if (withBackground) {
    final bg = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(size, size),
        [const Color(0xFFEF5350), const Color(0xFFB71C1C)],
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, size, size), const Radius.circular(224)),
      bg,
    );
    // Subtle highlight in the top-left.
    final gloss = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(0, size * 0.55),
        [const Color(0x33FFFFFF), const Color(0x00FFFFFF)],
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, size, size), const Radius.circular(224)),
      gloss,
    );
  }

  // The adaptive foreground must sit inside the safe zone, so shrink it.
  final scale = withBackground ? 1.0 : 0.72;
  canvas.translate(size / 2, size / 2);
  canvas.scale(scale);
  canvas.translate(-size / 2, -size / 2);

  final white = Paint()..color = Colors.white;

  // Bold download arrow: shaft, head, then a tray line beneath.
  canvas.drawRRect(
    RRect.fromRectAndRadius(
        const Rect.fromLTRB(442, 165, 582, 500), const Radius.circular(32)),
    white,
  );
  final head = Path()
    ..moveTo(282, 470)
    ..lineTo(742, 470)
    ..lineTo(512, 730)
    ..close();
  canvas.drawPath(head, white);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
        const Rect.fromLTRB(282, 800, 742, 872), const Radius.circular(36)),
    white,
  );

  return recorder.endRecording();
}

Future<void> _write(String path, ui.Picture picture) async {
  final image = await picture.toImage(1024, 1024);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path)..createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote $path (${file.lengthSync()} bytes)');
}
