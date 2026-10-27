# Work by what changed

A frame is a function of the state and the time, and mbui is deterministic. So the work a frame does should be in
proportion to what changed since the last one, and what changed should be known from what read what, not found by
comparing frames afterwards nor guessed by rules. This is the design mbui is moving to; the steps at the end say how,
each held by the check that comes first.

## Where it is today

The view is built every frame by running code that writes into the frame: nodes, and the frame's lists of what it says
besides what it draws (said.mbt: what takes the focus, the pointer's shape, targets, what scrolls, words that can be
picked, what is read out). A part kept (kept_part.mbt) or a list's row kept (kept_rows.mbt) skips that work by
recording what its build and paint wrote, moving it to where it is drawn now and saying it again (said.mbt's `Moved`,
the band, `rows_said`, `parts_placed`). Whether it may be skipped is a list of conditions: what its computed read, and
rules on top for what it did not read (any event from the host, a press held on it, the pointer over it, the frame
after an event). Each bug of it so far was one thing written and not recorded, or read and not followed: every kind of
thing a part may hold has to be recorded and said again by hand, so each new kind is a bug till it is. It is off
(kept_part.mbt's `parts_on`: every frame built whole) until what replaces it below is there.

## The model

1. **State is signals, and only values.** The core's data and the view's own state (where the pointer is, what is
   pressed, the focus, what is picked, where a list is scrolled, the current input) are signals. A host's event and an
   effect's result do one thing: write state. Nothing holds "something happened".
2. **Derivations are pulled.** A computed is worked out when it is read, and stops what depends on it where its value
   did not change: "is this box under the pointer" changes as the pointer crosses its edge, not as it moves.
3. **Time is one signal, the frames' clock `now`.** A moment (a "3 minutes ago", an exit's end) is a derivation that
   changes at that moment and wakes then; it does not read every frame.
4. **A motion is `animated(target, spec)`.** Its target is a value (worked out of the state, or a box the layout
   worked out); it remembers the target it last read and where it showed then, and from the frame the target changes
   goes on from where it was, as fast as it went. It reads `now` only while it goes. No one tells it to start: there is
   no animate, snap or follow, no `Mover`, no list of what moves. Shown or not is `animated(present)`; whether a node
   gone is still drawn is a moment (its exit's end).
5. **What is built is a value.** Each part (a row, a pane, a page) is a computed whose value is its subtree: its
   boxes, and what it says (what takes the focus, its targets, what scrolls, its words, what it reads out) as data in
   that subtree, not written into the frame. Where it is is not in it: a subtree and its layout depend on what it shows
   and the room it is given; what holds it places it. Nothing it read changed: the same value, by reference, and
   nothing under it is visited. `box(fn() { ... })` stays as the way to write it; what it means becomes making a
   subtree, not writing into the Ctx.
6. **Layout and paint are computeds too.** Layout is computed(subtree, room); paint is computed(layout, what is read
   as it is drawn: where, how large, how opaque, what colour, what cuts it), giving the part's instances in its own
   frame. A value read in a phase makes only that phase work again: read as built, the part is built; read in layout
   (a height going), what it lays out is laid out again; read in paint (a move, a fade), its instances are worked out
   again, nothing built nor laid out. A page sliding, a row moving to its new place, a reshape: paint reading
   `animated` of a laid-out box.
7. **Unread is no work.** A change nothing on screen reads makes no frame and costs nothing; while nothing reads `now`
   no frame is asked for; what is hidden reads nothing until it shows. A motion read again after a while is worked out
   at `now` at once: it is deterministic, so it is what it would have been had it been followed every frame.
8. **What the frame gives the host follows from it.** The parts drawn again are the boxes, old and new, of the paint
   computeds that ran this frame and of what was built or laid out again; only their instances are sent. Hits, the
   pointer, the focus and what is read out are asked of the frame's tree.

## What goes

`outside_events`, a part's `held`, `pointed` and `came_built`, the frame built once more after an event;
`shows_motion`, `kept_clock`'s frame for motions, `Mover` and its `said`/`told`, `movers` and asking each `rest_at`
every frame, `moving`/`set_out`; the motion package's moves and reshapes told after layout; building each frame what
holds a native view or the field with the keys (where they are is worked out in paint); the replay of kept_part.mbt and
kept_rows.mbt (bands, `Moved`, `rows_said`, `parts_placed`) and said.mbt's recorded lists; comparing instances for
damage (src/damage). A kept part's `same` comes down to: its computed is not stale, and its key, the layout's epoch
and the scale are as they were.

## Held by the tests

Whatever work a frame skips, a Tester draws that frame whole after it as well, and the two must come out the same:
the instances drawn, and what they ask for next. The first frame they part at fails the test, saying the frame, the
instance and the value. So every test holds every way of skipping work as it comes in, and each step below is merged
only with all of them green (frame_watch.mbt, `looks_check`).

## The way there

1. Measured: still.fail's scenes offscreen (scripts/appbench.sh) and on a phone (scripts/appbench_phone.sh), what each
   frame built, laid out and drew, how long each took and what asked for it (Tester::wanted_why); each step below
   compared with the one before it.
2. The whole frame first: its work runs under one watch of what it reads (signals' Watch, frame_watch.mbt), and it is
   built again only where that changed. The clock is a signal (Ctx::now reads it followed; what changes only at a
   moment reads it as one and wakes then), the host's settings are one (frame_env), and what is no signal yet is
   counted into two (outside_said, inputs_said: what came from outside, the hand). A frame where nothing it read
   changed but its looks by the clock (a spinner, the spokes, a breath: cycle_look.mbt) draws the last frame's
   instances, each look applied at its time.
3. The view's own state into signals (the pointer, presses, the focus, what is picked, scrolling, the current input) and
   the app's (its store's, its timers'). The hand is (hand.mbt): what the pointer is over, what is pressed and what the
   press went down on, clicked, held long, the focus, the current input, where the pointer is and whether it is down,
   its discrete events, said as each frame begins, a set read by member where it is (signals' Keyed: a row pointed at
   changes as the pointer crosses its edge); `inputs_said` went, and a pointer moved over what lights nothing builds
   nothing. Left: what scrolls (a list's place, a box scrolled sideways), what a field holds, what a pager or a menu
   keeps of a press, read so; then `outside_said`, the frame built after an input taken (inputrec.mbt's `inputs_taken`),
   `outside_events`, `held`, `pointed` and `came_built` go.
4. Motions as `animated(target)`, read in the phase that uses them, unread not stepped. The frame's paint runs under a
   watch of its own (frame_watch.mbt's paint_watch): where a node is placed by the clock (Ctx::moved_by: a stack's
   slide) and a look worked out as it is painted (Ctx::look_by: a fade) read where a motion is there, so a frame where
   only that changed is painted again from the last build's tree, nothing built or laid out (a picture's fade too); a
   motion going that nothing reads asks for frames that do nothing. Then the rest read so: the motion package's moves
   and reshapes, the bar's springs, a hover's fade; its told moves and the movers go.
5. What is built as a value, a list's row first (in place of kept_rows.mbt), then a pane and a page (in place of
   kept_part.mbt).
6. The replay, said.mbt's recording and src/damage's comparing go; only the instances that changed are sent.
