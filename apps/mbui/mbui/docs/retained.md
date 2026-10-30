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
8. **A frame does what was marked.** As a frame begins: what came is written (the hand, the core's messages, the
   host's settings, the clock), the bindings it made stale run (`show`, `each` and `pick` make and let go nodes), the
   nodes marked are laid out (@flex.compute's reuse: only the dirty ones), what was laid out that a binding reads (a
   list's window, `laid_size`) runs those bindings, laid out again while it changes (`frame_passes_most`), then the
   nodes marked to paint are painted, their instances kept by node, and only the instances that changed go to the
   host. A frame where nothing was marked is no frame.

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

8. **The same events, the same picture.** From the same state, the same events with their moments and the same
   settings, any moment looked at shows the same picture, presses the same things and has made, kept, let go and set
   leaving the same nodes, whether frames came at 60 Hz, at 120 Hz or once at that moment: frames only change how much
   work is done. So what comes and goes is committed with the change that caused it, at that change's moment (an
   input's its event time; the time is the host's, given to the tree, never read where it is worked out), what had
   ended by then settled first; what a component made then reads the state as it was then. A frame settles what ends
   by its own moment and draws; layout, words and paint wait for it and are merged. Nothing is made right by one frame
   more, by reading the time where a value is worked out, or by waiting for things to settle.

Shown by counting, on the real path, apart: bindings worked out, nodes made and let go, measures, drawing made, what is
composed again, the scene gone through, and what is handed to the host. A colour changed touches no other component; a
page moved makes nothing again; a list's rows reused and let go as they should be; a node let go leaves no subscription,
timer or native resource; frames at 60 Hz, 120 Hz and a jump to the moment come out the same. A renderer may go through
the records kept to draw them; nothing finds what changed by working the tree out whole or comparing it.

## Held by the tests

The Tester keeps its one check, said another way: whatever a frame did by what was marked, the same state made into
a tree from nothing, laid out and painted whole, must come out the same, instance for instance, and ask for the same
next. A frame that parts from it is a read not followed (a value not a signal, a binding that read outside itself) and
fails, saying the frame, the node and the property. Every test holds it, as `looks_check` does now.

## The way there

Each step merged with all tests green and the app's frames pixel for pixel the same as before (the screens, corners,
squeeze and contrast checks; film's images before and after where a step touches what shows).

1. **What a frame says goes onto its nodes.** Today a build says what takes the focus, the pointer's shape, what
   takes presses, drags the window, keeps what is picked, asks for a menu, what is told once the build is over, and
   its paint where presses go, what scrolls, the words that can be picked, the scroll bars, into lists of the frame's
   (said.mbt's `build_lists`, `paint_lists`), and besides them what is read out, the corners worked out once laid
   out, what floats over a list, what sticks, what scrolls sideways, the moves shown, the looks drawn, the words, what
   was used (kept_nodes.mbt's RowNodes: thirty kinds a kept row records and says again). Each becomes what a node
   holds, asked of the tree as it is laid out and painted. Then a subtree kept is its nodes and nothing besides, made
   once or built: the ground both the old frame and the new one stand on, one list a PR, nothing shown changed.
2. **The runtime** (src/ui, beside what is there; begun in made.mbt: a node made once is filled by a call of
   Ctx::box or Ctx::text that makes it alone, followed by a watch of its own and filled anew in its place as what it
   read changes, put back unbuilt each frame otherwise; what it holds comes and goes by made_each and made_show; a
   press is a callback, Made::on_press; a frame built whole fills every node anew, so what was kept is held to it.
   Put among a frame's nodes where the old view says, Ctx::made: the island the other way round, the new inside the
   old, for the parts made once to grow from the leaves while the old frame holds them): nodes made once, `Live` bindings by phase, `show`/`pick`/`each`
   with owners, handlers, the tree's hit tests, layout of the marked nodes, paint kept by node, the frame of step 8,
   and the Tester's check of a tree made from nothing. Its own tests: random trees changed a little at a time against
   one made fresh, as flex's reuse_test does. Begun as src/view (2026-10-30): nodes, owners and checked handles,
   bindings by phase, show/pick/each, a frame visiting only what was marked; not yet the queued bindings (rule 2 of
   what it must be), a node's drawing kept where it is in what holds it (4, 5), leaving (6).
3. **The old view as an island.** `old(fn(c : Ctx) { ... })` is a node whose subtree is built the old way, every node
   under it made again when anything it read changed (its build tracked as a whole, as frame_watch does the frame's).
   The whole app first runs as one island on the new runtime, and looks and does just as it did. Begun in
   src/ui/view_host.mbt (2026-10-30): an app's window a tree (`set_view_app`), the old view built for its island's
   room, laid out where it is placed, cut to it, drawn between what is before and after it, pressed through the tree;
   one island a window yet, its place a global the old layout reads.
   An island is kept only where nothing it read changed, so what it reads must say when it changes: the pages' own
   state is signals, and what is put into one from elsewhere (a draft's files, a menu's choice) tells it. What comes
   that is no signal yet (the hand's events, a message, a host's answer, a test's draw) builds every island anew;
   the frames kept are those of the clock alone (a page sliding in or out). Each build of a frame builds the same
   (what a build changes of its own state, the next build of the frame starts from the frame before), and the Tester
   holds every island kept to it built anew.
4. **From the outside in.** The window and its shell (frame, panes, tape, stacks, presenters) made once; each page in
   them an island. Then src/kit and src/sf's components, each given its made-once form beside its old one while pages
   still use the old; then each page made once, its island gone with it. Each step makes a page's island smaller; none
   leaves an app built two ways for longer than its PRs.
5. **What goes**, as no island is left: the frame's watch, paint watch and layout watch (frame_watch.mbt), kept parts
   and rows (kept_part.mbt, kept_rows.mbt, kept_nodes.mbt), said.mbt's recorded lists, `frame_passes_most`'s passes
   for a build, `rows_check` and `looks_check` as they are, `outside_said`, `Mover`, src/damage's comparing of
   instances, the `old` island itself. Gone first, as nothing used it once islands were kept as their nodes: the
   replay of a part or a row from what its build and paint recorded (KeptPart, RowKept, their bands, on_drawn_again,
   off since #2325).
