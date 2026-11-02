// The page's panel on the tape (Medium) held by the window's tree: its ground, its corners the tape's and the line round
// it the tree's, a step darker while it is behind the one in use (tape_behind); in it the stack (@ui.nav_flat_view), each
// page a node of its own built the old way in it (its island), a phone's screen: what is opened from it pushed over it,
// slid in and taken off by back as a phone's are, down to the page chosen to be shown in it, as the frame drew it before.

///|
/// How far behind the one in use the page's panel is drawn by what reads it in node `n` (tape_behind's): its ground a
/// step darker that far, the page's own where it is in use.
fn tape_page_ground(n : @view.View) -> Int64 {
  let k = tape_behind_at(Page, tape_drawn_at(n))
  if k <= 0.0 {
    @sf.theme().p.bg
  } else {
    @sf.behind_ground(k~)
  }
}

///|
/// The page's panel (in node `v`, as tape_panel_box gives it room): what it says each frame its pages are built, before
/// them (tape_page_said); its ground, corners and line, cutting what is in it to them; the stack in it, as wide as beside
/// the system's column (`under` its ground alone).
fn tape_page_pane(v : @view.View, src : Source) -> Unit {
  // (its tips over all of the window, as the old frame's are: none cut by the panel)
  let tips = @sf.TipLayer::new(fn() { tape_goes.node })
  // (what is drawn in it cut to its room, as the island it was drawn by before was: the panel's ground and line too)
  v.clips(Is(true)) |> ignore
  // (drawing nothing, under all of it: taking no press, what the page's bar does not take nothing's, not its)
  @ui.old(v, fn(c) { tape_page_said(c, src) }, key=tape_island_key).over(Is(true)).presses(Is(false)) |> ignore
  v.box(fn(panel) {
    panel
    .grow(Is(1.0))
    .clips(Is(true))
    .ground(By(fn() { tape_page_ground(panel) }))
    .edge(By(fn() { (1.0, @sf.theme().p.line) }))
    .padding(By(fn() { (0.0, 0.0, if tape_shown_side() is None { tape_room_now().under } else { 0.0 }, 0.0) }))
    |> ignore
    // (its corners the tape's, those at the window's edge following the window's: linked each, as @sf.corners_radius)
    @ui.tree_corners_linked(panel, fn() { Some(tape_pane_corners(Page, tape_shown_side() is Some(_))) })
    @ui.nav_flat_view(
      panel,
      app.nav,
      fn(c, p) { tape_page_one(c, src, p) },
      fn(p) { (tape_goes.ready)(p) },
      tape_goes.most,
      bg=fn() { tape_page_ground(panel) },
      // (a page's bar on the tape the tree's, over its own view: what the page says of it, collected as it is built)
      head=fn(b, k) { tape_bar_head(b, k, tips) },
      // (what its bar said kept till its entry leaves the stack: shown again (beside the one over it as that goes back),
      // its bar there with it before its page is built again)
      gone=fn(k) { tape_bars.remove(k) },
      // (back its while the page is in use: the side panel's, the sidebar's first)
      takes_back=fn() { wide.tape_at.get() == Page },
      page_key=fn(_) { tape_island_key() },
    )
    |> ignore
  })
  |> ignore
}

///|
/// What the page's panel says each frame its pages are built (its island, before them, drawing nothing): the page on
/// top switched (page_switch_frame); a passage of a message picked while the page is not in use brings it over.
fn tape_page_said(c : @ui.Ctx, src : Source) -> Unit {
  let (now, _, _, _) = @sfbase.workspace_in_view(src)
  guard now is Some(_) else { return }
  // a chat and a new chat switched between: the composer moving, the rest crossfading (switch.mbt), as the page on top
  // changes, before any page of it is built
  page_switch_frame(c)
  // a passage of a message picked while the page is not in use (held where it shows beside the sidebar): the page comes
  // over with it, its bar there to be pressed (pengxiao, 2026-10-25: 引用 pressed there went to what showed of the page
  // and brought it over, quoting nothing). As it is picked, once: a passage left picked keeps nothing from being brought
  // over after (pengxiao, 2026-10-25: the sidebar pressed or pulled over went straight back)
  let pick = if @sfbase.pk.ts == "" { "" } else { "\{@sfbase.pk.ts}\u{1}\{@sfbase.pk.taken_at}" }
  if pick != "" &&
    pick != wide.tape_pick.get() &&
    wide.tape_at.get() != Page &&
    wide.tape_ask.get() is None &&
    wide.tape_pull.get() is None {
    wide.tape_ask.set(Some(Page))
  }
  wide.tape_pick.set(pick)
}

///|
/// Page `page` of the stack in the page's panel, its island's (as wide as the stack is, beside the system's column): a
/// step darker while the panel is behind the one in use, nothing of it read out then (tape_behind); what is in it as
/// wide as beside the column, its right corners none of what is in it there (beside_column); a right click in it copying
/// what is picked; what moves in it of its own (the composer) taking its place from its foot.
fn tape_page_one(c : @ui.Ctx, src : Source, page : Page) -> Unit {
  let (now, _, _, _) = @sfbase.workspace_in_view(src)
  guard now is Some(w) else { return }
  // (said by this build: image_item, video_item)
  @sfbase.held_pictures_waiting.val = false
  let side = tape_shown_side()
  let under = if side is None { tape_room_now().under } else { 0.0 }
  let corners = tape_pane_corners(Page, side is Some(_))
  let page_id = c.id("main-page")
  tape_behind(c, Page, fn() {
    context_page(c, page_id)
    let pane = c.box(style=frame_main.then(@ui.style(w=Fixed(c.width))), id=page_id, fn() {
      @sf.pane_round.val = Some(beside_column(corners, under))
      tape_bar_collected(c, fn() { page_one(c, src, w, page, c.width, c.height, 0.0, pane_finger()) })
      @sf.pane_round.val = None
    })
    // (what moves in the page of its own takes its place from the page's foot: the tape moving the page, a keyboard
    // making it shorter, move none of it (it goes with the page, at once))
    @motion.scope(c, pane, bottom=true)
  })
}

///|
/// A page's bar on the tape as its page said it the last time it was built (tape_bar_collected), and what its back
/// does then; the node of the tree's that shows it reads it (tape_bar_head).
priv struct TapeBar {
  said : @signals.Signal[PaneBarSaid?]
  mut back : () -> Unit
}

///|
/// Each page's bar on the tape, by its entry (its number): made as its page is first shown or built, let go as the entry
/// leaves the stack (nav_flat_view's `gone`), not as its node stops showing.
// kept across runs: emptied as a run begins (tape_goes_reset), each let go with its entry
let tape_bars : Map[Int, TapeBar] = {}

///|
/// The bar of entry `k`'s page, made as it is first asked.
fn tape_bar_of(k : Int) -> TapeBar {
  match tape_bars.get(k) {
    Some(b) => b
    None => {
      let b = { said: @signals.signal(None, same=fn(a, b) { a == b }), back: fn() {  } }
      tape_bars[k] = b
      b
    }
  }
}

///|
/// Over entry `k`'s page in the page's panel (node `b`): its bar, the tree's (pane_bar_node), as its page said it as it
/// was built; none where it said none or keeps its own (one with actions, built the old way with them); the panel's
/// corners its ends', its ground the panel's.
fn tape_bar_head(b : @view.View, k : Int, tips : @sf.TipLayer) -> Unit {
  let tb = tape_bar_of(k)
  b.show(fn() { tb.said.get() is Some(_) }, fn(h) {
    pane_bar_node(
      h,
      fn() { tb.said.get() },
      fn() { (tb.back)() },
      fn() {
        let side = tape_shown_side()
        let under = if side is None { tape_room_now().under } else { 0.0 }
        beside_column(tape_pane_corners(Page, side is Some(_)), under)
      },
      fn() { tape_page_ground(h) },
      tips,
      // (the page's width, as its page is built in it: the stack's room in the panel)
      fn() { tape_page_at(tape_drawn_at(h)) },
      // (nothing of it read out while the panel is not in use, as the page under it: tape_behind)
      fn() { wide.tape_at.get() != Page },
    )
    |> ignore
  })
}

///|
/// `build` (a page of the page's panel, built in Ctx `c`, its entry the one it is built for: c.owner) with what it says
/// of its bar (@sf.page's pane_bar) collected for the tree's bar over it (tape_bar_head), the page under it alone; one
/// with actions of its own (built the old way, by its view) with its whole bar as before (pane_page), the tree's none.
/// Told to the tree's bar as it changes, by what it shows: none where the page said none this time. The wire put back
/// as it was once it is built.
fn tape_bar_collected(c : @ui.Ctx, build : () -> Unit) -> Unit {
  let tb = tape_bar_of(c.owner)
  let wire = @sf.pane_bar.val
  let said : Ref[PaneBarSaid?] = Ref(None)
  @sf.pane_bar.val = Some(fn(c, bar, page) {
    match (bar.actions, wire) {
      (Some(_), Some(draw)) => draw(c, bar, page)
      _ => {
        // (one with a head of its own has what it is of as its bar's title: pane_page's)
        let (title, small) = if bar.own_head && bar.small != "" { (bar.small, "") } else { (bar.title, bar.small) }
        said.val = Some({ back: bar.back.map(fn(b) { b.0 }), title, small, about: bar.about })
        tb.back = match bar.back {
          Some((_, go)) => go
          None => fn() {  }
        }
        // (the bar's room left by the page as it is built, the tree's bar laid over it: what is under it where it stays
        // from the frame it is first built, whenever the bar is told what it shows)
        c.box(style=pane_page_fill, fn() {
          c.box(style=@ui.style(w=Full, h=Fixed(pane_bar_h())), fn() {  }) |> ignore
          c.box(style=pane_page_rest, page) |> ignore
        })
        |> ignore
      }
    }
  })
  build()
  @sf.pane_bar.val = wire
  tb.said.set(said.val)
}
