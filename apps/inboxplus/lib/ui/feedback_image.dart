import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

const feedbackImageMaxEdge = 1600;
const feedbackImageMaxBytes = 3 * 1024 * 1024;

class UnreadableImageException implements Exception {
  const UnreadableImageException();
}

Future<Uint8List> normalizeFeedbackImage(Uint8List bytes) async {
  final ui.Image image;
  try {
    final codec = await ui.instantiateImageCodecWithSize(
      await ui.ImmutableBuffer.fromUint8List(bytes),
      getTargetSize: (width, height) {
        final scale = _scale(width, height, feedbackImageMaxEdge);
        return ui.TargetImageSize(
          width: math.max(1, (width * scale).round()),
          height: math.max(1, (height * scale).round()),
        );
      },
    );
    try {
      image = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  } catch (_) {
    throw const UnreadableImageException();
  }
  try {
    return await fitFeedbackImage(image);
  } finally {
    image.dispose();
  }
}

Future<Uint8List> fitFeedbackImage(ui.Image image) async {
  var edge = math.min(
    feedbackImageMaxEdge,
    math.max(image.width, image.height),
  );
  while (true) {
    final png = await _encode(image, edge);
    if (png.length <= feedbackImageMaxBytes) return png;
    edge = edge * 3 ~/ 4;
  }
}

double _scale(int width, int height, int edge) =>
    math.min(1, edge / math.max(width, height));

Future<Uint8List> _encode(ui.Image source, int edge) async {
  final scale = _scale(source.width, source.height, edge);
  final width = math.max(1, (source.width * scale).round());
  final height = math.max(1, (source.height * scale).round());
  var image = source;
  if (width != source.width || height != source.height) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    image = await picture.toImage(width, height);
    picture.dispose();
  }
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    if (image != source) image.dispose();
  }
}
