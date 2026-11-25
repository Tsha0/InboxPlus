import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inboxplus/ui/person_avatar.dart';

void main() {
  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('avatar initial fits a 46-point avatar at ${scale}x text', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 844),
              textScaler: TextScaler.linear(scale),
            ),
            child: const Scaffold(
              body: Center(child: PersonAvatar(name: 'José Chen', size: 46)),
            ),
          ),
        ),
      );

      final initial = find.text('J');
      final paragraph = tester.renderObject<RenderParagraph>(initial);
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(
          paragraph.getMaxIntrinsicHeight(double.infinity) - 0.01,
        ),
        reason: 'the initial is laid out shorter than its glyphs and clips',
      );
      final avatar = tester.getRect(find.byType(PersonAvatar));
      final glyphs = tester.getRect(initial);
      expect(avatar.inflate(0.01).contains(glyphs.topLeft), isTrue);
      expect(avatar.inflate(0.01).contains(glyphs.bottomRight), isTrue);
    });
  }
}
