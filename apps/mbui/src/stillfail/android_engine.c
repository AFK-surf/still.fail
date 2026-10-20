// core_engine.m's Android twin, compiled by scripts/android.sh for APP=stillfail (moon never sees this file): the
// core in ember's Hermes engine (src/sfcore/android_engine.c).
#include "../sfcore/android_engine.c"

// main.mbt asks it (core_engine.m has the same on Apple's systems).
int32_t mb_stillfail_core_linked(void) { return 1; }

// What still.fail's own host is told (reports.mbt): its crash reports and the bar's timing (Crashes.java, BarTiming.java).
#include "../host/android_reports.c"
