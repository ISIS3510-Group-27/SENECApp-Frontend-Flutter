import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

/// Writes each traced action's timeline summary (frame build and raster
/// times) and the image-cache numbers to build/perf/.
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null || data['completed'] != true) {
      throw StateError('The profiled session did not finish: no results.');
    }
    final out = Directory('build/perf')..createSync(recursive: true);
    for (final MapEntry(:key, :value) in data.entries) {
      if (key == 'completed') continue;
      if (key == 'memory') {
        File(
          '${out.path}/memory.json',
        ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(value));
        continue;
      }
      final timeline = driver.Timeline.fromJson(value as Map<String, dynamic>);
      final summary = driver.TimelineSummary.summarize(timeline);
      await summary.writeTimelineToFile(
        key,
        destinationDirectory: out.path,
        pretty: true,
        includeSummary: true,
      );
    }
  },
);
