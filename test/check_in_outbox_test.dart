import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:senecapp/data/api/api_client.dart';
import 'package:senecapp/state/check_in_outbox.dart';
import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'pending attendance survives restart and stays with its owner',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var online = false;
      var sent = 0;
      final services = testServices(
        auth: signedInAuth(),
        backend: MockClient((request) async {
          if (!online) throw http.ClientException('offline');
          sent++;
          return http.Response(
            jsonEncode({
              'event_id': 1,
              'checked_in_at': '2026-11-27T12:00:00Z',
              'distance_m': null,
              'already_checked_in': false,
            }),
            200,
          );
        }),
      );
      final reconnect = StreamController<void>.broadcast();
      CheckInOutbox build(String owner) => CheckInOutbox(
        account: owner,
        events: services.events,
        preferences: prefs,
        onCheckedIn: () {},
        reconnected: reconnect.stream,
      );
      final first = build('a');
      await first.start();
      await expectLater(
        first.submit(1, code: 'valid'),
        throwsA(isA<ApiException>()),
      );
      first.dispose();
      online = true;
      final other = build('b');
      await other.start();
      expect(sent, 0);
      other.dispose();
      final restored = build('a');
      await restored.start();
      expect(sent, 1);
      expect(jsonDecode(prefs.getString('check_in.outbox.a')!), isEmpty);
      restored.dispose();
      await reconnect.close();
    },
  );
}
