// The core's engine, linked into this app alone so the default demo stays without the 57 MB shell
// (src/sfcore/apple_engine.m: Hermes on the Rust shell, the browser session for signing in).
#include "../sfcore/apple_engine.m"

// An environment variable for the app's MoonBit, "" when unset.
moonbit_string_t mb_coredemo_env(moonbit_string_t name) {
  const char *v = getenv(mb_ns_from_string(name).UTF8String);
  return mb_string_from_ns(v ? @(v) : @"");
}

// The engine's name, for the header.
moonbit_string_t mb_coredemo_engine(void) { return mb_string_from_ns(@"Hermes"); }

// MBUI_SECURE_TEST=1 (main.mbt): secure.* round-tripped by the engine (apple_core.mm), its outcome on the log.
int mb_core_secure_test(void);
int32_t mb_coredemo_secure_test(void) { return mb_core_secure_test(); }
