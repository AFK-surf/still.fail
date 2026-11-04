// Compatibility widgets express input handlers as branches in their build. Execute those branches while their
// event is committed, before retained layout. The sizing build and the eventual paint build cannot consume them
// again. Inputs nobody read remain available to the legacy root outside the retained islands.

///|
priv struct OldInputReads {
  clicks : Set[Int]
  doubles : Set[Int]
  menus : Set[Int]
  keys : Array[(Int, Int, Bool)]
  actions : Array[(Int, Action)]
  mut tapped : Bool
}

///|
let old_input_reads : Ref[OldInputReads?] = Ref(None)

///|
/// The latest local layout of an island, measured since the frame's targets were published. Inputs use these
/// nodes to find targets; asking for geometry never draws a frame or runs a widget's input handler.
let old_input_boxes : Map[@view.NodeId, Int] = Map([])

///|
let old_targets_due : Ref[Bool] = Ref(false)

///|
fn old_targets_refresh(c : Ctx, tree : @view.Tree) -> Unit {
  if !old_targets_due.val { return }
  old_targets_due.val = false
  let was_said = dr.targets_said
  dr.targets_said = false
  c.targets_start()
  c.targets_found(paint_base.root, tree) |> ignore
  // These targets describe the new layout, not a new paint. The normal frame will publish its own snapshot.
  targets_kept.stale = true
  c.targets_commit()
  dr.targets_said = was_said
}

///|
fn old_inputs(c : Ctx, at : Double) -> Unit {
  if old_input_reads.val is Some(_) || old_placed.is_empty() { return }
  desk_frame_start()
  if
    (c.clicked.is_empty() && c.double_clicked.is_empty() && c.tapped is None &&
      desk.keys.is_empty() && desk.menus.is_empty() && c.asked_actions.is_empty() && c.actions.is_empty()) {
    return
  }
  let reads : OldInputReads = { clicks: Set::new(), doubles: Set::new(), menus: Set::new(), keys: [], actions: [], tapped: false }
  old_input_reads.val = Some(reads)
  let was_clock = c.clock
  let was_evented = nodes_run.evented
  let was_only = nodes_run.evented_only
  c.clock = at
  nodes_run.evented = true
  nodes_run.evented_only = -1
  c.focus_frame_start()
  // Snapshot the existing islands: a handler may open or close one. Newly opened content was not a target of
  // this input and must not take that same input when it is first made.
  let placed = old_placed.copy()
  for p in placed {
    match old_islands.iter().find_first(fn(o) { o.id == p.0 }) {
      Some(o) => {
        old_build_size(c, o, p.3, height=p.4, measuring=false) |> ignore
        // An input handler can change the content while this build reads it. That read may acknowledge the
        // content watch before its queued notification runs. Invalidate the intrinsic leaf for the input itself,
        // before the retained layout resolves it; never feed the measured result back into a layout binding.
        if o.natural { o.measure_revision.set(@signals.untracked(fn() { o.measure_revision.get() }) + 1) }
      }
      None => ()
    }
  }
  nodes_run.evented = was_evented
  nodes_run.evented_only = was_only
  c.clock = was_clock
  old_input_reads.val = None
  c.clicked.retain(fn(id) { !reads.clicks.contains(id) })
  c.double_clicked.retain(fn(id) { !reads.doubles.contains(id) })
  desk.menus.retain(fn(m) { !m.0.iter().any(fn(id) { reads.menus.contains(id) }) })
  desk.keys.retain(fn(k) { !reads.keys.contains(k) })
  c.actions.retain(fn(a) { !reads.actions.contains(a) })
  if reads.tapped { c.tapped = None }
}
