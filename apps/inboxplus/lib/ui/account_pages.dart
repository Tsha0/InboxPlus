import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inboxplus_storage/inboxplus_storage.dart'
    show ConversationRoute;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'confirmation.dart';
import 'feedback_dialog.dart'
    show
        FeedbackForm,
        chooseFeedbackImage,
        feedbackDiagnosticsNotice,
        feedbackImageError;
import 'inbox_ui_controller.dart';
import 'network_badge.dart';

part 'phone_settings.dart';

class ConnectAccountsDialog extends StatefulWidget {
  const ConnectAccountsDialog({super.key, required this.controller});

  final InboxUiController controller;

  @override
  State<ConnectAccountsDialog> createState() => _ConnectAccountsDialogState();
}

class _ConnectAccountsDialogState extends State<ConnectAccountsDialog>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _phoneFormKey = GlobalKey<FormState>();
  final _values = <String, TextEditingController>{};
  bool _exportingQr = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.resumeLogin());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final value in _values.values) {
      value.dispose();
    }
    unawaited(widget.controller.cancelLogin());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final login = widget.controller.login;
        final desktop = switch (defaultTargetPlatform) {
          TargetPlatform.macOS ||
          TargetPlatform.windows ||
          TargetPlatform.linux => true,
          _ => false,
        };
        if (desktop && login == null) return _desktopPicker(context);
        return Dialog(
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 540,
              maxHeight: MediaQuery.sizeOf(context).height * .88,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 12, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              login?.title ?? 'Add an account',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            if (login == null) ...[
                              const SizedBox(height: 4),
                              const Text(
                                'Your conversations, together in Inbox+.',
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close account setup',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: login == null
                        ? _networkPicker(context)
                        : _loginContent(context, login),
                  ),
                ),
                if (login != null) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (login.step != LoginStep.complete)
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        if (login.step == LoginStep.fields) ...[
                          FilledButton(
                            onPressed: login.busy ? null : _submit,
                            child: Text(
                              login.networkId == 'whatsapp'
                                  ? 'Get linking code'
                                  : 'Continue',
                            ),
                          ),
                        ],
                        if (login.step == LoginStep.complete)
                          FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Done'),
                          ),
                        if (login.step == LoginStep.failed)
                          ..._failedActions(login),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _failedActions(LoginState login) {
    final retry = login.busy
        ? null
        : () => widget.controller.beginLogin(login.networkId);
    final openSettings = widget.controller.openFullDiskAccessSettings;
    return switch (login.imessageProblem) {
      IMessageSetupProblem.fullDiskAccessNeeded ||
      IMessageSetupProblem.stillBlocked => [
        FilledButton.tonal(onPressed: retry, child: const Text('Try again')),
        FilledButton.icon(
          onPressed: openSettings,
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Open System Settings'),
        ),
      ],
      IMessageSetupProblem.finishInSettings => [
        FilledButton.tonal(
          onPressed: openSettings,
          child: const Text('Open System Settings'),
        ),
        FilledButton(onPressed: retry, child: const Text('Try again')),
      ],
      IMessageSetupProblem.messagesNotSetUp => [
        FilledButton.tonal(
          onPressed: widget.controller.openMessages,
          child: const Text('Open Messages'),
        ),
        FilledButton(onPressed: retry, child: const Text('Try again')),
      ],
      IMessageSetupProblem.unreadable ||
      null => [FilledButton(onPressed: retry, child: const Text('Try again'))],
    };
  }

  Widget _desktopPicker(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      key: const Key('account-picker'),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: 620,
        height: math.min(625, MediaQuery.sizeOf(context).height - 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add an account',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pick the network you want to bring into Inbox+.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _networkPicker(context, desktop: true),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 22,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      backgroundColor: theme.colorScheme.surfaceContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                          width: .5,
                        ),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _networkPicker(BuildContext context, {bool desktop = false}) {
    final controller = widget.controller;
    if (controller.networks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Text('No messaging clients are available on this device.'),
      );
    }
    final networks = controller.networks.toList()
      ..sort((a, b) {
        if (a.comingSoon != b.comingSoon) return a.comingSoon ? 1 : -1;
        if (a.available != b.available) return a.available ? -1 : 1;
        final aName = networkNames[a.id] ?? a.name;
        final bName = networkNames[b.id] ?? b.name;
        return aName.toLowerCase().compareTo(bName.toLowerCase());
      });
    return Column(
      children: [
        if (desktop)
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = math.max(
                1,
                ((constraints.maxWidth + 12) / 180).floor(),
              );
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final network in networks)
                    SizedBox(
                      width: width,
                      child: _desktopNetworkTile(context, network),
                    ),
                ],
              );
            },
          )
        else
          for (final network in networks) ...[
            Builder(
              builder: (context) {
                final connected = controller.accounts.any(
                  (account) => account.platform == network.id,
                );
                final enabled =
                    network.available && !connected && !controller.isBusy;
                final description = connected
                    ? 'Already connected'
                    : network.available
                    ? network.description
                    : network.reason ?? 'Unavailable on this device';
                return Card.outlined(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    leading: NetworkBadge(
                      network: network.id,
                      size: 42,
                      labelled: false,
                    ),
                    title: Text(network.name),
                    subtitle: description.isEmpty ? null : Text(description),
                    trailing: Icon(
                      connected
                          ? Icons.check_circle_outline
                          : network.available
                          ? Icons.chevron_right
                          : Icons.lock_outline,
                    ),
                    enabled: enabled,
                    onTap: enabled
                        ? () => controller.beginLogin(network.id)
                        : null,
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
        if (controller.error case final error?) ...[
          const SizedBox(height: 8),
          _Notice(message: error, isError: true),
        ],
      ],
    );
  }

  Widget _desktopNetworkTile(BuildContext context, NetworkCapability network) {
    final controller = widget.controller;
    final connected = controller.accounts.any(
      (account) => account.platform == network.id,
    );
    final enabled = network.available && !connected && !controller.isBusy;
    final description = connected
        ? 'Already connected'
        : network.available
        ? network.description
        : network.reason ?? 'Unavailable on this device';
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      key: ValueKey('picker-${network.id}'),
      label: networkNames[network.id] ?? network.name,
      value: description,
      selected: connected,
      button: true,
      enabled: enabled,
      excludeSemantics: true,
      onTap: enabled ? () => controller.beginLogin(network.id) : null,
      child: Tooltip(
        message: description,
        excludeFromSemantics: true,
        child: TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.all(12),
            alignment: Alignment.topLeft,
            backgroundColor: colors.onSurface.withValues(
              alpha: enabled ? .035 : .015,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: enabled ? () => controller.beginLogin(network.id) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  NetworkBadge(network: network.id, labelled: false),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      network.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: enabled || connected
                            ? colors.onSurface
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (connected) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.check_circle, size: 14, color: colors.onSurface),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: MediaQuery.textScalerOf(context).scale(11) * 1.3 * 3,
                child: Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loginContent(BuildContext context, LoginState login) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (login.instructions.isNotEmpty) ...[
          Text(login.instructions),
          const SizedBox(height: 24),
        ],
        switch (login.step) {
          LoginStep.preparing => Padding(
            padding: const EdgeInsets.all(36),
            child: Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  login.networkId == 'imessage'
                      ? 'Reading Messages on this Mac…'
                      : 'Preparing secure sign-in…',
                ),
              ],
            ),
          ),
          LoginStep.qr => _qrContent(login),
          LoginStep.pairingCode => Column(
            children: [
              const Text('Linking code'),
              const SizedBox(height: 16),
              SelectableText(
                login.pairingCode!,
                semanticsLabel: 'Linking code ${login.pairingCode!}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(letterSpacing: 3, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: login.pairingCode!),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Linking code copied. Switch to WhatsApp to enter it.',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy linking code'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Keep Inbox+ open in the app switcher until linking finishes. If the code expires, request a new one.',
              ),
            ],
          ),
          LoginStep.fields => Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                children: [
                  for (final field in login.fields) ...[
                    TextFormField(
                      key: ValueKey('${login.networkId}-${field.id}'),
                      controller: _values.putIfAbsent(
                        field.id,
                        TextEditingController.new,
                      ),
                      enabled: !login.busy,
                      obscureText: field.secret,
                      autocorrect: !field.secret && !field.phone,
                      enableSuggestions: !field.secret,
                      keyboardType: field.phone
                          ? TextInputType.phone
                          : TextInputType.text,
                      textInputAction: field == login.fields.last
                          ? TextInputAction.done
                          : TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: field.label,
                        helperText: field.hint,
                        helperMaxLines: 4,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          !field.optional &&
                              (value == null || value.trim().isEmpty)
                          ? 'Enter ${field.label.toLowerCase()}.'
                          : null,
                      onFieldSubmitted: field == login.fields.last
                          ? (_) => _submit()
                          : null,
                    ),
                    const SizedBox(height: 18),
                  ],
                ],
              ),
            ),
          ),
          LoginStep.complete => const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: [
                Icon(Icons.check_circle_outline, size: 56),
                SizedBox(height: 16),
                Text('Account connected'),
                SizedBox(height: 8),
                Text(
                  'Your conversations will appear as they sync.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          LoginStep.failed => switch (login.imessageProblem) {
            final problem? => _IMessageSetupGuide(
              problem: problem,
              onOpenSettings: widget.controller.openFullDiskAccessSettings,
            ),
            null => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.error_outline, size: 48),
                  SizedBox(height: 16),
                  Text('Could not connect this account'),
                ],
              ),
            ),
          },
        },
        if (login.busy && login.step != LoginStep.preparing) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(semanticsLabel: 'Signing in'),
        ],
        if ((login.error ?? widget.controller.error) case final error?) ...[
          const SizedBox(height: 16),
          _Notice(message: error, isError: true),
        ],
        if (login.networkId == 'whatsapp' &&
            login.step == LoginStep.fields) ...[
          const SizedBox(height: 16),
          TextButton(
            onPressed: login.busy
                ? null
                : () => widget.controller.beginLogin('whatsapp', useQr: true),
            child: const Text('Use a QR code on another screen'),
          ),
        ],
      ],
    );
  }

  Widget _qrContent(LoginState login) {
    return Column(
      children: [
        if (login.qrImage != null)
          Semantics(
            label: 'Sign-in QR code. Save it or display it on another screen to scan.',
            image: true,
            child: Image.memory(
              base64Decode(login.qrImage!),
              width: 240,
              height: 240,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          )
        else if (login.qrData == null || login.qrData!.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Loading sign-in code',
              ),
            ),
          )
        else
          Semantics(
            label: 'Sign-in QR code. Save it or display it on another screen to scan.',
            image: true,
            child: ExcludeSemantics(
              child: LayoutBuilder(
                builder: (context, constraints) => Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.white,
                    child: QrImageView(
                      data: login.qrData!,
                      size: (constraints.maxWidth - 32).clamp(120.0, 240.0),
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),
        if (login.qrImage != null || login.qrData?.isNotEmpty == true) ...[
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _exportingQr ? null : () => _exportQr(login),
                icon: const Icon(Icons.save_alt),
                label: Text(
                  defaultTargetPlatform == TargetPlatform.iOS
                      ? 'Save QR to Photos'
                      : 'Save QR code',
                ),
              ),
              if (defaultTargetPlatform == TargetPlatform.iOS)
                OutlinedButton.icon(
                  onPressed: _exportingQr
                      ? null
                      : () => _exportQr(login, share: true),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share QR code'),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Flexible(child: Text('Waiting for approval…')),
          ],
        ),
        TextButton(
          onPressed: login.busy
              ? null
              : () =>
                    widget.controller.beginLogin(login.networkId, useQr: true),
          child: const Text('Get a new QR code'),
        ),
        if (login.networkId == 'whatsapp') ...[
          if (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android)
            TextButton(
              onPressed: login.busy
                  ? null
                  : () =>
                        widget.controller.beginLogin('whatsapp', useQr: false),
              child: const Text('Link with a code on this phone'),
            ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Form(
            key: _phoneFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Link with a phone number instead'),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('whatsapp-pairing-phone'),
                  controller: _values.putIfAbsent(
                    'phone',
                    TextEditingController.new,
                  ),
                  enabled: !login.busy,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp phone number',
                    helperText: 'Include your country code.',
                  ),
                  validator: (value) => value?.trim().isEmpty != false
                      ? 'Enter your phone number.'
                      : null,
                  onFieldSubmitted: (_) => _submitPhone(),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('whatsapp-pair-phone'),
                  onPressed: login.busy ? null : _submitPhone,
                  child: const Text('Get linking code'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _submitPhone() {
    final login = widget.controller.login;
    if (login?.networkId != 'whatsapp' ||
        login!.busy ||
        !(_phoneFormKey.currentState?.validate() ?? false)) {
      return;
    }
    widget.controller.submitLogin({'phone': _values['phone']!.text.trim()});
  }

  Future<void> _exportQr(LoginState login, {bool share = false}) async {
    setState(() => _exportingQr = true);
    try {
      final bytes = await loginQrImageBytes(login);
      if (!mounted) return;
      if (widget.controller.login != login) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The sign-in code changed. Save the new code.'),
          ),
        );
        return;
      }
      await widget.controller.exportLoginQr(bytes, share: share);
      if (mounted &&
          widget.controller.error == null &&
          !share &&
          defaultTargetPlatform == TargetPlatform.iOS) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR code saved to Photos.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The QR code could not be exported. Try a fresh code.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingQr = false);
    }
  }

  void _submit() {
    final login = widget.controller.login;
    if (login == null ||
        login.busy ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    widget.controller.submitLogin({
      for (final field in login.fields) field.id: _values[field.id]?.text ?? '',
    });
  }
}

Future<Uint8List> loginQrImageBytes(LoginState login) async {
  final Uint8List bytes;
  if (login.qrImage != null) {
    bytes = base64Decode(login.qrImage!);
  } else {
    final qr = QrValidator.validate(
      data: login.qrData!,
      version: QrVersions.auto,
    ).qrCode!;
    const moduleSize = 8.0;
    const quietZone = 4 * moduleSize;
    final codeSize = qr.moduleCount * moduleSize;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
    canvas.translate(quietZone, quietZone);
    final painter = QrPainter.withQr(
      qr: qr,
      gapless: true,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );
    painter.paint(canvas, Size.square(codeSize));
    final picture = recorder.endRecording();
    final imageSize = (codeSize + 2 * quietZone).toInt();
    final image = await picture.toImage(imageSize, imageSize);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    bytes = data!.buffer.asUint8List();
  }
  return bytes;
}

class InboxSettingsPage extends StatelessWidget {
  const InboxSettingsPage({
    super.key,
    required this.controller,
    required this.onConnect,
    required this.onOpenConversation,
  });

  final InboxUiController controller;
  final VoidCallback onConnect;
  final ValueChanged<ConversationRoute> onOpenConversation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => _PhoneSettingsPage(page: this),
  );

  String _networkName(String id) {
    for (final network in controller.networks) {
      if (network.id == id) return network.name;
    }
    return id;
  }

  Future<void> _reconnect(BuildContext context, String accountId) {
    final dialog = showDialog<void>(
      context: context,
      builder: (context) => ConnectAccountsDialog(controller: controller),
    );
    unawaited(controller.reconnectAccount(accountId));
    return dialog;
  }

  Future<void> _confirmClearCache(BuildContext context) async {
    if (await confirmClearMediaCache(context)) {
      await controller.clearMediaCache();
    }
  }
}

class _ThemeGrid extends StatelessWidget {
  const _ThemeGrid({required this.controller});

  final InboxUiController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preferences = controller.preferences;
    final palettes = [
      ...InboxThemePalette.presets,
      if (preferences.themePreset == 'custom') ?preferences.palette,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 66).floor().clamp(3, 6);
        final width = (constraints.maxWidth - (columns - 1) * 6) / columns;
        return Wrap(
          spacing: 6,
          runSpacing: 12,
          children: [
            for (final palette in palettes)
              SizedBox(
                width: width,
                child: Semantics(
                  label: '${palette.name} theme',
                  selected: preferences.themePreset == palette.id,
                  button: true,
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: controller.isBusy
                        ? null
                        : () => controller.setPreference(
                            'themePreset',
                            palette.id,
                          ),
                    borderRadius: BorderRadius.circular(13),
                    child: Column(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              width: 2,
                              color: preferences.themePreset == palette.id
                                  ? scheme.onSurface
                                  : Colors.transparent,
                            ),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Color(0xff000000 | palette.background),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: scheme.onSurface.withValues(alpha: .08),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: Color(0xff000000 | palette.logo),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Color(0xff000000 | palette.accent),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          palette.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: preferences.themePreset == palette.id
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _IMessageSetupGuide extends StatelessWidget {
  const _IMessageSetupGuide({
    required this.problem,
    required this.onOpenSettings,
  });

  final IMessageSetupProblem problem;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant);
    final (icon, title, body) = switch (problem) {
      IMessageSetupProblem.fullDiskAccessNeeded ||
      IMessageSetupProblem.stillBlocked => (
        Icons.verified_user_outlined,
        'Allow Inbox+ to read your messages',
        'Inbox+ shows your iMessage and SMS conversations by reading the Messages history on this Mac. macOS protects that history with Full Disk Access.',
      ),
      IMessageSetupProblem.finishInSettings => (
        Icons.verified_user_outlined,
        'Finish in System Settings',
        'Turn on Inbox+ in Full Disk Access. When macOS asks, choose Quit & Reopen, then add iMessage again.',
      ),
      IMessageSetupProblem.messagesNotSetUp => (
        Icons.chat_bubble_outline,
        'Messages isn\'t set up on this Mac',
        'Inbox+ could not find a Messages history. Open Messages, sign in with your Apple Account and wait for your conversations to appear. Then try again.',
      ),
      IMessageSetupProblem.unreadable => (
        Icons.storage_outlined,
        'Inbox+ couldn\'t read your Messages history',
        'Messages may be updating its history. Wait a moment and try again.',
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 30),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center, style: muted),
        if (problem.needsFullDiskAccess) ...[
          if (problem != IMessageSetupProblem.finishInSettings) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.laptop_mac_outlined,
                  size: 15,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Messages are read on this Mac. Nothing is uploaded.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          const _FullDiskAccessPreview(),
          if (problem == IMessageSetupProblem.fullDiskAccessNeeded) ...[
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 4,
              children: [
                for (final (number, step) in const [
                  ('1', 'Open Settings'),
                  ('2', 'Turn on Inbox+'),
                  ('3', 'Choose Quit & Reopen'),
                ])
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$number  ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: step, style: muted),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Center(
            child: TextButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.open_in_new, size: 15),
              label: const Text(
                'System Settings › Privacy & Security › Full Disk Access',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Text(
            'Not in the list? Click + below the list, then choose Inbox+ from Applications.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        if (problem == IMessageSetupProblem.stillBlocked) ...[
          const SizedBox(height: 16),
          const _Notice(
            message: 'Inbox+ still can\'t read Messages. If you just turned on access, quit and reopen Inbox+, then try again.',
          ),
        ],
      ],
    );
  }
}

class _FullDiskAccessPreview extends StatelessWidget {
  const _FullDiskAccessPreview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final small = theme.textTheme.bodySmall!;
    Widget placeholderRow({required bool on}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          _appSquare(colors.surfaceContainerHighest),
          const SizedBox(width: 9),
          Container(
            width: 70,
            height: 8,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const Spacer(),
          _Switch(on: on),
        ],
      ),
    );
    return Semantics(
      label: 'Illustration of System Settings showing Inbox+ in the Full Disk Access list with its switch turned off',
      image: true,
      child: ExcludeSemantics(
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 128,
                  color: colors.surfaceContainerHigh,
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final item in const [
                        'General',
                        'Appearance',
                        'Notifications',
                        'Privacy & Security',
                        'Desktop & Dock',
                      ])
                        Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: item == 'Privacy & Security'
                              ? BoxDecoration(
                                  color: colors.primary,
                                  borderRadius: BorderRadius.circular(6),
                                )
                              : null,
                          child: Text(
                            item,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: small.copyWith(
                              color: item == 'Privacy & Security'
                                  ? colors.onPrimary
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Privacy & Security › ',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const TextSpan(
                                text: 'Full Disk Access',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          style: small,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              placeholderRow(on: false),
                              Container(
                                color: colors.primary.withValues(alpha: .08),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(5),
                                      child: Image.asset(
                                        'assets/inboxplus-logo.png',
                                        width: 20,
                                        height: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    Text(
                                      'Inbox+',
                                      style: small.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    const _Switch(on: false, highlighted: true),
                                  ],
                                ),
                              ),
                              placeholderRow(on: true),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '+   −',
                          style: small.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _appSquare(Color color) => Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(5),
    ),
  );
}

class _Switch extends StatelessWidget {
  const _Switch({required this.on, this.highlighted = false});

  final bool on;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 30,
      height: 18,
      padding: const EdgeInsets.all(2),
      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: on ? const Color(0xff34c759) : colors.outlineVariant,
        borderRadius: BorderRadius.circular(9),
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: colors.primary.withValues(alpha: .3),
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      child: Container(
        width: 14,
        height: 14,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isError
              ? colors.errorContainer
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 20,
              color: isError ? colors.onErrorContainer : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isError ? colors.onErrorContainer : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A file size worded as Finder words one: decimal units, whole kilobytes, one decimal for megabytes
/// and two for larger sizes.
String formatByteCount(int bytes) {
  if (bytes == 0) return 'Zero KB';
  if (bytes < 1000) return '$bytes byte${bytes == 1 ? '' : 's'}';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var index = 0;
  String scaled() =>
      (bytes / math.pow(1000, index + 1)).toStringAsFixed(math.min(index, 2));
  while (index < units.length - 1 && double.parse(scaled()) >= 1000) {
    index++;
  }
  final value = scaled();
  final trimmed = value.contains('.')
      ? value.replaceFirst(RegExp(r'\.?0+$'), '')
      : value;
  return '$trimmed ${units[index]}';
}
