import 'dart:async' show Completer;
import 'dart:ui' show SemanticsAction;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoSwitch;
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart'
    show kSecondaryMouseButton, PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inboxplus_flutter/contact_suggestions.dart';
import 'package:inboxplus_flutter/ui/account_pages.dart'
    show ConnectAccountsDialog, formatByteCount, loginQrImageBytes;
import 'package:inboxplus_flutter/ui/inbox_app.dart';
import 'package:inboxplus_flutter/ui/inbox_ui_controller.dart';
import 'package:inboxplus_storage/inboxplus_storage.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  const appleAccount = AccountRecord(
    id: 'imessage-local',
    platform: 'imessage',
    displayName: 'iMessage',
    isConnected: true,
  );
  testWidgets('empty inbox offers account setup without sample conversations', (
    tester,
  ) async {
    final controller = _FakeController(accounts: [], conversations: []);
    await _pumpApp(tester, controller);

    expect(find.text('Your inbox starts here'), findsOneWidget);
    expect(find.text('Connect an account'), findsWidgets);
    expect(find.byType(ListTile), findsNothing);

    await tester.tap(find.text('Connect an account').first);
    await tester.pumpAndSettle();

    expect(find.text('Add an account'), findsOneWidget);
    expect(find.text('Telegram'), findsOneWidget);
    expect(controller.beginLoginCalls, isEmpty);
  });

  testWidgets('macOS update menu follows native availability', (tester) async {
    final controller = _FakeController()..updatesEnabled = true;
    await _pumpApp(tester, controller);
    final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
    final appMenu = bar.menus.first as PlatformMenu;
    final group = appMenu.menus.whereType<PlatformMenuItemGroup>().first;
    final update = group.members.singleWhere(
      (item) => item.label == 'Check for Updates…',
    );
    update.onSelected!();
    expect(controller.updateChecks, 1);

    controller.updatesEnabled = false;
    controller.notifyListeners();
    await tester.pumpAndSettle();
    final disabledBar = tester.widget<PlatformMenuBar>(
      find.byType(PlatformMenuBar),
    );
    final disabledMenu = disabledBar.menus.first as PlatformMenu;
    final disabledGroup = disabledMenu.menus
        .whereType<PlatformMenuItemGroup>()
        .first;
    expect(
      disabledGroup.members.where((item) => item.label == 'Check for Updates…'),
      isEmpty,
    );
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets('phone opens a conversation and returns to the inbox', (
    tester,
  ) async {
    final controller = _FakeController();
    await _pumpApp(tester, controller, size: const Size(390, 844));

    expect(find.byKey(const Key('message-composer')), findsNothing);
    await tester.tap(find.byKey(const Key('conversation-first-alice')));
    await tester.pumpAndSettle();

    expect(controller.selectedRoute, const ConversationRoute('first', 'alice'));
    expect(find.byKey(const Key('message-composer')), findsOneWidget);
    expect(find.byKey(const Key('inbox-search')), findsNothing);

    await tester.tap(find.byKey(const Key('back-to-inbox')));
    await tester.pumpAndSettle();

    expect(controller.selectedRoute, isNull);
    expect(find.byKey(const Key('inbox-search')), findsOneWidget);
    expect(find.byKey(const Key('message-composer')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('iOS iMessage placeholder cannot start account setup', (
    tester,
  ) async {
    final controller = _FakeController(
      accounts: [],
      conversations: [],
      additionalNetworks: const [
        NetworkCapability(
          id: 'imessage',
          name: 'iMessage',
          available: false,
          comingSoon: true,
          reason: 'Coming soon · Experimental iOS integration',
        ),
      ],
    );
    await _pumpApp(tester, controller, size: const Size(390, 844));
    await tester.tap(find.text('Connect an account').first);
    await tester.pumpAndSettle();

    final imessage = find.widgetWithText(ListTile, 'iMessage');
    expect(imessage, findsOneWidget);
    expect(
      find.text('Coming soon · Experimental iOS integration'),
      findsOneWidget,
    );
    expect(tester.widget<ListTile>(imessage).enabled, isFalse);
    expect(tester.widget<ListTile>(imessage).onTap, isNull);
    await tester.tap(imessage);
    await tester.pumpAndSettle();
    expect(controller.beginLoginCalls, isEmpty);
    expect(controller.login, isNull);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets(
    'desktop account grid orders capabilities and prevents duplicate accounts',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = _FakeController(
        conversations: [],
        additionalNetworks: const [
          NetworkCapability(
            id: 'discord',
            name: 'Discord',
            available: false,
            reason: 'Not supported yet',
          ),
          NetworkCapability(
            id: 'slack',
            name: 'Slack',
            available: false,
            comingSoon: true,
            reason: "It's coming soon",
          ),
          NetworkCapability(
            id: 'messenger',
            name: 'Messenger',
            available: true,
          ),
        ],
      );
      await _pumpApp(tester, controller, size: const Size(900, 600));
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(
        find.text('Pick the network you want to bring into Inbox+.'),
        findsOneWidget,
      );
      final messenger = find.byKey(const Key('picker-messenger'));
      final telegram = find.byKey(const Key('picker-telegram'));
      final whatsapp = find.byKey(const Key('picker-whatsapp'));
      final imessage = find.byKey(const Key('picker-imessage'));
      expect(tester.getTopLeft(messenger).dy, tester.getTopLeft(telegram).dy);
      expect(
        tester.getTopLeft(telegram).dx,
        lessThan(tester.getTopLeft(whatsapp).dx),
      );
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        expect(
          tester.getTopLeft(imessage).dy,
          greaterThan(tester.getTopLeft(messenger).dy),
        );
      } else {
        expect(imessage, findsNothing);
        expect(find.text('iMessage'), findsNothing);
      }
      expect(find.text('Already connected'), findsNWidgets(2));
      expect(
        tester
            .getSemantics(messenger)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
        tester
            .getSemantics(telegram)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
      await tester.tap(telegram);
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        await tester.tap(imessage);
      }
      expect(controller.beginLoginCalls, isEmpty);
      tester
          .getSemantics(messenger)
          .owner!
          .performAction(
            tester.getSemantics(messenger).id,
            SemanticsAction.tap,
          );
      await tester.pump();
      expect(controller.beginLoginCalls, ['messenger']);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account-picker')), findsNothing);
      expect(controller.cancelLoginCalls, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets('desktop account picker escapes and displays setup errors', (
    tester,
  ) async {
    final controller = _FakeController(accounts: [], conversations: []);
    controller.error = 'Could not prepare sign-in.';
    await _pumpApp(tester, controller);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ConnectAccountsDialog),
        matching: find.text(controller.error!),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ConnectAccountsDialog), findsNothing);
    expect(controller.cancelLoginCalls, 1);
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets(
    'desktop contact cards expose exact unlink and move actions at minimum size',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final person = ContactRecord(
        id: 'alice',
        displayName: 'Alice with a very long display name',
        identities: const [
          IdentityLink('first', 'shared'),
          IdentityLink('second', 'shared'),
        ],
      );
      final target = ContactRecord(id: 'bob', displayName: 'Bob');
      final controller = _FakeController(
        contacts: [person, target],
        conversations: [
          for (final account in ['first', 'second'])
            ConversationRecord(
              route: ConversationRoute(account, 'shared-chat'),
              title: 'A very long chat title that must fit the minimum desktop width',
              identityId: 'shared',
              latestActivity: DateTime(2026, 11, 5),
            ),
        ],
      );
      await _pumpApp(tester, controller, size: const Size(900, 600));
      await tester.tap(find.byTooltip('Contacts'));
      await tester.pumpAndSettle();
      final row = find.byKey(const Key('contact-row-alice'));
      expect(
        tester.getSemantics(row),
        isSemantics(
          label: person.displayName,
          value: 'WhatsApp · Telegram',
          isButton: true,
          hasTapAction: true,
          isSelected: false,
        ),
      );
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(tester.getSemantics(row), isSemantics(isSelected: true));
      final card = find.byKey(const Key('conversation-card-first-shared-chat'));
      expect(
        tester.getSemantics(card),
        isSemantics(isButton: true, hasTapAction: true),
      );
      await tester.tap(card, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Unlink conversation from this person'), findsNothing);
      expect(controller.savedContacts, isEmpty);
      await tester.tap(card, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      controller.contactSaveError = 'Could not save the local grouping.';
      await tester.tap(find.text('Unlink conversation from this person'));
      await tester.pumpAndSettle();
      expect(controller.savedContacts, isEmpty);
      expect(controller.contacts.first.identities, hasLength(2));
      expect(find.text(controller.contactSaveError!), findsWidgets);
      controller.contactSaveError = null;
      await tester.tap(card, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlink conversation from this person'));
      await tester.pumpAndSettle();
      expect(
        controller.savedContacts.single.identities.single.accountId,
        'second',
      );
      await tester.tap(card, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Bob'));
      await tester.pumpAndSettle();
      expect(controller.linkedIdentities.single.identity.accountId, 'first');
      expect(controller.linkedIdentities.single.identity.identityId, 'shared');
      expect(controller.linkedIdentities.single.person.id, 'bob');
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(
        controller.selectedRoute,
        const ConversationRoute('first', 'shared-chat'),
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'desktop suggestions link only after acceptance and retain failures',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = _FakeController(
        conversations: [
          for (final account in ['first', 'second'])
            ConversationRecord(
              route: ConversationRoute(account, 'chat'),
              title: 'José Chen',
              identityId: 'same',
              latestActivity: DateTime(2026, 11, 5),
            ),
        ],
      );
      await _pumpApp(tester, controller, size: const Size(900, 600));
      await tester.tap(find.byTooltip('Contacts'));
      await tester.pumpAndSettle();
      expect(find.text('Suggested links'), findsOneWidget);
      expect(find.text('WhatsApp · Telegram'), findsOneWidget);
      expect(controller.contacts, isEmpty);
      final action = find.bySemanticsLabel('Link José Chen across networks');
      expect(
        tester.getSemantics(action),
        isSemantics(isButton: true, hasTapAction: true),
      );
      controller.contactSaveError = 'Could not save this grouping.';
      await tester.tap(find.text('Link these?'));
      await tester.pumpAndSettle();
      expect(find.text(controller.contactSaveError!), findsWidgets);
      expect(controller.contacts, isEmpty);
      expect(find.text('Link these?'), findsOneWidget);
      controller.contactSaveError = null;
      await tester.tap(find.text('Link these?'));
      await tester.pumpAndSettle();
      expect(find.text('Link these?'), findsNothing);
      expect(find.text('2 conversations across your networks'), findsOneWidget);
      expect(controller.contacts.single.displayName, 'José Chen');
      expect(controller.sentDrafts, isEmpty);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'desktop Contacts orders by names instead of internal ids',
    (tester) async {
      final controller = _FakeController(
        contacts: [
          ContactRecord(id: '000', displayName: 'Riley'),
          ContactRecord(id: 'z', displayName: 'alex'),
          ContactRecord(id: 'b', displayName: 'Émilie'),
          ContactRecord(id: 'a', displayName: 'Maya'),
        ],
      );
      await _pumpApp(tester, controller, size: const Size(900, 600));
      await tester.tap(find.byTooltip('Contacts'));
      await tester.pumpAndSettle();
      final rows = ['z', 'b', 'a', '000']
          .map((id) => tester.getTopLeft(find.byKey(Key('contact-row-$id'))).dy)
          .toList();
      expect(rows, orderedEquals([...rows]..sort()));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets('new message submits the chosen account and recipient', (
    tester,
  ) async {
    final controller = _FakeController();
    await _pumpApp(tester, controller);

    await tester.tap(find.byTooltip('New message').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-message-account')), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-message-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Telegram · Telegram').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('new-message-recipient')),
      '  alice_example  ',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open conversation'));
    await tester.pumpAndSettle();

    expect(controller.startedConversations, hasLength(1));
    expect(controller.startedConversations.single.key, 'second');
    expect(controller.startedConversations.single.value, 'alice_example');
    expect(find.byKey(const Key('new-message-recipient')), findsNothing);
  });

  testWidgets('drafts remain with their conversation when selection changes', (
    tester,
  ) async {
    final controller = _FakeController();
    await _pumpApp(tester, controller);

    await tester.tap(find.byKey(const Key('conversation-first-alice')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('message-composer')),
      'Remember the train tickets',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('conversation-second-bob')));
    await tester.pumpAndSettle();
    expect(_composerText(tester), isEmpty);
    await tester.enterText(
      find.byKey(const Key('message-composer')),
      'See you at lunch',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('conversation-first-alice')));
    await tester.pumpAndSettle();

    expect(_composerText(tester), 'Remember the train tickets');
    expect(
      controller.draftFor(const ConversationRoute('second', 'bob'))?.body,
      'See you at lunch',
    );
    expect(controller.sentDrafts, isEmpty);
  });

  testWidgets('desktop new message offers Mac Contacts for iMessage', (
    tester,
  ) async {
    final controller = _FakeController(
      accounts: const [appleAccount],
      conversations: [],
      iMessageAvailable: true,
      onRecipientContacts: (_) async => const LocalRecipientSnapshot.available([
        LocalRecipient(name: 'Alex Morgan', address: 'alex@example.com'),
        LocalRecipient(name: 'Alex Morgan', address: '+14155550101'),
      ]),
    );
    await _pumpApp(tester, controller);
    await tester.tap(find.byTooltip('New message').first);
    await tester.pumpAndSettle();
    expect(find.text('Mac Contacts'), findsOneWidget);
    expect(find.text('Refresh Contacts'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    final query = find.byKey(const Key('new-message-recipient'));
    await tester.enterText(query, 'Alex');
    await tester.pumpAndSettle();
    expect(find.text('alex@example.com'), findsOneWidget);
    expect(find.text('+14155550101'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('+14155550101'));
    await tester.pumpAndSettle();
    expect(
      find.text('Recipient: Alex Morgan · +14155550101 · iMessage'),
      findsOneWidget,
    );
    expect(controller.startedConversations, isEmpty);
    expect(controller.sentDrafts, isEmpty);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(controller.startedConversations.single.key, 'imessage-local');
    expect(controller.startedConversations.single.value, '+14155550101');
    expect(controller.sentDrafts, isEmpty);
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets(
    'new message refreshes Contacts access and preserves manual entry',
    (tester) async {
      var reads = 0;
      final controller = _FakeController(
        accounts: const [appleAccount],
        conversations: [],
        iMessageAvailable: true,
        onRecipientContacts: (_) async => ++reads == 1
            ? const LocalRecipientSnapshot.accessUnavailable()
            : const LocalRecipientSnapshot.available([
                LocalRecipient(name: 'Maya Chen', address: 'maya@example.com'),
              ]),
      );
      await _pumpApp(tester, controller);
      await tester.tap(find.byTooltip('New message').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Contacts access is unavailable'),
        findsOneWidget,
      );
      final query = find.byKey(const Key('new-message-recipient'));
      await tester.enterText(query, 'manual@example.com');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Refresh Contacts'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(
        tester.widget<TextField>(query).controller!.text,
        'manual@example.com',
      );
      await tester.enterText(query, 'Maya');
      await tester.pumpAndSettle();
      expect(find.text('maya@example.com'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.startedConversations, isEmpty);
      expect(controller.sentDrafts, isEmpty);
    },
    variant: TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets(
    'new message ignores Contacts from an earlier account selection',
    (tester) async {
      final earlier = Completer<LocalRecipientSnapshot>();
      var reads = 0;
      final controller = _FakeController(
        accounts: const [
          appleAccount,
          AccountRecord(
            id: 'first',
            platform: 'whatsapp',
            displayName: 'WhatsApp',
            isConnected: true,
          ),
        ],
        conversations: [],
        iMessageAvailable: true,
        onRecipientContacts: (_) async => ++reads == 1
            ? earlier.future
            : const LocalRecipientSnapshot.available([
                LocalRecipient(name: 'Alex New', address: 'new@example.com'),
              ]),
      );
      await _pumpApp(tester, controller);
      await tester.tap(find.byTooltip('New message').first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('new-message-account')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('WhatsApp · WhatsApp').last);
      await tester.pumpAndSettle();
      expect(find.text('Mac Contacts'), findsNothing);
      await tester.tap(find.byKey(const Key('new-message-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('iMessage · iMessage').last);
      await tester.pumpAndSettle();
      earlier.complete(
        const LocalRecipientSnapshot.available([
          LocalRecipient(name: 'Alex Old', address: 'old@example.com'),
        ]),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('new-message-recipient')),
        'Alex',
      );
      await tester.pumpAndSettle();
      expect(find.text('new@example.com'), findsOneWidget);
      expect(find.text('old@example.com'), findsNothing);
      expect(controller.recipientRequests, [
        'imessage-local',
        'imessage-local',
      ]);
      expect(controller.startedConversations, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets(
    'desktop new message keeps input after failure and cannot close while opening',
    (tester) async {
      final opening = Completer<void>();
      var attempts = 0;
      final controller = _FakeController(
        onStartConversation: (_, _) async {
          if (++attempts == 1) await opening.future;
        },
      );
      await _pumpApp(tester, controller, size: const Size(900, 600));
      await tester.tap(find.byTooltip('New message').first);
      await tester.pumpAndSettle();
      final query = find.byKey(const Key('new-message-recipient'));
      await tester.enterText(query, '+14155550101');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 300));
      expect(query, findsOneWidget);
      controller.error = 'The recipient could not be opened.';
      opening.complete();
      await tester.pumpAndSettle();
      expect(find.text('The recipient could not be opened.'), findsOneWidget);
      expect(tester.widget<TextField>(query).controller!.text, '+14155550101');
      controller.error = null;
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(query, findsNothing);
      expect(attempts, 2);
      expect(controller.sentDrafts, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets('Enter sends the draft and Shift Enter inserts a new line', (
    tester,
  ) async {
    final controller = _FakeController();
    await _pumpApp(tester, controller);
    await tester.tap(find.byKey(const Key('conversation-first-alice')));
    await tester.pumpAndSettle();
    final composer = find.byKey(const Key('message-composer'));
    await tester.enterText(composer, 'First line');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(_composerText(tester), 'First line\n');
    expect(controller.sentDrafts, isEmpty);
    await tester.enterText(composer, 'Ready to send');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.sentDrafts, hasLength(1));
    expect(controller.sentDrafts.single.value, 'Ready to send');
    expect(_composerText(tester), isEmpty);
  });

  testWidgets(
    'unknown conversation activity has no epoch date',
    (tester) async {
      final controller = _FakeController(
        conversations: [
          ConversationRecord(
            route: const ConversationRoute('first', 'empty'),
            title: 'Empty chat',
            latestActivity: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
          ConversationRecord(
            route: const ConversationRoute('second', 'recent'),
            title: 'Recent chat',
            latestActivity: DateTime.now().subtract(const Duration(days: 1)),
          ),
        ],
      );
      await _pumpApp(tester, controller);
      expect(find.text('1/1'), findsNothing);
      final desktop = {
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }.contains(defaultTargetPlatform);
      expect(find.text('1d'), findsOneWidget);
      await tester.tap(find.byKey(const Key('conversation-first-empty')));
      await tester.pumpAndSettle();
      if (desktop) {
        expect(find.text('No recent messages'), findsOneWidget);
        expect(find.text('Start the conversation'), findsNothing);
        await tester.tap(find.byKey(const Key('desktop-rail-settings')));
        await tester.pumpAndSettle();
        expect(find.text('Connected'), findsOneWidget);
        expect(find.text('Last message yesterday'), findsOneWidget);
      } else {
        expect(find.text('Start the conversation'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'desktop account rows match the network wording and removal flow',
    (tester) async {
      final controller =
          _FakeController(
              accounts: [
                const AccountRecord(
                  id: 'first',
                  platform: 'whatsapp',
                  displayName: 'Preview account',
                  isConnected: true,
                ),
                const AccountRecord(
                  id: 'second',
                  platform: 'telegram',
                  displayName: 'telegram',
                ),
                if (defaultTargetPlatform == TargetPlatform.macOS)
                  const AccountRecord(
                    id: 'apple',
                    platform: 'imessage',
                    displayName: 'iMessage',
                    isConnected: true,
                  ),
              ],
              conversations: const [],
            )
            ..currentPreferences = const PreferencesRecord(
              disconnectedAccountIds: ['second'],
            )
            ..networkProblems['first'] = AccountNetworkProblem.signedOut;
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        controller.changingAccounts.add('apple');
      }
      Future<void> settle() async {
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await _pumpApp(tester, controller);
      await tester.tap(find.byKey(const Key('desktop-rail-settings')));
      await settle();

      expect(find.text('Preview account'), findsOneWidget);
      expect(find.text('telegram'), findsNothing);
      expect(
        find.text('Signed out of WhatsApp — remove it and add it again'),
        findsOneWidget,
      );
      expect(find.text('Disconnected — messages are kept'), findsOneWidget);
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        expect(
          tester
              .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator),
              )
              .semanticsLabel,
          'Updating iMessage',
        );
      } else {
        expect(find.textContaining('iMessage'), findsNothing);
      }

      await tester.tap(find.byTooltip('Manage Telegram'));
      await settle();
      expect(find.text('Reconnect'), findsOneWidget);
      expect(find.text('Remove account…'), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await settle();

      await tester.tap(find.byTooltip('Manage WhatsApp'));
      await settle();
      expect(find.text('Disconnect'), findsOneWidget);
      await tester.tap(find.text('Remove account…'));
      await settle();
      expect(find.text('Remove WhatsApp?'), findsOneWidget);
      expect(
        find.textContaining(
          'To keep the history in Inbox+, disconnect instead.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Sign out and remove'));
      await settle();
      expect(controller.removedAccounts, ['first']);

      if (defaultTargetPlatform == TargetPlatform.macOS) {
        await tester.tap(find.byTooltip('Manage iMessage'));
        await settle();
        expect(find.text('Remove account…'), findsNothing);
      } else {
        expect(find.byTooltip('Manage iMessage'), findsNothing);
      }
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  test('file sizes follow the Finder wording', () {
    for (final (bytes, wording) in [
      (0, 'Zero KB'),
      (1, '1 byte'),
      (999, '999 bytes'),
      (1499, '1 KB'),
      (1500, '2 KB'),
      (999500, '1 MB'),
      (1234567, '1.2 MB'),
      (15049999, '15 MB'),
      (999950000, '1 GB'),
      (1234567890, '1.23 GB'),
      (12345678901, '12.35 GB'),
    ]) {
      expect(formatByteCount(bytes), wording, reason: '$bytes bytes');
    }
  });

  test('named relative times follow the Foundation wording', () {
    final now = DateTime.utc(2026, 11, 6, 1, 18, 24);
    String before(Duration elapsed) =>
        namedRelativeTime(now.subtract(elapsed), now);
    expect(before(Duration.zero), 'now');
    expect(before(const Duration(seconds: 89)), '1 minute ago');
    expect(before(const Duration(seconds: 91)), '2 minutes ago');
    expect(before(const Duration(seconds: 5399)), '1 hour ago');
    expect(before(const Duration(seconds: 5401)), '2 hours ago');
    for (final (days, wording) in [
      (1.0, 'yesterday'),
      (1.5, '2 days ago'),
      (7.0, 'last week'),
      (13.0, '2 weeks ago'),
      (26.0, '3 weeks ago'),
      (27.0, '4 weeks ago'),
      (29.0, '4 weeks ago'),
      (31.0, 'last month'),
      (40.0, '2 months ago'),
      (300.0, '10 months ago'),
      (350.0, 'last year'),
      (548.0, 'last year'),
      (700.0, '2 years ago'),
    ]) {
      final elapsed = Duration(seconds: (days * 86400).round());
      expect(before(elapsed), wording, reason: '$days days');
    }
  });

  testWidgets(
    'person conversation cards omit unknown activity dates',
    (tester) async {
      final controller = _FakeController(
        conversations: [
          ConversationRecord(
            route: const ConversationRoute('first', 'empty'),
            title: 'Empty chat',
            latestActivity: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            identityId: 'local-identity',
          ),
        ],
        contacts: [
          ContactRecord(
            id: 'person',
            displayName: 'Grouped person',
            identities: const [IdentityLink('first', 'local-identity')],
          ),
        ],
      );
      await _pumpApp(tester, controller);
      await tester.tap(find.text('Grouped person'));
      await tester.pumpAndSettle();
      expect(find.text('Rename person…'), findsOneWidget);
      expect(find.textContaining('1970'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'same conversation id on different accounts keeps drafts separate',
    (tester) async {
      final controller = _FakeController(
        conversations: [
          _conversation('first', 'shared', 'Alice'),
          _conversation('second', 'shared', 'Bob'),
        ],
      );
      await _pumpApp(tester, controller);

      await tester.tap(find.byKey(const Key('conversation-first-shared')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('message-composer')),
        'Only for Alice',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('conversation-second-shared')));
      await tester.pumpAndSettle();
      expect(_composerText(tester), isEmpty);
      await tester.enterText(
        find.byKey(const Key('message-composer')),
        'For Bob',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-message')));
      await tester.pumpAndSettle();

      expect(controller.sentDrafts, hasLength(1));
      expect(
        controller.sentDrafts.single.key,
        const ConversationRoute('second', 'shared'),
      );
      expect(controller.sentDrafts.single.value, 'For Bob');
      expect(
        controller.draftFor(const ConversationRoute('first', 'shared'))?.body,
        'Only for Alice',
      );
    },
  );

  testWidgets('visiting Settings preserves the inbox search', (tester) async {
    final controller = _FakeController();
    await _pumpApp(tester, controller);

    await tester.enterText(find.byKey(const Key('inbox-search')), 'Alice');
    await tester.pump();
    expect(find.byKey(const Key('conversation-first-alice')), findsOneWidget);
    expect(find.byKey(const Key('conversation-second-bob')), findsNothing);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Connected accounts'), findsOneWidget);
    await tester.tap(find.byTooltip('Inbox'));
    await tester.pumpAndSettle();

    final search = tester.widget<TextField>(
      find.byKey(const Key('inbox-search')),
    );
    expect(search.controller?.text, 'Alice');
    expect(find.byKey(const Key('conversation-first-alice')), findsOneWidget);
    expect(find.byKey(const Key('conversation-second-bob')), findsNothing);
  });

  testWidgets(
    'unavailable account explains availability and cannot start login',
    (tester) async {
      final controller = _FakeController(
        accounts: [],
        conversations: [],
        additionalNetworks: const [
          NetworkCapability(
            id: 'discord',
            name: 'Discord',
            available: false,
            reason: 'Not supported yet',
          ),
        ],
      );
      await _pumpApp(tester, controller, size: const Size(390, 844));

      await tester.tap(find.text('Connect an account'));
      await tester.pumpAndSettle();
      expect(find.text('Not supported yet'), findsOneWidget);
      await tester.tap(find.text('Discord'));
      await tester.pump();

      expect(controller.beginLoginCalls, isEmpty);
      await tester.tap(find.byTooltip('Close account setup'));
      await tester.pumpAndSettle();
      expect(controller.cancelLoginCalls, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone transcript fits an attachment and staged files', (
    tester,
  ) async {
    const route = ConversationRoute('first', 'alice');
    final controller = _FakeController(
      messages: {
        route: [
          MessageRecord(
            id: 'attachment-message',
            route: route,
            body: 'The itinerary is attached.',
            timestamp: DateTime(2026, 11, 4, 12),
            isOutgoing: false,
            attachments: const [
              AttachmentRecord(
                id: 'itinerary',
                kind: 'file',
                fileName: 'A long itinerary filename for our trip.pdf',
                byteCount: 2048,
              ),
            ],
          ),
        ],
      },
    );
    controller._drafts[route] = DraftRecord(
      route: route,
      body: 'Thanks!',
      revision: 1,
      attachments: const [
        AttachmentRecord(
          id: 'staged',
          kind: 'file',
          fileName: 'Return tickets.pdf',
        ),
      ],
    );
    await _pumpApp(tester, controller, size: const Size(320, 700));

    await tester.tap(find.byKey(const Key('conversation-first-alice')));
    await tester.pumpAndSettle();

    expect(find.text('The itinerary is attached.'), findsOneWidget);
    expect(find.text('Return tickets.pdf'), findsOneWidget);
    expect(_composerText(tester), 'Thanks!');
    expect(tester.takeException(), isNull);
  });

  testWidgets('conversation actions mute and hide without deleting history', (
    tester,
  ) async {
    const route = ConversationRoute('first', 'alice');
    final controller = _FakeController();
    await _pumpApp(tester, controller, size: const Size(390, 844));
    await tester.tap(find.byKey(const Key('conversation-first-alice')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Conversation actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mute conversation'));
    await tester.pumpAndSettle();
    expect(controller.preferencesFor(route).isMuted, isTrue);

    await tester.tap(find.byTooltip('Conversation actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide conversation'));
    await tester.pumpAndSettle();
    expect(controller.preferencesFor(route).hiddenAt, isNotNull);
    expect(controller.conversations.any((item) => item.route == route), isTrue);
    await tester.tap(find.byKey(const Key('back-to-inbox')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation-first-alice')), findsNothing);
    await tester.tap(find.text('1 hidden'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation-first-alice')), findsOneWidget);
    expect(find.byKey(const Key('conversation-second-bob')), findsNothing);
    await tester.tap(find.byKey(const Key('conversation-first-alice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Conversation actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unhide conversation'));
    await tester.pumpAndSettle();
    expect(controller.preferencesFor(route).hiddenAt, isNull);
    await tester.tap(find.byKey(const Key('back-to-inbox')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to Inbox'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation-first-alice')), findsOneWidget);
  });

  testWidgets('editing a contact preserves a disconnected account identity', (
    tester,
  ) async {
    final controller = _FakeController(
      contacts: [
        ContactRecord(
          id: 'alice',
          displayName: 'Alice',
          identities: const [
            IdentityLink('removed-account', 'alice-network-id'),
          ],
        ),
      ],
    );
    await _pumpApp(tester, controller, size: const Size(390, 844));
    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit Alice'));
    await tester.pumpAndSettle();

    expect(find.text('Disconnected account'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Save contact'));
    await tester.pumpAndSettle();

    expect(
      controller.savedContacts.single.identities.single.accountId,
      'removed-account',
    );
    expect(
      controller.savedContacts.single.identities.single.identityId,
      'alice-network-id',
    );
  });

  testWidgets('a failed contact save keeps the editor open with the input', (
    tester,
  ) async {
    final controller = _FakeController()
      ..contactSaveError = 'This identity is already linked.';
    await _pumpApp(tester, controller);
    await tester.tap(find.byTooltip('Contacts'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add contact'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Alice');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Contact ID or username'),
      'alice123',
    );
    await tester.tap(find.text('Save contact'));
    await tester.pumpAndSettle();

    expect(find.text('Add contact'), findsOneWidget);
    expect(find.text('This identity is already linked.'), findsWidgets);
    expect(find.text('alice123'), findsOneWidget);
    expect(controller.savedContacts, isEmpty);
  });

  testWidgets('new message fits above the phone keyboard', (tester) async {
    final controller = _FakeController();
    await _pumpApp(tester, controller, size: const Size(390, 600));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(find.byTooltip('New message'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new-message-recipient')), findsOneWidget);
    expect(find.text('Open conversation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reconnect keeps the selected existing account', (tester) async {
    final controller = _FakeController(
      accounts: const [
        AccountRecord(
          id: 'existing-telegram',
          platform: 'telegram',
          displayName: 'Telegram',
        ),
      ],
    );
    await _pumpApp(tester, controller, size: const Size(390, 844));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reconnect Telegram'));
    await tester.pumpAndSettle();

    expect(controller.reconnectedAccounts, ['existing-telegram']);
    expect(find.byTooltip('Close account setup'), findsOneWidget);
    expect(controller.beginLoginCalls, isEmpty);
  });

  testWidgets('a restricted conversation explains why sending is unavailable', (
    tester,
  ) async {
    const route = ConversationRoute('first', 'alice');
    final controller = _FakeController(
      sendingUnavailableReasons: {
        route: 'Sending in this encrypted chat is not available yet.',
      },
    );
    await _pumpApp(tester, controller);
    await tester.tap(find.byKey(const Key('conversation-first-alice')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('message-composer')),
      'Keep as a draft',
    );
    await tester.pump();

    expect(
      find.text('Sending in this encrypted chat is not available yet.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('send-message')))
          .onPressed,
      isNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.sentDrafts, isEmpty);
    expect(_composerText(tester), 'Keep as a draft');
  });

  for (final wasSent in [true, false]) {
    testWidgets(
      'checking uncertain delivery as $wasSent never resends automatically',
      (tester) async {
        const route = ConversationRoute('first', 'alice');
        final controller = _FakeController(
          messages: {
            route: [_failedMessage(route)],
          },
          unconfirmedMessages: {
            route: {'uncertain'},
          },
        );
        await _pumpApp(tester, controller, size: const Size(320, 700));
        await tester.tap(find.byKey(const Key('conversation-first-alice')));
        await tester.pumpAndSettle();
        expect(find.text('Retry'), findsNothing);
        await tester.tap(find.text('Check delivery'));
        await tester.pumpAndSettle();
        expect(find.text('Check the original app first'), findsOneWidget);
        await tester.tap(
          find.text(wasSent ? 'It was sent' : 'It was not sent'),
        );
        await tester.pumpAndSettle();

        expect(controller.resolvedDeliveries, [
          (route: route, messageId: 'uncertain', wasSent: wasSent),
        ]);
        expect(controller.retriedMessages, isEmpty);
        expect(controller.sentDrafts, isEmpty);
      },
    );
  }

  testWidgets('canceling a delivery check keeps the unresolved message', (
    tester,
  ) async {
    const route = ConversationRoute('first', 'alice');
    final controller = _FakeController(
      messages: {
        route: [_failedMessage(route)],
      },
      unconfirmedMessages: {
        route: {'uncertain'},
      },
    );
    await _pumpApp(tester, controller);
    await tester.tap(find.byKey(const Key('conversation-first-alice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check delivery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Check delivery'), findsOneWidget);
    expect(controller.resolvedDeliveries, isEmpty);
    expect(controller.retriedMessages, isEmpty);
    expect(controller.sentDrafts, isEmpty);
  });

  testWidgets('a confirmed send failure still offers Retry', (tester) async {
    const route = ConversationRoute('first', 'alice');
    final controller = _FakeController(
      messages: {
        route: [_failedMessage(route)],
      },
    );
    await _pumpApp(tester, controller);
    await tester.tap(find.byKey(const Key('conversation-first-alice')));
    await tester.pumpAndSettle();
    expect(find.text('Check delivery'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(controller.retriedMessages, [
      (route: route, messageId: 'uncertain'),
    ]);
    expect(controller.resolvedDeliveries, isEmpty);
  });

  testWidgets(
    'desktop saves a downloaded attachment from the text context menu',
    (tester) async {
      const route = ConversationRoute('first', 'alice');
      final controller = _FakeController(
        messages: {
          route: [
            MessageRecord(
              id: 'file-message',
              route: route,
              body: 'Here is the itinerary.',
              timestamp: DateTime(2026, 11, 5),
              isOutgoing: false,
              attachments: const [
                AttachmentRecord(
                  id: 'itinerary',
                  kind: 'file',
                  fileName: 'Itinerary.txt',
                  localPath: '/private/fixture/media/itinerary.txt',
                ),
              ],
            ),
          ],
        },
      );
      await _pumpApp(tester, controller, size: const Size(900, 600));
      await tester.tap(find.byKey(const Key('conversation-first-alice')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Here is the itinerary.').last,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Save Attachment…'), findsOneWidget);
      await tester.tap(find.text('Save Attachment…'));
      await tester.pumpAndSettle();
      expect(controller.savedAttachments, [
        (route: route, messageId: 'file-message', attachmentId: 'itinerary'),
      ]);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'desktop attachment menu scopes multiple files and disables an undownloaded file',
    (tester) async {
      const route = ConversationRoute('first', 'alice');
      final controller = _FakeController(
        messages: {
          route: [
            MessageRecord(
              id: 'multiple-files',
              route: route,
              body: '',
              timestamp: DateTime(2026, 11, 5),
              isOutgoing: false,
              attachments: const [
                AttachmentRecord(
                  id: 'ready',
                  kind: 'file',
                  fileName: 'Ready.txt',
                  localPath: '/private/fixture/media/ready.txt',
                  isDownloadable: false,
                ),
                AttachmentRecord(
                  id: 'waiting',
                  kind: 'file',
                  fileName: 'Waiting.txt',
                ),
              ],
            ),
          ],
        },
      );
      await _pumpApp(tester, controller, size: const Size(900, 600));
      await tester.tap(find.byKey(const Key('conversation-first-alice')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Ready.txt'),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final waiting = tester.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, 'Save Waiting.txt…'),
      );
      expect(waiting.enabled, isFalse);
      await tester.tap(find.text('Save Ready.txt…'));
      await tester.pumpAndSettle();
      expect(controller.savedAttachments, [
        (route: route, messageId: 'multiple-files', attachmentId: 'ready'),
      ]);
      expect(controller.downloadedAttachments, isEmpty);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  group('received remote image', () {
    const route = ConversationRoute('first', 'alice');
    _FakeController remoteImage() => _FakeController(
      messages: {
        route: [
          MessageRecord(
            id: 'photo-message',
            route: route,
            body: '',
            timestamp: DateTime(2026, 11, 5),
            isOutgoing: false,
            attachments: const [
              AttachmentRecord(
                id: 'photo',
                kind: 'image',
                fileName: 'image',
                mimeType: 'image/jpeg',
              ),
            ],
          ),
        ],
      },
    );

    testWidgets('loads inline without a manual download', (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = remoteImage();
      await _pumpApp(tester, controller, size: const Size(390, 844));
      await tester.tap(find.byKey(const Key('conversation-first-alice')));
      await tester.pumpAndSettle();
      expect(controller.loadedImages, [
        (route: route, messageId: 'photo-message', attachmentId: 'photo'),
      ]);
      expect(find.bySemanticsLabel('Loading image'), findsOneWidget);
      expect(find.byTooltip('Download attachment'), findsNothing);
      expect(controller.downloadedAttachments, isEmpty);
      semantics.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('a failed load offers a retry instead of reloading', (
      tester,
    ) async {
      final controller = remoteImage()
        ..imageLoadStates['photo'] = AttachmentLoadState.failed;
      await _pumpApp(tester, controller, size: const Size(390, 844));
      await tester.tap(find.byKey(const Key('conversation-first-alice')));
      await tester.pumpAndSettle();
      expect(find.text('Image unavailable'), findsOneWidget);
      expect(controller.loadedImages, isEmpty);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(controller.loadedImages, hasLength(1));
    });

    testWidgets('an oversized image says so without loading', (tester) async {
      final controller = remoteImage()
        ..imageLoadStates['photo'] = AttachmentLoadState.tooLarge;
      await _pumpApp(tester, controller, size: const Size(390, 844));
      await tester.tap(find.byKey(const Key('conversation-first-alice')));
      await tester.pumpAndSettle();
      expect(find.text('Image too large to preview'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(controller.loadedImages, isEmpty);
    });
  });

  testWidgets(
    'desktop local image preview saves and closes back to the draft',
    (tester) async {
      final semantics = tester.ensureSemantics();
      const route = ConversationRoute('first', 'alice');
      final controller = _FakeController(
        messages: {
          route: [
            MessageRecord(
              id: 'image-message',
              route: route,
              body: '',
              timestamp: DateTime(2026, 11, 5),
              isOutgoing: false,
              attachments: const [
                AttachmentRecord(
                  id: 'image',
                  kind: 'image',
                  fileName: 'Photo.png',
                  localPath: '/private/fixture/media/photo.png',
                  isDownloadable: false,
                ),
              ],
            ),
          ],
        },
      );
      controller.updateDraft(route, 'Keep this text');
      await _pumpApp(tester, controller, size: const Size(900, 600));
      await tester.tap(find.byKey(const Key('conversation-first-alice')));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Preview Photo.png'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Close preview'), findsWidgets);
      await tester.tap(find.text('Save As…'));
      await tester.pumpAndSettle();
      expect(controller.savedAttachments, [
        (route: route, messageId: 'image-message', attachmentId: 'image'),
      ]);
      await tester.tap(find.byTooltip('Close preview'));
      await tester.pumpAndSettle();
      expect(_composerText(tester), 'Keep this text');
      expect(controller.sentDrafts, isEmpty);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'desktop opens a local-only attachment without requiring a download',
    (tester) async {
      final semantics = tester.ensureSemantics();
      const route = ConversationRoute('first', 'alice');
      final controller = _FakeController(
        messages: {
          route: [
            MessageRecord(
              id: 'local-message',
              route: route,
              body: '',
              timestamp: DateTime(2026, 11, 5),
              isOutgoing: false,
              attachments: const [
                AttachmentRecord(
                  id: 'local-file',
                  kind: 'file',
                  fileName: 'Local itinerary.txt',
                  localPath: '/private/fixture/media/local.txt',
                  isDownloadable: false,
                ),
              ],
            ),
          ],
        },
      );
      await _pumpApp(tester, controller);
      await tester.tap(find.byKey(const Key('conversation-first-alice')));
      await tester.pumpAndSettle();
      expect(find.text('Local itinerary.txt'), findsOneWidget);
      expect(find.text('This shared item is unavailable.'), findsNothing);
      expect(find.byTooltip('Download attachment'), findsNothing);
      final open = tester.getSemantics(
        find.bySemanticsLabel('Open Local itinerary.txt'),
      );
      expect(
        open,
        matchesSemantics(
          label: 'Open Local itinerary.txt',
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      open.owner!.performAction(open.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(controller.openedAttachments, [
        '/private/fixture/media/local.txt',
      ]);
      open.owner!.performAction(open.id, SemanticsAction.focus);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.openedAttachments, hasLength(2));
      semantics.dispose();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  for (final platform in ['instagram', 'messenger']) {
    testWidgets(
      'shared $platform links open the named app without downloading',
      (tester) async {
        const route = ConversationRoute('first', 'alice');
        final controller = _FakeController(
          accounts: [
            AccountRecord(
              id: 'first',
              platform: platform,
              displayName: 'My account',
              isConnected: true,
            ),
          ],
          messages: {
            route: [
              MessageRecord(
                id: 'shared-reel',
                route: route,
                body: 'From our trip',
                timestamp: DateTime(2026, 11, 4),
                isOutgoing: false,
                attachments: [
                  AttachmentRecord(
                    id: 'reel',
                    kind: 'link',
                    fileName: 'Shared reel',
                    isDownloadable: false,
                    deepLink: platform == 'instagram'
                        ? 'https://www.instagram.com/reel/example/'
                        : 'https://www.facebook.com/reel/example/',
                  ),
                ],
              ),
            ],
          },
        );
        await _pumpApp(tester, controller, size: const Size(320, 700));
        await tester.tap(find.byKey(const Key('conversation-first-alice')));
        await tester.pumpAndSettle();

        expect(find.byTooltip('Download attachment'), findsNothing);
        await tester.tap(
          find.text(
            platform == 'instagram' ? 'Open in Instagram' : 'Open in Facebook',
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.openedAttachmentLinks, [
          (route: route, messageId: 'shared-reel', attachmentId: 'reel'),
        ]);
        expect(controller.downloadedAttachments, isEmpty);
      },
    );
  }

  testWidgets(
    'non-downloadable content without a link has no open or download action',
    (tester) async {
      const route = ConversationRoute('first', 'alice');
      final controller = _FakeController(
        messages: {
          route: [
            MessageRecord(
              id: 'shared-post',
              route: route,
              body: '',
              timestamp: DateTime(2026, 11, 4),
              isOutgoing: false,
              attachments: const [
                AttachmentRecord(
                  id: 'missing',
                  kind: 'link',
                  isDownloadable: false,
                ),
              ],
            ),
          ],
        },
      );
      await _pumpApp(tester, controller);
      await tester.tap(find.byKey(const Key('conversation-first-alice')));
      await tester.pumpAndSettle();

      expect(find.text('This shared item is unavailable.'), findsOneWidget);
      expect(find.byTooltip('Message actions'), findsNothing);
      expect(find.byTooltip('Download attachment'), findsNothing);
      expect(find.text('Open in Instagram'), findsNothing);
      expect(find.text('Open in Facebook'), findsNothing);
      expect(controller.openedAttachmentLinks, isEmpty);
      expect(controller.downloadedAttachments, isEmpty);
      if (isDesktopPlatform) {
        await tester.tap(
          find.text('This shared item is unavailable.'),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets('$platform uses the desktop panes at the minimum window size', (
      tester,
    ) async {
      final controller = _FakeController();
      await _pumpApp(tester, controller, size: const Size(900, 600));
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byKey(const Key('desktop-rail-inbox')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Search inbox')), findsWidgets);
      expect(find.text('Choose a conversation'), findsOneWidget);
      await tester.tap(find.byKey(const Key('conversation-first-alice')));
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsWidgets);
      expect(find.byKey(const Key('message-composer')), findsOneWidget);
      expect(find.byKey(const Key('conversation-first-alice')), findsOneWidget);
      expect(find.byKey(const Key('back-to-inbox')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Attach a file')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Send message')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Mute conversation')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Message')), findsWidgets);
      await tester.tap(find.byKey(const Key('desktop-rail-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('desktop-preferences')), findsOneWidget);
      expect(find.text('Show message previews'), findsOneWidget);
      expect(find.text('Classic'), findsOneWidget);
      expect(find.text('Night Swim'), findsOneWidget);
      expect(find.text('Background'), findsOneWidget);
      if (platform != TargetPlatform.macOS) {
        expect(find.textContaining('iMessage'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant({platform}));
  }

  testWidgets(
    'desktop logo has no themed button surface behind its rounded tile',
    (tester) async {
      final controller = _FakeController()
        ..currentPreferences = const PreferencesRecord(themePreset: 'sunset');
      await _pumpApp(tester, controller);
      final logo = find.bySemanticsLabel('Inbox+ logo');
      final surface = find.descendant(
        of: logo,
        matching: find.byType(Material),
      );
      expect(tester.widget<Material>(surface).color, Colors.transparent);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(logo));
      await tester.pumpAndSettle();
      expect(tester.widget<Material>(surface).color, Colors.transparent);
      await tester.tap(logo);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.widget<Material>(surface).color, Colors.transparent);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'desktop logo spins only its mark and keeps the tile upright',
    (tester) async {
      final controller = _FakeController();
      await _pumpApp(tester, controller);
      final logo = find.bySemanticsLabel('Inbox+ logo');
      final artwork = find.descendant(of: logo, matching: find.byType(Image));
      final tile = find.descendant(of: logo, matching: find.byType(ClipRRect));
      expect(artwork, findsOneWidget);
      expect(tile, findsOneWidget);
      final markTransform = find.ancestor(
        of: artwork,
        matching: find.byKey(const Key('desktop-logo-mark')),
      );
      expect(markTransform, findsOneWidget);
      expect(find.ancestor(of: tile, matching: markTransform), findsNothing);
      await tester.tap(logo);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final rotation = tester.widget<Transform>(markTransform).transform;
      expect(rotation.entry(0, 1).abs(), greaterThan(.01));
      for (final transform in tester.widgetList<Transform>(
        find.ancestor(of: tile, matching: find.byType(Transform)),
      )) {
        expect(transform.transform.entry(0, 1), 0);
        expect(transform.transform.entry(1, 0), 0);
      }
      final background = tester.widget<ColoredBox>(
        find.descendant(of: tile, matching: find.byType(ColoredBox)).first,
      );
      expect(background.color, Colors.black);
      await tester.tap(logo);
      await tester.pumpAndSettle();
      expect(controller.sentDrafts, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'desktop logo honors reduced motion with a glow and no rotation',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final controller = _FakeController();
      await _pumpApp(tester, controller);
      final logo = find.bySemanticsLabel('Inbox+ logo');
      await tester.tap(logo);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      final rotation = tester
          .widget<Transform>(find.byKey(const Key('desktop-logo-mark')))
          .transform;
      expect(rotation.entry(0, 0), 1);
      expect(rotation.entry(0, 1), 0);
      expect(find.bySemanticsLabel('Inbox+ logo'), findsOneWidget);
      final glow =
          tester
                  .widget<DecoratedBox>(
                    find.byKey(const Key('desktop-logo-glow')),
                  )
                  .decoration
              as BoxDecoration;
      expect(glow.boxShadow!.single.color.a, greaterThan(0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'desktop rail uses the original tray people compose and settings symbols',
    (tester) async {
      await _pumpApp(tester, _FakeController());
      expect(find.byIcon(CupertinoIcons.tray_full_fill), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.person_2_fill), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.square_pencil), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.gear_alt_fill), findsOneWidget);
      expect(find.byKey(const Key('desktop-rail-inbox')), findsOneWidget);
      expect(find.byKey(const Key('desktop-rail-settings')), findsOneWidget);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'desktop menu accelerators open every menu and preserve editing focus',
    (tester) async {
      final controller = _FakeController();
      await _pumpApp(tester, controller);
      await tester.tap(find.byKey(const Key('conversation-first-alice')));
      await tester.pumpAndSettle();
      final composer = find.byKey(const Key('message-composer'));
      const draft = 'Keep the keyboard draft';
      await tester.enterText(composer, draft);
      final field = tester.widget<TextField>(composer);
      const selection = TextSelection(baseOffset: 5, extentOffset: 17);
      field.controller!.selection = selection;
      await tester.pumpAndSettle();
      for (final (key, character, entry) in [
        (LogicalKeyboardKey.keyF, 'f', find.text('New Message…')),
        (LogicalKeyboardKey.keyE, 'e', find.text('Select All')),
        (LogicalKeyboardKey.keyN, 'n', find.text('Next Conversation')),
        (LogicalKeyboardKey.keyC, 'c', find.textContaining('Mark as')),
        (LogicalKeyboardKey.keyH, 'h', find.text('Inbox+ Help')),
      ]) {
        final menuItem = find.descendant(
          of: find.byType(MenuItemButton),
          matching: entry,
        );
        await _openMenuWithAlt(tester, key, character);
        expect(menuItem, findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(MenuItemButton), findsNothing);
        expect(field.focusNode!.hasFocus, isTrue);
        expect(field.controller!.selection, selection);
        expect(_composerText(tester), draft);
      }
      expect(controller.sentDrafts, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'desktop Edit menu edits the draft and restores composer focus',
    (tester) async {
      var clipboard = '';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
            return null;
          }
          return switch (call.method) {
            'Clipboard.getData' => {'text': clipboard},
            'Clipboard.hasStrings' => {'value': clipboard.isNotEmpty},
            _ => null,
          };
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final controller = _FakeController();
      await _pumpApp(tester, controller);
      await tester.tap(find.byKey(const Key('conversation-first-alice')));
      await tester.pumpAndSettle();
      final composer = find.byKey(const Key('message-composer'));
      const draft = 'A draft to edit';
      await tester.enterText(composer, draft);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await _chooseEditMenuItem(tester, 'Select All');
      final field = tester.widget<TextField>(composer);
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: draft.length),
      );
      expect(field.focusNode!.hasFocus, isTrue);
      expect(_composerText(tester), draft);
      await _chooseEditMenuItem(tester, 'Copy');
      expect(clipboard, draft);
      expect(_composerText(tester), draft);
      await _chooseEditMenuItem(tester, 'Cut');
      expect(clipboard, draft);
      expect(_composerText(tester), isEmpty);
      await tester.pump(const Duration(milliseconds: 600));
      await _chooseEditMenuItem(tester, 'Paste');
      expect(_composerText(tester), draft);
      await tester.pump(const Duration(milliseconds: 600));
      await _chooseEditMenuItem(tester, 'Undo');
      expect(_composerText(tester), isEmpty);
      await _chooseEditMenuItem(tester, 'Redo');
      expect(_composerText(tester), draft);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(controller.sentDrafts, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'desktop Edit menu follows search focus without changing the draft',
    (tester) async {
      final controller = _FakeController();
      await _pumpApp(tester, controller);
      await tester.tap(find.byKey(const Key('conversation-first-alice')));
      await tester.pumpAndSettle();
      const draft = 'Keep this draft';
      await tester.enterText(find.byKey(const Key('message-composer')), draft);
      final search = find.byKey(const Key('inbox-search'));
      await tester.enterText(search, 'Alice');
      await tester.pumpAndSettle();
      await _chooseEditMenuItem(tester, 'Select All');
      final field = tester.widget<TextField>(search);
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      expect(field.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(field.controller!.text, isEmpty);
      expect(_composerText(tester), draft);
      expect(controller.sentDrafts, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'desktop Edit menu keyboard activation and cancellation preserve the target',
    (tester) async {
      final controller = _FakeController();
      await _pumpApp(tester, controller);
      await tester.tap(find.byKey(const Key('conversation-first-alice')));
      await tester.pumpAndSettle();
      final composer = find.byKey(const Key('message-composer'));
      const draft = 'Keep this selection';
      await tester.enterText(composer, draft);
      final field = tester.widget<TextField>(composer);
      const selection = TextSelection(baseOffset: 5, extentOffset: 9);
      field.controller!.selection = selection;
      await tester.pumpAndSettle();
      await _openMenuWithAlt(tester, LogicalKeyboardKey.keyE, 'e');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MenuItemButton, 'Select All'), findsNothing);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(field.controller!.selection, selection);
      expect(_composerText(tester), draft);
      await _openMenuWithAlt(tester, LogicalKeyboardKey.keyE, 'e');
      final selectAll = find.descendant(
        of: find.byType(MenuItemButton),
        matching: find.text('Select All'),
      );
      for (var step = 0; step < 8; step++) {
        if (Focus.of(tester.element(selectAll)).hasPrimaryFocus) break;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(Focus.of(tester.element(selectAll)).hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: draft.length),
      );
      expect(field.focusNode!.hasFocus, isTrue);
      expect(_composerText(tester), draft);
      expect(controller.sentDrafts, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'desktop Reply focuses the composer and preserves text when canceled',
    (tester) async {
      const route = ConversationRoute('first', 'alice');
      final controller = _FakeController(
        canReply: true,
        messages: {
          route: [
            MessageRecord(
              id: 'original',
              route: route,
              body: 'Original message',
              timestamp: DateTime(2026, 11, 5),
              isOutgoing: false,
            ),
            MessageRecord(
              id: 'pending',
              route: route,
              body: 'Pending message',
              timestamp: DateTime(2026, 11, 5, 1),
              isOutgoing: true,
              deliveryState: DeliveryState.pending,
            ),
          ],
        },
      );
      await _pumpApp(tester, controller);
      await tester.tap(find.byKey(const Key('conversation-first-alice')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Pending message').last,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsNothing);
      expect(find.text('Copy Text'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Original message'),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect(find.text('Replying to Alice'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Cancel reply')), findsWidgets);
      final composer = find.byKey(const Key('message-composer'));
      expect(tester.widget<TextField>(composer).focusNode!.hasFocus, isTrue);
      await tester.enterText(composer, 'My reply');
      await tester.pumpAndSettle();
      expect(controller.draftFor(route)?.replyToMessageId, 'original');
      await tester.tap(find.byTooltip('Cancel reply'));
      await tester.pumpAndSettle();
      expect(_composerText(tester), 'My reply');
      expect(controller.draftFor(route)?.replyToMessageId, isNull);
      expect(find.text('Replying to Alice'), findsNothing);
      expect(controller.sentDrafts, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets(
    'desktop reaction menu includes existing emoji and pills target the selected message',
    (tester) async {
      const route = ConversationRoute('first', 'alice');
      final controller = _FakeController(
        canReact: true,
        reactionCounts: {'👍': 2, '🎉': 1},
        ownReactionKeys: {'🎉'},
        messages: {
          route: [
            MessageRecord(
              id: 'target',
              route: route,
              body: 'React here',
              timestamp: DateTime(2026, 11, 5),
              isOutgoing: false,
            ),
          ],
        },
      );
      await _pumpApp(tester, controller);
      await tester.tap(find.byKey(const Key('conversation-first-alice')));
      await tester.pumpAndSettle();
      expect(find.byType(ActionChip), findsNothing);
      await tester.tap(find.text('👍 2'));
      expect(controller.reactionCalls.single.messageId, 'target');
      expect(controller.reactionCalls.single.emoji, '👍');
      await tester.tap(
        find.text('React here').last,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('React'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final existingReaction = find.widgetWithText(PopupMenuItem<String>, '🎉');
      expect(
        (tester.widget<PopupMenuItem<String>>(existingReaction).child
                as Semantics)
            .properties
            .selected,
        isTrue,
      );
      await tester.tap(existingReaction);
      await tester.pumpAndSettle();
      expect(controller.reactionCalls.last, (
        route: route,
        messageId: 'target',
        emoji: '🎉',
      ));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets(
    'desktop reaction picker searches beyond quick emoji and cancels without reacting',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.runAsync(
        () => rootBundle.loadString('assets/reaction_emoji.json'),
      );
      const route = ConversationRoute('first', 'alice');
      final controller = _FakeController(
        canReact: true,
        messages: {
          route: [
            MessageRecord(
              id: 'target',
              route: route,
              body: 'Choose an emoji',
              timestamp: DateTime(2026, 11, 5),
              isOutgoing: false,
            ),
          ],
        },
      );
      await _pumpApp(tester, controller);
      await tester.tap(find.byKey(const Key('conversation-first-alice')));
      await tester.pumpAndSettle();

      Future<void> openPicker() async {
        await tester.tap(
          find.text('Choose an emoji').last,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('React'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('More…'));
        await tester.pumpAndSettle();
      }

      await openPicker();
      final more = tester.getSemantics(find.byTooltip('More emoji'));
      expect(more.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      more.owner!.performAction(more.id, SemanticsAction.tap);
      await tester.pump();
      await tester.runAsync(
        () => rootBundle.loadString('assets/reaction_emoji.json'),
      );
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('search-reactions'));
      expect(find.bySemanticsLabel(RegExp('Search emoji')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Fewer emoji')), findsWidgets);
      expect(tester.widget<TextField>(search).autofocus, isTrue);
      await tester.enterText(search, 'no such emoji name');
      await tester.pumpAndSettle();
      expect(find.text('No emoji found'), findsOneWidget);
      await tester.enterText(search, '  ROCKET  ');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Fewer emoji'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More emoji'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, '  ROCKET  ');
      final rocket = tester.getSemantics(find.byTooltip('React with 🚀'));
      expect(rocket.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      rocket.owner!.performAction(rocket.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(controller.reactionCalls.single, (
        route: route,
        messageId: 'target',
        emoji: '🚀',
      ));
      expect(find.byKey(const Key('search-reactions')), findsNothing);
      final mouse = TestGesture(
        dispatcher: tester.sendEventToBinding,
        kind: PointerDeviceKind.mouse,
        device: 2,
      );
      await mouse.addPointer(location: const Offset(0, 0));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Choose an emoji').last));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('React'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(controller.reactionCalls, hasLength(1));
      expect(find.byTooltip('More emoji'), findsNothing);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'phone reaction search fits above the keyboard and submits the first match',
    (tester) async {
      const route = ConversationRoute('first', 'alice');
      final controller = _FakeController(
        canReact: true,
        messages: {
          route: [
            MessageRecord(
              id: 'target',
              route: route,
              body: 'Phone reaction',
              timestamp: DateTime(2026, 11, 5),
              isOutgoing: false,
            ),
          ],
        },
      );
      await _pumpApp(tester, controller, size: const Size(390, 844));
      await tester.tap(find.byKey(const Key('conversation-first-alice')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Message actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('React'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More emoji'));
      await tester.pump();
      await tester.runAsync(
        () => rootBundle.loadString('assets/reaction_emoji.json'),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('search-reactions'));
      await tester.enterText(search, 'face tears joy');
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(search).dy, lessThan(524));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(controller.reactionCalls.single, (
        route: route,
        messageId: 'target',
        emoji: '😂',
      ));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('desktop appearance offers a new custom palette', (tester) async {
    final controller = _FakeController();
    await _pumpApp(tester, controller);
    await tester.tap(find.byKey(const Key('desktop-rail-settings')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reset to Classic'));
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Reset to Classic'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Surprise Me'));
    await tester.pumpAndSettle();
    expect(controller.preferenceChanges.single.key, 'customColors');
    expect(controller.preferenceChanges.single.value, isA<List<int>>());
    final colors = controller.preferenceChanges.single.value as List<int>;
    expect(colors, hasLength(3));
    expect(colors.toSet(), hasLength(3));
    expect(colors.every((color) => color >= 0 && color <= 0xffffff), isTrue);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets('desktop retention picker names its setting and saves a choice', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final controller = _FakeController();
    await _pumpApp(tester, controller);
    await tester.tap(find.byKey(const Key('desktop-rail-settings')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('1 week'),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('desktop-preferences')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.text('1 week'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Keep messages for')),
      matchesSemantics(
        label: 'Keep messages for',
        value: '1 week',
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        hasExpandedState: true,
      ),
    );
    await tester.tap(find.text('1 week'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 month'));
    await tester.pumpAndSettle();
    expect(controller.preferenceChanges.single.key, 'messageRetentionDays');
    expect(controller.preferenceChanges.single.value, 30);
    handle.dispose();
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets(
    'desktop denied notifications show the system warning and preserve disabled choices',
    (tester) async {
      final controller = _FakeController()
        ..notificationStatus = const SystemNotificationStatus(
          authorization: NotificationAuthorization.denied,
          canOpenSettings: true,
        );
      await _pumpApp(tester, controller, size: const Size(900, 600));
      await tester.tap(find.byKey(const Key('desktop-rail-settings')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'macOS is blocking Inbox+ notifications. Enable them in System Settings.',
        ),
        findsOneWidget,
      );
      expect(find.text('Open Notifications Settings…'), findsOneWidget);
      final toggles = tester
          .widgetList<CupertinoSwitch>(find.byType(CupertinoSwitch))
          .take(3)
          .toList();
      expect(toggles, hasLength(3));
      expect(
        toggles.every((toggle) => toggle.value && toggle.onChanged == null),
        isTrue,
      );
      await tester.tap(find.text('Open Notifications Settings…'));
      await tester.pumpAndSettle();
      expect(controller.notificationSettingsRequests, 1);
      expect(controller.preferenceChanges, isEmpty);
      expect(controller.notificationRefreshes, 1);
      controller.onNotificationRefresh = () {
        controller.notificationStatus = const SystemNotificationStatus(
          authorization: NotificationAuthorization.allowed,
          soundEnabled: true,
        );
      };
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('blocking Inbox+ notifications'),
        findsNothing,
      );
      expect(
        tester
            .widgetList<CupertinoSwitch>(find.byType(CupertinoSwitch))
            .take(3)
            .every((toggle) => toggle.value && toggle.onChanged != null),
        isTrue,
      );
      expect(controller.preferenceChanges, isEmpty);
    },
    variant: TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets(
    'desktop notification permission prompt preserves the saved off preference',
    (tester) async {
      final controller = _FakeController()
        ..currentPreferences = const PreferencesRecord(
          notificationsEnabled: false,
        )
        ..notificationStatus = const SystemNotificationStatus(
          authorization: NotificationAuthorization.notDetermined,
        );
      controller.onNotificationPermission = () {
        controller.notificationStatus = const SystemNotificationStatus(
          authorization: NotificationAuthorization.allowed,
          soundEnabled: true,
        );
      };
      await _pumpApp(tester, controller, size: const Size(900, 600));
      await tester.tap(find.byKey(const Key('desktop-rail-settings')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<CupertinoSwitch>(find.byType(CupertinoSwitch))
            .take(3)
            .every((toggle) => toggle.onChanged == null),
        isTrue,
      );
      await tester.tap(find.text('Allow Notifications…'));
      await tester.pumpAndSettle();
      expect(controller.notificationPermissionRequests, 1);
      expect(controller.preferences.notificationsEnabled, isFalse);
      expect(controller.preferenceChanges, isEmpty);
      final toggles = tester
          .widgetList<CupertinoSwitch>(find.byType(CupertinoSwitch))
          .take(3)
          .toList();
      expect(toggles.first.value, isFalse);
      expect(toggles.first.onChanged, isNotNull);
      expect(
        toggles.skip(1).every((toggle) => toggle.onChanged == null),
        isTrue,
      );
    },
    variant: TargetPlatformVariant({TargetPlatform.macOS}),
  );

  for (final status in [
    const SystemNotificationStatus(
      authorization: NotificationAuthorization.allowed,
      soundEnabled: false,
      alertsEnabled: false,
      canOpenSettings: true,
    ),
    const SystemNotificationStatus(
      authorization: NotificationAuthorization.allowed,
      soundEnabled: false,
      canOpenSettings: true,
    ),
    const SystemNotificationStatus(
      authorization: NotificationAuthorization.allowed,
      soundEnabled: true,
      alertsEnabled: false,
      canOpenSettings: true,
    ),
    const SystemNotificationStatus(),
  ]) {
    testWidgets(
      'desktop notification settings distinguish ${status.authorization} sound=${status.soundEnabled} alerts=${status.alertsEnabled}',
      (tester) async {
        final controller = _FakeController()..notificationStatus = status;
        await _pumpApp(tester, controller, size: const Size(900, 600));
        await tester.tap(find.byKey(const Key('desktop-rail-settings')));
        await tester.pumpAndSettle();
        final toggles = tester
            .widgetList<CupertinoSwitch>(find.byType(CupertinoSwitch))
            .take(3)
            .toList();
        expect(toggles.first.onChanged, isNotNull);
        expect(toggles[1].onChanged, isNotNull);
        expect(toggles.last.onChanged == null, status.soundEnabled == false);
        if (status.soundEnabled == false) {
          expect(
            find.textContaining('Notification sounds are turned off'),
            findsOneWidget,
          );
        }
        if (status.alertsEnabled == false) {
          expect(
            find.textContaining('Notification banners are turned off'),
            findsOneWidget,
          );
        }
        if (status.authorization == NotificationAuthorization.unavailable) {
          expect(
            find.textContaining('could not be checked on this desktop'),
            findsOneWidget,
          );
          expect(find.text('Open Notifications Settings…'), findsNothing);
        }
        expect(controller.preferenceChanges, isEmpty);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }),
    );
  }

  testWidgets(
    'desktop notification badge guidance keeps the menu bar preference editable',
    (tester) async {
      final controller = _FakeController()
        ..notificationStatus = const SystemNotificationStatus(
          authorization: NotificationAuthorization.allowed,
          badgesEnabled: false,
        );
      await _pumpApp(tester, controller, size: const Size(900, 600));
      await tester.tap(find.byKey(const Key('desktop-rail-settings')));
      await tester.pumpAndSettle();
      final note = find.text(
        'Dock badges may also be blocked by macOS. The menu bar count still works.',
      );
      await tester.scrollUntilVisible(
        note,
        250,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('desktop-preferences')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(note, findsOneWidget);
      final toggle = tester.widget<CupertinoSwitch>(
        find.descendant(
          of: find.bySemanticsLabel(
            'Show the unread count in the Dock and menu bar',
          ),
          matching: find.byType(CupertinoSwitch),
        ),
      );
      expect(toggle.value, isTrue);
      expect(toggle.onChanged, isNotNull);
      expect(controller.preferenceChanges, isEmpty);
    },
    variant: TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets(
    'desktop notification activation leaves Settings for the exact chat and keeps drafts and search',
    (tester) async {
      const first = ConversationRoute('first', 'alice');
      const second = ConversationRoute('second', 'bob');
      final controller = _FakeController();
      controller.updateDraft(first, 'Keep the first draft');
      controller.updateDraft(second, 'Keep the second draft');
      await _pumpApp(tester, controller, size: const Size(900, 600));
      await tester.tap(find.byKey(const Key('conversation-first-alice')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('inbox-search')),
        'retained search',
      );
      await tester.tap(find.byKey(const Key('desktop-rail-settings')));
      await tester.pumpAndSettle();
      controller.notificationActivation++;
      controller.selectConversation(second);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('message-composer')), findsOneWidget);
      expect(_composerText(tester), 'Keep the second draft');
      expect(controller.draftFor(first)?.body, 'Keep the first draft');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('inbox-search')))
            .controller!
            .text,
        'retained search',
      );
      await tester.tap(find.byKey(const Key('desktop-rail-settings')));
      await tester.pumpAndSettle();
      controller.notificationActivation++;
      controller.selectConversation(second);
      await tester.pumpAndSettle();
      expect(_composerText(tester), 'Keep the second draft');
      expect(controller.sentDrafts, isEmpty);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'desktop notification activation replaces a person summary with its exact conversation',
    (tester) async {
      const route = ConversationRoute('first', 'alice');
      final controller = _FakeController(
        contacts: [
          ContactRecord(
            id: 'person',
            displayName: 'Linked person',
            identities: const [IdentityLink('first', 'alice')],
          ),
        ],
      );
      await _pumpApp(tester, controller, size: const Size(900, 600));
      await tester.tap(find.byKey(const Key('desktop-rail-contacts')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Linked person').first);
      await tester.pumpAndSettle();
      expect(find.text('Rename person…'), findsOneWidget);
      controller.notificationActivation++;
      controller.selectConversation(route);
      await tester.pumpAndSettle();
      expect(find.text('Rename person…'), findsNothing);
      expect(find.byKey(const Key('message-composer')), findsOneWidget);
      expect(controller.selectedRoute, route);
      expect(controller.sentDrafts, isEmpty);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'desktop search opens a matched message and keeps the query across sections',
    (tester) async {
      const route = ConversationRoute('first', 'alice');
      final controller = _FakeController(
        messages: {
          route: [
            MessageRecord(
              id: 'ticket',
              route: route,
              body: 'Meet at the station',
              timestamp: DateTime(2026, 11, 4, 12),
              isOutgoing: false,
            ),
          ],
        },
      );
      await _pumpApp(tester, controller, size: const Size(1100, 700));
      await tester.enterText(find.byKey(const Key('inbox-search')), 'station');
      await tester.pumpAndSettle();
      expect(find.text('Messages'), findsOneWidget);
      expect(find.byKey(const Key('conversation-first-alice')), findsNothing);
      await tester.tap(
        find.byKey(const Key('search-result-first-alice-ticket')),
      );
      await tester.pumpAndSettle();
      expect(controller.selectedRoute, route);
      expect(find.byKey(const Key('message-composer')), findsOneWidget);
      expect(find.byTooltip('Message actions'), findsNothing);
      await tester.tap(find.byKey(const Key('desktop-rail-contacts')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('desktop-rail-inbox')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('inbox-search')))
            .controller!
            .text,
        'station',
      );
      expect(controller.selectedRoute, route);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets('desktop network filters list only networks with chats', (
    tester,
  ) async {
    final controller = _FakeController(
      accounts: const [
        AccountRecord(id: 'first', platform: 'whatsapp', displayName: 'WA'),
        AccountRecord(id: 'second', platform: 'telegram', displayName: 'TG'),
        AccountRecord(id: 'apple', platform: 'imessage', displayName: 'iM'),
      ],
    );
    await _pumpApp(tester, controller, size: const Size(1100, 700));
    expect(find.widgetWithText(TextButton, 'WhatsApp'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Telegram'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'iMessage'), findsNothing);
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets('desktop network filters narrow linked person conversations', (
    tester,
  ) async {
    final controller = _FakeController(
      conversations: [
        ConversationRecord(
          route: const ConversationRoute('first', 'alice'),
          title: 'Alice on WhatsApp',
          identityId: 'alice-wa',
          latestActivity: DateTime(2026, 11, 4, 12),
        ),
        ConversationRecord(
          route: const ConversationRoute('second', 'alice'),
          title: 'Alice on Telegram',
          identityId: 'alice-tg',
          latestActivity: DateTime(2026, 11, 4, 11),
        ),
      ],
      contacts: [
        ContactRecord(
          id: 'alice',
          displayName: 'Alice',
          identities: const [
            IdentityLink('first', 'alice-wa'),
            IdentityLink('second', 'alice-tg'),
          ],
        ),
      ],
    );
    await _pumpApp(tester, controller, size: const Size(1100, 700));
    expect(find.text('+1'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Telegram').first);
    await tester.pumpAndSettle();
    expect(find.text('+1'), findsNothing);
    expect(find.byKey(const Key('conversation-first-alice')), findsNothing);
    await tester.tap(find.byKey(const Key('conversation-second-alice')));
    await tester.pumpAndSettle();
    expect(find.text('2 conversations across your networks'), findsOneWidget);
    await tester.tap(find.text('Alice on Telegram'));
    await tester.pumpAndSettle();
    expect(
      controller.selectedRoute,
      const ConversationRoute('second', 'alice'),
    );
    expect(find.byKey(const Key('message-composer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets(
    'desktop rename keeps the name on failure and saves without losing identities',
    (tester) async {
      final controller = _FakeController(
        contacts: [
          ContactRecord(
            id: 'alice',
            displayName: 'Alice',
            identities: const [IdentityLink('first', 'alice-network')],
          ),
        ],
      );
      await _pumpApp(tester, controller);
      await tester.tap(find.byKey(const Key('desktop-rail-contacts')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename person…'));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('desktop-person-name'));
      await tester.enterText(field, 'Alice renamed');
      controller.contactSaveError = 'The contact could not be saved.';
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'Alice renamed');
      expect(controller.savedContacts, isEmpty);
      controller.contactSaveError = null;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      expect(controller.savedContacts.single.displayName, 'Alice renamed');
      expect(
        controller.savedContacts.single.identities.single.identityId,
        'alice-network',
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets('WhatsApp phone pairing shows a selectable linking code', (
    tester,
  ) async {
    final controller = _FakeController(accounts: [], conversations: []);
    controller.login = const LoginState(
      networkId: 'whatsapp',
      step: LoginStep.qr,
      title: 'Connect WhatsApp',
      qrData: 'fixture-qr-data',
    );
    await _pumpApp(tester, controller, size: const Size(390, 844));
    await tester.tap(find.text('Connect an account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.byKey(const Key('whatsapp-pairing-phone')));
    await tester.enterText(
      find.byKey(const Key('whatsapp-pairing-phone')),
      '+65 8123 4567',
    );
    await tester.ensureVisible(find.byKey(const Key('whatsapp-pair-phone')));
    await tester.tap(find.byKey(const Key('whatsapp-pair-phone')));
    await tester.pump();

    expect(controller.submittedLoginFields, [
      {'phone': '+65 8123 4567'},
    ]);
    controller.login = const LoginState(
      networkId: 'whatsapp',
      step: LoginStep.pairingCode,
      title: 'Link WhatsApp',
      pairingCode: 'ABCD-EFGH',
      instructions: 'Enter this code in WhatsApp on your phone.',
    );
    controller.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Linking code ABCD-EFGH'), findsOneWidget);
    expect(find.text('ABCD-EFGH'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.byKey(const Key('whatsapp-pairing-phone')), findsNothing);
    expect(
      find.text('Enter this code in WhatsApp on your phone.'),
      findsOneWidget,
    );
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.ensureVisible(find.text('Copy linking code'));
    await tester.tap(find.text('Copy linking code'));
    await tester.pump();
    expect(copied, 'ABCD-EFGH');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'iPhone WhatsApp phone form supports correction and a QR alternative',
    (tester) async {
      final controller = _FakeController(accounts: [], conversations: []);
      controller.login = const LoginState(
        networkId: 'whatsapp',
        step: LoginStep.fields,
        title: 'Link WhatsApp with a code',
        fields: [
          LoginField(
            id: 'country_code',
            label: 'Country calling code',
            phone: true,
          ),
          LoginField(id: 'phone', label: 'Phone number', phone: true),
        ],
      );
      await _pumpApp(tester, controller, size: const Size(390, 844));
      await tester.tap(find.text('Connect an account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const ValueKey('whatsapp-country_code')),
        '65',
      );
      await tester.enterText(
        find.byKey(const ValueKey('whatsapp-phone')),
        '8123 4567',
      );
      await tester.tap(find.text('Get linking code'));
      await tester.pump();
      expect(controller.submittedLoginFields.single, {
        'country_code': '65',
        'phone': '8123 4567',
      });
      controller.login = const LoginState(
        networkId: 'whatsapp',
        step: LoginStep.fields,
        title: 'Link WhatsApp with a code',
        error: 'Check your number',
        fields: [
          LoginField(
            id: 'country_code',
            label: 'Country calling code',
            phone: true,
          ),
          LoginField(id: 'phone', label: 'Phone number', phone: true),
        ],
      );
      controller.notifyListeners();
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('whatsapp-phone')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        '8123 4567',
      );
      await tester.ensureVisible(find.text('Use a QR code on another screen'));
      await tester.tap(find.text('Use a QR code on another screen'));
      await tester.pump();
      expect(controller.qrLoginChoices.single, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(controller.resumeLoginCalls, 1);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'iPhone WeChat QR can be saved and shared without losing the attempt',
    (tester) async {
      final controller = _FakeController(accounts: [], conversations: []);
      controller.login = const LoginState(
        networkId: 'wechat',
        step: LoginStep.qr,
        qrImage: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=',
      );
      await _pumpApp(tester, controller, size: const Size(390, 844));
      await tester.tap(find.text('Connect an account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.text('Save QR to Photos'));
      await tester.tap(find.text('Save QR to Photos'));
      await tester.pump();
      await tester.ensureVisible(find.text('Share QR code'));
      await tester.tap(find.text('Share QR code'));
      await tester.pump();
      expect(controller.exportedQrs.map((qr) => qr.share), [false, true]);
      expect(controller.exportedQrs.first.image.take(8), [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]);
      expect(controller.cancelLoginCalls, 0);
      expect(controller.login?.step, LoginStep.qr);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  test('QR export includes an opaque four-module quiet zone', () async {
    final bytes = await loginQrImageBytes(
      const LoginState(
        networkId: 'whatsapp',
        step: LoginStep.qr,
        qrData: 'fixture-qr-data',
      ),
    );
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final pixels = (await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final width = frame.image.width;
    expect(width, 232);
    for (var y = 0; y < width; y++) {
      for (var x = 0; x < width; x++) {
        if (x < 32 || y < 32 || x >= width - 32 || y >= width - 32) {
          expect(pixels.sublist((y * width + x) * 4, (y * width + x) * 4 + 4), [
            255,
            255,
            255,
            255,
          ]);
        }
      }
    }
    expect(pixels[(32 * width + 32) * 4], 0);
    frame.image.dispose();
  });

  testWidgets(
    'Discord optional email fields allow token-only sign-in',
    (tester) async {
      final controller = _FakeController(accounts: [], conversations: []);
      controller.login = const LoginState(
        networkId: 'discord',
        step: LoginStep.fields,
        title: 'Connect Discord',
        fields: [
          LoginField(id: 'username', label: 'Email', optional: true),
          LoginField(
            id: 'password',
            label: 'Password',
            secret: true,
            optional: true,
          ),
          LoginField(
            id: 'token',
            label: 'Session token (optional)',
            secret: true,
            optional: true,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConnectAccountsDialog(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      final token = find.byKey(const ValueKey('discord-token'));
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: token, matching: find.byType(TextField)),
            )
            .obscureText,
        isTrue,
      );
      await tester.enterText(token, 'fixture-token');
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(controller.submittedLoginFields.single, {
        'username': '',
        'password': '',
        'token': 'fixture-token',
      });
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'WeChat displays the server QR image without WhatsApp pairing controls',
    (tester) async {
      final controller = _FakeController(accounts: [], conversations: []);
      controller.login = const LoginState(
        networkId: 'wechat',
        step: LoginStep.qr,
        title: 'Connect WeChat',
        qrImage: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=',
        instructions:
            'Scan this code using WeChat on your phone, then confirm sign-in.',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConnectAccountsDialog(controller: controller)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is MemoryImage,
        ),
        findsOneWidget,
      );
      expect(find.byType(QrImageView), findsNothing);
      expect(find.byKey(const Key('whatsapp-pairing-phone')), findsNothing);
      expect(find.text('Connect WeChat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}

MessageRecord _failedMessage(ConversationRoute route) => MessageRecord(
  id: 'uncertain',
  route: route,
  body: 'A message to check',
  timestamp: DateTime(2026, 11, 4),
  isOutgoing: true,
  deliveryState: DeliveryState.failed,
);

Future<void> _pumpApp(
  WidgetTester tester,
  _FakeController controller, {
  Size size = const Size(1200, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(InboxPlusApp(controller: controller));
  await tester.pumpAndSettle();
}

Future<void> _openMenuWithAlt(
  WidgetTester tester,
  LogicalKeyboardKey key,
  String character,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(key, character: character);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.pumpAndSettle();
}

Future<void> _chooseEditMenuItem(WidgetTester tester, String label) async {
  await tester.tap(find.text('Edit'), kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(MenuItemButton, label),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

String _composerText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('message-composer')))
    .controller!
    .text;

ConversationRecord _conversation(String accountId, String id, String title) =>
    ConversationRecord(
      route: ConversationRoute(accountId, id),
      title: title,
      latestActivity: DateTime(2026, 11, 4, 12),
    );

class _FakeController extends InboxUiController {
  _FakeController({
    List<AccountRecord>? accounts,
    List<ConversationRecord>? conversations,
    this.messages = const {},
    List<ContactRecord> contacts = const [],
    this.sendingUnavailableReasons = const {},
    this.unconfirmedMessages = const {},
    this.canReply = false,
    this.canReact = false,
    this.iMessageAvailable = false,
    this.onRecipientContacts,
    this.onStartConversation,
    this.reactionCounts = const {},
    this.ownReactionKeys = const {},
    this.additionalNetworks = const [],
  }) : contacts = List.of(contacts),
       accounts =
           accounts ??
           const [
             AccountRecord(
               id: 'first',
               platform: 'whatsapp',
               displayName: 'WhatsApp',
               isConnected: true,
             ),
             AccountRecord(
               id: 'second',
               platform: 'telegram',
               displayName: 'Telegram',
               isConnected: true,
             ),
           ],
       conversations =
           conversations ??
           [
             _conversation('first', 'alice', 'Alice'),
             _conversation('second', 'bob', 'Bob'),
           ];

  final _drafts = <ConversationRoute, DraftRecord>{};
  final bool canReply;
  final bool canReact;
  final bool iMessageAvailable;
  final List<NetworkCapability> additionalNetworks;
  final Future<LocalRecipientSnapshot> Function(String)? onRecipientContacts;
  final Future<void> Function(String, String)? onStartConversation;
  final recipientRequests = <String>[];
  final Map<String, int> reactionCounts;
  final Set<String> ownReactionKeys;
  final reactionCalls =
      <({ConversationRoute route, String messageId, String emoji})>[];
  final beginLoginCalls = <String>[];
  final qrLoginChoices = <bool?>[];
  final exportedQrs = <({Uint8List image, bool share})>[];
  int resumeLoginCalls = 0;
  final sentDrafts = <MapEntry<ConversationRoute, String>>[];
  final List<MapEntry<String, String>> startedConversations = [];
  final Map<ConversationRoute, List<MessageRecord>> messages;
  final _conversationPreferences =
      <ConversationRoute, ConversationPreferencesRecord>{};
  final savedContacts = <ContactRecord>[];
  final linkedIdentities = <({IdentityLink identity, ContactRecord person})>[];
  final preferenceChanges = <MapEntry<String, Object>>[];
  final Map<ConversationRoute, String> sendingUnavailableReasons;
  final reconnectedAccounts = <String>[];
  final Map<ConversationRoute, Set<String>> unconfirmedMessages;
  final resolvedDeliveries =
      <({ConversationRoute route, String messageId, bool wasSent})>[];
  final retriedMessages = <({ConversationRoute route, String messageId})>[];
  final openedAttachmentLinks =
      <({ConversationRoute route, String messageId, String attachmentId})>[];
  final downloadedAttachments =
      <({ConversationRoute route, String messageId, String attachmentId})>[];
  final openedAttachments = <String>[];
  final imageLoadStates = <String, AttachmentLoadState>{};
  final loadedImages =
      <({ConversationRoute route, String messageId, String attachmentId})>[];
  final savedAttachments =
      <({ConversationRoute route, String messageId, String attachmentId})>[];
  String? contactSaveError;
  final submittedLoginFields = <Map<String, String>>[];
  var cancelLoginCalls = 0;

  @override
  final List<AccountRecord> accounts;

  @override
  final List<ConversationRecord> conversations;

  @override
  bool get isLoading => false;

  @override
  bool get isBusy => false;

  @override
  bool get isOffline => false;

  @override
  String? error;

  @override
  final List<ContactRecord> contacts;

  @override
  List<NetworkCapability> get networks => [
    ...additionalNetworks,
    NetworkCapability(
      id: 'whatsapp',
      name: 'WhatsApp',
      available: true,
      canAttach: true,
      canReply: canReply,
      canReact: canReact,
      canStartConversation: true,
    ),
    NetworkCapability(
      id: 'telegram',
      name: 'Telegram',
      available: true,
      canStartConversation: true,
    ),
    if (defaultTargetPlatform == TargetPlatform.macOS)
      NetworkCapability(
        id: 'imessage',
        name: 'iMessage',
        available: iMessageAvailable,
        canStartConversation: iMessageAvailable,
        reason: 'Available only on macOS',
      ),
  ];

  @override
  ConversationRoute? selectedRoute;

  @override
  int notificationActivation = 0;

  @override
  LoginState? login;

  @override
  StorageSummary get storageSummary => const StorageSummary();

  @override
  PreferencesRecord get preferences => currentPreferences;
  PreferencesRecord currentPreferences = const PreferencesRecord();
  @override
  String get launchAtLoginStatus => 'off';
  bool updatesEnabled = false;
  int updateChecks = 0;
  @override
  bool get supportsUpdates => updatesEnabled;
  @override
  Future<void> checkForUpdates() async {
    updateChecks++;
  }

  @override
  SystemNotificationStatus notificationStatus = const SystemNotificationStatus(
    authorization: NotificationAuthorization.allowed,
    soundEnabled: true,
  );
  int notificationRefreshes = 0;
  int notificationSettingsRequests = 0;
  int notificationPermissionRequests = 0;
  VoidCallback? onNotificationRefresh;
  VoidCallback? onNotificationPermission;

  @override
  Future<void> disconnectAccount(String accountId) async {}

  @override
  List<MessageRecord> messagesFor(ConversationRoute route) =>
      messages[route] ?? const [];

  @override
  DraftRecord? draftFor(ConversationRoute route) => _drafts[route];

  @override
  ConversationPreferencesRecord preferencesFor(ConversationRoute route) =>
      _conversationPreferences[route] ??
      ConversationPreferencesRecord(route: route);

  @override
  Map<String, int> reactionsFor(ConversationRoute route, String messageId) =>
      reactionCounts;

  @override
  Set<String> ownReactionsFor(ConversationRoute route, String messageId) =>
      ownReactionKeys;

  @override
  String? sendingUnavailableReason(ConversationRoute route) =>
      sendingUnavailableReasons[route];

  @override
  void selectConversation(ConversationRoute? route) {
    selectedRoute = route;
    notifyListeners();
  }

  @override
  void updateDraft(ConversationRoute route, String text) {
    _drafts[route] = DraftRecord(
      route: route,
      body: text,
      revision: (_drafts[route]?.revision ?? 0) + 1,
      replyToMessageId: _drafts[route]?.replyToMessageId,
      attachments: _drafts[route]?.attachments ?? [],
    );
    notifyListeners();
  }

  @override
  Future<void> sendDraft(ConversationRoute route) async {
    sentDrafts.add(MapEntry(route, _drafts[route]?.body ?? ''));
    _drafts.remove(route);
    notifyListeners();
  }

  @override
  Future<void> beginLogin(String networkId, {bool? useQr}) async {
    beginLoginCalls.add(networkId);
    qrLoginChoices.add(useQr);
  }

  @override
  Future<void> reconnectAccount(String accountId) async {
    reconnectedAccounts.add(accountId);
  }

  @override
  Future<void> cancelLogin() async {
    cancelLoginCalls++;
  }

  @override
  Future<void> resumeLogin() async {
    resumeLoginCalls++;
  }

  @override
  Future<void> exportLoginQr(Uint8List image, {bool share = false}) async {
    exportedQrs.add((image: image, share: share));
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> stageAttachments(ConversationRoute route) async {}

  @override
  void removeDraftAttachment(ConversationRoute route, String attachmentId) {}

  @override
  void setReplyTo(ConversationRoute route, String? messageId) {
    _drafts[route] = DraftRecord(
      route: route,
      body: _drafts[route]?.body ?? '',
      revision: (_drafts[route]?.revision ?? 0) + 1,
      replyToMessageId: messageId,
      attachments: _drafts[route]?.attachments ?? [],
    );
    notifyListeners();
  }

  @override
  Future<void> retryMessage(ConversationRoute route, String messageId) async {
    retriedMessages.add((route: route, messageId: messageId));
  }

  @override
  bool isDeliveryUnconfirmed(ConversationRoute route, String messageId) =>
      unconfirmedMessages[route]?.contains(messageId) ?? false;

  @override
  Future<void> resolveUnconfirmedSend(
    ConversationRoute route,
    String messageId, {
    required bool wasSent,
  }) async {
    resolvedDeliveries.add((
      route: route,
      messageId: messageId,
      wasSent: wasSent,
    ));
  }

  @override
  Future<void> react(
    ConversationRoute route,
    String messageId,
    String emoji,
  ) async {
    reactionCalls.add((route: route, messageId: messageId, emoji: emoji));
  }

  @override
  Future<void> downloadAttachment(
    ConversationRoute route,
    String messageId,
    String attachmentId,
  ) async {
    downloadedAttachments.add((
      route: route,
      messageId: messageId,
      attachmentId: attachmentId,
    ));
  }

  @override
  AttachmentLoadState? attachmentLoadState(
    ConversationRoute route,
    String attachmentId,
  ) => imageLoadStates[attachmentId];

  @override
  Future<void> loadInlineImage(
    ConversationRoute route,
    String messageId,
    String attachmentId,
  ) async {
    loadedImages.add((
      route: route,
      messageId: messageId,
      attachmentId: attachmentId,
    ));
  }

  @override
  Future<void> openAttachmentLink(
    ConversationRoute route,
    String messageId,
    String attachmentId,
  ) async {
    openedAttachmentLinks.add((
      route: route,
      messageId: messageId,
      attachmentId: attachmentId,
    ));
  }

  @override
  Future<void> openAttachment(String localPath) async {
    openedAttachments.add(localPath);
  }

  @override
  Future<void> saveAttachment(
    ConversationRoute route,
    String messageId,
    String attachmentId,
  ) async {
    savedAttachments.add((
      route: route,
      messageId: messageId,
      attachmentId: attachmentId,
    ));
  }

  @override
  Future<void> startConversation(String accountId, String recipient) async {
    startedConversations.add(MapEntry(accountId, recipient));
    await onStartConversation?.call(accountId, recipient);
  }

  @override
  Future<LocalRecipientSnapshot> recipientContacts(String accountId) async {
    recipientRequests.add(accountId);
    return await onRecipientContacts?.call(accountId) ??
        const LocalRecipientSnapshot.available();
  }

  @override
  Future<void> setFavorite(ConversationRoute route, bool favorite) async {}

  @override
  Future<void> setMuted(
    ConversationRoute route,
    bool muted, {
    DateTime? until,
  }) async {
    final old = preferencesFor(route);
    _conversationPreferences[route] = ConversationPreferencesRecord(
      route: route,
      isMuted: muted,
      mutedUntil: until,
      hiddenAt: old.hiddenAt,
    );
    notifyListeners();
  }

  @override
  Future<void> setHidden(ConversationRoute route, bool hidden) async {
    final old = preferencesFor(route);
    _conversationPreferences[route] = ConversationPreferencesRecord(
      route: route,
      isMuted: old.isMuted,
      hiddenAt: hidden ? DateTime.now() : null,
    );
    notifyListeners();
  }

  @override
  Future<void> saveContact(ContactRecord contact) async {
    error = contactSaveError;
    if (error == null) savedContacts.add(contact);
    notifyListeners();
  }

  @override
  Future<String?> acceptContactSuggestion(ContactSuggestion suggestion) async {
    error = contactSaveError;
    if (error != null) {
      notifyListeners();
      return null;
    }
    const id = 'accepted-person';
    contacts.add(
      ContactRecord(
        id: id,
        displayName: suggestion.displayName,
        identities: suggestion.identities,
      ),
    );
    notifyListeners();
    return id;
  }

  @override
  Future<void> linkIdentity(IdentityLink identity, ContactRecord person) async {
    linkedIdentities.add((identity: identity, person: person));
  }

  @override
  Future<void> setUnread(ConversationRoute route, bool unread) async {}

  @override
  Future<void> removeContact(String id) async {}

  @override
  Future<void> submitLogin(Map<String, String> fields) async {
    submittedLoginFields.add(Map.of(fields));
  }

  @override
  Future<void> removeAccount(String accountId) async =>
      removedAccounts.add(accountId);
  final removedAccounts = <String>[];
  final networkProblems = <String, AccountNetworkProblem>{};
  final changingAccounts = <String>{};
  @override
  AccountNetworkProblem? networkProblem(String accountId) =>
      networkProblems[accountId];
  @override
  bool isChangingAccount(String accountId) =>
      changingAccounts.contains(accountId);
  @override
  Future<void> openLoginItemsSettings() async {}

  @override
  Future<void> refreshNotificationStatus() async {
    notificationRefreshes++;
    onNotificationRefresh?.call();
    notifyListeners();
  }

  @override
  Future<void> requestNotificationPermission() async {
    notificationPermissionRequests++;
    onNotificationPermission?.call();
    notifyListeners();
  }

  @override
  Future<void> openNotificationSettings() async {
    notificationSettingsRequests++;
  }

  @override
  Future<void> setPreference(String key, Object value) async {
    preferenceChanges.add(MapEntry(key, value));
  }

  @override
  Future<void> clearMediaCache() async {}
  @override
  Future<void> exportDiagnostics() async {}
  @override
  Future<void> requestQuit() async {}
}
