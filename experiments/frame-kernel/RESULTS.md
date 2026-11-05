# Evidence for the independent runtime slice

Baseline: `351cef2857f2b281a25728363e9416fbc6b469bb`.
Combined experiment: `b4217adac8`. No production app imports this module.
The subsequent production integration implements intrinsic geometry dependencies
in `mbui/view` and uses them in the real chat composer/list; it does not run the
application on the experimental kernel.

## Actual application integration

The initial integration replaced the chat list's read of its composer's previous
layout with an intrinsic-height expression. Real editor measurement and the
existing application renderer were used, with the 3000-message `chat-long`
fixture. Small-screen input and medium/large-screen stills were rendered before
and after. Their final PNGs were byte-identical.

This was insufficient as a performance change. On the same three-line input,
the first integration increased layout calculations from 6 to 17: marking an
input stale invalidated consumers even when a minimum kept their resulting
height unchanged. Separating a stale measurement from a changed output brought
that count back to 6. A second counterexample showed that an unchanged consumer
was still placed again when another branch needed layout; measurement caches and
placement validity now have separate invalidation. The combined flex/view suite
passed 848 tests after that change.

The six-line real-input control remains an explicit failed performance result:
before that final placement separation, baseline and integration did 23 and 24
layout calculations, respectively (416/442 placed nodes and 12/36 measurements).
Both final pictures have SHA-256
`bbb165b1c9b3cc30e5facc7a58bd397d7e4f1eca11f11ebac125952a251360d3`.
Thus matching appearance and removing one feedback edge did not by themselves
make the application cheaper. The virtual list still consumes row-layout
notifications and recomputes its allocation.

These replays use classic Wasm in Node, the real app, native text metrics and
offscreen rendering. They establish work counts and appearance, not Android
Wasmtime frame times. The shared build machine's changing load also prevents
comparing the elapsed times from separate runs as a speedup.

The next comparison changed only the production list's position accumulation:
an interval index replaces copying and summing all historical rows whenever a
visible row's height changes. A 30/3000-row regression first failed on the old
accumulator (`30 != 1` updated rows), then passed with the index. The view suite
passed 282 tests and the scoped composer/list application suite passed 28.

| Actual `chat-long` replay | Old accumulation | Interval index |
| --- | ---: | ---: |
| Six-line input: row records processed | 15,010 | 5 |
| Six-line input: index intervals visited | 0 | 612 |
| Six-line input: layout calculations / placed nodes | 24 / 402 | 24 / 402 |
| Three drags: row records processed | 3,002 | 3,002 |
| Three drags: index intervals visited | 0 | 6,099 |
| Three drags: layout calculations / placed nodes | 10 / 664 | 10 / 664 |

The input replay demonstrates avoiding repeated history accumulation. At this
stage the drag replay still rebuilt all row positions once and did not
demonstrate less work. Both final pictures match their controls byte-for-byte. The drag picture's
SHA-256 is
`7cf58a282349d50408f55d30aaf59d49c3f2720608a9e03e4e25d4ed42933554`.
Index interval visits are a different kind of operation from row processing;
these counts are not a wall-time ratio.

### Separate model inputs from motion completion

The remaining drag rebuild occurred at motion completion: the reaction reread
the page's row callback and produced a new array with the same keys in the same
order. Neither the grid nor the key contents had changed. `ListRows::in_node`
now captures items, ordered keys and independently reactive content versions in
computed values. Motion completion reads those values without reevaluating the
model. Unchanged ordered keys retain their array identity. Content versions keep
their own dependency tracking, including edits after the preceding motion ends.

The 30/3000-row counterexample failed before the change because completing a
motion reread the unchanged model. Both new tests then passed with the scoped
list suite (28 tests); the composer/list application suite also passed 28 tests.
The implementation is committed as `5d2eb4d540`.

| Actual `chat-long` replay | Interval index only | Separate model inputs |
| --- | ---: | ---: |
| Six-line input: row records processed / intervals visited | 5 / 612 | 5 / 612 |
| Three drags: row records processed / intervals visited | 3,002 / 6,099 | 0 / 1,944 |
| Three drags: layout calculations / placed nodes | 10 / 664 | 10 / 664 |
| Three drags: nodes created / released | 130 / 127 | 130 / 127 |

These counts exclude initialization. New visible rows still receive their normal
construction, measurement and layout. This change removes an unrelated rebuild
of history; it does not claim that processing a changed input collection is O(1).
The final input and drag PNGs have the same hashes as the controls above.

The complete scripted input and drag replays were also rendered at 60 Hz against
the original pre-integration runtime, using the same native text and offscreen
GPU host. Decoded frame hashes match for all 18 input frames and all 78 drag
frames. Representative whole-screen drag frames were inspected. These videos
cover the scripted intervals through their `exit`, not every possible
interruption, rate or subsequent animation tail. They establish appearance for
these operations, not Android execution times. The comparison baseline remains
`351cef2857f2b281a25728363e9416fbc6b469bb`; it is not the subsequently updated
`arch/next` or a deployed build.

## Contracts and counterexamples

The scoped Wasm-GC suite passed 29/29 tests. These cover controlled model
writes, dynamic read dependencies, parent allocation using the real editor's
measurement, sparse/dense-frame equivalence, interrupted trajectories,
projection and hit testing, variable-height indexing and exact fractional
boundaries. Three controls retain the observed baseline counterexamples.

Restoring `scroll.sample(presented_at)` in place of `scroll.sample(now)` made
`presentation prediction cannot move the layout's scroll moment` fail. Restoring
the implementation made the full suite pass. The display prediction cannot be
used as a hidden layout clock.

The bounded classic-Wasm executable passed under Wasmtime 50.0.1 with a 512 KiB
Wasm stack: 30 and 3000 rows, 25 cycles each, including layout, interrupted page
motion and scroll contracts. Its warmed 3000-row index read four rows, visited
19 intervals and measured zero rows. Changing a crossed row remeasured one row.

## Isolated calculation cost

Measured on a shared M2 Max build machine under concurrent load, using classic
Wasm and Wasmtime. Each workload was calibrated independently toward 300 ms;
the table preserves the iteration counts and all three integer-ms samples.
The linear reference is our own resolver, not the production application's UI.

| Workload | Iterations per sample | Milliseconds |
| --- | ---: | --- |
| Change one visible row, 30 total | 28232 | 349, 339, 318 |
| Change one visible row, 3000 total | 23465 | 288, 291, 303 |
| Warm indexed scroll, 3000 integer-height rows | 65043 | 406, 356, 566 |
| Warm indexed scroll, 3000 fractional-height rows | 65755 | 280, 293, 557 |
| Linear reference scroll, 3000 rows | 2133 | 253, 359, 360 |

The single-row update remains in the same cost range with 100 times as many
source rows. The index avoids rereading crossed history. Timing variance is
substantial: these are calculation-cost checks, not phone frame times or a
before/after application benchmark. BigInt extent storage also needs memory and
real text workloads before choosing a production representation.

## Lifetime and memory

The separate bounded executable allocates a 3000-row kernel, crosses and mutates
history, ends its semantic owner through an immediate input, and checks that the
query and visible leaves are released without drawing an exit frame. A late
input cannot revive it.

In Node/V8 with classic Wasm, 100 warm-up lifetimes followed by 500 measured
lifetimes kept linear memory at 8,912,896 bytes (8.5 MiB) throughout. Deliberately
retaining eight approximately 4 MiB allocations raised the allocation high-water
mark to 71,303,168 bytes (68 MiB), so the observation can detect growth. Linear
memory does not shrink when allocations are released. A plateau plus explicit
resource checks is useful evidence for this workload, not a universal leak proof
or an Android memory measurement.

## Remaining adoption evidence

The experimental kernel does not yet demonstrate a general owner tree, full
input/IME, stable-key history insertion/removal or recorded font/resource changes.
Production integration has exercised actual chat input and scrolling, including
the frame comparisons above, but retains the existing runtime's owner, event and
rendering system. It still performs repeated layout and does not enforce the
experimental model's write permissions or frame-independent semantic ownership.
Android development-target frame and memory measurements remain necessary; the
phone goal is not achieved by the results above.
