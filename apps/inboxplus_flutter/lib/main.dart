import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'app_controller.dart';
import 'platform/app_environment.dart';
import 'ui/inbox_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Inbox+ embedded dependencies',
    ], await rootBundle.loadString('assets/third_party_notices.txt'));
  });
  runApp(const InboxPlus());
}

class InboxPlus extends StatefulWidget {
  const InboxPlus({super.key});

  @override
  State<InboxPlus> createState() => _InboxPlusState();
}

class _InboxPlusState extends State<InboxPlus> {
  AppController? _controller;
  String? _error;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    AppEnvironment.native.setMethodCallHandler((call) async {
      if (call.method == 'notificationActivated') {
        await _controller?.openPendingNotification();
        return null;
      }
      if (call.method == 'prepareToTerminate') {
        final controller = _controller;
        if (controller == null) return _error != null;
        try {
          await controller.close();
          return true;
        } catch (_) {
          return false;
        }
      }
      if (call.method != 'prepareToClose') throw MissingPluginException();
      try {
        await _controller?.flushBeforeClose();
        return true;
      } catch (_) {
        return false;
      }
    });
    _lifecycle = AppLifecycleListener(
      onResume: () =>
          unawaited(_controller?.openPendingNotification() ?? Future.value()),
      onHide: () => unawaited(_controller?.flush() ?? Future.value()),
      onDetach: () => unawaited(_controller?.close() ?? Future.value()),
    );
    unawaited(_open());
  }

  Future<void> _open() async {
    setState(() => _error = null);
    try {
      final controller = await AppController.open();
      if (!mounted) {
        await controller.close();
        return;
      }
      setState(() => _controller = controller);
      await controller.openPendingNotification();
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Inbox+ startup failed: ${error.runtimeType}${error is PlatformException ? ' (${error.code})' : ''}',
        );
      }
      if (!mounted) return;
      setState(
        () => _error = error is AppStorageException
            ? error.message
            : 'Your profile could not be opened. Existing data has been kept.',
      );
    }
  }

  @override
  void dispose() {
    AppEnvironment.native.setMethodCallHandler(null);
    _lifecycle.dispose();
    unawaited(_controller?.close() ?? Future.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller != null) return InboxPlusApp(controller: _controller!);
    return MaterialApp(
      title: inboxPlusAppName,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: _error == null
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 24),
                      Text('Opening your inbox…'),
                    ],
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline, size: 40),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _open,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
