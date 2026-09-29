//! What the station was called before it was still.fail (ember), and moving an install made under that name
//! (docs/rename-still-fail.md). A machine updated from ember has its data in ~/.ember: the first start of this station
//! moves it to ~/.stillfail and leaves a link at the old place, so the paths written down under it (in config.json, the
//! store, the agents' own files, scripts) still lead there. With both there, the new one is used and the old one left.
//! Its variables are read under the new names (STILLFAIL_*), else the old ones (EMBER_*).
//!
//! What is kept by a path's name, not the path, is carried over too: Claude Code's transcripts, in projects/<the cwd
//! with every other character than a letter or digit a dash>, get a link under the new cwd's name (so a session begun
//! under ~/.ember resumes), and a profile's login that Claude Code left in the keychain under the old home's name is
//! found (no_keychain::take_back).

use std::path::{Path, PathBuf};

use tracing::{info, warn};

/// The data directory under the home, and what it was.
pub const DATA_DIR: &str = ".stillfail";
pub const FORMER_DATA_DIR: &str = ".ember";

/// Environment variables' prefix, and what it was.
pub const PREFIX: &str = "STILLFAIL_";
pub const FORMER_PREFIX: &str = "EMBER_";

/// `name` (without its prefix, as "DATA") as `env` has it: STILLFAIL_DATA, else EMBER_DATA. Empty is unset.
pub fn var_in(env: impl Fn(&str) -> Option<String>, name: &str) -> Option<String> {
    [PREFIX, FORMER_PREFIX].iter().find_map(|p| env(&format!("{p}{name}")).filter(|v| !v.is_empty()))
}

/// `name` (without its prefix) from this process's environment: STILLFAIL_<name>, else EMBER_<name>.
pub fn var(name: &str) -> Option<String> {
    var_in(|k| std::env::var(k).ok(), name)
}

/// Both names of a variable the station sets for what it starts (jobs, runtimes): the new one, and the old one for
/// scripts written against it.
pub fn both(name: &str) -> [String; 2] {
    [format!("{PREFIX}{name}"), format!("{FORMER_PREFIX}{name}")]
}

/// The data directory: `given` (--data, or the variable), else ~/.stillfail. ~/.ember, given or found there, is taken
/// for the default and moved (move_data); a directory given elsewhere is used as it is.
pub fn data_dir(home: &Path, given: Option<PathBuf>) -> PathBuf {
    let (new, old) = (home.join(DATA_DIR), home.join(FORMER_DATA_DIR));
    match given {
        Some(dir) if !same(&dir, &new) && !same(&dir, &old) => dir,
        _ => move_data(&old, &new),
    }
}

fn same(a: &Path, b: &Path) -> bool {
    a.components().eq(b.components())
}

fn exists(path: &Path) -> bool {
    std::fs::symlink_metadata(path).is_ok()
}

/// Moves `old` to `new` and links `old` to it, once: with `new` there (or no `old`) nothing moves; an empty `new` (made
/// by something that ran first) does not count. Not while a station runs `old` (it holds run/station.lock): `old` is
/// then answered, and whoever starts the station finds it held. Answers the directory to use.
pub fn move_data(old: &Path, new: &Path) -> PathBuf {
    if !exists(old) || is_link_to(old, new) || (exists(new) && !empty_dir(new)) {
        return new.to_path_buf();
    }
    if held(&old.join("run").join("station.lock")) {
        warn!(dir = %old.display(), "a station runs the old data directory; not moving it now");
        return old.to_path_buf();
    }
    if exists(new) {
        let _ = std::fs::remove_dir(new);
    }
    if let Err(error) = std::fs::rename(old, new) {
        warn!(%error, from = %old.display(), to = %new.display(), "the data directory could not be moved; staying where it is");
        return old.to_path_buf();
    }
    match std::os::unix::fs::symlink(new, old) {
        Ok(()) => info!(from = %old.display(), to = %new.display(), "data directory moved (a link stays at the old place)"),
        Err(error) => warn!(%error, from = %old.display(), to = %new.display(), "data directory moved, but no link left at the old place"),
    }
    new.to_path_buf()
}

/// A directory with nothing in it (not a link to one).
fn empty_dir(path: &Path) -> bool {
    std::fs::symlink_metadata(path).is_ok_and(|m| m.is_dir()) && std::fs::read_dir(path).is_ok_and(|mut entries| entries.next().is_none())
}

fn is_link_to(link: &Path, to: &Path) -> bool {
    std::fs::read_link(link).is_ok_and(|target| same(&target, to))
}

/// Whether another process holds `lock` (flock), as a running station holds its run/station.lock.
fn held(lock: &Path) -> bool {
    let Ok(file) = std::fs::OpenOptions::new().write(true).open(lock) else { return false };
    let fd = std::os::fd::AsRawFd::as_raw_fd(&file);
    // SAFETY: flock on a descriptor this function owns; dropping the file lets it go.
    unsafe { libc::flock(fd, libc::LOCK_EX | libc::LOCK_NB) != 0 }
}

/// Where `path` was before the data directory moved: under ~/.ember for a path under ~/.stillfail.
pub fn former_path(home: &Path, path: &Path) -> Option<PathBuf> {
    path.strip_prefix(home.join(DATA_DIR)).ok().map(|rest| home.join(FORMER_DATA_DIR).join(rest))
}

/// The home directory, as the station's environment says.
pub fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("."))
}

/// A cwd as Claude Code names its transcripts' directory after it: every character other than a letter or digit a dash.
pub fn claude_project(path: &Path) -> String {
    path.to_string_lossy().chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '-' }).collect()
}

/// Links, in Claude Code's transcript directories under `data` (the shared transcripts/claude and a profile's own
/// projects/), each project named after a cwd under `old` under the name the same cwd has under `data`: a session begun
/// under ~/.ember is found by `claude --resume` from ~/.stillfail. Once the data directory moved (the old place is a link
/// to it, or the installer, not able to move it, made the new place a link to the old); the links are made again when
/// missing, and nothing else is touched.
pub fn link_claude_projects(data: &Path, old: &Path) {
    if !is_link_to(old, data) && !is_link_to(data, old) {
        return;
    }
    let (from, to) = (claude_project(old), claude_project(data));
    let mut dirs = vec![data.join("transcripts").join("claude")];
    for home in std::fs::read_dir(data.join("homes")).into_iter().flatten().flatten() {
        let projects = home.path().join("projects");
        if std::fs::symlink_metadata(&projects).is_ok_and(|m| m.is_dir()) {
            dirs.push(projects);
        }
    }
    for dir in dirs {
        for entry in std::fs::read_dir(&dir).into_iter().flatten().flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            let Some(rest) = name.strip_prefix(&from).filter(|rest| rest.is_empty() || rest.starts_with('-')) else { continue };
            let alias = dir.join(format!("{to}{rest}"));
            if !exists(&alias) {
                if let Err(error) = std::os::unix::fs::symlink(&name, &alias) {
                    warn!(%error, project = name, "a transcript directory could not be linked under the new data directory's name");
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn variables_are_read_under_the_new_name_else_the_old() {
        let env = |pairs: &'static [(&'static str, &'static str)]| move |k: &str| pairs.iter().find(|(n, _)| *n == k).map(|(_, v)| v.to_string());
        assert_eq!(var_in(env(&[("STILLFAIL_DATA", "/new"), ("EMBER_DATA", "/old")]), "DATA").as_deref(), Some("/new"));
        assert_eq!(var_in(env(&[("EMBER_DATA", "/old")]), "DATA").as_deref(), Some("/old"));
        assert_eq!(var_in(env(&[("STILLFAIL_DATA", ""), ("EMBER_DATA", "/old")]), "DATA").as_deref(), Some("/old"));
        assert_eq!(var_in(env(&[]), "DATA"), None);
        assert_eq!(both("JOB_ID"), ["STILLFAIL_JOB_ID".to_string(), "EMBER_JOB_ID".to_string()]);
    }

    #[test]
    fn the_old_data_directory_moves_once_and_leaves_a_link() {
        let home = tempfile::tempdir().unwrap();
        let (old, new) = (home.path().join(".ember"), home.path().join(".stillfail"));
        std::fs::create_dir_all(old.join("mesh")).unwrap();
        std::fs::write(old.join("config.json"), "{}").unwrap();
        std::fs::write(old.join("mesh").join("cloud.json"), "{\"origin\":\"x\"}").unwrap();

        assert_eq!(data_dir(home.path(), None), new);
        assert!(std::fs::symlink_metadata(&new).unwrap().is_dir());
        assert_eq!(std::fs::read_link(&old).unwrap(), new);
        // What was written down under the old path still reads.
        assert_eq!(std::fs::read_to_string(old.join("mesh").join("cloud.json")).unwrap(), "{\"origin\":\"x\"}");
        assert_eq!(std::fs::read_to_string(new.join("config.json")).unwrap(), "{}");

        // Again (and given the old path, as an old service or launcher gives it): nothing moves.
        assert_eq!(data_dir(home.path(), Some(old.clone())), new);
        assert_eq!(data_dir(home.path(), Some(new.clone())), new);
        assert_eq!(std::fs::read_link(&old).unwrap(), new);
    }

    #[test]
    fn with_both_there_the_new_one_is_used_and_the_old_one_left() {
        let home = tempfile::tempdir().unwrap();
        let (old, new) = (home.path().join(".ember"), home.path().join(".stillfail"));
        std::fs::create_dir_all(&old).unwrap();
        std::fs::create_dir_all(&new).unwrap();
        std::fs::write(old.join("config.json"), "old").unwrap();
        std::fs::write(new.join("config.json"), "new").unwrap();
        assert_eq!(data_dir(home.path(), None), new);
        assert!(std::fs::symlink_metadata(&old).unwrap().is_dir());
        assert_eq!(std::fs::read_to_string(old.join("config.json")).unwrap(), "old");
        assert_eq!(std::fs::read_to_string(new.join("config.json")).unwrap(), "new");
    }

    #[test]
    fn an_empty_new_directory_made_first_does_not_keep_the_old_one_from_moving() {
        let home = tempfile::tempdir().unwrap();
        let (old, new) = (home.path().join(".ember"), home.path().join(".stillfail"));
        std::fs::create_dir_all(&old).unwrap();
        std::fs::write(old.join("config.json"), "{}").unwrap();
        std::fs::create_dir_all(&new).unwrap();
        assert_eq!(data_dir(home.path(), None), new);
        assert_eq!(std::fs::read_to_string(new.join("config.json")).unwrap(), "{}");
        assert_eq!(std::fs::read_link(&old).unwrap(), new);
    }

    #[test]
    fn a_fresh_machine_gets_the_new_directory_and_a_given_one_is_its_own() {
        let home = tempfile::tempdir().unwrap();
        assert_eq!(data_dir(home.path(), None), home.path().join(".stillfail"));
        assert!(!home.path().join(".ember").exists());
        std::fs::create_dir_all(home.path().join(".ember")).unwrap();
        let elsewhere = home.path().join("station-data");
        assert_eq!(data_dir(home.path(), Some(elsewhere.clone())), elsewhere);
        assert!(std::fs::symlink_metadata(home.path().join(".ember")).unwrap().is_dir());
    }

    #[test]
    fn not_moved_from_under_a_running_station() {
        let home = tempfile::tempdir().unwrap();
        let old = home.path().join(".ember");
        std::fs::create_dir_all(old.join("run")).unwrap();
        let lock = std::fs::OpenOptions::new().create(true).truncate(false).write(true).open(old.join("run").join("station.lock")).unwrap();
        // SAFETY: flock on a descriptor the test owns.
        assert_eq!(unsafe { libc::flock(std::os::fd::AsRawFd::as_raw_fd(&lock), libc::LOCK_EX | libc::LOCK_NB) }, 0);
        assert_eq!(data_dir(home.path(), None), old);
        assert!(!home.path().join(".stillfail").exists());
        drop(lock);
        assert_eq!(data_dir(home.path(), None), home.path().join(".stillfail"));
        assert_eq!(std::fs::read_link(&old).unwrap(), home.path().join(".stillfail"));
    }

    #[test]
    fn paths_under_the_new_directory_have_their_former_place() {
        let home = Path::new("/Users/a");
        assert_eq!(former_path(home, Path::new("/Users/a/.stillfail/homes/cc")), Some(PathBuf::from("/Users/a/.ember/homes/cc")));
        assert_eq!(former_path(home, Path::new("/Users/a/elsewhere/cc")), None);
    }

    #[test]
    fn claude_sessions_begun_under_the_old_directory_are_found_under_the_new_ones_name() {
        let home = tempfile::tempdir().unwrap();
        let (old, new) = (home.path().join(".ember"), home.path().join(".stillfail"));
        let claude = old.join("transcripts").join("claude");
        let cwd = old.join("sessions").join("ember").join("c-1").join("workspace");
        let project = claude.join(claude_project(&cwd));
        std::fs::create_dir_all(&project).unwrap();
        std::fs::write(project.join("s1.jsonl"), "{}\n").unwrap();
        // A project of somewhere else, and a profile's own projects/ with one of the data directory's.
        std::fs::create_dir_all(claude.join("-Users-a-code-x")).unwrap();
        let own = old.join("homes").join("p1").join("projects");
        std::fs::create_dir_all(own.join(claude_project(&old.join("sessions").join("k")))).unwrap();

        // Not moved yet: nothing to link.
        link_claude_projects(&old, &old);
        assert_eq!(std::fs::read_dir(&claude).unwrap().count(), 2);

        assert_eq!(data_dir(home.path(), None), new);
        link_claude_projects(&new, &old);
        let moved = new.join("sessions").join("ember").join("c-1").join("workspace");
        let alias = new.join("transcripts").join("claude").join(claude_project(&moved));
        assert_eq!(std::fs::read_to_string(alias.join("s1.jsonl")).unwrap(), "{}\n");
        assert!(std::fs::symlink_metadata(&alias).unwrap().file_type().is_symlink());
        assert!(new.join("homes").join("p1").join("projects").join(claude_project(&new.join("sessions").join("k"))).is_dir());
        // Others are left; again, nothing more.
        assert_eq!(std::fs::read_dir(new.join("transcripts").join("claude")).unwrap().count(), 3);
        link_claude_projects(&new, &old);
        assert_eq!(std::fs::read_dir(new.join("transcripts").join("claude")).unwrap().count(), 3);
    }
}
