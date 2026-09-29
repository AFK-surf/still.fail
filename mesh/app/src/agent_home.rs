//! The shared agent home: one MEMORY.md and one skills/ directory used by every profile of both runtimes. It lives in
//! the data dir, not the repository, since it holds team-specific memory. Each profile home links to it under the name
//! its runtime loads automatically.

use std::path::{Path, PathBuf};

use anyhow::Result;
use ember_shapes::RuntimeKind;
use tracing::warn;

pub fn agent_home_paths(agent_home: &Path) -> (PathBuf, PathBuf) {
    (agent_home.join("MEMORY.md"), agent_home.join("skills"))
}

/// The skills the station brings, by directory name: about its own tools, so they are rewritten at every start and
/// change with the station (the team's own skills sit beside them).
const BUILTIN_SKILLS: &[(&str, &str)] =
    &[("ember-jobs", include_str!("skills/ember-jobs.md")), ("ember-viz", include_str!("skills/ember-viz.md"))];

/// Writes the station's own skills into the shared skills directory.
pub fn write_builtin_skills(agent_home: &Path) -> Result<()> {
    let (_, skills) = agent_home_paths(agent_home);
    for (name, text) in BUILTIN_SKILLS {
        let dir = skills.join(name);
        std::fs::create_dir_all(&dir)?;
        let path = dir.join("SKILL.md");
        if std::fs::read_to_string(&path).ok().as_deref() != Some(*text) {
            std::fs::write(&path, text)?;
        }
    }
    Ok(())
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

/// A skill in the shared skills directory as the pages show it: its name (its directory), what its SKILL.md says it is
/// for, whether it is a project's memory (its description says so), and whether it is the station's own (rewritten at
/// every start, so not edited on the pages).
#[derive(serde::Serialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SkillFile {
    pub name: String,
    pub description: String,
    pub project: bool,
    pub builtin: bool,
    pub text: String,
}

/// What a project memory's description starts with.
pub const PROJECT_PREFIX: &str = "项目记忆：";

/// A SKILL.md's frontmatter field (`key: value`), if it has one.
fn front(text: &str, key: &str) -> Option<String> {
    let body = text.strip_prefix("---\n")?;
    let end = body.find("\n---")?;
    body[..end].lines().find_map(|line| line.strip_prefix(&format!("{key}:")).map(|v| v.trim().trim_matches('"').to_string()))
}

/// The shared skills, by name: the team's and the station's own.
pub fn list_skills(agent_home: &Path) -> Vec<SkillFile> {
    let (_, dir) = agent_home_paths(agent_home);
    let mut skills: Vec<SkillFile> = std::fs::read_dir(&dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().to_string_lossy().to_string();
            let text = std::fs::read_to_string(entry.path().join("SKILL.md")).ok()?;
            let description = front(&text, "description").unwrap_or_default();
            Some(SkillFile {
                project: description.starts_with(PROJECT_PREFIX),
                builtin: BUILTIN_SKILLS.iter().any(|(n, _)| *n == name),
                name,
                description,
                text,
            })
        })
        .collect();
    skills.sort_by(|a, b| (a.builtin, !a.project, a.name.clone()).cmp(&(b.builtin, !b.project, b.name.clone())));
    skills
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

    #[test]
    fn the_stations_own_skills_are_written_and_kept_as_the_station_has_them() {
        let dir = tempfile::tempdir().unwrap();
        let home = dir.path().join("agent");
        std::fs::create_dir_all(home.join("skills").join("team-skill")).unwrap();
        std::fs::write(home.join("skills").join("team-skill").join("SKILL.md"), "ours").unwrap();
        write_builtin_skills(&home).unwrap();
        let path = home.join("skills").join("ember-jobs").join("SKILL.md");
        assert!(std::fs::read_to_string(&path).unwrap().starts_with("---\nname: ember-jobs\n"));
        std::fs::write(&path, "edited by hand").unwrap();
        write_builtin_skills(&home).unwrap();
        assert!(std::fs::read_to_string(&path).unwrap().contains("job_start"), "the station's own, as it has it");
        assert_eq!(std::fs::read_to_string(home.join("skills").join("team-skill").join("SKILL.md")).unwrap(), "ours", "the team's stay");
    }

    #[test]
    fn skills_are_listed_with_what_they_are_for_and_projects_memories_told_apart() {
        let dir = tempfile::tempdir().unwrap();
        let home = dir.path().join("agent");
        write_builtin_skills(&home).unwrap();
        let write = |name: &str, text: &str| {
            std::fs::create_dir_all(home.join("skills").join(name)).unwrap();
            std::fs::write(home.join("skills").join(name).join("SKILL.md"), text).unwrap();
        };
        write("发版", "---\nname: 发版\ndescription: 项目记忆：每周发版时使用。\n---\n\n- 周四发\n");
        write("pdf", "---\nname: pdf\ndescription: Reading PDFs.\n---\n");
        let skills = list_skills(&home);
        let names: Vec<(String, bool, bool)> = skills.iter().map(|s| (s.name.clone(), s.project, s.builtin)).collect();
        assert_eq!(names, [("发版".into(), true, false), ("pdf".into(), false, false), ("ember-jobs".into(), false, true), ("ember-viz".into(), false, true)]);
        assert_eq!(skills[0].description, "项目记忆：每周发版时使用。");
    }
}
