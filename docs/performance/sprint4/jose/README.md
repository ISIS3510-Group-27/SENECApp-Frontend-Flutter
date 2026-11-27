# Flutter event-filter evidence — Sprint 4

See [RESULTS.md](RESULTS.md) for measured medians and ranges. `summary.json`
is machine-readable. Each `before/run-N/metrics.json` and `after/run-N/metrics.json`
contains the ordered output IDs and elapsed batches from an actual Android
profile-mode session. All six sessions produced checksum 9795000 and identical
ordered IDs. Each case has nine observations per variant (three rounds per run).

## Provenance

`manifest.json` identifies the base revision and SHA-256 hashes of both exact
filter implementations. Their archived contents are in `before/event_filters.dart.txt`
and `after/event_filters.dart.txt`; `optimization.patch.gz` shows the production
change. `device.json` records the temporary Android ARM emulator configuration.
Diagnostic-only bundled fonts were present in both profiling builds; the
benchmark renders only a basic label and exercises filtering directly.

This is a filter workload, not Events-screen scrolling or whole-app profiling.
The list, search cache and image decode optimizations already in the base
revision belong to previous teammate work and are not measured as new changes.

## Repeat

Use the same Flutter/Dart version (Flutter 3.47.4), Java 17 and device settings.
Build the same harness with either archived filter version, then run:

```sh
flutter drive --profile --no-pub --no-dds -d <android-device> \
  --driver=test_driver/event_filters_driver.dart \
  --target=integration_test/event_filters_perf_test.dart \
  --dart-define=PERF_VARIANT=before
```

Repeat three times, copying `build/perf/jose/before` after each run to
`<evidence>/before/run-1` through `run-3`. Repeat with `PERF_VARIANT=after` and the
optimized implementation. Do not change fixtures or harness between variants.
Then run:

```sh
python3 scripts/performance/summarize_event_filters.py <evidence> \
  --output <evidence>/summary
```

The script refuses incomplete sessions, differing ordered outputs/checksums,
wrong build mode/platform or missing rounds. Keep the device otherwise idle.
Rebuild both versions and repeat on a physical phone for the course requirement.

## Raw profiler data

Gzipped VM timelines and sanitized session logs were exported to the ignored
`artifacts/sprint4/profiling/{before,after}/run-N` folders. Decompress a timeline
to inspect its `traceEvents`; filtering spans are labeled
`event_filters.<count>.<scenario>`, with event count, iterations and round in
arguments. These are real VM captures, not fabricated profiler screenshots. The VM timeline
buffer is bounded: some earliest spans were evicted in the longer BEFORE traces.
All thirty timing batches per session were separately saved in `metrics.json`.
The benchmark harness is also copied into that artifact directory for recovery.

`backend-access.json` records separate public AWS checks: database health 200,
unauthenticated BQ6 401. Those checks do not prove authenticated analytics
collection. No test account was available.
