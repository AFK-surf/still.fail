// What is presented drawn as nodes of the window's tree, where a tree hosts them (presented_nodes): a confirm in the
// middle of the window (How AsDialog: not a sheet) as confirm_node, at its place in the window's stack of layers (its
// serial), over or under the old frame's presented as each was presented; the rest the host's (presented) still.
// Closed (cancel, Escape, back), it closes as the host's closes it (dismissed_now: what is over it too, what it holds
// let go of, once); said, it closes and what it says goes on, at that moment; going, it is presented till its way out
// is over (tree_presented: the host lets it go then).

///|
/// The serials of what of the presented the window's tree draws, while it is drawn (made, till it has gone).
// kept across runs: put back by presenters_reset; each let go as its node is
let tree_presented : Set[Int] = Set::new()

///|
/// Whether a window's tree draws what it can of the presented (presented_nodes made, not let go).
// kept across runs: said by presented_nodes as it is made and let go
let presented_in_tree : Ref[Bool] = Ref(false)

///|
/// Whether `p` is the window's tree's to draw: a confirm or a question not on a sheet, where a tree draws them.
fn tree_draws(p : Presented, sheet : Bool) -> Bool {
  presented_in_tree.val && !sheet && p.shows is (Confirm(_, _, _, _, _) | Ask(_, _, _, _, _, _, _, _))
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
        _ => ()
      }
    },
  )
}
