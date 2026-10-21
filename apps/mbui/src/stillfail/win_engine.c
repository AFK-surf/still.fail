// core_engine.m's Windows twin, put in its place by mbui's scripts/win.sh for APP=stillfail (moon.pkg cannot pick stubs
// per OS): the core in Hermes on the Rust shell (src/sfcore/win_engine.c).
#include "../sfcore/win_engine.c"

// main.mbt asks it before it starts the core (core_engine.m has the same on Apple's systems): what keeps this file in the
// link, and, here, where the engine is handed over.
int32_t mb_stillfail_core_linked(void) {
  use_hermes_engine();
  return 1;
}

// What still.fail's own host is told (reports.mbt: crash reports, the bar's timing): only Android's takes it
// (src/host/android_reports.c); 0 says so.
int32_t mb_stillfail_tell(const void *what, const void *a, const void *b, int32_t n, int32_t m) { return 0; }
