// A panel's row opening the next menu beside it (submenu_row's) as nodes of the window's tree: a menu's row with a
// chevron toward where it opens. On 小屏 pressed, the presenters' menu of its items (a sheet, titled by its words); on
// 中屏 and 大屏 pressed, or the mouse's pointer come onto it, or the arrow key toward that side with the focus on it, its
// menu beside it at once (menu_node, not modal: what is under it its own as ever), at its side (Right, else Left),
// lined up with its top, as far off it as two of a panel's padding (the two panels' edges that far apart); the pointer
// leaving it leaves the menu open. One of a panel's at a time (panel_submenus_lent): another's opened, this one's
// closed. Closed by a choice (closed, then what it does), Escape, the arrow key back, a press outside it (which goes on
// to what it lands on), and as the row goes.

///|
/// Which of a presented panel's submenu rows has its menu open (one at a time): lent by presented_nodes to each of what
/// it presents, let go with it.
// kept across runs: what each presented one is lent, let go with it
let panel_submenus_lent : @view.Lent[@signals.Signal[@view.View?]] = @view.Lent::new()

///|
/// Where the menus of the submenu rows a panel holds are made: the panel's own layer (modal, over the window: the
/// keyboard's focus may go into what is made in it, and nothing the panel cuts cuts them), lent by its presenter
/// (dialog_layer_node, panel_node).
// kept across runs: what each panel's layer is lent, let go with it
let submenu_layer_lent : @view.Lent[@view.View] = @view.Lent::new()

///|
/// What presented_nodes lends `row`, the node one presented is made in: its submenu rows' one open, none at first.
fn panel_submenus_lend(row : @view.View) -> Unit {
  row.lends(panel_submenus_lent, @signals.signal(None, same=same_view)) |> ignore
}

///|
/// What a panel's presenter lends its layer: itself, where its submenu rows' menus are made.
fn submenu_layer_lend(layer : @view.View) -> Unit {
  layer.lends(submenu_layer_lent, layer) |> ignore
}

///|
/// The same node, or both none.
fn same_view(a : @view.View?, b : @view.View?) -> Bool {
  match (a, b) {
    (Some(x), Some(y)) => x.id() == y.id()
    (None, None) => true
    _ => false
  }
}

///|
/// A row opening the next menu beside it in `parent` (submenu_row's): `label`, `icon` before it where it has one, a
/// chevron toward `side` at its end; `items` the menu's, as they are as it opens. Laid out as a panel's row where it
/// stands (panel_row_by, a menu's row: a small panel's, a sheet's, at a dialog's foot). Outside a presented panel its
/// menu is its own alone, made in `parent`'s layer.
#callsite(autofill(loc))
pub fn submenu_row_node(
  parent : @view.View,
  label : () -> String,
  items : () -> Array[MenuItem?],
  icon? : () -> String = fn() { "" },
  side? : @ui.Side = Right,
  loc~ : SourceLoc,
) -> Unit {
  let open_row = match parent.lent(panel_submenus_lent) {
    Some(o) => o
    None => @signals.signal(None, same=same_view)
  }
  let layer = parent.lent(submenu_layer_lent).unwrap_or(parent)
  // (opened by the keyboard: its first item's the focus as it opens)
  let by_key = Ref(false)
  let small = fn() { layout(parent.window().0) is Small }
  let open = fn(r : @view.View, key : Bool) {
    if small() {
      present(Menu(items(), label(), Start), Node(r))
      return
    }
    by_key.val = key
    open_row.set(Some(r))
  }
  // (closed, where it is this one's open: another's opened at that moment stays)
  let close = fn(r : @view.View) {
    if same_view(open_row.untracked(), Some(r)) {
      open_row.set(None)
    }
  }
  let toward = if side == Left { @ui.key_code_left } else { @ui.key_code_right }
  panel_row_by(
    loc~,
    parent,
    label,
    fn(r) { open(r, r.focus_shown()) },
    icon,
    fn() { "" },
    if side == Left { "chevron-left" } else { "chevron-right" },
    false,
    plain=true,
    made=fn(r) {
      // (the mouse's pointer come onto it: open at that moment, as long as nothing has it since)
      r.reacts(fn() { hovered_node(r) }, at_start=false, fn(on) {
        if on && !small() {
          open(r, false)
        }
      })
      // (asked of every node that takes keys, the topmost first: its own while it has the focus)
      r.on_key(fn(k) {
        if k.mods == 0 && k.code == toward && r.focused() && !small() {
          open(r, true)
          true
        } else {
          false
        }
      })
      |> ignore
      // (closed as it starts leaving (its menu out of sight from then: lives_with), and as it is let go)
      r.on_leaving(fn() { close(r) }) |> ignore
      r.owns(fn() { close(r) }) |> ignore
      // (its menu made as it opens, as it was opened then: by the keyboard or not; let go at once as it closes; made in
      // the panel's layer, in what lives as long as its row does (View::lives_with: its scope the row's, as a tip's in
      // its layer): out of sight as its row starts leaving, back as that comes back, gone with it)
      let holder = layer.box(fn(h) { h.over(Is(true)) |> ignore }).lives_with(r)
      holder.show(fn() { same_view(open_row.get(), Some(r)) }, at_once=true, fn(m) {
        // (the focus given back to its row as it goes: what opened it, kit's submenu's return_focus)
        m.over(Is(true)).opened_by(@view.ByNode(r.id())) |> ignore
        let items_now = items()
        menu_node(
          m,
          fn() { true },
          fn(_) { r },
          fn() { items_now },
          "",
          Start,
          panel_pad + panel_pad,
          by_key.val,
          false,
          fn(item) {
            close(r)
            (item.select)()
          },
          fn() { close(r) },
          side~,
          modal=false,
        )
      })
    },
  )
}
