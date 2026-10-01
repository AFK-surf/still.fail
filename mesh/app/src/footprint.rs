//! How much of the machine the station takes, for people to see and clean up: its data directory by what each part is
//! for, each chat's workspace (and what in it can be made again: node_modules, a Rust target, a Gradle build), and,
//! only shown, what agents use beside it on the machine (runtimes' own homes, tool caches).
//!
//! Sizes are what the files take on disk (blocks), a file with several links counted once, links not followed. Going
//! through many gigabytes takes a while, so a scan runs in the background and its result is kept; the pages say when
//! it was made.

use std::collections::{HashMap, HashSet};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use serde::Serialize;

use crate::store::now_ms;

/// What a part of the data directory is for: the pages name them.
pub const PARTS: [&str; 6] = ["chats", "transcripts", "homes", "archive", "repos", "other"];

#[derive(Serialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Part {
    pub id: String,
    pub bytes: u64,
}

/// A place beside the data directory that agents use: shown, not cleaned here.
#[derive(Serialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Elsewhere {
    pub id: String,
    pub path: String,
    pub bytes: u64,
}

/// A chat's own directory (its session's workspace and what is beside it).
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Room {
    pub bytes: u64,
    /// What can be made again, in it: directories and their sizes.
    pub rebuild: Vec<(PathBuf, u64)>,
}

impl Room {
    pub fn rebuild_bytes(&self) -> u64 {
        self.rebuild.iter().map(|(_, b)| b).sum()
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Scan {
    pub checked_at: i64,
    pub took_ms: u64,
    pub parts: Vec<Part>,
    pub elsewhere: Vec<Elsewhere>,
    /// By session key.
    pub rooms: HashMap<String, Room>,
}

impl Scan {
    pub fn total(&self) -> u64 {
        self.parts.iter().map(|p| p.bytes).sum()
    }
}

/// Where a session's own directory is: the one its workspace is in when the station made it (sessions/…/workspace),
/// else none (a workspace that is a person's project is not the station's to measure or clean).
pub fn room_of(data_dir: &Path, workspace: &str) -> Option<PathBuf> {
    let workspace = Path::new(workspace);
    let own = workspace.file_name().is_some_and(|n| n == "workspace") && workspace.starts_with(data_dir.join("sessions"));
    own.then(|| workspace.parent().map(Path::to_path_buf)).flatten()
}

/// Whether a directory is one a build or an install makes again: node_modules, a Cargo target, a Gradle build and its
/// cache, Next's and Turbo's caches, Python's bytecode.
pub fn rebuildable(dir: &Path) -> bool {
    let Some(name) = dir.file_name().and_then(|n| n.to_str()) else { return false };
    let beside = |file: &str| dir.parent().is_some_and(|p| p.join(file).exists());
    match name {
        "node_modules" | ".next" | ".turbo" | "__pycache__" => true,
        "target" => beside("Cargo.toml"),
        ".gradle" => beside("settings.gradle") || beside("settings.gradle.kts") || beside("build.gradle") || beside("build.gradle.kts"),
        "build" => beside("build.gradle") || beside("build.gradle.kts"),
        _ => false,
    }
}

/// Counts files once each however many links they have.
#[derive(Default)]
struct Seen(HashSet<(u64, u64)>);

impl Seen {
    fn bytes(&mut self, meta: &std::fs::Metadata) -> u64 {
        if meta.nlink() > 1 && !self.0.insert((meta.dev(), meta.ino())) {
            return 0;
        }
        meta.blocks() * 512
    }
}

/// The size of `path` and everything under it; links are not followed. With `found`, directories that can be made
/// again are listed there (each counted whole, not looked into further).
fn measure(path: &Path, seen: &mut Seen, mut found: Option<&mut Vec<(PathBuf, u64)>>) -> u64 {
    let Ok(meta) = std::fs::symlink_metadata(path) else { return 0 };
    let mut bytes = seen.bytes(&meta);
    if !meta.is_dir() {
        return bytes;
    }
    let Ok(entries) = std::fs::read_dir(path) else { return bytes };
    for entry in entries.flatten() {
        let child = entry.path();
        let is_dir = entry.file_type().is_ok_and(|t| t.is_dir());
        match found.as_deref_mut() {
            Some(list) if is_dir && rebuildable(&child) => {
                let size = measure(&child, seen, None);
                list.push((child, size));
                bytes += size;
            }
            Some(list) => bytes += measure(&child, seen, Some(list)),
            None => bytes += measure(&child, seen, None),
        }
    }
    bytes
}

/// Measures one chat's directory again (after something in it was cleaned).
pub fn measure_room(dir: &Path) -> Room {
    let mut rebuild = vec![];
    let bytes = measure(dir, &mut Seen::default(), Some(&mut rebuild));
    Room { bytes, rebuild }
}

/// Places beside the data directory that agents use, under the person's home: runtimes' own homes and the caches of
/// the tools agents run most.
fn elsewhere_places(home: &Path) -> Vec<(&'static str, PathBuf)> {
    let mut places = vec![("claude", home.join(".claude")), ("codex", home.join(".codex"))];
    if cfg!(target_os = "macos") {
        places.push(("playwright", home.join("Library/Caches/ms-playwright")));
        places.push(("pnpm", home.join("Library/pnpm")));
    } else {
        places.push(("playwright", home.join(".cache/ms-playwright")));
        places.push(("pnpm", home.join(".local/share/pnpm")));
    }
    places.push(("npm", home.join(".npm")));
    places.push(("cargo", home.join(".cargo/registry")));
    places
}

/// Goes through the data directory: `sessions` are the sessions' keys and workspaces. Slow (it reads every file).
pub fn scan(data_dir: &Path, home: Option<&Path>, sessions: &[(String, String)]) -> Scan {
    let started = std::time::Instant::now();
    let mut seen = Seen::default();
    let mut rooms = HashMap::new();
    let mut measured: HashSet<PathBuf> = HashSet::new();
    for (key, workspace) in sessions {
        let Some(dir) = room_of(data_dir, workspace) else { continue };
        if !measured.insert(dir.clone()) {
            continue;
        }
        let mut rebuild = vec![];
        let bytes = measure(&dir, &mut seen, Some(&mut rebuild));
        rooms.insert(key.clone(), Room { bytes, rebuild });
    }
    let mut sizes: HashMap<&str, u64> = HashMap::new();
    sizes.insert("chats", rooms.values().map(|r| r.bytes).sum());
    // What is in the data directory, by part; directories of chats the station no longer has count as chats.
    if let Ok(entries) = std::fs::read_dir(data_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            let path = entry.path();
            if name == "sessions" {
                // Its directories other than the chats' (gone chats, and the directories that hold them).
                *sizes.entry("chats").or_default() += measure_skipping(&path, &measured, &mut seen);
                continue;
            }
            let part = match name.as_str() {
                "transcripts" => "transcripts",
                "homes" => "homes",
                "archive" => "archive",
                "repos" => "repos",
                _ => "other",
            };
            *sizes.entry(part).or_default() += measure(&path, &mut seen, None);
        }
    }
    let elsewhere = home
        .map(|home| {
            elsewhere_places(home)
                .into_iter()
                .filter(|(_, p)| p.exists() && !p.starts_with(data_dir))
                .map(|(id, p)| {
                    let shown = match p.strip_prefix(home) {
                        Ok(rest) => format!("~/{}", rest.display()),
                        Err(_) => p.display().to_string(),
                    };
                    Elsewhere { id: id.to_string(), bytes: measure(&p, &mut seen, None), path: shown }
                })
                .filter(|e| e.bytes > 0)
                .collect()
        })
        .unwrap_or_default();
    Scan {
        checked_at: now_ms(),
        took_ms: started.elapsed().as_millis() as u64,
        parts: PARTS.iter().map(|id| Part { id: id.to_string(), bytes: sizes.get(id).copied().unwrap_or(0) }).collect(),
        elsewhere,
        rooms,
    }
}

/// `dir` without the directories in `skip` (and what is under them).
fn measure_skipping(dir: &Path, skip: &HashSet<PathBuf>, seen: &mut Seen) -> u64 {
    if skip.contains(dir) {
        return 0;
    }
    if !skip.iter().any(|s| s.starts_with(dir)) {
        return measure(dir, seen, None);
    }
    let Ok(meta) = std::fs::symlink_metadata(dir) else { return 0 };
    let mut bytes = seen.bytes(&meta);
    for entry in std::fs::read_dir(dir).into_iter().flatten().flatten() {
        bytes += measure_skipping(&entry.path(), skip, seen);
    }
    bytes
}

/// The last scan, and whether one runs.
#[derive(Default)]
pub struct Footprint {
    last: Mutex<Option<Scan>>,
    scanning: Mutex<bool>,
}

impl Footprint {
    pub fn last(&self) -> Option<Scan> {
        self.last.lock().unwrap().clone()
    }

    pub fn scanning(&self) -> bool {
        *self.scanning.lock().unwrap()
    }

    /// Marks a scan begun; false when one already runs.
    pub fn begin(&self) -> bool {
        let mut scanning = self.scanning.lock().unwrap();
        !std::mem::replace(&mut *scanning, true)
    }

    pub fn finish(&self, scan: Scan) {
        *self.last.lock().unwrap() = Some(scan);
        *self.scanning.lock().unwrap() = false;
    }

    /// A chat's directory as it is now, or gone (None), in the last scan, with the parts' sizes following it.
    pub fn update_room(&self, key: &str, room: Option<Room>) {
        let mut last = self.last.lock().unwrap();
        let Some(scan) = last.as_mut() else { return };
        let before = scan.rooms.get(key).map(|r| r.bytes).unwrap_or(0);
        let after = room.as_ref().map(|r| r.bytes).unwrap_or(0);
        match room {
            Some(room) => scan.rooms.insert(key.to_string(), room),
            None => scan.rooms.remove(key),
        };
        if let Some(chats) = scan.parts.iter_mut().find(|p| p.id == "chats") {
            chats.bytes = (chats.bytes + after).saturating_sub(before);
        }
    }

    /// What a scan older than `max_age_ms` (or none) needs: whether to start one.
    pub fn stale(&self, max_age_ms: i64) -> bool {
        self.last.lock().unwrap().as_ref().is_none_or(|s| now_ms() - s.checked_at > max_age_ms)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write(path: &Path, bytes: usize) {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, vec![7u8; bytes]).unwrap();
    }

    #[test]
    fn the_data_directory_is_measured_by_part_and_chat() {
        let root = tempfile::tempdir().unwrap();
        let data = root.path().join("data");
        let ws = data.join("sessions/ember/c-1/workspace");
        write(&ws.join("notes.md"), 10_000);
        write(&ws.join("app/node_modules/x/index.js"), 50_000);
        write(&ws.join("app/package.json"), 100);
        write(&ws.join("rust/Cargo.toml"), 100);
        write(&ws.join("rust/target/debug/bin"), 40_000);
        // Not a Cargo target: kept.
        write(&ws.join("docs/target/page.md"), 3_000);
        write(&data.join("sessions/ember/c-gone/workspace/a"), 8_000);
        write(&data.join("transcripts/claude/x.jsonl"), 20_000);
        write(&data.join("repos/r/file"), 5_000);
        write(&data.join("ember.db"), 4_000);
        let home = root.path().join("home");
        write(&home.join(".npm/_cacache/x"), 6_000);
        let scan = scan(&data, Some(&home), &[("ember:c-1".into(), ws.to_string_lossy().into_owned()), ("other".into(), "/somewhere/else".into())]);
        let room = &scan.rooms["ember:c-1"];
        assert!(room.bytes >= 103_000, "{room:?}");
        let mut rebuild: Vec<_> = room.rebuild.iter().map(|(p, _)| p.strip_prefix(&ws).unwrap().to_string_lossy().into_owned()).collect();
        rebuild.sort();
        assert_eq!(rebuild, ["app/node_modules", "rust/target"]);
        assert!(room.rebuild_bytes() >= 90_000 && room.rebuild_bytes() < room.bytes);
        assert!(!scan.rooms.contains_key("other"), "a workspace that is not the station's is not measured");
        let part = |id: &str| scan.parts.iter().find(|p| p.id == id).unwrap().bytes;
        assert!(part("chats") >= room.bytes + 8_000, "a gone chat's directory counts as chats");
        assert!(part("transcripts") >= 20_000 && part("repos") >= 5_000 && part("other") >= 4_000);
        assert_eq!(part("homes"), 0);
        assert_eq!(scan.total(), scan.parts.iter().map(|p| p.bytes).sum::<u64>());
        assert_eq!(scan.elsewhere.iter().map(|e| (e.id.as_str(), e.path.as_str())).collect::<Vec<_>>(), [("npm", "~/.npm")]);
    }

    #[test]
    fn a_file_linked_twice_counts_once() {
        let root = tempfile::tempdir().unwrap();
        write(&root.path().join("a/file"), 64_000);
        std::fs::create_dir_all(root.path().join("b")).unwrap();
        std::fs::hard_link(root.path().join("a/file"), root.path().join("b/file")).unwrap();
        let once = measure(&root.path().join("a"), &mut Seen::default(), None);
        let both = measure(root.path(), &mut Seen::default(), None);
        assert!(both < once + 10_000, "{once} {both}");
    }

    #[test]
    fn a_room_cleaned_updates_the_parts() {
        let usage = Footprint::default();
        assert!(usage.stale(1000) && usage.begin() && !usage.begin());
        let room = Room { bytes: 100, rebuild: vec![(PathBuf::from("/x/node_modules"), 60)] };
        usage.finish(Scan { checked_at: now_ms(), parts: vec![Part { id: "chats".into(), bytes: 150 }], rooms: HashMap::from([("k".into(), room)]), ..Scan::default() });
        assert!(!usage.scanning() && !usage.stale(60_000));
        usage.update_room("k", Some(Room { bytes: 40, rebuild: vec![] }));
        assert_eq!(usage.last().unwrap().parts[0].bytes, 90);
        usage.update_room("k", None);
        assert_eq!(usage.last().unwrap().parts[0].bytes, 50);
        assert!(usage.last().unwrap().rooms.is_empty());
    }

    #[test]
    fn what_can_be_made_again() {
        let root = tempfile::tempdir().unwrap();
        let p = root.path();
        write(&p.join("android/build.gradle.kts"), 1);
        write(&p.join("android/settings.gradle.kts"), 1);
        assert!(rebuildable(&p.join("x/node_modules")) && rebuildable(&p.join("android/build")) && rebuildable(&p.join("android/.gradle")));
        assert!(!rebuildable(&p.join("site/build")) && !rebuildable(&p.join("site/target")) && !rebuildable(&p.join("dist")));
    }
}
