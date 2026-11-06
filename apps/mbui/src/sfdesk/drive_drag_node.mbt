// Internal file drags for folders made in the window's tree. A target is owned by its node; the window's let-go
// dispatch chooses the innermost target under the pointer and lets a chat take the same item at that input's moment.

///|
priv struct DriveNodeTarget {
  view : @view.View
  target : () -> FTarget
}

///|
priv struct DriveNodePending {
  item : Dragged
  into : DriveAt
  move : Bool
  name : String
  anywhere : Bool
}

///|
priv struct DriveOldView {
  view : @view.View
  mut ws : String
}

///|
// kept across runs: each target is removed with its view, and drag_reset clears the map
let drive_node_targets : @sf.LiveMap[@view.NodeId, DriveNodeTarget] = @sf.LiveMap::new()

///|
// kept across runs: each old island's registration is removed with its view
let drive_node_old_views : @sf.LiveMap[@view.NodeId, DriveOldView] = @sf.LiveMap::new()

///|
// kept across runs: the carried row's gesture, cleared by drag_reset
let drive_node_position : @signals.Signal[(Double, Double)?] = @signals.signal(None, same=fn(a, b) { a == b })

///|
// kept across runs: drops belong to the window, and drag_reset clears them
let drive_node_pending : @sf.LiveMap[Int, DriveNodePending] = @sf.LiveMap::new()

///|
// kept across runs: drag_reset puts it back
let drive_node_serial : Ref[Int] = Ref(0)

///|
// kept across runs: drag_reset invalidates an outstanding release
let drive_node_gesture : Ref[Int] = Ref(0)

///|
// kept across runs: held only while the signed-in window owns its drag layer
let drive_node_window : Ref[Bool] = Ref(false)

///|
fn drive_node_drag_reset() -> Unit {
  drive_node_targets.clear()
  drive_node_position.set(None)
  drive_node_pending.clear()
  drive_node_serial.val = 0
  drive_node_gesture.val += 1
  drive_node_window.val = false
}

///|
/// A target belongs to its node. Its effect follows the current destination, the carried item and the pointer;
/// let-go is delivered to the innermost eligible target by the window's tree.
fn drive_node_target(
  v : @view.View,
  src : Source,
  ws : () -> String,
  target : () -> FTarget,
) -> () -> String? {
  let item : DriveNodeTarget = { view: v, target }
  drive_node_targets[v.id()] = item
  v.owns(fn() { drive_node_targets.remove(v.id()) }) |> ignore
  @ui.takes_let_go(v, fn(_, _) {
    let t = @signals.untracked(target)
    if !fdrag_takes(t) { return false }
    match drag_taken() {
      Some(d) => {
        drive_node_position.set(None)
        drive_node_drop(src, @signals.untracked(ws), d, t, @ui.mods_held())
        true
      }
      None => false
    }
  })
  fn() {
    guard dragged() is Some(d) else { return None }
    let now = target()
    if !@ui.let_go_here(v) || !fdrag_takes(now) { return None }
    match @ui.view_tree() {
      None => None
      Some(tree) => {
        for (id, child) in drive_node_targets.iter() {
          if id != v.id() && tree.holds(v.id(), id) && @ui.let_go_here(child.view) && fdrag_takes((child.target)()) {
            return None
          }
        }
        match now.into {
          None => Some("keep")
          Some(at) => Some(fdrag_effect(d, at.station, @ui.mods_held()))
        }
      }
    }
  }
}

///|
/// The folder page's target asks only whether it is lit.
fn drive_drop_target_node(
  v : @view.View,
  src : Source,
  ws : () -> String,
  target : () -> FTarget,
) -> () -> Bool {
  let effect = drive_node_target(v, src, ws, target)
  fn() { effect() is Some(_) }
}

///|
/// An internal-only sidebar target. `into` is None for 个人收藏 (folders only); otherwise it is the destination.
/// The returned effect is None when the target is not the active one, else "keep", "move" or "copy". All of the
/// destination's properties may change while the node lives; destroying the node removes the target. A heading or
/// empty hint may register without taking presses of its own.
pub fn drive_side_target_node(
  v : @view.View,
  src : Source,
  ws : () -> String,
  into : () -> DriveAt?,
  name : () -> String,
  write : () -> Bool,
  transfers : () -> Bool,
) -> () -> String? {
  drive_node_target(v, src, ws, fn() {
    { id: 0, key: "", into: into(), name: name(), write: write(), transfers: transfers(), depth: 0, outside: false }
  })
}

///|
/// A row's drag words, at their input's moment. Up keeps the item until the window gives it to the target or chat;
/// Off cancels it. A finger moves the list rather than carrying a file.
fn drive_node_drag(src : Source, at : DriveAt, e : DvEntry, d : @view.Drag) -> Unit {
  match d.kind {
    Down | Moved => {
      if fdrag.item.get() is None {
        drive_node_gesture.val += 1
        let root = at.root.unwrap_or("")
        let path = dv_join(at.path, e.name)
        fdrag.item.set(Some({ station: at.station, station_name: station_name(src, at.station), root, path,
          abs: dv_absolute(root, path), name: e.name, size: e.size, dir: e.dir }))
      }
      drive_node_position.set(Some((d.wx, d.wy)))
    }
    Up => {
      drive_node_position.set(Some((d.wx, d.wy)))
      // The let-go dispatch runs in this same input after the row's gesture. Clear an unclaimed item immediately
      // after that dispatch, including a release over blank space where no node takes a press.
      let generation = drive_node_gesture.val
      match @ui.view_tree() {
        Some(tree) => tree.root().at_moment(d.at, fn() {
          if drive_node_gesture.val == generation && drive_node_position.get() is Some(_) {
            drag_taken() |> ignore
            drive_node_position.set(None)
          }
        }) |> ignore
        None => { drag_taken() |> ignore; drive_node_position.set(None) }
      }
    }
    Off => { drag_taken() |> ignore; drive_node_position.set(None) }
  }
}

///|
/// Do a drop now or follow the destination folder until its names are known. A waiting drop belongs to the window,
/// rather than to a row that may leave the virtual list while the read is under way.
fn drive_node_drop(src : Source, ws : String, item : Dragged, target : FTarget, mods : Int) -> Unit {
  match target.into {
    None => favorite_add(src, ws, { station: item.station, root: item.abs, path: "", name: item.name })
    Some(into) => {
      let move = fdrag_effect(item, into.station, mods) == "move"
      let anywhere = dv_stations(src, ws).0.unwrap_or([]).iter().any(fn(s) { s.station == into.station && s.anywhere })
      if !fdrag_transfer(@ui.current(), src, item, into, move, target.name, anywhere) {
        drive_node_serial.val += 1
        drive_node_pending[drive_node_serial.val] = { item, into, move, name: target.name, anywhere }
      }
    }
  }
}

///|
/// Choose an old target only among the actual hit and its holders in the visible old island.
fn drive_node_old_at(c : @ui.Ctx, x : Double, y : Double) -> FTarget? {
  ignore(c)
  let within = @ui.old_drop_within(x, y)
  let mut best : FTarget? = None
  for t in fdrag.drawn {
    if within.contains(t.id) && fdrag_takes(t) {
      match best {
        Some(b) if b.depth > t.depth => ()
        _ => best = Some(t)
      }
    }
  }
  best
}

///|
fn drive_node_over_old(x : Double, y : Double) -> Bool {
  !@ui.old_drop_within(x, y).is_empty()
}

///|
/// An old island with file targets participates at its own place in the same let-go chain as new nodes. This matters
/// where a chat owns the island: its old folder must take the item before the chat's draft can take it.
fn drive_node_watch_old(src : Source, ws : String) -> Unit {
  guard drive_node_window.val && @ui.old_building_view() is Some(v) else { return }
  match drive_node_old_views.get(v.id()) {
    Some(old) => { old.ws = ws; return }
    None => ()
  }
  let old : DriveOldView = { view: v, ws }
  drive_node_old_views[v.id()] = old
  v.owns(fn() { drive_node_old_views.remove(v.id()) }) |> ignore
  @ui.takes_let_go(v, fn(x, y) {
    guard dragged() is Some(item) && drive_node_old_at(@ui.current(), x, y) is Some(target) else { return false }
    drag_taken() |> ignore
    drive_node_position.set(None)
    drive_node_drop(src, old.ws, item, target, @ui.mods_held())
    true
  })
}

///|
/// Owned by the signed-in window: an item released over an old sidebar target still goes there, an item released over
/// no target is cleared, and the drag's chip follows the pointer. A chat or a folder takes it before this fallback.
pub fn drive_drag_window_node(window : @view.View, src : Source, ws : () -> String) -> Unit {
  drive_node_window.val = true
  window.owns(fn() {
    drive_node_window.val = false
    drive_node_gesture.val += 1
    drive_node_position.set(None)
    drive_node_pending.clear()
    drag_taken() |> ignore
  }) |> ignore
  @ui.takes_let_go(window, fn(x, y) {
    guard dragged() is Some(item) else { return false }
    let target = drive_node_old_at(@ui.current(), x, y)
    drag_taken() |> ignore
    drive_node_position.set(None)
    match target {
      Some(t) => drive_node_drop(src, @signals.untracked(ws), item, t, @ui.mods_held())
      None => if app.nav.top() is NewChat && drive_node_over_old(x, y) {
        // A new-chat composer can still be an old view. Its existing tab_take_drop checks the pane's own rectangle
        // and takes this once; a new-tree chat has already taken the item before this window fallback.
        ftab.let_go = Some((item, x, y, @ui.current().frame_number()))
        tab_let_go_told.set(@signals.untracked(fn() { tab_let_go_told.get() }) + 1)
      }
    }
    true
  })
  // A cancelled press (including a window losing focus) has no let-go target. A normal release is dispatched before
  // reactions to that input run, so only an item still unclaimed at the end of the event is cancelled here.
  window.reacts(fn() { (@ui.pointer_pressed(), dragged() is Some(_)) }, fn(state) {
    if !state.0 && state.1 {
      drag_taken() |> ignore
      drive_node_position.set(None)
    }
  })
  window.reacts(fn() {
    let ready : Array[Int] = []
    for (id, pending) in drive_node_pending.iter() {
      let at = pending.into
      let (value, error) = drive_folder(src, at.station, at.root.unwrap_or(""), at.path)
      if value is Some(_) || error is Some(_) { ready.push(id) }
    }
    ready.sort()
    ready
  }, fn(ready) {
    for id in ready {
      match @signals.untracked(fn() { drive_node_pending.get(id) }) {
        Some(p) => {
          drive_node_pending.remove(id)
          fdrag_transfer(@ui.current(), src, p.item, p.into, p.move, p.name, p.anywhere) |> ignore
        }
        None => ()
      }
    }
  })
  // The old shell opens this same presenter during the transition. It is safe to ask here too: the presenter is
  // opened once and the window owns it even when the folder page is no longer on screen.
  window.reacts(fn() { clash_told.get() }, fn(_) { clash_dialog(@ui.current()) })
  window.show(fn() { window.pointer_here_told() is Some(_) && dragged() is Some(_) }, fn(layer) {
    layer.over(Is(true)).presses(Is(false)).hides(Is(true)).lines_up(Is(Some(Start))).offset(By(fn() {
      let (x, y) = window.pointer_here_told().unwrap_or((0.0, 0.0))
      (x + fdrag_ghost_off, y + fdrag_ghost_off)
    })) |> ignore
    layer.box(fn(chip) {
      @sf.style_node(chip, fn() { fdrag_ghost_chip })
      chip.alpha(Is(0.9)).shadow(By(fn() { (16.0, 12.0, @sf.theme().p.shadow) })) |> ignore
      @sf.icon_node(chip, "folder", drag_icon, By(fn() { @sf.theme().p.muted }), name_now=fn() {
        match dragged() { Some(i) => dv_kind_icon(if i.dir { "folder" } else { dv_kind_of(i.name) }); None => "folder" }
      }) |> ignore
      @sf.words_node(chip, fn() { dragged().map(fn(i) { i.name }).unwrap_or("") }, fn() { drag_chip_words }) |> ignore
    }) |> ignore
  })
}
