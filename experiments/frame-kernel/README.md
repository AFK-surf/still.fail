# Independent runtime experiment

This is a competing design experiment, not a production fix or a replacement UI
framework. It does not wrap `view.Tree` or change its scheduling flags. Existing
`mbui/flex` measurement and `mbui/motion` curve solvers remain the calculation
primitives. No application imports this module.

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
   logical work, then applies the input. The kernel has no host clock provider.
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
4. **Change knowledge stays local.** Row versions invalidate only their measured
   leaf. Layout starts at the anchor and ends when the viewport is filled. The
   resulting geometry stays usable while only the page transform changes.
5. **Hit tests read the projected scene.** They use its transform and clip, rather
   than a separately rebuilt registry. An event should project at its event time;
   it must not depend on whichever frame happened to be painted last.

The narrow code here deliberately has no generic user callback in layout, no
observer publication, and no mutable global clock. It tests whether the causal
loop can be removed from the model rather than made less likely by a guard.

## What this slice can and cannot prove

The tests cover sibling constraints, a visible and an offscreen row mutation,
30 versus 3000 rows, interrupted motion with sparse/dense frames, sampling ahead
without early disposal, and projection-consistent hit testing. Row heights are
synthetic intrinsic measurements passed through the existing flex engine.

This is not yet evidence for phone smoothness. Text shaping, GPU submission,
general component bindings, nested lazy containers, live core data, full owner
trees, scrolling physics, focus/IME, overlays, old-view migration and actual app
visual parity are not implemented here. Leaf allocation is an internal render
cache; its work may differ between frame schedules. Semantic owners must remain
independent of that cache. This slice has one semantic owner and does not yet
prove the general case.

## Comparison that would justify adoption

Run identical recorded input and text-metric tapes through the current runtime
and the alternative: identical semantic state/lifetime and picture/hit result at
chosen moments, under 60 Hz, 120 Hz and sparse frames. Count propagation,
measurement, composition and GPU work separately. Include 30 and 3000 rows,
composer growth, history insertion, leave/reenter, interrupted gestures and image
completion. Then run the same dev target and host on Android and measure frame
budget, allocations and memory. A simpler model is a hypothesis until that
comparison succeeds.

The existing failing control is
`apps/mbui/mbui/src/view/frame_moment_test.mbt`: specifying a frame at 100 while
the host is at 200 gives logic/drawing at 200 after four host clock reads. Fixing
that single path is a useful control, but does not by itself establish the
alternative's broader contracts.

Run on the build station: `moon test --target wasm-gc --release` from this module.
