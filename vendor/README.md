# vendor

Crates taken from crates.io and changed for ember; `[patch.crates-io]` in mesh/ and client/ points at them. Each
change is marked `ember:` in the source. Drop a crate here once upstream has the same.

- **swarm-discovery 0.6.3**
  - src/receiver.rs: a peer's addresses are read from the answers as well as the additionals, and records with
    mDNS's cache-flush bit count as class IN. A router reflecting mDNS between subnets sends the addresses on as
    answers, which 0.6.3 dropped, so a station on the other subnet was never found.
  - src/socket.rs: a failed send on one interface (a VM bridge that takes no multicast) is logged at debug, not
    error, as it recurs with every announcement.
- **iroh-mdns-address-lookup 0.4.0** (src/lib.rs): multicast goes out on, and is received from, every local IPv4
  interface (swarm-discovery's `add_interface_v4`), not only the default route's. A machine on two networks (studio:
  wired 192.168.0.x, Wi-Fi 192.168.20.x) was only announced on the first.
