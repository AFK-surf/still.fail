// The core's engine, linked into this app (src/sfcore/apple_engine.m: Hermes on the Rust shell, on iOS the browser
// session for signing in). moon does not track the file it includes: touch this one after changing that.
#include "../sfcore/apple_engine.m"

// This machine's station, the app's own native call on macOS (src/host/station_calls.h). moon does not track the
// included files: touch this one after changing them.
#if !TARGET_OS_IPHONE
#include "../host/mac_station.m"
#include "../host/station_calls.h"
#endif

// Called from main.mbt: what keeps this file in the link (moon links an app's stubs as an archive, and an object
// nothing refers to is left out, its engine's constructor with it).
int32_t mb_stillfail_core_linked(void) { return 1; }

// What still.fail's own host is told (reports.mbt: crash reports, the bar's timing): Android's (src/host/
// android_reports.c), and iOS's and macOS's (src/host/apple_reports.m): on both the window thread's hangs and the errors
// the app got past, on iOS MetricKit's reports of crashes and hangs as well (scripts/ios-core.sh links MetricKit). A
// build without PostHog's key in its Info.plist sends nothing (`hello` 0). moon does not track the included file:
// touch this one after changing it.
#include "../host/apple_reports.m"
