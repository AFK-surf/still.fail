// The still.fail core's engine for the mbui app where no platform glue is needed around it (Windows: stillfail_engine.dll,
// scripts/native.ts part `engine` win32-x64): Hermes 0.81.4, the same as Android's, running the core's bytecode
// (client/core-ts hosts/hermes-start.ts, by apps/mbui/scripts/core.sh hermes) on one thread of its own, with its tasks,
// timers and microtasks, and `__native` on the Rust shell (client/shell). Android's engine
// (apps/android/core/src/main/cpp/engine.cpp) without JNI: what it says, and the calls only the app can do (`secure.*`,
// `listen.*`), go to the host through a C API, so a host in C (src/host/win_core.c) needs no C++ of its own.
#pragma once
#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#ifdef SF_ENGINE_BUILD
#define SF_ENGINE_API __declspec(dllexport)
#else
#define SF_ENGINE_API __declspec(dllimport)
#endif
#else
#define SF_ENGINE_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct sf_engine sf_engine;

/// What the engine hands its host. Called on the core's own thread; the pointers are valid only during the call.
typedef struct {
  void *ctx;
  /// What the core says to the app: its JSON (UTF-8, not NUL-terminated) and, for a message with bytes beside it, the
  /// bytes (`bytes` NULL when it has none). `{"fatal": …}` once the core has failed: stop it and start another.
  void (*say)(void *ctx, const char *json, size_t len, const uint8_t *bytes, size_t blen);
  /// A call only the app can do (`secure.*`, `listen.*`): answered with sf_engine_complete, from any thread, later or
  /// at once (`bytes` NULL when the call has none).
  void (*app_call)(void *ctx, uint64_t id, const char *op, const char *json, size_t len, const uint8_t *bytes, size_t blen);
  /// A line of the core's log: 0 debug, 1 info, 2 warn, 3 error. May be NULL.
  void (*log)(void *ctx, int level, const char *text, size_t len);
} sf_engine_host;

/// Starts a core: its script (Hermes bytecode or source; copied), named `script_url` in its stack traces, its files in
/// `data_dir` (made by the shell), still.fail cloud at `cloud_origin`, `beta` the test channel, `os` what it says it
/// runs on ("windows"). Returns at once; the core's thread starts the shell, runs the script and connects one client,
/// the app, whose messages sf_engine_receive passes in. NULL only when no thread could be made.
SF_ENGINE_API sf_engine *sf_engine_start(const uint8_t *script, size_t script_len, const char *script_url, const char *data_dir,
                                         const char *cloud_origin, int beta, const char *os, const sf_engine_host *host);

/// What the app says (the protocol's JSON, and the bytes beside it or NULL). Copied; any thread.
SF_ENGINE_API void sf_engine_receive(sf_engine *engine, const char *json, size_t len, const uint8_t *bytes, size_t blen);

/// The app's answer to an app_call: `error` (UTF-8, `elen` bytes) when it failed, else `json` and the bytes beside it
/// (or NULL). Copied; any thread, but never after sf_engine_stop.
SF_ENGINE_API void sf_engine_complete(sf_engine *engine, uint64_t id, const char *json, size_t len, const char *error, size_t elen,
                                      const uint8_t *bytes, size_t blen);

/// Ends the core and waits for its thread; the shell's answers still on their way are let go. Nothing is called on the
/// host after it returns, and `engine` is gone. Not from the core's thread.
SF_ENGINE_API void sf_engine_stop(sf_engine *engine);

#ifdef __cplusplus
}
#endif
