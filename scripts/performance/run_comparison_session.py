"""Run the controlled Android session and capture real emulator screenshots.

The target uses the app's UI and native SQLite, with an in-memory backend.
No Firebase account or production write is involved. Android SDK installation
is deliberately outside this script; pass the SDK's adb and emulator serial.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--flutter", default="flutter")
    args = parser.parse_args()
    if not args.device.startswith("emulator-"):
        parser.error("This script toggles connectivity only on an emulator.")
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)

    def adb(*command):
        return subprocess.run(
            [args.adb, "-s", args.device, *command],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        ).stdout

    def network(enabled):
        action = "enable" if enabled else "disable"
        adb("shell", "svc", "wifi", action)
        adb("shell", "svc", "data", action)

    def capture(name):
        time.sleep(0.5)
        (output / f"{name}.png").write_bytes(adb("exec-out", "screencap", "-p"))

    completed = set()
    command = [
        args.flutter, "drive", "--profile", "--no-pub", "--no-dds",
        "-d", args.device,
        "--driver=test_driver/compare_groups_driver.dart",
        "--target=integration_test/compare_groups_session_test.dart",
    ]
    process = None
    try:
        network(True)
        process = subprocess.Popen(
            command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1,
        )
        with (output / "session.log").open("w") as log:
            for line in process.stdout:
                safe = re.sub(r"(?:ws|http)://(?:127\.0\.0\.1|localhost):\d+/\S+", "[local VM service]", line)
                log.write(safe)
                log.flush()
                print(safe, end="", flush=True)
                if "SPRINT4_ONLINE_READY" in line and "online" not in completed:
                    capture("online")
                    completed.add("online")
                    network(False)
                elif "SPRINT4_OFFLINE_READY" in line and "offline" not in completed:
                    capture("offline")
                    completed.add("offline")
                    network(True)
                elif "SPRINT4_RECONNECTED_READY" in line and "reconnected" not in completed:
                    capture("reconnected")
                    completed.add("reconnected")
        result = process.wait()
        if result != 0 or completed != {"online", "offline", "reconnected"}:
            raise RuntimeError(f"Session failed: exit={result}, stages={sorted(completed)}")
        verification = Path("build/perf/jose/comparison/verification.json")
        data = json.loads(verification.read_text())
        data["device_kind"] = "Android emulator; not a physical device"
        (output / "verification.json").write_text(json.dumps(data, indent=2) + "\n")
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            process.wait(timeout=15)
        network(True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
