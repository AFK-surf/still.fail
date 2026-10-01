//! Station RPC uses its own ALPN and the iroh peer key, not a member/admin credential. Membership comes only from
//! the authenticated cloud presence socket. On losing it, new peer calls fail closed until a fresh roster arrives.
use super::*;
use stillfail_app::remote::Call;
pub const ALPN: &[u8] = b"stillfail/station/1";
const MAX_MESSAGE: usize = 1024 * 1024;

fn member(station: &Station, peer: &str, workspace: Option<&str>) -> Result<String> {
    if !station.peers_current.load(std::sync::atomic::Ordering::SeqCst) { bail!("workspace peer roster is not current; waiting for the control plane"); }
    let state=station.state.lock().unwrap();
    if state.removed_at.is_some() || workspace.is_some_and(|w| w!=state.workspace) { bail!("station is outside this workspace"); }
    if !state.peers.iter().any(|p| p["id"].as_str()==Some(peer)) || peer==state.station { bail!("peer is not another station in this workspace"); }
    Ok(state.workspace.clone())
}

pub fn attach(endpoint: Endpoint, station: Arc<Station>) {
    tokio::spawn(async move {
        loop {
            if let Some(app)=station.backend.0.get() {
                let (endpoint, station)=(endpoint.clone(),station.clone());
                let call: Call=Arc::new(move |target,request| {
                    let (endpoint,station)=(endpoint.clone(),station.clone());
                    Box::pin(async move {
                        if target.is_empty() && request["method"]=="peers" {
                            let s=station.state.lock().unwrap();
                            return Ok(json!({"workspace":s.workspace,"stations":s.peers,"current":station.peers_current.load(std::sync::atomic::Ordering::SeqCst)}));
                        }
                        let workspace=member(&station,&target,request["workspace"].as_str())?;
                        // Requests are bounded and retriable by stable task key. A timeout is never reported as
                        // "not run": callers must query the same key after reconnecting.
                        tokio::time::timeout(Duration::from_secs(30), async {
                            let id: iroh::EndpointId=target.parse()?;
                            let relays=relays(&station.state.lock().unwrap());
                            let mut addr=iroh::EndpointAddr::new(id);
                            for relay in relays { addr=addr.with_relay_url(relay); }
                            let conn=endpoint.connect(addr,ALPN).await.context("peer unavailable or does not support station RPC")?;
                            let (mut send,mut recv)=conn.open_bi().await?;
                            let bytes=serde_json::to_vec(&json!({"workspace":workspace,"request":request}))?;
                            if bytes.len()>MAX_MESSAGE { bail!("peer request too large"); }
                            send.write_all(&bytes).await?;
                            send.finish()?;
                            let bytes=recv.read_to_end(MAX_MESSAGE).await?;
                            let result: Value=serde_json::from_slice(&bytes)?;
                            if let Some(error)=result["error"].as_str() { bail!("{error}"); }
                            // Keep QUIC alive until the peer's FIN is received (read_to_end above).
                            Ok(result["result"].clone())
                        }).await.map_err(|_| anyhow!("peer request timed out; execution may have happened — query the same task key"))?
                    })
                });
                app.remote.attach(call);
                break;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        loop {
            if station.peers_current.load(std::sync::atomic::Ordering::SeqCst) {
                let (workspace, peers)={let s=station.state.lock().unwrap(); (s.workspace.clone(),s.peers.iter().filter_map(|p|p["id"].as_str().map(str::to_string)).collect::<Vec<_>>())};
                if let Some(app)=station.backend.0.get() { app.remote.revoke(&workspace,&peers).await; }
            }
            tokio::time::sleep(Duration::from_secs(5)).await;
        }
    });
}

pub async fn serve(station: Arc<Station>, conn: Connection) -> Result<()> {
    let peer=conn.remote_id().to_string();
    member(&station,&peer,None)?;
    let (mut send,mut recv)=tokio::time::timeout(Duration::from_secs(10),conn.accept_bi()).await??;
    let bytes=tokio::time::timeout(Duration::from_secs(15),recv.read_to_end(MAX_MESSAGE)).await??;
    let result: Result<Value>=async {
        let envelope: Value=serde_json::from_slice(&bytes)?;
        let workspace=envelope["workspace"].as_str().ok_or_else(|| anyhow!("workspace missing"))?;
        member(&station,&peer,Some(workspace))?;
        let app=station.backend.0.get().ok_or_else(|| anyhow!("station is starting"))?;
        app.remote.handle(workspace,&peer,envelope["request"].clone()).await
    }.await;
    let answer=match result { Ok(value)=>json!({"result":value}),Err(e)=>json!({"error":e.to_string()}) };
    send.write_all(&serde_json::to_vec(&answer)?).await?;
    send.finish()?;
    let _=tokio::time::timeout(Duration::from_secs(10),send.stopped()).await;
    Ok(())
}
