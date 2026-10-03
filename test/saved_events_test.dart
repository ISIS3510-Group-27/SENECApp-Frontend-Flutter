import 'package:flutter_test/flutter_test.dart';
import 'package:senecapp/app_services.dart';
import 'package:senecapp/data/models/student_profile.dart';
import 'package:senecapp/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  const student = StudentProfile(
    id: 1,
    name: 'Sofía Arango',
    email: 's.arango@uniandes.edu.co',
    interests: ['AI/ML'],
  );

  AppState state(AppServices services) => AppState(
    student: student,
    me: services.me,
    groups: services.groups,
    events: services.events,
    notifications: services.notifications,
    preferences: services.preferences,
  );

  test('saved events are stored per student', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final services = testServices(preferences: prefs);

    final appState = state(services);
    await appState.restoreSavedEvents();
    await appState.toggleEventSaved(42);

    expect(appState.isEventSaved(42), isTrue);
    expect(prefs.getStringList('saved_events.student.1'), ['42']);

    final restored = state(services);
    await restored.restoreSavedEvents();

    expect(restored.isEventSaved(42), isTrue);
  });
}
