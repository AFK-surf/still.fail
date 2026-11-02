// The page's pane's stack held by the window's tree (@ui.nav_flat_view: the pane beside the block on Large, the tape's
// page panel on Medium): each page of the stack a node of its own, built the old way in it (its island), as the frame
// drew the stack's page before, or one of the library's made once in it (pane_made: 关于): what waits to be confirmed
// in the workspace's safe mode in its place, else the page moved aside as the folded sidebar is shown a while, its
// words picked by the pointer (a finger picks them as on a phone).

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
  let gated = fn() {
    match @sfbase.workspace_in_view(src).0 {
      Some(w) => fold_target(src, w, v.window().0).0.gated
      None => false
    }
  }
  // (the page on top switched, as the stack is told it, before any page of it is built; none while what waits in the
  // safe mode is in the pages' place. What the page's bars and the sidebar's parts work out from, where the block's
  // move has got, each of them works out as it is built: pane_page_one, pane_gate_built, pane_block_built)
  page_switch_said(v, fn() { @sfbase.workspace_in_view(src).0 is Some(_) && !gated() })
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
    // (a page of the library's made once in its place: 关于)
    made=fn(p) { pane_made(src, p) },
    // (which show, as the stack stands whole: the page made once that shows, by its entry)
    shown=fn(ks) { fold_goes.shown = ks },
  )
  |> ignore
}

///|
/// The pages of the library's made once as nodes in the pane off the tape (Large), in the place of their old view
/// (nav_flat_view's `made`): 关于, 记忆. Laid out by the width the frame gives the pane (the window's less the block's column
/// where its move goes: fold_target's, never what the page last laid out), narrow or wide (page_node), each made again
/// only as that arrangement changes. What the old view's island did for the page done by its node (pane_made_host).
fn pane_made(src : Source, page : Page) -> (String, (@view.View, () -> Page, Page?, () -> Int, Int) -> Unit)? {
  guard pane_makes.val else { return None }
  // (made in the workspace in view, its settings' core, under what it was opened from, as wide as the frame gives it)
  let made = fn(
    kind : String,
    f : (@view.View, @settings.Core, () -> @settings.Here, () -> @sf.PageFrame, () -> Double) -> Unit,
  ) {
    Some(
      (
        kind,
        fn(v : @view.View, _page : () -> Page, under : Page?, _stint : () -> Int, k : Int) {
          v.pick(fn() { @sfbase.workspace_in_view(src).0.map(fn(w) { w.id }) }, fn(p, _id) {
            guard @signals.untracked(fn() { @sfbase.workspace_in_view(src).0 }) is Some(w) else { return }
            let core = settings_core(src, w)
            let here = fn() { @settings.here_of(core, w.id, w.name) }
            @settings.frame(core, @signals.untracked(here))
            pane_made_host(p, src, k)
            // (back over it only under another settings page or a place of the rail's: setting_page's; its words read
            // as they are said, in the language now)
            let frame = fn() -> @sf.PageFrame {
              {
                back: match under {
                  Some(u) if u is (Setting(_) | Place(_)) => Some(@sfbase.back_label(u))
                  _ => None
                },
                top: 0.0,
                foot: 0.0,
                named: false,
              }
            }
            let width = fn() {
              let ww = p.window().0
              match @sfbase.workspace_in_view(src).0 {
                Some(w) => ww - fold_target(src, w, ww).1.col
                None => ww
              }
            }
            p.box(fn(a) {
              a.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
              f(a, core, here, frame, width)
            })
            |> ignore
          })
        },
      ),
    )
  }
  match page {
    Setting(About) =>
      made("about", fn(a, core, _here, frame, width) {
        @sfpages.about_node(a, core, on_back=core.pop, frame~, width~)
      })
    Setting(Memories) =>
      made("memories", fn(a, core, here, frame, width) {
        @sfpages.memories_node(a, core, here, on_back=core.pop, frame~, width~)
      })
    _ => None
  }
}

///|
/// Whether the frame makes the library's pages once where they are made at either width (pane_made; tape_made's 关于):
/// on in the app; off for a test that draws them as their old view does, to be compared.
// kept across runs: said by a test alone, round what it draws
pub let pane_makes : Ref[Bool] = Ref(true)

///|
/// What page_one and pane_page_one did for the page in its island, done for entry `k`'s page made once in node `p`: moved
/// aside as the folded sidebar is shown a while, where the block's move has got (page_aside's); over it the window's
/// title bar where its buttons are in the app's top row (title_row's); a right click in it copying what is picked
/// (context_node); what it shows across read of it as the sidebar comes to be shown a while, and nothing handed the
/// system's bars, while its entry shows (fold_goes' `made` by its entry, `shown`). Nothing in it moves of its own for
/// what moves the page (a keyboard, the block): no motion of the old view's is in it to be scoped to its foot
/// (@motion.scope's), its own (the update's bar's room) bound to its cause.
fn pane_made_host(p : @view.View, src : Source, k : Int) -> Unit {
  p
  .grow(Is(1.0))
  .min_height(Is(Some(0.0)))
  .offset(By(fn() {
    match @sfbase.workspace_in_view(src).0 {
      Some(w) => {
        let (_, now) = fold_target(src, w, p.window().0)
        (fold_along(fold_drawn_at(p), now).aside, 0.0)
      }
      None => (0.0, 0.0)
    }
  }))
  |> ignore
  context_node(p)
  fold_goes.made[k] = p
  p.owns(fn() {
    match fold_goes.made.get(k) {
      Some(v) if v.id() == p.id() => fold_goes.made.remove(k)
      _ => ()
    }
  })
  |> ignore
  p.show(fn() { @ui.window_inset() }, fn(t) {
    t
    .over(Is(true))
    .height(Is(Some(@sf.wide_bar_h)))
    .presses(Is(true))
    .moves_window(Is(true))
    |> ignore
  })
}
