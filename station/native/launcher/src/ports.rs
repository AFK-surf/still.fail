//! The two listening sockets the launcher holds for Node (so a handover leaves no gap on them): the agents' MCP endpoint
//! (as mesh/app/src/ports.rs) and the loopback port (as mesh/station/src/local.rs). A port named (the config's http.port,
//! --port) is the station's to keep: taken, starting fails and says by what. Unnamed, the usual one is taken if free,
//! else any free one: another program on the machine must not keep the station from starting.
//!
//! The MCP port the station had last is remembered (<data>/run/mcp.json) and taken first when it is free: agents a
//! station leaves running for the next one (stopped and started again, a crash) were told it, and know no other. Only
//! the machine's own data directory has usual ports; a station on another one (a test's, a development station's)
//! takes free ones unless one is named, so it never keeps the machine's station off them.

use std::io::ErrorKind;
use std::net::TcpListener;
use std::path::Path;

use crate::data::{Config, write_whole};

/// The MCP endpoint's socket, per the config: unnamed, the port remembered first, then the usual one (`own`: the
/// machine's data directory), then any. The port it got is remembered.
pub fn mcp(data: &Path, config: &Config, own: bool) -> Result<TcpListener, String> {
    let what = if config.english { "the agents' MCP endpoint" } else { "agent 的 MCP 端点" };
    let (host, port) = (config.host.as_str(), config.port);
    let taken = || {
        if config.english {
            format!("Port {host}:{port} for {what} is taken by another program (the config names this port). Run `lsof -nP -iTCP:{port} -sTCP:LISTEN` to see which, or pick another port in the config.")
        } else {
            format!("{what} 的端口 {host}:{port} 已被别的程序占用（配置里指定了这个端口）。用 `lsof -nP -iTCP:{port} -sTCP:LISTEN` 看是谁，或在配置里换一个端口。")
        }
    };
    let file = data.join("run").join("mcp.json");
    let before = remembered(&file);
    let usual = (config.named || own).then_some(port);
    let listener = listen_first(host, before, usual, config.named, taken, |port| TcpListener::bind((host, port)))?;
    let got = listener.local_addr().map_err(|e| e.to_string())?.port();
    if before.is_some_and(|before| before != got) && !config.named {
        crate::log::warn(&format!("the MCP endpoint's port of before cannot be had; agents left running start again (port={got})"));
    } else if usual.is_some_and(|usual| usual != got) {
        crate::log::warn(&format!("the MCP endpoint's usual port is taken; listening on a free one (port={got})"));
    }
    write_whole(&file, &format!("{{\"port\":{got}}}\n")).map_err(|e| format!("run/mcp.json: {e}"))?;
    Ok(listener)
}

/// The MCP port remembered in `file`, if it reads.
fn remembered(file: &Path) -> Option<u16> {
    let raw: serde_json::Value = serde_json::from_slice(&std::fs::read(file).ok()?).ok()?;
    raw["port"].as_u64().and_then(|p| u16::try_from(p).ok()).filter(|&p| p != 0)
}

/// The loopback port (--port, else 4760 for the machine's data directory, `own`; any other takes a free one); the
/// port it got is written to <data>/run/ports.json.
pub fn admin(data: &Path, port: u16, named: bool, own: bool, english: bool) -> Result<TcpListener, String> {
    let taken = || {
        if english {
            format!("Port 127.0.0.1:{port} is taken by another program (--port names this port). Run `lsof -nP -iTCP:{port} -sTCP:LISTEN` to see which, or pick another port.")
        } else {
            format!("端口 127.0.0.1:{port} 已被别的程序占用（--port 指定了这个端口）。用 `lsof -nP -iTCP:{port} -sTCP:LISTEN` 看是谁，或换一个端口。")
        }
    };
    let usual = (named || own).then_some(port);
    let listener = listen_first("127.0.0.1", None, usual, named, taken, |port| TcpListener::bind(("127.0.0.1", port)))?;
    let got = listener.local_addr().map_err(|e| e.to_string())?.port();
    if usual.is_some_and(|usual| usual != got) {
        crate::log::warn(&format!("the loopback port's usual number is taken; listening on a free one (port={got})"));
    }
    write_whole(&data.join("run").join("ports.json"), &format!("{{\"admin\":{got}}}\n")).map_err(|e| format!("run/ports.json: {e}"))?;
    Ok(listener)
}

/// `remembered` if it is free, else `usual` if it is, else any free port; named (then `usual` is that port), taken is an
/// error. Bound with `bind` (a test's, for a port no other program can take meanwhile). The port remembered is passed
/// over whatever keeps it from being had; the usual one says why it cannot be, unless it is only taken.
fn listen_first(host: &str, remembered: Option<u16>, usual: Option<u16>, named: bool, taken: impl Fn() -> String, mut bind: impl FnMut(u16) -> std::io::Result<TcpListener>) -> Result<TcpListener, String> {
    if let Some(port) = remembered.filter(|&p| Some(p) != usual && !named) {
        if let Ok(listener) = bind(port) {
            return Ok(listener);
        }
    }
    if let Some(port) = usual {
        match bind(port) {
            Ok(listener) => return Ok(listener),
            Err(e) if e.kind() == ErrorKind::AddrInUse && named => return Err(taken()),
            Err(e) if e.kind() == ErrorKind::AddrInUse => {}
            Err(e) => return Err(format!("{host}:{port}: {e}")),
        }
    }
    bind(0).map_err(|e| format!("{host}:0: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn listen(host: &str, port: u16, named: bool, taken: impl Fn() -> String) -> Result<TcpListener, String> {
        listen_first(host, None, Some(port), named, taken, |port| TcpListener::bind((host, port)))
    }

    fn temp(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("launcher-ports-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("run")).unwrap();
        dir
    }

    /// A bind of the test's: each port asked is noted, and answered from `free` (listeners the test bound, by the port
    /// asked; 0 for any), else taken. A real port let go to be bound again could be taken by another program meanwhile.
    fn binder(free: Vec<(u16, TcpListener)>, asked: &mut Vec<u16>) -> impl FnMut(u16) -> std::io::Result<TcpListener> + '_ {
        let mut free = free;
        move |port| {
            asked.push(port);
            match free.iter().position(|(p, _)| *p == port) {
                Some(at) => Ok(free.remove(at).1),
                None => Err(ErrorKind::AddrInUse.into()),
            }
        }
    }

    #[test]
    fn a_usual_port_taken_gives_way_to_a_free_one_a_named_one_does_not() {
        let other = TcpListener::bind("127.0.0.1:0").unwrap();
        let taken = other.local_addr().unwrap().port();
        let got = listen("127.0.0.1", taken, false, String::new).unwrap().local_addr().unwrap().port();
        assert!(got != taken && got > 0);
        assert_eq!(listen("127.0.0.1", taken, true, || "taken".into()).unwrap_err(), "taken");
        let config = Config { host: "127.0.0.1".into(), port: taken, named: true, english: false };
        let data = temp("named");
        assert!(mcp(&data, &config, true).unwrap_err().contains("已被别的程序占用"));
        std::fs::remove_dir_all(&data).unwrap();
        // Free, the usual one is used as it is.
        let free = TcpListener::bind("127.0.0.1:0").unwrap();
        let at = free.local_addr().unwrap();
        let mut asked = vec![];
        assert_eq!(listen_first("127.0.0.1", None, Some(at.port()), false, String::new, binder(vec![(at.port(), free)], &mut asked)).unwrap().local_addr().unwrap(), at);
        assert_eq!(asked, [at.port()]);
    }

    #[test]
    fn the_port_of_before_is_taken_first_then_the_usual_one_then_any() {
        let (before, any) = (TcpListener::bind("127.0.0.1:0").unwrap(), TcpListener::bind("127.0.0.1:0").unwrap());
        let (at_before, at_any) = (before.local_addr().unwrap(), any.local_addr().unwrap());
        // Free, the port of before: agents left running know it.
        let mut asked = vec![];
        let got = listen_first("127.0.0.1", Some(at_before.port()), Some(4750), false, String::new, binder(vec![(at_before.port(), before)], &mut asked)).unwrap();
        assert_eq!((got.local_addr().unwrap(), asked), (at_before, vec![at_before.port()]));
        // Taken, the usual one; taken too, any.
        let mut asked = vec![];
        let got = listen_first("127.0.0.1", Some(12671), Some(4750), false, String::new, binder(vec![(0, any)], &mut asked)).unwrap();
        assert_eq!((got.local_addr().unwrap(), asked), (at_any, vec![12671, 4750, 0]));
        // Named, the config's port alone.
        let mut asked = vec![];
        assert_eq!(listen_first("127.0.0.1", Some(12671), Some(5000), true, || "taken".into(), binder(vec![], &mut asked)).unwrap_err(), "taken");
        assert_eq!(asked, [5000]);
    }

    #[test]
    fn the_mcp_port_is_remembered_and_had_again_and_another_data_directory_takes_no_usual_port() {
        let data = temp("remembered");
        // The usual port, kept by another program: a station on another data directory never tries it.
        let usual = TcpListener::bind("127.0.0.1:0").unwrap();
        let config = Config { host: "127.0.0.1".into(), port: usual.local_addr().unwrap().port(), named: false, english: true };
        drop(usual);
        let first = mcp(&data, &config, false).unwrap();
        let port = first.local_addr().unwrap().port();
        assert_ne!(port, config.port);
        assert_eq!(std::fs::read_to_string(data.join("run/mcp.json")).unwrap(), format!("{{\"port\":{port}}}\n"));
        assert_eq!(remembered(&data.join("run/mcp.json")), Some(port));
        // The station stops and starts again: the same port, so the agents it left running still reach it.
        drop(first);
        let again = mcp(&data, &config, false).unwrap();
        assert_eq!(again.local_addr().unwrap().port(), port);
        // Nor the loopback port's usual one.
        let admin = admin(&data, 4760, false, false, true).unwrap();
        assert_ne!(admin.local_addr().unwrap().port(), 4760);
        std::fs::remove_dir_all(&data).unwrap();
    }
}
