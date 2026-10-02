//! The two listening sockets the launcher holds for Node (so a handover leaves no gap on them): the agents' MCP endpoint
//! (as mesh/app/src/ports.rs) and the loopback port (as mesh/station/src/local.rs). A port named (the config's http.port,
//! --port) is the station's to keep: taken, starting fails and says by what. Unnamed, the usual one is taken if free,
//! else any free one: another program on the machine must not keep the station from starting.

use std::io::ErrorKind;
use std::net::TcpListener;
use std::path::Path;

use crate::data::{Config, write_whole};

/// The MCP endpoint's socket, per the config.
pub fn mcp(config: &Config) -> Result<TcpListener, String> {
    let what = if config.english { "the agents' MCP endpoint" } else { "agent 的 MCP 端点" };
    let (host, port) = (config.host.as_str(), config.port);
    let taken = || {
        if config.english {
            format!("Port {host}:{port} for {what} is taken by another program (the config names this port). Run `lsof -nP -iTCP:{port} -sTCP:LISTEN` to see which, or pick another port in the config.")
        } else {
            format!("{what} 的端口 {host}:{port} 已被别的程序占用（配置里指定了这个端口）。用 `lsof -nP -iTCP:{port} -sTCP:LISTEN` 看是谁，或在配置里换一个端口。")
        }
    };
    let listener = listen(host, port, config.named, taken)?;
    let got = listener.local_addr().map_err(|e| e.to_string())?.port();
    if got != port {
        crate::log::warn(&format!("the MCP endpoint's usual port is taken; listening on a free one (port={got})"));
    }
    Ok(listener)
}

/// The loopback port (--port, else 4760); the port it got is written to <data>/run/ports.json.
pub fn admin(data: &Path, port: u16, named: bool, english: bool) -> Result<TcpListener, String> {
    let taken = || {
        if english {
            format!("Port 127.0.0.1:{port} is taken by another program (--port names this port). Run `lsof -nP -iTCP:{port} -sTCP:LISTEN` to see which, or pick another port.")
        } else {
            format!("端口 127.0.0.1:{port} 已被别的程序占用（--port 指定了这个端口）。用 `lsof -nP -iTCP:{port} -sTCP:LISTEN` 看是谁，或换一个端口。")
        }
    };
    let listener = listen("127.0.0.1", port, named, taken)?;
    let got = listener.local_addr().map_err(|e| e.to_string())?.port();
    if got != port {
        crate::log::warn(&format!("the loopback port's usual number is taken; listening on a free one (port={got})"));
    }
    write_whole(&data.join("run").join("ports.json"), &format!("{{\"admin\":{got}}}\n")).map_err(|e| format!("run/ports.json: {e}"))?;
    Ok(listener)
}

fn listen(host: &str, port: u16, named: bool, taken: impl Fn() -> String) -> Result<TcpListener, String> {
    match TcpListener::bind((host, port)) {
        Ok(listener) => Ok(listener),
        Err(e) if e.kind() == ErrorKind::AddrInUse && named => Err(taken()),
        Err(e) if e.kind() == ErrorKind::AddrInUse => TcpListener::bind((host, 0)).map_err(|e| format!("{host}:0: {e}")),
        Err(e) => Err(format!("{host}:{port}: {e}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_usual_port_taken_gives_way_to_a_free_one_a_named_one_does_not() {
        let other = TcpListener::bind("127.0.0.1:0").unwrap();
        let taken = other.local_addr().unwrap().port();
        let got = listen("127.0.0.1", taken, false, String::new).unwrap().local_addr().unwrap().port();
        assert!(got != taken && got > 0);
        assert_eq!(listen("127.0.0.1", taken, true, || "taken".into()).unwrap_err(), "taken");
        let config = Config { host: "127.0.0.1".into(), port: taken, named: true, english: false };
        assert!(mcp(&config).unwrap_err().contains("已被别的程序占用"));
        // Free, the usual one is used as it is.
        let free = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = free.local_addr().unwrap().port();
        drop(free);
        assert_eq!(listen("127.0.0.1", port, false, String::new).unwrap().local_addr().unwrap().port(), port);
    }
}
