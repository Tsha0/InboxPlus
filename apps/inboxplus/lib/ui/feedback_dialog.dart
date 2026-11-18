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
  Uint8List? image;

  FeedbackDraft? get draft {
    final kind = this.kind;
    final body = text.text.trim();
    if (kind == null || body.isEmpty) return null;
    return FeedbackDraft(kind: kind, text: body, image: image);
  }

  void clear() {
    kind = null;
    text.clear();
    image = null;
  }

  void dispose() => text.dispose();
}

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
    } on Exception {
      if (mounted) {
        setState(
          () => _imageError =
              'Inbox+ can’t read this file as an image. Choose a PNG or JPEG.',
        );
      }
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  Future<Uint8List?> _chooseImage() async {
    final bytes = await widget.controller.pickFeedbackImage();
    return bytes == null ? null : normalizeFeedbackImage(bytes);
  }

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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 480;
    final padding = narrow ? 18.0 : 30.0;
    return PopScope(
      canPop: _phase is! _Sending,
      child: Dialog(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        constraints: const BoxConstraints(maxWidth: 592),
        insetPadding: EdgeInsets.all(narrow ? 12 : 24),
        child: SingleChildScrollView(
          child: switch (_phase) {
            _Sent(:final kind, :final receipt) => Padding(
              padding: EdgeInsets.all(padding),
              child: _sent(context, kind, receipt),
            ),
            _ => _editor(scheme, padding),
          },
        ),
      ),
    );
  }

  Widget _editor(ColorScheme scheme, double padding) {
    final supporting = _supportingStyle(scheme);
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: scheme.outline),
    );
    final hint = switch (_form.kind) {
      FeedbackKind.bug => 'What happened? What did you expect instead?',
      FeedbackKind.feature => 'What would you like Inbox+ to do?',
      FeedbackKind.needsWork => 'What could work better?',
      FeedbackKind.praise => 'What’s working well for you?',
      null => 'Tell us what you’d like us to know.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padding, padding, padding, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: const Text(
                  'Send feedback',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 6),
              Text('Help us make Inbox+ better.', style: supporting),
              const SizedBox(height: 22),
              const Text('Feedback type', style: _labelStyle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final kind in FeedbackKind.values) _kind(kind)],
              ),
              const SizedBox(height: 22),
              const ExcludeSemantics(
                child: Text('Details', style: _labelStyle),
              ),
              const SizedBox(height: 8),
              Semantics(
                label: 'Details',
                child: TextField(
                  key: const Key('feedback-text'),
                  controller: _form.text,
                  autofocus: true,
                  enabled: _editable,
                  minLines: 5,
                  maxLines: 10,
                  maxLength: 5000,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText: hint,
                    contentPadding: const EdgeInsets.all(14),
                    enabledBorder: fieldBorder,
                    focusedBorder: fieldBorder.copyWith(
                      borderSide: BorderSide(color: scheme.primary, width: 2),
                    ),
                  ),
                  buildCounter:
                      (
                        context, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) => currentLength > 4500
                      ? Text('$currentLength/$maxLength')
                      : null,
                ),
              ),
              const SizedBox(height: 22),
              _screenshot(scheme),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: EdgeInsets.fromLTRB(padding, 16, padding, 20),
          child: _footer(scheme),
        ),
      ],
    );
  }

  Widget _footer(ColorScheme scheme) {
    final supporting = _supportingStyle(scheme);
    final (visibility, warning) = switch (_form.kind) {
      null => (
        'Bugs, requests and suggestions are posted publicly on GitHub.',
        ' Praise is sent privately.',
      ),
      FeedbackKind(isPublic: true) => (
        'Posted publicly on GitHub.',
        ' Don’t include private messages.',
      ),
      _ => ('Sent privately to the developer.', ''),
    };
    final failure = switch (_phase) {
      _Failed(:final message) => message,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(CupertinoIcons.info, size: 15, color: supporting.color),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text.rich(
                      TextSpan(
                        text: visibility,
                        style: _labelStyle.copyWith(fontSize: 12),
                        children: [TextSpan(text: warning, style: supporting)],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Diagnostics are attached automatically. They don’t include messages or account names.',
                    style: supporting,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (failure != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(failure, style: TextStyle(color: scheme.error)),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              key: const Key('feedback-close'),
              style: _secondaryStyle(scheme, height: 40),
              onPressed: _phase is _Sending
                  ? null
                  : () => Navigator.pop(context),
              child: const Text('Close'),
            ),
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
          backgroundColor: selected
              ? scheme.primary.withValues(alpha: .12)
              : Colors.transparent,
          foregroundColor: scheme.onSurface,
          disabledBackgroundColor: selected
              ? scheme.primary.withValues(alpha: .08)
              : Colors.transparent,
          disabledForegroundColor: scheme.onSurfaceVariant,
          visualDensity: VisualDensity.standard,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: const Size(0, 35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
        ),
        child: Text(kind.label, style: _labelStyle),
      ),
    );
  }

  Widget _screenshot(ColorScheme scheme) {
    final image = _form.image;
    final busy = _attaching || !_editable;
    final supporting = _supportingStyle(scheme);
    final buttonStyle = _secondaryStyle(scheme, height: 34).copyWith(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
    final description = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(CupertinoIcons.photo, size: 15, color: supporting.color),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  text: 'Screenshot',
                  style: _labelStyle,
                  children: [TextSpan(text: ' · Optional', style: supporting)],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                image == null
                    ? 'Check for private content before sending.'
                    : 'Only the developer can see this screenshot.',
                style: supporting,
              ),
            ],
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (image == null) ...[
          TextButton(
            key: const Key('feedback-capture'),
            onPressed: busy ? null : () => _attach(_captureWindow),
            style: buttonStyle,
            child: const Text('Capture window'),
          ),
          TextButton(
            key: const Key('feedback-choose-image'),
            onPressed: busy ? null : () => _attach(_chooseImage),
            style: buttonStyle,
            child: const Text('Choose image…'),
          ),
        ] else
          TextButton(
            key: const Key('feedback-remove-image'),
            onPressed: busy ? null : () => setState(() => _form.image = null),
            style: buttonStyle,
            child: const Text('Remove screenshot'),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 440
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [description, const SizedBox(height: 10), actions],
                )
              : Row(
                  children: [
                    Expanded(child: description),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * .55,
                      ),
                      child: actions,
                    ),
                  ],
                ),
        ),
        if (image != null) ...[
          const SizedBox(height: 10),
          Container(
            height: 150,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Image.memory(
              image,
              key: const Key('feedback-image-preview'),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              semanticLabel: 'Screenshot to send',
            ),
          ),
        ],
        if (_attaching) ...[
          const SizedBox(height: 10),
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: 'Preparing screenshot',
              ),
            ),
          ),
        ],
        if (_imageError case final error?) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(error, style: supporting.copyWith(color: scheme.error)),
          ),
        ],
      ],
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
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (issueUrl != null)
              TextButton(
                key: const Key('feedback-view-issue'),
                onPressed: () =>
                    launchUrl(issueUrl, mode: LaunchMode.externalApplication),
                style: _secondaryStyle(scheme, height: 40),
                child: const Text('View on GitHub'),
              ),
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

  static const _labelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  static TextStyle _supportingStyle(ColorScheme scheme) => TextStyle(
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w400,
    color: Color.alphaBlend(
      scheme.onSurface.withValues(alpha: .25),
      scheme.onSurfaceVariant,
    ),
  );

  static ButtonStyle _secondaryStyle(
    ColorScheme scheme, {
    required double height,
  }) => _buttonStyle.merge(
    TextButton.styleFrom(
      minimumSize: Size(0, height),
      backgroundColor: scheme.surfaceContainerLow,
      disabledBackgroundColor: scheme.surfaceContainerLow,
      foregroundColor: scheme.onSurface,
      side: BorderSide(color: scheme.outlineVariant),
    ),
  );

  static final _buttonStyle = FilledButton.styleFrom(
    minimumSize: const Size(0, 40),
    visualDensity: VisualDensity.standard,
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: _labelStyle,
  );
}
