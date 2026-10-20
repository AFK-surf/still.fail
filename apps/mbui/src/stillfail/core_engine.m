// The core's engine, linked into this app (src/sfcore/apple_engine.m: Hermes on the Rust shell, the browser
// session for signing in). moon does not track the file it includes: touch this one after changing that.
#include "../sfcore/apple_engine.m"

// Called from main.mbt: what keeps this file in the link (moon links an app's stubs as an archive, and an object
// nothing refers to is left out, its engine's constructor with it).
int32_t mb_stillfail_core_linked(void) { return 1; }
