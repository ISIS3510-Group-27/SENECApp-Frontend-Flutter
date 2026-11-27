import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null ||
        data['completed'] != true ||
        data['profile_mode'] != true) {
      throw StateError('The profile session did not complete in profile mode.');
    }
    final variant = '${data['variant']}';
    if (variant != 'before' && variant != 'after') {
      throw StateError('PERF_VARIANT must be before or after.');
    }
    final output = Directory('build/perf/jose/$variant')
      ..createSync(recursive: true);
    final encode = const JsonEncoder.withIndent('  ');
    File('${output.path}/metrics.json').writeAsStringSync(
      encode.convert({
        for (final entry in data.entries)
          if (entry.key != 'event_filters_timeline') entry.key: entry.value,
      }),
    );
    File(
      '${output.path}/timeline.json',
    ).writeAsStringSync(encode.convert(data['event_filters_timeline']));
  },
);
