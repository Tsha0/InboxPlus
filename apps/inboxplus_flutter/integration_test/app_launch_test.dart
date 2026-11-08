import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inboxplus_flutter/app_controller.dart';
import 'package:inboxplus_flutter/ui/account_pages.dart';
import 'package:inboxplus_flutter/ui/contacts_page.dart';
import 'package:inboxplus_flutter/ui/inbox_app.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a fresh install opens with its embedded connectors', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    final controller = await AppController.open();
    try {
      // AppController.open keeps going without connectors, so a missing
      // native library would otherwise only show up as unavailable networks.
      expect({
        for (final network in controller.networks)
          if (network.available) network.id,
      }, containsAll(<String>['whatsapp', 'telegram']));

      await tester.pumpWidget(InboxPlusApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('Your inbox starts here'), findsOneWidget);

      await tester.tap(find.byKey(const Key('phone-tab-contacts')));
      await tester.pumpAndSettle();
      expect(find.byType(InboxContactsPage), findsOneWidget);

      await tester.tap(find.byKey(const Key('phone-tab-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(InboxSettingsPage), findsOneWidget);

      await tester.tap(find.byKey(const Key('phone-tab-inbox')));
      await tester.pumpAndSettle();
      expect(find.text('Your inbox starts here'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await controller.close();
    }
  });
}
