# LAN connections behind an outbound firewall

Set `STILLFAIL_MESH_BIND_ADDR=0.0.0.0:4770` in the station service's environment to keep its IPv4 QUIC listener on UDP
port 4770 across restarts. Choose an unused port. The default remains an OS-assigned port. An invalid or occupied
explicit address fails to bind; it does not silently choose another port. The startup `mesh listening` log records
the actual sockets. An IPv4 bind does not disable the separate IPv6 listener: retain the IPv6 firewall policy too.
This setting does not change the loopback HTTP listeners or device authentication.

For a macOS VM whose outbound traffic is blocked by PF, permit incoming LAN traffic to that one UDP port with
`keep state`. Replies can then use that state without granting the VM permission to initiate arbitrary LAN traffic.
For example, adapt the interface, subnet and port to the machine, within its existing firewall anchor:

```pf
pass in quick on en0 inet proto udp from 192.168.20.0/24 to (en0) port 4770 keep state
```

If clients discover the station through mDNS, also allow its announcements and responses. Place these exceptions
after the existing outbound block rule (which must not be `quick`), or otherwise integrate them into the policy:

```pf
pass out quick on en0 inet proto udp from (en0) port 5353 to 224.0.0.251 port 5353 keep state
pass out quick on en0 inet proto udp from (en0) port 5353 to 192.168.20.0/24 port 5353 keep state
```

These are packet restrictions, not process authentication. Any process able to bind these local ports can use their
exceptions. mDNS publishes discovery information to the LAN; it does not grant access to station data. Clients on
another subnet need a separate discovery mechanism or an explicitly configured address. Inbound-only QUIC permits
a LAN client to initiate a connection, but does not promise that all peer-initiated hole-punching paths will work.
Keep the existing outbound default block and relay/proxy exceptions; do not allow the whole LAN or public UDP range.

Back up the anchor, validate with `pfctl -nf`, and reload only the affected anchor. Do not flush unrelated states.
Verify a real QUIC stream from a second LAN machine reports a direct path, then repeat after a station restart.
Also verify that arbitrary LAN connections and unapproved public TCP/UDP destinations remain blocked and that the
existing relay and proxy still work. Restore the saved anchor if validation fails.
