// Drops are input causes, like a paste. A retained page names the editor that receives drops beside its fields;
// an editor directly under the drop keeps its own caret and paste limit, and a layer over the page keeps the drop.

///|
priv struct TreeDropField {
  within : @view.View
  field : @view.View
  when : () -> Bool
  paths : (Array[DroppedPath]) -> Bool
}

///|
// kept across runs: each registration is owned by its node and removed with it; drop_reset also clears them.
let tree_drop_fields : Map[@view.NodeId, TreeDropField] = Map([])

///|
priv struct TreeFileDrop {
  node : @view.View
  when : () -> Bool
  over : @signals.Signal[Bool]
  dropped : (Pick) -> Unit
}

///|
// kept across runs: each target belongs to its node and drop_reset clears the registry.
let tree_file_drops : Map[@view.NodeId, TreeFileDrop] = Map([])

///|
// kept across runs: the one hovered target, cleared when it leaves, its node goes or the run is reset.
let tree_file_hover : Ref[TreeFileDrop?] = Ref(None)

///|
/// Let files from outside the app go into this node. The returned value follows whether the files are over this target;
/// it may be read by a node's reactive style. The deepest visible target takes the drop once. The callback gets the
/// pick whose files are read asynchronously; Pick::files follows the host's answer when read in a reactive effect.
/// The node owns the registration and its hover, and `when` says whether it accepts files now.
pub fn files_into_node(
  node : @view.View,
  dropped : (Pick) -> Unit,
  when? : () -> Bool = fn() { true },
) -> () -> Bool {
  let over = @signals.signal(false, same=fn(a, b) { a == b })
  let own : TreeFileDrop = { node, when, over, dropped }
  match tree_file_drops.get(node.id()) {
    Some(previous) => {
      if tree_file_hover.val is Some(hover) && physical_equal(hover, previous) { tree_file_hover.val = None }
      previous.over.set(false)
    }
    None => ()
  }
  tree_file_drops[node.id()] = own
  node.owns(fn() {
    if tree_file_hover.val is Some(hover) && physical_equal(hover, own) { tree_file_hover.val = None }
    match tree_file_drops.get(node.id()) {
      Some(now) if physical_equal(now, own) => tree_file_drops.remove(node.id())
      _ => ()
    }
    over.set(false)
  }) |> ignore
  // A changed condition can expose an ancestor target even while the pointer stays still.
  node.owns(@signals.effect(fn() {
    if !(when)() {
      if tree_file_hover.val is Some(hover) && physical_equal(hover, own) { tree_file_hover.val = None }
      over.set(false)
    }
    h_frame_owed()
  })) |> ignore
  fn() { over.get() }
}

///|
/// The innermost eligible target in the same visible chain as a let-go, including press room and clipping.
fn tree_file_aim(
  x : Double,
  y : Double,
  fields_block? : Bool = true,
  after_old? : Bool = false,
) -> TreeFileDrop? {
  guard view_app.val is Some(tree) else { return None }
  let nodes = tree_file_drops.values().map(fn(own) { own.node }).collect()
  guard !nodes.is_empty() else { return None }
  let mut found : TreeFileDrop? = None
  // The input event or frame already brought the tree; place the old hits without advancing it a second time.
  old_hits_place(g(), Some(tree))
  for node in drop_nodes_at_now(x, y, nodes) {
    match tree_file_drops.get(node.id()) {
      Some(own) if @signals.untracked(own.when) => {
        found = Some(own)
        break
      }
      _ => ()
    }
  }
  guard found is Some(own) else { return None }
  match tree.target_at(x, y) {
    Hosted(host) if !after_old && tree.holds(own.node.id(), host) && old_file_drop_there(host, x, y) => return None
    Pressed(id) | Dragged(id) | TopRow(id) | Off(id) =>
      if fields_block && tree_fields.contains(id) && tree.holds(own.node.id(), id) { return None }
    _ => ()
  }
  Some(own)
}

///|
/// A file target drawn above an unrelated retained text target gets Finder's paths as files. A field or its registered
/// path region inside the file target retains its existing first chance to take those paths as text or references.
fn tree_file_before_tree_paths(x : Double, y : Double) -> Bool {
  guard view_app.val is Some(tree) &&
    tree_drop_aim(x, y) is Some((field, region, direct)) &&
    tree_file_aim(x, y, fields_block=false) is Some(files) else { return false }
  let text_target = if direct {
    field.view
  } else {
    region.map_or(field.view, fn(own) { own.within })
  }
  !tree.holds(files.node.id(), text_target.id())
}

///|
/// An old island's own hit target, including a box that points but does not take a press, keeps its drop.
fn old_file_drop_there(id : @view.NodeId, x : Double, y : Double) -> Bool {
  if old_wheel_there(id, x, y) { return true }
  !old_drop_within_now(x, y).is_empty()
}

///|
/// Re-evaluate a stationary external drag when its target, geometry or a covering layer changes.
fn tree_files_refresh() -> Unit {
  // Finder gives paths for a field to paste; Explorer gives only a pick, so the enclosing target takes it there.
  let aim = dropping.held.bind(fn(p) { tree_file_aim(p.0, p.1, fields_block=platform() == 0) })
  let before = tree_file_hover.val
  if before is Some(a) && aim is Some(b) && physical_equal(a, b) { return }
  tree_file_hover.val = aim
  match before {
    Some(own) => own.over.set(false)
    None => ()
  }
  match (tree_file_hover.val, aim) {
    (Some(now), Some(own)) if physical_equal(now, own) => own.over.set(true)
    _ => ()
  }
}

///|
/// A visible old field in front of a target keeps Finder paths. A field in an old island underneath a retained target
/// does not get in that target's way, even though it is still present in the old frame's hit list.
fn old_field_before_file_target(own : TreeFileDrop, id : Int) -> Bool {
  let c = g()
  guard dropping.paths.iter().find_first(fn(d) { d.pick == id && c.editors.contains(d.target) }) is Some(d) else {
    return false
  }
  guard view_app.val is Some(tree) else { return true }
  let hit = hit_at(c.hit_ids, c.hit_rects, c.hit_clips, d.x, d.y, pressed=true)
  let hit = press_reach(c.hit_ids, c.hit_rects, c.hit_clips, hit, d.x, d.y)
  if hit < 0 || c.hit_ids[hit] != d.target { return false }
  match old_hit_owner(hit) {
    None => true
    Some(island) => match tree.target_at(d.x, d.y) {
      Hosted(host) => host == island && tree.holds(own.node.id(), host)
      _ => false
    }
  }
}

///|
fn tree_files_let_go(x : Double, y : Double, id : Int, has_paths : Bool, after_old? : Bool = false) -> Unit {
  guard tree_file_aim(x, y, fields_block=has_paths, after_old~) is Some(own) &&
    !old_field_before_file_target(own, id) && take_drop_id(id) is Some(pick) else { return }
  view_event(fn() { (own.dropped)(pick) })
}

///|
/// An old island gets its frame's first chance. If it did not take the files, an enclosing retained target may take
/// them before the default field-path paste and before an unread drop is forgotten.
fn tree_files_after_old() -> Unit {
  for (x, y, id, frame) in dropping.drops.copy() {
    if frame == g().frame_no {
      let has_paths = dropping.paths.iter().any(fn(d) { d.pick == id })
      tree_files_let_go(x, y, id, has_paths, after_old=true)
    }
  }
}

///|
/// Words let go within `within`, beside a field, go into `field` at its caret. A drop directly on another field
/// belongs to that field. `paths` may take a host's file paths instead of pasting them; false leaves them as words.
pub fn words_into_node(
  within : @view.View,
  field : @view.View,
  when? : () -> Bool = fn() { true },
  paths? : (Array[DroppedPath]) -> Bool = fn(_) { false },
) -> Unit {
  let own = { within, field, when, paths }
  tree_drop_fields[within.id()] = own
  within.owns(fn() {
    match tree_drop_fields.get(within.id()) {
      Some(now) if physical_equal(now, own) => tree_drop_fields.remove(within.id())
      _ => ()
    }
  }) |> ignore
}

///|
fn tree_drop_owner(node : @view.View) -> TreeDropField? {
  let mut at = Some(node)
  while at is Some(v) {
    match tree_drop_fields.get(v.id()) {
      Some(own) => return Some(own)
      None => at = v.parent()
    }
  }
  None
}

///|
/// The same frontmost target as a press. A bare old root has no target of its own; in its empty area, the last
/// registered region drawn there may take the drop. A modal, another field or a control outside the region may not.
fn tree_drop_aim(x : Double, y : Double) -> (TreeField, TreeDropField?, Bool)? {
  guard view_app.val is Some(tree) && !old_layer_over(x, y) else { return None }
  let target = tree.target_at(x, y)
  let id = match target {
    Pressed(id) | Dragged(id) | Hosted(id) | TopRow(id) | Off(id) => Some(id)
    Nothing => None
  }
  let owner = id.bind(fn(id) { tree.view_of(id) }).bind(tree_drop_owner)
  match id.bind(fn(id) { tree_fields.get(id) }) {
    Some(tf) => {
      let own = match owner {
        Some(o) if o.field.id() == tf.view.id() && (o.when)() => Some(o)
        _ => None
      }
      return Some((tf, own, true))
    }
    None => ()
  }
  let take = fn(own : TreeDropField) {
    if !(own.when)() || !tree.takes_presses(own.within.id()) || !tree.can_focus(own.field.id()) { return None }
    tree_fields.get(own.field.id()).map(fn(tf) { (tf, Some(own), false) })
  }
  match owner {
    Some(own) => return take(own)
    None => ()
  }
  match target {
    Nothing => ()
    Hosted(id) if !old_wheel_there(id, x, y) => ()
    _ => return None
  }
  let mut found = None
  for (d, _, _) in tree.drawn_held() {
    match tree_drop_fields.get(d.id) {
      Some(own) => {
        let b = tree.input_bounds(d.id)
        if x >= d.x && y >= d.y && x < d.x + d.w && y < d.y + d.h &&
          x >= b.0 && y >= b.1 && x < b.2 && y < b.3 {
          match take(own) { Some(aim) => found = Some(aim); None => () }
        }
      }
      None => ()
    }
  }
  found
}

///|
fn tree_drop_paste(tf : TreeField, words : String, direct : Bool, x : Double, y : Double) -> Unit {
  let c = g()
  c.focus_visible = false
  tree_field_focus(tf.view.id())
  if direct { place_caret_at(tf.st, x, y, view_moment()) }
  tf.st.text_input(text_paste, words, 0, 0, view_moment())
  tree_field_told(tf)
  tree_field_redraw()
}

///|
fn tree_words_let_go(x : Double, y : Double, words : String) -> Bool {
  guard tree_drop_aim(x, y) is Some((tf, _, direct)) else { return false }
  view_event(fn() { tree_drop_paste(tf, words, direct, x, y) })
  true
}

///|
fn tree_paths_let_go(x : Double, y : Double, paths : Array[DroppedPath]) -> Bool {
  guard tree_drop_aim(x, y) is Some((tf, owner, direct)) else { return false }
  view_event(fn() {
    if !owner.map_or(false, fn(o) { (o.paths)(paths) }) {
      tree_drop_paste(tf, paths_words(paths), direct, x, y)
    }
  })
  true
}
