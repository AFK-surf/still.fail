// The still.fail contents and surface of a panel presented as a sheet. The sheet owns its presence and gestures;
// this lays out the same grabber, title, body and foot that the old presenter placed in it.

///|
// kept across runs: lent to a sheet's foot while its nodes live
let sheet_foot_fill_node : @view.Lent[Bool] = @view.Lent::new()

///|
// kept across runs: lent by a panel to the nodes it holds
let panel_title_row_at : @view.Lent[Bool] = @view.Lent::new()

///|
/// Whether this panel body has its own title row supplied by a centred dialog. A sheet or an anchored panel gives
/// none, so its body may draw that same title in its own place.
pub fn panel_title_row_given_node(v : @view.View) -> Bool {
  v.lent(panel_title_row_at).unwrap_or(false)
}

///|
fn panel_sheet_content_node(parent : @view.View, x : PanelOf, from : Anchor, close : () -> Unit) -> Unit {
  guard x.nodes is Some(n) else { return }
  let title = fn() { match x.live { Some(live) => live().0; None => x.title } }
  let description = fn() { match x.live { Some(live) => live().2; None => x.description } }
  parent.box(fn(grab) {
    grab.height(Is(Some(sheet_grab_h))).lines_up(Is(Some(Middle))).padding(Is((0.0, 12.0, 0.0, 8.0))) |> ignore
    grab.box(fn(line) {
      line.width(Is(Some(38.0))).height(Is(Some(5.0))).radius(Is(2.5)).ground(By(fn() { theme().p.line })) |> ignore
    }) |> ignore
  }) |> ignore
  parent.show(fn() { title() != "" }, fn(head) {
    head.padding(Is((sheet_panel_sides, 4.0, sheet_panel_sides, 10.0))) |> ignore
    words_node(head, title, fn() { sheet_title_words }) |> ignore
  })
  parent.show(fn() { description() != "" }, fn(lead) {
    lead.padding(Is((sheet_panel_sides, 0.0, sheet_panel_sides, 0.0))) |> ignore
    words_node(lead, description, fn() { sheet_lead }) |> ignore
  })
  parent.box(fn(body) {
    body.shrink(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
    if x.tall > 0.0 && !n.fit { body.grow(Is(1.0)) |> ignore }
    let contents = fn(scroller : @view.View) {
      scroller.box(fn(held) {
        let sides = if x.tall > 0.0 { 0.0 } else if from != Unanchored { sheet_row_sides } else { sheet_panel_sides }
        let bottom = if x.tall > 0.0 || from == Unanchored || n.foot is None { sheet_panel_foot } else { 0.0 }
        held.padding(Is((sides, 0.0, sides, bottom))) |> ignore
        if x.tall > 0.0 && !n.fit && !n.scrolls { held.grow(Is(1.0)) |> ignore }
        held.box(fn(content) {
          if x.tall > 0.0 && !n.fit && !n.scrolls { content.grow(Is(1.0)) |> ignore }
          look_lent(content, Narrow)
          content.lends(panel_title_row_at, false) |> ignore
          panel_rows_lent(content, fn() {
            {
              sides_in: sides,
              rows_out: dmax(0.0, sides - panel_card_in),
              words_in: if x.tall > 0.0 { sheet_panel_sides } else if from != Unanchored { sheet_panel_sides - sheet_row_sides } else { 0.0 },
              small: false,
            }
          })
          content.lends(panel_width_at, fn() { content.window().0 }) |> ignore
          content.lends(panel_old_at, fn() {
            { look: Narrow, column: false, column_in: 0.0, dialog: false, whole: x.tall <= 0.0,
              clear: fn() { 0.0 }, held: fn() { false }, side: fn() { Bottom } }
          }) |> ignore
          (n.body)(content, close)
        }) |> ignore
      }) |> ignore
    }
    if n.scrolls {
      let scroll = @view.Scroll::new()
      body.scrolls(scroll, slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), contents)
      .clips(By(fn() { scroll.goes() })).bounds_input(By(fn() { scroll.goes() })) |> ignore
    } else {
      contents(body)
    }
  }) |> ignore
  match n.foot {
    Some(foot) => parent.box(fn(row) {
      row.padding(Is((20.0, 24.0, 20.0, 24.0))) |> ignore
      row.box(fn(content) {
        content.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(8.0)) |> ignore
        content.lends(sheet_foot_fill_node, !n.foot_across) |> ignore
        look_lent(content, Narrow)
        foot(content, close)
      }) |> ignore
    }) |> ignore
    None => ()
  }
}

///|
fn panel_sheet_node(
  parent : @view.View,
  open : () -> Bool,
  x : PanelOf,
  p : Presented,
  close : () -> Unit,
  cancel : () -> Unit,
  shown : () -> Unit,
  gone : () -> Unit,
) -> Unit {
  guard x.nodes is Some(n) else { return }
  @kit.sheet_node(
    parent, open, cancel, fn(surface) { panel_sheet_content_node(surface, x, p.from, close) },
    tall=x.tall,
    fit=n.fit,
    grows=x.grows,
    raised=fn() { p.recede.get() * p.pushed.get() },
    sinks=fn() { p.sinks.get() },
    dims=fn() { scrim_owner(true) == p.serial },
    covered=fn() { p.recede.get() },
    scrim=fn() { sheet_scrim },
    height=fn(h) {
      if @signals.untracked(fn() { p.sheet_h.get() }) != h {
        // A sheet below is placed by this requested height in the existing presenter stack.
        @signals.start_batch()
        p.sheet_h.set(h)
        presented_told()
        @signals.end_batch()
      }
    },
    shown~,
    gone~,
    look=panel_sheet_look_node,
    label=fn() { match x.live { Some(live) => live().0; None => x.title } },
    initial_focus=fn() { if x.focus { match n.initial_focus { Some(target) => target(); None => None } } else { None } },
    under=sheet_under,
  )
}

///|
fn panel_sheet_look_node(surface : @view.View, scrim : () -> Double) -> Unit {
  surface
  .radius(Is(pane_corner))
  .ground(By(fn() { if presented_alone.val { theme().p.bg } else { 0L } }))
  .glass(By(fn() {
    if presented_alone.val {
      None
    } else {
      let t = theme()
      Some({ ..glass_sheet(), solid: over(over(t.p.bg, alpha(0x000000FFL, 0.28 * scrim())), alpha(t.p.card, 0.8)) })
    }
  }))
  .shadow(Is((sheet_raised.sigma, sheet_raised.dy, sheet_raised.color))) |> ignore
}
