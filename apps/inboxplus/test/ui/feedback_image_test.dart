import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:inboxplus/ui/feedback_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ui.Image> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  }

  Future<ui.Image> solid(int width, int height) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xff3a86ff),
    );
    return recorder.endRecording().toImage(width, height);
  }

  Future<Uint8List> png(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  bool isPng(Uint8List bytes) =>
      bytes.length > 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47;

  test('an oversized image is scaled to a 1600 px PNG', () async {
    final normalized = await normalizeFeedbackImage(
      await png(await solid(3200, 1000)),
    );
    expect(isPng(normalized), isTrue);
    final image = await decode(normalized);
    expect((image.width, image.height), (1600, 500));
  });

  test('a small image keeps its size', () async {
    final image = await decode(
      await normalizeFeedbackImage(await png(await solid(300, 200))),
    );
    expect((image.width, image.height), (300, 200));
  });

  test('an image that stays over 3 MB is scaled down until it fits', () async {
    final random = math.Random(7);
    const edge = 1600;
    final pixels = Uint8List.fromList([
      for (var i = 0; i < edge * edge; i++) ...[
        random.nextInt(256),
        random.nextInt(256),
        random.nextInt(256),
        255,
      ],
    ]);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      edge,
      edge,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final noise = await completer.future;
    expect((await png(noise)).length, greaterThan(feedbackImageMaxBytes));
    final fitted = await fitFeedbackImage(noise);
    expect(fitted.length, lessThanOrEqualTo(feedbackImageMaxBytes));
    expect(isPng(fitted), isTrue);
    final image = await decode(fitted);
    expect(image.width, lessThan(edge));
    expect(image.width, image.height);
  });

  test('bytes that are not an image are rejected', () async {
    await expectLater(
      normalizeFeedbackImage(Uint8List.fromList('not an image'.codeUnits)),
      throwsA(isA<UnreadableImageException>()),
    );
  });
}
