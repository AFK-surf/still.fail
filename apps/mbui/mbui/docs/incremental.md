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
(kept_part.mbt's `parts_on`: only a test turns it on, Tester::keep_parts): a list's row and a part are kept as their
nodes instead (step 5 below).

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

## What decides the work

An app says what it shows, by what it reads, and who each thing is; never what is to be built again. What the
framework does again follows from three things alone, as in Compose, Flutter and SwiftUI:

1. **Who a node is: where it is in the tree, by the call that made it or the key it was given.** Not where it falls in
   the frame's order: a node more or less built before it (a bar's button as it shows, a mark in a motion) changes
   nothing of what comes after it. What is kept of a node (its layout, its build, its motions, its measure) is kept by
   who it is. A list's rows are so (a row in its own nodes, kept_nodes.mbt's `row_nodes_lent`); every node is to be.
2. **What it read.** Every state is a signal, the app's too (a host's bars, a column's width, a press). A plain mutable
   read as it is built is a read nothing follows; it is made a signal, never followed by forgetting what was kept
   (detlint `built-by-hand`: only goes down, to none).
3. **In which phase it read it.** What is built reads what it shows; layout reads the room and what moves a size (a
   row's height going); paint reads what moves a place or a look. A motion read in build makes it build each frame it
   goes: it is read where it is used. What is built never reads what was laid out (detlint `layout-read-back`: the
   first frame has none, a change lays the frame out twice); a list's rows coming, going and changing their height are
   the list's, from each row's key and what it shows (as Compose's animateItem, a diffable collection view), not told
   by the app for each kind of row.

A frame kept that differs from the frame built whole (the Tester's `looks_check`, `rows_check`) is a read not
followed, or a node taken for another. The fix is that read made followed, or that node known for who it is; never
building more (a part forgotten, a row built each frame, "built again while it moves"), which hides the next one.

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
   nothing. A list's place is read as it is laid out (Ctx::place_list): what the hand does to it between frames (a
   finger dragging it, a wheel) is said by its own signal (ListState's `hand_said`), and its own motions are stepped
   there (a wheel's ease, a fling, a glide, an overscroll going back), so a list scrolled lays the frame out again,
   nothing taken by what is built. What reads the press is built again as it goes down, past the slop or up, not as the
   finger moves (hand.mbt's `beyond`); the system's back gesture as it goes is where the page follows it (Nav's
   `finger`), no event; what reads where the pointer is reads it only where it uses it (a field's while a press drags in
   it, a rail's place while it is dragged). Left: a box scrolled sideways, what a field holds, what a pager or a menu
   keeps of a press, read so; then `outside_said` (what comes as a topic's change alone is taken as it comes, before the frame decides what it
   does, said by its signal: @ui.on_message_said, the core's `receive_said`; the rest still counts), the frame built
   after an input taken (inputrec.mbt's `inputs_taken`),
   `outside_events`, `held`, `pointed` and `came_built` go.
4. Motions as `animated(target)`, read in the phase that uses them, unread not stepped. The frame's paint runs under a
   watch of its own (frame_watch.mbt's paint_watch): where a node is placed by the clock (Ctx::moved_by: a stack's
   slide) and a look worked out as it is painted (Ctx::look_by: a fade) read where a motion is there, so a frame where
   only that changed is painted again from the last build's tree, nothing built or laid out (a picture's fade too); a
   motion going that nothing reads asks for frames that do nothing. Then the rest read so: the motion package's moves
   and reshapes, the bar's springs, a hover's fade; its told moves and the movers go.
5. What is built as a value, a list's row first (kept_nodes.mbt, in place of kept_rows.mbt): a row is built and laid out
   under a watch of its own and kept as its nodes, laid out, with what its build said of the frame. The frame's layout
   runs under a watch of its own too (frame_watch.mbt's layout watch). A frame where only what its layout or a row read
   changed is built again as it was built (what built the lists read nothing that changed, so it builds them the same)
   and each row nothing it read changed is put back where its list lays it, neither built nor laid out; one built anew
   (what its build read changed, an event of the hand) builds them all, but a list whose rows show only what they read
   (Ctx::list's `rows_read`: each reads its own of what the list shows, as the history's steps read theirs by the row,
   history_steps.mbt): its rows are kept however what builds it is built, each built again only for what it read; a
   pass of the frame built again in it (what was read changed as it was built or laid out, a row's words measured)
   builds them anew. What a row says of the frame that is said again
   in no way (a layer opened over the page, a list of its own, a native view: kept_census, row_nodes_why) builds it
   every frame; what it read of the layout is read back as it read it, and what it holds at its list's top, what
   scrolls in it (sideways.mbt) and a field are said again where it is put back. What a row or the layout read that changes before
   it is read in the frame (what came for the frame, taken as it begins) it reads as it is, no frame after it asked for;
   what reads a measure for its size (`measured`, `measured_size`) is told as its size changes, not as it moves (a page
   it is on sliding in). A Tester builds each pass that kept a row once more keeping none, and the two must build and
   say the same (rows_check). A part (a pane, a page: Ctx::kept_part) is kept so too (Ctx::part_nodes): built under a
   watch of its own, its nodes put back where it is built with what it said of the frame, the lists in it laid out
   each frame as the rest are; built again for what it read, or as what builds it builds it elsewhere, its lists' rows
   are built anew with it (ListState's `fresh`). Where the stacks are in one (a pane's pages), a stack changed
   between frames tells it (nav.mbt's `stacks_said`). Then the replay goes (kept_part.mbt's, kept_rows.mbt).
6. The replay, said.mbt's recording and src/damage's comparing go; only the instances that changed are sent.
