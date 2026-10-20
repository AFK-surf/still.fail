#!/usr/bin/env python3
"""Create one isolated iPhone simulator with an installed iOS 26+ runtime."""
import json
import os
import re
import subprocess


def create():
    inventory = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "--json"], text=True))
    runtimes = [runtime for runtime in inventory["runtimes"]
                if runtime.get("isAvailable") and re.fullmatch(r"iOS \d+(?:\.\d+)*", runtime["name"])
                and int(runtime["version"].split(".")[0]) >= 26]
    if not runtimes:
        raise SystemExit("Install an iOS 26+ simulator runtime on the runner (Xcode Settings → Components).")
    runtime = max(runtimes, key=lambda item: tuple(map(int, item["version"].split("."))))
    supported = {item["identifier"] for item in runtime.get("supportedDeviceTypes", [])}
    phones = [item for item in inventory["devicetypes"] if item["name"].startswith("iPhone")
              and (not supported or item["identifier"] in supported)]
    if not phones:
        raise SystemExit("The installed iOS runtime has no supported iPhone simulator type.")
    name = f"stillfail-ci-{os.environ.get('GITHUB_RUN_ID', str(os.getpid()))}-{os.environ.get('GITHUB_RUN_ATTEMPT', '1')}"
    return subprocess.check_output(["xcrun", "simctl", "create", name, phones[-1]["identifier"], runtime["identifier"]], text=True).strip()


if __name__ == "__main__":
    print(create())
