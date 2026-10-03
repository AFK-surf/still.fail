#!/usr/bin/env python3
"""Builds the Android app: the core's native shell (client/shell, Rust) for
aarch64-linux-android with the NDK, and the core itself (client/core-ts) as
Hermes bytecode (its hermesc is React Native's, of the release :core's Hermes
is), both put where :core picks them up (core/build/generated), then Gradle,
which builds the engine (core/src/main/cpp) against Hermes.

Needs rustup's aarch64-linux-android target, the SDK in $ANDROID_HOME
(default ~/Library/Android/sdk) with ndk;28.2.13676358, a JDK 17+, Node 24 and
pnpm. CARGO_TARGET_DIR is honoured; the Android build goes under it like any other.

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
TARGET = "aarch64-linux-android"
ABI = "arm64-v8a"
API = 29
NDK_VERSION = "28.2.13676358"
LIBRARY = "libstillfail_shell.so"
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


def run(command, env, cwd=ROOT):
    print("+", " ".join(str(x) for x in command), flush=True)
    subprocess.run(command, cwd=cwd, env=env, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--release", action="store_true", help="build the core with the release profile")
    parser.add_argument("--tasks", nargs="*", default=[":app:assembleDebug"], help="Gradle tasks (none: only the native part)")
    parser.add_argument("--beta", action="store_true", help="build the beta app beside the released one (-PstillfailBeta)")
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
    # The app's types are what the core declares it sends and takes (client/core-ts/src/shapes/schema.ts, src/ops.ts):
    # a stale Shapes.kt or Operations.kt stops the build.
    run(["node", "client/core-ts/scripts/shapes.ts", "--check"], env, cwd=ROOT)
    run(["node", "client/core-ts/scripts/operations.ts", "--check"], env, cwd=ROOT)
    # And its icons are still.fail's set as drawn (design/icons).
    run(["python3", "scripts/icons.py", "--check"], env, cwd=ROOT)
    # Named by its file (SONAME): the engine that links it is then given its name, not where it was built.
    run(["cargo", "rustc", "-p", "stillfail-shell", "--lib", "--crate-type", "cdylib", "--target", TARGET, *(["--release"] if args.release else []),
         "--", "-C", f"link-arg=-Wl,-soname,{LIBRARY}"], env, cwd=CLIENT)
    built = target_dir / TARGET / profile / LIBRARY

    generated = APP / "core/build/generated"
    jni = generated / "jniLibs" / ABI
    assets = generated / "assets"
    shutil.rmtree(generated, ignore_errors=True)
    jni.mkdir(parents=True)
    assets.mkdir(parents=True)
    # Only the packaged copy is stripped; the build keeps its symbols.
    shutil.copy2(built, jni / LIBRARY)
    run([str(llvm / "llvm-strip"), "--strip-unneeded", str(jni / LIBRARY)], env)
    # The core: bundled for Hermes and compiled to its bytecode (client/core-ts/scripts/hermes-bundle.ts).
    core = CLIENT / "core-ts"
    run(["pnpm", "install", "--frozen-lockfile", "--silent"], env, cwd=core)
    run(["node", "scripts/hermes-bundle.ts", str(generated / "core.js"), str(assets / "core.hbc")], dict(env, HERMESC=str(hermesc(env))), cwd=core)

    if args.tasks:
        run([str(APP / "gradlew"), "-p", str(APP), *(["-PstillfailBeta"] if args.beta else []), *args.tasks], env)
        if ":app:assembleDebug" in args.tasks:
            print(APP / "app/build/outputs/apk/debug/app-debug.apk")


if __name__ == "__main__":
    main()
