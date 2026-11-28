# Jose — Sprint 4 verification guide

## Scope and attribution

The Flutter comparison mirrors Daniel Vergara's Kotlin view. Open **Profile →
Compare recommended groups**, select two different organizations, compare their
information and reasons, then open a detail using the existing join flow.
The backend, its BQ6 query and the shared analytics pipeline were not changed.

Implementation blocks:

- `5b4a063`: recommendation loading and comparison state.
- `1ab0d3f`: comparison screen and Profile navigation.
- `20ac47f`: per-account persistent snapshot and offline behavior.
- Working-tree changes: profiling harness, date-filter optimization, controlled
  Android session and verification material. Review before committing.

## Code to inspect

| Concern | File | Behavior |
|---|---|---|
| Presentation | `lib/features/compare_groups/compare_groups_screen.dart` | Existing theme/components, two distinct pickers, responsive comparison, saved-data notice and retry |
| State and concurrency | `lib/features/compare_groups/compare_groups_view_model.dart` | `load()` shares an in-flight Future, `_fetch()` starts disk reading alongside the request; stale session/disposed results cannot update the screen |
| Persistent snapshot | `lib/data/local/recommendation_snapshot_store.dart` | Schema v1, at most 10 recommendations and 128 KiB, valid for less than 24 hours, no persisted attribution request ID |
| Shared local storage | `lib/data/local/sqlite_local_store.dart` | Existing SQLite database per account; snapshot uses its document storage; sign-out wipes that account's database |
| Connectivity | Comparison screen and view model | Subscribe to reconnect, cancel subscription on disposal, refresh and enable actions only with fresh server information |
| Attribution | `lib/features/rso_detail/rso_detail_screen.dart` and existing repositories | Opening a live compared group carries `EntryPoint.recommendation` and the current response's request ID into the existing detail/join flow |
| Optimization | `lib/features/events/event_filters.dart` | Hoist date bounds out of the event loop; copy directly for an unfiltered list; preserve filtering and ordering contracts |

`async`/`await` avoids waiting synchronously for I/O; it does not make CPU work
parallel. The comparison adds no isolate or coroutine. The project's existing
background JSON processing and image caching are shared infrastructure, not new
work claimed by this contribution. Similarly, the existing normalized-search
`Expando` cache belongs to the earlier optimization and is not this change.

## Eventual connectivity scenarios

1. **Online:** load live recommendations and save a reduced snapshot. Opening a
   group uses the current request ID.
2. **Offline after a successful load:** close/reopen comparison. Restore an
   unexpired snapshot, show its age and allow both selections. Details requiring
   the server stay disabled. No request ID is reconstructed from saved data.
3. **Reconnect:** refresh from the server. Keep selections still present in the
   new results. Enable detail actions only after a successful live response.
4. **No usable copy:** show an actionable error/Retry, rather than invented data.
5. **Authentication/authorization errors:** do not conceal 401/403 with cached
   results. Cache fallback applies to unreachable/server-failure cases.
6. **Account changes:** disregard pending results from the previous session;
   account databases prevent one student's copy appearing for another student.

The 24-hour rule controls validity, not immediate physical erasure. This storage
is not presented as encrypted. Offline comparisons do not enqueue joins.

## Controlled Android session

**Observed on November 27, 2026:** all stages passed in profile mode on the
temporary Android ARM emulator (API 30). Native SQLite restored the saved copy,
offline detail buttons were disabled, reconnection enabled them after live
refresh, and fixture detail/join requests carried recommendation attribution.
See [machine-readable verification](evidence/verification.json) and actual
screens: [online](evidence/online.png), [offline](evidence/offline.png),
[reconnected](evidence/reconnected.png). Full Flutter suite: **338 tests passed**;
final static analysis: **no issues**.

`integration_test/compare_groups_session_test.dart` runs the actual Flutter UI,
connectivity plugin and native SQLite with an in-memory `FakeBackend`. It does
not sign into Firebase or change real memberships. Its host runner disables and
restores **only the specified emulator's** network and captures actual screens:

```sh
python3 scripts/performance/run_comparison_session.py \
  --adb "$ANDROID_HOME/platform-tools/adb" \
  --device emulator-5560 --output artifacts/sprint4/comparison
```

The runner verifies online → offline restore → reconnection, disabled/enabled
detail actions and recommendation attribution in captured fixture requests.
This demonstrates behavior, not successful delivery to production analytics.

## Profiling reproduction

Run `integration_test/event_filters_perf_test.dart` using
`test_driver/event_filters_driver.dart` in **profile mode**. Set
`--dart-define=PERF_VARIANT=before` or `after`. Keep the device, workload, build
mode and harness identical. Save each run before the next overwrites the files
in `build/perf/jose/`. Workload inputs are synthetic, fixed at 50 and 160 events,
with 5,000 iterations and three rounds per case. Compare output IDs and checksum
before interpreting timings. Raw VM timelines contain labeled filtering spans.

These timings measure elapsed duration for repeated CPU-bound filtering. They
are not whole-screen load times, rendering frame times, process CPU utilization,
battery use or carbon measurements. Emulator measurements need repetition on a
physical Android to satisfy the course's device requirement.

The measured report and exact implementation hashes are in
[profiling evidence](../../performance/sprint4/jose/RESULTS.md). With 160
events, weekly filtering fell from 104.78 to 62.33 microseconds per call (median
of nine batch observations). Ordered outputs/checksums matched in all six runs.

## Production BQ6 check still needed

Question: **Which entry point produces more joins: personalized recommendations,
or search and filters?** The existing backend groups views/confirmed joins by
entry point and exposes aggregate conversion results. This contribution adds a
new frontend route feeding that existing pipeline; it does not implement a new
backend calculation. A join/view ratio is descriptive, not causal evidence.

With an authorized verified test account and dashboard access, select a fixed
date range, record the initial counts, open/join a dedicated group from live
comparison, and verify recommendation attribution in backend/dashboard data.
Repeat through search with a separate controlled case. Obtain permission before
changing memberships and remove test data through the supported process.

Public checks only prove the AWS health endpoint responds and BQ6 rejects an
unauthenticated request. No test account was available during this work.

## Delivery checklist

- Repeat comparison and profiling on a physical phone.
- Complete the authenticated BQ6/dashboard check above.
- Build the **real `lib/main.dart` target**, not an integration-test APK, using
  the team's API URL and Firebase mode. Do not commit another person's local
  Java/SDK paths, generated directories or diagnostic font fixtures.
- Review APK signing, package identifier and Firebase project before uploading
  to the team's App Distribution. An internal debug-signed artifact is not a
  production release signature. Actual invitations require authorized access.
- Record the visible personal ethics reflection and add the final team video
  link. `ETHICS_NOTES.md` contains preparation prompts, not a recorded deliverable.
- Keep raw traces/APKs in the ignored artifact folders; commit source, tests and
  concise documentation after review. No source commit is made automatically.
