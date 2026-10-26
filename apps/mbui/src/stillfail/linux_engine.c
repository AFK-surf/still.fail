// core_engine.m's Linux twin, put in its place by mbui's scripts/linux.sh for APP=stillfail (moon.pkg cannot pick stubs
// per OS): the core in Hermes on the Rust shell (src/sfcore/linux_engine.c).
#include "../sfcore/linux_engine.c"

// main.mbt asks it before it starts the core (core_engine.m has the same on Apple's systems): what keeps this file in the
// link (moon links an app's stubs as an archive, and an object nothing refers to is left out, its engine's constructor
// with it).
int32_t mb_stillfail_core_linked(void) { return 1; }

// What still.fail's own host is told (reports.mbt: crash reports, the bar's timing): only Android's takes it
// (src/host/android_reports.c); 0 says so.
int32_t mb_stillfail_tell(const void *what, const void *a, const void *b, int32_t n, int32_t m) {
  (void)what, (void)a, (void)b, (void)n, (void)m;
  return 0;
}
