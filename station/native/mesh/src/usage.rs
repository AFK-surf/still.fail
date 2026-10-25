//! What processes have used so far (station/src/resources): macOS counts each one's CPU time, memory footprint, idle
//! wakeups, energy and bytes read from and written to disk (`proc_pid_rusage`, RUSAGE_INFO_V6, what Activity Monitor's columns come from), readable for the
//! user's own processes without root. Elsewhere nothing is read.

use napi_derive::napi;

/// What one process has used so far.
#[napi(object)]
pub struct ProcessUsage {
    /// CPU time, user and system, in nanoseconds.
    pub cpu_ns: f64,
    /// Its memory footprint now (Activity Monitor's Memory), in bytes.
    pub footprint: f64,
    /// Times it woke a CPU (interrupt wakeups: Activity Monitor's Idle Wake Ups).
    pub wakeups: f64,
    /// Energy, in nanojoules (exact up to some 100 days at 1 kW).
    pub energy_nj: f64,
    /// Bytes read from disk (Activity Monitor's Disk: Bytes Read).
    pub disk_read: f64,
    /// Bytes written to disk.
    pub disk_written: f64,
}

/// Each of `pids`' usage so far; none for one not read (gone, another user's, not macOS).
#[napi]
pub fn process_usage(pids: Vec<u32>) -> Vec<Option<ProcessUsage>> {
    pids.into_iter().map(read).collect()
}

#[cfg(target_os = "macos")]
fn read(pid: u32) -> Option<ProcessUsage> {
    /// rusage_info_v6 (<sys/resource.h>): user and system time, …, the wakeups (the 4th), …, the footprint (the 8th), …,
    /// the bytes read and written (the 17th and 18th), …, the energy (the 41st), and room for the rest.
    #[repr(C)]
    struct RusageInfoV6 {
        uuid: [u8; 16],
        before: [u64; 40],
        energy_nj: u64,
        rest: [u64; 16],
    }
    #[repr(C)]
    struct Timebase {
        numer: u32,
        denom: u32,
    }
    const RUSAGE_INFO_V6: libc::c_int = 6;
    unsafe extern "C" {
        fn proc_pid_rusage(pid: libc::c_int, flavor: libc::c_int, buffer: *mut RusageInfoV6) -> libc::c_int;
        fn mach_timebase_info(info: *mut Timebase) -> libc::c_int;
    }
    let mut info = std::mem::MaybeUninit::<RusageInfoV6>::zeroed();
    // SAFETY: the buffer is a whole rusage_info_v6, which the call fills.
    let rc = unsafe { proc_pid_rusage(pid as libc::c_int, RUSAGE_INFO_V6, info.as_mut_ptr()) };
    if rc != 0 {
        return None;
    }
    let info = unsafe { info.assume_init() };
    // The times are in mach ticks (on Apple silicon not nanoseconds).
    let mut base = Timebase { numer: 1, denom: 1 };
    // SAFETY: the call fills the struct.
    unsafe { mach_timebase_info(&mut base) };
    let ticks = (info.before[0] + info.before[1]) as f64;
    Some(ProcessUsage {
        cpu_ns: ticks * base.numer as f64 / base.denom.max(1) as f64,
        footprint: info.before[7] as f64,
        wakeups: info.before[3] as f64,
        energy_nj: info.energy_nj as f64,
        disk_read: info.before[16] as f64,
        disk_written: info.before[17] as f64,
    })
}

#[cfg(not(target_os = "macos"))]
fn read(_pid: u32) -> Option<ProcessUsage> {
    None
}
