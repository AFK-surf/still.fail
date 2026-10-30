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
   one made fresh, as flex's reuse_test does.
3. **The old view as an island.** `old(fn(c : Ctx) { ... })` is a node whose subtree is built the old way, every node
   under it made again when anything it read changed (its build tracked as a whole, as frame_watch does the frame's).
   The whole app first runs as one island on the new runtime, and looks and does just as it did.
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
