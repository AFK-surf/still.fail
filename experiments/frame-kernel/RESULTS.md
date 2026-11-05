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
reappearance. The narrow reference change is `1de556022c`. A subsequent Android
comparison using the same shell and keyboard inset confirmed the missing sixth
line before the change and all six lines plus the caret afterward. Both complete
screenshots were inspected and posted in the task chat. This confirms the
presentation correction, not a frame-time improvement.

The independent integration's Android failure was also rerun with checked traps,
using the same Wasm program and 512 KiB stack. It reports `call stack exhausted`
while a geometry-reading structure runs through `Tree::at_cause`, signal batch
completion and another structure's notification. The recorded 20 frames are the
runtime's default backtrace capture limit, not evidence of a 20-frame-deep stack
([Wasmtime configuration](https://docs.wasmtime.dev/api/wasmtime/struct.Config.html#method.wasm_backtrace_max_frames)).
That diagnostic compiler setting is not part of the performance comparison.

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
Android trap were correctness failures to investigate, not benchmark noise.

### Keep layout output inside its derivation

Tracing the repeated placement showed the drawing clock alternating between
25307.770053 and 25267.907595 within one frame. A shift changed, the resulting
geometry notified observers, and those notifications entered input settlement,
rewinding the drawing clock to the earlier cause. Reverting the shift notified
the observers again. The current runtime stopped at its 512-pass guard; the
older independent integration could recurse until exhausting the Wasm stack.

A minimal test needed both a predicted drawing time and a size change with a
geometry observer. A clock-only test passed and did not cover the failure. The
complete case failed with the same 512-pass diagnostic. Keeping geometry
notifications inside the active layout phase made all 545 view/motion tests
pass on the current reference, including the tests that settle real input
changes between frames. The independent integration also needed its two
remaining direct host-clock reads in `queued` and `at_cause` routed through the
declared-time helper; without that, the clock-read tests failed at 4 and 1 reads.

The actual Android rerun used independent `6be1d6d682` and narrow-reference
`7139dcf402`, the same shell, checked traps and the unchanged 512 KiB Wasm stack.
Both states passed open/back/reopen, six-line input after the keyboard inset,
and scrolling. All six full-screen results were inspected. The input pixels
contain all six lines in both states, and none of the six logs contains a
512-pass diagnostic, Wasm trap or drive failure. The independent framework
suite passed 2291 tests and the reference UI suite passed 1624. These results
clear the previously observed cases for these builds; checked-trap timings are
not a performance comparison.

A further timing counterexample fails at those commits: sampling a
future display time can notify a geometry or clock observer that advances the
logical timeline and executes a deadline before an intervening input. The
native success above does not establish the full input/projection contract.
Treating display sampling as derivation too, retaining the logical cause in its
queued properties, and preventing derived callbacks from advancing the timeline
makes the two counterexamples pass. The reference view/motion suite passes 547
tests, including cancellation of a future deadline by an intervening input.
The change is independent `12b4583e39` and narrow-reference `371cdd47a6`.
The independent view/UI/signals/motion suite passes 2293 tests; the reference UI
suite passes 1624. The actual Android rerun again passes all six open/back/reopen,
keyboard input and scrolling trials, without layout-cycle diagnostics or traps.
All six resulting screens were inspected; both input screens show all six lines.
The same checked-trap shell and 512 KiB stack were used. The full-render input
and scroll movies also retain identical decoded hashes against the original
pre-integration baseline for all 18 and 78 frames respectively.

### Corrected native comparison

The two corrected programs were compared under the same normal signal-trap
setting, in independent/reference/reference/independent order. This reused the
validated Wasm modules rather than rebuilding different source states. All 12
open/back/reopen, input and scroll trials passed without a layout-cycle diagnostic
or trap. All 12 final screens were inspected; the four input screens show six
lines with the same keyboard inset (279.076935 layout units). The native scroll
end positions differ as actual input/frame schedules differ, so these captures
are not asserted to be pixel-identical.

The trace joins each measured interval to the thread that emitted its own record.
Intervals are clipped to the operation's start/end markers, including the input
work after a start marker in the middle of a frame. Excluding that partial frame
would, for example, miss a 301 ms click-handling interval in the second
independent open trial. Every included interval has complete recorded scheduler
state coverage. The ring-buffer/periodic-flush configuration has no reported
discard or missing-flush issue; 37 unsupported ftrace setup events remain reported
as notices. Monotonic clock offsets vary by less than 0.0001 ms.

These are summed milliseconds across each scripted operation, not per-frame
times. Each cell retains both trials. "Running" is the Android scheduler's
classification; it cannot exclude descheduling of a virtual CPU by the Mac host.
"Post-tree" includes the old-frame path, including building, layout and painting,
and any additional tree work it triggers. It is not just GPU drawing.

| Operation / implementation | Work-bearing frames | Framework wall ms | Framework running ms | Tree running ms | Post-tree running ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Scroll / independent | 60, 73 | 361, 200 | 201, 192 | 21, 19 | 180, 173 |
| Scroll / reference | 61, 76 | 347, 235 | 241, 219 | 33, 26 | 208, 193 |
| Six-line input / independent | 11, 11 | 49, 16 | 24, 15 | 2, 3 | 21, 13 |
| Six-line input / reference | 11, 11 | 46, 21 | 34, 19 | 5, 4 | 29, 15 |
| Open/back/reopen / independent | 9, 4 | 127, 254 | 109, 240 | 19, 37 | 90, 203 |
| Open/back/reopen / reference | 12, 5 | 114, 211 | 109, 197 | 17, 19 | 92, 179 |

Input handling outside the frame is separate: each input trial records 12 text
callbacks and five key callbacks. Their combined running time is 21/18 ms for
the independent integration and 15/17 ms for the reference. Script-dispatched
pointer handling is inside the frame's drive interval, not in those text/key
totals. Including presentation and the drive interval, the open trials spend
309/748 ms in callbacks for the independent integration and 221/412 ms for the
reference. The second independent opening contains a 90 ms framework frame and
a separate 301 ms drive/input interval; neither is cleared by the small average
cost of ordinary scrolling.

This does not establish an overall win for the independent integration. It
removes proven historical-row work, but 86–90% of the recorded framework running
time during scrolling remains after the initial tree stage, and opening remains
expensive. The two code bases also differ outside the experimental integration;
the native driver produces different frame schedules. These results cannot
isolate the intrinsic-height/index changes as the cause of a timing difference.
Further diagnosis follows the actual long input/build/paint calls rather than
assuming the remaining cost is layout or thread waiting.

End-of-trial process PSS is 255–294 MiB for the independent integration and
243–283 MiB for the reference. These are whole-app snapshots, including native
resources, not a repeated-lifetime leak test or a measured memory improvement.
Previous incorrect-presentation runs are not used to claim an adoption speedup.

## Local list measurement in the actual application adapter

The opening trace was followed into the long input call. Filling the visible
window repeatedly created a row, placed the whole tree, published the row's
height, and then created another row. Two openings recorded approximately 28 and
22 ms of scheduled running time in the enclosing layout call. Nested calls
overlap: adding their inclusive durations would count the same work repeatedly.

The adapter now measures the list's owned visible rows at its allocated content
width before the next whole-tree placement. Those answers update its private
position index, without depending on the child's placed-size notification. A
30/3000-row counterexample first failed because another whole-tree calculation
occurred between successive row constructions. The local measurement version
passed the flex/view suite's 857 tests. A further percentage-padding case caught
an incorrect width basis: the containing block, rather than the list's own
border width, determines that padding. The corrected width, visible-window
resize, content-change and disposal cases passed together (3 tests).

Framework tests did not establish application correctness. The first real send
test repeatedly queried destination geometry until the Wasm-GC executor ran out
of memory. Bounded instrumentation identified the repeated caller as the
composer's motion group. Its held-height getter sampled the drawing clock to
decide whether to release the box. Releasing changed the shape key; measuring
the resulting motion at the earlier logical time restored the hold, restarting
the same group. The local list heights were already unchanged during these
repetitions.

Release is now scheduled on the input timeline, with cancellation when the hold
is retimed or its render owner is disposed. Prediction at 110 does not release a
hold while input time is 90; a retiming input at 95 cancels the old deadline at
100, and a late advance to 300 delivers the new release with cause 195. The
actual composer, row motion and foot-clearance checks then passed (31 tests),
including the send that previously exhausted memory. These changes are in
`0f410f2f33` and `aa6b667c85`; the first is an intermediate WIP with the failing
integration still present.

The combined view/flex/motion/UI suite then passed 2682 tests. On the same
Android Wasmtime shell, both versions completed opening/back/reopening, six-line
input and scrolling without a trap or layout-cycle diagnostic. The input and
scroll full-render films match the previously corrected baseline at every
decoded frame (18 and 78 frames). The native screenshots were also inspected;
the six lines are present. The native scroll end positions differ because this
driver delivers samples on the actual frame schedule, so those screenshots are
not asserted equal. Sending is covered by the application tests above, not by
these three native scripts.

One before/after pair under shared-host load gave the following operation sums.
Definitions and scheduler limitations are the same as the corrected comparison
above. Full-frame time includes presentation and script-dispatched pointer
input, with the operation's boundary frames clipped to its markers. Text/key
callbacks delivered outside those frames are shown separately.

| Operation | Work-bearing frames, before / after | Framework running ms | Full-frame running ms | Outside text/key running ms |
| --- | ---: | ---: | ---: | ---: |
| Scroll | 36 / 69 | 209 / 289 | 691 / 515 | — |
| Six-line input | 11 / 11 | 35 / 29 | 76 / 78 | 42 / 32 |
| Open/back/reopen | 4 / 5 | 77 / 110 | 200 / 315 | — |

These results do not establish a speedup. In particular, the open operation's
script/input interval consumed 104 / 176 ms of running time. Fewer repeated
whole-tree placements in a focused test have not removed the actual opening
bottleneck. Different native frame schedules also change the input positions
during page motion and the number of frames being summed. The local-measurement
program's Wasm SHA-256 is
`2a8771df9dc2f24c77ca740d1ef6d703f541775eff9ab3be7b5a4f78be48aee6`.

This remains an adapter using the existing tree and arbitrary row renderers; it
neither makes their callbacks pure nor replaces their semantic ownership with
the independent kernel. It is a checkpoint of diagnosed old-runtime behavior,
not completion of the independent architecture. The next adoption must connect
the actual chat's input, allocation and presentation to the forward contract;
more isolated fixes to the old scheduler do not satisfy that requirement.

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

The parent-allocation migration now includes media, attachment rows, scroll
content and thumb sizing, short end-aligned lists and the chat's floating actions.
The short-list resize counterexample first failed because publishing the
viewport height scheduled a second whole-tree computation. A percentage minimum
height now consumes the current parent's constraint; the same check passes with
one computation. Floating actions measure the composer's height expression and
their own content in the same parent arrangement, without deriving padding from
the last placed pane width. The focused list/scroll checks passed 16 tests and
the actual composer/send/flight checks plus floating-action allocation passed 36.

The previous scroll allocation change passed 867 view/flex tests and 35 app tests.
Its 78-frame scroll film is byte-identical after decoding, as are the attachment
stills. The next chat-layout build preserves the small and large screen pictures,
including the visible return-to-latest action, pixel for pixel. A corrected drive
opens the middle pane before scrolling; its 720-by-900 pictures now also expose
the action and match pixel for pixel. These are actual app scenes rendered from distinct Wasm
programs (baseline `1188c0ad1461df1f83d1beeed96a29d3027ffbc20ec6f79432b9a1937fe6dbee`,
chat allocation `0cb2631496fa4f430f942d52776e1dce8a204d745fc7cfc4fed74be3077988f4`).
They establish presentation preservation for these scenes, not a speedup.

The scroll range still writes scroll state from layout notifications; the list's
row selection, anchor and responsive row bindings still use layout results.
These are unresolved violations of the forward frame contract.

The new arrangement boundary rejects signal reads during projection, geometry
reads during input capture, state writes, binding changes and child construction.
Computed values retain whether they observed geometry, including nested cached
values and untracked reads; a change of provenance propagates even when the
numeric value is unchanged. The six prohibited operations first passed silently
on the baseline, then each failed as required in an isolated Wasm test package.
The focused signal, boundary, allocation and text-measurement suite passed 222
tests. This boundary covers explicit arrangements and the guarded APIs, not
arbitrary Ref storage or the legacy layout bindings.

Actual app adoption exposed three hidden dependencies: the scrollbar captured
the list's old position table despite measuring its complete content; text
measurement read the live theme; and attachment layout read the prior chat width
through its corner calculation. The scroll measurement now supplies its own
extent, text shaping captures its theme before measurement, and a pane supplies
the composer's shape from its allocation inputs. A row-filling quote no longer
reads an unused corner reach. The expanded composer, attachment and send checks
passed 55 tests. The complete framework run exposed an omitted absolute overlay
beside a custom arrangement; automatic overlays now follow their containing
block while explicit placements remain owned by the plan. The corrected run
passed 2665 signal, view, flex and UI checks.

Late dependency borrowing exposed two further provenance holes: an already
cached reader was not marked when its source later borrowed output dependencies,
or when those dependencies were lent to another cached value. Both new cases
failed first. Provenance now crosses existing computed-reader links without
running getters or effects; fresh evaluation can still remove that provenance.
The signal and isolated boundary checks then passed 195 tests.

The full application run has five failures, not a green result: typing, scrolling
and page changes still rebuild old frame content, a joined sent row jumps from
620.5 to 642.5, and the leaving new-chat heading moves from 404 to 186. All five
also fail on the pre-boundary revision `4f39726ad7`, with the same two position
jumps (101 focused checks, 96 passing in each source state). They remain work
for this redesign. The full script also reports 57 uncaptured core answers;
56 occur in those focused checks in both states and still need the core's
recording tool. The boundary batch's twelve actual-app pictures have now been
inspected: attachments and quotes at 390×844, 720×900 and 1280×900 match their
controls byte-for-byte. The before/after Wasm SHA-256 values are respectively
`1cefd3c35ec5ad4d43cac071ba1ab4195a93e147d267ac265f298c9fa91b443b`
and `943f9fc9ac22be961e72c77203b4c01c5462bd4dcf938875db2816df0018905e`.
These are stable pictures, not evidence that the five motion/work failures are fixed.

The two position jumps were then traced to separate missing inputs. The leaving
new-chat container received zero height: its hosted child grew, but the container
itself did not, losing 218 px of centering room. Letting that container fill its
parent fixes the existing large-screen transition check. A replacement chat value
also reset every row version to zero, hiding the removal of the previous message's
timestamp from the list's height causes. A new snapshot regression failed before
preserving per-key versions across full values; unchanged rows keep their version.
The row, subscription, snapshot, send, composer, quote and wide-page checks then
passed all 219 tests. The three host-frame work checks remain unresolved; actual
transition pictures are being captured separately from these checks.
This is not a validated release.

The corrected new-chat transition was inspected in actual-app stills at 0, 70
and 700 ms and in every frame of a 60 Hz, 700 ms film. The illustration and
heading now fade at their original position while the composer and sent words
move; the final picture is identical. These films sample the declared moments
of the app's own renderer, not a recording of an operating-system window.

The host-frame checks exposed two conflated kinds of work. A retained text
reply after presentation requested a frame by invalidating the old build; typed
text also left a legacy follow-up input flag even though the retained editor had
taken it. Both now request only the work that reads the change. The original
checks failed before these changes; the editor check now asserts every host
frame, including the frame after the input, rather than callback counts alone.

Running without the old rebuild also exposed glyph ownership tied to that
rebuild. A hidden layer kept its atlas plots pinned, and atlas epochs did not
advance on retained-only frames. Each presented frame now begins an atlas epoch;
unchanged visible layers keep their plots, changed layers claim what they draw,
and hidden layers hold none. Old-view plots remain recorded for frames that
retain those views. The strengthened case hides 40 glyphs and shows 40 others in
one actual host frame: it failed before the epoch fix and now passes. All 1605
UI tests pass after these changes. The actual-chat trace no longer rebuilds the
old frame for typing, deleting or moving the caret. Its damage still includes
the enlarged glass capture, and the scrolling and page-exit work checks remain
unfinished. This is no claim about Android speed or completed runtime adoption.

Retained mouse selection now owns its press, pointer coordinates and release,
including double/triple clicks, modal cancellation and scrolling past an edge.
The previous route passed through the old input state, which both rebuilt the
old frame and let legacy hover cleanup erase the selection's pointer. Selection
readers now subscribe to its state; focus bookkeeping no longer subscribes the
whole old frame to retained focus changes. The application's three shell
underlays take input only at their own targets. The strengthened host-frame
selection and editor-focus checks failed first; all 1608 UI checks now pass.

The actual chat's six pairs of pictures were inspected: typing at all three
screen sizes, mouse selection at medium/large, and finger scrolling at small.
Every pair is byte-identical to its control. The baseline and updated Wasm
hashes are `65bb8d3a9a0b4e27ac09dc1e6a53c972058eb17954f9283d2297d3bb63d0c1d8`
and `06d8fb8ee292eced5b797e83d30895c0bf81ce246b8af63a681ae0e483b78009`.
The long-chat host checks still have three failures: glass damage extends beyond
the composer or becomes the whole window, the first large-screen drag rebuilds
one old island, and the small-screen page exit still triggers old builds. The
small-screen drag/fling no longer rebuilds old views. None of this establishes
an Android speedup or completion of the runtime redesign.

The experimental kernel does not yet demonstrate a general owner tree, full
input/IME, stable-key history insertion/removal or recorded font/resource changes.
Production integration has exercised actual chat input and scrolling, including
the frame comparisons above, but retains the existing runtime's owner, event and
rendering system. It still performs repeated layout and does not enforce the
experimental model's write permissions or frame-independent semantic ownership.
Android development-target frame and memory measurements remain necessary; the
phone goal is not achieved by the results above.

The first large-screen drag was traced to the shortcut handler reading editor
focus even when no focus shortcut was pressed. Testing the action before
reading focus removes that subscription; the first drag now builds no old
island. The related composer/reference checks pass (55 of 58; the same three
host-work checks still fail).

Page departure now saves positions and releases native resources in a retained
reaction to the navigation lifetime, without waiting for a build. The player
regression sends Back and a later input with no frame between: the previous
source loses the saved position, the new source saves it and closes the view.
All 35 player, chat and chat-open checks pass. This does not yet remove the
remaining small-screen departure rebuilds or glass damage expansion.
