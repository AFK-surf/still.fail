# A station on the device's LAN

> **Since 2026-10-29** a device reaches a station with one connection on its main endpoint (home on every relay, iroh
> from zzj3720/iroh `stillfail`): the station's LAN and tailnet addresses are given to that connection, iroh
> opens a path to them beside its relay paths, and every path is given up after 3 s of silence (not 15 s), its
> packets going on on another. The separate LAN and tailnet endpoints below are dialled only while the station's
> workspace turned the main endpoint's ways off (`ways_off`: `direct`, or one of still.fail's relays). What follows is
> why they were made, and how they work in that case.

A device on the same LAN as a station reaches it directly, on an endpoint that dials the station's LAN addresses and
nothing else. It does not rely on iroh's hole punching.

## Why

On 2026-10-17, a phone and several Macs on one LAN (studio, mini1, ccvm) connected to stations through a relay first,
the way every link starts. iroh then punched a path to the station's LAN address. That path went quiet a few seconds
after it opened: one end's packets stopped reaching the other, though the same addresses and ports carried plain UDP
both ways without loss. iroh lets a path go after hearing nothing for 15 s (`PATH_MAX_IDLE_TIMEOUT`), and requests on it
waited that long each time before going back through the relay. A connection dialled straight at the station's
address (its path 0, no relay, no punching) stayed direct for minutes with little loss.

On 2026-10-18 this was measured between mini1 (wired) and a test station on studio, a request every 5 s. A connection
dialled by address answered all 144 requests in 12 minutes at 1–2 ms. One device that started through a relay had iroh
punch a path to the station's LAN address, moved to it at once and answered all 48 requests in 4 minutes on it. What
looked like punched paths carrying nothing back in the same measurements came from the test: its clients were three
endpoints with one key. iroh picks one path per remote key for all its connections; on the others, the punched path was
made a backup and the station answered through the relay, which passes what is sent to a key to only one of the
endpoints holding it. A phone's endpoints each have a key of their own (`pinnedKey`), so this is not what it saw. Why
its punched paths went quiet on 2026-10-17 is not known. A phone says how its ways' paths change in `mesh.path` spans
(docs/telemetry.md): which opened, went or was chosen, round trips and packets a tick before and after, and the first
ping missed on each.

On 2026-10-18 one way a direct path goes dark was found, on an Android emulator on studio driving the station's
desktop: the path carried small packets both ways, and went dark the moment the phone sent something larger (a picture
pasted, 116 KB) until iroh let it go 15 s later, the picture then going through the relay. Linux (Android) sends such a
burst as one segmented datagram (UDP GSO, noq-udp); the emulator's network accepts it and drops all of it, and every
retransmission is a burst again. With GSO off on Android (vendor/noq-udp, one datagram a sendmsg) eight pastes in a row,
four of them right after the app was killed and opened again, reached the station within about 1 s of the tap; with it
on, each of eight took 16–19 s. Whether a real phone's network drops such bursts too is not known; with GSO off it no
longer matters.

## How

- The station says its LAN addresses with its answer to a device's first credential: `lan`, `ip:port` for each private
  IPv4 address on an interface a device on the LAN could reach (not VM or container bridges, tunnels or link-local),
  at the port of its IPv4 mesh socket (`station/src/mesh/lan.ts`, `serve.ts`). A station from before says nothing; the
  device goes on as before.
- The core keeps them per station address (`Link.lan`). If no way to the station is on the LAN endpoint yet, it dials
  them there (`Mesh.#dialLanIf`). The LAN endpoint is bound with the device key made over for `lan` (`pinnedKey`), on no
  relay, so it does no lookups and punches no holes. Its link is one more way to the station (`pinned: "lan"`).
- Requests move to that way at the next ping it answers (`mesh.route` with why `lan`). It is taken over a punched path
  on the main endpoint as well.
- While a way on the LAN endpoint answered within `LAN_RECALL_MS`, requests keep off the main endpoint unless no other
  way is up: the LAN way is enough, and the main endpoint's link would only punch one more path to the station. When
  the LAN way is lost, they go to a relay's own way, and the main endpoint is not dialled again every `REDIAL_MAIN_MS`.
  A way's key is `lan` on the LAN endpoint, and `direct` only for a punched path.
- macOS lets an app reach its own subnet only once Local Network is switched on for it. On 2026-10-18 the desktop app
  on a MacBook on studio's Wi-Fi had not been let: it reached studio only at its other subnet's address, through the
  router (12 ms, a fifth of the packets lost), and mini1 over Tailscale, and moved between ways and relays every few
  minutes. A station's net view says the addresses the station said (`lan`). The Electron desktop app (until 2026-10-26)
  sent a byte to each, and one on its subnet refused at once ("No route to host") had the station's row say Local
  Network is off and its page the way to System Settings; the Mac app built in its place (apps/mbui) asks for Local
  Network (its Info.plist's NSLocalNetworkUsageDescription) but does not tell yet that it was refused. The permissions page lists the app's own, the
  station's page the station's (docs/remote-screens.md, Grants).
- A device off the station's LAN gets no answer at those addresses. It tries them once for each set the station says,
  and again after the network changes. While the station was reached directly in the last 10 minutes, it tries again
  every 30 s.
- A direct way, on the LAN endpoint or a punched path, can still go quiet. On 2026-10-18 a phone on studio's LAN
  moved to such a way and back to a relay every minute or so. When requests lose a direct way within `MIN_STAY_MS` of
  moving to it twice in a row, the core moves them to no direct way for `DIRECT_HOLD_MS`, unless no other way is up.
  The hold doubles each time this happens again, up to `DIRECT_HOLD_MAX_MS`. A direct way that stays starts the count
  anew. The `mesh.route` span that starts a hold says how long it is (`stillfail.direct_held_ms`).
- A station's event stream that ends while another way to the station is up opens again on that way at once. The
  station is shown as reached throughout (`StationWire.standing`, station/link.ts). Before, every move between ways
  showed 正在重连 for a moment.
- Tests: `client/core-ts/test/mesh.test.ts`. The simulated LAN (`SimNet.lan` with `quietAfterMs`) has the punched path
  go quiet, and `SimNet.away` puts the device off the LAN.

## Tailscale

A device on the same tailnet as a station reaches it straight at its Tailscale address, the way a device on its LAN
does, Tailscale carrying the packets (straight, or through Tailscale's own relays when it could not punch through).

- The station says its Tailscale addresses with its answer to a device's first credential: `tailnet`, `ip:port` for
  each address of its in 100.64.0.0/10 at the port of its IPv4 mesh socket (`station/src/mesh/lan.ts` `tailnetAddrs`).
  Known by the address, not the interface: Tailscale's is utun on macOS (left out of the LAN), tailscale0 on Linux.
- The core dials them on an endpoint of their own (`pinned: "tailnet"`, the device key made over for `tailnet`), on no
  relay, as the LAN endpoint. Unlike a LAN way it is not taken at once nor does it keep the requests off the main
  endpoint: a tailnet going through Tailscale's relays may be slower than still.fail's nearest, so its way is compared
  by how it answers, as a relay's way is (`clearlyBetter`, `BETTER_TICKS`, `MIN_STAY_MS`). A station's card says
  `Tailscale` for it.
- Off the station's tailnet its addresses lead nowhere: tried once for each set it says and again after the network
  changes. Once a way there answered (since the network last changed), it is dialled again every `EXPLORE_MS` while
  none is open, as the relays are.
- Where each station said it is reached straight (LAN and tailnet) is kept on the device (`station-addresses`): a run
  dials them at once beside the relays (`#dialAll`), not after a relay brought the station's answer again, so a station
  on the device's tailnet is reached with none of the relays answering (2026-10-29: the user wanted Tailscale as one
  more way to a workspace's stations).
- Macs ask no Local Network permission for it: 100.64.0.0/10 is not the local subnet.
- Tests: `client/core-ts/test/mesh.test.ts` (`onTailnet`).

## Storms

2026-10-19 a phone on ccvm's LAN and the station traded some 48,000 packets a second for over ten minutes with no request among them: the phone's of QUIC's smallest size (room for a PING or an IMMEDIATE_ACK only), the station's ACK-only. Neither kind is held back by congestion control or pacing in noq, so it ran at what the LAN took, four station threads half busy, until the phone's Wi-Fi went off. What kept the phone asking is not known yet (suspects: `network_change` pinging every path with an ACK request on each suspecting wake, or tail-loss probes built up).

The station looks at each connection's counts every second (`Connection.stats`: packets and the frames in them; `station/src/mesh/storms.ts`). One receiving 1,000 packets a second or more, at most one in 50 carrying data, logs `a connection is storming` once with that second's counts and its paths, and is closed (code 5, `storm`) once it has gone on 10 s; the device connects again. Next time one shows, its line says which frames went which way.
