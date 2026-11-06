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
        // (as wide as the pane is laid out at the cause's moment: View::laid_size)
        let pane = page.laid_size().0
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
  let radii = fn() {
    let roots = @ui.tree_corner_roots_now()
    corners().map(fn(ks) { ks.map(fn(k) { k.radius(roots) }) })
  }
  let latest : Ref[() -> Unit] = Ref(fn() {  })
  let landing : Ref[(String) -> @sfpages.MineLanding?] = Ref(fn(_) { None })
  // (its composer while made: what its page's layout and its picks read of the room it takes)
  let made_now : @signals.Signal[@sfpages.ChatComposerNode?] = @signals.signal(None, same=fn(a, b) {
    match (a, b) {
      (Some(x), Some(y)) => physical_equal(x.root, y.root)
      (None, None) => true
      _ => false
    }
  })
  // (the room it takes under the list as this frame laid it out, read as it is painted)
  let room_laid = fn(laid : @view.Laid) {
    match made_now.get() {
      Some(m) =>
        @sfpages.composer_room_in(
          laid.size(m.root).map(fn(z) { z.1 }).unwrap_or(0.0),
          laid.size(m.composer.cap).map(fn(z) { z.1 }).unwrap_or(0.0),
          (m.room_of)(),
        )
      None => 0.0
    }
  }
  // (its view not read yet: its messages to come in their bones, the first where the list's first row will be, or why
  // it cannot be read. A chat just made from a new chat already has fresh_view's view, so it shows no sample.)
  talk.show(fn() { view() is None }, fn(b) {
    b
    .over(Is(true))
    |> ignore
    @sfpages.chat_waiting_node(b, src, r, fn() { chat_bar_room() + list_head_gap }, fn() { @sf.under_bar_room().px() })
  })
  // (its list over all of it and its composer at its foot, laid out by its room: the composer measured first, the room
  // it takes (what of it is laid out, its capsule's as that reports it, composer_room_in) given the list as what
  // covers its foot, its own lift with it (Layout::measure's `foot`: its last row that tall), in the same layout:
  // nothing of the composer read back)
  talk.box(fn(body) {
    body.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
    let lift : Ref[() -> Double] = Ref(fn() { 0.0 })
    let l = body.box(fn(l) {
      l.min_height(Is(Some(0.0))) |> ignore
      let list = @sfpages.chat_list_node(l, src, r, view, fn() { chat_bar_room() + list_head_gap }, settings_core(src, w),
        foot_gap=list_foot_gap, composer_across=fn(pane) { @sfpages.composer_geometry(pane, radii()).0 })
      latest.val = list.to_latest
      landing.val = list.landing_of
      lift.val = list.lift
    })
    // (made while its page is the one seen in the stack's top's place (the top, or the one kept there while the top
    // waits): the draft's field is one editor's, and the same chat may be under it (its history asked as a page, a
    // service beside it))
    let f = body.box(fn(f) {
      // (its shape by whether the talk's width lets it follow the panel's corners, picked as the talk is laid out
      // (View::by_room): nothing of the talk's width read back)
      f.by_room(By(radii), sized=true, fn(radii, pane, _) { @sfpages.composer_follows(pane, radii) }, fn(f, follows) {
      @sfpages.composer_on_page(f, src, r.station + ":" + r.session, fn() { app.nav.drawn_stay().0 == k }, fn(f) {
        let made = @sfpages.chat_composer_node(
          f,
          src,
          r,
          view,
          fn() { @sfpages.composer_side_in(radii()) },
          // (its lines as many as the talk's height gives them)
          (talk, fn(_, h) { h }),
          fn(pane) { @sfpages.composer_geometry(pane, radii()).1 },
          fn() { @sfpages.composer_place_of(follows, radii()) },
          fn(_key) { (latest.val)() },
          active=fn() { app.nav.drawn_stay().0 == k },
          drops=talk,
          // (its shape as the talk it stands in is laid out, in the same layout: composer_box_node's)
          place_in=fn(pane) { @sfpages.composer_geometry(pane, radii()).2 },
        )
        made_now.set(Some(made))
        f.owns(fn() { made_now.set(None) }) |> ignore
      })
      }) |> ignore
    })
    // (what flies over its messages and its composer, laid out after them in the same layout: what flies as big as
    // what it lands on as that is laid out, Layout::anchor)
    let fl = body.box(fn(fl) {
      @sfpages.chat_flight_layer_made(r, fl)
      @sfbase.send_flight_node(
        fl,
        r.station + ":" + r.session,
        fn(f) { (landing.val)(f.key).bind(fn(l) { l.text }) },
        quotes=fn(f, key) { (landing.val)(f.key).bind(fn(l) { l.quotes.get(key) }) },
        files=fn(f, key) { (landing.val)(f.key).bind(fn(l) { l.files.get(key) }) },
      )
    })
    body.layout_box(By(fn() { (lift.val)() }), fn(lay, lift) {
      let (_, ch) = lay.measure(f, lay.width)
      // (the room the composer takes, all of it as measuring it in this layout said (made in it or not): composer_room_in)
      let room = match (lay.reported(f, "opened"), lay.reported(f, "shape")) {
        (Some(opened), Some(shape)) =>
          @sfpages.composer_room_in(lay.reported(f, "composer").unwrap_or(ch), lay.reported(f, "cap").unwrap_or(0.0), (opened, shape))
        _ => 0.0
      }
      lay.measure(l, lay.width, height=lay.height, foot=(0.0, room + lift)) |> ignore
      lay.place(l, 0.0, 0.0)
      lay.place(f, 0.0, lay.height - ch)
      lay.measure(fl, lay.width, height=lay.height) |> ignore
      lay.place(fl, 0.0, 0.0)
    })
    |> ignore
  })
  |> ignore
  // (what is picked of a message: the finger's bar or the mouse's pill over it: pick_node.mbt)
  talk.box(fn(pl) {
    pl
    .over(Is(true))
    |> ignore
    @sfpages.pick_bar_node(pl, src, r.station + ":" + r.session, fn() { chat_bar_room() }, room_laid)
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
  // (a row of the 文件 tab carried onto the chat, let go on it: into its draft at that moment (useChatDrop: named by its
  // path, or as a file where the chat says so))
  @ui.takes_let_go(talk, fn(_, _) {
    match drag_taken() {
      Some(item) => {
        let draft = r.station + ":" + r.session
        writing_drop(src, writing(src, draft), r.station, [@sfpages.dropped_of(item)], @sfpages.drops_as_files(src, draft))
        true
      }
      None => false
    }
  })
  talk.box(fn(o) {
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
          over(c, fn() { chat_over(c, src, w, r) })
        })
      })
      .grow(Is(1.0))
      |> @ui.old_takes_own
      |> ignore
    })
  })
  |> ignore
  chat_bar_node(talk, src, w, r, k, view, corners, ground)
}

///|
/// What of chat `r`'s page is drawn over its messages by the old view it was (chat_page's, chat_talk's): the bar and
/// its popovers, what a row carried over the pane frosts, the new chat it became leaving over it.
fn chat_over(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  r : ChatRef,
) -> Unit {
  let view = view_of_chat(src, r).0
  let pane = c.box(style=chat_over_box, fn() { })
  if view is Some(_) {
    drop_hint(c, pane)
  }
  new_chat_after(c, src, w, r)
}

///|
// kept across runs: a value (no field of it changes)
let chat_over_box : @ui.Style = @ui.css("w=Full h=Full")
