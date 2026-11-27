import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null || data['completed'] != true) {
      throw StateError('The comparison session did not complete.');
    }
    final output = Directory('build/perf/jose/comparison')
      ..createSync(recursive: true);
    File(
      '${output.path}/verification.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  },
);
