//! The agents' MCP endpoint's port (the admin page's is ember-station's: mesh/station/src/local.rs, alike). A port the
//! config names is the station's to keep: taken, starting fails and says by what. Unnamed, the usual one (4750) is
//! taken if free, else any free one: another program on the machine (an old ssh tunnel, a second station) must not
//! keep the station from starting.

use std::io::ErrorKind;

use anyhow::Result;
use tokio::net::TcpListener;

/// A port the config names, taken by another program.
#[derive(Debug, thiserror::Error)]
#[error("{what} 的端口 {host}:{port} 已被别的程序占用（配置里指定了这个端口）。用 `lsof -nP -iTCP:{port} -sTCP:LISTEN` 看是谁，或在配置里换一个端口。")]
pub struct PortTaken {
    pub what: String,
    pub host: String,
    pub port: u16,
}

/// Listens on `port`, or, when it is only the usual one (not named in the config) and taken, on any free port.
pub async fn listen(host: &str, port: u16, named: bool, what: &str) -> Result<TcpListener> {
    match TcpListener::bind((host, port)).await {
        Ok(listener) => Ok(listener),
        Err(e) if e.kind() == ErrorKind::AddrInUse && named => Err(PortTaken { what: what.into(), host: host.into(), port }.into()),
        Err(e) if e.kind() == ErrorKind::AddrInUse => Ok(TcpListener::bind((host, 0)).await?),
        Err(e) => Err(e.into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn a_usual_port_taken_by_something_else_gives_way_to_a_free_one_a_port_the_config_names_does_not() {
        let other = listen("127.0.0.1", 0, false, "x").await.unwrap();
        let taken = other.local_addr().unwrap().port();
        let station = listen("127.0.0.1", taken, false, "管理页").await.unwrap();
        let got = station.local_addr().unwrap().port();
        assert!(got != taken && got > 0);
        let refused = listen("127.0.0.1", taken, true, "管理页").await.unwrap_err();
        assert!(refused.downcast_ref::<PortTaken>().is_some() && refused.to_string().contains("已被别的程序占用"));
        // Free, the usual one is used as it is.
        let free = listen("127.0.0.1", 0, false, "x").await.unwrap();
        let port = free.local_addr().unwrap().port();
        drop(free);
        assert_eq!(listen("127.0.0.1", port, false, "x").await.unwrap().local_addr().unwrap().port(), port);
    }
}
