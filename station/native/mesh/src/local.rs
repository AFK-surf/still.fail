//! What the station's TypeScript cannot do as the Rust station did, done by the Rust station's own code:
//! - the archive lock (mesh/app/src/archive.rs `file_lock`): an flock on the lock file, held across processes (a Rust
//!   station and a TS one, or two Node processes during a handover, never pack the same room at once);
//! - local Markdown links (mesh/app/src/local_links.rs `prepare`), read with pulldown-cmark as the Rust reads them.
use std::fs::{File, OpenOptions};
#[cfg(unix)]
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use napi_derive::napi;
use pulldown_cmark::{Event, LinkType, Parser, Tag};

/// A lock taken: held until released (or the process ends).
#[napi]
pub struct FileLock {
    file: Mutex<Option<File>>,
}

#[napi]
impl FileLock {
    /// Lets it go.
    #[napi]
    pub fn release(&self) {
        self.file.lock().unwrap().take();
    }
}

/// archive.rs `file_lock`: the lock file made (0600, never truncated) and an exclusive lock taken on it (flock on Unix,
/// LockFileEx on Windows: std's `File::lock`), waited for off the JS thread.
#[napi]
pub async fn file_lock(path: String) -> napi::Result<FileLock> {
    tokio::task::spawn_blocking(move || -> std::io::Result<FileLock> {
        let mut options = OpenOptions::new();
        // Read too: LockFileEx wants a handle that may read or write, and one opened to append only may do neither.
        options.create(true).read(true).append(true);
        #[cfg(unix)]
        options.mode(0o600);
        let file = options.open(&path)?;
        file.lock()?;
        Ok(FileLock { file: Mutex::new(Some(file)) })
    })
    .await
    .map_err(|e| napi::Error::from_reason(e.to_string()))?
    .map_err(|e| napi::Error::from_reason(e.to_string()))
}

/// `C:\…` or `C:/…`: a path on a Windows drive.
fn is_drive_path(text: &str) -> bool {
    let b = text.as_bytes();
    b.len() >= 3 && b[0].is_ascii_alphabetic() && b[1] == b':' && (b[2] == b'\\' || b[2] == b'/')
}

/// Resolve only file URLs, familiar machine roots, or paths that actually name a local file.
fn local_path(destination: &str) -> std::result::Result<Option<PathBuf>, String> {
    let decoded = percent_encoding::percent_decode_str(destination).decode_utf8_lossy();
    let path = if destination.starts_with("file:") {
        url::Url::parse(destination)
            .ok()
            .and_then(|u| u.to_file_path().ok())
            .ok_or_else(|| format!("invalid local file link: {destination}; use an absolute path in files"))?
    } else if cfg!(windows) && is_drive_path(&decoded) {
        // On Windows a drive's path (`C:\…`, `C:/…`) is a local one, as a familiar root's is on Unix.
        PathBuf::from(decoded.as_ref())
    } else {
        if !decoded.starts_with('/') || decoded.starts_with("//") {
            return Ok(None);
        }
        let known = ["/Users/", "/home/", "/tmp/", "/private/", "/var/", "/Volumes/", "/mnt/", "/workspace/", "/etc/", "/opt/"];
        if !known.iter().any(|root| decoded.starts_with(root)) && !Path::new(decoded.as_ref()).is_file() {
            return Ok(None);
        }
        PathBuf::from(decoded.as_ref())
    };
    if path.is_file() {
        return Ok(Some(path));
    }
    let raw = path.to_string_lossy();
    let mut base = raw.as_ref();
    for _ in 0..2 {
        let Some((head, tail)) = base.rsplit_once(':') else { break };
        if tail.is_empty() || !tail.bytes().all(|c| c.is_ascii_digit()) {
            break;
        }
        base = head;
        if Path::new(base).is_file() {
            return Ok(Some(PathBuf::from(base)));
        }
    }
    Err(format!("local file link does not name a readable file: {destination}; correct the path or write it as code instead of a link"))
}

/// A destination with no scheme that is neither from a root nor a fragment or a query (`films/a.mp4`, `report.pdf`):
/// a path where the agent works, as `files` takes one.
fn is_relative(destination: &str) -> bool {
    let scheme = destination.split_once(':').is_some_and(|(s, _)| {
        s.as_bytes().first().is_some_and(u8::is_ascii_alphabetic) && s.bytes().all(|c| c.is_ascii_alphanumeric() || matches!(c, b'+' | b'-' | b'.'))
    });
    !destination.is_empty() && !scheme && !destination.starts_with(|c| matches!(c, '/' | '\\' | '#' | '?'))
}

/// A relative link's file: none when it names one of the message's files (`[report](report.pdf)` beside `files`, which
/// the clients place by its name), else the one it names in the workspace. Naming neither, it is refused: no reader
/// could open it.
fn in_workspace(destination: &str, paths: &[String], workspace: &Path) -> std::result::Result<Option<PathBuf>, String> {
    let decoded = percent_encoding::percent_decode_str(destination).decode_utf8_lossy();
    let name = decoded.rsplit('/').next().unwrap_or_default();
    if paths.iter().any(|p| Path::new(p).file_name().is_some_and(|n| n.to_string_lossy() == name)) {
        return Ok(None);
    }
    let path = workspace.join(decoded.as_ref());
    if path.is_file() {
        return Ok(Some(path));
    }
    Err(format!(
        "local file link {destination} names no file in the workspace ({}) nor one of the message's files; give its absolute path or attach it with files, use a full URL (https://…), or write it as code",
        workspace.display()
    ))
}

#[napi(object)]
pub struct Prepared {
    pub text: String,
    pub paths: Vec<String>,
}

/// local_links.rs `prepare`: local links made to refer to the message's attachments (added to `paths`), word for word
/// as the Rust station does; its refusals thrown with the same words.
#[napi]
pub fn prepare_local_links(text: String, paths: Vec<String>, workspace: String) -> napi::Result<Prepared> {
    let mut paths = paths;
    let workspace = Path::new(&workspace);
    let fail = |m: String| napi::Error::from_reason(m);
    let mut replacements = Vec::new();
    for (event, range) in Parser::new(&text).into_offset_iter() {
        let (kind, destination) = match event {
            Event::Start(Tag::Link { link_type, dest_url, .. } | Tag::Image { link_type, dest_url, .. }) => (link_type, dest_url),
            _ => continue,
        };
        let path = match local_path(&destination).map_err(fail)? {
            Some(path) => path,
            // (an email's autolink, <a@b.c>, is no path)
            None if kind != LinkType::Email && is_relative(&destination) => match in_workspace(&destination, &paths, workspace).map_err(fail)? {
                Some(path) => path,
                None => continue,
            },
            None => continue,
        };
        if kind != LinkType::Inline {
            return Err(fail(format!("local file link {destination} must use inline Markdown: [label](path); it will be attached automatically")));
        }
        let source = &text[range.clone()];
        let start = source
            .rmatch_indices(destination.as_ref())
            .find_map(|(start, _)| {
                let before = source[..start].trim_end().trim_end_matches('<').trim_end();
                before.ends_with("](").then_some(start)
            })
            .ok_or_else(|| fail(format!("write local file link {destination} without Markdown escapes (use <…> around paths with spaces)")))?;
        let canonical = path.canonicalize().map_err(|_| fail(format!("no such file: {}", path.display())))?;
        if !paths.iter().any(|p| workspace.join(p).canonicalize().ok().as_ref() == Some(&canonical)) {
            paths.push(path.to_string_lossy().into_owned());
        }
        let name = path.file_name().ok_or_else(|| fail(format!("not a file: {}", path.display())))?.to_string_lossy();
        let name = percent_encoding::utf8_percent_encode(&name, percent_encoding::NON_ALPHANUMERIC).to_string();
        replacements.push((range.start + start..range.start + start + destination.len(), name));
    }
    let mut names = std::collections::HashMap::new();
    for path in paths.iter() {
        let path = workspace.join(path);
        let canonical = path.canonicalize().map_err(|_| fail(format!("no such file: {}", path.display())))?;
        if let Some(name) = path.file_name() {
            if let Some(previous) = names.insert(name.to_os_string(), canonical.clone()) {
                if previous != canonical {
                    return Err(fail(format!("attachments have the same name: {}; rename the files before posting", name.to_string_lossy())));
                }
            }
        }
    }
    let mut result = text.clone();
    replacements.sort_by_key(|(r, _)| r.start);
    for (range, name) in replacements.into_iter().rev() {
        result.replace_range(range, &name);
    }
    Ok(Prepared { text: result, paths })
}

/// The process at the other end of a connected Unix socket (docs/data-outflow.md): its pid, and on macOS its audit
/// token (`LOCAL_PEERTOKEN`, hex: the pid with its generation, which the code signature is looked up by so a pid used
/// again by another process is not mistaken for it). Taken when the other end connected, not now.
#[napi(object)]
pub struct PeerProcess {
    pub pid: u32,
    pub audit_token: Option<String>,
}

/// The other end of the socket `fd`; none when it is not a Unix socket's or the system does not say.
#[napi]
pub fn peer_process(fd: i32) -> Option<PeerProcess> {
    peer(fd)
}

#[cfg(target_os = "macos")]
fn peer(fd: i32) -> Option<PeerProcess> {
    // <sys/un.h>: SOL_LOCAL, LOCAL_PEERPID, LOCAL_PEERTOKEN.
    const SOL_LOCAL: libc::c_int = 0;
    const LOCAL_PEERPID: libc::c_int = 0x002;
    const LOCAL_PEERTOKEN: libc::c_int = 0x006;
    let mut pid: libc::pid_t = 0;
    let mut len = std::mem::size_of::<libc::pid_t>() as libc::socklen_t;
    if unsafe { libc::getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &mut pid as *mut _ as *mut libc::c_void, &mut len) } != 0 || pid <= 0 {
        return None;
    }
    let mut token = [0u8; 32];
    let mut len = token.len() as libc::socklen_t;
    let ok = unsafe { libc::getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, token.as_mut_ptr() as *mut libc::c_void, &mut len) } == 0 && len as usize == token.len();
    Some(PeerProcess { pid: pid as u32, audit_token: ok.then(|| hex::encode(token)) })
}

#[cfg(target_os = "linux")]
fn peer(fd: i32) -> Option<PeerProcess> {
    let mut cred = libc::ucred { pid: 0, uid: 0, gid: 0 };
    let mut len = std::mem::size_of::<libc::ucred>() as libc::socklen_t;
    if unsafe { libc::getsockopt(fd, libc::SOL_SOCKET, libc::SO_PEERCRED, &mut cred as *mut _ as *mut libc::c_void, &mut len) } != 0 || cred.pid <= 0 {
        return None;
    }
    Some(PeerProcess { pid: cred.pid as u32, audit_token: None })
}

#[cfg(not(any(target_os = "macos", target_os = "linux")))]
fn peer(_fd: i32) -> Option<PeerProcess> {
    None
}
