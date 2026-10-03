import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:senecapp/data/api/api_client.dart';
import 'package:senecapp/data/api/client_context.dart';

import 'support/fakes.dart';

void main() {
  late FakeAuthService auth;

  setUp(() => auth = signedInAuth());

  ApiClient client(MockClientHandler handler) => ApiClient(
    baseUrl: 'http://test/api/v1/',
    auth: auth,
    context: testClientContext(),
    httpClient: MockClient(handler),
  );

  test('sends the bearer token and the client context headers', () async {
    late http.Request sent;
    await client((request) async {
      sent = request;
      return jsonResponse({});
    }).get('/me');

    expect(sent.url.toString(), 'http://test/api/v1/me');
    expect(sent.headers['Authorization'], 'Bearer test-token');
    expect(sent.headers['X-App'], 'flutter');
    expect(sent.headers['X-App-Version'], '1.0.0');
    expect(sent.headers['X-Platform'], 'android');
    expect(sent.headers['X-Device-Model'], 'Google Pixel 8');
    expect(sent.headers['X-OS-Version'], '14');
    expect(sent.headers['X-Session-Id'], matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  test('drops null query values and repeats list values', () async {
    late Uri url;
    await client((request) async {
      url = request.url;
      return jsonResponse([]);
    }).get(
      '/groups',
      query: {
        'q': 'tennis',
        'category': null,
        'interest_id': [1, 2],
      },
    );

    expect(url.queryParametersAll, {
      'q': ['tennis'],
      'interest_id': ['1', '2'],
    });
  });

  test('sends JSON bodies and decodes UTF-8 responses', () async {
    late http.Request sent;
    final result = await client((request) async {
      sent = request;
      return jsonResponse({'full_name': 'Sofía Arango'});
    }).patch('/me', body: {'semester': 6});

    expect(sent.method, 'PATCH');
    expect(sent.headers['Content-Type'], startsWith('application/json'));
    expect(sent.body, '{"semester":6}');
    expect(result, {'full_name': 'Sofía Arango'});
  });

  test("surfaces the backend's error detail", () async {
    final api = client(
      (_) async => jsonResponse({'detail': 'Email domain is not allowed'}, 403),
    );

    await expectLater(
      api.get('/me'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.message, 'message', 'Email domain is not allowed'),
      ),
    );
  });

  test('uses the first validation message for invalid input', () async {
    final api = client(
      (_) async => jsonResponse({
        'detail': [
          {'msg': 'Input should be less than or equal to 20'},
        ],
      }, 422),
    );

    await expectLater(
      api.patch('/me', body: {'semester': 99}),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Input should be less than or equal to 20',
        ),
      ),
    );
  });

  test('retries once with a fresh token after a 401', () async {
    final tokens = <String?>[];
    final result = await client((request) async {
      tokens.add(request.headers['Authorization']);
      return tokens.length == 1
          ? jsonResponse({'detail': 'Invalid or expired token'}, 401)
          : jsonResponse({'ok': true});
    }).get('/me');

    expect(tokens, ['Bearer test-token', 'Bearer fresh-token']);
    expect(result, {'ok': true});
  });

  test('reports a session that stays unauthorized', () async {
    var unauthorized = 0;
    final api = client(
      (_) async => jsonResponse({'detail': 'Invalid or expired token'}, 401),
    )..onUnauthorized = () => unauthorized++;

    await expectLater(api.get('/me'), throwsA(isA<ApiException>()));
    expect(unauthorized, 1);
  });

  test('turns connection failures into network errors', () async {
    final api = client(
      (_) async => throw http.ClientException('Connection refused'),
    );

    await expectLater(
      api.get('/me'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.isNetworkError,
          'isNetworkError',
          true,
        ),
      ),
    );
  });

  group('session id', () {
    late DateTime now;
    late ClientContext context;

    setUp(() {
      now = DateTime(2026, 10, 2, 12);
      context = ClientContext(
        appVersion: '1.0.0',
        platform: 'android',
        deviceModel: 'Google Pixel 8',
        osVersion: '14',
        clock: () => now,
      );
    });

    test('survives a short trip to the background', () {
      final first = context.sessionId;

      context.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 29));
      context.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(context.sessionId, first);
    });

    test('is replaced after 30 minutes in the background', () {
      final first = context.sessionId;

      context.didChangeAppLifecycleState(AppLifecycleState.hidden);
      context.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 30));
      context.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(context.sessionId, isNot(first));
    });
  });
}
