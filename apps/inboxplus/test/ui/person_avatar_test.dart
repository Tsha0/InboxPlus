import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inboxplus/ui/person_avatar.dart';

void main() {
  for (final scale in [1.0, 2.0, 3.0]) {
    for (final name in ['José Chen', '陈']) {
      final initial = name.characters.first.toUpperCase();
      testWidgets(
        'avatar initial $initial fits a 46-point avatar at ${scale}x text',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(320, 844),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: Center(child: PersonAvatar(name: name, size: 46)),
                ),
              ),
            ),
          );

          final glyph = find.text(initial);
          final paragraph = tester.renderObject<RenderParagraph>(glyph);
          expect(
            paragraph.size.height,
            greaterThanOrEqualTo(
              paragraph.getMaxIntrinsicHeight(double.infinity) - 0.01,
            ),
            reason: 'the initial is laid out shorter than its glyphs and clips',
          );
          final avatar = tester.getRect(find.byType(PersonAvatar));
          final inscribed = avatar.deflate(avatar.width * (1 - 1 / sqrt2) / 2);
          final glyphs = tester.getRect(glyph);
          expect(
            inscribed.inflate(0.01).contains(glyphs.topLeft),
            isTrue,
            reason: 'the initial extends past the circle',
          );
          expect(
            inscribed.inflate(0.01).contains(glyphs.bottomRight),
            isTrue,
            reason: 'the initial extends past the circle',
          );
        },
      );
    }
  }
}
