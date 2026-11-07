import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'confirmation.dart';
import 'inbox_ui_controller.dart';
import 'network_badge.dart';

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
                        if (login.step == LoginStep.failed) ...[
                          FilledButton(
                            onPressed: login.busy
                                ? null
                                : () => widget.controller.beginLogin(
                                    login.networkId,
                                  ),
                            child: const Text('Try again'),
                          ),
                        ],
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
          LoginStep.preparing => const Padding(
            padding: EdgeInsets.all(36),
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text('Preparing secure sign-in…'),
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
          LoginStep.failed => const Padding(
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
  });

  final InboxUiController controller;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Make Inbox+ feel like home.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              _SettingsGroup(
                title: 'Connected accounts',
                trailing: TextButton.icon(
                  onPressed: controller.isBusy ? null : onConnect,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add account'),
                ),
                children: [
                  if (controller.accounts.isEmpty)
                    const ListTile(
                      leading: Icon(Icons.person_add_alt_1_outlined),
                      title: Text('No accounts yet'),
                      subtitle: Text(
                        'Add a network to bring your conversations here.',
                      ),
                    ),
                  for (final account in controller.accounts)
                    ListTile(
                      leading: NetworkBadge(
                        network: account.platform,
                        size: 42,
                        labelled: false,
                      ),
                      title: Text(account.displayName),
                      subtitle: Text(
                        '${_networkName(account.platform)} · ${account.isConnected ? 'Connected' : 'Disconnected'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!account.isConnected)
                            IconButton(
                              tooltip: 'Reconnect ${account.displayName}',
                              onPressed: controller.isBusy
                                  ? null
                                  : () => _reconnect(context, account.id),
                              icon: const Icon(Icons.refresh),
                            ),
                          IconButton(
                            tooltip: 'Remove ${account.displayName}',
                            onPressed: controller.isBusy
                                ? null
                                : () async {
                                    if (await confirmAccountRemoval(
                                      context,
                                      _networkName(account.platform),
                                    )) {
                                      await controller.removeAccount(
                                        account.id,
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              _SettingsGroup(
                title: 'Appearance',
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Color mode',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        _ColorModePicker(controller: controller),
                      ],
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                    child: _ThemeGrid(controller: controller),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SettingsGroup(
                title: 'Messages',
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_none),
                    title: const Text('Show notifications'),
                    subtitle: const Text(
                      'While Inbox+ is running, with device permission. '
                      'Background notifications on phones are not available yet.',
                    ),
                    value: controller.preferences.notificationsEnabled,
                    onChanged: controller.isBusy
                        ? null
                        : (value) => controller.setPreference(
                            'notificationsEnabled',
                            value,
                          ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    secondary: const Icon(Icons.keyboard_return),
                    title: const Text('Press Enter to send'),
                    subtitle: const Text(
                      'Shift+Enter always starts a new line.',
                    ),
                    value: controller.preferences.enterToSend,
                    onChanged: controller.isBusy
                        ? null
                        : (value) =>
                              controller.setPreference('enterToSend', value),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SettingsGroup(
                title: 'Muted conversations',
                children: [
                  if (!controller.conversations.any(
                    (conversation) => controller
                        .preferencesFor(conversation.route)
                        .isMutedAt(DateTime.now()),
                  ))
                    const ListTile(
                      leading: Icon(Icons.notifications_none),
                      title: Text('No muted conversations'),
                    ),
                  for (final conversation in controller.conversations)
                    if (controller
                        .preferencesFor(conversation.route)
                        .isMutedAt(DateTime.now()))
                      ListTile(
                        leading: const Icon(Icons.notifications_off_outlined),
                        title: Text(conversation.title),
                        trailing: TextButton(
                          onPressed: controller.isBusy
                              ? null
                              : () => controller.setMuted(
                                  conversation.route,
                                  false,
                                ),
                          child: const Text('Unmute'),
                        ),
                      ),
                ],
              ),
              const SizedBox(height: 24),
              _SettingsGroup(
                title: 'Hidden conversations',
                children: [
                  if (!controller.conversations.any(
                    (conversation) =>
                        controller
                            .preferencesFor(conversation.route)
                            .hiddenAt !=
                        null,
                  ))
                    const ListTile(
                      leading: Icon(Icons.visibility_outlined),
                      title: Text('No hidden conversations'),
                    ),
                  for (final conversation in controller.conversations)
                    if (controller
                            .preferencesFor(conversation.route)
                            .hiddenAt !=
                        null)
                      ListTile(
                        leading: const Icon(Icons.visibility_off_outlined),
                        title: Text(conversation.title),
                        trailing: TextButton(
                          onPressed: controller.isBusy
                              ? null
                              : () => controller.setHidden(
                                  conversation.route,
                                  false,
                                ),
                          child: const Text('Restore'),
                        ),
                      ),
                ],
              ),
              const SizedBox(height: 24),
              _SettingsGroup(
                title: 'Storage on this device',
                children: [
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('Downloaded media'),
                    subtitle: Text(
                      '${controller.storageSummary.attachmentCount} attachments',
                    ),
                    trailing: Text(
                      formatByteCount(controller.storageSummary.mediaBytes),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: const Text('Saved messages'),
                    trailing: Text('${controller.storageSummary.messageCount}'),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    title: const Text('Clear downloaded media'),
                    subtitle: const Text(
                      'Messages, drafts and unsent attachments are kept.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    enabled:
                        !controller.isBusy &&
                        controller.storageSummary.mediaBytes > 0,
                    onTap:
                        !controller.isBusy &&
                            controller.storageSummary.mediaBytes > 0
                        ? () => _confirmClearCache(context)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (controller.error case final error?) ...[
                _Notice(message: error, isError: true),
                const SizedBox(height: 24),
              ],
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Open source licenses'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Inbox+',
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Inbox+  ·  All your conversations, one inbox.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

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

class _ColorModePicker extends StatelessWidget {
  const _ColorModePicker({required this.controller});

  final InboxUiController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label) in [
            ('system', 'System'),
            ('light', 'Light'),
            ('dark', 'Dark'),
          ])
            Semantics(
              selected: controller.preferences.appearance == value,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: controller.preferences.appearance == value
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .12),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: TextButton(
                  onPressed: controller.isBusy
                      ? null
                      : () => controller.setPreference('appearance', value),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    foregroundColor: scheme.onSurface,
                    backgroundColor: controller.preferences.appearance == value
                        ? (dark
                              ? scheme.onSurface.withValues(alpha: .16)
                              : Colors.white)
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: controller.preferences.appearance == value
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
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

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
        Card.outlined(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
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
