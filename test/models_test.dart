import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senecapp/core/format/dates.dart';
import 'package:senecapp/data/models/app_notification.dart';
import 'package:senecapp/data/models/campus_event.dart';
import 'package:senecapp/data/models/group_filters.dart';
import 'package:senecapp/data/models/rso.dart';
import 'package:senecapp/data/models/rso_category.dart';

void main() {
  group('Rso.fromJson', () {
    final json = {
      'id': 8,
      'name': 'Fotografía Uniandes',
      'category': {'id': 4, 'slug': 'arts', 'label': 'Arts', 'icon': null},
      'description': 'Photowalks.',
      'color': '#6366F1',
      'image_url': null,
      'verified': false,
      'is_active': true,
      'member_count': 134,
      'tags': [
        {'id': 24, 'slug': 'photography', 'name': 'Photography'},
      ],
      'next_event': {
        'id': 9,
        'title': 'Photowalk',
        'starts_at': '2026-10-03T14:00:00Z',
      },
      'is_member': false,
      'is_saved': true,
    };

    test('reads a list item', () {
      final rso = Rso.fromJson(json);

      expect(rso.category, RsoCategory.arts);
      expect(rso.color, const Color(0xFF6366F1));
      expect(rso.tags, ['Photography']);
      expect(rso.isSaved, isTrue);
      expect(rso.nextEventAt, DateTime.utc(2026, 10, 3, 14));
      expect(rso.upcomingEvents, isEmpty);
    });

    test('finds the bundled photo from the name', () {
      expect(Rso.fromJson(json).imageSlug, 'fotografia_uniandes');
      expect(
        Rso.fromJson({...json, 'name': 'AI & Machine Learning'}).imageSlug,
        'ai_machine_learning',
      );
    });

    test('reads the profile extras and tags its events with the group', () {
      final rso = Rso.fromJson({
        ...json,
        'founded_year': 2012,
        'meeting_building': {'id': 1, 'code': 'ML', 'name': 'Mario Laserna'},
        'upcoming_events': [
          {
            'id': 9,
            'group_id': 8,
            'title': 'Photowalk',
            'starts_at': '2026-10-03T14:00:00Z',
            'ends_at': '2026-10-03T16:00:00Z',
            'building': null,
            'location_detail': null,
            'is_cancelled': false,
          },
        ],
      });

      expect(rso.foundedYear, 2012);
      expect(rso.meetingBuilding, 'Mario Laserna');
      expect(rso.upcomingEvents.single.rsoName, 'Fotografía Uniandes');
      expect(rso.upcomingEvents.single.color, rso.color);
      expect(rso.upcomingEvents.single.location, 'Location to be announced');
    });

    test('an unknown category or colour falls back instead of failing', () {
      final rso = Rso.fromJson({
        ...json,
        'category': {'id': 99, 'slug': 'esports', 'label': 'Esports'},
        'color': null,
      });

      expect(rso.category, RsoCategory.all);
      expect(rso.color, isNotNull);
    });
  });

  test('a notification is unread until opened or dismissed', () {
    final notification = AppNotification.fromJson({
      'id': 1,
      'type': 'new_event',
      'title': 'New event',
      'body': 'Drop-in',
      'data': <String, dynamic>{},
      'group_id': 1,
      'event_id': null,
      'created_at': '2026-10-02T12:00:00Z',
      'opened_at': null,
      'dismissed_at': null,
    });

    expect(notification.unread, isTrue);
    expect(notification.copyWith(opened: true).unread, isFalse);
    expect(notification.copyWith(dismissed: true).unread, isFalse);
  });

  group('GroupFilters', () {
    test('sends only the filters that are set', () {
      expect(const GroupFilters().toQuery(), isEmpty);
      expect(
        const GroupFilters(
          query: '  robots ',
          category: RsoCategory.technology,
          interestIds: {14, 12},
          verifiedOnly: true,
          sort: GroupSort.newest,
        ).toQuery(),
        {
          'q': 'robots',
          'category': 'technology',
          'interest_id': [12, 14],
          'verified': true,
          'sort': 'newest',
        },
      );
    });

    test('sorting alone is browsing, any filter is searching', () {
      expect(const GroupFilters(sort: GroupSort.name).isSearch, isFalse);
      expect(const GroupFilters(query: 'chess').isSearch, isTrue);
      expect(const GroupFilters(withUpcomingEvents: true).isSearch, isTrue);
      expect(const GroupFilters(category: RsoCategory.sports).isSearch, isTrue);
    });
  });

  test('event times read like the prototype', () {
    final event = CampusEvent(
      id: 1,
      rsoId: 1,
      rsoName: 'Tennis Uniandes',
      title: 'Drop-in',
      startsAt: DateTime(2026, 8, 22, 8),
      endsAt: DateTime(2026, 8, 22, 10),
      color: Colors.red,
      buildingName: 'Centro Deportivo',
      locationDetail: 'Court 2',
    );

    expect(event.date, 'Sat, Aug 22');
    expect(event.time, '8:00 AM');
    expect(event.location, 'Centro Deportivo · Court 2');
  });

  test('inbox ages count back from now', () {
    final now = DateTime(2026, 10, 2, 12);
    expect(
      Dates.ago(now.subtract(const Duration(seconds: 30)), now: now),
      'just now',
    );
    expect(
      Dates.ago(now.subtract(const Duration(minutes: 5)), now: now),
      '5m ago',
    );
    expect(
      Dates.ago(now.subtract(const Duration(hours: 2)), now: now),
      '2h ago',
    );
    expect(
      Dates.ago(now.subtract(const Duration(days: 3)), now: now),
      '3d ago',
    );
    expect(Dates.ago(DateTime(2026, 8, 22), now: now), 'Aug 22');
  });
}
