//! The shared agent home: one MEMORY.md and one skills/ directory used by every profile of both runtimes. It lives in
//! the data dir, not the repository, since it holds team-specific memory. Each profile home links to it under the name
//! its runtime loads automatically. (src/agent-home.ts)

use std::path::{Path, PathBuf};

use anyhow::Result;
use ember_shapes::RuntimeKind;
use tracing::warn;

pub fn agent_home_paths(agent_home: &Path) -> (PathBuf, PathBuf) {
    (agent_home.join("MEMORY.md"), agent_home.join("skills"))
}

/// Creates the agent home if missing and links it into every profile home (id, runtimes, home).
pub fn link_agent_home(agent_home: &Path, profiles: &[(&str, &[RuntimeKind], &Path)]) -> Result<()> {
    let (memory, skills) = agent_home_paths(agent_home);
    std::fs::create_dir_all(&skills)?;
    if !memory.exists() {
        std::fs::write(&memory, "# ember memory\n")?;
    }
    for (_, runtimes, home) in profiles {
        std::fs::create_dir_all(home)?;
        // Each runtime it runs reads the memory under its own name.
        for runtime in *runtimes {
            link(&memory, &home.join(if *runtime == RuntimeKind::Claude { "CLAUDE.md" } else { "AGENTS.md" }))?;
        }
        link(&skills, &home.join("skills"))?;
    }
    Ok(())
}

/// One place for each runtime's transcripts, shared by every profile that runs it: a session is the station's, not an
/// account's, so any account can take it on (another, when one's quota is used up) with all it had. Each profile home's
/// transcript directory (Claude Code's projects/, Codex's sessions/) is a link there. A real directory in its place is
/// left alone, with a warning (the profile then keeps its own).
pub fn link_transcripts(data_dir: &Path, profiles: &[(&str, &[RuntimeKind], &Path)]) -> Result<()> {
    for (id, runtimes, home) in profiles {
        for runtime in *runtimes {
            let shared = data_dir.join("transcripts").join(crate::config::runtime_name(*runtime));
            std::fs::create_dir_all(&shared)?;
            std::fs::create_dir_all(home)?;
            let path = home.join(if *runtime == RuntimeKind::Claude { "projects" } else { "sessions" });
            if !path.exists() && !is_link(&path) {
                std::os::unix::fs::symlink(&shared, &path)?;
            } else if !is_link(&path) || std::fs::read_link(&path).ok().as_deref() != Some(shared.as_path()) {
                warn!(profile = id, path = %path.display(), "a profile's transcripts are not in the shared place");
            }
        }
    }
    Ok(())
}

fn is_link(path: &Path) -> bool {
    std::fs::symlink_metadata(path).map(|m| m.file_type().is_symlink()).unwrap_or(false)
}

fn link(target: &Path, path: &Path) -> Result<()> {
    match std::fs::symlink_metadata(path) {
        Err(_) => std::os::unix::fs::symlink(target, path)?,
        Ok(meta) if meta.file_type().is_symlink() && std::fs::read_link(path).ok().as_deref() == Some(target) => {}
        // A real file or a different link: someone configured it by hand. Leave it and say so.
        Ok(_) => warn!(path = %path.display(), target = %target.display(), "not linking the agent home over an existing path"),
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use RuntimeKind::{Claude, Codex};

    #[test]
    fn profile_homes_link_to_the_shared_memory_and_skills_under_their_runtimes_names() {
        let root = tempfile::tempdir().unwrap();
        let agent = root.path().join("agent");
        let (cc, cx, both) = (root.path().join("cc"), root.path().join("cx"), root.path().join("both"));
        let profiles: [(&str, &[RuntimeKind], &Path); 3] = [("cc", &[Claude], &cc), ("cx", &[Codex], &cx), ("both", &[Claude, Codex], &both)];
        link_agent_home(&agent, &profiles).unwrap();
        link_agent_home(&agent, &profiles).unwrap(); // idempotent
        let read = |p: PathBuf| std::fs::read_link(p).unwrap();
        assert_eq!(read(cc.join("CLAUDE.md")), agent.join("MEMORY.md"));
        assert_eq!(read(cc.join("skills")), agent.join("skills"));
        assert_eq!(read(cx.join("AGENTS.md")), agent.join("MEMORY.md"));
        // An account run on both reads the memory under both names.
        assert_eq!(read(both.join("CLAUDE.md")), agent.join("MEMORY.md"));
        assert_eq!(read(both.join("AGENTS.md")), agent.join("MEMORY.md"));
    }

    #[test]
    fn a_hand_written_file_in_a_profile_home_is_left_alone() {
        let root = tempfile::tempdir().unwrap();
        let cc = root.path().join("cc");
        std::fs::create_dir(&cc).unwrap();
        std::fs::write(cc.join("CLAUDE.md"), "mine").unwrap();
        link_agent_home(&root.path().join("agent"), &[("cc", &[Claude], &cc)]).unwrap();
        assert_eq!(std::fs::read_to_string(cc.join("CLAUDE.md")).unwrap(), "mine");
    }

    #[test]
    fn every_profiles_transcripts_are_a_runtimes_one_shared_place() {
        let root = tempfile::tempdir().unwrap();
        let (both, own) = (root.path().join("both"), root.path().join("own"));
        std::fs::create_dir_all(own.join("sessions")).unwrap();
        link_transcripts(root.path(), &[("both", &[Claude, Codex], &both), ("own", &[Codex], &own)]).unwrap();
        assert_eq!(std::fs::read_link(both.join("projects")).unwrap(), root.path().join("transcripts/claude"));
        assert_eq!(std::fs::read_link(both.join("sessions")).unwrap(), root.path().join("transcripts/codex"));
        assert!(std::fs::symlink_metadata(own.join("sessions")).unwrap().is_dir());
    }
}
