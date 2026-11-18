import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:url_launcher/url_launcher.dart';

import 'feedback_image.dart';
import 'inbox_ui_controller.dart';

class FeedbackForm {
  FeedbackKind? kind;
  final text = TextEditingController();
  bool includeDiagnostics = false;
  Uint8List? image;

  FeedbackDraft? get draft {
    final kind = this.kind;
    final body = text.text.trim();
    if (kind == null || body.isEmpty) return null;
    return FeedbackDraft(
      kind: kind,
      text: body,
      includeDiagnostics: includeDiagnostics,
      image: image,
    );
  }

  void clear() {
    kind = null;
    text.clear();
    includeDiagnostics = false;
    image = null;
  }

  void dispose() => text.dispose();
}

Future<Uint8List?> chooseFeedbackImage(InboxUiController controller) async {
  final bytes = await controller.pickFeedbackImage();
  return bytes == null ? null : normalizeFeedbackImage(bytes);
}

String feedbackImageError(Exception error) => error is FeedbackImageFailure
    ? error.message
    : 'Inbox+ can’t read this file as an image. Choose a PNG or JPEG.';

sealed class _Phase {
  const _Phase();
}

final class _Editing extends _Phase {
  const _Editing();
}

final class _Sending extends _Phase {
  const _Sending();
}

final class _Sent extends _Phase {
  const _Sent(this.kind, this.receipt);
  final FeedbackKind kind;
  final FeedbackReceipt receipt;
}

final class _Failed extends _Phase {
  const _Failed(this.message);
  final String message;
}

class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({
    super.key,
    required this.controller,
    required this.form,
    required this.captureBoundary,
  });

  final InboxUiController controller;
  final FeedbackForm form;
  final GlobalKey captureBoundary;

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  _Phase _phase = const _Editing();
  bool _attaching = false;
  String? _imageError;
  final _sendFocus = FocusNode();

  FeedbackForm get _form => widget.form;
  bool get _editable => _phase is _Editing || _phase is _Failed;
  bool get _canSend => _editable && !_attaching && _form.draft != null;

  @override
  void initState() {
    super.initState();
    _form.text.addListener(_textChanged);
  }

  @override
  void dispose() {
    _form.text.removeListener(_textChanged);
    _sendFocus.dispose();
    super.dispose();
  }

  void _textChanged() => setState(() {});

  Future<void> _send() async {
    final draft = _form.draft;
    if (draft == null || !_canSend) return;
    setState(() => _phase = const _Sending());
    try {
      final receipt = await widget.controller.sendFeedback(draft);
      _form.clear();
      if (mounted) setState(() => _phase = _Sent(draft.kind, receipt));
    } on FeedbackFailure catch (failure) {
      if (!mounted) return;
      setState(() => _phase = _Failed(failure.message));
      _sendFocus.requestFocus();
    }
  }

  Future<void> _attach(Future<Uint8List?> Function() source) async {
    setState(() {
      _attaching = true;
      _imageError = null;
    });
    try {
      final image = await source();
      if (mounted && image != null) setState(() => _form.image = image);
    } on Exception catch (error) {
      if (mounted) setState(() => _imageError = feedbackImageError(error));
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  Future<Uint8List?> _chooseImage() => chooseFeedbackImage(widget.controller);

  Future<Uint8List?> _captureWindow() async {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        widget.captureBoundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final longest = math.max(boundary.size.width, boundary.size.height);
    final image = await boundary.toImage(
      pixelRatio: math.min(ratio, feedbackImageMaxEdge / longest),
    );
    try {
      return await fitFeedbackImage(image);
    } finally {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _phase is! _Sending,
    child: Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: math.max(0, MediaQuery.sizeOf(context).height - 48),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: switch (_phase) {
            _Sent(:final kind, :final receipt) => _sent(context, kind, receipt),
            _ => _editor(context),
          },
        ),
      ),
    ),
  );

  Widget _editor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kind = _form.kind;
    final failure = switch (_phase) {
      _Failed(:final message) => message,
      _ => null,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: const Text(
            'Send feedback',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        Text(switch (kind) {
          null => 'Bugs, requests and suggestions are posted publicly on GitHub. Praise is sent privately.',
          FeedbackKind(isPublic: true) =>
            'Posted publicly on GitHub. Don’t include private messages.',
          _ => 'Sent privately to the developer.',
        }, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final value in FeedbackKind.values) _kind(value)],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('feedback-text'),
          controller: _form.text,
          autofocus: true,
          enabled: _editable,
          minLines: 5,
          maxLines: 10,
          maxLength: 5000,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            hintText: 'Tell us what went wrong, or share general feedback.',
          ),
          buildCounter: (
            context, {
            required currentLength,
            required isFocused,
            maxLength,
          }) => currentLength > 4500 ? Text('$currentLength/$maxLength') : null,
        ),
        const SizedBox(height: 12),
        _screenshot(context),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const Key('feedback-diagnostics'),
          value: _form.includeDiagnostics,
          onChanged: _editable
              ? (value) => setState(() => _form.includeDiagnostics = value!)
              : null,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          visualDensity: VisualDensity.compact,
          title: const Text('Attach diagnostics'),
          subtitle: const Text(
            'Version, platform, connected networks, settings and counts. No messages or account names.',
          ),
        ),
        if (failure != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(failure, style: TextStyle(color: scheme.error)),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            if (kind?.expectsScreenshot == true && _form.image == null)
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.photo,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'No screenshot attached',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              const Spacer(),
            TextButton(
              key: const Key('feedback-close'),
              onPressed: _phase is _Sending
                  ? null
                  : () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('feedback-send'),
              focusNode: _sendFocus,
              style: _buttonStyle,
              onPressed: _canSend ? _send : null,
              child: _phase is _Sending
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Sending…'),
                      ],
                    )
                  : const Text('Send feedback'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _kind(FeedbackKind kind) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _form.kind == kind;
    void choose() => setState(() => _form.kind = kind);
    return Semantics(
      label: kind.label,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      enabled: _editable,
      onTap: _editable ? choose : null,
      excludeSemantics: true,
      child: TextButton(
        key: Key('feedback-kind-${kind.name}'),
        onPressed: _editable ? choose : null,
        style: TextButton.styleFrom(
          backgroundColor: selected ? scheme.primary : Colors.transparent,
          foregroundColor: selected ? scheme.onPrimary : scheme.onSurface,
          disabledBackgroundColor: selected
              ? scheme.primary.withValues(alpha: .5)
              : Colors.transparent,
          disabledForegroundColor: selected
              ? scheme.onPrimary.withValues(alpha: .8)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          minimumSize: const Size(0, 28),
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
        ),
        child: Text(
          kind.label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _screenshot(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = _form.image;
    final notice = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final zone = BoxDecoration(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: scheme.outlineVariant),
    );
    if (image != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 200,
            decoration: zone,
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.memory(
                    image,
                    key: const Key('feedback-image-preview'),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    semanticLabel: 'Screenshot to send',
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: IconButton(
                    key: const Key('feedback-remove-image'),
                    tooltip: 'Remove screenshot',
                    onPressed: _editable
                        ? () => setState(() => _form.image = null)
                        : null,
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.surface,
                      minimumSize: const Size(26, 26),
                    ),
                    icon: const Icon(CupertinoIcons.xmark, size: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text('Only the developer can see this screenshot.', style: notice),
        ],
      );
    }
    final busy = _attaching || !_editable;
    return Container(
      decoration: zone,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Icon(CupertinoIcons.photo, size: 24, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            _form.kind?.isPublic == false
                ? 'Add a screenshot of what you like.'
                : 'Add a screenshot. It helps us fix this faster.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              TextButton.icon(
                key: const Key('feedback-capture'),
                onPressed: busy ? null : () => _attach(_captureWindow),
                style: TextButton.styleFrom(
                  backgroundColor: scheme.surfaceContainer,
                ),
                icon: const Icon(CupertinoIcons.macwindow, size: 15),
                label: const Text('Capture Inbox+ window'),
              ),
              TextButton.icon(
                key: const Key('feedback-choose-image'),
                onPressed: busy ? null : () => _attach(_chooseImage),
                style: TextButton.styleFrom(
                  backgroundColor: scheme.surfaceContainer,
                ),
                icon: const Icon(CupertinoIcons.folder, size: 15),
                label: const Text('Choose image…'),
              ),
            ],
          ),
          if (_attaching) ...[
            const SizedBox(height: 12),
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: 'Preparing screenshot',
              ),
            ),
          ],
          if (_imageError case final error?) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sent(
    BuildContext context,
    FeedbackKind kind,
    FeedbackReceipt receipt,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final issueUrl = receipt.issueUrl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          CupertinoIcons.checkmark_circle_fill,
          size: 36,
          color: scheme.primary,
        ),
        const SizedBox(height: 12),
        Semantics(
          header: true,
          liveRegion: true,
          child: const Text(
            'Thanks for your feedback',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          kind.isPublic
              ? 'It’s posted on GitHub.'
              : 'It was sent privately to the developer.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (issueUrl != null) ...[
              TextButton(
                key: const Key('feedback-view-issue'),
                onPressed: () =>
                    launchUrl(issueUrl, mode: LaunchMode.externalApplication),
                child: const Text('View on GitHub'),
              ),
              const SizedBox(width: 8),
            ],
            FilledButton(
              key: const Key('feedback-done'),
              autofocus: true,
              style: _buttonStyle,
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ],
    );
  }

  static final _buttonStyle = FilledButton.styleFrom(
    minimumSize: const Size(0, 24),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const TextStyle(fontSize: 13),
  );
}
