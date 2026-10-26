# bench/signals: mbui's signals against JavaScript's, and in still.fail's own use

[js-reactivity-benchmark](https://github.com/transitive-bullshit/js-reactivity-benchmark) at 2c273f1 (2026-09-19:
alien-signals 3.2.1, Preact Signals 1.14.4, Vue 3.5.43, Solid 1.9.15, Angular 22.1.7, Svelte 5.57 and nine more,
every case's result checked), run as it is, beside its five suites ported case for case to MoonBit (`src/native`) on
mbui's signals (`src/signals`) compiled natively as still.fail's apps are (`scripts/mbc`'s split C): its sizes, its
checks and its timing boundaries, and its random graphs drawn by the same generator, so they are the same graphs.
`native.exe self` checks the graphs of the benchmark's adapter tests and how many times their computeds ran
(alien-signals' counts).

```sh
bench/signals/run.sh                              # every engine, about 10 minutes on an M4: out/report.md
ENGINES=alien,preact,vue REPEATS=5 bench/signals/run.sh
```

Each suite of each engine runs in a process of its own; a case is the fastest of `REPEATS` samples after a warm-up.

## What to read

The report's first table: each case's time over alien-signals', on the 29 cases that measure the engine. The other
five measure something else: molBench's time is mostly its Fibonacci (native code computes it about three times as
fast as V8), CellX times one update of a few microseconds (in JS mostly a function not yet optimised, and the clock),
and kairo's `mux` builds an array natively where the benchmark builds an object.

Natively, what a sample made is let go after its clock stops, as a JS engine's collector takes back what a sample
made outside the timed samples (explicit `gc()` between them); `mem` checks that what is made and let go is freed
(300 rounds of every graph, the resident memory before and after).

## 2026-10-26, Mac mini M4, Node 24.22.1

Time over alien-signals', geometric mean (lower is better):

| Engine | kairo (no mux) | s: create | s: update | dynamic | all 29 |
| --- | ---: | ---: | ---: | ---: | ---: |
| mbui signals (native) | 0.98× | 0.84× | 0.75× | 0.71× | 0.83× |
| alien-signals | 1.00× | 1.00× | 1.00× | 1.00× | 1.00× |
| Preact Signals | 1.22× | 1.60× | 1.13× | 1.33× | 1.33× |
| @vue/reactivity | 2.03× | 1.55× | 1.36× | 1.70× | 1.63× |
| @angular/signals | 2.80× | 2.81× | 1.46× | 2.51× | 2.35× |
| Svelte v5 | 4.65× | 2.18× | 3.66× | 2.19× | 2.97× |
| SolidJS | 4.24× | 2.21× | 3.67× | 3.48× | 3.16× |
| MobX | 3.94× | 4.88× | 2.35× | 2.58× | 3.48× |

Before the port kept a node as one object, its stacks as arrays and its reads' checks in place (docs/signals.md,
"Under reference counting"), native was 1.23× (create 1.83×). The machine's other work moves a run's JS engines by
up to a third (alien-signals' own times from run to run): compare runs by alien-signals' times before reading ratios.
What is left on kairo is mostly its numbers: a computed of a Double boxes its value in an Option each time it changes.

## The app's own use: record.sh, replay.sh

What still.fail's app does with the signals is not what the benchmark above does: no effects; each frame a few dozen
to a hundred and thirty reads, nearly all of a value that did not change; one set (the frame); a computed run in
some frames; parts kept on Medium read again for their part (`reading`) and invalidated. So the app's use is its own
benchmark:

```sh
bench/signals/record.sh     # a Mac: the app filmed offscreen (src/sffilm) through scripted flows, every call into the
                            # signals written down (record/trace.patch on a copy), a trace a flow in traces/
bench/signals/replay.sh     # any machine: every trace done again on the signals as they are now, checked and timed
```

`replay` makes every signal and computed as the app did, in its order, and a computed's getter, run where the
signals run it, does again what that run of the app's did; it stops where a computed runs a time more or less than it
did in the app, so a change to the signals that changes what runs is caught too. Only the signals' own work is timed:
the app's builds, layout and drawing are not in a trace. A flow whose script did not pass (files-browse,
search-medium) is kept as far as it went: what the app did meanwhile is as real.

2026-10-26, Studio (M2 Max), 18 flows, 7664 frames, phone, fold (Medium) and desktop windows:

| | reads | runs | sets | µs |
| --- | ---: | ---: | ---: | ---: |
| a frame, on average | 93 | 0.4 | 1 | 0.47 |
| the busiest flow's frame (fold-composer, tape-images) | 125 | 1 | 1.1 | 1.09 |

A frame at 60 Hz has 16 667 µs: the signals take 0.003% of it, at most 0.007%. Make the signals faster for what this
measures, not for the benchmark above; and a change that makes them slower here matters only if it shows in a frame.
