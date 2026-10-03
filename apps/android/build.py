#!/usr/bin/env python3
"""Builds the Android app: the core's native parts, prebuilt (scripts/native.ts:
the shell, client/shell in Rust, and the engine, core/src/main/cpp: Hermes with
its JSI), and the core itself (client/core-ts) as Hermes bytecode (its hermesc
is React Native's, of the release :core's Hermes is), all put where :core picks
them up (core/build/generated), then Gradle. A native part whose source changed
and is not published yet is built here first (cargo with the NDK; Gradle's CMake).

Needs the SDK in $ANDROID_HOME (default ~/Library/Android/sdk), a JDK 17+, Node 24
and pnpm; to build a native part here also rustup and ndk;28.2.13676358.
STILLFAIL_ENGINE=cmake builds the engine in this Gradle build as before (to work
on engine.cpp with Android Studio).

  apps/android/build.py                   # :app:assembleDebug
  apps/android/build.py --tasks :core:testDebugUnitTest
  apps/android/build.py --release         # an optimized core
  apps/android/build.py --release --beta  # the beta app (fail.still.android.beta, 「youdid.wtf」; app/build.gradle.kts)
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
ABI = "arm64-v8a"
LIBRARY = "libstillfail_shell.so"
ENGINE = ["libjsi.so", "libstillfail_hermes.so", "libc++_shared.so"]
# React Native's release whose Hermes :core runs (gradle/libs.versions.toml `hermes`): its hermesc compiles the core.
HERMES = "0.81.4"


def hermesc(env):
    """React Native's hermesc for this machine, from its npm package (kept in a cache once fetched)."""
    cache = Path(env.get("STILLFAIL_BUILD_CACHE", Path.home() / "Library/Caches/stillfail-build")) / f"hermesc-{HERMES}"
    folder = "osx-bin" if sys.platform == "darwin" else "linux64-bin"
    binary = cache / "package/sdks/hermesc" / folder / "hermesc"
    if not binary.exists():
        cache.mkdir(parents=True, exist_ok=True)
        run(["npm", "pack", f"react-native@{HERMES}", "--silent"], env, cwd=cache)
        run(["tar", "-xzf", f"react-native-{HERMES}.tgz", "package/sdks/hermesc"], env, cwd=cache)
    return binary


def native(part, env):
    """A native part's directory: prebuilt, or built here when its source changed (scripts/native.ts)."""
    return Path(subprocess.check_output(["node", str(ROOT / "scripts/native.ts"), "path", part, "android-arm64"], env=env, text=True).strip())


def run(command, env, cwd=ROOT):
    print("+", " ".join(str(x) for x in command), flush=True)
    subprocess.run(command, cwd=cwd, env=env, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--release", action="store_true", help="(the native parts are the release profile's either way)")
    parser.add_argument("--tasks", nargs="*", default=[":app:assembleDebug"], help="Gradle tasks (none: only the native part)")
    parser.add_argument("--beta", action="store_true", help="build the beta app beside the released one (-PstillfailBeta)")
    args = parser.parse_args()

    env = dict(os.environ)
    sdk = Path(env.get("ANDROID_HOME", Path.home() / "Library/Android/sdk"))
    if not env.get("JAVA_HOME") and Path("/usr/libexec/java_home").exists():
        env["JAVA_HOME"] = subprocess.check_output(["/usr/libexec/java_home"], text=True).strip()
    env["ANDROID_HOME"] = str(sdk)

    # The app's types are what the core declares it sends and takes (client/core-ts/src/shapes/schema.ts, src/ops.ts):
    # a stale Shapes.kt or Operations.kt stops the build.
    run(["node", "client/core-ts/scripts/shapes.ts", "--check"], env, cwd=ROOT)
    run(["node", "client/core-ts/scripts/operations.ts", "--check"], env, cwd=ROOT)
    # And its icons are still.fail's set as drawn (design/icons).
    run(["python3", "scripts/icons.py", "--check"], env, cwd=ROOT)
    # The shell and the engine, prebuilt (the release profile, whichever the app's is).
    cmake = env.get("STILLFAIL_ENGINE") == "cmake"
    shell = native("shell", env)
    engine = None if cmake else native("engine", env)

    generated = APP / "core/build/generated"
    jni = generated / "jniLibs" / ABI
    assets = generated / "assets"
    shutil.rmtree(generated, ignore_errors=True)
    jni.mkdir(parents=True)
    assets.mkdir(parents=True)
    # The prebuilt keeps its symbols; the app's copy is stripped by Gradle (stripDebugSymbols, with the NDK) when packed.
    shutil.copy2(shell / LIBRARY, jni / LIBRARY)
    if engine:
        for name in ENGINE:
            shutil.copy2(engine / name, jni / name)
    # The core: bundled for Hermes and compiled to its bytecode (client/core-ts/scripts/hermes-bundle.ts).
    core = CLIENT / "core-ts"
    run(["pnpm", "install", "--frozen-lockfile", "--silent"], env, cwd=core)
    run(["node", "scripts/hermes-bundle.ts", str(generated / "core.js"), str(assets / "core.hbc")], dict(env, HERMESC=str(hermesc(env))), cwd=core)

    if args.tasks:
        run([str(APP / "gradlew"), "-p", str(APP), *(["-PstillfailBeta"] if args.beta else []), *([] if cmake else ["-PstillfailPrebuiltEngine"]), *args.tasks], env)
        if ":app:assembleDebug" in args.tasks:
            print(APP / "app/build/outputs/apk/debug/app-debug.apk")


if __name__ == "__main__":
    main()
