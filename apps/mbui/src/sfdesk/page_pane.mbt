// The page's pane's stack held by the window's tree (@ui.nav_flat_view: the pane beside the block on Large, the tape's
// page panel on Medium): each page of the stack a node of its own, built the old way in it (its island), as the frame
// drew the stack's page before: what waits to be confirmed in the workspace's safe mode in its place, else the page moved
// aside as the folded sidebar is shown a while, its words picked by the pointer (a finger picks them as on a phone).

///|
/// Page `page` of the stack in workspace `w`, its island's: `main_w` wide and `ph` high, moved `aside`, as the frame drew
/// the stack's top before.
fn page_one(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  page : Page,
  main_w : Double,
  ph : Double,
  aside : Double,
  finger : Bool,
) -> Unit {
  let top = page == app.nav.top()
  if @ui.window_inset() {
    title_row(c, "page-title-row", @sf.wide_bar_h + (if wide.tape { @sf.tape_bar_over() } else { 0.0 }))
  }
  c.sized(main_w, ph, fn() {
    let body = fn() {
      let moved = c.box(style=page_aside, tx=aside, fn() {
        // (the page drawn: one on its way out hands no actions to the system's bars)
        drawn_page.val = Some(page)
        if top {
          top_drawn.val = true
        }
        let (now, all, _, invited) = @sfbase.workspace_in_view(src)
        main_page(c, src, now.unwrap_or(w), all, invited, page)
        drawn_page.val = None
      })
      @motion.scope(c, moved, bottom=true)
    }
    if finger {
      body()
    } else {
      c.selectable(color=@sf.alpha(@sf.theme().p.blue, 0.28), body)
    }
  })
}

///|
/// Page `page` of the pane off the tape (Large), its island's (the room the tree leaves the stack beside the block's
/// column): the page's bars' room where the block's move has got (page_bar_room), the page moved aside as the block is
/// shown a while; the top's what the page shows across as it is laid out (fold_peek_shift reads it).
fn pane_page_one(c : @ui.Ctx, src : Source, page : Page) -> Unit {
  let (now, _, _, _) = @sfbase.workspace_in_view(src)
  guard now is Some(w) else { return }
  let (r, target) = fold_target(src, w, c.window_size().0)
  let f = fold_built(c, target)
  fold_bars(f)
  // (the page shown in the pane, whether the one on top or the one kept while that waits: the one page built here)
  let page_id = c.id("main-page")
  // (said by this build: image_item, video_item)
  @sfbase.held_pictures_waiting.val = false
  fold_goes.page_id = page_id
  // (what the page shows across as it is laid out, its bars left out: where the page moves aside to as the folded
  // sidebar is shown a while, taken as that starts: fold_peek_shift)
  c.shown_across(page_id, but="page-bar") |> ignore
  // a right click in it: what is picked copied (context_menu.mbt)
  context_page(c, page_id)
  let pane = c.box(style=frame_main.then(@ui.style(w=Fixed(c.width))), id=page_id, fn() {
    page_one(c, src, w, page, c.width, c.height, f.aside, pane_finger())
  })
  // (what moves in the page of its own takes its place from the page's foot: a keyboard, the block moving the page
  // aside, move none of it)
  @motion.scope(c, pane, bottom=true)
}

///|
/// The stack in the pane off the tape (Large) as a node of `v`'s: each page its island (pane_page_one); a page put in
/// place shown as pane_page_wait says, at its causes; nothing pushed over slides here (shown in place as any other).
/// While the workspace waits to be confirmed in its safe mode, what waits in its place instead, the stack none of it
/// (nothing of it pressed, nothing of it back), as the frame had it before.
fn pane_pages(v : @view.View, src : Source) -> Unit {
  // (what the page's bars and the sidebar's parts work out from, where the block's move has got, said every frame the
  // pane's frame is built, as the pane's island said it before its page: whichever page shows, or none)
  @ui.old(v, fn(c) { pane_bars_said(c, src) }, key=tape_island_key).over(Is(true)) |> ignore
  let gated = fn() {
    match @sfbase.workspace_in_view(src).0 {
      Some(w) => fold_target(src, w, v.window().0).0.gated
      None => false
    }
  }
  // (what waits in its place giving back the focus as it goes, to what had it as it came: the page under it kept, laid
  // out nowhere meanwhile (none of it built, pressed or read out), the focus in it let go of then, after it is kept)
  v.show(gated, fn(g) {
    g.grow(Is(1.0)).focus_returns() |> ignore
    @ui.old(g, fn(c) { pane_gate_built(c, src) }, key=tape_island_key).grow(Is(1.0)) |> ignore
  })
  v.box(fn(s) {
    s.grow(Is(1.0)).laid_nowhere(By(gated)) |> ignore
    pane_stack(s, src)
  })
  |> ignore
}

///|
/// The pane's frame's island (Large), drawing nothing: what the page's bars and the sidebar's parts work out from, where
/// the block's move has got (fold_bars), and the page on top switched (page_switch_frame), said as it is built: before
/// the stack's pages, built again as either changes.
fn pane_bars_said(c : @ui.Ctx, src : Source) -> Unit {
  let (now, _, _, _) = @sfbase.workspace_in_view(src)
  guard now is Some(w) else { return }
  let (r, target) = fold_target(src, w, c.window_size().0)
  fold_bars(fold_built(c, target))
  // a chat and a new chat switched between: the composer moving, the rest crossfading (switch.mbt), as the page on top
  // changes, before any page of it is built; none while what waits in the safe mode is in the pages' place
  if !r.gated {
    page_switch_frame(c)
  }
}

///|
/// What waits to be confirmed in the workspace's safe mode, in the pane off the tape (its island).
fn pane_gate_built(c : @ui.Ctx, src : Source) -> Unit {
  let (now, _, _, _) = @sfbase.workspace_in_view(src)
  guard now is Some(w) else { return }
  let (_, target) = fold_target(src, w, c.window_size().0)
  fold_bars(fold_built(c, target))
  if @ui.window_inset() {
    title_row(c, "page-title-row", @sf.wide_bar_h)
  }
  c.box(style=frame_gate.then(@ui.style(w=Fixed(c.width), h=Fixed(c.height))), fn() {
    let core = settings_core(src, w)
    @sfpages.lock_wait_page(c, core, @settings.here_of(core, w.id, w.name))
  })
  |> ignore
}

///|
fn pane_stack(v : @view.View, src : Source) -> Unit {
  @ui.nav_flat_view(
    v,
    app.nav,
    fn(c, p) { pane_page_one(c, src, p) },
    fn(p) { (fold_goes.ready)(p) },
    fold_goes.most,
    bg=fn() { @sf.theme().p.bg },
    stacks=fn() { false },
    page_key=fn(_) { tape_island_key() },
  )
  |> ignore
}
