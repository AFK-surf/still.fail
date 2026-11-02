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
  // (what is drawn in it cut to its room, as the island it was drawn by before was: the panel's ground and line too)
  v.clips(Is(true)) |> ignore
  @ui.old(v, fn(c) { tape_page_said(c, src) }, key=tape_island_key).over(Is(true)) |> ignore
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
      page_one(c, src, w, page, c.width, c.height, 0.0, pane_finger())
      @sf.pane_round.val = None
    })
    // (what moves in the page of its own takes its place from the page's foot: the tape moving the page, a keyboard
    // making it shorter, move none of it (it goes with the page, at once))
    @motion.scope(c, pane, bottom=true)
  })
}
