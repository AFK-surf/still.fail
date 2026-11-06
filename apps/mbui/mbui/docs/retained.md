# Built once

What mbui is moving to, in place of docs/incremental.md's way there (2026-10-30). A view is made once: each node is
made when it first shows and stays until it goes; what of it changes is bound to what it is worked out of, and when
that changes, that alone is done again: a property set, a node laid out, its instances painted. Nothing is built again
to find out what changed, so nothing needs proving the same as a build made whole.

## Why not built every frame

A frame is a function of the state and the time. The least work a frame can do is what reads what changed. There are
two ways there:

1. Run the whole view again and prove what may be skipped: React with memo, Compose's recomposition and skipping,
   mbui's frame built under a watch with its parts and rows kept (frame_watch.mbt, kept_nodes.mbt). Skipping rests on
   "run again, it would come out the same", which a compiler or a check must hold. A read nothing followed is a part
   that should have been built and was not, found only by building whole beside it (`looks_check`, `rows_check`); the
   kinds of it were each found one by one (2026-10-28: eleven left).
2. Never run it again: Solid, Vue Vapor, the browser's DOM. What is made is made once; what changes is a binding on a
   node's property, run when what it read changes. The work is what changed by how it is made, not by a proof.

mbui takes the second: the signals (src/signals, alien-signals, as Vapor's) are already it; what is left is to stop
building the view each frame. Layout and paint are the browser's and Flutter's: a node marked as its size or its look
changes, laid out or painted again alone, a move or a fade only painted (a transform, an opacity on the compositor).

## The model

1. **State is signals.** The core's data, the app's state, the view's own (where the pointer is, what is pressed, the
   focus, what is picked, where a list is), the host's settings, the frames' clock. A mutable value that is not a
   signal is never read by what is made (detlint `built-by-hand`, to none). A host's event writes state, nothing else.
2. **A view is made once.** A component is a function run once, as its node is made: it makes its nodes, binds what of
   them changes and says what each does when acted on. It returns nothing it would have to give again.
3. **What changes is a binding.** A property is `Live[T]`: `Is(v)`, set once, or `By(fn() { ... })`, worked out
   tracked and set again as what it read changes. Its phase is the property's, not the binding's: a box's padding is
   layout's, its ground paint's, its words layout's (their size) and paint's. Set again, it marks what that phase
   does again: a layout property marks the node to be laid out (and what holds it, up to a box whose size it cannot
   change: a relayout boundary, a box of a size given); a paint property marks its instances to be worked out again.
4. **Structure that changes is a node of its own.** `show(when, then, otherwise?)`, `pick(of, by)` (a node made by a
   value, made anew where the value is not `same`), `each(items, key, row)` (a row a key, made as its key comes, kept
   while it stays, moved as the order changes, let go as it goes; the row given its item as a signal of its own, so a
   row whose item changed is not made again). Each holds an owner: what a part made (its bindings, its computeds, its
   effects, its native views) is let go with it (signals' `effect_scope`, `Computed::dispose`: under reference counting
   nothing let go is taken back).
5. **Acting is a callback.** `on_press`, `on_change`, `on_key`, `on_drop`... run outside any tracking, in a batch;
   they write state, and what reads it does the rest. No component returns "was pressed" (`if @sf.link_row(...)`) nor
   reads "was clicked since the frame before".
6. **The hand is asked of the tree.** What the pointer is over, what a press went down on, what has the focus, what is
   read out: hit tests and walks of the retained tree, the nodes' own handlers and semantics on them, not lists said
   by each frame's build (said.mbt). A node's lit, pressed, focused and selected states are signals of the node, read by
   its style's paint properties (hovering changes no size: docs/style.md), so a press lights a node by painting it.
7. **Time is a signal, read where it is used.** A motion is `animated(target, spec)` (docs/motion.md), a signal of its
   own: read by a paint property (a place, a look: `moved_by`, `look_by`) it paints again each frame it goes and
   nothing else; read by a layout property (a height going), it lays out its node again each frame it goes. A moment
   (a "3 minutes ago", an exit's end) wakes then. Nothing that is not shown reads it; nothing is told to start.
8. **What comes and goes, at its cause; the rest, at the frame.** A change from outside (an input, a message, a
   host's answer, a press of the tree's) is handled at its own moment: what had ended by then settled first, then its
   handlers, as one change with that moment as its cause's. `show`, `each` and `pick` make and let go nodes as the
   change that caused them is committed, at its moment (what they make reads the state as it is then). What a press
   finds, or anything that asks where things are, is the tree brought to that moment (the bindings told worked out,
   what was marked laid out). A frame settles what ended by its moment, works out the bindings told, lays out the
   nodes marked (.compute's reuse: only the dirty ones), places and looks at what changed, and paints the
   instances that changed, kept by node. A frame where nothing was marked is no frame.

## What it is in mbui

- **Nodes** stay a pool of `Node` by index (node.mbt: no pointer cycles under reference counting), each made once and
  kept until its owner lets it go, freed slots reused. A node's identity is its slot; there is no key across frames to
  find it again (`ident`, `seed`, `slot`, `made_pass` go). `Ctx` becomes what a component makes nodes with as it runs,
  not the frame being built.
- **Style** (style.mbt) is resolved by state in a binding of the node's own: its state blocks read the node's lit,
  pressed, focused, selected and disabled signals and the theme's; what it sets is paint's where it is a colour, a
  shadow, an opacity, layout's where it is a size (and the style checks keep hover from changing one).
- **Words** (text.mbt, rich.mbt): their shaping is layout's measure, cached by node; changed words mark the node.
- **Lists** (list.mbt): the list's window (which rows show) is a computed of where it is scrolled and the rows'
  measured heights, read by the list's `each`; rows coming into it are made as the frame lays out, rows leaving let go
  (or kept a while as their own `each` keeps them). The anchor and the estimates stay as they are.
- **Presenters** (src/sf presenters: menus, sheets, dialogs) are a `show` at the window's top layer, opened by a
  signal; where they come from is a node's laid-out rect, read as a layout binding.
- **Fields** (editor.mbt) are nodes holding their own state as now; what is typed writes it; the caret blinks by a
  moment.
- **Native views** (native.mbt) are made and let go with their node; where they are is worked out as it is painted.
- **Leaving** is the structure's: `show` and `each` keep a node gone as long as its exit says (docs/motion.md:
  `animated(present)`), still painted, no longer hit nor read out; its exit's end is the moment it is let go. A row's
  neighbours moving as it comes or goes are moved by that coming or going, told by the `each` that knows it (Compose's
  animateItem), never by comparing where they were laid out.
- **Layers** (docs/strata.md) are the paint order of the retained tree, a node's stratum a property.
- **What is read out** (a11y.mbt, semantics.mbt) is the tree's, each node's semantics bindings of its own; what
  changed of it is told to the host as it changes.

## Motion in what is made once

How the others put motion on a tree made once, and what of it is ours (2026-10-30, the user:
「研究一下这个框架跟动效怎么最合理地结合」「看看同类产品都是怎么做的」). They agree on five things:

- **What moves is a property of the node, its target state.** Core Animation keeps a layer's model value (what was
  set) apart from its presentation value (what shows now, worked out from the animations on it each frame), and what
  acts reads the model. Compose reads an animated value in a `graphicsLayer { }` lambda, as it is drawn, so a motion
  composes nothing again. Ours: a property bound to `animated(target, spec)` (rule 7 above); its target is state, its
  value now is worked out only where it is read; logic reads the target alone (docs/motion.md rule 3).
- **The phase that reads it is the phase that is done again.** Compose's three phases (composition, layout, drawing): a
  state read in one does that one again and those after. Ours: a place, a scale, an opacity, a cut, a look are paint's
  (painted again each frame it goes, nothing laid out); a size is layout's (its node laid out again, up to a relayout
  boundary); none is the build's. What is made is never made again for a motion.
- **A motion is set off by its cause, never by a value changing.** QML has both: `Behavior on x` (any change of `x`
  eases, whatever changed it) and States with Transitions (what eases is said with the change of state that causes it).
  Slint's `animate x`, Flutter's implicit widgets and Compose's `animate*AsState` are the first kind. Ours is the
  second alone (docs/motion.md rules 1 and 2): a binding moves where its cause says so (`by`), a window made wider
  changes a width at once. The only place "its value changed, so it eases" holds is a control's own state (kind 7).
- **Coming and going is the structure's.** Vue's `<Transition>` (Vapor's own `VaporTransition`), Solid's
  transition-group, Compose's `AnimatedVisibility`, Svelte's `transition:`: what decides that a node shows keeps it,
  gone, as long as its exit says. Ours: `show` and `each` (Leaving, above).
- **A place that follows the layout is moved from where the node is.** Framer Motion and Svelte's `animate:flip` measure
  before and after a change and move the difference away (FLIP); Compose's `animateItem` knows which item moved by the
  lazy list's keys, and `animateBounds` / `SharedTransitionLayout` work out the target layout first (lookahead) and
  move what shows towards it; SwiftUI's `matchedGeometryEffect` and Flutter's `Hero` fly a pair matched by id in an
  overlay. Ours: the node made once is still there at its cause's moment, so where it is drawn then is the "from"; the
  layout of the frame of the cause is the "to"; a paint offset from one to the other, let go by its curve. Only the
  cause (an `each` that moved a row, a stack that pushed a page, a sidebar folded) says so; nothing compares frames.
  What flies between two places (kind 4) flies in an overlay, the pair matched by its key.

The nine kinds (docs/motion.md) in it:

| Kind | Made once as | Read in |
|---|---|---|
| 1. In the hand | the gesture writes a signal of where it is; let go, `animated` from there at its speed | paint (a place), layout where it resizes (a sheet's height) |
| 2. Coming and going | `show` / `each` keep the node while its exit runs; enter from what it hangs on | paint |
| 3. Moved or reshaped | the cause starts a FLIP from the node's place or ground at that moment to the new layout | paint (place, ground); layout only for a size the design moves |
| 4. Flying | an overlay node keyed by the pair, from the source's place to the arrival's | paint |
| 5. Another page | the stack's page nodes, each a place offset bound to the stack's way (pushed, popped, risen), told by the navigation | paint |
| 6. Scrolled to | the list's offset `animated` by its glide | layout of the list's window (which rows show), paint of the rest |
| 7. A control answering | the control's state signals eased (lit, pressed, its value) | paint |
| 8. Waiting | a look by the clock (`cycle_look`) | paint |
| 9. Emphasis | `animated` told at its cause | paint |

What this takes away: "what is placed by the clock" (a page's slide as a closure the build put on its node,
`Ctx::moved_by`) becomes the page node's own paint offset, kept with it; "where the last frame drew a target, read
as it is built" (`Ctx::rect_of` in a build, the motion package's records found by key after layout) is the node's own
place, read at the cause's moment; the motion package's per-frame records by key (`mo.recs`, measures) go with the
frames that built everything again.

## What it must be, and how that is shown

What the others do, read for this (2026-10-30, the review of src/view: Solid's owners, Vue's effect scopes and Vapor's
render effects, Slint's pure properties, Compose's phases and AnimatedVisibility, Flutter's layout and layer updates,
Qt Quick's renderer), and what it comes to here: fine-grained bindings of properties, a lifetime owned apart from what
is tracked, and layout, paint and composition kept by node. Neither another engine nor another signals.

1. **What is tracked and what is owned are two things.** A node's making runs in a scope of its own (Solid's Owner apart
   from its Listener: `untrack` stops following reads, never owning): every effect, computed, timer and native
   resource made there is let go with the node, its cleanups run once. A handle on a node let go, a callback come late,
   does nothing (its making is checked where every use of a handle begins). The signals' algorithm stays as it is; what
   is added is the owning.
2. **A binding works its value out and nothing else.** Written in a batch by one event, marked stale, its value worked
   out as the frame takes it (Vapor's render effects queued, Slint's lazy pure properties); a value set twice is set
   once; a property given once (`Is`) makes no effect. A property has one binding at a time (another lets the one before
   go); its phase is the property's (width, words, ground, a transform), not the caller's. No `set` does layout,
   shaping or the host's work where it is set.
3. **What is done again is what the change is.** Structure, measure and place, what is drawn, how it is composed (a
   transform, an opacity, a cut), what is read out: each its own. A colour lays nothing out; a move measures no words; a
   node moved keeps what it holds where they are in it. Layout goes up to the first box that does not read what it
   holds (a size given is not that by itself: a holder may read its intrinsic size or baseline). What is laid out tells
   only what reads it (a popover's place, a list's window), never a whole page made again.
4. **The scene is kept, not the frame.** Each node's drawing kept where it is in what holds it, in order; what composes
   it (transform, opacity, cut) kept on the node that does; the host given the records and composition that changed.
   A host taking the whole frame each time (gles_render.h's glBufferData of all of it, apple_render.m's upload) is
   given it by an adapter said to be one: it is no "only what changed", and no step is done because of it. A test may
   unfold the scene into whole `Drawn` records; nothing inside works on that unfolding.
5. **Composed is not a texture each.** Overlap, rounded cuts, glass and opacity mean what they mean now: an opacity on
   a group composed and then faded is not each of its parts faded, and is not swapped for it. Drawing and hit testing
   share one transform and cut; a holder moved does not write its subtree's places in the window again (they are worked
   out as they are visited).
6. **Coming, there, going, gone.** `show`, `each` and the stacks own a node while it leaves: still drawn, no longer
   pressed nor read out, let go when the exits started by its cause end (Compose's AnimatedVisibility). Time is read by
   what moves and by what waits for a moment, each from its cause's start, target, curve and the frame's time, never by
   how many frames went by.
7. **The old view is a node.** Made, updated and let go at a node's edges (Compose's AndroidView: factory, update,
   release), given a size, a place, a cut and a place in the order, and pressed through the tree. The first island may
   be the whole app; the API takes one a page, so the old goes from the outside in, never an app beside the tree.

8. **One logical timeline.** Everything that happens at a moment of its own (an input, a message, a leaving ending, a
   step of what goes by steps: docs/motion.md, the logical clock) is on one timeline the host only wakes and gives the
   time to, done in the order of its moments (those together in the order told), each as of its moment; frames and
   events advance it to their moment (Tree::advance) and only observe and draw it.
9. **The same events, the same picture.** From the same state, the same events with their moments and the same
   settings, any moment looked at shows the same picture, presses the same things and has made, kept, let go and set
   leaving the same nodes, whether frames came at 60 Hz, at 120 Hz or once at that moment: frames only change how much
   work is done. So what comes and goes is committed with the change that caused it, at that change's moment (an
   input's its event time; the time is the host's, given to the tree, never read where it is worked out), what had
   ended by then settled first; what a component made then reads the state as it was then. A frame settles what ends
   by its own moment and draws; layout, words and paint wait for it and are merged. Nothing is made right by one frame
   more, by reading the time where a value is worked out, or by waiting for things to settle.
10. **A frame goes one way: events, bindings, layout, paint.** The events due by its moment are committed first, each at
   its own; then the bindings told are worked out; then layout runs once, measuring and placing; then what changed is
   painted. Layout is of one moment, the frame's; a frame drawn ahead of it (for when it is shown) samples only paint's
   properties there (a place moved, a look), as a compositor's motions are, never a size. Nothing goes back within the frame (Compose's phases: "no way to go backwards while in the same frame").
   Sizes and places worked out by layout are read by paint, by hit tests and by the next event; no binding, `computed`
   or `reacts` reads them to change the structure, a property layout reads, or where a list is scrolled to. Where one
   thing's size decides another's (the composer's height and the room the messages leave under them), their nearest
   common holder lays both out (a layout of its own: Compose's "the minimal shared parent serves as the source of
   truth"), not a size told back and set on the other. The one structure made in layout is a lazy container's
   (rule 11): it makes and lets go of nodes in its own subtree as it lays them out. `Tree::laid_out` does not call
   itself; a node marked during layout fails a test where what is marked and what marked it are the tree's own (an old view
   lays out the old way, reading its layout back and building again: what it marks is counted as owed, the count only
   ever smaller, never let fail what is not yet the tree's) (the browser's ResizeObserver defers what it cannot deliver and
   says so; here what a frame cannot settle in its one pass is a fault, rule 9).
11. **A long list is laid out from its anchor.** Its scroll state is an anchor: a row's key and how far its edge is from
   the list's (Compose's LazyListState: the first visible item and its offset, kept by key across changes of the
   rows). Each layout measures rows out from the anchor until the window (and a little more, made ahead) is filled,
   and makes, keeps and lets go of rows by that; no row off the window is measured or gone through. A chat's list is
   laid out from its end (reversed: Flutter's `reverse`, Compose's `reverseLayout`): at its end is the anchor at the
   newest row, 0 from the foot; a row come at the end while it is there is at the end; history come over it moves
   nothing in sight; going to a message is its key put as the anchor. Heights measured are kept by key for the scroll
   bar's estimate of the whole, and only for that. A row coming, going or moving is drawn moved (an offset, a cut, a
   fade, in paint) from its cause: the list is laid out where its rows end up, each of their changes of place drawn
   on the way there; a row whose own height moves is laid out again alone, as what it holds changes.
12. **A list is read by its index, its changes told with their cause.** What a list shows is given as how many rows,
   the key and the value of row i, and the changes since (inserted, removed, moved, one row's value set), each with
   what caused it (a message come, one sent, history fetched): a row's coming or going moves by that cause, never by
   comparing the rows before and after. Where a key is is looked up from where it was last (Compose's nearest range),
   not from a map of the whole. What a row shows is worked out of its value for the rows made, by key and version;
   nothing worked out for one row goes through all of them (`keys().search`, `find_first`, a map of the whole array in a
   binding). A list given whole (a topic's first value) is gone through once, as it is given.
13. **The hand and the keys go one way down the tree.** Drawing and hit testing walk what is drawn, a subtree wholly
   outside its clip skipped; there is no order of every node kept and made again as one comes or goes. A key goes to
   the node with the focus and up through what holds it (the DOM's bubbling); back goes to the topmost layer (a menu, a
   sheet, the page stack's top). Nothing is found by going through the whole tree.
14. **What a frame costs is what shows and what changed.** A frame scrolled, a row laid out another height, a motion
   stepping, one message come: each costs what is on screen and what changed, never the list's length. Held by
   counting: the same scene with 30 and with 3000 rows does the same work a frame (bindings worked out, rows gone
   through, measures), a check in CI; and in milliseconds (matklad's "Benchmark In Milliseconds") against the build
   before a page moved into the tree: opening, scrolling and a send's motion each faster, on a native build.
   A frame's cost is also what the GPU and the display do for it, counted the same way: the area drawn again (the
   damage the host is given, as a share of the window), the area of glass sampled again for it, whether the host was
   asked for the frame it drew and for the display's highest rate while something is typed or moves. A keystroke into
   a field draws again the field and what it pushes, no more; a scroll, the list and what is over it; neither builds an
   old view again. Held by the Tester run as a host runs it (a frame at each refresh, drawn only where asked: the frames
   a host would draw: #3962) on the real pages with long data, 30 and 3000 rows alike, in CI; and on a
   phone (the slowest device the app ships to: frames over its budget, refreshes missed, the GPU's time a frame) against
   the build before, a dev build beside the person's own. Milliseconds on a desktop's offscreen run show a step is not
   slower; they do not show a frame is in its budget, and no step is called faster by them alone (2026-11-05: the
   layers of rule 15 measured four times faster offscreen drew the whole phone screen every frame).
15. **The scene is kept by layer.** A layer begins at the window's root, at what the root holds (a page, what is over
   it), at what a `show`, `pick` or `each` made (a page, a sheet, a row), at a list's rows, at an old view, at what is
   over all or over the scrim, and at what moves as it is drawn (a place property bound: a spinner turning, a row
   sliding, a fade): `Tree::starts_layer` (Flutter's repaint boundaries, Chromium's paint chunks). Each keeps what it
   drew, where that is among the frame's instances, what it was cut, faded and stretched by as it began, the glyphs'
   plots it draws from (said drawn from in each frame the old frame paints: `Atlas::drawn`) and the pictures it shows, and what its
   drawing read, by a watch of its own (src/ui/scene_layers.mbt).
16. **A frame draws again only the layers something of changed, and says it at its cause.** The tree tells what changed
   as it changes (`Tree::take_changed`: content made again; `take_placed`: placed, faded, turned or cut otherwise;
   `take_removed`: let go); a layer's watch tells what its drawing read changed (an image decoded, a field's words, the
   clock while it reads it); a moment its drawing waits for comes. Each marks the layer it is in; one placed, or cutting,
   fading or setting the glyphs of what it holds, draws all it holds again with it. Every other layer is the instances it
   was: copied where it is put, as the old frame paints the frame, or left where it lies, a frame of the tree alone
   (`alone_frame`: nothing of the old frame painted, each layer to draw again drawn in a buffer of its own from what it
   began in and put where it was, where it comes to as many instances; else the old frame paints the frame, copying
   what is kept).
17. **Where the window changed is told by what changed, never found.** Each node the tree said changed is drawn again
   where all it and what it holds reached as last drawn and where they reach once drawn (`@damage.Parts`: as far as any
   pixel reaches, merged, at most four, glass a part reaches taken in whole); a layer whose drawing read what changed,
   all of it; what the old frame paints again: each old view where what it draws differs from what it drew the last time it
   painted (`@damage.Parts::add_changed`: the old frame says nothing of what changed in it, so this one place compares,
   an adapter of rule 4's kind said to be one, gone with the islands; an old view whole is a phone's screen whole); the old
   frame's cycles by the clock where they were and are; a stream's picture each frame. Nothing of the tree's is
   compared with the frame before it; `src/damage` keeps no frame (the old views' instances, kept by the scene for
   the adapter above, go with them).
18. **The host is given the whole by an adapter that says so.** The renderers upload every instance each frame
   (`@hostapi.present`): that is the adapter of rule 4, named where it is (`h_present`), no "only what changed", and
   nothing is done because of it; what changed is the parts (`@hostapi.render_dirty`). A renderer taking the layers
   that changed is its own step, not this one.
19. **Held by the tests.** A frame that copied a layer kept is painted again with nothing kept, in every Tester
   (`Ctx::scene_check`, with `looks_check`): instance for instance the same, or the test fails naming the layer; a frame
   of the tree alone is built whole after it as well and compared (`looks_compare`). What a frame costs is counted
   (`@ui.scene_done`: layers drawn, instances drawn and copied, frames of the tree alone, the work of saying where it
   changed): a spinner turning over a chat's 3000 messages and over an empty page cost the same, as does a row of a
   list of 3000 and of 30 changed (src/ui/scene_cost_wbtest.mbt, in CI).

Where mbui is not yet so (2026-11-04):

- ui's `ListRows::in_node`, whose rooms are read as each block is worked out, still goes through the old windowed list
  (view's `scrolls_window_rooms`): it works the rows' tops out from the first and goes through them as it is scrolled;
  its end is followed and what is read held by reactions reading layout's results. It is made again as rule 11 says,
  its rooms read before the layout as `in_node_indexed`'s are, its motions as paint's.
- Layout's results are signals (`owed_laid_size`, `owed_laid_window`, `sizes_told`) read where they change what is
  made, and `Tree::laid_out` calls itself again where what they told marked more (rule 10); a change settled as of its
  logical moment turns the clock there and back in the middle of layout. Each reader goes to paint's, the next event's,
  or into the layout of the holder of both; laid_out runs once, at the frame's moment.
- The core's topics give a list whole each time, and pages work out maps and positions of the whole (rule 12).
- What is drawn is gone through down the tree as it is (`Tree::walk_drawn`), no order of every node kept; a point is
  found going down only into what may take it there (`Tree::walk_taken`: what bounds its input to itself, a column
  that scrolls, gone into only where the point is in it; what takes no press skipped whole); a key goes to what has
  the focus and up through what holds it, then to the rest said to take keys, topmost first, as a window's own
  listeners; back to the topmost said to take it, by the window's stack of layers first (rule 13, counted:
  `walk_cost_test.mbt`, the same with 30 rows and 3000). Not yet: a node's box does not bound what it holds (what is
  placed absolutely may lie past it), so a subtree is skipped only where something cuts input to it, and the host is
  still given the whole scene each frame to draw (rule 4).
- The old frame is built beside the tree every frame (ui's `frame_drawn` after `view_frame`), back and focus each kept
  twice; a page moved into the tree lets its old way go in the same change.
- `Tree` holds events, the clock, layout, focus, back and the scroll bars together, whether a step may run said by
  nineteen flags of its own; it is taken apart by the phases of rule 10, one phase at a time.

Shown by counting, on the real path, apart: bindings worked out, nodes made and let go, measures, drawing made, what is
composed again, the scene gone through, and what is handed to the host. A colour changed touches no other component; a
page moved makes nothing again; a list's rows reused and let go as they should be; a node let go leaves no subscription,
timer or native resource; frames at 60 Hz, 120 Hz and a jump to the moment come out the same. A renderer may go through
the records kept to draw them; nothing finds what changed by working the tree out whole or comparing it.

## Layout read back: how rule 10 is made so (2026-11-05)

Today a size or a place layout worked out is a signal (`View::owed_laid_size`, `owed_laid_window`,
`owed_drawn_window`, the tree's `sizes_told`), read by bindings, `computed` and `reacts` that change the structure, a
property layout reads, or where a list is scrolled to; `Tree::laid_out` then calls itself until nothing more is marked
(up to `laid_passes_most`), and a change settled in the middle of it turns the clock to its moment and back. Told a
frame later instead, the loop is only moved between frames: the frames do not stop, and what they show depends on how
many there were (rule 9). So none of it is a signal any more, in a frame or after it. What layout works out is read in
three places, each untracked, and nowhere else:

1. **Paint, this frame's.** A place property (`offset`, `drawn_off`, `scale`, `alpha`, `radius`) may be given as
   `Painted(fn(laid) { … })` (not `Drawn`: a `Pivot` is that), a third `Live` beside `Is` and `By`: worked out as the frame is painted, after its one
   layout, reading where nodes were laid out this frame through `laid` (`Laid::rect(v)`, `Laid::size(v)`). A signal it
   reads, or a node it read laid out elsewhere, draws its layer again (rule 16), never lays anything out. What a flight lands on, a preview beside its link, a
   ring around what is picked, a thumbnail following its node: paint, drawn where things are in the frame shown, a frame
   behind nothing.
2. **The hand and the next event, the frame on screen's.** `View::shown_rect()` / `shown_size()`, plain values of the
   frame last drawn, read only in an input event's handler and in a hit test (a menu opened beside what was pressed,
   where a row was for a jump, whether the pointer is on a card); in a reaction, an effect, a timer or a build, even
   untracked, it would set state a frame late, by how many frames there were. A menu that stays beside its anchor is placed by `View::beside` in
   layout, not by a rectangle read once.
3. **The layout of what holds both.** Where one size decides another, their nearest common holder lays both out:
   `View::layout_box` (layout_box.mbt, Compose's `Layout`/`SubcomposeLayout`) is given its constraints, makes the
   children it asks for by key, measures and places them, all in one pass. On it:
   - *room down, size up*: an arrangement by the width given (窄排法 / 宽排法, a segment's words fitted to its track, a
     table's columns, a side panel's width, what a pane holds by its width) is a key chosen from the constraints and the
     child of that key made; `View::by_room(pick, make)` is the case of one child;
   - *what one is laid out at, from another measured first* (the composer measured, the list given what is left; a
     header's copy key at the header's foot; a box opening to a share of what it holds measured whole);
   - *filling what holds it* needs nothing new: `over(Is(true))` is laid out over all of its holder, `width_share(1.0)`
     as wide, `Within(n)` as wide as `n` or the holder where that is less; `min_width_within` and `max_width_within` say
     the least and most so, so a card between 360 and 560 within its room is said, not read back;
   - *a long list* (rule 11; a page's windowed list, `scrolls_window`, by the same pass, counting each row it has not
     measured as its estimate) lays out its rows from its anchor in its own layout box (list_anchor.mbt): which rows are
     made, where they are, how far it may scroll, whether it is at its end, all from one pass; what it measured last
     time (its `ListLaid`, the heights it kept by key) is its own record, read by its next layout, never a signal; a row's
     room (`ListRoom`: offset, cut, fade) is set on the row's holder by the list as it places it, for paint. Going to a
     row, keeping the focused field in sight, following the end: an intent an event sets on the list's state, taken by
     its next layout (`ListState::reveal(key, align)`, `follow_end`), not a scroll set by a reaction to a rectangle.
     A scroll moves the anchor by the heights of the rows it goes past, each measured as it is passed if it was not;
     an estimate is only for the scroll bar and for a jump by key far off, so where a drag stops is the same at 60 Hz,
     at 120 Hz or in one jump.

What a layout makes (a list's rows, `by_room`'s and `layout_box`'s children) is a cache of the picture: how many are
made and let go is by the frames there were and the room there is. So it holds no state of the app's and starts nothing
that lasts (a subscription, a download, a decoded picture, a draft): those are kept outside it by the data's key, and
what it makes reads them. A long list makes the rows a scroll goes past only to measure them; which rows were shown is
told, never found by a row being made: `scrolls_window`'s `seen` (in sight as it was laid out, or gone across as it
went on by itself, whether the frames between were many or one; not what a move at once went past), told as the layout
that found them is done, of its moment, whether a frame is painted before what comes next or not, as a page opens a
draft for a block it showed; `scrolls_anchored`'s `sighted` (what a move at once went past too), told once the frame
is painted, as the pictures a chat's rows show are asked of the host.

What waits for a node "to be laid out" (a sheet opened once the page is there, a keyboard asked for once the field is)
waits for nothing that is the tree's: it is done at its cause; where the host must have the node drawn first, the node's
`on_first_drawn` is an event on the timeline (rule 8) at the frame that drew it, said once, and only asks the host for
something (the keyboard, a native view); it sets nothing a build or a layout reads.

**The frame.** `Tree::laid_out` runs once a frame, at the frame's moment: the events due by then committed first at
their own (rule 9), then the bindings, then layout, then paint. No settling inside it, no clock turned there and back.
Gone with the signals: `owed_laid_size`, `owed_laid_window`, `owed_drawn_window`, `Tree::sizes_told` and the nodes'
size, rect and drawn-rect cells; `View::owed_once_laid_out`; `laid_passes_most` and `laid_marked_at`; the clock turned
inside layout (`settle_now`'s, #4106) and each place given the frame's moment by hand (#4025, #4113); a list's rows told
their room (#4095's `rooms_told`) and its extent held up from below (#4115's `extent_floor`); what a hand-off from the
host shuts and opens of layout reads (`shut_layout_reads`, `reads_own`: #4105, #4109), which the rule below holds
everywhere. An old view hosted still lays out the old way, its passes counted as owed until it is gone (rule 10).

**Where it stands (2026-11-06).** `Tree::laid_out` lays the tree out once for each moment it is asked at (a frame's;
an event's, finding where things are at its own moment: Tree::laid_now). What comes after that layout only places (a
column brought to what is to be in sight moves what it holds); a layout more is taken only for what is owed, counted by
what asked for it (`Tree::owed_passes`: sizes told, once laid out, rows left out told, brought into sight, what is under
the pointer and a bar near it told after placing), and anything else that marks the tree's layout after its own layout
is a fault saying where it marked it (in a host's run: told, that moment drawn and hit as its one layout has it, what
was marked laid out as the tree is next laid out, at whatever moment that is; what is drawn then is that layout's, not
what was marked after it, and is not to be taken as one with it). The passes of one outermost layout and those nested in
it (what is under the pointer told after placing lays it out once more) are bounded together; layouts asked for apart at
the same moment (two inputs at one moment) are each their own, their order the events'. The count names what is still
to move and proves nothing of determinism: that is what the rules above aim at, still to be shown where the lists'
caches and kept heights differ by the frames there were. The reads
still owed are named so (`owed_laid_size`, `owed_laid_window`, `owed_drawn_window`, `owed_went`, `owed_left_out`,
`owed_once_laid_out`), counted by detlint's `layout-read-back`; as each is gone its count, and its passes, are.

**Wrong is red,** by where a read is, not by whether it is tracked: the frame's phase says where it is (an input
event, a hit test, a `Painted` being worked out, a layout box's `place` of its own children). `laid` read outside a `Painted`,
`shown_*` outside an event's handler or a hit test, a size or a place of layout's anywhere else, and a signal a build or
a layout reads set in `on_first_drawn`: each a fault naming what read it and which node; `laid_out`
entered a second time in a frame is a fault; detlint's `layout-read-back` counts what is left and only falls, to 0. In
every Tester: one layout pass a frame, and the frames stop once nothing is due (the last input and the motions it set
off over, a few frames on: no frame more is asked for); a drag over rows 40 and 80 tall in turn stops on the same row
at the same offset, and a scroll leaves the same state and decodes the same pictures as often, drawn frame by frame or
in one jump; a row let go and made again decodes nothing again.

**The way there,** each a PR, CI at its baseline, the six steps' table no worse, one pass a frame where the step
reaches:
1. the framework's: `Painted`, `Laid`, `shown_rect`, `by_room`, `min_width_within`/`max_width_within`, the list's intents and
   its rooms set in its layout, `on_first_drawn`; the old interfaces kept as they are (laid out again in the frame,
   under the cap), so the passes a frame counted fall only as readers move, never by telling later;
2. the app's readers moved, by the inventory (85 lines: paint 16, the hand 6, a holder's layout 60, a wait 3);
3. the faults on, the old interfaces gone with detlint's count at 0;
4. the passes' cap, `once_laid_out` and the moments said by hand gone; `laid_out` once.

## Held by the tests

The Tester keeps its one check, said another way: whatever a frame did by what was marked, the same state made into
a tree from nothing, laid out and painted whole, must come out the same, instance for instance, and ask for the same
next. A frame that parts from it is a read not followed (a value not a signal, a binding that read outside itself) and
fails, saying the frame, the node and the property. Every test holds it, as `looks_check` does now.

## The way there

Each step merged with all tests green, no page costing more a frame than before it (rule 14: counted, and on a
phone against the build before; a page partly moved is held to it too, its old views and the adapters included), and the app's frames pixel for pixel the same as before (the screens, corners,
squeeze and contrast checks; film's images before and after where a step touches what shows).

1. **What a frame says goes onto its nodes.** Today a build says what takes the focus, the pointer's shape, what
   takes presses, drags the window, keeps what is picked, asks for a menu, what is told once the build is over, and
   its paint where presses go, what scrolls, the words that can be picked, the scroll bars, into lists of the frame's
   (said.mbt's `build_lists`, `paint_lists`), and besides them what is read out, the corners worked out once laid
   out, what floats over a list, what sticks, what scrolls sideways, the moves shown, the looks drawn, the words, what
   was used (kept_nodes.mbt's RowNodes: thirty kinds a kept row records and says again). Each becomes what a node
   holds, asked of the tree as it is laid out and painted. Then a subtree kept is its nodes and nothing besides, made
   once or built: the ground both the old frame and the new one stand on, one list a PR, nothing shown changed.
2. **The runtime**, src/view (2026-10-30): nodes made once, each its own scope (what it makes owned by it) and a
   checked handle; one binding a property, worked out as the frame or an event takes it; `show`/`pick`/`each`
   committed at their cause, leaving and coming back; a frame visiting only what was marked, what a node draws kept
   where it is its own and its place composed apart; the tree's hit tests; events at their moment (Tree::event,
   Tree::bring_to). Its own tests: random trees changed a little at a time against one made fresh, timing at any frame
   rate the same, ownership and release.
3. **The old view as an island.** `old(node, fn(c : Ctx) { ... })` (src/ui/view_host.mbt) puts the old view, built the
   old way, in a node of the window's tree: built for the node's room, placed, cut and faded as it is, painted in its
   place in the tree's order, pressed through the tree. Every window (ui.run's, a Tester's) is such a tree; the app is
   first one island, the whole window, and looks and does just as it did. Any number of islands a window: each a
   subtree of the old frame kept as its nodes, built again only as what it read changes or an input goes to it, and
   owning (a scope of its node's) all it makes as it is built and laid out, its parts and rows and what they follow,
   let go at once with its node. The old frame's work area (its Ctx, its frame) is shared by the islands for now, a
   way there: what each owns is its own, and each is built and painted again alone: what one read changing builds that
   one (its part), not the old frame whole nor its other islands; an input builds the one it went to (the focus's, for
   the keys and the input method's words; none where the focus is the tree's); where an old view is placed or how big
   it is laid out is its own, not the frame's settings (moved, it is drawn where it is; resized, it alone is built
   again). What comes that is no signal yet (a message, a host's answer, a test's draw) builds every island anew, and
   is made a signal as it is found.
4. **From the outside in.** The window and its shell (frame, panes, tape, stacks, presenters) made once; each page in
   them an island. Then src/kit and src/sf's components, each given its made-once form beside its old one while pages
   still use the old; then each page made once, its island gone with it. Each step makes a page's island smaller; none
   leaves an app built two ways for longer than its PRs. What is on screen in every state (the islands under and over
   the shell: its bottom bar, its presenters, its toasts) goes before the pages, as it is paid for by every page while
   it stays.

   Where it stands (2026-10-31). Made once: the app's state (app_is: failed, signed out, starting, signed in) a node
   picked by it; signed in, the shell a node picked by the window's width (View::window) and whether a workspace is in
   view. Laid out Small with one, the narrow shell's nodes (still.fail's sfapp/narrow_shell.mbt): an island under all
   of it (what the frame does in every tier before its pages: what is told as the frame ends, the icon's number, the
   keys, whether the first page waits), the back of the stack's root a node said at the cause that changes whose it is
   (a tab of the bar pressed: narrow_takes_back), the stack, and an island over it (the bottom bar,
   what opens over the pages, the presenters, the toasts). The stack is the tree's (src/ui/nav_view.mbt): each page on
   it a node of its own, made as it is put on and let go as it leaves (what it made forgotten then, its `on_leave`
   told), its page an island while it shows; which pages show and where they are drawn are bindings (View::shift, in
   their own widths: the frame drawing them lays them out); a slide sets out at its cause's moment, its length by how
   big the stack is laid out then (View::laid_size), its end a moment of the timeline where the page that went is let
   go; a page pushed to show what the core has for it sets out at the moment that answer came, or once its wait is
   over (View::reacts, View::at_moment). The slide no longer waits for how late its first frame was to the screen (the
   old stack's `late_check`): a host's lateness is no event of the logic. Laid out Medium with a sidebar to show (or beside the
   system's bars), the tape (still.fail's sfdesk/tape_view.mbt): its row and its panels nodes made once, laid out by
   the tree (the sidebar's column, the page's panel, a chat's side panel while it is open or closes, a node of its own),
   what each holds an island; the tape's move a trajectory committed at its cause (where each thing it moves was then,
   worked out of the move before it alone, and where it goes), drawn as the row's offset; what is no cause of a move
   (the window, an edge dragged, the system's column) puts things where they go at once; the page brought over once
   the core has what it shows or its stay on top has waited its while (a moment of the timeline); a cover of the tree's
   over each panel not in use takes a tap, the secondary button and a finger's pull, each at its event's moment, a
   finger held still on it handed to the words under it (View::gesture's `through`), and says what it is, a screen
   reader's press of it its own at that press's moment (View::says, on_press). Laid out Large, the wide frame off the
   tape (still.fail's sfdesk/pane_view.mbt): its shell, row, column and page nodes made once, laid out by the tree,
   what each holds an island; the block's fold (⌘\, shown a while) a move committed at its cause, set out from where
   the move before had it then; the tape left mid-move for a place with no sidebar of its own, the block closing from
   where the tape had it then. On both what the page's pane shows while a page put on top waits for what it shows is
   its node's, at its causes (still.fail's sfdesk/page_wait.mbt; Nav::flat_keep: the one shown before kept by the
   stack till the core gives it or its wait is over). On both back while the frame takes it is a node of the tree's
   (still.fail's sfdesk wide_takes_back: a View::follows_back in a show bound to it, said at the cause that changes
   it; what is over the whole window put away and the history's entry before among it), what it does chosen as a
   gesture begins (a panel of the tape followed as it goes, or the shell's back done once, the history's entry chosen
   then), the host told the app takes back as the tree changes what takes it (Ctx::back_told_host); what an old view
   says takes back (a page's own stack, a layer over all) takes it before: a layer's (Ctx::overlay), as this opening of
   it, given up as it takes back, what it was said over (a page's own stack's) taking the next; dismissed so, by Escape
   or by a press outside it, it is given up at that moment (no input of its taken since, a press held in it called
   off, the focus given back) and what is told as it is dismissed told then (Ctx::with_dismissed: sf's presenters
   close what they presented at that moment), its view reading the dismissal and drawing its going as it is built
   next; a layer whose opener is told nothing of it (no with_dismissed) is closed by its view only as it is built
   next. The history's entries are made at their causes (still.fail's sfbase app_history.mbt: a person's act one
   change, its entry once that change is committed), but for an act taken as an old view builds (a row pressed), done
   with that build. The edges are nodes of the tree's on both (the tape's
   column edges, still.fail's sfdesk/tape_view.mbt; 大屏's sidebar edge, pane_view.mbt: src/sf's edge_node and
   edge_look_node): each press, drag and let go at its event's moment, their look, pointer's shape, words and tip
   bound to what they say; where a list's thumb an old view draws is shown under one's strip, the thumb's there for a
   mouse (ui's yield_thumbs: the tree's one choice of what takes a point, Tree::on_target, as the pointer is over it,
   goes down and is handed through; looked at again as the old frame's targets are published whole, not a frame on).
   A page pushed over the page's own stack on the tape slides at its causes (Nav::held_over). The checks that measure
   a frame measure the tree's nodes with the old frame's: what the hand changes (Tester::hand_moves: Tree::hand_nodes,
   each by its own identity, every cell that reads the pointer or the press lit), the corner rule (Tester::corner_faults,
   lit_all_faults, the rule held on every frame at rest: Tree::drawn_held, as drawn, each old view's box held by its
   node) and the styles' census (Tester::census: Tree::styled, as each is set). Still the old way: a peek's move aside
   read from the page's old layout. Old view still: a window of its own, the
   sign-in and the splash; the theme each island is built
   in; back, said by the islands as they are built, in the tree's order (the top page first, then the stack's swipe);
   which island takes a press where they lie one over another (where more than one is at a point, all of them are told
   of the input); the window's sides beside the system's bars (beside_sides: the islands are placed in the window's
   terms within it); the layers of the old frame (menus, sheets) painted over everything.

   What the narrow shell's old views do as they are told is set out at its cause's moment, not at the frame that next
   builds them, and drawing only reads it at the frame's: the bottom bar is told what the app's state says of it
   (shown, the notch's action, the places, the bars, the width of the box it is laid out in) by a reaction of the
   shell's node (View::reacts) at the moment that changes, its ways set out from then, a frame building it reading
   where they are; a zoom's commands take one moment as they begin (an event's said with it, else what the window's
   tree is doing: ui's `tree_cause`, else the frame's or the host's clock) and its glide and fling are ways of its own
   from it. A finger on the bar's glass is a node's (still.fail's bar_glass_node), each event at its own moment. An image
   opened over the pages is nodes of the tree's (still.fail's sfbase/viewer_tree.mbt): its layer, its ground (bound to
   its ways, the clock read only while one goes), its canvas taking up to two fingers, the secondary button and the
   wheel (View::on_drag, on_menu, on_wheel), each event decided at its moment by the zoom's and the strip's ways read
   there (Zoom::rect_at, scale_at; @motion.Way); it is set out as it is made, done at its ways' declared ends, reads
   ahead what is beside it as that is said, and stops taking presses as it closes. Its picture, its marks and the
   words written on it (the tree's fields), its bars on every tier and the system's bars' actions (each press at its
   event's moment), its keys (View::on_key: Escape, the arrows) and back (View::takes_back, a menu or a sheet over it
   first) are the tree's; so is its flight in and out, the picture drawn and cut by the flight's nodes at the moment
   each frame draws them. A film's and a song's viewer is the same layer (viewer_player): its ground, its fade, its
   bars' share of the way and its flight the tree's, the still and the black under it one image cut once
   (View::image_in), the frame it lands with taken as the host says it grabbed it (NativeView::grabs_told), its system
   bars' 全屏 following the player's state (signals). Hosted in it as old views, and why: the player's own body
   (Viewer::player_stage: its picture, controls, keys, 全屏 and turning sideways are the library's player, an old
   view; it says its back after the viewer's, so its own takes it first); what a thumbnail draws over its picture in
   flight (a film's capsule: the chat's own drawing, Viewer::thumb_over, given no place, its opacity the tree's); what
   it shows of anything but a picture of its own (viewer_hosted: a page, a table, code, words read as they come, the
   reader, a PDF), each its library part's old view. Still the old way there: where it flies from and back into, the
   thumbnail's place and corners as the chat's old view was last laid out (note_thumb's @motion.measure, thumb_of),
   and the chat's bar and composer put over the flight by the old frame's strata (over_flight): they move with the
   chat's page. A row or a part kept as its nodes follows what it read by a watch owned where it is
   built: the old view that made it going, the watch goes with it (stale and gone: Watch::gone), and one built again
   under another with the same key follows anew there, never put back as though it still followed.

   A modal layer is the tree's (View::modal): the topmost on, by where each is among what holds it as the tree is now
   (Tree::modal_top), takes all input; what it does not hold takes none, from the moment a change saying so is
   committed whole (Tree::at_cause, an event, a moment of the timeline, a structure's first making: what a change does
   in between is never seen half done). The old views ask it where they use input, each by the island it was built in
   (Node's and a focus stop's `island`, set as it is built and as its lists' rows are laid out): the frame's hit
   targets (an old view's found only while the tree lets it take presses: old_hit_open), the keys, Tab, the focus's
   words, a key catcher, the wheel, what is read out. A press held on an old view is held by the one it is on (the old
   frame's hit target's, an empty one over another passing it on: old_press_owner), and called off once at the cause
   of a modal layer coming over it, as the host calling it off is (Ctx::press_called_off, at that cause's moment).
   What a press called off sets going in an old view's list sets out at that moment: what it pulled past an end goes
   back from it (Ctx::release's spring back at `at`), however late the next frame; a fling, which a press called off
   never sets going, still sets out at its first frame on Android and iOS (Compose's playtime 0), the desktop's coast
   as it is let go.

   Not moved yet, and why: how far the wide frame's page moves aside as the folded sidebar is shown a while
   (still.fail's sfdesk fold_peek_shift) is worked out at the moment it is shown, from what the page shows across
   (Ctx::shown_across), and that is what the page's old view showed as it was last laid out (readback.mbt's
   reads_after_layout): a page opened a moment before, with no frame drawn between, moves the page aside by the one
   before's (a chat's page then the new chat's or the settings': 42 with no frame between, 0 with one). What a page
   shows across can be known at a cause's moment only once the page is the tree's (laid out at that moment: its
   structure and layout committed with the change, Tree::laid_now); filling it in at the next layout would say of the
   cause what a later layout found (a page or its data come between: still as frames fall), and building the old view
   outside a frame is no way there. It moves with the pages.
5. **What goes**, as no island is left: the frame's watch, paint watch and layout watch (frame_watch.mbt), kept parts
   and rows (kept_part.mbt, kept_rows.mbt, kept_nodes.mbt), said.mbt's recorded lists, `frame_passes_most`'s passes
   for a build, `rows_check` and `looks_check` as they are, `outside_said`, `Mover`, the `old` island itself. Gone
   already: src/damage's comparing of instances (rules 15–17, 2026-11-04). Gone first, as nothing used it once islands were kept as their nodes: the
   replay of a part or a row from what its build and paint recorded (KeptPart, RowKept, their bands, on_drawn_again,
   off since #2325).
