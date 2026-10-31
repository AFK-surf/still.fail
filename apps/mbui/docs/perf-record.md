# The performance record (性能记录)

Settings › 关于 › 诊断 › 性能记录, on iOS (other hosts keep none: the row is not shown). On, the app writes what the
device spends its time on to files of its own, every 5 s, until it is turned off; it starts again with the app while
it is on (a setting of the device's, not synced). Nothing leaves the device. It is MBUI_PROBE=1's probe, kept in a
file, with what it takes to find the culprit, not only the totals.

## Where it is

`Documents/perf/perf-YYYYMMDD.log` in the app's container (past 5 MB, `perf-YYYYMMDD-2.log`, …; the 3 newest files
kept). Off the phone: **分享记录** under the switch (shown once anything is written) hands the files on as one,
oldest first (`still.fail-perf.log`, @hostapi.perf_read) through the system's share sheet: AirDrop to a Mac, Mail, a
chat. That is the way for a release build: the Files app shows nothing of the app's (no `UIFileSharingEnabled`), and
`devicectl device copy from --domain-type appDataContainer` reads only an app signed for development (with that build's
bundle id as `--domain-identifier`).

Each line is `<local time> <what>: …`. The app's lines come as it draws (every 5 s of frames); the host's every 5 s,
drawn or not. Off, nothing runs: no timer, no file touched, a flag read each frame.

## The lines

| line | from | says |
| --- | --- | --- |
| `perf: on (launch / turned on) device=… app=… thermal= lowpower= battery=` | ios_app.m | where a run begins |
| `ios: cpu=N% thermal=T mem=MB battery=state/level lowpower=` | ios_app.m | the whole process's share of one CPU (100% one core busy throughout); thermal 0 nominal, 1 fair, 2 serious, 3 critical |
| `threads: name=N% …` | ios_app.m | the 8 busiest threads by name: `main` (the app: build, layout, paint, present), `still.fail_core` (Hermes, the core's JS), the decoders, tokio's (the shell: network, iroh), `com.apple.*`; an unnamed one `gcd` (a dispatch queue's worker as it was asked) or `?` |
| `shell stacks: shell=N% for 10s, binary <UUID>` then `shell stack: #N thread <id> +0x… libsystem_kernel.dylib:kevent+8 …` | ios_app.m | where the shell's threads (`stillfail-shell`: tokio's, the network's) kept 80% of a CPU or more for two ticks running: each of them sampled 3 times a tick, one after another, for at most 12 ticks (a minute) of one stretch; frames innermost first, `+0x…` an offset in the app's binary (the build whose UUID the first line says: `atos -o <its binary> -l 0x100000000` on 0x100000000 plus each), else the system library's symbol |
| `core js: busy=N% tasks=N 120ms/30 shell:fetch \| 80ms/2 app:chat.send \| …` | apple_core.mm | the core's thread by what each task was: `app:<call>`, `app:sub <topic>` (asked by the app), `shell:<op>` (the shell's answer to what the core asked: its JS handling it), `timer` (a JS timer), `task` (anything else) |
| `shell: tap.views=… istream.read=… ops: name=N …` | apple_core.mm | what the Rust shell did: the remote screen's taps, and the 6 operations asked most since |
| `frames: fps= fps_peak= span= cpu= looks_alone= painted_alone= (last: …) main_busy= avg msgs/build/layout/paint/present= drawn whole/part/none= gpu_avg= slow=` | mbui app.mbt | the main thread's frames since the last summary, said as the first frame after its 5 s comes (`span`: how long that was, longer where nothing was drawn for a while): how many a second on average and in its busiest second (`fps_peak`: a burst not averaged away by a pause after it), how busy, what its last frame was for, where each frame's time went on average, how much of the window each drew, the GPU's time, frames whose own work took longer than 24 ms (a pause before a frame is not one) |
| `frames why (the 5 heaviest, ms/frames): 310ms/120 built: the clock read at src/…:42 \| …` | mbui app.mbt | what the frames were for, by why (frame_watch.mbt's `built_why` / `painted_why`; `looks: cycles at src/…` for the looks alone, where each cycle drawn was said, Ctx::cycle_look), each its main-thread work and count |
| `measures: 150 now-room/… 39x18 to 0x18 \| 150 emit-tail/… not laid out \| …` | mbui motion/layer.mbt | the measures (measure, measured_size, measured_rect) that told what read them since the last summary, the 6 most told first, each its count, key and why: its size from to, `laid out again` / `not laid out` (gone a frame, back the next: a reader that measures only some frames), `moved`, `first`, `forgotten`. A row built again each frame for a measure shows here by its key |
| `frames heaviest: Nms <why>` | mbui app.mbt | the slowest frame and why it was |
| `messages (bytes/count, by channel): …` | mbui messages.mbt | what was posted to the app (`core`, the screens', the system's), each its bytes and count |
| `core: in (ms/count/KB, the 6 longest): 3.2ms/12/40KB topic chats delta \| … \|\| out (count, the 6 most): 4 chat.read \| …` | src/core | what the core said to the app, by topic (`value`, `delta`, `error`) or call (`answer`, `progress`), each the app's time taking it on the main thread, its count and size; what the app asked of the core |
| `page: Chat` | src/sfbase | the page on top |
| `screens: h264 1920x1080 asked=/60fps fps=58 kbps=8000 phase=open` | src/sfpages | each remote screen open: what it decodes, what it asked for, what came |
| `present avg: ring wait, upload, drawable wait, encode` | apple_render.m | every 240 presents, where a present's time went |
| `app: foreground / background`, `app: screen shown / hidden / closed <key>`, `thermal: N`, `lowpower: on/off`, `power: battery=…` | ios_app.m, screen_view.mbt | what changed: line the heat up against these |

## Connections

What the core does to reach the stations and still.fail cloud, written by the core (client/core-ts record.ts) into the
same record while it is on; off, nothing is formatted (each place asks first, one call to the host). Nothing in them
changes what the core does. Rare things a line each; what goes on all the time (each way's packets) a line per station
per 5 s tick of its ways.

| line | from | says |
| --- | --- | --- |
| `conn dial: #N <ws>/<station> via=main\|main+addresses\|relay:<host>\|lan\|tailnet onto= credential= dialled= openBi= sent= total= -> ok\|no-answer\|interrupted\|error: …` | mesh.ts open | each dial, numbered: through which endpoint (the main one, at the addresses the station said, a relay's own, the LAN's, the tailnet's), each stage's time from its start (`onto`: on a relay; `credential`: the station's credential had; `dialled`: the QUIC connection made; `openBi`: its stream; `sent`: the credential sent; `-` not reached), how it ended (`no-answer`: nothing in CONNECT_TIMEOUT_MS) |
| `conn rebind: a dial unanswered, nothing open -> bound \| relays retold -> … \| skipped: Nms since the last (REBIND_MS)` | mesh.ts #rebind | the main endpoint bound anew, and why |
| `conn stuck: <station> not rebound: N link(s) open` | mesh.ts link | a dial left unanswered before, the endpoint not bound anew as links are open on it |
| `conn network-change: told the main endpoint (the network changed \| retry \| the UI back after Ns), N link(s) open, N relay endpoint(s) not told` | mesh.ts #watch | a wake (the system's network change, 重试, the app back) told to iroh |
| `dht: dht#N read failed #n: <kind> [(os error N)], next read in Nms \| binding anew failed: … \| bound anew: port A -> B \| reads back after n failed, Nms after the first \| lookup <id8> asked [again, joining the one going] \| first answer after Nms \| done after Nms: N answer(s) (Nms before)` | record.ts recordDht (the shell's `dht.said`, vendor/n0-mainline's ember) | the DHT lookup's socket and lookups, kept while the record is on however long between takes (a phone back after minutes away says what its socket did then), taken at most once a tick, as each dial starts and ends, and at each wake; `(Nms before)`: when it happened. A failing socket says its first 3 failures and then each power of two; at most 64 lines between takes (`N line(s) dropped`). `reads back`: a datagram came in on the socket again (not yet a valid DHT answer: that is a lookup's `first answer`). A lookup names the station by its id's first 8 and says when, not which dial it served |
| `conn ways: <station> <way> in=+B out=+B missed=N [*<relay or address> <rtt> +sent/lost; …] \| …` | mesh.ts #steer | each 5 s tick of a station's ways (where it has more than one to choose between): bytes in and out of each link since the last, its pings missed in a row, each path's packets sent and lost since (`*` the one in use) |
| `link miss: <station> misses=N/12 cloud=up\|down -> reconnecting\|offline\|error: <why>` | station/link.ts | a try at the station's event stream that did not open; `cloud`: still.fail cloud's socket as it was (any account's) |
| `link wait: <station> Ns (backoff \| answered \| brief streams \| tried seldom: LONG_MISSES \| tried seldom: the cloud says offline) misses=N why=…` | station/link.ts | how long until the next try, and why that long |
| `link woke: <station> by its time \| a wake (UI back, network, retry) \| the cloud or its pings (back) after Ns` | station/link.ts | what ended the wait |
| `cloud socket: <account> open after Nms [(after a failed open: stations not reached tried now)] \| open failed after Nms: … \| ended after Ns: silent\|dropped` | sync/cloud.ts | still.fail cloud's events socket; the first open after a failed one wakes every station not reached (`networkBack`) |
| `net: path satisfied\|unsatisfied\|satisfiable ifaces=pdp_ip0/cell,en0/wifi,… expensive= constrained= ipv4= ipv6= -> said: the network changed \| not said (the same interfaces) \| the first seen` | ios_app.m | every update of the system's network path as it comes, whether the app took it for a change (the interfaces compared whole: under a VPN the first is always its tunnel) |

Reading a stuck reconnect: find the station's `link miss` lines; each is followed by `link wait` (how long and why)
and later `link woke` (by what). A wait of 600s (`tried seldom`) with no `link woke` before it ends means nothing woke
it: look for `cloud socket … open` (it would) and `net: path … said` (it would). The `conn dial` lines of the same
minutes say where each try stopped: `onto=-` (no relay reached), `dialled=-` with `no-answer` (no QUIC connection in
time: the station or the way), `openBi`/`sent` missing (the connection made, then lost). `conn stuck` with links open
means the endpoint was not bound anew for them. A station the DHT is asked about (`dht: … lookup <id8>`) in the
same seconds as its dial, with `done after …: 0 answer(s)` or a socket failing (`read failed`) before it, could not be
found through the DHT then (that lookup had no answer; a later one may); whether that is why the dial failed the lines
do not say: `via=main+addresses` means the dial had addresses given, and `via=main` without them may still have had a
relay or addresses iroh kept, so neither says whether the dial needed the DHT.

## From a warm phone to the culprit

1. Find when it got warm: `thermal:` lines, or `ios: … thermal=2`. Look at the `ios: cpu=` lines before it. Under
   ~30% for minutes rarely warms a phone; 100%+ (more than a core) does.
2. Which thread: `threads:`. `main` high → the app's frames (3). `still.fail_core` high → the core's JS (4). tokio's
   or the decoder's high with a screen open → the remote screen's stream (5). `com.apple.*`/`?` high → the system
   working for the app (Metal, the decoder, networking).
3. The main thread: `frames:` gives fps and `main_busy`. A page at rest should draw nothing: fps near 0. If fps stays
   high at rest, `frames why` says why each frame was built or painted, with the place in the sources (a clock read, a
   moment waited for, what a read changed and where it was set); the heaviest of them is the one to fix. High
   `avg … build` with few frames: building is slow (nodes=); high `present` or `gpu_avg`: the GPU's side (`drawn
   whole/part/none`: whole frames redrawn for little).
4. The core: `core js:` says which task kind the core's thread spent its time on (an app call, a shell answer, a
   timer). `core: in` says which topic's messages cost the main thread the most and how big they were: a topic
   changing many times a second, or a whole value sent each time instead of a delta, shows there; `out` shows the app
   asking the same thing again and again.
5. A remote screen: `screens:` fps and kbps against what was asked; `shell: tap.*` whether its frames go straight to
   the decoder (`tap.direct.video` close to `tap.video`) or through the app's queue.
6. Read it against what happened: `app: background` (iOS stops the app soon after: no lines), a screen opened,
   charging (`battery=charging` warms a phone by itself), low power mode.

## What it costs

Off: one flag read per frame and per core task. On: counters and sums, one map entry per frame's why, per core task
kind and per core message kind; each 5 s a few lines appended (a file opened, written, closed on a queue of its own).
The per-slow-frame lines of MBUI_PROBE=1 are not written (counted as `slow=`). MBUI_PROBE=1 still prints its lines on
the log as before, with or without the record.
