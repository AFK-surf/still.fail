///|
/// Whether the core's engine is linked in (core_engine.m; calling it keeps it in the link).
extern "C" fn core_linked() -> Int = "mb_stillfail_core_linked"

///|
/// What still.fail's own host is told (src/host/android_reports.c: Android's crash reports and bar timing, Crashes.java,
/// BarTiming.java): `what` with its words and numbers; 0 where nothing takes it (macOS, iOS, Windows).
#borrow(what, a, b)
extern "C" fn host_tell(what : String, a : String, b : String, n : Int, m : Int) -> Int = "mb_stillfail_tell"
