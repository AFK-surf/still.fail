#!/usr/bin/env python3
"""Regression test for payload ownership; no Xcode, credentials, or Simulator needed."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

installer = Path(__file__).with_name("install-prebuilt.sh").resolve()
with tempfile.TemporaryDirectory(prefix="mbui-payload-test-") as tmp:
    root = Path(tmp)
    for kind, payload, bundle, executable in [
        ("app", "App", "mbui.app", "mbui"),
        ("share", "Share", "Share.appex", "Share"),
    ]:
        source = root / "staged" / payload
        destination = root / "products" / bundle
        derived = root / "derived" / kind
        source.mkdir(parents=True)
        destination.mkdir(parents=True)
        derived.mkdir(parents=True)
        (source / executable).write_text("fixture executable")
        if kind == "app":
            (source / "core.hbc").write_text("fixture bytecode")
        old = source / "resources" / "old.txt"
        old.parent.mkdir()
        old.write_text("obsolete")
        protected = ["Info.plist", "PkgInfo", "embedded.mobileprovision", "XcodeOwned",
                     "Frameworks/hermes.framework/hermes", "PlugIns/Share.appex/Share",
                     "_CodeSignature/CodeResources"]
        for name in protected:
            path = destination / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("protected")
        env = dict(os.environ, SRCROOT=str(root), TARGET_BUILD_DIR=str(root / "products"),
                   WRAPPER_NAME=bundle, EXECUTABLE_NAME=executable, DERIVED_FILE_DIR=str(derived))
        subprocess.run(["/bin/bash", str(installer), kind], env=env, check=True)
        old.unlink()
        (source / "new.txt").write_text("added")
        subprocess.run(["/bin/bash", str(installer), kind], env=env, check=True)
        assert not (destination / "resources" / "old.txt").exists()
        assert (destination / "new.txt").read_text() == "added"
        for name in protected:
            assert (destination / name).read_text() == "protected", name
        assert not list(destination.glob("*payload*.json"))
        inventory = json.loads((derived / f"mbui-payload-{kind}.json").read_text())
        assert "new.txt" in inventory["files"]
        assert "Info.plist" not in inventory["files"]
        print(f"PASS {kind}: deletion propagated; Xcode-owned and unknown outputs preserved")
