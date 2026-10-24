package dev.mbui;

/**
 * What the core spends its time on, in the app as shipped (still.fail's CoreProfile, apps/android/core Engine.kt): its
 * JS sampled for a while, the trace (Chrome's format, for DevTools' Performance panel) written to a file; and what the
 * Rust shell has been asked since the process started. The engine's (libstillfail_hermes.so: sf_engine_profile and
 * sf_engine_shell_stats), bound here by src/host/android_core.c as the core first starts: before that,
 * UnsatisfiedLinkError.
 */
final class CoreProfile {
    private CoreProfile() {}

    /** The core's JS sampled for {@code seconds}, its trace written to {@code path} then (logcat StillFailCore says so). */
    static native void sample(int seconds, String path);

    /** {@code {calls: {op: [started, unanswered]}, handles: {kind: n}, sqls}} (client/shell's sf_shell_stats). */
    static native String shellStats();
}
