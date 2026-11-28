import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:senecapp/data/local/join_history_store.dart';
import 'package:senecapp/data/repositories/join_sources_repository.dart';
import 'package:senecapp/features/join_sources/join_sources_view_model.dart';
import 'support/fakes.dart';

void main() {
  test('a permission refusal clears previously displayed BQ6 data', () async {
    var forbidden = false;
    final fake = FakeBackend(adminOf: {1}).client;
    final client = MockClient((request) async {
      if (forbidden && request.url.path.endsWith('/insights/join-sources')) {
        return http.Response('{"detail":"Forbidden"}', 403);
      }
      return http.Response.fromStream(
        await fake.send(
          http.Request(request.method, request.url)
            ..headers.addAll(request.headers)
            ..bodyBytes = request.bodyBytes,
        ),
      );
    });
    final services = testServices(auth: signedInAuth(), backend: client);
    final connection = StreamController<void>.broadcast();
    final repository = JoinSourcesRepository(
      api: services.api,
      store: MemoryJoinHistoryStore(),
    )..useAccount('a');
    final model = JoinSourcesViewModel(
      groupId: 1,
      repository: repository,
      analytics: services.analytics,
      reconnected: connection.stream,
    );
    await model.load();
    expect(model.view, isNotNull);
    forbidden = true;
    await model.load(force: true);
    expect(model.view, isNull);
    expect(model.error?.statusCode, 403);
    model.dispose();
    await connection.close();
  });
}
