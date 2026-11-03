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
/// The page's panel (in node `v`, as tape_panel_box gives it room): the page on top switched as the stack is told it
/// (page_switch_said), a passage picked as it is picked (tape_pick_said); its ground, corners and line, cutting what is
/// in it to them; the stack in it, as wide as beside the system's column (`under` its ground alone).
fn tape_page_pane(v : @view.View, src : Source) -> Unit {
  // (its tips over all of the window, as the old frame's are: none cut by the panel)
  let tips = @sf.TipLayer::new(fn() { tape_goes.node })
  // (what is drawn in it cut to its room, as the island it was drawn by before was: the panel's ground and line too)
  v.clips(Is(true)) |> ignore
  // (the page on top switched, as the stack is told it: before any page of it is built; a passage picked while the page
  // is not in use, as it is picked: tape_pick_said)
  page_switch_said(v, fn() { @sfbase.workspace_in_view(src).0 is Some(_) })
  tape_pick_said(v, src)
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
      head=fn(b, k, made) { tape_bar_head(b, k, made, tips) },
      // (a page of the library's made once in its place, where it is: its bar the tape's, from what the page is)
      made=fn(p) { tape_made(src, p, tips) },
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
/// A passage of a message picked while the page is not in use (held where it shows beside the sidebar), followed in
/// node `v`: the page comes over with it, its bar there to be pressed (pengxiao, 2026-10-25: 引用 pressed there went to
/// what showed of the page and brought it over, quoting nothing). As it is picked, once (@sfbase.picked: a new
/// identity), never as it stays picked: a passage left picked keeps nothing from being brought over after (pengxiao,
/// 2026-10-25: the sidebar pressed or pulled over went straight back).
fn tape_pick_said(v : @view.View, src : Source) -> Unit {
  // (what is picked, as told, while a workspace is in view: none taken while none is, what is picked then taken as one
  // is again)
  v.reacts(fn() { (@sfbase.picked.get().serial, @sfbase.workspace_in_view(src).0 is Some(_)) }, fn(now) {
    let (serial, held) = now
    guard held else { return }
    let pick = if serial == 0 { "" } else { serial.to_string() }
    if pick != "" &&
      pick != wide.tape_pick.get() &&
      wide.tape_at.get() != Page &&
      wide.tape_ask.get() is None &&
      wide.tape_pull.get() is None {
      wide.tape_ask.set(Some(Page))
    }
    wide.tape_pick.set(pick)
  })
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
/// does then; or what a page made once said of itself (tape_made); the node of the tree's that shows it reads it
/// (tape_bar_head).
priv struct TapeBar {
  said : @signals.Signal[PaneBarSaid?]
  mut back : () -> Unit
  /// what a page made once said of itself as it was last told (page_node's `said`), kept with its entry
  page_said : @signals.Signal[@sf.PageSaid?]
  /// what such a page does in its bar, as it gave it, how tall it stands there in a page laid out so, and which making
  /// of the page gave it (the bar's made again for each)
  page_actions : @signals.Signal[((@view.View) -> Unit, (@sf.Look) -> Double, Int)?]
}

///|
/// The makings of pages that give the tape's bar what they do, numbered.
// kept across runs: a count
let tape_actions_made : Ref[Int] = Ref(0)

///|
fn next_tape_actions_gen() -> Int {
  tape_actions_made.val += 1
  tape_actions_made.val
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
      let b = {
        said: @signals.signal(None, same=fn(a, b) { a == b }),
        back: fn() {  },
        page_said: @signals.signal(None, same=fn(a, b) { a == b }),
        page_actions: @signals.signal(None, same=fn(a, b) {
          match (a, b) {
            (None, None) => true
            (Some(x), Some(y)) => x.2 == y.2
            _ => false
          }
        }),
      }
      tape_bars[k] = b
      b
    }
  }
}

///|
/// Over entry `k`'s page in the page's panel (node `b`): its bar, the tree's (pane_bar_node), as its page said it as it
/// was built; over one made once (`made`: tape_made) as it says of itself (tape_made_bar); none where an old view
/// said none or keeps its own (one with actions, built the old way with them); the panel's corners its ends', its
/// ground the panel's.
fn tape_bar_head(b : @view.View, k : Int, made : Bool, tips : @sf.TipLayer) -> Unit {
  let tb = tape_bar_of(k)
  // (a page made once: its bar there whatever it has said yet, from what it said of itself and where it was put on
  // from (its back); else as its old view said it. Where it was put on from as last said, kept while the stack is
  // told of a change before it is whole (an entry put in place and kept shown by its owner, told in either order))
  let under : Ref[Page?] = Ref(None)
  // (and whether it is a place of the rail's itself, kept so with it: no back over one, whatever is under it)
  let place = Ref(false)
  let said = fn() {
    if !made {
      return tb.said.get()
    }
    match app.nav.page_of(k) {
      Some((p, u)) => {
        under.val = u
        place.val = p is Place(_)
      }
      None => ()
    }
    Some(tape_made_bar(under.val, place.val, tb.page_said.get()))
  }
  b.show(fn() { said() is Some(_) }, fn(h) {
    pane_bar_node(
      h,
      said,
      fn() {
        if made {
          app.nav.pop() |> ignore
        } else {
          (tb.back)()
        }
      },
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
      // (what a page made once does, at its end)
      actions=fn() { if made { tb.page_actions.get() } else { None } },
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

///|
/// The pages of the library's made once as nodes in the page's panel, in the place of their old view (nav_flat_view's
/// `made`), by what each is: 关于, 记忆, 归档 and 自动决策, as the settings' list opens them; a station's own archiving, as 归档
/// opens it; 更新日志 as 关于 opens it; 一台 station 的记忆 as 记忆 opens it. Each laid out by the page's width (the stack's
/// in the panel at rest, as the tape lays it out now: page_node narrow or wide; narrow while that is not known); 关于,
/// 记忆 and 更新日志 a right click in them copying what is picked. Under the tape's bar (tape_bar_head, from
/// tape_made_bar): no title, no back of its own, nothing over it in its room.
fn tape_made(
  src : Source,
  page : Page,
  tips : @sf.TipLayer,
) -> (String, (@view.View, () -> Page, Page?, () -> Int, Int) -> Unit)? {
  // (as wide as the stack in the panel at rest, as the tape lays it out now: the page's width, 0 while not known)
  let width = fn() {
    let r = tape_room_now()
    r.main_to - (if tape_shown_side() is None { r.under } else { 0.0 })
  }
  // (made in the workspace in view, its settings' core; what it says of itself kept with its entry, `k`)
  let made = fn(
    kind : String,
    f : (
      @view.View,
      @settings.Core,
      () -> @settings.Here,
      () -> Int,
      (@sf.PageSaid) -> Unit,
      ((@view.View) -> Unit, (@sf.Look) -> Double) -> Unit,
    ) -> Unit,
  ) {
    Some(
      (
        kind,
        fn(v : @view.View, _page : () -> Page, _under : Page?, stint : () -> Int, k : Int) {
          let told = fn(s : @sf.PageSaid) { tape_bar_of(k).page_said.set(Some(s)) }
          v.pick(fn() { @sfbase.workspace_in_view(src).0.map(fn(w) { w.id }) }, fn(p, _id) {
            // (what the page made in `p` does in the bar, its own while `p` is: given as it is made, let go with `p`
            // where none since gave the bar another's)
            let gen = next_tape_actions_gen()
            let acts = fn(make : (@view.View) -> Unit, side : (@sf.Look) -> Double) {
              tape_bar_of(k).page_actions.set(Some((make, side, gen)))
            }
            p.owns(fn() {
              let tb = tape_bar_of(k)
              if @signals.untracked(fn() { tb.page_actions.get() }) is Some((_, _, g)) && g == gen {
                tb.page_actions.set(None)
              }
            })
            |> ignore
            match @signals.untracked(fn() { @sfbase.workspace_in_view(src).0 }) {
              Some(w) => {
                let core = settings_core(src, w)
                let here = fn() { @settings.here_of(core, w.id, w.name) }
                @settings.frame(core, @signals.untracked(here))
                f(p, core, here, stint, told, acts)
              }
              None => ()
            }
          })
        },
      ),
    )
  }
  match page {
    // (laid out by the page's width, narrow or wide: page_node's)
    Setting(About) if pane_makes.val =>
      made("about", fn(p, core, _here, _stint, told, _acts) {
        context_node(p)
        @sfpages.about_node(p, core, on_back=core.pop, frame=fn() { tape_made_frame }, said=told, width~)
      })
    Setting(Memories) if pane_makes.val =>
      made("memories", fn(p, core, here, _stint, told, _acts) {
        context_node(p)
        @sfpages.memories_node(p, core, here, on_back=core.pop, frame=fn() { tape_made_frame }, said=told, width~)
      })
    Setting(Changelog) if pane_makes.val =>
      made("changelog", fn(p, core, _here, _stint, told, _acts) {
        context_node(p)
        @sfpages.changelog_node(p, core, on_back=core.pop, frame=fn() { tape_made_frame }, said=told, width~)
      })
    // (a place of the rail's whose page is one of those: that page as the settings open it, at the stack's root, made
    // under its own kind)
    Place(name) =>
      match @settings.route_of(name) {
        // (those whose old view is gone: every frame makes them once, as a page or a place)
        Some(r) if r is (About | Changelog | Memories | Memory(_) | Archiving | StationArchiving(_) | AutoDecisions | Usage | UsagePrices(_)) =>
          tape_made(src, Setting(r), tips).map(fn(m) { ("place/" + m.0, m.1) })
        _ => None
      }
    // (by its station: another station's another page, not this one become it)
    Setting(Memory(address)) if pane_makes.val =>
      made("memory/" + address, fn(p, core, here, _stint, told, _acts) {
        context_node(p)
        @sfpages.memory_node(p, core, here, address, on_back=core.pop, frame=fn() { tape_made_frame }, said=told, width~, tips~)
      })
    Setting(Usage) if pane_makes.val =>
      made("usage", fn(p, core, here, _stint, told, acts) {
        context_node(p)
        @sfpages.usage_node(p, core, here, on_back=core.pop, frame=fn() { tape_made_frame }, said=told, width~, tips~, bar_actions=acts)
      })
    // (by its days: another's of other days another page)
    Setting(UsagePrices(days)) if pane_makes.val =>
      made("usage-prices/" + days.to_string(), fn(p, core, here, _stint, told, _acts) {
        context_node(p)
        @sfpages.usage_prices_node(p, core, here, days, on_back=core.pop, frame=fn() { tape_made_frame }, said=told, width~)
      })
    Setting(Archiving) if pane_makes.val =>
      made("archiving", fn(p, core, here, stint, told, _acts) {
        @sfpages.archiving_node(p, core, here, on_back=core.pop, frame=fn() { tape_made_frame }, stint~, said=told, width~)
      })
    Setting(AutoDecisions) if pane_makes.val =>
      made("auto-decisions", fn(p, core, here, _stint, told, _acts) {
        @sfpages.decisions_node(p, core, here, on_back=core.pop, frame=fn() { tape_made_frame }, said=told, width~, tips~)
      })
    // (by its station: another station's another page, not this one become it)
    Setting(StationArchiving(st)) if pane_makes.val =>
      made("station-archiving/" + st, fn(p, core, here, _stint, told, _acts) {
        @sfpages.station_archiving_node(p, core, here, st, on_back=core.pop, frame=fn() { tape_made_frame }, said=told, width~)
      })
    _ => None
  }
}

///|
/// What the tape gives a page made once in its panel (tape_made): the bar over it names it and has back (named, no
/// back), nothing over it in its room, the settings' room at its foot (setting_page's).
// kept across runs: a value
let tape_made_frame : @sf.PageFrame = { back: None, top: 0.0, foot: 0.0, named: true }

///|
/// The bar over a page made once in the page's panel (tape_made), as it said of itself (`said`: its title, what it is
/// for; none yet, nothing said), back where the page it was put on from (`under`) is one of the settings' or a place
/// of the rail's (setting_page's); none over a `place` of the rail's itself, whatever is under it (place_page's).
fn tape_made_bar(under : Page?, place : Bool, said : @sf.PageSaid?) -> PaneBarSaid {
  let back = match under {
    Some(u) if !place && u is (Setting(_) | Place(_)) => Some(@sfbase.back_label(u))
    _ => None
  }
  match said {
    Some(s) => { back, title: s.title, small: "", about: s.about }
    None => { back, title: "", small: "", about: "" }
  }
}
