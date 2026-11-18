import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inboxplus/feedback_relay.dart';
import 'package:inboxplus/ui/inbox_ui_controller.dart';

void main() {
  late HttpServer server;
  late Uri endpoint;
  final requests = <({ContentType? type, Map<String, Object?> body})>[];
  late Future<void> Function(HttpResponse response) respond;

  void reply(int status, Object body) => respond = (response) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  };

  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = Uri.parse('http://127.0.0.1:${server.port}/api/feedback');
    server.listen((request) async {
      requests.add((
        type: request.headers.contentType,
        body: jsonDecode(
          await utf8.decodeStream(request),
        ) as Map<String, Object?>,
      ));
      await respond(request.response);
    });
  });

  tearDown(() => server.close(force: true));

  test('posts the report and returns its GitHub issue', () async {
    reply(200, {'issueUrl': 'https://github.com/Tsha0/InboxPlus/issues/42'});
    final image = Uint8List.fromList([137, 80, 78, 71]);
    final receipt = await FeedbackRelay(endpoint: endpoint).submit(
      FeedbackDraft(
        kind: FeedbackKind.needsWork,
        text: 'Sidebar is cramped',
        includeDiagnostics: true,
        image: image,
      ),
      {
        'version': '0.9.0',
        'storage': {'messages': 3},
      },
    );
    expect(
      receipt.issueUrl,
      Uri.parse('https://github.com/Tsha0/InboxPlus/issues/42'),
    );
    expect(requests.single.type?.mimeType, 'application/json');
    expect(requests.single.body, {
      'kind': 'needsWork',
      'text': 'Sidebar is cramped',
      'app': {
        'version': inboxPlusVersion,
        'build': inboxPlusBuild,
        'platform': Platform.operatingSystem,
      },
      'diagnostics': {
        'version': '0.9.0',
        'storage': {'messages': 3},
      },
      'image': base64Encode(image),
    });
  });

  test('praise succeeds without an issue or optional fields', () async {
    reply(200, {});
    final receipt = await FeedbackRelay(endpoint: endpoint).submit(
      const FeedbackDraft(kind: FeedbackKind.praise, text: 'Love it'),
      null,
    );
    expect(receipt.issueUrl, isNull);
    expect(requests.single.body.keys, unorderedEquals(['kind', 'text', 'app']));
    expect(requests.single.body['kind'], 'praise');
  });

  for (final url in [
    'https://example.com/Tsha0/InboxPlus/issues/1',
    'http://github.com/Tsha0/InboxPlus/issues/1',
    'https://github.com.example.com/issues/1',
    'javascript:alert(1)',
  ]) {
    test('a sent report drops the untrusted link $url', () async {
      reply(200, {'issueUrl': url});
      final receipt = await FeedbackRelay(endpoint: endpoint).submit(
        const FeedbackDraft(kind: FeedbackKind.bug, text: 'Crash'),
        null,
      );
      expect(receipt.issueUrl, isNull);
    });
  }

  for (final (status, failure) in [
    (400, FeedbackFailure.rejected),
    (405, FeedbackFailure.rejected),
    (413, FeedbackFailure.tooLarge),
    (429, FeedbackFailure.unavailable),
    (500, FeedbackFailure.unavailable),
    (503, FeedbackFailure.unavailable),
  ]) {
    test('status $status fails as ${failure.name}', () async {
      reply(status, {'error': 'relay detail'});
      await expectLater(
        FeedbackRelay(endpoint: endpoint).submit(
          const FeedbackDraft(kind: FeedbackKind.bug, text: 'Crash'),
          null,
        ),
        throwsA(failure),
      );
    });
  }

  test('an unreachable relay fails as offline', () async {
    final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close(force: true);
    await expectLater(
      FeedbackRelay(endpoint: Uri.parse('http://127.0.0.1:$port/api/feedback'))
          .submit(
            const FeedbackDraft(kind: FeedbackKind.bug, text: 'Crash'),
            null,
          ),
      throwsA(FeedbackFailure.offline),
    );
  });

  test('a relay that never answers fails as unavailable', () async {
    respond = (_) => Completer<void>().future;
    await expectLater(
      FeedbackRelay(
        endpoint: endpoint,
        timeout: const Duration(milliseconds: 200),
      ).submit(
        const FeedbackDraft(kind: FeedbackKind.bug, text: 'Crash'),
        null,
      ),
      throwsA(FeedbackFailure.unavailable),
    );
  });
}
