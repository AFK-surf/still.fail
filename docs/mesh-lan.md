# A station on the device's LAN

A device on the same LAN as a station reaches it directly, on an endpoint that dials the station's LAN addresses and
nothing else. It does not rely on iroh's hole punching.

## Why

On 2026-10-17, a phone and several Macs on one LAN (studio, mini1, ccvm) connected to stations through a relay first,
the way every link starts. iroh then punched a path to the station's LAN address. That path went quiet a few seconds
after it opened: one end's packets stopped reaching the other, though the same addresses and ports carried plain UDP
both ways without loss. iroh lets a path go after hearing nothing for 15 s (`PATH_MAX_IDLE_TIMEOUT`), and requests on it
waited that long each time before going back through the relay. A connection dialled straight at the station's
address (its path 0, no relay, no punching) stayed direct for minutes with little loss. The cause in iroh is not
known yet.

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
