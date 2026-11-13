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
) -> Unit {
  let top = page == app.nav.top()
  // (a chat's bar the page node's, dragging the window itself where nothing of it takes the press:
  // chat_bar_wide_node; the old view's row there would take what is over it)
  if @ui.window_inset() && !(page is Chat(_) && pane_makes.val) {
    title_row(c, "page-title-row", @sf.wide_bar_h + (if wide.tape.get() { @sf.tape_bar_over() } else { 0.0 }))
  }
  c.sized(main_w, ph, fn() {
    let body = fn() {
      let moved = c.box(style=page_aside, tx=aside, fn() {
        // (the page drawn: one on its way out hands no actions to the system's bars)
        drawn_page.val = Some(page)
        if top {
          top_drawn.val = true
        }
        let (now, _, _, _) = @sfbase.workspace_in_view(src)
        main_page(c, src, now.unwrap_or(w), page)
        drawn_page.val = None
      })
      @motion.scope(c, moved, bottom=true)
    }
    c.selectable(color=@sf.alpha(@sf.theme().p.blue, 0.28), body)
  })
}

///|
/// Page `page` of the pane off the tape (Large), its island's (the room the tree leaves the stack beside the block's
/// column): the page's bars' room where the block's move has got (page_bar_room), the page moved aside as the block is
/// shown a while; the top's what the page shows across as it is laid out (fold_peek_shift reads it).
fn pane_page_one(c : @ui.Ctx, src : Source, page : Page) -> Unit {
  let (now, _, _, _) = @sfbase.workspace_in_view(src)
  guard now is Some(w) else { return }
  let (_, target) = fold_target(src, w, c.window_size().0)
  let f = fold_built(c, target)
  fold_bars(c, f)
  // (the page shown in the pane, whether the one on top or the one kept while that waits: the one page built here)
  let page_id = c.id("main-page")
  // (said by this build: image_item, video_item)
  @sfbase.held_pictures_waiting.val = []
  fold_goes.page_id = page_id
  // (what the page shows across as it is laid out, its bars left out: where the page moves aside to as the folded
  // sidebar is shown a while, taken as that starts: fold_peek_shift)
  c.shown_across(page_id, but="page-bar") |> ignore
  // a right click in it: what is picked copied (context_menu.mbt)
  context_page(c, page_id)
  let pane = c.box(style=frame_main.then(@ui.style(w=Fixed(c.width))), id=page_id, fn() {
    page_one(c, src, w, page, c.width, c.height, f.aside)
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
fn pane_pages(v : @view.View, src : Source, tips : @sf.TipLayer) -> Unit {
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
    pane_stack(s, src, tips)
  })
  |> ignore
}

///|
/// What waits to be confirmed in the workspace's safe mode, in the pane off the tape (its island).
fn pane_gate_built(c : @ui.Ctx, src : Source) -> Unit {
  let (now, _, _, _) = @sfbase.workspace_in_view(src)
  guard now is Some(w) else { return }
  let (_, target) = fold_target(src, w, c.window_size().0)
  fold_bars(c, fold_built(c, target))
  if @ui.window_inset() {
    title_row(c, "page-title-row", @sf.wide_bar_h)
  }
  c.box(style=frame_gate.then(@ui.style(w=Fixed(c.width), h=Fixed(c.height))), fn() {
    let core = settings_core(src, w)
    @sfpages.lock_wait_page(c, core, @settings.here_of(core, w.id, w.name))
    // (the workspace's button over the page where the system's tabs are the rail: gate_heading)
    if @sf.native_on() {
      c.layer(fn() { gate_heading(c, src, w) }) |> ignore
    }
  })
  |> ignore
}

///|
/// The workspace's button (its icon and name in the system's glass: chats.mbt workspace_heading, the bars'
/// workspace-switch) over the top of the page that waits, where the sidebar's head would have it: the sidebar is not
/// shown while the device waits, and where the rail's places are the system's tabs those hold no workspaces, so with
/// nothing to switch with a person was held in the workspace until a trusted device approved this one (the user,
/// 2026-11-03; the web's SecurityWaiting keeps its WorkspaceSwitcher over the page, cloud/workspace.tsx Bare). The
/// rail has the workspaces where it is the app's own, the narrow frame's Home bar its switch (sfapp lock_gate).
fn gate_heading(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let list = @sf.theme().chat_list
  let inset = list.band_in + list.heading_in
  let top = @ui.system_bars().top + side_top_web + band_new_top
  let width = dmin(dmax(side_min, wide.side_w.get()), c.width - @sf.native_clear() - 2.0 * inset)
  c.box(style=@ui.style(w=Fixed(width), h=Fixed(@sf.band_row_h())), left=inset, top=top, fn() {
    workspace_heading(c, src, w)
  })
  |> ignore
}

///|
fn pane_stack(v : @view.View, src : Source, tips : @sf.TipLayer) -> Unit {
  @ui.nav_flat_view(
    v,
    app.nav,
    fn(c, p) { pane_page_one(c, src, p) },
    fn(p) { (fold_goes.ready)(p) },
    fold_goes.most,
    bg=fn() { @sf.theme().p.bg },
    stacks=fn() { false },
    page_for=fn(entry, serial) {
      let retained = @sfbase.page_entry_source(src, entry, serial)
      let page_read = @sfbase.page_chat_reader(retained, entry, serial)
      fn(visible) {
        let shown = src.owned_by(visible)
        fn(c, page) {
          @sfbase.page_entry_read(serial, retained, page)
          page_read(page)
          pane_page_one(c, if page is Chat(_) { retained } else { shown }, page)
        }
      }
    },
    page_key=fn(_) { tape_island_key() },
    // (a page of the library's made once in its place: 关于)
    made=fn(p) { pane_made(src, p, tips) },
    // (which show, as the stack stands whole: the page made once that shows, by its entry)
    shown=fn(ks) { fold_goes.shown = ks },
  )
  |> ignore
}

///|
/// The pages of the library's made once as nodes in the pane off the tape (Large), in the place of their old view
/// (nav_flat_view's `made`): 关于, 记忆, 更新日志, 一台 station 的记忆; 归档, a station's own archiving, 自动决策; 用量,
/// 价目表; a chat (and the new chat that becomes it), its old view in it as yet (chat_page_made). Laid out by the width the frame gives the pane (the window's less the block's column where its move goes:
/// fold_target's, never what the page last laid out), narrow or wide (page_node), each made again only as that
/// arrangement changes. What the old view's island did for the page done by its node (pane_made_host).
fn pane_made(
  src : Source,
  page : Page,
  tips : @sf.TipLayer,
) -> (String, (@view.View, () -> Page, Page?, () -> Int, Int) -> Unit)? {
  guard pane_makes.val else { return None }
  // (made in the workspace in view, its settings' core, under what it was opened from, as wide as the frame gives it)
  let made = fn(
    kind : String,
    f : (@view.View, @settings.Core, () -> @settings.Here, () -> Int, () -> @sf.PageFrame, () -> Double) -> Unit,
  ) {
    Some(
      (
        kind,
        fn(v : @view.View, page : () -> Page, under : Page?, stint : () -> Int, k : Int) {
          v.pick(fn() { @sfbase.workspace_in_view(src).0.map(fn(w) { w.id }) }, fn(p, _id) {
            guard @signals.untracked(fn() { @sfbase.workspace_in_view(src).0 }) is Some(w) else { return }
            let core = settings_core(src, w)
            let here = fn() { @settings.here_of(core, w.id, w.name) }
            @settings.frame(core, @signals.untracked(here))
            // (a dialog a fixture's mode puts up over its page, before the page is made: setting_page's)
            settings_fixture(src, core)
            pane_made_host(p, src, k)
            // (back over it only under another settings page or a place of the rail's: setting_page's; a place of the
            // rail's itself, none, whatever is under it: place_page's; its words read as they are said, in the
            // language now)
            let frame = fn() -> @sf.PageFrame {
              {
                back: match (page(), under) {
                  (Place(_), _) => None
                  (_, Some(u)) if u is (Setting(_) | Place(_)) => Some(@sfbase.back_label(u))
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
              f(a, core, here, stint, frame, width)
            })
            |> ignore
          })
        },
      ),
    )
  }
  match page {
    Setting(About) =>
      made("about", fn(a, core, _here, _stint, frame, width) {
        @sfpages.about_node(a, core, on_back=core.pop, frame~, width~)
      })
    Setting(Memories) =>
      made("memories", fn(a, core, here, _stint, frame, width) {
        @sfpages.memories_node(a, core, here, on_back=core.pop, frame~, width~)
      })
    Setting(Changelog) =>
      made("changelog", fn(a, core, _here, _stint, frame, width) {
        @sfpages.changelog_node(a, core, on_back=core.pop, frame~, width~)
      })
    // (the profiles' place: the profile picked in its list, made once as its page is; none to pick yet, the first to add)
    Place("profiles") =>
      made("place/profiles", fn(a, core, here, stint, frame, width) {
        profiles_place_node(a, src, core, here, stint, frame, width, tips~)
      })
    // (the stations' place with one that only runs tasks picked: its page made once, in the place of the old view's)
    Place("stations") if place_rig(src) != "" =>
      pane_made(src, Setting(Station(place_rig(src))), tips).map(fn(m) { ("place/" + m.0, m.1) })
    // (a place of the rail's whose page is one of those: that page, at the stack's root (no back over it, place_page's),
    // made under its own kind)
    Place(name) =>
      match @settings.route_of(name) {
        // (those whose old view is gone: every frame makes them once, as a page or a place)
        Some(r) if @settings.made_once(r) =>
          pane_made(src, Setting(r), tips).map(fn(m) { ("place/" + m.0, m.1) })
        _ => None
      }
    // (by its station: another station's another page, not this one become it)
    Setting(Memory(address)) =>
      made("memory/" + address, fn(a, core, here, _stint, frame, width) {
        @sfpages.memory_node(a, core, here, address, on_back=core.pop, frame~, width~, tips~)
      })
    Setting(Archiving) =>
      // (its pictures asked for again each time it is come back to, not each frame it stays: nav_flat_view's stint)
      made("archiving", fn(a, core, here, stint, frame, width) {
        @sfpages.archiving_node(a, core, here, on_back=core.pop, frame~, stint~, width~)
      })
    Setting(AutoDecisions) =>
      made("auto-decisions", fn(a, core, here, _stint, frame, width) {
        @sfpages.decisions_node(a, core, here, on_back=core.pop, frame~, width~, tips~)
      })
    // (by its station: another station's another page, not this one become it)
    Setting(StationArchiving(st)) =>
      made("station-archiving/" + st, fn(a, core, here, _stint, frame, width) {
        @sfpages.station_archiving_node(a, core, here, st, on_back=core.pop, frame~, width~)
      })
    Setting(Shortcuts) =>
      // (recording while it is the one on top of the stack: its stay there, stint's)
      made("shortcuts", fn(a, core, _here, stint, frame, width) {
        @sfpages.shortcuts_node(a, core, on_back=core.pop, frame~, active=fn() { app.nav.top_stay().1 == stint() }, width~)
      })
    Setting(Notifications) =>
      // (a workspace's picture asked for again each time it is come back to: nav_flat_view's stint)
      made("notifications", fn(a, core, here, stint, frame, width) {
        @sfpages.notify_node(a, core, here, on_back=core.pop, frame~, stint~, width~)
      })
    // (by its station, skill and the part first shown: another's another page)
    Setting(MemoryDoc(address, skill, at)) =>
      made("memory-doc/" + address + "/" + skill + "/" + at.to_string(), fn(a, core, here, _stint, frame, width) {
        @sfpages.memory_doc_node(a, core, here, address, skill, at, on_back=core.pop, frame~, width~)
      })
    Setting(AutoPolicy(st)) =>
      made("auto-policy/" + st, fn(a, core, here, _stint, frame, width) {
        @sfpages.policy_node(a, core, here, st, on_back=core.pop, frame~, width~)
      })
    Setting(Appearance) =>
      made("appearance", fn(a, core, _here, _stint, frame, width) { @sfpages.appearance_node(a, core, on_back=core.pop, frame~, width~) })
    // (by its station and id: another's another page)
    Setting(Profile(address, id)) =>
      made("profile/" + address + "/" + id, fn(a, core, here, stint, frame, width) {
        @sfpages.profile_node(a, core, here, address, id, on_back=core.pop, frame~, width~, tips~, stint~)
      })
    Setting(NewProfile(address)) =>
      made("new-profile/" + address, fn(a, core, here, _stint, frame, width) {
        @sfpages.new_profile_node(a, core, src, here, address, on_back=core.pop, frame~, width~, tips~)
      })
    Setting(LocalStation) =>
      made("local-station", fn(a, core, _here, _stint, frame, width) {
        @sfpages.local_station_node(a, core, on_back=core.pop, frame~, width~)
      })
    // (by its station: another station's another page, not this one become it)
    Setting(Station(address)) =>
      made("station/" + address, fn(a, core, here, stint, frame, width) {
        @sfpages.station_node(a, core, here, address, on_back=core.pop, frame~, width~, stint~)
      })
    Setting(Permissions) =>
      made("permissions", fn(a, core, _here, _stint, frame, width) {
        @sfpages.permissions_node(a, core, on_back=core.pop, frame~, width~)
      })
    Setting(Security) =>
      made("security", fn(a, core, here, stint, frame, width) {
        @sfpages.security_node(a, core, here, on_back=core.pop, frame~, stint~, width~)
      })
    Setting(SecurityOpen) =>
      made("security-open", fn(a, core, here, _stint, frame, width) {
        @sfpages.security_open_node(a, core, here, on_back=core.pop, frame~, width~)
      })
    Setting(Workspace) =>
      made("workspace", fn(a, core, here, stint, frame, width) {
        @sfpages.workspace_node(a, core, here, on_back=core.pop, frame~, stint~, width~, tips~)
      })
    Setting(VaultItems) =>
      made("vault-items", fn(a, core, here, _stint, frame, width) {
        @sfpages.vault_items_node(a, core, here, on_back=core.pop, frame~, width~, tips~)
      })
    // (by its station and id: another's another page)
    Setting(Connects(only)) =>
      made("connects/" + only, fn(a, core, here, stint, frame, width) {
        @sfpages.connects_node(a, src, core, here, only, on_back=core.pop, frame~, stint~, width~, tips~)
      })
    Setting(Connect(station, id)) =>
      made("connect/" + station + "/" + id, fn(a, core, here, stint, frame, width) {
        @sfpages.connect_node(a, src, core, here, station, id, on_back=core.pop, frame~, stint~, width~, tips~)
      })
    Setting(AutoCompletion) =>
      made("auto-completion", fn(a, core, here, _stint, frame, width) {
        @sfpages.completion_node(a, core, here, on_back=core.pop, frame~, width~, tips~)
      })
    Setting(Usage) =>
      made("usage", fn(a, core, here, _stint, frame, width) {
        @sfpages.usage_node(a, core, src, here, on_back=core.pop, frame~, width~, tips~)
      })
    // (by its days: another's of other days another page)
    Setting(UsagePrices(days)) =>
      made("usage-prices/" + days.to_string(), fn(a, core, here, _stint, frame, width) {
        @sfpages.usage_prices_node(a, core, here, days, on_back=core.pop, frame~, width~)
      })
    // (a chat, and the new chat that becomes one in place: the same page, a node of the tree's, its old view in it as
    // yet, built as the stack's island built it: pane_page_one)
    page if @sfbase.chat_page_is(page) =>
      Some(
        (
          "chat",
          fn(v, _page, _under, stint, k) {
            // (beside it its side panel, the tree's, reading by the page's source, let go with it: side_panel_node)
            v.row(Is(true)).grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
            let page_src : Ref[Source] = Ref(src)
            v.box(fn(p) {
              p.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))) |> ignore
              // (its bar the tree's, over the page's old view: chat_bar_wide_node, keeping clear of the window's corner)
              page_src.val = @sfbase.chat_page_made(
                p,
                src,
                k,
                pane_page_one,
                key=tape_island_key,
                drawn=fn(serial) { pane_page_wait.draws(serial) },
                over=fn(o, src, page, stint) {
                  chat_bar_wide_node(o, src, page, pane_chat_bar_ends(src, o), tips, stint)
                },
                // (with chat_page_nodes on: its messages nodes, its composer in their list's foot its old view)
                body=fn(col, s, r, composer, shows) {
                  pane_made_chat(col, src, k)
                  chat_body_nodes(col, s, r, tips, stint, composer, shows)
                },
                // (the composer's old view on the page's way to another width as the side panel slides beside it, as the
                // old page's was inside its with_side: its foot's room across the way, not stepped where it crosses its
                // width, composer_foot_in)
                foot=fn(c, s, r) {
                  match @sfbase.workspace_in_view(s).0 {
                    Some(w) => with_side(c, s, w, r, fn() { chat_composer_nodes(c, s, r, wide.tape.get()) })
                    None => chat_composer_nodes(c, s, r, wide.tape.get())
                  }
                },
                // (its column on the page's way as the side panel slides beside it: laid out as at its narrower end)
                narrower=fn(n) { side_narrower(src, n, k) },
              )
            })
            |> ignore
            side_panel_node(v, page_src.val, k, tips)
          },
        ),
      )
    _ => None
  }
}

///|
/// Where a chat's bar in the pane off the tape keeps clear at its ends (chat_bar_wide_node's, node `n` its page's): as a
/// page's bar there (page_bar_room), where the block's move has it as the bar is drawn (fold_along's, as
/// pane_aside_at's): its start past the rail and the window's buttons as the block is closed, its margins while it is
/// shown a while; its end at the window's corner while no panel is open beside it (window_end_in: its buttons'
/// corner the window's, followed), clear of a corner too square for ⌘F's field (a capsule: window_corner_past), the
/// bar's own padding beside a panel.
fn pane_chat_bar_ends(src : Source, n : @view.View) -> ChatBarEnds {
  let look = fn() {
    match @sfbase.workspace_in_view(src).0 {
      Some(w) => {
        let (_, now) = fold_target(src, w, n.window().0)
        Some(fold_along(fold_drawn_at(n), now))
      }
      None => None
    }
  }
  {
    over: fn() { 0.0 },
    // (as the old view's were, drawn in the page moved aside: page_one's `aside`, which the bar over it is not)
    margins: fn() {
      match look() {
        Some(f) => (f.bar_ml + f.aside, f.bar_mr - f.aside)
        None => (0.0, 0.0)
      }
    },
    start: fn() {
      match look() {
        Some(f) => f.bar_pl
        None => 0.0
      }
    },
    end: fn(beside, finding) {
      if beside {
        bar_in
      } else if finding {
        if @ui.window_keys_own() {
          @sf.window_keys_room(roots=@ui.tree_corner_roots_now()) + bar_in
        } else {
          @sf.window_corner_past(bar_in, roots=@ui.tree_corner_roots_now())
        }
      } else {
        @sf.window_end_in(bar_in, roots=@ui.tree_corner_roots_now())
      }
    },
    linked: fn() { if @ui.window_keys_own() { None } else { Some(@sf.window_corner_key()) } },
    ground: fn(_) { @sf.theme().p.bg },
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
  .offset(By(fn() { (pane_aside_at(src, p), 0.0) }))
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

///|
/// What page_one did for a chat's page in its island, done for entry `k`'s chat made as nodes, its messages' column
/// `col` (chat_body_nodes', the composer in it): moved aside as the folded sidebar is shown a while, where the block's
/// move has got (its bar over it keeps its ends by the same: pane_chat_bar_ends), and what it shows across read of it as
/// that starts, while its entry shows (fold_goes' `made`), the one kept while the one on top waits too.
fn pane_made_chat(col : @view.View, src : Source, k : Int) -> Unit {
  col.offset(By(fn() { (pane_aside_at(src, col), 0.0) })) |> ignore
  fold_goes.made[k] = col
  col.owns(fn() {
    match fold_goes.made.get(k) {
      Some(v) if v.id() == col.id() => fold_goes.made.remove(k)
      _ => ()
    }
  })
  |> ignore
}

///|
/// How far the page in the pane off the tape is moved aside as node `n` is drawn (the folded block shown a while over
/// it), where the block's move has it then.
fn pane_aside_at(src : Source, n : @view.View) -> Double {
  match @sfbase.workspace_in_view(src).0 {
    Some(w) => {
      let (_, now) = fold_target(src, w, n.window().0)
      fold_along(fold_drawn_at(n), now).aside
    }
    None => 0.0
  }
}

///|
/// How wide the pane off the tape is as node `n` is drawn: the window's less the block's column, where the block's move
/// has it then.
fn pane_w_at(src : Source, n : @view.View) -> Double {
  let ww = n.window().0
  match @sfbase.workspace_in_view(src).0 {
    Some(w) => {
      let (_, now) = fold_target(src, w, ww)
      ww - fold_along(fold_drawn_at(n), now).col
    }
    None => ww
  }
}
