//! Workspace file helpers for automatic cleanup of archived sessions.

use std::collections::HashSet;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

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

#[cfg(test)]
mod tests {
    use super::*;

    fn write(path: &Path, bytes: usize) {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, vec![7u8; bytes]).unwrap();
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
    fn what_can_be_made_again() {
        let root = tempfile::tempdir().unwrap();
        let p = root.path();
        write(&p.join("android/build.gradle.kts"), 1);
        write(&p.join("android/settings.gradle.kts"), 1);
        assert!(rebuildable(&p.join("x/node_modules")) && rebuildable(&p.join("android/build")) && rebuildable(&p.join("android/.gradle")));
        assert!(!rebuildable(&p.join("site/build")) && !rebuildable(&p.join("site/target")) && !rebuildable(&p.join("dist")));
    }
}
