# Evidence for the independent runtime slice

Baseline: `351cef2857f2b281a25728363e9416fbc6b469bb`.
Combined implementation: `b4217adac8`. No production app imports the experiment.

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

The slice does not yet demonstrate a general owner tree, full input/IME,
stable-key history insertion/removal, recorded font/resource changes, or a
retained scene submitted to the real GPU. It has not been compared against an
actual chat replay or measured on Android. The contract evidence justifies the
next integration work; it does not establish that the phone goal is achieved.
