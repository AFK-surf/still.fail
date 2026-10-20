#!/usr/bin/env python3
"""Verify real WidgetKit reads while the main app is terminated, in a disposable simulator."""
import argparse
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

from simulator import create

ROOT = Path(__file__).resolve().parents[3]
APP = "fail.still.iphone.e2e"
GROUP = "group.fail.still.iphone"


def run(args, *, env=None, output=None):
    return subprocess.run(args, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT if output else None,
                          text=True, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mesh-native", default=os.environ.get("STILLFAIL_MESH_NATIVE"), required=not os.environ.get("STILLFAIL_MESH_NATIVE"))
    options = parser.parse_args()
    if not Path(options.mesh_native).is_file():
        raise SystemExit("--mesh-native must name a built local mesh addon")
    result = ROOT / ".airbuild" / "widget-e2e-results" / time.strftime("%Y%m%d-%H%M%S")
    result.mkdir(parents=True)
    env = {**os.environ, "STILLFAIL_MESH_NATIVE": str(Path(options.mesh_native).resolve())}
    device = create()
    fixture = None
    try:
        run(["xcrun", "simctl", "boot", device])
        run(["xcrun", "simctl", "bootstatus", device, "-b"])
        with tempfile.TemporaryDirectory(prefix="stillfail-widget-fixture-") as temporary:
            config = Path(temporary) / "fixture.json"
            fixture = subprocess.Popen(["node", "apps/ios/scripts/widget-fixture.ts", str(config)], cwd=ROOT, env=env,
                                       stdout=subprocess.PIPE, stderr=(result / "fixture.log").open("w"), text=True)
            if not select.select([fixture.stdout], [], [], 20)[0]:
                raise RuntimeError("The isolated fixture did not start")
            ready = json.loads(fixture.stdout.readline())
            origin = ready["origin"]
            derived = ROOT / ".airbuild" / "widget-e2e"
            common = ["xcodebuild", "-project", "apps/ios/StillFail.xcodeproj", "-scheme", "WidgetExtensionE2E",
                      "-destination", f"platform=iOS Simulator,id={device}", "-derivedDataPath", str(derived),
                      "-clonedSourcePackagesDirPath", str(ROOT / ".airbuild" / "spm"), "-disableAutomaticPackageResolution"]
            with (result / "build.log").open("w") as log:
                run(common + ["SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG WIDGET_E2E", "WIDGET_E2E_SUFFIX=.e2e",
                              f"WIDGET_FIXTURE_ORIGIN={origin}", "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_ALLOWED=YES", "build-for-testing"], env=env, output=log)
            app = derived / "Build/Products/Debug-iphonesimulator/StillFail.app"
            run(["xcrun", "simctl", "install", device, str(app)])
            group = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", device, APP, GROUP], text=True).strip())
            shutil.copyfile(config, group / "widget-e2e.json")
            run(["xcrun", "simctl", "launch", device, APP, "--seed-widget-fixture"])
            for _ in range(100):
                if (group / "widget-e2e-seeded").is_file():
                    break
                time.sleep(.2)
            else:
                raise RuntimeError("Main app did not write its synthetic session through the shared Keychain")
            run(["xcrun", "simctl", "terminate", device, APP])
            with (result / "test.log").open("w") as log:
                run(common + ["-parallel-testing-enabled", "NO", "-resultBundlePath", str(result / "killed-main.xcresult"), "test-without-building"], env=env, output=log)
            record = json.loads((group / "widget-e2e-result.json").read_text())
            with urllib.request.urlopen(origin + "/test/state") as response:
                state = json.load(response)
            if record["tasks"] != 7 or state["reads"] < 4 or state["refreshes"] < 1:
                raise RuntimeError(f"Widget did not read current node data: {record}, {state}")
            (result / "evidence.json").write_text(json.dumps({"extension": record, "fixture": state, "main_app": "notRunning (asserted by XCTest)"}, indent=2))
            print(f"PASS: WidgetKit updated 2 -> 7 with the main app terminated. Evidence: {result}")
    finally:
        if fixture is not None:
            fixture.terminate()
            try:
                fixture.wait(timeout=5)
            except subprocess.TimeoutExpired:
                fixture.kill()
                fixture.wait()
        subprocess.run(["xcrun", "simctl", "shutdown", device], capture_output=True)
        subprocess.run(["xcrun", "simctl", "delete", device], capture_output=True)


if __name__ == "__main__":
    main()
