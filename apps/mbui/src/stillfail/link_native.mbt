///|
/// Whether the core's engine is linked in (core_engine.m; calling it keeps it in the link).
extern "C" fn core_linked() -> Int = "mb_stillfail_core_linked"

///|
/// What still.fail's own host is told (src/host/android_reports.c: Android's crash reports and bar timing, Crashes.java,
/// BarTiming.java; src/host/apple_reports.m: iOS's crash reports): `what` with its words and numbers; 0 where nothing
/// takes it (macOS, Windows, an iOS build without PostHog's key).
#borrow(what, a, b)
extern "C" fn host_tell(what : String, a : String, b : String, n : Int, m : Int) -> Int = "mb_stillfail_tell"
