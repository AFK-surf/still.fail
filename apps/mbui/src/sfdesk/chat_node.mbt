// A chat's page (chat_page.mbt's) made once in the window's tree in the wide frame's pane: its messages (sfpages
// chat_list_node) and its composer (sfpages chat_composer_node) its own nodes, as on a narrow screen (sfapp
// chat_node.mbt); its bar and side panel's shell its nodes too. Independent pages in the side panel, and what opens
// over the chat, keep their own page boundaries.

///|
/// Chat `r`'s page in `p` while it shows (entry `k` of the stack): its messages under its bar over its composer's room,
/// the composer at its foot, what flies over them, the bar and what is let go over them; its side panel beside it as its
/// tabs open it (side_beside's slide). `old_over` builds what of it is the old view's over it, as where it is shows its pages
/// (the tape's panel: its bar told the tape, its corners the panel's); no `side` panel beside it where that is shown
/// apart (the tape's: tape_side); its `ground` where it is (the tape's panel's, a step darker behind the one in use).
fn chat_root_node(
  p : @view.View,
  src : Source,
  r : ChatRef,
  k : Int,
  old_over? : (@ui.Ctx, () -> Unit) -> Unit = fn(_, build) { build() },
  corners? : () -> FixedArray[@ui.CornerOf]? = fn() { None },
  side? : Bool = true,
  ground? : (@view.View) -> Int64 = fn(_) { @sf.theme().p.bg },
) -> Unit {
  p.pick(fn() { @sfbase.workspace_in_view(src).0.map(fn(w) { w.id }) }, fn(page, _id) {
    page.grow(Is(1.0)).min_height(Is(Some(0.0))).row(Is(true)).ground(By(fn() { ground(page) })) |> ignore
    guard @signals.untracked(fn() { @sfbase.workspace_in_view(src).0 }) is Some(w) else { return }
    let view = fn() { @sfbase.chat_view_now(src, r) }
    // (its side panel's tabs, as the core says them: open while it has any)
    let open = fn() { view().map(fn(v) { side_of(v).0.length() > 0 }).unwrap_or(false) }
    // (how far it has slid in: in and out on a Move as long as it is wide, from the change that opens or closes it)
    let slide = @motion.Way::new(if @signals.untracked(open) { 1.0 } else { 0.0 })
    page.reacts(open, fn(o) {
      let to = if o { 1.0 } else { 0.0 }
      if slide.target() != to {
        let pane = page.laid_size_told().map(fn(z) { z.0 }).unwrap_or(page.window().0)
        slide.go(to, @motion.move(over=side_whole(pane)), at=page.cause_at())
      }
    })
    let slid = fn() {
      guard side else { return 0.0 }
      slide.said()
      if slide.goes_at(page.logic_at()) { slide.value_at(page.drawn_at()) } else { slide.target() }
    }
    // laid out by the pane's room (View::layout_box: nothing of its size read back): the chat as wide as the pane less
    // the panel beside it, all of it where the panel comes over it (narrower than both take); the panel from the pane's
    // right edge as far in as it has slid, cut there (the page cuts it), over the chat or beside it, each its own child
    page
    .clips(Is(true))
    .layout_box(By(fn() { (side && open(), slid(), panel_own.width.get()) }), fn(l, at) {
      let (opened, slid_in, wanted) = at
      let pane = l.width
      let whole = side_whole_of(pane, wanted)
      let col = slid_in * whole
      let over = pane < side_both_least
      let talk = l.child("talk", fn(talk) {
        talk.min_width(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
        chat_talk_node(talk, src, w, r, k, view, old_over, corners, ground)
      })
      l.measure(talk, if over { pane } else { pane - col }, height=l.height) |> ignore
      l.place(talk, 0.0, 0.0)
      if side && (col > 0.0 || opened) {
        let panel = l.child(if over { "side over" } else { "side beside" }, fn(panel) {
          side_panel_node(panel, src, w, r, view, over=fn() { over }, old_page=fn(c, build) {
            app.nav.page_old(c, k, fn(_) { build() })
          })
        })
        l.measure(panel, whole, height=l.height) |> ignore
        l.place(panel, pane - col, 0.0)
      }
    })
    |> ignore
  })
}

///|
/// How wide a chat's side panel is in a pane `pane` wide: over the chat (ChatPage.css.ts sidePanel on a narrow page:
/// min(460px, 100vw)) where the pane has not the room for both, else beside it (side_width).
fn side_whole(pane : Double) -> Double {
  side_whole_of(pane, panel_own.width.get())
}

///|
/// side_whole with the width the person dragged it to (`wanted`, panel_own's) given: what a layout reads, taken before it.
fn side_whole_of(pane : Double, wanted : Double?) -> Double {
  if pane < side_both_least {
    dmin(side_over_w, pane)
  } else {
    side_width_of(pane, wanted)
  }
}

///|
/// The chat itself in `talk` (chat_talk's): its list under the bar's room over the composer's, the composer at its
/// foot, what flies in it, and over them the bar, what opens over it, what is let go over the pane and what is picked in
/// the messages, an island.
fn chat_talk_node(
  talk : @view.View,
  src : Source,
  w : Workspace,
  r : ChatRef,
  k : Int,
  view : () -> ChatView?,
  over : (@ui.Ctx, () -> Unit) -> Unit,
  corners : () -> FixedArray[@ui.CornerOf]?,
  ground : (@view.View) -> Int64,
) -> Unit {
  let width = fn() { talk.laid_size_told().map(fn(z) { z.0 }).unwrap_or(talk.window().0) }
  let height = fn() { talk.laid_size_told().map(fn(z) { z.1 }).unwrap_or(talk.window().1) }
  let radii = fn() {
    let roots = @ui.tree_corner_roots_now()
    corners().map(fn(ks) { ks.map(fn(k) { k.radius(roots) }) })
  }
  let geometry = fn() { @sfpages.composer_geometry(width(), radii()) }
  let latest : Ref[() -> Unit] = Ref(fn() {  })
  let landing : Ref[(String) -> @sfpages.MineLanding?] = Ref(fn(_) { None })
  let room : @signals.Signal[(() -> Double)?] = @signals.signal(None, same=fn(a, b) { a is None && b is None })
  let room_now = fn() { room.get().map(fn(f) { f() }).unwrap_or(0.0) }
  // (its view not read yet: its messages to come in their bones, the first where the list's first row will be, or why
  // it cannot be read. A chat just made from a new chat already has fresh_view's view, so it shows no sample.)
  talk.show(fn() { view() is None }, fn(b) {
    b
    .over(Is(true))
    |> ignore
    @sfpages.chat_waiting_node(b, src, r, fn() { chat_bar_room() + list_head_gap }, fn() { @sf.under_bar_room().px() })
  })
  talk.box(fn(l) {
    l.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
    let list = @sfpages.chat_list_node(l, src, r, view, fn() { chat_bar_room() + list_head_gap }, room_now, settings_core(src, w),
      foot_gap=list_foot_gap, composer_across=fn() { geometry().0 })
    latest.val = list.to_latest
    landing.val = list.landing_of
  })
  |> ignore
  talk.box(fn(f) {
    f
    .over(Is(true))
    .lies_along(Is(End))
    |> ignore
    // (made while its page is the one seen in the stack's top's place (the top, or the one kept there while the top
    // waits): the draft's field is one editor's, and the same chat may be under it (its history asked as a page, a
    // service beside it))
    @sfpages.composer_on_page(f, fn() { app.nav.drawn_stay().0 == k }, fn(f) {
    let made = @sfpages.chat_composer_node(
      f,
      src,
      r,
      view,
      fn() { @sfpages.composer_side_in(radii()) },
      height,
      fn(pane) { @sfpages.composer_geometry(pane, radii()).1 },
      fn() { geometry().2 },
      fn(_key) { (latest.val)() },
      active=fn() { app.nav.drawn_stay().0 == k },
      drops=talk,
      // (its shape as the talk it stands in is laid out, in the same layout: composer_box_node's)
      place_in=fn(pane) { @sfpages.composer_geometry(pane, radii()).2 },
    )
    room.set(Some(made.room))
    f.owns(fn() { room.set(None) }) |> ignore
    })
  })
  |> ignore
  talk.box(fn(fl) {
    fl
    .over(Is(true))
    |> ignore
    @sfpages.chat_flight_layer_made(r, fl)
    @sfbase.send_flight_node(
      fl,
      r.station + ":" + r.session,
      fn(f) { (landing.val)(f.key).bind(fn(l) { l.text }) },
      quotes=fn(f, key) { (landing.val)(f.key).bind(fn(l) { l.quotes.get(key) }) },
      files=fn(f, key) { (landing.val)(f.key).bind(fn(l) { l.files.get(key) }) },
    )
  })
  |> ignore
  // (what is picked of a message: the finger's bar or the mouse's pill over it: pick_node.mbt)
  talk.box(fn(pl) {
    pl
    .over(Is(true))
    |> ignore
    @sfpages.pick_bar_node(pl, src, r.station + ":" + r.session, fn() { chat_bar_room() }, room_now)
  })
  |> ignore
  // (the chat's keys, done while it takes input; what it needs of the viewer felt as that comes; ⌘F's bar let go as
  // another chat shows)
  chat_actions_node(talk, src, w, r, view, fn() { (latest.val)() })
  @sfbase.feel_needed_node(talk, view, fn() { app.nav.shows(k) })
  talk.reacts(fn() { app.nav.shows(k) && find_chat() != "" && find_chat() != chat_key(r) }, fn(other) {
    if other { (chat_find_list(r).forget)() }
  })
  // (the bar and what opens over it, what is let go over the pane and what is picked in the messages: the old view's,
  // an island over all of it, built as the stack's page)
  talk.box(fn(o) {
    // (where it is in the window, as laid out: followed, so as it is laid out it is known, not asked of it at a moment)
    let pane_rect : Ref[(Double, Double, Double, Double)?] = Ref(None)
    o.reacts(fn() { o.laid_window_told() }, fn(r) { pane_rect.val = r })
    o
    .over(Is(true))
    |> ignore
    o.show(fn() { app.nav.shows(k) }, fn(s) {
      // (all of the chat's room: what opens over it opens in it)
      s
      .over(Is(true))
      |> ignore
      @ui.old(s, fn(c) {
        app.nav.page_old(c, k, fn(c) {
          over(c, fn() { chat_over(c, src, w, r, fn() { pane_rect.val }) })
        })
      })
      .grow(Is(1.0))
      |> @ui.old_takes_own
      |> ignore
    })
  })
  |> ignore
  chat_bar_node(talk, src, w, r, k, view, width, corners, ground)
}

///|
/// What of chat `r`'s page is drawn over its messages by the old view it was (chat_page's, chat_talk's): the bar and
/// its popovers, what a row carried over the pane frosts and what is let go there, the
/// new chat it became leaving over it. `pane_at` where the pane is in the window, as the tree laid it out.
fn chat_over(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  r : ChatRef,
  pane_at : () -> (Double, Double, Double, Double)?,
) -> Unit {
  let view = view_of_chat(src, r).0
  let draft = r.station + ":" + r.session
  let pane = c.box(style=chat_over_box, fn() { })
  if view is Some(_) {
    drop_hint(c, pane)
  }
  // (a row of the 文件 tab let go over it, into the draft: chat_talk's; files from Finder and words from another app
  // the composer's own, over all of the chat: chat_composer_node's `drops`)
  // (where the pane is the tree's to say: built again only for what it reads, this box's own place not laid out yet
  // as a row is let go over it)
  match tab_take_drop(c) {
    Some((item, x, y)) if inside(@signals.untracked(pane_at), x, y) =>
      c.tell("chat-drop/" + draft, fn() {
        writing_drop(src, writing(src, draft), r.station, [@sfpages.dropped_of(item)], @sfpages.drops_as_files(src, draft))
      })
    _ => ()
  }
  new_chat_after(c, src, w, r)
}

///|
// kept across runs: a value (no field of it changes)
let chat_over_box : @ui.Style = @ui.css("w=Full h=Full")
