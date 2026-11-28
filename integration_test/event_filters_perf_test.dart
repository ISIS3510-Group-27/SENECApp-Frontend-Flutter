import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/event_filter_workload.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('event filtering CPU profile', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('SENECApp filter profiling'))),
      ),
    );
    await tester.pumpAndSettle();
    late Map<String, Object> metrics;
    await binding.traceAction(() async {
      metrics = runEventFilterWorkload();
    }, reportKey: 'event_filters_timeline');
    binding.reportData = {
      ...?binding.reportData,
      'metrics': metrics,
      'variant': const String.fromEnvironment(
        'PERF_VARIANT',
        defaultValue: 'unspecified',
      ),
      'profile_mode': kProfileMode,
      'platform': defaultTargetPlatform.name,
      'completed': true,
    };
  });
}
