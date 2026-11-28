import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:senecapp/data/local/insight_store.dart';

void main() {
  test('concurrent insight writes preserve a readable cache', () async {
    final dir = await Directory.systemTemp.createTemp('senecapp-review-');
    final store = FileInsightStore(directory: () async => dir);
    try {
      final errors = <Object>[];
      await Future.wait(
        List.generate(10, (i) async {
          try {
            await store.write('a', 'profile:1', {'value': i}, DateTime.now());
          } catch (e) {
            errors.add(e);
          }
        }),
      );
      final saved = await store.read('a', 'profile:1');
      expect(
        errors,
        isEmpty,
        reason: 'Concurrent refreshes must not collide on the temporary file',
      );
      expect(saved, isNotNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
