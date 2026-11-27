// Sprint 4 micro-optimization profiling: the same scripted session is run on
// the code before and after the optimizations, with the Flutter timeline
// recorded. Run against the local backend (dev sign-in, seeded data):
//
//   flutter drive --profile --no-dds \
//     --driver=test_driver/perf_driver.dart \
//     --target=integration_test/perf_test.dart
//
// Results: build/perf/*.timeline_summary.json (frame build and raster times
// from the timeline) and build/perf/memory.json (image cache use).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:senecapp/main.dart' as app;

/// Lets the live app run for [seconds] of real time. (pumpAndSettle never
/// settles here: spinners and the light sensor keep scheduling frames.)
Future<void> _settle(WidgetTester tester, [int seconds = 3]) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
  }
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 150 && finder.evaluate().isEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
  }
  expect(finder, findsWidgets);
}

/// The screen's vertical list (not the search field's or a carousel's
/// horizontal scrollable).
final _list = find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);

Map<String, Object> _imageCache() {
  final cache = PaintingBinding.instance.imageCache;
  return {
    'bytes': cache.currentSizeBytes,
    'images': cache.currentSize,
    'live_images': cache.liveImageCount,
  };
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('profiled session', (tester) async {
    // The app's main() routes framework errors to analytics; keep the test's
    // handler so a failing step fails the run instead of passing silently.
    final testOnError = FlutterError.onError;
    await app.main();
    FlutterError.onError = testOnError;
    await _settle(tester, 5);
    debugPrint('PERF started');

    // Dev sign-in with the backend's seeded demo student (no password).
    final demo = find.text('Use demo student');
    if (demo.evaluate().isNotEmpty) {
      await tester.tap(demo);
      await _settle(tester);
    }
    await _waitFor(tester, _list);
    await _settle(tester);
    debugPrint('PERF signed in');

    // 1. Discover: scroll the whole organizations list and back. Every cover
    //    photo is decoded into the image cache on the way.
    PaintingBinding.instance.imageCache.clear();
    final discover = _list.first;
    await binding.traceAction(() async {
      for (var i = 0; i < 12; i++) {
        await tester.fling(discover, const Offset(0, -500), 1500);
        await _settle(tester, 1);
      }
      for (var i = 0; i < 12; i++) {
        await tester.fling(discover, const Offset(0, 500), 1500);
        await _settle(tester, 1);
      }
    }, reportKey: 'discover_scroll');
    final memory = {'after_discover_scroll': _imageCache()};
    debugPrint('PERF discover done $memory');

    // 2. Events: save and unsave one event a few times. Each tap changes
    //    AppState; how much of the screen rebuilds is what's measured.
    await tester.tap(find.text('Events').last);
    await _settle(tester);
    await _waitFor(tester, find.byTooltip('Save event'));
    await binding.traceAction(() async {
      for (var i = 0; i < 10; i++) {
        final save = find.byTooltip(i.isEven ? 'Save event' : 'Unsave event');
        await tester.tap(save.first);
        await _settle(tester, 1);
      }
    }, reportKey: 'events_save_toggle');
    debugPrint('PERF save toggle done');

    // 2b. The same taps with build tracing on: one timeline event per widget
    //     built (what DevTools' "Track widget builds" shows), to count how
    //     many widgets one save rebuilds. Separate from 2 so the tracing
    //     overhead doesn't distort its frame times.
    debugProfileBuildsEnabled = true;
    await binding.traceAction(() async {
      for (var i = 0; i < 4; i++) {
        final save = find.byTooltip(i.isEven ? 'Save event' : 'Unsave event');
        await tester.tap(save.first);
        await _settle(tester, 1);
      }
    }, reportKey: 'events_save_builds');
    debugProfileBuildsEnabled = false;

    // 3. Events: scroll the list (cards rebuilt as they come into view).
    final events = _list.first;
    await binding.traceAction(() async {
      for (var i = 0; i < 8; i++) {
        await tester.fling(events, const Offset(0, -600), 2000);
        await _settle(tester, 1);
      }
    }, reportKey: 'events_scroll');
    memory['after_events'] = _imageCache();

    binding.reportData = {
      ...?binding.reportData,
      'memory': memory,
      'completed': true,
    };
  });
}
