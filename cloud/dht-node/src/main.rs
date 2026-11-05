//! A node of the public Mainline DHT that answers others from the first (server mode) on a port people can reach, so a
//! station or an app starting its DHT has a node of ours to ask for the others (`dht` in station/native/mesh and in
//! client/shell). It starts from the public DHT's own bootstrap nodes and holds nothing of ours.

use std::time::Duration;

use n0_mainline::Dht;

#[tokio::main]
async fn main() {
    let port = std::env::args().nth(1).and_then(|p| p.parse().ok()).unwrap_or(6881);
    let dht = Dht::builder().server_mode().port(port).build().expect("the port is taken");
    loop {
        let info = dht.info().await.expect("the DHT stopped");
        println!("{:?}: {} nodes known", info.local_addr(), info.routing_table_size());
        tokio::time::sleep(Duration::from_secs(600)).await;
    }
}
