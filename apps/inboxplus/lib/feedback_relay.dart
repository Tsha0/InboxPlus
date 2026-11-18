import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ui/inbox_ui_controller.dart';

typedef FeedbackSubmitter = Future<FeedbackReceipt> Function(
  FeedbackDraft draft,
  Map<String, Object?> diagnostics,
);

class FeedbackRelay {
  FeedbackRelay({Uri? endpoint, this.timeout = const Duration(seconds: 60)})
    : endpoint = endpoint ?? Uri.parse('https://inboxplus.chat/api/feedback');

  final Uri endpoint;
  final Duration timeout;

  Future<FeedbackReceipt> submit(
    FeedbackDraft draft,
    Map<String, Object?> diagnostics,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      return await _post(client, draft, diagnostics).timeout(timeout);
    } on FeedbackFailure {
      rethrow;
    } on SocketException {
      throw FeedbackFailure.offline;
    } catch (_) {
      throw FeedbackFailure.unavailable;
    } finally {
      client.close(force: true);
    }
  }

  Future<FeedbackReceipt> _post(
    HttpClient client,
    FeedbackDraft draft,
    Map<String, Object?> diagnostics,
  ) async {
    final body = utf8.encode(
      jsonEncode({
        'kind': draft.kind.wireName,
        'text': draft.text,
        'app': {
          'version': inboxPlusVersion,
          'build': inboxPlusBuild,
          'platform': Platform.operatingSystem,
        },
        'diagnostics': diagnostics,
        if (draft.image case final image?) 'image': base64Encode(image),
      }),
    );
    final request = await client.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.contentLength = body.length;
    request.add(body);
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    return switch (response.statusCode) {
      200 => FeedbackReceipt(issueUrl: _trustedIssueUrl(text)),
      413 => throw FeedbackFailure.tooLarge,
      400 || 405 => throw FeedbackFailure.rejected,
      _ => throw FeedbackFailure.unavailable,
    };
  }

  static Uri? _trustedIssueUrl(String body) {
    final Object? value;
    try {
      value = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (value case {'issueUrl': final String raw}) {
      final url = Uri.tryParse(raw);
      if (url != null && url.isScheme('https') && url.host == 'github.com') {
        return url;
      }
    }
    return null;
  }
}
