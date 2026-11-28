import 'package:senecapp/data/api/api_client.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:senecapp/data/local/health_store.dart';
import 'package:senecapp/data/local/insight_store.dart';
import 'package:senecapp/data/repositories/group_health_repository.dart';
import 'package:senecapp/data/repositories/insights_repository.dart';
import 'support/fakes.dart';

class DelayedHealth extends MemoryHealthStore {
  final started = Completer<void>();
  final reply = Completer<StoredHealth?>();
  @override
  Future<StoredHealth?> read(String account, int groupId) {
    if (account == 'a') {
      started.complete();
      return reply.future;
    }
    return super.read(account, groupId);
  }
}

class DelayedInsight extends MemoryInsightStore {
  final started = Completer<void>();
  final reply = Completer<StoredInsight?>();
  @override
  Future<StoredInsight?> read(String account, String key) {
    if (account == 'a') {
      started.complete();
      return reply.future;
    }
    return super.read(account, key);
  }
}

void main() {
  final body =
      jsonDecode(
            r'''{"health": {"question": "Which active student groups show a decline in participation (>30% over four consecutive weeks), and which re-engagement feature produces the higher return to attendance rate: event reminders or group messages?", "answer": "4 groups declined >30% over four weeks (Basket Andes, Board Game Caf\u00e9, Fotograf\u00eda Uniandes, Sociedad de Debate). Event reminders produced the higher return-to-attendance rate (60.0% vs 25.0%).", "weeks": [{"week_start": "2026-10-03T01:38:40.339075Z", "attendance": 31}, {"week_start": "2026-10-10T01:38:40.339075Z", "attendance": 16}, {"week_start": "2026-10-17T01:38:40.339075Z", "attendance": 24}, {"week_start": "2026-10-24T01:38:40.339075Z", "attendance": 29}, {"week_start": "2026-10-31T01:38:40.339075Z", "attendance": 31}, {"week_start": "2026-11-07T01:38:40.339075Z", "attendance": 30}, {"week_start": "2026-11-14T01:38:40.339075Z", "attendance": 40}, {"week_start": "2026-11-21T01:38:40.339075Z", "attendance": 59}], "baseline": 25.0, "recent": 40.0, "decline_pct": -0.6, "declining": false, "case": null, "arms": [{"arm": "event_reminders", "groups": 2, "lapsed": 15, "returned": 9, "return_to_attendance_rate": 0.6}, {"arm": "group_messages", "groups": 2, "lapsed": 4, "returned": 1, "return_to_attendance_rate": 0.25}]}, "profile_tips": {"question": "Which fields of a group profile are most correlated with students saving or joining the group?", "answer": "Fields most correlated with saving or joining: has_image (r=0.09, 1.65x conversion), has_instagram (r=0.07, 1.42x conversion), description_length (r=0.07).", "days": 90, "filled": 7, "total": 7, "fields": [{"field": "has_image", "filled": true, "views": 13461, "correlation": 0.0913, "lift": 1.65, "conversion_with": 0.1857, "conversion_without": 0.1125}, {"field": "has_instagram", "filled": true, "views": 13461, "correlation": 0.069, "lift": 1.42, "conversion_with": 0.182, "conversion_without": 0.1286}, {"field": "has_founded_year", "filled": true, "views": 13461, "correlation": 0.0601, "lift": 1.7, "conversion_with": 0.1711, "conversion_without": 0.1005}, {"field": "has_meeting_building", "filled": true, "views": 13461, "correlation": 0.0392, "lift": 1.33, "conversion_with": 0.1689, "conversion_without": 0.1266}, {"field": "has_website", "filled": true, "views": 13461, "correlation": 0.036, "lift": 1.21, "conversion_with": 0.1887, "conversion_without": 0.1563}, {"field": "has_contact_email", "filled": true, "views": 13461, "correlation": 0.0319, "lift": 1.17, "conversion_with": 0.1716, "conversion_without": 0.1466}, {"field": "has_upcoming_event", "filled": true, "views": 13461, "correlation": null, "lift": null, "conversion_with": 0.1632, "conversion_without": null}]}}''',
          )
          as Map<String, dynamic>;
  final now = DateTime(2026, 11, 27, 12);
  test('Health: late read from A must not populate B cache', () async {
    var requests = 0;
    final services = testServices(
      auth: signedInAuth(),
      backend: MockClient((_) async {
        requests++;
        return http.Response('{"detail":"Forbidden"}', 403);
      }),
    );
    final store = DelayedHealth();
    final repo = GroupHealthRepository(
      api: services.api,
      store: store,
      clock: () => now,
    )..useAccount('a');
    final pending = repo.load(5);
    await store.started.future;
    repo.useAccount('b');
    store.reply.complete(
      StoredHealth(body: body['health'] as Map<String, dynamic>, savedAt: now),
    );
    await expectLater(pending, throwsA(isA<ApiException>()));
    Object? outcome;
    try {
      outcome = await repo.load(5);
    } catch (e) {
      outcome = e;
    }
    expect(
      requests,
      1,
      reason: 'B must contact server; actual $outcome was served from A cache',
    );
  });
  test('Insights: late read from A must not populate B cache', () async {
    var requests = 0;
    final services = testServices(
      auth: signedInAuth(),
      backend: MockClient((_) async {
        requests++;
        return http.Response('{"detail":"Forbidden"}', 403);
      }),
    );
    final store = DelayedInsight();
    final repo = InsightsRepository(
      api: services.api,
      store: store,
      clock: () => now,
    )..useAccount('a');
    final pending = repo.profileTips(5);
    await store.started.future;
    repo.useAccount('b');
    store.reply.complete(
      StoredInsight(body: body['profile_tips'], savedAt: now),
    );
    await expectLater(pending, throwsA(isA<ApiException>()));
    Object? outcome;
    try {
      outcome = await repo.profileTips(5);
    } catch (e) {
      outcome = e;
    }
    expect(
      requests,
      1,
      reason: 'B must contact server; actual $outcome was served from A cache',
    );
  });
}
