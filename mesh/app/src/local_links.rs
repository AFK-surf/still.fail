//! Local Markdown destinations are files to deliver, not routes on the web client.
use std::path::{Path, PathBuf};

use anyhow::{Result, anyhow, bail};
use pulldown_cmark::{Event, LinkType, Parser, Tag};

/// Resolve only file URLs, familiar machine roots, or paths that actually name a local file.
/// In particular, station routes (/o/…, /chats/…) and protocol-relative web URLs stay web links.
fn local_path(destination: &str) -> Result<Option<PathBuf>> {
    let decoded = percent_encoding::percent_decode_str(destination).decode_utf8_lossy();
    let path = if destination.starts_with("file:") {
        reqwest::Url::parse(destination).ok().and_then(|u| u.to_file_path().ok())
            .ok_or_else(|| anyhow!("invalid local file link: {destination}; use an absolute path in files"))?
    } else {
        if !decoded.starts_with('/') || decoded.starts_with("//") { return Ok(None); }
        let known = ["/Users/", "/home/", "/tmp/", "/private/", "/var/", "/Volumes/", "/mnt/", "/workspace/", "/etc/", "/opt/"];
        if !known.iter().any(|root| decoded.starts_with(root)) && !Path::new(decoded.as_ref()).is_file() { return Ok(None); }
        PathBuf::from(decoded.as_ref())
    };
    if path.is_file() { return Ok(Some(path)); }
    // Codex commonly emits /path/file.rs:12 or /path/file.rs:12:3.
    let raw = path.to_string_lossy();
    let mut base = raw.as_ref();
    for _ in 0..2 {
        let Some((head, tail)) = base.rsplit_once(':') else { break };
        if tail.is_empty() || !tail.bytes().all(|c| c.is_ascii_digit()) { break; }
        base = head;
        if Path::new(base).is_file() { return Ok(Some(PathBuf::from(base))); }
    }
    bail!("local file link does not name a readable file: {destination}; correct the path or write it as code instead of a link")
}

/// Keep ordinary prose and code untouched. Make actual local links refer to immutable message attachments.
/// Run before posting anything so a missing/ambiguous attachment can be corrected by the agent.
pub fn prepare(text: &str, paths: &mut Vec<String>, workspace: &Path) -> Result<String> {
    let mut replacements = Vec::new();
    for (event, range) in Parser::new(text).into_offset_iter() {
        let (kind, destination) = match event {
            Event::Start(Tag::Link { link_type, dest_url, .. } | Tag::Image { link_type, dest_url, .. }) => (link_type, dest_url),
            _ => continue,
        };
        let Some(path) = local_path(&destination)? else { continue };
        if kind != LinkType::Inline {
            bail!("local file link {destination} must use inline Markdown: [label](path); it will be attached automatically");
        }
        let source = &text[range.clone()];
        let start = source.match_indices(destination.as_ref()).find_map(|(start, _)| {
            let before = source[..start].trim_end().trim_end_matches('<').trim_end();
            before.ends_with("](").then_some(start)
        }).ok_or_else(|| anyhow!("write local file link {destination} without Markdown escapes (use <…> around paths with spaces)"))?;
        let canonical = path.canonicalize()?;
        if !paths.iter().any(|p| workspace.join(p).canonicalize().ok().as_ref() == Some(&canonical)) {
            paths.push(path.to_string_lossy().into_owned());
        }
        let name = path.file_name().ok_or_else(|| anyhow!("not a file: {}", path.display()))?.to_string_lossy();
        // A plain encoded basename works with existing web and Android clients, including spaces and parentheses.
        let name = percent_encoding::utf8_percent_encode(&name, percent_encoding::NON_ALPHANUMERIC).to_string();
        replacements.push((range.start + start..range.start + start + destination.len(), name));
    }
    // Both clients identify attachments by name; different files with one name must never silently overwrite.
    let mut names = std::collections::HashMap::new();
    for path in paths.iter() {
        let path = workspace.join(path);
        let canonical = path.canonicalize()?;
        if let Some(name) = path.file_name() {
            if let Some(previous) = names.insert(name.to_os_string(), canonical.clone()) {
                if previous != canonical { bail!("attachments have the same name: {}; rename the files before posting", name.to_string_lossy()); }
            }
        }
    }
    let mut result = text.to_string();
    replacements.sort_by_key(|(r, _)| r.start);
    for (range, name) in replacements.into_iter().rev() { result.replace_range(range, &name); }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn delivers_local_links_and_images_once_and_preserves_code_and_web_links() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("a report(1).txt");
        std::fs::write(&path, "report").unwrap();
        let path = path.display();
        let text = format!("[报告](<{path}>) ![](<file://{path}>) [line](<{path}:12:3>)\n`[example](/tmp/missing)`\n```md\n[x](/tmp/missing)\n```\n[web](https://example.com/a) [chat](/o/ws/st/chat) [cdn](//example.com/a)");
        let mut paths = vec![];
        let result = prepare(&text, &mut paths, dir.path()).unwrap();
        assert_eq!(paths.len(), 1);
        assert!(result.starts_with("[报告](<a%20report%281%29%2Etxt>) ![](<a%20report%281%29%2Etxt>) [line](<a%20report%281%29%2Etxt>)"), "{result}");
        assert!(result.contains("`[example](/tmp/missing)`\n```md\n[x](/tmp/missing)\n```"));
        assert!(result.ends_with("[web](https://example.com/a) [chat](/o/ws/st/chat) [cdn](//example.com/a)"));
    }

    #[test]
    fn explicit_files_are_reused_and_missing_or_colliding_files_are_rejected() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("report.txt");
        std::fs::write(&file, "one").unwrap();
        let mut paths = vec!["report.txt".into()];
        prepare(&format!("[report]({})", file.display()), &mut paths, dir.path()).unwrap();
        assert_eq!(paths.len(), 1);
        assert!(prepare("[missing](/tmp/stillfail-no-such-report.txt)", &mut vec![], dir.path()).unwrap_err().to_string().contains("correct the path"));
        std::fs::create_dir(dir.path().join("other")).unwrap();
        let other = dir.path().join("other/report.txt");
        std::fs::write(&other, "two").unwrap();
        assert!(prepare(&format!("[report]({})", other.display()), &mut paths, dir.path()).unwrap_err().to_string().contains("same name"));
    }
}
