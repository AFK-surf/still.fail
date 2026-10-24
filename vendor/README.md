# vendor

Crates taken from crates.io, and Swift packages the native apps build in, changed for still.fail; `[patch.crates-io]` in
mesh/ and client/ points at the crates. Each change is marked `ember:` in the source. Drop one here once upstream has
the same.

- **PermissionFlow** (Swift, EYHN/PermissionFlow at 9b02967, as Cue's Computer Use pins it; only SystemSettingsKit and
  PermissionFlow; station/native/screen uses it for its permission window)
  - Cue's patches (Cue `systems/connector/salix-connect/native/macos/patches/`): the panel lists the steps
    (`guidanceSteps`) with a header that keeps its width, the drag card says the app's display name, its "Drag" label
    is the localizer's.
  - The floating panel takes any file to drag, not only an `.app` (PermissionFlowController.swift).
  - Its words are the host's (`PermissionFlowLocalizer.words`, the station's language), not a resource bundle: the
    helper ships as one app with nothing beside its executable. PermissionFlowButton (unused, its words a bundle's)
    is left out.

- **serve-sim** (Swift, EvanBacon/serve-sim at 0193e65, `packages/serve-sim/Sources`, Apache-2.0; still.fail Helper's
  `simulator.view` uses it, docs/remote-screens.md "Simulators"): only the iOS Simulator's capture and input,
  `SimNative/{FrameCapture,HIDInjector,DeviceHubKeyboardBridge,DuoHIDBridge,PixelBufferUtils,SimFrameworks,Xcode}.swift`
  and the `SimNativeSupport` they use; not its Node module, encoders, recorder or accessibility dumps. Package.swift is
  ours (no node-swift).
  - Shared.swift: what FrameCapture takes from upstream's files left out (PixelConsumerCount, isoTimestamp,
    jsonString), as they are there.
  - FrameCapture and HIDInjector, and the methods the helper calls, are public (another module uses them).
  - FrameCapture re-emits a still screen's picture at its 5 fps idle floor only when asked (`setReemitsIdle`): the
    helper encodes a picture only when it is new.

- **swarm-discovery 0.6.3**
  - src/receiver.rs: a peer's addresses are read from the answers as well as the additionals, and records with
    mDNS's cache-flush bit count as class IN. A router reflecting mDNS between subnets sends the addresses on as
    answers, which 0.6.3 dropped, so a station on the other subnet was never found.
  - src/sender.rs: the first query goes out 20–120 ms after starting (RFC 6762 §5.2) instead of a whole cadence
    (0.7 s, pushed back further by others' queries) later.
  - src/socket.rs: a failed send on one interface (a VM bridge that takes no multicast) is logged at debug, not
    error, and failing on every interface is said once when it starts (and once when it ends), not with every
    announcement: both recur with each one (twice a second on a Mac that denies the process the local network).
- **iroh-mdns-address-lookup 0.4.0** (src/lib.rs)
  - Multicast goes out on, and is received from, every local IPv4 interface (swarm-discovery's `add_interface_v4`),
    not only the default route's. A machine on two networks (studio: wired 192.168.0.x, Wi-Fi 192.168.20.x) was
    only announced on the first.
  - Without advertising (ember's devices: they only look stations up), the interfaces are still joined.
  - A republish (same addresses and TXT) is not a new discovery: `Peer`'s equality includes when it was seen, so
    every mDNS packet reached the endpoint as new addresses (also reported upstream-side in rayfish/rayfish#161).
- **iroh 1.0.3** (src/socket/remote_map/remote_state.rs): an address waiting to open a path (the connection out of
  path ids or the remote's CIDs) is queued once, not again by every connection that still cannot open it at each 333 ms
  retry. With two or more connections to a remote at the limit the queue multiplied each time, to gigabytes
  (n0-computer/iroh#4390; upstream's fix #4551 is merged but in no release yet).
- **iroh 1.0.3** (src/socket/remote_map/remote_state.rs): the Initial packets sent to every known path before one
  is selected are kept, and sent at once to addresses that Address Lookup finds afterwards. Without it a station
  found by mDNS a moment after the dial (the relay down or unreachable) was only tried at QUIC's next Initial
  retransmit, 1 s or 3 s after the first: LAN connections took 1–6 s.
- **noq-udp 1.3.0** (src/linux.rs): no UDP segmentation offload (GSO) on Android, each datagram sent on its own. An
  Android emulator's network accepts a segmented burst and drops all of it; QUIC on a direct path then got nothing
  through once it sent more than a packet or two at once, until iroh dropped the path 15 s later (docs/mesh-lan.md).
- **noq-udp 1.3.0** (src/unix.rs): on Apple platforms a datagram's source address is set with `IP_PKTINFO`. It was
  set with `IP_RECVDSTADDR`, which macOS ignores on send, so a reply left from the address the routing table picked.
  On a machine with two addresses on one network (studio: 192.168.20.10 on the wired VLAN, 192.168.20.107 on Wi-Fi) a
  device that had dialed one got the answer from the other, and the handshake never finished: the station dropped
  what came back as sent to the wrong interface.
