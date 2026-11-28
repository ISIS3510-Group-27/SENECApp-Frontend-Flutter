"""Validate paired profile sessions and summarize repeated filtering duration.

Input: ROOT/before/run-*/metrics.json and ROOT/after/run-*/metrics.json.
The report describes synthetic emulator measurements, never physical-device,
screen-load, battery or production-usage measurements.
"""

import argparse
import json
from pathlib import Path
from statistics import median


def summarize(root):
    samples = {}
    expected = None
    for variant in ("before", "after"):
        files = sorted((root / variant).glob("run-*/metrics.json"))
        if len(files) != 3:
            raise ValueError(f"Expected three {variant} sessions, found {len(files)}")
        for path in files:
            data = json.loads(path.read_text())
            if not data.get("completed") or not data.get("profile_mode"):
                raise ValueError(f"Incomplete/non-profile session: {path}")
            if data.get("variant") != variant or data.get("platform") != "android":
                raise ValueError(f"Wrong variant/platform: {path}")
            metrics = data["metrics"]
            signature = (metrics["output_ids"], metrics["checksum"])
            if expected is None:
                expected = signature
            if expected != signature:
                raise ValueError(f"Filtering behavior differs: {path}")
            for row in metrics["measurements"]:
                key = (row["events"], row["scenario"], variant)
                samples.setdefault(key, []).append(row["elapsed_us"] / row["iterations"])
    rows = []
    for count, scenario in sorted({(key[0], key[1]) for key in samples}):
        before = samples[count, scenario, "before"]
        after = samples[count, scenario, "after"]
        if len(before) != 9 or len(after) != 9:
            raise ValueError("Expected three rounds in each of three sessions")
        rows.append({
            "events": count,
            "scenario": scenario,
            "before_median_us": median(before),
            "after_median_us": median(after),
            "reduction_percent": (1 - median(after) / median(before)) * 100,
            "before_range_us": [min(before), max(before)],
            "after_range_us": [min(after), max(after)],
            "observations_per_variant": 9,
        })
    return {"outputs_identical": True, "checksum": expected[1], "rows": rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    report = summarize(args.root)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    lines = [
        "# Event-filter profiling — Jose, Flutter Sprint 4", "",
        "Android ARM emulator, API 30, profile/AOT build, America/Bogota. "
        "Synthetic fixed inputs; three sessions per variant, three rounds per "
        "case, 5,000 calls per round after warm-up. No production backend calls.", "",
        "Values below are median elapsed microseconds per call (nine batch "
        "observations). A negative reduction means a regression. Batch wall-clock "
        "duration includes allocation/GC and emulator/host scheduling effects.", "",
        "| Events | Case | Before µs | After µs | Reduction | Before range µs | After range µs |",
        "|---:|---|---:|---:|---:|---|---|",
    ]
    for row in report["rows"]:
        span = lambda field: "–".join(f"{v:.2f}" for v in row[field])
        lines.append(
            f'| {row["events"]} | {row["scenario"]} | '
            f'{row["before_median_us"]:.2f} | {row["after_median_us"]:.2f} | '
            f'{row["reduction_percent"]:.2f}% | {span("before_range_us")} | {span("after_range_us")} |'
        )
    lines.extend(["", "All six sessions produced identical ordered output IDs and checksums.", "",
        "The change hoists date bounds outside the event loop and copies the "
        "unfiltered list directly. It does not introduce the existing normalized "
        "search cache or change rendering. Raw VM timelines retain named filtering spans.", "",
        "These are not physical-phone, screen-load, frame-time, CPU-utilization, "
        "memory, battery or carbon results. Repeat on physical hardware for the course requirement.", ""])
    (args.output / "RESULTS.md").write_text("\n".join(lines))


if __name__ == "__main__":
    main()
