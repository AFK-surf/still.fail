// The visual part of an internal file drop on a chat. The chat itself takes the let-go and writes its draft.

///|
// kept across runs: a registration belongs to the node drawing the hint, and is removed with that node
let chat_drop_hint_layers : @sf.LiveMap[Int, () -> Bool] = @sf.LiveMap::new()

///|
// kept across runs: an old node's cleanup must not remove a later node's registration
let chat_drop_hint_serial : Ref[Int] = Ref(0)

///|
priv struct OldChatDropHint {
  owner : @view.View
  pane : Int
}

///|
// kept across runs: these belong to the current drag and are cleared when it ends
let old_chat_drop_hints : @sf.LiveMap[(@view.NodeId, Int), OldChatDropHint] = @sf.LiveMap::new()

///|
// kept across runs: one cleanup per old island, regardless of how many drags pass over it
let old_chat_hint_owners : @sf.LiveMap[@view.NodeId, Bool] = @sf.LiveMap::new()

///|
fn old_chat_drop_hint(pane : Int) -> Unit {
  guard drive_node_window.val && dragged() is Some(_) && @ui.old_building_view() is Some(owner) else { return }
  let id = owner.id()
  if !@signals.untracked(fn() { old_chat_hint_owners.contains(id) }) {
    old_chat_hint_owners[id] = true
    // The old island participates in the visible-target chain, but still lets its chat or window take the release.
    // Following that chain also updates the chip if the island moves or returns under a stationary pointer.
    @ui.takes_let_go(owner, fn(_, _) { false })
    owner.owns(fn() {
      old_chat_hint_owners.remove(id)
      old_chat_drop_hints.retain(fn(k, _) { k.0 != id })
    }) |> ignore
  }
  let key = (id, pane)
  if @signals.untracked(fn() { old_chat_drop_hints.contains(key) }) { return }
  old_chat_drop_hints[key] = { owner, pane }
}

///|
// The old pane may remain mounted when its chat loses its view. It is no longer drawing a hint in that case.
fn old_chat_drop_hint_forget(pane : Int) -> Unit {
  guard @ui.old_building_view() is Some(owner) else { return }
  old_chat_drop_hints.remove((owner.id(), pane))
}

///|
fn chat_drop_hint_covers_chip() -> Bool {
  if chat_drop_hint_layers.iter().any(fn(entry) { (entry.1)() }) { return true }
  guard !old_chat_drop_hints.is_empty() && @ui.view_tree() is Some(tree) &&
    tree.root().pointer_here_told() is Some((x, y)) else { return false }
  let within = @ui.old_drop_within(x, y)
  old_chat_drop_hints.iter().any(fn(entry) {
    let hint = entry.1
    hint.owner.alive() && @ui.let_go_here(hint.owner) && within.contains(hint.pane)
  })
}

///|
/// Whether a chat's `talk` can accept the carried item at the pointer. `when` has the same condition as its
/// takes_let_go callback. This trackable value is owned by `talk`; an eligible folder in the chat takes precedence.
pub fn chat_drop_hint_active(talk : @view.View, when : () -> Bool) -> () -> Bool {
  fn() {
    if !when() || dragged() is None || !@ui.let_go_here(talk) { return false }
    match @ui.view_tree() {
      Some(tree) => {
        for (id, target) in drive_node_targets.iter() {
          if id != talk.id() && tree.holds(talk.id(), id) && @ui.let_go_here(target.view) &&
            fdrag_takes((target.target)()) {
            return false
          }
        }
        match tree.root().pointer_here_told() {
          Some((x, y)) => for (id, island) in drive_node_old_views.iter() {
            if tree.holds(talk.id(), id) && @ui.let_go_here(island.view) &&
              drive_node_old_at(@ui.current(), x, y) is Some(_) {
              return false
            }
          }
          None => ()
        }
        true
      }
      None => false
    }
  }
}

///|
/// Draw the chat's file-drop hint in `parent` while `active` says so (chat_drop_hint_active). It takes no input and
/// is hidden from accessibility. Its parent is separate from the hit area so its owner can put the composer above it.
pub fn chat_drop_hint_node(parent : @view.View, active : () -> Bool) -> Unit {
  chat_drop_hint_serial.val += 1
  let id = chat_drop_hint_serial.val
  chat_drop_hint_layers[id] = active
  parent.owns(fn() { chat_drop_hint_layers.remove(id) }) |> ignore
  parent.show(active, fn(layer) {
    layer.over(Is(true)).presses(Is(false)).hides(Is(true)).glass(By(fn() { Some(@sf.glass_floating()) }))
    .gap(Is(16.0)).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
    layer.pick(fn() { dragged().map(fn(i) { i.dir }).unwrap_or(false) }, fn(mark, folder) {
      mark.lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
      if folder {
        @sf.icon_node(mark, "folder", drop_folder, By(fn() { @sf.theme().p.muted })).scale(Is(2.0)) |> ignore
      } else {
        @sf.file_tile_node(mark, fn() { dragged().map(fn(i) { i.name }).unwrap_or("") }).scale(Is(2.0)) |> ignore
      }
    })
    @sf.words_node(layer, fn() { @sf.t("web-main.composer.dropHere") }, fn() { drop_hint_words }) |> ignore
  })
}
