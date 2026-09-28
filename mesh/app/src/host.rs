//! What the machine a station runs on looks like: for people deciding where work goes and whether a station is
//! struggling. Memory on macOS comes from vm_stat (what Activity Monitor counts as used: app, wired and compressed
//! pages, not reclaimable cache); disk is the file system holding the station's data directory.

use std::ffi::CString;
use std::path::Path;
use std::sync::Mutex;
use std::time::Duration;

use serde::Serialize;
use tokio::process::Command;

use crate::store::now_ms;

#[derive(Serialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HostMemory {
    pub total_bytes: u64,
    pub used_bytes: u64,
    pub swap_used_bytes: Option<u64>,
}

#[derive(Serialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HostDisk {
    pub path: String,
    pub total_bytes: u64,
    pub free_bytes: u64,
}

#[derive(Serialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HostInfo {
    pub hostname: String,
    /// e.g. "macOS 26.0" or "Linux 6.8".
    pub os: String,
    pub arch: String,
    pub cpus: usize,
    pub cpu_model: String,
    /// 1-minute load average divided by CPU count, 0–1+.
    pub load: f64,
    pub uptime_sec: u64,
    pub memory: HostMemory,
    pub disk: HostDisk,
    /// The station's own process.
    pub ember_rss_bytes: u64,
    pub checked_at: i64,
}

/// A command's output, or nothing when it cannot be run (within a few seconds).
async fn output(command: &str, args: &[&str]) -> Option<String> {
    let run = Command::new(command).args(args).kill_on_drop(true).output();
    let out = tokio::time::timeout(Duration::from_secs(3), run).await.ok()?.ok()?;
    out.status.success().then(|| String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// The number after `label:` in `text`, e.g. vm_stat's and /proc/meminfo's lines.
fn field(text: &str, label: &str) -> u64 {
    text.lines()
        .find_map(|line| line.strip_prefix(label)?.strip_prefix(':').map(|rest| rest.trim().trim_end_matches('.').split_whitespace().next().unwrap_or("").parse().unwrap_or(0)))
        .unwrap_or(0)
}

fn uname() -> (String, String) {
    // SAFETY: utsname is plain data filled in by uname(2).
    let mut name: libc::utsname = unsafe { std::mem::zeroed() };
    if unsafe { libc::uname(&mut name) } != 0 {
        return (String::new(), String::new());
    }
    let text = |field: &[libc::c_char]| unsafe { std::ffi::CStr::from_ptr(field.as_ptr()) }.to_string_lossy().into_owned();
    (text(&name.sysname), text(&name.release))
}

fn hostname() -> String {
    let mut buf = [0u8; 256];
    // SAFETY: gethostname writes at most buf.len() bytes.
    if unsafe { libc::gethostname(buf.as_mut_ptr() as *mut libc::c_char, buf.len()) } != 0 {
        return String::new();
    }
    let end = buf.iter().position(|b| *b == 0).unwrap_or(buf.len());
    let name = String::from_utf8_lossy(&buf[..end]).into_owned();
    name.strip_suffix(".local").map(String::from).unwrap_or(name)
}

fn load_average() -> f64 {
    let mut loads = [0f64; 3];
    // SAFETY: getloadavg writes at most 3 values.
    if unsafe { libc::getloadavg(loads.as_mut_ptr(), 3) } < 1 {
        return 0.0;
    }
    loads[0]
}

fn disk(path: &Path) -> HostDisk {
    let given = path.to_string_lossy().into_owned();
    let empty = HostDisk { path: given.clone(), total_bytes: 0, free_bytes: 0 };
    let Ok(c) = CString::new(given.clone()) else { return empty };
    // SAFETY: statvfs fills the struct for a NUL-terminated path.
    let mut st: libc::statvfs = unsafe { std::mem::zeroed() };
    if unsafe { libc::statvfs(c.as_ptr(), &mut st) } != 0 {
        return empty;
    }
    let block = st.f_frsize as u64;
    HostDisk { path: given, total_bytes: st.f_blocks as u64 * block, free_bytes: st.f_bavail as u64 * block }
}

/// Node's names for the architecture, which the pages show.
fn arch() -> String {
    match std::env::consts::ARCH {
        "aarch64" => "arm64".into(),
        "x86_64" => "x64".into(),
        other => other.into(),
    }
}

async fn memory() -> HostMemory {
    if cfg!(target_os = "macos") {
        let total = output("sysctl", &["-n", "hw.memsize"]).await.and_then(|t| t.parse().ok()).unwrap_or(0u64);
        if let Some(vm) = output("vm_stat", &[]).await {
            let page: u64 = vm.split("page size of ").nth(1).and_then(|r| r.split_whitespace().next()).and_then(|n| n.parse().ok()).unwrap_or(16384);
            let pages = |label: &str| field(&vm, label) as i64;
            let used = (pages("Anonymous pages") - pages("Pages purgeable") + pages("Pages wired down") + pages("Pages occupied by compressor")).max(0) as u64 * page;
            let swap = output("sysctl", &["-n", "vm.swapusage"]).await.and_then(|s| {
                let used = s.split("used = ").nth(1)?.split('M').next()?.parse::<f64>().ok()?;
                Some((used * 1024.0 * 1024.0).round() as u64)
            });
            return HostMemory { total_bytes: total, used_bytes: used.min(total), swap_used_bytes: swap };
        }
        return HostMemory { total_bytes: total, used_bytes: 0, swap_used_bytes: None };
    }
    let info = std::fs::read_to_string("/proc/meminfo").unwrap_or_default();
    let kb = |k: &str| field(&info, k) * 1024;
    HostMemory {
        total_bytes: kb("MemTotal"),
        used_bytes: kb("MemTotal").saturating_sub(kb("MemAvailable")),
        swap_used_bytes: Some(kb("SwapTotal").saturating_sub(kb("SwapFree"))),
    }
}

async fn cpu_model() -> String {
    if cfg!(target_os = "macos") {
        return output("sysctl", &["-n", "machdep.cpu.brand_string"]).await.unwrap_or_default();
    }
    let info = std::fs::read_to_string("/proc/cpuinfo").unwrap_or_default();
    info.lines().find_map(|l| l.strip_prefix("model name").and_then(|r| r.split_once(':')).map(|(_, v)| v.trim().to_string())).unwrap_or_default()
}

async fn uptime_sec() -> u64 {
    if cfg!(target_os = "macos") {
        // "{ sec = 1790000000, usec = 0 } ..."
        let boot = output("sysctl", &["-n", "kern.boottime"]).await.and_then(|t| t.split("sec = ").nth(1)?.split(',').next()?.trim().parse::<i64>().ok());
        return boot.map(|b| (now_ms() / 1000 - b).max(0) as u64).unwrap_or(0);
    }
    std::fs::read_to_string("/proc/uptime").ok().and_then(|t| t.split_whitespace().next()?.parse::<f64>().ok()).map(|s| s.round() as u64).unwrap_or(0)
}

async fn os_name() -> String {
    let (sysname, release) = uname();
    if cfg!(target_os = "macos") {
        return match output("sw_vers", &["-productVersion"]).await {
            Some(version) => format!("macOS {version}"),
            None => format!("macOS (Darwin {release})"),
        };
    }
    format!("{sysname} {release}")
}

/// This process's resident memory.
async fn own_rss() -> u64 {
    let pid = std::process::id().to_string();
    output("ps", &["-o", "rss=", "-p", &pid]).await.and_then(|kb| kb.trim().parse::<u64>().ok()).map(|kb| kb * 1024).unwrap_or(0)
}

static CACHED: Mutex<Option<HostInfo>> = Mutex::new(None);

/// The machine's state, at most ten seconds old.
pub async fn host_info(data_dir: &Path) -> HostInfo {
    if let Some(cached) = CACHED.lock().unwrap().clone().filter(|c| now_ms() - c.checked_at < 10_000) {
        return cached;
    }
    let (memory, os, cpu_model, uptime_sec, ember_rss_bytes) = tokio::join!(memory(), os_name(), cpu_model(), uptime_sec(), own_rss());
    let cpus = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1);
    let value = HostInfo {
        hostname: hostname(),
        os,
        arch: arch(),
        cpus,
        cpu_model,
        load: (load_average() / cpus.max(1) as f64 * 100.0).round() / 100.0,
        uptime_sec,
        memory,
        disk: disk(data_dir),
        ember_rss_bytes,
        checked_at: now_ms(),
    };
    *CACHED.lock().unwrap() = Some(value.clone());
    value
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn the_machine_is_described_and_kept_for_a_while() {
        let dir = tempfile::tempdir().unwrap();
        let info = host_info(dir.path()).await;
        assert!(info.cpus >= 1 && !info.os.is_empty() && !info.hostname.is_empty());
        assert!(info.memory.total_bytes > 0 && info.memory.used_bytes <= info.memory.total_bytes);
        assert!(info.disk.total_bytes > 0 && info.ember_rss_bytes > 0 && info.uptime_sec > 0);
        let json = serde_json::to_value(&info).unwrap();
        assert!(json["memory"]["totalBytes"].is_u64() && json["cpuModel"].is_string());
        assert_eq!(host_info(dir.path()).await.checked_at, info.checked_at, "read again within ten seconds: the same");
    }

    #[test]
    fn vm_stat_lines_are_read() {
        let vm = "Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages free:                               12345.\nAnonymous pages:                         400.\n";
        assert_eq!((field(vm, "Pages free"), field(vm, "Anonymous pages"), field(vm, "Pages wired down")), (12345, 400, 0));
    }
}
