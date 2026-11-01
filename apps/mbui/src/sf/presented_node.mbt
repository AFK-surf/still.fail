// What is presented drawn as nodes of the window's tree, where a tree hosts them (presented_nodes), not on a sheet
// (小屏's, the host's still): a confirm (confirm_node) and a question (ask_node) in the middle of the window, a menu
// (menu_node) beside what opened it, each at its place in the window's stack of layers (its serial), over or under the
// old frame's presented as each was presented; the rest the host's (presented) still. Closed (cancel, Escape, back), it
// closes as the host's closes it (dismissed_now: what is over it too, what it holds let go of, once); said, it closes
// and what it says goes on, at that moment. A confirm or a question going is presented till its way out is over
// (tree_presented: the host lets it go then); a menu is let go of as it closes, as the host's menu_popover is. A menu's
// items given anew where they are kept (presented_changed) are read again by its rows, keys and choices.

///|
/// The serials of what of the presented the window's tree draws, while it is drawn (made, till it has gone).
// kept across runs: put back by presenters_reset; each let go as its node is
let tree_presented : Set[Int] = Set::new()

///|
/// Whether a window's tree draws what it can of the presented (presented_nodes made, not let go).
// kept across runs: said by presented_nodes as it is made and let go
let presented_in_tree : Ref[Bool] = Ref(false)

///|
/// Whether `p` is the window's tree's to draw: a confirm, a question or a menu not on a sheet, where a tree draws them.
fn tree_draws(p : Presented, sheet : Bool) -> Bool {
  presented_in_tree.val &&
  !sheet &&
  p.shows is (Confirm(_, _, _, _, _) | Ask(_, _, _, _, _, _, _, _) | Menu(_, _, _))
}

///|
/// What of the presented the window's tree draws, in `root` (over all of it the root holds: each at its place in the
/// window's stack of layers), made as one is presented and let go once it has gone.
pub fn presented_nodes(root : @view.View) -> Unit {
  presented_in_tree.val = true
  root.owns(fn() { presented_in_tree.val = false }) |> ignore
  root.each(
    fn() {
      presented_said.get() |> ignore
      let sheet = layout(root.window().0) is Small
      presented_now.filter(fn(p) { tree_draws(p, sheet) }).map(fn(p) { p.serial })
    },
    fn(serial) { serial },
    fn(row, item) {
      let serial = @signals.untracked(fn() { item.get() })
      guard presented_now.search_by(fn(q) { q.serial == serial }) is Some(i) else { return }
      let p = presented_now[i]
      // (the root's node it is in at its place in the window's stack of layers: its serial, as the host's presented are)
      row.over(Is(true)).stacked(Is(serial)) |> ignore
      let open = fn() {
        presented_said.get() |> ignore
        presented_open_of(serial)
      }
      // (drawn from its layer made till its way out is over: one closed before it ever showed, never)
      let shown = fn() { tree_presented.add(serial) }
      let gone = fn() {
        // (its way out over: the host lets it go, as its own once drawn no more)
        tree_presented.remove(serial)
        presented_told()
      }
      // (said: it closes, and what is over it, then what it says goes on, at that moment)
      let done = fn(f : () -> Unit) {
        p.ended = true
        close_from_serial(serial)
        f()
      }
      match p.shows {
        Confirm(title, words, action, danger, run) =>
          confirm_node(
            row,
            open,
            fn() { title },
            fn() { words },
            fn() { action },
            danger,
            fn() { dismissed_now(serial) },
            fn() { done(run) },
            shown~,
            gone~,
          )
        Ask(title, value, placeholder, action, hint, secret, empty, run) =>
          ask_node(
            row,
            "sf-present/\{serial}",
            open,
            title,
            p.line,
            value,
            placeholder,
            action,
            hint,
            secret,
            empty,
            fn() { dismissed_now(serial) },
            fn(line) { done(fn() { run(line) }) },
            shown~,
            gone~,
          )
        Menu(items, title, along) => {
          // (beside what opened it, where it was drawn as it opened; opened by the keyboard where that showed its focus:
          // menu_popover's anchor_of and offset)
          let (anchor, by_key, offset, keep_field) = @signals.untracked(fn() { menu_anchor_now(p.from) })
          // (what it holds as it is now, where it is kept: given anew there whole, then told, presented_changed; what
          // reads it, its rows, keys and choices, read it again then; what a choice does, as it is there then)
          menu_node(
            row,
            open,
            anchor,
            fn() {
              presented_said.get() |> ignore
              items
            },
            title,
            along,
            offset,
            by_key,
            keep_field,
            fn(item) { done(item.select) },
            fn() { dismissed_now(serial) },
            shown~,
            gone~,
          )
        }
        _ => ()
      }
    },
  )
}

///|
/// What a menu presented `from` goes beside, as menu_popover's anchor_of has it: what opened it where it is drawn
/// (@ui.old_anchor: the window's corner, nothing wide, where it never was, as kit's menu_anchor has it), a point,
/// or the window's middle a third down; whether the keyboard opened it (what opened it shows the focus), how far off it
/// it stands (at a point, none), and whether a finger opened it with a field focused (kit's dropdown_menu: the focus
/// left there).
fn menu_anchor_now(from : Anchor) -> ((@view.View) -> @view.View, Bool, Double, Bool) {
  let c = @ui.current()
  // (as kit's dropdown_menu: opened by the keyboard, its first item's; else by a finger with a field focused, that
  // field's still)
  let keep = @ui.pointing() is Finger && c.field_focused()
  let (ww, wh) = c.window_size()
  let middle = (ww / 2.0, wh / 3.0, 0.0, 0.0)
  match from {
    Of(id) => {
      let by_key = c.focus_shown(id)
      (fn(layer) { @ui.old_anchor(layer, id, (0.0, 0.0, 0.0, 0.0)) }, by_key, panel_offset, keep && !by_key)
    }
    At(x, y, w, h) =>
      (
        fn(layer) { fixed_anchor(layer, (x, y, w, h)) },
        false,
        if w == 0.0 && h == 0.0 { 0.0 } else { panel_offset },
        keep,
      )
    Unanchored => (fn(layer) { fixed_anchor(layer, middle) }, false, panel_offset, keep)
  }
}
