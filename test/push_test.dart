import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:senecapp/data/push/push_service.dart';

import 'support/fakes.dart';

/// Push notifications (Firebase Cloud Messaging) and the inbox interactions
/// BQ8 compares: opened versus cleared without a look.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late FakeBackend backend;
  late FakePushService push;

  Future<void> openApp(WidgetTester tester, {FakePushService? withPush}) async {
    backend = FakeBackend();
    push = withPush ?? FakePushService();
    await pumpApp(
      tester,
      testServices(auth: signedInAuth(), backend: backend.client, push: push),
    );
  }

  /// A push about the AI & ML workshop (event 2), inbox entry 2.
  const workshopPush = PushNotification(
    notificationId: 2,
    groupId: 5,
    eventId: 2,
    title: 'New event from AI & Machine Learning',
    body: 'LLM Workshop: Build Your Own Agent.',
  );

  group('Device registration', () {
    testWidgets('signing in registers this phone', (tester) async {
      await openApp(tester);

      final registration = backend.requestsTo('POST', '/me/devices').single;
      expect(jsonDecode(registration.body), {
        'token': 'fcm-token-1',
        'platform': 'android',
        'app': 'flutter',
      });
    });

    testWidgets('a rotated token is registered again', (tester) async {
      await openApp(tester);

      push.rotateToken('fcm-token-2');
      await tester.pumpAndSettle();

      final tokens = [
        for (final r in backend.requestsTo('POST', '/me/devices'))
          (jsonDecode(r.body) as Map)['token'],
      ];
      expect(tokens, ['fcm-token-1', 'fcm-token-2']);
    });

    testWidgets('no permission, no registration', (tester) async {
      await openApp(tester, withPush: FakePushService(currentToken: null));

      expect(backend.requestsTo('POST', '/me/devices'), isEmpty);
    });

    testWidgets('without Firebase nothing is registered', (tester) async {
      backend = FakeBackend();
      await pumpApp(
        tester,
        testServices(auth: signedInAuth(), backend: backend.client),
      );

      expect(
        backend.requests.where((r) => r.url.path.contains('/me/devices')),
        isEmpty,
      );
    });

    testWidgets('signing out unregisters it, while still signed in', (
      tester,
    ) async {
      await openApp(tester);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.fling(find.text('INTERESTS'), const Offset(0, -1000), 2000);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      final removal = backend
          .requestsTo('DELETE', '/me/devices/fcm-token-1')
          .single;
      expect(removal.headers['Authorization'], 'Bearer test-token');
    });
  });

  group('Pushes', () {
    testWidgets('tapping one records the open and shows its event', (
      tester,
    ) async {
      await openApp(tester);
      final inboxFetches = backend
          .requestsTo('GET', '/me/notifications')
          .length;

      push.tap(workshopPush);
      await tester.pumpAndSettle();

      expect(
        backend.requestsTo('POST', '/me/notifications/2/open'),
        hasLength(1),
      );
      expect(
        backend.requestsTo('GET', '/events/2').single.url.queryParameters,
        {'entry_point': 'notification'},
      );
      expect(find.text('HOSTED BY'), findsOneWidget);
      expect(
        backend.requestsTo('GET', '/me/notifications').length,
        inboxFetches + 1,
        reason: 'the bell catches up',
      );
    });

    testWidgets('a push about a group opens the group', (tester) async {
      await openApp(tester);

      push.tap(
        const PushNotification(
          notificationId: 4,
          groupId: 3,
          title: 'A new group you might like',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        backend.requestsTo('GET', '/groups/3').single.url.queryParameters,
        {'entry_point': 'notification'},
      );
    });

    testWidgets('a push the app was launched from opens on start', (
      tester,
    ) async {
      await openApp(
        tester,
        withPush: FakePushService(launchPush: workshopPush),
      );

      expect(
        backend.requestsTo('POST', '/me/notifications/2/open'),
        hasLength(1),
      );
      expect(find.text('HOSTED BY'), findsOneWidget);
    });

    testWidgets('one arriving while the app is open is shown in it', (
      tester,
    ) async {
      await openApp(tester);
      final inboxFetches = backend
          .requestsTo('GET', '/me/notifications')
          .length;

      push.arrive(workshopPush);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('New event from AI & Machine Learning'),
        findsOneWidget,
      );
      expect(
        backend.requestsTo('GET', '/me/notifications').length,
        inboxFetches + 1,
      );
      expect(
        backend.requestsTo('POST', '/me/notifications/2/open'),
        isEmpty,
        reason: 'seeing it is not opening it',
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(
        backend.requestsTo('POST', '/me/notifications/2/open'),
        hasLength(1),
      );
      expect(find.text('HOSTED BY'), findsOneWidget);
    });
  });

  testWidgets('swiping a card away dismisses it without opening it', (
    tester,
  ) async {
    await openApp(tester);
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('3 unread'), findsOneWidget);

    await tester.drag(
      find.text('Round Robin Tournament is this Saturday.'),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(
      backend.requestsTo('POST', '/me/notifications/1/dismiss'),
      hasLength(1),
    );
    expect(
      backend.requests.where((r) => r.url.path.endsWith('/open')),
      isEmpty,
    );
    expect(find.text('2 unread'), findsOneWidget);
    // Still listed, now read.
    expect(
      find.text('Round Robin Tournament is this Saturday.'),
      findsOneWidget,
    );
  });

  test('reads the push payload', () {
    final push = PushNotification.fromData({
      'notification_id': '852',
      'type': 'new_event',
      'group_id': '1',
      'event_id': '19',
    }, title: 'New event from Tennis Uniandes');

    expect(push.notificationId, 852);
    expect(push.groupId, 1);
    expect(push.eventId, 19);
    expect(push.title, 'New event from Tennis Uniandes');
    expect(
      PushNotification.fromData({'type': 'group_message'}).groupId,
      isNull,
    );
  });
}
