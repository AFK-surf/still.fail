//! Station RPC uses its own ALPN and the iroh peer key, not a member/admin credential. Membership comes only from
//! the authenticated cloud presence socket. On losing it, new peer calls fail closed until a fresh roster arrives.
use super::*;
use stillfail_app::remote::Call;
pub const ALPN: &[u8] = b"stillfail/station/1";
const MAX_MESSAGE: usize = 1024 * 1024;

fn member(station: &Station, peer: &str, workspace: Option<&str>) -> Result<String> {
    if !station.peers_current.load(std::sync::atomic::Ordering::SeqCst) {
        bail!("workspace peer roster is not current; waiting for the control plane");
    }
    let state = station.state.lock().unwrap();
    if state.removed_at.is_some() || workspace.is_some_and(|w| w != state.workspace) {
        bail!("station is outside this workspace");
    }
    if !state.peers.iter().any(|p| p["id"].as_str() == Some(peer)) || peer == state.station {
        bail!("peer is not another station in this workspace");
    }
    Ok(state.workspace.clone())
}

/// Whether a connection runs over the LAN now: its path is direct, to a private address in a network of one of this
/// machine's interfaces. A relay, a public address, or a VPN's (Tailscale's 100.64/10 is no network of a LAN) is not.
fn on_lan(conn: &Connection) -> bool {
    let paths = conn.paths();
    let Some(path) = paths.iter().find(|p| p.is_selected()) else { return false };
    let iroh::TransportAddr::Ip(addr) = path.remote_addr() else { return false };
    let interfaces = netdev::get_interfaces();
    lan_address(addr.ip().to_canonical(), &interfaces)
}

fn lan_address(ip: std::net::IpAddr, interfaces: &[netdev::Interface]) -> bool {
    match ip {
        std::net::IpAddr::V4(ip) => ip.is_private() && interfaces.iter().any(|i| i.ipv4.iter().any(|net| net.prefix_len() > 0 && net.contains(&ip))),
        std::net::IpAddr::V6(ip) => {
            let segment = ip.segments()[0];
            let local = segment & 0xffc0 == 0xfe80 || segment & 0xfe00 == 0xfc00;
            local && interfaces.iter().any(|i| i.ipv6.iter().any(|net| net.prefix_len() > 0 && net.contains(&ip)))
        }
    }
}

pub fn attach(endpoint: Endpoint, station: Arc<Station>) {
    tokio::spawn(async move {
        loop {
            if let Some(app) = station.backend.0.get() {
                let (endpoint, station) = (endpoint.clone(), Arc::downgrade(&station));
                let connections: Arc<Mutex<std::collections::HashMap<String, Connection>>> = Arc::default();
                let call: Call = Arc::new(move |target, request| {
                    let (endpoint, station, connections) = (endpoint.clone(), station.clone(), connections.clone());
                    Box::pin(async move {
                        let station = station.upgrade().ok_or_else(|| anyhow!("station stopped"))?;
                        if target.is_empty() && request["method"] == "peers" {
                            let s = station.state.lock().unwrap();
                            return Ok(
                                json!({"workspace":s.workspace,"stations":s.peers,"self":s.station,"current":station.peers_current.load(std::sync::atomic::Ordering::SeqCst)}),
                            );
                        }
                        let workspace = member(&station, &target, request["workspace"].as_str())?;
                        // Requests are bounded and retriable by stable task key. A timeout is never reported as
                        // "not run": callers must query the same key after reconnecting.
                        let result = tokio::time::timeout(Duration::from_secs(30), async {
                            let id: iroh::EndpointId = target.parse()?;
                            let relays = relays(&station.state.lock().unwrap());
                            let mut addr = iroh::EndpointAddr::new(id);
                            for relay in relays {
                                addr = addr.with_relay_url(relay);
                            }
                            let cached = connections
                                .lock()
                                .unwrap()
                                .get(&target)
                                .filter(|c| c.close_reason().is_none())
                                .cloned();
                            let conn = match cached {
                                Some(conn) => conn,
                                None => {
                                    let conn = endpoint
                                        .connect(addr, ALPN)
                                        .await
                                        .context("peer unavailable or does not support station RPC")?;
                                    connections.lock().unwrap().insert(target.clone(), conn.clone());
                                    conn
                                }
                            };
                            let (mut send, mut recv) = conn.open_bi().await?;
                            let bytes = serde_json::to_vec(&json!({"workspace":workspace,"request":request}))?;
                            if bytes.len() > MAX_MESSAGE {
                                bail!("peer request too large");
                            }
                            send.write_all(&bytes).await?;
                            send.finish()?;
                            let bytes = recv.read_to_end(MAX_MESSAGE).await?;
                            let result: Value = serde_json::from_slice(&bytes)?;
                            if let Some(error) = result["error"].as_str() {
                                return Err(stillfail_app::remote::Refused(error.to_string()).into());
                            }
                            // Keep QUIC alive until the peer's FIN is received (read_to_end above).
                            Ok(result["result"].clone())
                        })
                        .await
                        .unwrap_or_else(|_| {
                            Err(anyhow!(
                                "peer request timed out; execution may have happened — query the same task key"
                            ))
                        });
                        if result
                            .as_ref()
                            .is_err_and(|e: &anyhow::Error| e.downcast_ref::<stillfail_app::remote::Refused>().is_none())
                        {
                            connections.lock().unwrap().remove(&target);
                        }
                        result
                    })
                });
                app.remote.attach(call);
                break;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        loop {
            let current = station.peers_current.load(std::sync::atomic::Ordering::SeqCst);
            let (workspace, peers) = {
                let s = station.state.lock().unwrap();
                (
                    s.workspace.clone(),
                    s.peers
                        .iter()
                        .filter_map(|p| p["id"].as_str().map(str::to_string))
                        .collect::<Vec<_>>(),
                )
            };
            if let Some(app) = station.backend.0.get() {
                app.remote.revoke(&workspace, &peers, current).await;
            }
            tokio::time::sleep(Duration::from_secs(5)).await;
        }
    });
}

pub async fn serve(station: Arc<Station>, conn: Connection) -> Result<()> {
    let peer = conn.remote_id().to_string();
    member(&station, &peer, None)?;
    loop {
        let (mut send, mut recv) = tokio::time::timeout(Duration::from_secs(60), conn.accept_bi()).await??;
        let bytes = tokio::time::timeout(Duration::from_secs(15), recv.read_to_end(MAX_MESSAGE)).await??;
        let result: Result<Value> = async {
            let envelope: Value = serde_json::from_slice(&bytes)?;
            let workspace = envelope["workspace"].as_str().ok_or_else(|| anyhow!("workspace missing"))?;
            member(&station, &peer, Some(workspace))?;
            let app = station.backend.0.get().ok_or_else(|| anyhow!("station is starting"))?;
            // Whether it came over the LAN is the transport's to say, never the caller's (lent accounts, lan_share.rs).
            let mut request = envelope["request"].clone();
            if request.is_object() {
                request["lan"] = json!(on_lan(&conn));
            }
            app.remote.handle(workspace, &peer, request).await
        }
        .await;
        let answer = match result {
            Ok(value) => json!({"result":value}),
            Err(e) => json!({"error":e.to_string()}),
        };
        send.write_all(&serde_json::to_vec(&answer)?).await?;
        send.finish()?;
        let _ = tokio::time::timeout(Duration::from_secs(10), send.stopped()).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_a_private_address_in_one_of_its_own_networks_is_the_lan() {
        let mut lan = netdev::Interface::dummy();
        lan.ipv4 = vec!["192.168.20.11/24".parse().unwrap()];
        lan.ipv6 = vec!["fe80::1/64".parse().unwrap()];
        let mut vpn = netdev::Interface::dummy();
        vpn.ipv4 = vec!["100.101.102.103/32".parse().unwrap()];
        let interfaces = [lan, vpn];
        let at = |ip: &str| lan_address(ip.parse().unwrap(), &interfaces);
        assert!(at("192.168.20.42"));
        assert!(at("fe80::abcd"));
        assert!(!at("192.168.21.42"), "another network");
        assert!(!at("10.0.0.2"), "private, but not one of its networks");
        assert!(!at("100.101.102.104"), "a VPN's address");
        assert!(!at("47.76.247.168"), "public");
    }

    #[tokio::test]
    async fn real_peer_connection_runs_a_task_and_returns_its_artifact() -> Result<()> {
        let dir = tempfile::tempdir()?;
        let source = Endpoint::builder(Minimal).relay_mode(RelayMode::Disabled).bind().await?;
        let target = Endpoint::builder(Minimal)
            .relay_mode(RelayMode::Disabled)
            .alpns(vec![ALPN.to_vec()])
            .bind()
            .await?;
        let source_id = source.id().to_string();
        let state: CloudState = serde_json::from_value(
            json!({"origin":"http://localhost","station":target.id().to_string(),"workspace":"test-ws","workspace_name":"Test","name":"target","relay_url":"http://localhost:3340","grant_keys":{},"peers":[{"id":source_id}]}),
        )?;
        std::fs::create_dir_all(mesh_dir(dir.path()))?;
        save_state(dir.path(), &state)?;
        std::fs::write(dir.path().join("config.json"),json!({"http":{"host":"127.0.0.1","port":0},"agentHome":dir.path().join("agent"),"profiles":[],"remoteTasks":{"allow":[source_id]}}).to_string())?;
        let app = stillfail_app::server::App::start(stillfail_app::server::AppOptions {
            data: dir.path().into(),
            config: dir.path().join("config.json"),
            ui: dir.path().join("app/dist/admin"),
            handoff: None,
        })
        .await?;
        let backend = local::Backend::default();
        backend.0.set(app.clone()).ok();
        let station = Arc::new(Station {
            data: dir.path().into(),
            state: Mutex::new(state),
            peers_current: std::sync::atomic::AtomicBool::new(true),
            backend,
            ready: watch::channel(true).1,
            telemetry: Telemetry::new(false),
            adb: adb::Shares::default(),
        });
        let accepted = target.clone();
        let serving = station.clone();
        let server = tokio::spawn(async move {
            while let Some(incoming) = accepted.accept().await {
                let serving = serving.clone();
                tokio::spawn(async move {
                    if let Ok(conn) = incoming.await {
                        let _ = serve(serving, conn).await;
                    }
                });
            }
        });
        let address = target.addr();
        let connection = source.connect(address.clone(), ALPN).await?;
        async fn rpc(conn: &Connection, method: &str, extra: Value) -> Result<Value> {
            let (mut send, mut recv) = conn.open_bi().await?;
            let mut request = json!({"method":method,"session":"session","key":"one"});
            for (k, v) in extra.as_object().unwrap() {
                request[k] = v.clone();
            }
            send.write_all(&serde_json::to_vec(&json!({"workspace":"test-ws","request":request}))?)
                .await?;
            send.finish()?;
            let bytes = recv.read_to_end(MAX_MESSAGE).await?;
            Ok(serde_json::from_slice::<Value>(&bytes)?)
        }
        let described = rpc(&connection, "describe", json!({})).await?;
        assert_eq!(described["result"]["tasks"], true);
        let prepared = rpc(
            &connection,
            "task.prepare",
            json!({"spec":{"command":"echo transport-ok > result.txt"}}),
        )
        .await?;
        assert!(prepared["error"].is_null(), "{prepared}");
        let started = rpc(&connection, "task.start", json!({})).await?;
        assert!(started["error"].is_null(), "{started}");
        for _ in 0..200 {
            let status = rpc(&connection, "task.get", json!({})).await?;
            if status["result"]["job"]["state"] != "running" {
                assert_eq!(status["result"]["job"]["exitCode"], 0);
                break;
            }
            tokio::time::sleep(Duration::from_millis(25)).await;
        }
        let artifact = rpc(&connection, "file.get", json!({"path":"result.txt"})).await?;
        use base64::Engine;
        assert_eq!(
            base64::engine::general_purpose::STANDARD.decode(artifact["result"]["data"].as_str().unwrap())?,
            b"transport-ok\n"
        );
        let repeated = rpc(&connection, "task.start", json!({})).await?;
        assert_eq!(repeated["result"]["job"]["id"], started["result"]["job"]["id"]);
        assert!(member(&station, &source_id, Some("other-ws")).is_err());
        station.peers_current.store(false, std::sync::atomic::Ordering::SeqCst);
        assert!(member(&station, &source_id, None).is_err());
        station.peers_current.store(true, std::sync::atomic::Ordering::SeqCst);
        station.state.lock().unwrap().peers.clear();
        assert!(member(&station, &source_id, None).is_err());
        server.abort();
        source.close().await;
        target.close().await;
        app.shutdown().await;
        Ok(())
    }
}
