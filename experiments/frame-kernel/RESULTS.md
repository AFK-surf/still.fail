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

## Android measurements and the current architecture reference

The development app was built as classic Wasm and compiled with Wasmtime 50.0.1
for aarch64 Android, using the same APK shell for each source state and a 512 KiB
Wasm stack. The fixture needed its native input allocation exports added before
the native text-input path could run. This did not change the host ABI.

The first host timing record started after the retained tree had already been
built and laid out. A charged-work regression failed on that implementation;
moving the start before the retained tree made the five timing/record tests
pass. The production work figure now includes that tree. Its legacy build,
layout and paint components still describe the old-frame portion; they must not
be summed and presented as all work. Temporary instrumentation also measured
input callbacks outside the frame, host presentation, the drive and the tail.

The second Android comparison explicitly waited for the keyboard's inset
callback before typing. All four six-line input runs had the same reported
keyboard inset (279.0769348144531), 11 measured frames and 17 input callbacks.
Runs were ordered baseline, experiment, experiment, baseline. The complete
framework-work totals were respectively 72, 76, 37 and 237 ms; their largest
single frames were 25, 18, 9 and 138 ms. Input-callback totals were 60, 99, 38 and
211 ms. These shared-machine measurements do not establish a stable speedup.
The scroll runs also had different frame counts, so comparing their totals or
number of frames as a speedup would be invalid.

The open-chat scenario failed in both states because its script looked for the
chat page's title on Home. The actual Home row is `整理发布清单`; it is not
`一个很长的对话`. This was a script failure, and the run's successful shell exit
does not make that scenario pass. The final input screenshot was also not proof
that the last text update had reached drawing: the `field` assertion reads the
editor's value. The next diagnostic records the matching text at its paint site.

The current architecture reference is pinned separately at
`2e870349057312211e7ac1de96d6e6371fd9f5a2`. It already has anchored chat history
and logical-time layout changes absent from the original baseline above. The
experimental integration must be compared with this reference before claiming
it improves on the current architecture. A separate branch applies only the
model/motion dependency boundary, native input exports and complete-frame
accounting to that reference (`ce0ae7f3ec`); its 33 framework and 28 chat tests
pass. It does not adopt the experimental intrinsic-height graph or extent index.

### Actual-host correctness and scheduler attribution

A subsequent three-way run used that pinned current reference, the independent
integration and the narrow reference changes, with the same Android shell and
keyboard inset. Current and narrow-reference open/scroll/input scripts completed.
The independent integration terminated with SIGILL while leaving the chat. Its
eight fake-host classic-Wasm open/back cases subsequently passed at the same
512 KiB stack limit, at both screen scales and with/without the top bar. That
probe therefore does not explain or clear the actual Android failure.

More importantly, all three input screenshots showed five text lines with an
empty sixth-line caret, even though the model and the renderer's emitted text
contained all six lines. A successful script or matching draw list was not
sufficient evidence of a correct displayed frame. The final host record sent
no damage region for that changed text.

The cause is at the retained-paint boundary: a drawing dependency marked its
layer's instances stale, but did not add either the previous or new drawing
extent to the host's damage. Layout-originated changes already supplied those
extents. Paint-only text updates therefore changed the draw list while a partial
renderer preserved the previous pixels. A new input regression failed with
`changed=true`, 23 recorded instances and `damage=[]`. Carrying paint dependency,
timed wake and glyph-retry changes through previous/new extent invalidation made
the complete UI package pass 1624 tests, including caret disappearance and
reappearance. The narrow reference change is `1de556022c`; actual-host visual
confirmation is still required before calling it complete.

The traces join explicit frame-phase timestamps to the same GL thread's
scheduler records. Measured intervals have complete recorded state coverage.
The current-reference scroll's 57 measured frames contained 806 ms of complete
callback time: 399 ms scheduled as running, 405 ms runnable and 2 ms blocked.
The framework-work portion was 384 ms, of which 187 ms was running; tree work
was 31 ms and drawing/old-frame work was 353 ms. Thus a large part of elapsed
time was scheduling, but the remaining framework work was mainly outside the
new tree's layout boundary. On opening, the current reference's worst drawing
interval was 133 ms, with 111 ms running. It cannot all be dismissed as thread
waiting.

These are diagnostic classifications, not an adoption speedup: frame schedules
differed, the emulator's running state does not exclude host-side virtual-CPU
descheduling, and input presentation was incorrect. The trace configuration
also reported missing flush/discard-buffer configuration warnings and unsupported
ftrace setup events; interval coverage was checked rather than assuming every
requested event was recorded. Both current and narrow-reference startup logs
reported hitting the 512-pass layout guard. Those loops and the independent
Android trap remain correctness failures to investigate, not benchmark noise.

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
