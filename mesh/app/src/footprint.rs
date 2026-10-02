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
    let sessions = data_dir.join("sessions").canonicalize().ok()?;
    let workspace = Path::new(workspace);
    let workspace = match workspace.canonicalize() {
        Ok(path) => path,
        Err(_) if workspace.file_name()? == "workspace" => workspace.parent()?.canonicalize().ok()?.join("workspace"),
        Err(_) => return None,
    };
    let relative = workspace.strip_prefix(&sessions).ok()?;
    // Only the station layout sessions/<connect>/<session>/workspace, never an arbitrary nested project.
    if relative.components().count() != 3 || workspace.file_name()? != "workspace" {
        return None;
    }
    workspace.parent().map(Path::to_path_buf)
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

/// Even a generated-looking directory may contain tracked source. If Git cannot inspect a repository, keep it.
/// Standalone generated directories (e.g. a screenshot script's node_modules) do not need a Git repository.
pub fn safe_to_remove(path: &Path) -> bool {
    if !std::fs::symlink_metadata(path).is_ok_and(|m| m.is_dir()) || !rebuildable(path) {
        return false;
    }
    let Some(parent) = path.parent() else { return false };
    if !parent.ancestors().any(|p| p.join(".git").exists()) {
        return true;
    }
    std::process::Command::new("git")
        .arg("-C").arg(parent).args(["ls-files", "--"]).arg(path.file_name().unwrap())
        .output().is_ok_and(|out| out.status.success() && out.stdout.is_empty())
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
        // Never discover cleanup candidates in repository metadata or historical attachments.
        if found.is_some() && matches!(entry.file_name().to_str(), Some(".git" | "uploads")) {
            bytes += measure(&child, seen, None);
            continue;
        }
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
    #[test]
    fn archive_cleanup_keeps_attachments_git_and_symlink_targets() {
        let root = tempfile::tempdir().unwrap();
        let p = root.path();
        write(&p.join("uploads/node_modules/evidence.js"), 100);
        write(&p.join(".git/node_modules/metadata"), 100);
        write(&p.join("app/node_modules/dependency.js"), 100);
        let outside = tempfile::tempdir().unwrap();
        write(&outside.path().join("node_modules/source"), 100);
        std::os::unix::fs::symlink(outside.path(), p.join("linked")).unwrap();
        let found = measure_room(p).rebuild;
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].0, p.join("app/node_modules"));
        let data = p.join("data");
        let workspace = data.join("sessions/cl/chat/workspace");
        std::fs::create_dir_all(&workspace).unwrap();
        assert!(room_of(&data, workspace.to_str().unwrap()).is_some());
        std::os::unix::fs::symlink(outside.path(), data.join("sessions/cl/escape")).unwrap();
        std::fs::create_dir_all(outside.path().join("workspace")).unwrap();
        assert!(room_of(&data, data.join("sessions/cl/escape/workspace").to_str().unwrap()).is_none());
    }

    #[test]
    fn archive_cleanup_keeps_tracked_files_in_generated_directories() {
        let root = tempfile::tempdir().unwrap();
        let p = root.path();
        let git = |args: &[&str]| {
            assert!(std::process::Command::new("git").arg("-C").arg(p).args(args).output().unwrap().status.success());
        };
        git(&["init", "-q"]);
        write(&p.join("node_modules/local-source.js"), 100);
        git(&["add", "node_modules/local-source.js"]);
        assert!(!safe_to_remove(&p.join("node_modules")));
        write(&p.join("scratch/node_modules/dependency.js"), 100);
        assert!(safe_to_remove(&p.join("scratch/node_modules")));
    }

}
