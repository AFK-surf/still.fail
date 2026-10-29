# The performance record (性能记录)

Settings › 关于 › 诊断 › 性能记录, on iOS (other hosts keep none: the row is not shown). On, the app writes what the
device spends its time on to files of its own, every 5 s, until it is turned off; it starts again with the app while
it is on (a setting of the device's, not synced). Nothing leaves the device. It is MBUI_PROBE=1's probe, kept in a
file, with what it takes to find the culprit, not only the totals.

## Where it is

`Documents/perf/perf-YYYYMMDD.log` in the app's container (past 5 MB, `perf-YYYYMMDD-2.log`, …; the 3 newest files
kept). Off the phone:

```sh
xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
  --domain-identifier fail.still.mbui.devpx --source Documents/perf --destination perf
```

Each line is `<local time> <what>: …`. The app's lines come as it draws (every 5 s of frames); the host's every 5 s,
drawn or not. Off, nothing runs: no timer, no file touched, a flag read each frame.

## The lines

| line | from | says |
| --- | --- | --- |
| `perf: on (launch / turned on) device=… app=… thermal= lowpower= battery=` | ios_app.m | where a run begins |
| `ios: cpu=N% thermal=T mem=MB battery=state/level lowpower=` | ios_app.m | the whole process's share of one CPU (100% one core busy throughout); thermal 0 nominal, 1 fair, 2 serious, 3 critical |
| `threads: name=N% …` | ios_app.m | the 8 busiest threads by name: `main` (the app: build, layout, paint, present), `still.fail_core` (Hermes, the core's JS), the decoders, tokio's (the shell: network, iroh), `com.apple.*` |
| `core js: busy=N% tasks=N 120ms/30 shell:fetch \| 80ms/2 app:chat.send \| …` | apple_core.mm | the core's thread by what each task was: `app:<call>`, `app:sub <topic>` (asked by the app), `shell:<op>` (the shell's answer to what the core asked: its JS handling it), `timer` (a JS timer), `task` (anything else) |
| `shell: tap.views=… istream.read=… ops: name=N …` | apple_core.mm | what the Rust shell did: the remote screen's taps, and the 6 operations asked most since |
| `frames: fps= cpu= looks_alone= painted_alone= main_busy= avg msgs/build/layout/paint/present= drawn whole/part/none= gpu_avg= slow=` | mbui app.mbt | the main thread's frames: how many, how busy, where each frame's time went on average, how much of the window each drew, the GPU's time, frames slower than 24 ms |
| `frames why (the 5 heaviest, ms/frames): 310ms/120 built: the clock read at src/…:42 \| …` | mbui app.mbt | what the frames were for, by why (frame_watch.mbt's `built_why` / `painted_why`, `looks` for the looks alone), each its main-thread work and count |
| `frames heaviest: Nms <why>` | mbui app.mbt | the slowest frame and why it was |
| `messages (bytes/count, by channel): …` | mbui messages.mbt | what was posted to the app (`core`, the screens', the system's), each its bytes and count |
| `core: in (ms/count/KB, the 6 longest): 3.2ms/12/40KB topic chats delta \| … \|\| out (count, the 6 most): 4 chat.read \| …` | src/core | what the core said to the app, by topic (`value`, `delta`, `error`) or call (`answer`, `progress`), each the app's time taking it on the main thread, its count and size; what the app asked of the core |
| `page: Chat` | src/sfbase | the page on top |
| `screens: h264 1920x1080 asked=/60fps fps=58 kbps=8000 phase=open` | src/sfpages | each remote screen open: what it decodes, what it asked for, what came |
| `present avg: ring wait, upload, drawable wait, encode` | apple_render.m | every 240 presents, where a present's time went |
| `app: foreground / background`, `app: screen shown / hidden / closed <key>`, `thermal: N`, `lowpower: on/off`, `power: battery=…` | ios_app.m, screen_view.mbt | what changed: line the heat up against these |

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
