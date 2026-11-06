// The visual part of an internal file drop on a chat. The chat itself takes the let-go and writes its draft.

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
