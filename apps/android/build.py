#!/usr/bin/env python3
"""Builds the Android app: the Rust core (client/ffi) for aarch64-linux-android
with the NDK, its Kotlin bindings (uniffi-bindgen, from the built library),
both put where :core picks them up (core/build/generated), then Gradle.

Needs rustup's aarch64-linux-android target, the SDK in $ANDROID_HOME
(default ~/Library/Android/sdk) with ndk;28.2.13676358, and a JDK 17+.
CARGO_TARGET_DIR is honoured; the Android build goes under it like any other.

  apps/android/build.py                   # :app:assembleDebug
  apps/android/build.py --tasks :core:testDebugUnitTest
  apps/android/build.py --release         # an optimized core
"""
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

APP = Path(__file__).resolve().parent
ROOT = APP.parents[1]
CLIENT = ROOT / "client"
TARGET = "aarch64-linux-android"
ABI = "arm64-v8a"
API = 29
NDK_VERSION = "28.2.13676358"
LIBRARY = "libember_core_ffi.so"


def run(command, env, cwd=ROOT):
    print("+", " ".join(str(x) for x in command), flush=True)
    subprocess.run(command, cwd=cwd, env=env, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--release", action="store_true", help="build the core with the release profile")
    parser.add_argument("--tasks", nargs="*", default=[":app:assembleDebug"], help="Gradle tasks (none: only the native part)")
    args = parser.parse_args()

    env = dict(os.environ)
    # rustup's toolchain (with the Android target), ahead of any Homebrew rust.
    env["PATH"] = str(Path.home() / ".cargo/bin") + os.pathsep + env["PATH"]
    sdk = Path(env.get("ANDROID_HOME", Path.home() / "Library/Android/sdk"))
    ndk = sdk / "ndk" / NDK_VERSION
    host = "darwin-x86_64" if sys.platform == "darwin" else "linux-x86_64"
    llvm = ndk / "toolchains/llvm/prebuilt" / host / "bin"
    clang = llvm / f"{TARGET}{API}-clang"
    if not clang.exists():
        raise SystemExit(f"Missing NDK: install ndk;{NDK_VERSION} in {sdk}")
    if not env.get("JAVA_HOME") and Path("/usr/libexec/java_home").exists():
        env["JAVA_HOME"] = subprocess.check_output(["/usr/libexec/java_home"], text=True).strip()
    key = TARGET.upper().replace("-", "_")
    env.update({
        "ANDROID_HOME": str(sdk),
        "ANDROID_NDK_HOME": str(ndk),
        f"CC_{TARGET.replace('-', '_')}": str(clang),
        f"AR_{TARGET.replace('-', '_')}": str(llvm / "llvm-ar"),
        f"CARGO_TARGET_{key}_LINKER": str(clang),
        # Android 15+ devices may use 16 KiB pages.
        f"CARGO_TARGET_{key}_RUSTFLAGS": "-C link-arg=-Wl,-z,max-page-size=16384",
    })
    installed = subprocess.check_output(["rustup", "target", "list", "--installed"], env=env, text=True).split()
    if TARGET not in installed:
        run(["rustup", "target", "add", TARGET], env)

    profile = "release" if args.release else "debug"
    target_dir = Path(env.get("CARGO_TARGET_DIR", CLIENT / "target"))
    # The app's shapes are what the core declares it sends (client/shapes): a stale Shapes.kt stops the build.
    run(["sh", "scripts/shapes.sh", "--check"], env, cwd=ROOT)
    run(["cargo", "build", "-p", "ember-core-ffi", "--lib", "--target", TARGET, *(["--release"] if args.release else [])], env, cwd=CLIENT)
    built = target_dir / TARGET / profile / LIBRARY

    generated = APP / "core/build/generated"
    jni = generated / "jniLibs" / ABI
    bindings = generated / "uniffi"
    shutil.rmtree(generated, ignore_errors=True)
    jni.mkdir(parents=True)
    # Only the packaged copy is stripped; the build keeps its symbols.
    shutil.copy2(built, jni / LIBRARY)
    run([str(llvm / "llvm-strip"), "--strip-unneeded", str(jni / LIBRARY)], env)
    # The bindings come from the library's own metadata, so they always match it.
    run(["cargo", "run", "-q", "-p", "ember-core-ffi", "--features", "bindgen", "--bin", "uniffi-bindgen", "--",
         "generate", "--library", str(built), "--language", "kotlin", "--no-format", "--out-dir", str(bindings)], env, cwd=CLIENT)

    if args.tasks:
        run([str(APP / "gradlew"), "-p", str(APP), *args.tasks], env)
        if ":app:assembleDebug" in args.tasks:
            print(APP / "app/build/outputs/apk/debug/app-debug.apk")


if __name__ == "__main__":
    main()
