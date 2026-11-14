// What is presented drawn as nodes of the window's tree, where a tree hosts them (presented_nodes), not on a sheet
// (小屏's, the host's still): a confirm (confirm_node) and a question (ask_node) in the middle of the window, a menu
// (menu_node) and a pick (short, as a menu of its choices; long, pick_node) beside what opened it, each at its place in the window's stack of layers (its serial), over or under the
// old frame's presented as each was presented; the rest the host's (presented) still. Closed (cancel, Escape, back), it
// closes as the host's closes it (dismissed_now: what is over it too, what it holds let go of, once); said, it closes
// and what it says goes on, at that moment. A confirm or a question going is presented till its way out is over
// (tree_presented: the host lets it go then); a menu is let go of as it closes, as the host's menus were. A menu's
// items given anew where they are kept (presented_changed) are read again by its rows, keys and choices.

///|
/// The serials of what of the presented the window's tree draws, while it is drawn (made, till it has gone).
// kept across runs: put back by presenters_reset; each let go as its node is
let tree_presented : Set[Int] = Set([])

///|
/// Whether the row of each serial draws it as a sheet (sheet_node): what a page is put on (panel_page) only where it
/// is.
// kept across runs: put back by presenters_reset
let tree_as_sheet : Map[Int, Bool] = Map([])

///|
/// Whether `p` is drawn as a sheet of the window's tree on screen `sheet` (小屏's): sheet_node, as presented_nodes picks.
fn tree_sheet_of(p : Presented, sheet : Bool) -> Bool {
  sheet && (p.shows is Panel(x) && (x.nodes is Some(_) || (sheet_panel_of(x) && !over_host_sheet(p))))
}

///|
/// Whether `p` is the window's tree's to draw (presented_nodes): a stage and a panel whose body is nodes (panel_nodes)
/// on every screen, and a confirm, a question, a menu, a pick or a small panel not on a sheet. The rest (a sheet, a
/// panel that goes in steps or as wide as what it holds) the host's (presented) still.
fn tree_draws(p : Presented, sheet : Bool) -> Bool {
  (
    // (a stage on every screen the same, never a sheet: stage_node)
    (p.shows is Panel(x) && x.stage) ||
    // (what it holds nodes: the tree's alone, the host's frame having none of it to draw)
    (p.shows is Panel(x) && x.nodes is Some(_)) ||
    // (a panel on 小屏 that is no stage and goes in no steps of its own, whatever it holds: a sheet of the tree's, its old
    // body an old view in it, sheet_node)
    (sheet && p.shows is Panel(x) && sheet_panel_of(x) && !over_host_sheet(p)) ||
    (
      !sheet &&
      (
        p.shows is (Confirm(_, _, _, _, _, _) | Ask(_, _, _, _, _, _, _, _) | Menu(_, _, _)) ||
        p.shows is Pick(_, _, _, _, _, _) ||
        (p.shows is Panel(x) && (panel_popover_of(x, p.from) || panel_centred_of(x, p.from)))
      )
    )
  )
}

///|
/// Whether `p` is presented over a sheet the host draws (one that goes in steps, a menu, a pick, a question) still
/// open: an old panel over it is the host's too, a sheet over that one in the old frame's stack, never a layer of the
/// tree's over the old frame, which its old view's words and what a screen reader is told of it would be under (the
/// host's sheet's overlay is modal: what else of the old frame there is, its views in the tree's nodes among it, is
/// inert to it).
fn over_host_sheet(p : Presented) -> Bool {
  presented_now.iter().any(fn(q) { q.serial < p.serial && q.open && !q.closed_now && !tree_draws(q, true) })
}

///|
/// Whether panel `x` presented `from` is a small panel beside what opened it the window's tree draws (panel_node): not
/// a stage, a form or one opened by nothing (a dialog in the middle of the window), nor (yet) one as wide as what it
/// holds and a share of the window tall. One whose title is as it is now (`live`) heads itself with that title as it
/// is (panel_node). One that goes in steps (`steps`) is the tree's too, its first step: its steps are its sheet's (the
/// model's panel: all of its models a step in on 小屏, columns side by side beside what opened it), and a step told
/// (panel_go) beside what opened it is not drawn yet.
fn panel_popover_of(x : PanelOf, from : Anchor) -> Bool {
  !x.stage && !x.form && from != Unanchored && !(x.fits && x.tall > 0.0)
}

///|
/// Whether panel `x` presented `from` is a dialog in the middle of the window the window's tree draws
/// (panel_centred_node): one opened by nothing (its title, step and what it says as they are now where `live`), or a
/// form whatever opened it (as the host draws it: how_of; not yet one `live`); not a stage, nor (yet) one that goes in
/// steps a share of the window tall or a form.
fn panel_centred_of(x : PanelOf, from : Anchor) -> Bool {
  !x.stage &&
  (
    if x.form {
      !x.steps && x.live is None
    } else {
      from == Unanchored && (!x.steps || x.tall <= 0.0)
    }
  )
}

///|
/// Whether a pick of `choices` is a menu of them (short, or with no search), not a panel with a search.
fn pick_menu_of(choices : Array[Choice], search : Bool) -> Bool {
  choices.length() < pick_search_from || !search
}

///|
/// What of the presented the window's tree draws, in `root` (over all of it the root holds: each at its place in the
/// window's stack of layers), made as one is presented and let go once it has gone; and under them the reader's
/// layout's panel while one is open (reader_layout_nodes).
#callsite(autofill(loc))
pub fn presented_nodes(root : @view.View, loc~ : SourceLoc) -> Unit {
  // (the tips of what they hold: one layer of them for the window, over all of it, each presented one's lent it;
  // made after them, its keys (Escape shutting a tip) asked before theirs)
  let tips_at : Ref[@view.View?] = Ref(None)
  let tips = TipLayer::new(fn() { tips_at.val })
  // (the reader's layout's panel, laid over it: under what is presented, which stands in the window's stack of layers)
  reader_layout_nodes(root)
  root.each(
    fn() {
      presented_said.get() |> ignore
      let (w, _) = root.window()
      let sheet = layout(w) is Small
      // (a panel drawn by what screen it is on, none before the window has its size: what it is drawn as, a sheet or
      // not, is picked as it is made)
      presented_now
      .filter(fn(p) { tree_draws(p, sheet) && (w > 0.0 || !(p.shows is Panel(x) && !x.stage)) })
      .map(fn(p) { p.serial })
    },
    fn(serial) { serial },
    fn(row, item) {
      let serial = item.untracked()
      guard presented_now.search_by(fn(q) { q.serial == serial }) is Some(i) else { return }
      let p = presented_now[i]
      // (a sheet from the window's foot, on 小屏 as it is made: sheet_node)
      let as_sheet = tree_sheet_of(p, @signals.untracked(fn() { layout(root.window().0) is Small }))
      tree_as_sheet[serial] = as_sheet
      // (the root's node it is in at its place in the window's stack of layers: its serial, as the host's presented are)
      row.over(Is(true)).stacked(Is(serial)) |> ignore
      // (what opened it, for every kind it is drawn as: the focus given back to that as it goes, where it still takes
      // it, not to what had the focus as it opened: View::opened_by)
      match p.from {
        Node(v) => row.opened_by(@view.ByNode(v.id())) |> ignore
        Of(id) => row.opened_by(@view.ByOld(id)) |> ignore
        At(_, _, _, _) | Unanchored => ()
      }
      // (the tips of what its body and its foot are made of: the window's layer of them, panel_tips_lent)
      row.lends(panel_tips_lent, tips) |> ignore
      // (which of its submenu rows has its menu open, one at a time, its own: panel_submenus_lent)
      panel_submenus_lend(row)
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
      // (dimming what is under it only where nothing presented under it does: one scrim however many are over one
      // another, scrim_owner)
      let dims = fn() { scrim_owner(false) == serial }
      // (another dialog over it: dimmed over itself)
      let covered = fn() { dialog_covered(serial) }
      // (said: it closes, and what is over it, then what it says goes on, at that moment)
      let done = fn(f : () -> Unit) {
        // (its field let go of first, none giving it back: before its layer goes and gives back the focus, and before
        // what it says goes on)
        field_let_go(p)
        p.ended = true
        p.chosen = true
        close_from_serial(serial)
        f()
      }
      match p.shows {
        Confirm(title, words, warning, action, danger, run) =>
          confirm_node(
            row,
            open,
            fn() { title },
            fn() { words },
            fn() { action },
            danger,
            fn() { dismissed_now(serial) },
            fn() { done(run) },
            warning~,
            shown~,
            gone~,
            dims~,
            covered~,
          )
        Ask(title, value, placeholder, action, hint, secret, empty, run) =>
          ask_node(
            row,
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
            dims~,
            covered~,
          )
        Menu(items, title, along) => {
          // (beside what opened it, where it was drawn as it opened; opened by the keyboard where that showed its focus:
          // menu_anchor_now)
          let (anchor, by_key, offset, keep_field) = @signals.untracked(fn() { menu_anchor_now(p.from) })
          // (what it holds as it is now, where it is kept: given anew there whole, then told, presented_changed; what
          // reads it, its rows, keys and choices, read it again then; what a choice does, as it is there then)
          menu_node(
            row,
            open,
            anchor,
            fn() { presented_items_of(serial, items) },
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
        // (on 小屏, what it holds nodes or not (no stage, no steps of its own): a sheet from the window's foot, as the
        // host's are there)
        Panel(x) if as_sheet =>
          sheet_node(
            row,
            "sf-present/\{serial}",
            open,
            // (its own, then those a step further in from it: panel_page)
            fn() {
              let close = fn() { done(fn() {  }) }
              let all : Array[SheetPage] = [{ n: 0, x, nodes: x.nodes, close, from: p.from, lists: serial }]
              for more in p.more.get() {
                // (what its old body's lists say kept apart from every presented's own: measured_body's)
                all.push({ n: more.n, x: more.x, nodes: more.x.nodes, close, from: more.from, lists: -(serial * 1000 + more.n) })
              }
              all
            },
            fn() { dismissed_now(serial) },
            shown~,
            gone~,
            covered_by=fn() { sheet_over(serial) },
            in_place?=p.in_place,
            // (a step further in from another presenter's panel: back from it back to that one)
            step_back?=if p.under is Some(_) { Some(fn() { dismissed_now(serial, back=true) }) } else { None },
            // (a page back, where it is past its first)
            page_back=fn() { panel_pop(p) },
            stood=fn() { p.stands },
            // (how tall it stands as it closes, for what comes in its place: close_from)
            stands_by=fn(f) { p.stands_now = Some(f) },
            taken=fn() {
              presented_said.get() |> ignore
              p.taken_by != 0
            },
            // (dimming what is under it only where no sheet under it does, the host's sheets among them: scrim_owner)
            dims=fn() { scrim_owner(true) == serial },
          )
        Panel(x) if x.stage =>
          stage_node(
            row,
            "sf-present/\{serial}",
            open,
            x,
            fn() { done(fn() {  }) },
            fn() { dismissed_now(serial) },
            p,
            shown~,
            gone~,
            covered~,
          )
        Panel(x) if p.from == Unanchored || x.form =>
          panel_centred_node(
            row,
            "sf-present/\{serial}",
            open,
            x,
            fn() { done(fn() {  }) },
            fn() { dismissed_now(serial) },
            p,
            shown~,
            gone~,
            dims~,
            covered~,
          )
        Panel(x) => {
          // (beside what opened it, where it is drawn: as a menu's)
          let (anchor, _, _, _) = @signals.untracked(fn() { menu_anchor_now(p.from) })
          panel_node(
            row,
            "sf-present/\{serial}",
            open,
            anchor,
            x,
            fn() { done(fn() {  }) },
            fn() { dismissed_now(serial) },
            p,
            shown~,
            gone~,
          )
        }
        Pick(title, choices, chosen, choose, along, search) if !pick_menu_of(choices, search) => {
          // (a panel with its search over its list: pick_node)
          // (panel_offset off what opened it, a point too: @kit.popover's, as a long pick gives no other)
          let (anchor, _, _, _) = @signals.untracked(fn() { menu_anchor_now(p.from) })
          let offset = panel_offset
          pick_node(
            row,
            open,
            anchor,
            title,
            choices,
            chosen,
            p.line,
            along,
            offset,
            fn(k) { done(fn() { choose(k) }) },
            fn() { dismissed_now(serial) },
            shown~,
            gone~,
          )
        }
        Pick(title, choices, chosen, choose, along, _) => {
          // (a menu of its choices, a short pick's: the one chosen checked where one is, else each its icon;
          // what each is under its words, its value at its row's end, its own mark after its check)
          let (anchor, by_key, offset, keep_field) = @signals.untracked(fn() { menu_anchor_now(p.from) })
          let one_chosen = choices.iter().any(fn(x) { x.key == chosen })
          let items : Array[MenuItem?] = choices.map(fn(x) {
            Some({
              label: x.label,
              icon: if one_chosen { "" } else { x.icon },
              danger: false,
              disabled: false,
              chosen: if one_chosen { Some(x.key == chosen) } else { None },
              heading: false,
              select: fn() { choose(x.key) },
            })
          })
          menu_node(
            row,
            open,
            anchor,
            fn() { items },
            title,
            along,
            offset,
            by_key,
            keep_field,
            fn(item) { done(item.select) },
            fn() { dismissed_now(serial) },
            shown~,
            gone~,
            extras=fn(i) {
              match choices.get(i) {
                Some(x) => { note: x.note, value: x.value, mark: x.mark }
                None => menu_no_extra
              }
            },
            min_w=chooser_menu_w,
          )
        }
      }
    },
  )
  tips_at.val = Some(root.box(made_for=loc, fn(l) { l.over(Is(true)).over_all(Is(true)) |> ignore }))
}

///|
/// What a menu presented `from` goes beside, as the host's menus had it: what opened it where it is drawn
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
    // (a node of the window's tree: beside it where it is drawn)
    Node(v) => {
      let by_key = v.focus_shown()
      (fn(_) { v }, by_key, panel_offset, keep && !by_key)
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

///|
/// A window's tree of `page` (an old view, the whole window) with what of the presented the tree draws over it
/// (presented_nodes), in still.fail's theme: as the app's tree has them (sfapp's app_tree), for a page shown without
/// the app's shell. The Tester's or a host's `tree`, its old frame `@ui.old_views_here`.
pub fn presented_tree(page : (@ui.Ctx) -> Unit) -> (@view.View) -> Unit {
  fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    @ui.old(root, page).grow(Is(1.0)) |> ignore
    presented_nodes(root)
  }
}

///|
/// How far in from the column a panel's body is given node `v`'s words go (panel_words_in's, where the body is nodes:
/// panel_nodes); none outside a panel.
pub fn panel_words_in_node(v : @view.View) -> @ui.Style {
  @ui.style(px=room(panel_words_at_node(v)))
}

///|
/// How far in from the column a field over a panel's rows stands in node `v` of its body: in a small panel beside what
/// opened it at the column, its capsule on the rows' grounds' line as a pick's search is (pick_node's); in a sheet or a
/// dialog on its words' line, as a sheet's own field is (the things' 筛选); none outside a panel.
pub fn panel_field_in_node(v : @view.View) -> @ui.Style {
  let words = match v.lent(panel_in_lent) {
    Some(p) if !p.small => p.words
    _ => 0.0
  }
  @ui.style(px=room(words))
}

///|
/// The same, in points (panel_words_in_node's).
pub fn panel_words_at_node(v : @view.View) -> Double {
  match v.lent(panel_in_lent) {
    Some(p) => p.words
    None => 0.0
  }
}

///|
/// Node `v` of a panel's body clear of an untitled dialog's close button at its end (untitled_clear's, where the body is
/// nodes); none elsewhere.
pub fn untitled_clear_node(v : @view.View) -> @ui.Style {
  @ui.style(pr=room(panel_clear_at_node(v)))
}

///|
/// How far clear of an untitled dialog's close button node `v` of a panel's body is (untitled_clear_node's), in points.
fn panel_clear_at_node(v : @view.View) -> Double {
  match v.lent(panel_in_lent) {
    Some(p) => p.clear
    None => 0.0
  }
}

///|
/// Whether what a node is in is a sheet's foot whose buttons go across it, each its share (foot_fills, as nodes): lent by
/// sheet_node to its foot's row; read by button_node and foot_spacer_node.
// kept across runs: what each sheet lends its foot, let go with it
let foot_fills_lent : @view.Lent[Bool] = @view.Lent::new()

///|
/// What stands between a foot's buttons at its start and those at its end (Ctx::spacer's, as a node) in `parent`: the
/// room left between them; at a sheet's foot, a share of it as each button's (foot_fills: the old spacer's Fill there).
#callsite(autofill(loc))
pub fn foot_spacer_node(parent : @view.View, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(s) { s.grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore }) |> ignore
}

///|
/// The room what is put over the window has (a dialog in its middle, a panel or a menu beside what opened it): the
/// window, less what the system's bars reach in over it at each edge (View::clear: an iPhone Duo's bars of the app's
/// actions over its top and its tabs at its foot or down its side, a status bar, the home indicator), followed.
pub fn over_room(v : @view.View) -> (Double, Double) {
  let (w, h) = v.window()
  let (top, right, foot, left) = v.clear()
  (dmax(0.0, w - left - right), dmax(0.0, h - top - foot))
}
