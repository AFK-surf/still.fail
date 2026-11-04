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
    Pressed(id) | Dragged(id) | Hosted(id) | TopRow(id) => Some(id)
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
