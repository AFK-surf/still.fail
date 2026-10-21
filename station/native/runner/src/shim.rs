//! What a Windows `.cmd` shim runs, read from its text (sys/windows.rs's `unshim` goes around cmd with it): here, not
//! there, so that its cases are tried on any machine. As station/src/platform/windows.ts's `readShim`.

#![cfg_attr(not(windows), allow(dead_code))]

/// A path as a shim names it.
#[derive(Debug, PartialEq)]
pub enum Named<'a> {
    /// In the shim's own directory, under it: `%dp0%\…` (npm's), `%~dp0\…` (pnpm's).
    Beside(&'a str),
    /// As written.
    At(&'a str),
}

#[derive(Debug, PartialEq)]
pub enum Runs<'a> {
    /// A script, with Node (beside the shim, or on PATH): npm's and pnpm's shims for a JS command
    /// (`"%_prog%" "%dp0%\…\cli.js" %*`, `"%~dp0\node.exe" "%~dp0\…\cli.js" %*`).
    Node(Named<'a>),
    /// A program, given the arguments: npm's and pnpm's shims for a command that is a binary (Claude Code's
    /// `"%dp0%\…\bin\claude.exe" %*`), or one that only hands on to another `.cmd` (Vite+'s).
    Program(Named<'a>),
}

/// The lines around what an npm or pnpm shim runs (cmd-shim's), case aside, an `@` before them aside.
const FRAME: [&str; 7] = ["echo off", "goto start", ":find_dp0", "set dp0=%~dp0", ":start", "setlocal", "call :find_dp0"];

/// What `text`, a shim's, runs with the arguments it is given (`%*`, last); None for a shim of any other kind, which
/// cmd has to run.
pub fn read(text: &str) -> Option<Runs<'_>> {
    let lines: Vec<&str> = text.lines().map(|l| l.trim()).filter(|l| !l.is_empty()).collect();
    for line in &lines {
        let Some((before, script)) = last_quoted(line) else { continue };
        let before = before.trim_end();
        if before.ends_with("\"%_prog%\"") || before.ends_with("node.exe\"") || before.ends_with(" node") || before == "node" {
            return Some(Runs::Node(named(script)));
        }
    }
    let lines: Vec<&str> = lines
        .into_iter()
        .map(|l| l.strip_prefix('@').unwrap_or(l))
        .filter(|l| {
            let l = l.to_ascii_lowercase();
            !FRAME.contains(&l.as_str()) && !l.starts_with("exit /b")
        })
        .collect();
    let [line] = lines.as_slice() else { return None };
    match last_quoted(line)? {
        ("", program) => Some(Runs::Program(named(program))),
        _ => None,
    }
}

/// A line ending `"<path>" %*`: what comes before the quoted path, and the path, when nothing in it is left for cmd
/// to expand (`%USERPROFILE%\…`) but the shim's directory.
fn last_quoted(line: &str) -> Option<(&str, &str)> {
    let rest = line.strip_suffix("%*")?.trim_end().strip_suffix('"')?;
    let open = rest.rfind('"')?;
    let path = &rest[open + 1..];
    let own = ["%dp0%", "%~dp0"].iter().find_map(|p| path.strip_prefix(p)).unwrap_or(path);
    (!own.contains('%')).then_some((&rest[..open], path))
}

fn named(path: &str) -> Named<'_> {
    ["%dp0%\\", "%~dp0\\", "%dp0%", "%~dp0"]
        .iter()
        .find_map(|p| path.strip_prefix(p))
        .map_or(Named::At(path), Named::Beside)
}

#[cfg(test)]
mod tests {
    use super::*;

    // As cmd-shim (npm's) and @zkochan/cmd-shim (pnpm's) write them.
    const NPM_JS: &str = "@ECHO off\r\nGOTO start\r\n:find_dp0\r\nSET dp0=%~dp0\r\nEXIT /b\r\n:start\r\nSETLOCAL\r\nCALL :find_dp0\r\n\r\nIF EXIST \"%dp0%\\node.exe\" (\r\n  SET \"_prog=%dp0%\\node.exe\"\r\n) ELSE (\r\n  SET \"_prog=node\"\r\n  SET PATHEXT=%PATHEXT:;.JS;=;%\r\n)\r\n\r\nendLocal & goto #_undefined_# 2>NUL || title %COMSPEC% & \"%_prog%\"  \"%dp0%\\node_modules\\said\\cli.js\" %*\r\n";
    const NPM_EXE: &str = "@ECHO off\r\nGOTO start\r\n:find_dp0\r\nSET dp0=%~dp0\r\nEXIT /b\r\n:start\r\nSETLOCAL\r\nCALL :find_dp0\r\n\"%dp0%\\node_modules\\@anthropic-ai\\claude-code\\bin\\claude.exe\"   %*\r\n";
    const PNPM_JS: &str = "@SETLOCAL\r\n@IF EXIST \"%~dp0\\node.exe\" (\r\n  \"%~dp0\\node.exe\"  \"%~dp0\\node_modules\\x\\bin\\cli.js\" %*\r\n) ELSE (\r\n  @SET PATHEXT=%PATHEXT:;.JS;=;%\r\n  node  \"%~dp0\\node_modules\\x\\bin\\cli.js\" %*\r\n)\r\n";
    const PNPM_EXE: &str = "@SETLOCAL\r\n@\"%~dp0\\node_modules\\@anthropic-ai\\claude-code\\bin\\claude.exe\"   %*\r\n";

    #[test]
    fn npm_and_pnpm_shims_for_a_script_run_it_with_node() {
        assert_eq!(read(NPM_JS), Some(Runs::Node(Named::Beside(r"node_modules\said\cli.js"))));
        assert_eq!(read(PNPM_JS), Some(Runs::Node(Named::Beside(r"node_modules\x\bin\cli.js"))));
    }

    #[test]
    fn npm_and_pnpm_shims_for_a_binary_run_it() {
        let claude = Some(Runs::Program(Named::Beside(r"node_modules\@anthropic-ai\claude-code\bin\claude.exe")));
        assert_eq!(read(NPM_EXE), claude);
        assert_eq!(read(PNPM_EXE), claude);
    }

    #[test]
    fn one_that_hands_on_runs_what_it_names() {
        let vite = "@echo off\r\n\"C:\\Users\\a\\.vite-plus\\npm\\said.cmd\" %*\r\nexit /b %ERRORLEVEL%\r\n";
        assert_eq!(read(vite), Some(Runs::Program(Named::At(r"C:\Users\a\.vite-plus\npm\said.cmd"))));
    }

    #[test]
    fn anything_else_is_left_to_cmd() {
        assert_eq!(read("@echo said %*\r\n"), None);
        assert_eq!(read("@echo off\r\nset X=1\r\n\"%~dp0\\said.exe\" %*\r\n"), None);
        assert_eq!(read("@\"%~dp0\\said.exe\" --flag %*\r\n"), None);
        // What the station writes for a script: Git's sh, through a variable.
        assert_eq!(read("@\"%USERPROFILE%\\Git\\bin\\sh.exe\" \"%~dp0said\" %*\r\n"), None);
        assert_eq!(read("@\"%USERPROFILE%\\bin\\said.exe\" %*\r\n"), None);
    }
}
