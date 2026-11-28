# Event-filter profiling — Jose, Flutter Sprint 4

Android ARM emulator, API 30, profile/AOT build, America/Bogota. Synthetic fixed inputs; three sessions per variant, three rounds per case, 5,000 calls per round after warm-up. No production backend calls.

Values below are median elapsed microseconds per call (nine batch observations). A negative reduction means a regression. Batch wall-clock duration includes allocation/GC and emulator/host scheduling effects.

| Events | Case | Before µs | After µs | Reduction | Before range µs | After range µs |
|---:|---|---:|---:|---:|---|---|
| 50 | all | 11.98 | 0.38 | 96.85% | 11.62–13.74 | 0.24–0.68 |
| 50 | search | 29.34 | 18.48 | 37.03% | 29.04–30.28 | 18.20–19.15 |
| 50 | search_week | 19.58 | 5.25 | 73.20% | 19.44–21.58 | 5.19–5.43 |
| 50 | today | 15.01 | 1.77 | 88.24% | 14.72–15.68 | 1.52–2.46 |
| 50 | week | 29.56 | 15.41 | 47.89% | 28.74–30.49 | 15.15–16.18 |
| 160 | all | 36.42 | 0.40 | 98.90% | 35.98–38.42 | 0.37–0.52 |
| 160 | search | 105.17 | 66.29 | 36.97% | 103.50–105.62 | 65.21–68.10 |
| 160 | search_week | 66.70 | 20.95 | 68.59% | 65.64–66.97 | 20.55–21.59 |
| 160 | today | 48.43 | 5.32 | 89.01% | 47.37–51.74 | 5.21–5.45 |
| 160 | week | 104.78 | 62.33 | 40.51% | 103.06–105.90 | 61.54–65.17 |

All six sessions produced identical ordered output IDs and checksums.

The change hoists date bounds outside the event loop and copies the unfiltered list directly. It does not introduce the existing normalized search cache or change rendering. Raw VM timelines retain named filtering spans.

These are not physical-phone, screen-load, frame-time, CPU-utilization, memory, battery or carbon results. Repeat on physical hardware for the course requirement.
