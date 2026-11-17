import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inboxplus/desktop_preview.dart';
import 'package:inboxplus/platform/app_environment.dart';
import 'package:inboxplus_storage/inboxplus_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preview messages survive startup after the fixture has aged', () async {
    final fixture = jsonDecode(
      await File('../../Tests/Fixtures/desktop-parity.json').readAsString(),
    ) as Map;
    final launchTime = DateTime.utc(2040, 1, 1, 12);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      AppEnvironment.native,
      (call) async => call.method == 'protectPath' ? true : null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(AppEnvironment.native, null),
    );
    final controller = await createPreviewController(
      fixture,
      clock: () => launchTime,
    );
    addTearDown(() async {
      await controller.close();
      await controller.environment.directory.delete(recursive: true);
    });

    for (final chat in fixture['conversations'] as List) {
      final route = ConversationRoute(
        chat['account'] as String,
        chat['id'] as String,
      );
      final expected = (fixture['messages'] as List).where(
        (message) =>
            message['account'] == route.accountId &&
            message['conversation'] == route.conversationId,
      );
      final messages = await controller.store.loadRecentMessages(route);
      expect(
        messages.map((message) => message.id),
        unorderedEquals(expected.map((message) => message['id'])),
        reason: '${route.accountId}/${route.conversationId}',
      );
      for (final message in messages) {
        final source = expected.firstWhere((item) => item['id'] == message.id);
        expect(
          message.timestamp,
          launchTime.subtract(Duration(minutes: source['minutesAgo'] as int)),
        );
      }
    }
    expect(controller.preferences.messageRetentionDays, 7);
  });
}
