// The core's engine, linked into this app (src/sfcore/apple_engine.m: Hermes on the Rust shell, on iOS the browser
// session for signing in). moon does not track the file it includes: touch this one after changing that.
#include "../sfcore/apple_engine.m"

// Called from main.mbt: what keeps this file in the link (moon links an app's stubs as an archive, and an object
// nothing refers to is left out, its engine's constructor with it).
int32_t mb_stillfail_core_linked(void) { return 1; }

// What still.fail's own host is told (reports.mbt: crash reports, the bar's timing): only Android's takes it
// (src/host/android_reports.c); 0 says so.
int32_t mb_stillfail_tell(const void *what, const void *a, const void *b, int32_t n, int32_t m) { return 0; }
