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
- **noq-udp 1.3.0** (src/unix.rs): on Apple platforms a datagram's source address is set with `IP_PKTINFO`. It was
  set with `IP_RECVDSTADDR`, which macOS ignores on send, so a reply left from the address the routing table picked.
  On a machine with two addresses on one network (studio: 192.168.20.10 on the wired VLAN, 192.168.20.107 on Wi-Fi) a
  device that had dialed one got the answer from the other, and the handshake never finished: the station dropped
  what came back as sent to the wrong interface.
