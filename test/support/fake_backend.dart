import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes.dart';

/// An in-memory SENECApp backend for widget tests.
///
/// Serves the prototype's eight organizations, six events and four
/// notifications, applies search filters the way the real API does, keeps
/// joins, saves and inbox changes, and records every request so tests can
/// check what the app sent.
class FakeBackend {
  FakeBackend({
    Object me = sofiaJson,
    this.meStatus = 200,
    Set<int> memberIds = const {1, 2, 5},
    bool withSchedule = true,
    this.liveEventId,
    this.adminOf = const {},
  }) : me = me is Map ? {...me} : me,
       memberIds = {...memberIds},
       schedule = [
         if (withSchedule)
           {
             'id': 1,
             'weekday': 0,
             'start_time': '08:30:00',
             'end_time': '09:50:00',
             'title': 'Cálculo II',
             'building': _building,
           },
       ];

  /// An event moved to right now (started 10 minutes ago), so check-in is
  /// open. Every other event is days away.
  final int? liveEventId;

  /// Groups the student is an admin of: they get the check-in QR codes.
  final Set<int> adminOf;

  /// Events the student has checked in to.
  final Set<int> attended = {};

  /// Every event's check-in code.
  static String checkInCode(int eventId) => 'K7Q2X$eventId';

  /// `GET /me`; a `PATCH /me` changes it.
  final Object me;
  final int meStatus;

  /// `GET /me/schedule`, as the backend stores it.
  List<Map<String, dynamic>> schedule;

  /// The `request_id` of every "Free right now" answer.
  static const freeNowRequestId = '6d2f9b1a-8c4e-4f7a-b3d5-1e9a0c2b7f64';

  static const _building = {
    'id': 1,
    'code': 'ML',
    'name': 'Edificio Mario Laserna',
    'latitude': 4.6026,
    'longitude': -74.0649,
  };

  final Set<int> memberIds;
  final Set<int> savedIds = {};

  /// Every request after it arrived, oldest first.
  final List<http.Request> requests = [];

  /// When true, every request fails as if the server were unreachable.
  bool offline = false;

  /// Paths (after `/api/v1`) that answer 500, e.g. `/groups`.
  final Set<String> failing = {};

  /// Every client analytics event received, oldest first.
  final List<Map<String, dynamic>> analyticsEvents = [];

  /// When true, only the recommender fails (500).
  bool recommenderDown = false;

  /// The `request_id` of every recommendation list served.
  static const recRequestId = '0f8c2a7e-3b1d-4c5e-9a6f-2d4b8e1c7a90';

  /// What the recommender suggests, best first: the student's non-member
  /// groups with the reasons the real one would give.
  static const _recommended = [
    (3, ['Matches your interests: Travel', 'Popular on campus']),
    (6, ['Verified group']),
    (8, ['Its events fit your free time']),
  ];

  late final MockClient client = MockClient(_handle);

  /// Requests with [method] whose path ends with [path] (`/groups`,
  /// `/groups/3/join`...).
  List<http.Request> requestsTo(String method, String path) => [
    for (final r in requests)
      if (r.method == method && r.url.path == '/api/v1$path') r,
  ];

  // --- Data -----------------------------------------------------------------

  static final _now = DateTime.now().toUtc();

  static DateTime _inDays(int days, int hour) =>
      DateTime.utc(_now.year, _now.month, _now.day + days, hour);

  static const _interests = [
    (1, 'Tennis'),
    (7, 'Startups'),
    (11, 'Networking'),
    (12, 'AI/ML'),
    (15, 'Finance'),
    (23, 'Travel'),
    (24, 'Photography'),
    (26, 'Cars'),
    (30, 'Theater'),
  ];

  static const _categories = {
    'sports': 'Sports',
    'business': 'Business',
    'technology': 'Technology',
    'arts': 'Arts',
    'travel': 'Travel',
    'cars': 'Cars',
  };

  /// id, name, category, members, color, verified, interest ids, description.
  static const _groups = [
    (
      1,
      'Tennis Uniandes',
      'sports',
      142,
      '#A50104',
      true,
      [1],
      'Competitive and recreational tennis for all levels.',
    ),
    (
      2,
      'Emprendedores Uniandes',
      'business',
      318,
      '#FF6B35',
      true,
      [7, 11],
      'Where future founders meet. Pitch nights and mentorship.',
    ),
    (
      3,
      'Viajeros Uniandes',
      'travel',
      207,
      '#00C9A7',
      false,
      [23],
      'Explore Colombia and beyond with group trips.',
    ),
    (
      4,
      'Auto Enthusiasts',
      'cars',
      89,
      '#A78BFA',
      false,
      [26],
      'Monthly car meets and track days at Tocancipá.',
    ),
    (
      5,
      'AI & Machine Learning',
      'technology',
      256,
      '#3B82F6',
      true,
      [12],
      'Research papers, Kaggle competitions and build sessions.',
    ),
    (
      6,
      'Teatro Los Andes',
      'arts',
      173,
      '#EC4899',
      true,
      [30],
      'From improv to full theatrical productions.',
    ),
    (
      7,
      'Finance Society',
      'business',
      195,
      '#F59E0B',
      false,
      [15],
      'CFA prep, case competitions and connections to finance firms.',
    ),
    (
      8,
      'Fotografía Uniandes',
      'arts',
      134,
      '#6366F1',
      false,
      [24],
      'Darkroom access, photowalks and exhibitions.',
    ),
  ];

  /// id, group id, title, days from now, hour (UTC).
  static final _events = [
    (1, 1, 'Round Robin Tournament', 2, 13),
    (2, 5, 'LLM Workshop: Build Your Own Agent', 1, 22),
    (3, 2, 'Pitch Night #14', 3, 23),
    (4, 3, 'Trip to Salento & Coffee Region', 9, 12),
    (5, 4, 'Monthly Car Meet', 11, 15),
    (6, 6, 'Open Auditions: Obra de Semestre', 5, 0),
  ];

  late final List<Map<String, dynamic>> _notifications = [
    _notification(
      1,
      'new_event',
      'New event from Tennis Uniandes',
      'Round Robin Tournament is this Saturday.',
      1,
      1,
      hoursAgo: 2,
    ),
    _notification(
      2,
      'new_event',
      'New event from AI & Machine Learning',
      'LLM Workshop: Build Your Own Agent.',
      5,
      2,
      hoursAgo: 5,
    ),
    _notification(
      3,
      'group_message',
      'Emprendedores Uniandes',
      'Pitch Night #14 spots are filling up.',
      2,
      null,
      hoursAgo: 26,
    ),
    _notification(
      4,
      'group_recommendation',
      'A new group you might like',
      'Check out Viajeros Uniandes',
      3,
      null,
      hoursAgo: 50,
      opened: true,
    ),
  ];

  static Map<String, dynamic> _notification(
    int id,
    String type,
    String title,
    String body,
    int? groupId,
    int? eventId, {
    required int hoursAgo,
    bool opened = false,
  }) {
    final created = _now.subtract(Duration(hours: hoursAgo));
    return {
      'id': id,
      'type': type,
      'title': title,
      'body': body,
      'data': {'group_id': groupId, 'event_id': eventId},
      'group_id': groupId,
      'event_id': eventId,
      'created_at': created.toIso8601String(),
      'opened_at': opened ? created.toIso8601String() : null,
      'dismissed_at': null,
    };
  }

  Map<String, dynamic> _groupJson(int id, {bool detail = false}) {
    final g = _groups.firstWhere((g) => g.$1 == id);
    final events = _events.where((e) => e.$2 == id).toList()
      ..sort((a, b) => a.$4.compareTo(b.$4));
    return {
      'id': g.$1,
      'name': g.$2,
      'category': {
        'id': 1,
        'slug': g.$3,
        'label': _categories[g.$3],
        'icon': null,
      },
      'description': g.$8,
      'color': g.$5,
      'image_url': null,
      'verified': g.$6,
      'is_active': true,
      'member_count': g.$4,
      'tags': [
        for (final (tagId, name) in _interests)
          if (g.$7.contains(tagId)) {'id': tagId, 'slug': name, 'name': name},
      ],
      'next_event': events.isEmpty
          ? null
          : {
              'id': events.first.$1,
              'title': events.first.$3,
              'starts_at': _inDays(
                events.first.$4,
                events.first.$5,
              ).toIso8601String(),
            },
      'is_member': memberIds.contains(id),
      'is_saved': savedIds.contains(id),
      if (detail) ...{
        'founded_year': 2015,
        'contact_email': 'hola@uniandes.edu.co',
        'instagram_url': null,
        'website_url': null,
        'meeting_building': {
          'id': 1,
          'code': 'ML',
          'name': 'Edificio Mario Laserna',
          'latitude': 4.6026,
          'longitude': -74.0649,
        },
        'upcoming_events': [
          for (final e in events) _eventJson(e.$1, withGroup: false),
        ],
        'my_role': memberIds.contains(id) ? 'member' : null,
        'created_at': '2026-01-01T00:00:00Z',
      },
    };
  }

  Map<String, dynamic> _eventJson(int id, {bool withGroup = true}) {
    final e = _events.firstWhere((e) => e.$1 == id);
    final g = _groups.firstWhere((g) => g.$1 == e.$2);
    final starts = e.$1 == liveEventId
        ? _now.subtract(const Duration(minutes: 10))
        : _inDays(e.$4, e.$5);
    return {
      'id': e.$1,
      'group_id': e.$2,
      'title': e.$3,
      'starts_at': starts.toIso8601String(),
      'ends_at': starts.add(const Duration(hours: 2)).toIso8601String(),
      'building': {
        'id': 1,
        'code': 'ML',
        'name': 'Edificio Mario Laserna',
        'latitude': 4.6026,
        'longitude': -74.0649,
      },
      'location_detail': 'Salón 224',
      'is_cancelled': false,
      if (withGroup) ...{
        'description': null,
        'capacity': null,
        'group': {'id': g.$1, 'name': g.$2, 'color': g.$5},
        'attendee_count': 0,
        'checked_in': attended.contains(e.$1),
      },
    };
  }

  // --- Routing --------------------------------------------------------------

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    if (offline) throw http.ClientException('Connection refused');
    if (failing.contains(request.url.path.replaceFirst('/api/v1', ''))) {
      return jsonResponse({'detail': 'Internal Server Error'}, 500);
    }

    final path = request.url.path.replaceFirst('/api/v1', '');
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final query = request.url.queryParametersAll;

    switch ((request.method, segments)) {
      case ('POST', ['me', 'devices']):
        return http.Response('', 204);

      case ('DELETE', ['me', 'devices', _]):
        return http.Response('', 204);

      case ('POST', ['analytics', 'events']):
        final events = (jsonDecode(request.body) as Map)['events'] as List;
        analyticsEvents.addAll(events.cast<Map<String, dynamic>>());
        return jsonResponse({'accepted': events.length, 'duplicates': 0}, 202);

      case ('GET', ['me']):
        return jsonResponse(me, meStatus);

      case ('PATCH', ['me']):
        (me as Map).addAll(jsonDecode(request.body) as Map);
        return jsonResponse(me);

      case ('GET', ['me', 'schedule']):
        return jsonResponse(schedule);

      case ('PUT', ['me', 'schedule']):
        final blocks = (jsonDecode(request.body) as Map)['blocks'] as List;
        schedule = [
          for (final (i, block) in blocks.indexed)
            {
              'id': i + 1,
              'weekday': block['weekday'],
              'start_time': block['start_time'],
              'end_time': block['end_time'],
              'title': block['title'],
              'building': block['building_id'] == 1 ? _building : null,
            },
        ];
        return jsonResponse(schedule);

      case ('GET', ['recommendations', 'events', 'free-now']):
        return jsonResponse(_freeNow(request.url.queryParameters));

      case ('GET', ['events', final id, 'check-in-code']):
        final event = _events.firstWhere((e) => e.$1 == int.parse(id));
        if (!adminOf.contains(event.$2)) {
          return jsonResponse({'detail': 'Group admin role required'}, 403);
        }
        return jsonResponse({
          'event_id': event.$1,
          'code': checkInCode(event.$1),
          'qr_payload':
              'senecapp://check-in?event_id=${event.$1}'
              '&code=${checkInCode(event.$1)}',
        });

      case ('POST', ['events', final id, 'check-in']):
        return _checkIn(int.parse(id), jsonDecode(request.body) as Map);

      case ('GET', ['events', final id]):
        return jsonResponse(_eventJson(int.parse(id)));

      case ('GET', ['groups']):
        final items = _search(query);
        return jsonResponse({
          'items': items,
          'total': items.length,
          'limit': 50,
          'offset': 0,
        });

      case ('GET', ['groups', final id]):
        return jsonResponse(_groupJson(int.parse(id), detail: true));

      case ('PUT', ['groups', final id, 'save']):
        savedIds.add(int.parse(id));
        return http.Response('', 204);

      case ('DELETE', ['groups', final id, 'save']):
        savedIds.remove(int.parse(id));
        return http.Response('', 204);

      case ('POST', ['groups', final id, 'join']):
        memberIds.add(int.parse(id));
        return jsonResponse({
          'group_id': int.parse(id),
          'role': 'member',
          'status': 'active',
          'joined_at': _now.toIso8601String(),
          'entry_point': (jsonDecode(request.body) as Map)['entry_point'],
        });

      case ('GET', ['me', 'groups']):
        return jsonResponse([for (final id in memberIds) _groupJson(id)]);

      case ('GET', ['events']):
        final mine = query['mine']?.first == 'true';
        return jsonResponse({
          'items': [
            for (final e in [..._events]..sort((a, b) => a.$4.compareTo(b.$4)))
              if (!mine || memberIds.contains(e.$2)) _eventJson(e.$1),
          ],
          'total': 0,
          'limit': 50,
          'offset': 0,
        });

      case ('GET', ['me', 'notifications']):
        return jsonResponse({
          'items': _notifications,
          'total': _notifications.length,
          'limit': 50,
          'offset': 0,
          'unread_count': _notifications
              .where((n) => n['opened_at'] == null)
              .length,
        });

      case ('POST', ['me', 'notifications', final id, final action]):
        final notification = _notifications.firstWhere(
          (n) => n['id'] == int.parse(id),
        );
        notification[action == 'open' ? 'opened_at' : 'dismissed_at'] = _now
            .toIso8601String();
        return jsonResponse(notification);

      case ('GET', ['recommendations', 'groups']):
        if (recommenderDown) {
          return jsonResponse({'detail': 'Internal Server Error'}, 500);
        }
        return jsonResponse({
          'request_id': recRequestId,
          'model_version': 'test-v1',
          'items': [
            for (final (id, reasons) in _recommended)
              if (!memberIds.contains(id))
                {'group': _groupJson(id), 'score': 0.8, 'reasons': reasons},
          ],
        });

      case ('GET', ['interests']):
        return jsonResponse([
          for (final (id, name) in _interests)
            {'id': id, 'slug': name, 'name': name, 'category': null},
        ]);

      case ('GET', ['buildings']):
        return jsonResponse([
          {
            'id': 1,
            'code': 'ML',
            'name': 'Edificio Mario Laserna',
            'latitude': 4.6026,
            'longitude': -74.0649,
          },
        ]);
    }
    return jsonResponse({'detail': 'Not Found'}, 404);
  }

  /// The real rules: right code, within the check-in window, and within
  /// 500 m of the venue when a position is sent. Twice is fine.
  http.Response _checkIn(int eventId, Map body) {
    if (body['code'] != checkInCode(eventId)) {
      return jsonResponse({'detail': 'Invalid check-in code'}, 422);
    }
    if (attended.contains(eventId)) {
      return jsonResponse({
        'event_id': eventId,
        'checked_in_at': _now.toIso8601String(),
        'distance_m': null,
        'already_checked_in': true,
      });
    }
    if (eventId != liveEventId) {
      return jsonResponse({
        'detail': "Check-in is only open around the event's time",
      }, 409);
    }
    double? distance;
    if (body['latitude'] case final num latitude) {
      // Roughly metres from Mario Laserna; enough for a fake.
      distance =
          ((latitude - 4.6026).abs() +
              ((body['longitude'] as num) + 74.0649).abs()) *
          111000;
      if (distance > 500) {
        return jsonResponse({
          'detail': 'You seem to be too far from the event to check in',
        }, 409);
      }
    }
    attended.add(eventId);
    return jsonResponse({
      'event_id': eventId,
      'checked_in_at': _now.toIso8601String(),
      'distance_m': distance,
      'already_checked_in': false,
    });
  }

  /// Mirrors the real rules: GPS only with consent, else the class
  /// schedule's building; no schedule means "free for two hours".
  Map<String, dynamic> _freeNow(Map<String, String> query) {
    final optedIn = (me as Map)['location_opt_in'] == true;
    final gps = optedIn && query.containsKey('latitude');
    final source = gps
        ? 'gps'
        : schedule.isNotEmpty
        ? 'schedule'
        : 'none';
    return {
      'request_id': freeNowRequestId,
      'free_block': {
        'starts_at': _now.toIso8601String(),
        'ends_at': _now.add(const Duration(minutes: 70)).toIso8601String(),
        'minutes': 70,
      },
      'schedule_known': schedule.isNotEmpty,
      'location': {
        'building': source == 'none' ? null : _building,
        'source': source,
        'on_campus': gps ? true : null,
      },
      'items': [
        {
          'event': _eventJson(2),
          'distance_m': 240.0,
          'walking_minutes': 4,
          'score': 0.81,
          'reasons': ['4 min walk', 'Matches your interests'],
        },
        {
          'event': _eventJson(3),
          'distance_m': null,
          'walking_minutes': null,
          'score': 0.62,
          'reasons': ['From one of your groups'],
        },
      ],
      'message': null,
    };
  }

  List<Map<String, dynamic>> _search(Map<String, List<String>> query) {
    final q = query['q']?.first.toLowerCase();
    final categories = query['category'] ?? const [];
    final interestIds = (query['interest_id'] ?? const []).map(int.parse);
    final verified = query['verified']?.first;

    final matches = _groups.where((g) {
      final text = [
        g.$2,
        g.$8,
        _categories[g.$3]!,
        for (final (id, name) in _interests)
          if (g.$7.contains(id)) name,
      ].join(' ').toLowerCase();
      return (q == null || text.contains(q)) &&
          (categories.isEmpty || categories.contains(g.$3)) &&
          (interestIds.isEmpty || interestIds.any(g.$7.contains)) &&
          (verified == null || g.$6 == (verified == 'true'));
    }).toList()..sort((a, b) => b.$4.compareTo(a.$4));

    return [for (final g in matches) _groupJson(g.$1)];
  }
}
