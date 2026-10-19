//! sf_utc_offset_min (what the core's `utcOffset` asks) in zones set by TZ, which the C library reads on every
//! platform: POSIX's localtime_r, and on Windows the CRT's _localtime64_s. A file of its own: TZ is the process's, and
//! nothing else here may read the local time while it changes.
use stillfail_shell::sf_utc_offset_min;

/// TZ set as the C library sees it, and read again.
fn zone(tz: &str) {
    #[cfg(unix)]
    {
        // SAFETY: this test is the only thing in its process (its file's one test) reading the environment.
        unsafe { std::env::set_var("TZ", tz) };
        unsafe { libc::tzset() };
    }
    #[cfg(windows)]
    {
        // The CRT keeps its own copy of the environment, which SetEnvironmentVariable (std::env::set_var) does not change.
        unsafe extern "C" {
            fn _putenv_s(name: *const std::ffi::c_char, value: *const std::ffi::c_char) -> i32;
            fn _tzset();
        }
        let value = std::ffi::CString::new(tz).unwrap();
        assert_eq!(unsafe { _putenv_s(c"TZ".as_ptr(), value.as_ptr()) }, 0);
        unsafe { _tzset() };
    }
}

#[test]
fn offsets_follow_the_zone_and_its_daylight_saving() {
    const JANUARY: f64 = 1768478400000.0; // 2026-01-15T12:00:00Z
    const JULY: f64 = 1784116800000.0; // 2026-07-15T12:00:00Z
    for (tz, january, july) in [("UTC0", 0, 0), ("JST-9", 540, 540), ("IST-5:30", 330, 330), ("EST5EDT", -300, -240)] {
        zone(tz);
        assert_eq!((sf_utc_offset_min(JANUARY), sf_utc_offset_min(JULY)), (january, july), "TZ={tz}");
        // Within a second as at its start (the core passes milliseconds).
        assert_eq!(sf_utc_offset_min(JANUARY + 999.0), january, "TZ={tz}");
    }
}
