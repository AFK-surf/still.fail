# Independent runtime experiment

This is a competing design experiment, not a production fix or a replacement UI
framework. It does not wrap `view.Tree` or change its scheduling flags. Existing
`mbui/flex` measurement, `mbui/motion` curve solvers and `mbui/signals` dependency
tracking remain the calculation primitives. No application imports this module.
The fuller rationale and unimplemented requirements are in [DESIGN.md](DESIGN.md).

## Requirements before mechanisms

- State and semantic lifetime at a logical moment depend on timed inputs, not on
  the number or timing of rendered frames.
- Updating a row, typing, or scrolling must cost the visible work and the actual
  changes, not the whole history. Initial ingestion can visit the input once.
- An interrupted motion starts from its value and velocity at the input's moment.
- Layout, presentation and hit testing agree about geometry and transforms.
- The framework owns scheduling, dependency propagation and resource lifetime;
  pages should not implement cache invalidation and settling loops.
- One application and existing appearance, input behavior, host contracts and
  Wasm development remain requirements. Desktop timings are not phone evidence.

## Alternative contract

1. **Timed input is the only state writer.** `commit(at, change)` advances due
   logical work, applies the input, and completes work newly due at that same
   moment. The kernel has no host clock provider.
   A production version must route core answers, resource completion and input
   through this same boundary with their captured timestamps and sequence.
2. **Geometry is a result.** The common parent measures the composer, then passes
   the remaining constraint directly to the list. There are no geometry signals
   or callbacks that can restart structural work. Custom and lazy layouts may
   only create, measure and place their own children, using captured content.
3. **Presentation is sampling.** The display timestamp samples a trajectory; it
   never advances logical lifetime or writes a reactive clock. Both times belong
   to the same timeline and arrive explicitly at the boundary. A size animation
   needs an explicitly owned layout sample, not a global presentation signal.
4. **Change knowledge stays local.** A query observes only the cells it reads.
   A write makes those observations stale; it does not run layout. Row versions
   invalidate only their measured leaf. No input handler manually marks layout.
   Layout starts at the anchor and ends when the viewport is filled. The
   resulting geometry stays usable while only the page transform changes.
5. **Hit tests read the projected scene.** They use its transform and clip, rather
   than a separately rebuilt registry. An event should project at its event time;
   it must not depend on whichever frame happened to be painted last.

The narrow code here deliberately has no generic user callback in layout, no
geometry publication, and no mutable global clock. Model writes require a live
input transaction, rejected from queries or after the transaction closes. It
tests whether the causal loop can be removed from the model rather than made
less likely by a guard on recursion depth.

## What this slice can and cannot prove

The tests cover sibling constraints, a visible and an offscreen row mutation,
30 versus 3000 rows, interrupted motion with sparse/dense frames, sampling ahead
without early disposal, and projection-consistent hit testing. Row heights are
synthetic intrinsic measurements passed through the existing flex engine.
`state_wbtest.mbt` checks write permissions and automatic local invalidation.
`editor_wbtest.mbt` exercises the real editor's `FieldLaid` measurement and its
legacy leaf renderer under the Tester's text host; it is not a full editor port.

`measured_list.mbt` is a linear reference for exact known row heights.
`indexed_list.mbt` adds a range index whose collection owns invalidation. A
known crossed interval can be skipped; an item update invalidates its path,
without calculating geometry during the write. An unknown interval still costs
the measurements needed to cross it. The index stores exact binary extents to
keep fractional boundaries independent of cache grouping. Its BigInt storage is
a reference representation, with allocation cost still to evaluate.

This is not yet evidence for phone smoothness. Real-host text shaping, GPU
submission, general derived queries (nested queries are deliberately rejected),
nested lazy containers, live core data, full owner trees, scrolling physics,
focus/IME migration, overlays and actual app visual parity are not implemented
here. The legacy editor measurement still reads its host/font environment;
recorded resource inputs and invalidation must replace that implicit dependency
  before it is a production cache. Leaf allocation is an internal render
cache; its work may differ between frame schedules. Semantic owners must remain
independent of that cache. This slice has one semantic owner and does not yet
prove the general case.

The composer allocation, indexed rows, timed scrolling and page trajectory now
share one `Kernel`. A combined input tape changes composer and row heights,
scrolls, leaves and interrupts the page motion; optional frames may warm caches
but may not change the final allocation or hit result. A real `FieldLaid` row
also passes its measured height into flex without measuring the text twice.
Layout samples the logical frame moment; presentation prediction samples only
the page transform. The slice has no overscroll or signed-distance gesture model.

## Comparison that would justify adoption

Run identical recorded input and text-metric tapes through the current runtime
and the alternative: identical semantic state/lifetime and picture/hit result at
chosen moments, under 60 Hz, 120 Hz and sparse frames. Count propagation,
measurement, composition and GPU work separately. Include 30 and 3000 rows,
composer growth, history insertion, leave/reenter, interrupted gestures and image
completion. Then run the same dev target and host on Android and measure frame
budget, allocations and memory. A simpler model is a hypothesis until that
comparison succeeds.

The frame-time counterexample is in `src/control/frame_time_test.mbt`:
specifying a frame at 100 while the host is at 200 gives logic/drawing at 200
after four host clock reads. The desired assertion was first verified red in
commit `0f5ba584f8`; the experiment now retains the observed baseline behavior
without adding a deliberately failing test to the framework's normal suite.
Fixing that single path does not by itself establish the broader contracts.

Run on the build station:
`moon test --target wasm-gc --release src/kernel src/control` from this module.
The control tests assert the counterexamples found in the pinned current runtime;
they describe gaps in its contract, not desired behavior for a replacement.

For the bounded classic-Wasm executable (separate from the Wasm-GC test suite):

```sh
moon build --target wasm --release --no-strip src/probe
PROBE_WASM=$(rg --files _build/wasm/release/build | rg '/probe/probe.wasm$')
"$WASMTIME_BIN" run -W max-wasm-stack=524288 -D max-backtrace=100 \
  --preload spectest=spectest.wat "$PROBE_WASM"
```

`WASMTIME_BIN` names the installed development runtime. The preload supplies
ASCII diagnostic printing and an outer benchmark clock; it is not an application host. The executable tests
the computation under a 512 KiB Wasm stack, not Android rendering or throughput.

`src/perfprobe` builds similarly and times isolated computations using an outer
clock. Each workload is calibrated toward 300 ms and sampled three times; it
reports whole milliseconds and the iteration count. The linear reference is a
comparison for index traversal cost, not the existing application's runtime.
