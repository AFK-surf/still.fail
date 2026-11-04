// A chat's header in the wide frame, made once. Its title, people, agents, find field and actions follow their
// data; only the independent bodies opened by its controls are still hosted old views.

///|
/// The system's own navigation bar is the host boundary: hand it the same chat actions at each published frame.
/// The independent archive confirmation still belongs to the page's presenter.
fn chat_bar_host(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, view : ChatView?, chat : Json?) -> Unit {
  if native_turned(c, info_width) {
    chat_own.info_open.set(false)
    chat_own.jobs_open.set(false)
  }
  match view {
    Some(v) => {
      let extra = @sfpages.chat_extra_items(src, r, chat)
      let rows = if @sf.native_on() { @sfpages.chat_menu_of(src, w.id, r, extra) } else { [] }
      let more = fn() {
        let (from, along) = bar_menu_from(c, c.id("chat-more"))
        @sfpages.open_chat_menu(src, w.id, r, extra, from~, along~)
      }
      let screen = if v.screens.length() > 0 {
        Some((fn() {
          let (from, along) = bar_menu_from(c, c.id("chat-screen"))
          chat_screens_open(r, v.screens, from~, along~)
        }, chat_screens_driven(v.screens)))
      } else { None }
      let jobs_view = (src.topic)("chatJobs", chat_jobs_summary_params(r)).value
      let jobs = if flag(jobs_view, "hasJobs") || items(jobs_view, "jobs").length() > 0 {
        Some((jobs_toggle, text(jobs_view, "alarm") != ""))
      } else { None }
      bar_chat(src, r, v.agents,
        fn() { chat_own.info_open.set(!@signals.untracked(fn() { chat_own.info_open.get() })) },
        rows, more, jobs, screen,
        if v.archivable && !v.archived { Some(fn() { c.tell("chat/archive", fn() { archive_asked(src, w, r, v, chat) }) }) } else { None }) |> ignore
    }
    None => bar_chat_waiting() |> ignore
  }
  chat_archive_confirm(c, src, w, r, view, chat)
}

///|
fn jobs_toggle() -> Unit {
  chat_own.jobs_open.set(!@signals.untracked(fn() { chat_own.jobs_open.get() }))
}

///|
fn chat_bar_node(parent : @view.View, src : Source, w : Workspace, r : ChatRef, stint : Int,
  view : () -> ChatView?, width : () -> Double, corners : () -> FixedArray[@ui.CornerOf]?,
  ground : (@view.View) -> Int64) -> Unit {
  let chat = fn() { (src.topic)("chat", chat_params(r)).value }
  let station = fn() {
    stations_of((src.topic)("stations", { "scope": Json::string(w.id) }).value)
    .iter().find_first(fn(s) { s.address == r.station })
  }
  let finding = fn() { find_chat() == chat_key(r) && view().map_or(false, fn(v) { v.thread is Some(_) }) }
  let native = fn() { @sf.native_on() }
  let jobs = fn() { (src.topic)("chatJobs", chat_jobs_summary_params(r)).value }
  let popup = @sf.popup_root_node(parent)
  let tips = @sf.TipLayer::new(fn() { Some(popup) })
  let info_at : Ref[@view.View?] = Ref(None)
  let jobs_at : Ref[@view.View?] = Ref(None)
  let room = fn(p : @view.View, n : () -> Double) {
    p.box(fn(s) { s.width(By(fn() { Some(n()) })).shrink(Is(0.0)) |> ignore }) |> ignore
  }
  parent.box(fn(row) {
    pane_bar_made(row)
    row.over(Is(true)).width_share(Is(1.0)).row(Is(true)).moves_window(By(@ui.window_inset_now))
    .height(By(fn() { Some(@sf.wide_bar_h + (if corners() is Some(_) { @sf.tape_bar_over() } else { 0.0 })) }))
    .offset(By(fn() { (dmin(0.0, page_bar_room().2), 0.0) })) |> ignore
    room(row, fn() { dmax(0.0, page_bar_room().2) })
    row.box(fn(bar) {
      bar_fills(bar.row(Is(true)).lines_up(Is(Some(Middle))))
      .height_share(Is(1.0)).ground(By(fn() { ground(bar) }))
      .padding(By(fn() { (0.0, if corners() is Some(_) { @sf.tape_bar_over() } else { 0.0 }, 0.0, 1.0) }))
      |> ignore
      room(bar, fn() { page_bar_room().0 })
      bar.box(fn(inner) {
        bar_fills(inner.row(Is(true)).lines_up(Is(Some(Middle)))).gap(Is(@ui.Space::px(S4))) |> ignore
        inner.box(fn(title) {
          bar_fills(title.row(Is(true)).lines_up(Is(Some(Middle))))
          .padding(Is((@ui.Space::px(S2), 0.0, @ui.Space::px(S1), 0.0)))
          .gap(Is(@ui.Space::px(S2_5))).fits(Is(true)) |> ignore
          chat_title_node(title, src, r, view, width, tips)
          title.show(fn() { view().map_or(false, fn(v) { v.agents.length() == 0 }) && station() is Some(_) }, fn(s) {
            chat_station_node(s, r.station, fn() { station().unwrap() }, fn() { stint })
          })
          let people = fn() { view().map(fn(v) { v.people }).unwrap_or([]) }
          title.show(fn() { people().length() > 0 }, fn(p) {
            p.drops(Is(chat_bar_drop_people)) |> ignore
            people_stack_node(p, src, people, 5, fn() { stint }, tips)
          })
          let agents = fn() { view().map(fn(v) { v.agents }).unwrap_or([]) }
          title.each(fn() { agents().map(fn(a) { a.key }) }, fn(a) { a }, fn(tile, key) {
            let first = fn() { agents().length() > 0 && agents()[0].key == key.get() }
            tile.drops(By(fn() { if first() { 0 } else { chat_bar_drop_agents } })) |> ignore
            let initial = @signals.untracked(fn() { agents().iter().find_first(fn(a) { a.key == key.get() }).unwrap() })
            agent_tile_node(tile, src, r,
              fn() { agents().iter().find_first(fn(a) { a.key == key.get() }).unwrap_or(initial) },
              fn() { view().map_or(false, fn(v) { v.agents.length() > 1 && side_of(v).1 == key.get() }) },
              fn() { if first() { station() } else { None } }, fn() { stint }, fn() { ground(tile) })
          })
        }) |> ignore
        inner.show(finding, fn(f) {
          guard @signals.untracked(view) is Some(v) && v.thread is Some(th) else { return }
          @sfpages.find_bar_node(f, src, r, th, chat_find_list(r), tips) |> ignore
        })
        inner.show(fn() { !finding() && view() is Some(_) }, fn(keys) {
          keys.row(Is(true)).gap(By(fn() { @sf.keys_apart() })).lines_up(Is(Some(Middle))) |> ignore
          let button = fn(p : @view.View, icon : String, label : String, press : () -> Unit) {
            @sf.icon_button_node(p, icon, fn() { @sf.t(label) }, press, tips~)
            .radius(By(fn() {
              if corners() is Some(_) || @ui.window_keys_own() { @sf.bar_key_side / 2.0 }
              else { @sf.window_corner_key().radius(@ui.tree_corner_roots_now()) }
            }))
          }
          keys.show(fn() { !native() && view().map_or(false, fn(v) { v.archivable && !v.archived }) }, fn(a) {
            button(a, "archive", "web-pages.chat.archive", fn() {
              match view() { Some(v) => archive_asked(src, w, r, v, chat()); None => () }
            }) |> ignore
          })
          keys.show(fn() { (!native() || column_short.get()) && (flag(jobs(), "hasJobs") || items(jobs(), "jobs").length() > 0) }, fn(j) {
            let b = button(j, "web", "web-pages.chat.services", jobs_toggle)
            jobs_at.val = Some(b)
            j.owns(fn() { jobs_at.val = None }) |> ignore
            chat_key_dot_node(j, fn() { text(jobs(), "alarm") }, fn() { ground(j) })
          })
          keys.show(fn() { (!native() || column_short.get()) && view().map_or(false, fn(v) { v.screens.length() > 0 }) }, fn(s) {
            button(s, "monitor", "web-pages.chat.screen", fn() {
              match view() { Some(v) => {
                let (x, y, ww, hh) = s.placed_window_now()
                chat_screens_open(r, v.screens, from=At(x, y, ww, hh))
              }; None => () }
            }) |> ignore
            chat_key_dot_node(s, fn() { if view().map_or(false, fn(v) { chat_screens_driven(v.screens) }) { "restart" } else { "" } }, fn() { ground(s) })
          })
          keys.show(fn() { !native() }, fn(ours) {
            ours.row(Is(true)).gap(By(fn() { @sf.keys_apart() })) |> ignore
            let b = button(ours, "info", "web-pages.chat.info", fn() {
              chat_own.info_open.set(!@signals.untracked(fn() { chat_own.info_open.get() }))
            })
            info_at.val = Some(b)
            ours.owns(fn() { info_at.val = None }) |> ignore
            ours.box(fn(m) {
              button(m, "more", "common.more", fn() {
                let (x, y, ww, hh) = m.placed_window_now()
                @sfpages.open_chat_menu(src, w.id, r, @sfpages.chat_extra_items(src, r, chat()), from=At(x, y, ww, hh))
              }) |> ignore
            }) |> ignore
            ours.show(fn() { view().map_or(false, fn(v) { side_of(v).0.length() == 0 && v.agents.length() > 0 }) }, fn(p) {
              button(p, "panel-open", "web-pages.chat.openPanel", fn() {
                match view() { Some(v) if v.agents.length() > 0 => side_change(src, r, "open", Some(v.agents[0].key)); _ => () }
              }) |> ignore
            })
          })
        })
      }) |> ignore
      room(bar, fn() {
        match corners() {
          Some(ks) => @sf.tape_bar_end_of(ks, @ui.tree_corner_roots_now(), bar_in,
            side=if finding() { @sfpages.find_field_h } else { @sf.bar_key_side })
          None => if view().map_or(false, fn(v) { side_of(v).0.length() > 0 }) { bar_in }
            else if finding() { @sf.window_clear_in(bar_in) } else { page_bar_room().1 }
        }
      })
    }) |> ignore
    room(row, fn() { let (_, _, ml, mr) = page_bar_room(); mr + dmin(0.0, ml) })
  }) |> ignore
  let active = fn() { app.nav.drawn_stay().0 == stint && view() is Some(_) }
  popup.pick(fn() { (@sf.native_side(), column_short.get()) }, fn(layer, arrangement) {
    let (from_side, short) = arrangement
    // This branch chooses the window layer's anchor; it must keep the window's room for the panel beside it.
    layer.over(Is(true)) |> ignore
    let at = fn(p : @view.View) {
      if @sf.native_on() && native_mark.val != 0 { @ui.old_anchor(p, native_mark.val, (0.0, 0.0, 0.0, 0.0)) }
      else { info_at.val.unwrap_or(parent) }
    }
    @sf.panel_by_node(layer, "chat-info/" + chat_key(r), fn() { active() && chat_own.info_open.get() }, at,
      fn(c, _) { match view() { Some(v) => chat_info(c, src, w, r, v, chat()); None => () } },
      fn() { chat_own.info_open.set(false) }, w=chat_info_w,
      side=if from_side { Left } else { Bottom }, along=if from_side { Start } else { End })
    @sf.panel_by_node(layer, "chat-jobs/" + chat_key(r), fn() { active() && chat_own.jobs_open.get() },
      fn(p) {
        if @sf.native_on() && !column_short.get() && native_mark.val != 0 {
          @ui.old_anchor(p, native_mark.val, (0.0, 0.0, 0.0, 0.0))
        } else { jobs_at.val.unwrap_or(parent) }
      }, fn(c, close) {
        let go = fn(id : String) { close(); if id != "" { pick_job(id) }; side_change(src, r, "open", Some("jobs")) }
        jobs_popover(c, src, r.station, (src.topic)("chatJobs", chat_params(r)).value, go, go)
      }, fn() { chat_own.jobs_open.set(false) }, w=jobs_pop_w,
      side=if from_side && !short { Left } else { Bottom },
      along=if from_side && !short { Start } else { End })
  })
}

///|
fn chat_title_node(parent : @view.View, src : Source, r : ChatRef, view : () -> ChatView?, width : () -> Double, tips : @sf.TipLayer) -> Unit {
  let on = [("station", r.station), ("session", r.session)]
  let renaming = fn() {
    items((src.topic)("doing", {}).value, "doing").iter().find_first(fn(d) {
      text(Some(d), "call") == "chat.rename" && text(Some(d), "stage") != "failed" &&
        on.iter().all(fn(kv) { text(field(Some(d), "params"), kv.0) == kv.1 })
    }).map(fn(d) { text(field(Some(d), "params"), "title") }).unwrap_or("")
  }
  parent.box(fn(t) {
    t.words(By(fn() { if renaming() != "" { renaming() } else { view().map(fn(v) { v.title }).unwrap_or(r.title) } }))
    .words_look(By(fn() { @ui.style_words(chat_title_words) })).ink(By(fn() { @ui.style_ink(chat_title_words) }))
    .max_width(By(fn() { Some(dmax(chat_title_least, width() * chat_title_part)) }))
    .cuts(Is(true), keep=true).allow_ellipsis(Is(true)) |> ignore
  }) |> ignore
  let failed = fn() { core_failed(src, ["chat.rename"], on) }
  parent.show(fn() { renaming() != "" || failed() is Some(_) }, fn(mark) {
    mark.points(Is(true)) |> ignore
    mark.show(fn() { renaming() != "" }, fn(s) { @sf.spinner_node(s) |> ignore })
    mark.show(fn() { renaming() == "" && failed() is Some(_) }, fn(f) {
      @sf.icon_node(f, "info", 14.0, By(fn() { @sf.theme().p.red })) |> ignore
    })
    @sf.tip_node(tips, mark, fn() { failed().unwrap_or(@sf.t("web-pages.settings.stations.renaming")) }) |> ignore
  })
}

///|
fn people_stack_node(parent : @view.View, src : Source, people : () -> Array[Person], most : Int,
  stint : () -> Int, tips : @sf.TipLayer) -> Unit {
  parent.row(Is(true)).lines_up(Is(Some(Middle))).points(Is(true)) |> ignore
  let shown = fn() { let all = people(); if all.length() > most { all[:most].to_owned() } else { all } }
  parent.each(fn() { shown().map(fn(p) { p.id }) }, fn(id) { id }, fn(ring, id) {
    let first = @signals.untracked(fn() { shown().iter().find_first(fn(p) { p.id == id.get() }).unwrap() })
    let p = fn() { shown().iter().find_first(fn(p) { p.id == id.get() }).unwrap_or(first) }
    ring.width(Is(Some(19.0))).height(Is(Some(19.0))).radius(Is(9.5))
    .margin(By(fn() { (if shown().length() > 0 && shown()[0].id == p().id { -1.5 } else { -7.0 }, 0.0, 0.0, 0.0) }))
    .ground(By(fn() { @sf.theme().p.sidebar })).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
    ring.show(fn() { p().picture != "" }, fn(face) {
      @sf.avatar_node(face, fn() { p().id }, fn() { p().display }, fn() { (src.picture)(p().picture, stint()) }, person_side)
    })
    ring.show(fn() { p().picture == "" }, fn(face) {
      face.width(Is(Some(person_side))).height(Is(Some(person_side))).radius(Is(person_side / 2.0))
      .ground(By(fn() { @sf.theme().p.paper })).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
      bar_words(face, fn() { person_initial(p().display) }, people_letter, fn() { 1000.0 })
    })
  })
  parent.show(fn() { people().length() > most }, fn(m) {
    m.padding(Is((@ui.Space::px(S1_5), 0.0, 0.0, 0.0))) |> ignore
    bar_words(m, fn() { "+\{people().length() - most}" }, people_more, fn() { 1000.0 })
  })
  @sf.tip_node(tips, parent, fn() { @sf.t("web-main.people.in", args=[("names", people().map(fn(p) { p.display }).join(@sf.t("web-main.list.separator")))]) }) |> ignore
}

///|
fn chat_station_node(parent : @view.View, address : String, station : () -> Station, stint : () -> Int) -> Unit {
  parent.row(Is(true)).max_width(Is(Some(160.0))).gap(Is(4.0)).radius(Is(1000.0)).clips(Is(true))
  .lines_up(Is(Some(Middle))).padding(By(fn() { (if station().via != "" { chat_station_dot_in } else { @ui.Space::px(@sf.chat_station_in) }, 1.0, @ui.Space::px(@sf.chat_station_in), 1.0) }))
  .edge(By(fn() { (1.0, @ui.tree_theme().color(if parent.pointed() { Border } else { Line })) }))
  .says(By(fn() { Some(@view.said(Button, label=station().name)) })) |> ignore
  @sfpages.hover_node(parent, "bar-station/" + address, fn(c) { @settings.station_peek_card(c, address) }, tile=true, padded=false) |> ignore
  @sf.presses_node(parent, fn() {
    if !@sf.pointer_rests() {
      let (x, y, w, h) = parent.placed_window_now()
      @settings.open_station_peek(address, from=At(x, y, w, h))
    }
  })
  parent.show(fn() { station().via != "" }, fn(d) { chat_via_dot_node(d, fn() { station().via }, via_dot_side, 0.0) })
  parent.show(fn() { @sf.has_station_mark(station().emoji, station().icon) }, fn(m) {
    @sf.station_mark_node(m, fn() { station().emoji }, fn() { station().icon }, chat_station_mark, fn() { @sf.theme().p.muted }, stint)
  })
  bar_words(parent, fn() { station().name }, chat_station_words, fn() { 1000.0 })
}

///|
fn chat_via_dot_node(parent : @view.View, via : () -> String, size : Double, ring : Double,
  ground? : () -> Int64 = fn() { @ui.tree_theme().color(Bg) }) -> Unit {
  parent.width(Is(Some(size))).height(Is(Some(size))).radius(Is(size / 2.0))
  .ground(By(fn() {
    @ui.tree_theme().color(match via() { "direct" => Positive; "relay" => Warn; "offline" => Danger; _ => Muted })
  }))
  .edge(By(fn() { (ring, ground()) })) |> ignore
}

///|
fn agent_tile_node(parent : @view.View, src : Source, r : ChatRef, agent : () -> Agent,
  marked : () -> Bool, station : () -> Station?, stint : () -> Int, ground : () -> Int64) -> Unit {
  let aj = fn() { agent_json((src.topic)("chat", chat_params(r)).value, agent().key) }
  let said = fn() { @sf.t("web-pages.chat.historyOf", args=[("agent", agent().who)]) }
  let whole = fn() { station() is Some(_) && @sf.tile_whole() }
  let key = @signals.untracked(fn() { chat_key(r) + "/" + agent().key })
  let open = fn() { side_toggle(src, r, agent().key) }
  parent.row(Is(true)).height(Is(Some(20.0))).radius(Is(agent_station_round))
  .ground(By(fn() { @ui.tree_theme().color(Neutral) }))
  .edge(By(fn() { (if marked() { 2.0 } else { 0.0 }, @sf.theme().p.accent) })) |> ignore
  parent.box(fn(maker) {
    maker.width(Is(Some(20.0))).height(Is(Some(20.0))).lines_up(Is(Some(Middle))).lies_along(Is(Middle))
    .radius(Is(agent_station_round))
    .corners(By(fn() { if station() is Some(_) { Some((agent_station_round, 0.0, 0.0, agent_station_round)) } else { None } }))
    .ground(By(fn() { if maker.pointed() || maker.pressed() { @ui.tree_theme().color(Hover) } else { 0L } }))
    .says(By(fn() { if whole() { None } else { Some(@view.said(Button, label=said())) } })) |> ignore
    @sf.maker_mark_node(maker, fn() { agent().maker }, fn() { agent().runtime }, 12.0) |> ignore
    @sfpages.agent_badge_node(maker, fn() { agent().badge }, 20.0, ground)
    let held = @sfpages.hover_node(maker, "bar-agent/" + key, fn(c) {
      match aj() { Some(j) => agent_card(c, src, r, j); None => () }
    }, tile=true)
    @sf.presses_node(maker, open, menu=fn(_, _) { held() })
    maker.presses(By(fn() { !whole() })).points(By(fn() { !whole() })) |> ignore
  }) |> ignore
  parent.show(fn() { station() is Some(_) }, fn(part) {
    part.row(Is(true)).height(Is(Some(20.0))).max_width(Is(Some(140.0)))
    .padding(Is((@ui.Space::px(@sf.agent_station_in), 0.0, @ui.Space::px(@sf.agent_station_in), 0.0)))
    .lines_up(Is(Some(Middle))).radius(Is(agent_station_round))
    .corners(Is(Some((0.0, agent_station_round, agent_station_round, 0.0)))).clips(Is(true))
    .ground(By(fn() { if part.pointed() || part.pressed() { @ui.tree_theme().color(Hover) } else { 0L } })) |> ignore
    let s = fn() { station().unwrap() }
    part.says(By(fn() { if whole() { None } else { Some(@view.said(Button, label=s().name)) } })) |> ignore
    @sfpages.hover_node(part, "bar-agent-station/" + key, fn(c) { @settings.station_peek_card(c, r.station) }, tile=true, padded=false) |> ignore
    @sf.presses_node(part, fn() {
      if !@sf.pointer_rests() {
        let (x, y, w, h) = part.placed_window_now()
        @settings.open_station_peek(r.station, from=At(x, y, w, h))
      }
    })
    part.presses(By(fn() { !whole() })).points(By(fn() { !whole() })) |> ignore
    let mark = fn() { @sf.has_station_mark(s().emoji, s().icon) }
    part.show(mark, fn(m) { @sf.station_mark_node(m, fn() { s().emoji }, fn() { s().icon }, chat_station_mark, fn() { @sf.theme().p.muted }, stint) })
    part.show(fn() { !mark() }, fn(n) { bar_words(n, fn() { s().name }, chat_station_words, fn() { 1000.0 }) })
  })
  let held = @sfpages.hover_node(parent, "bar-agent-tile/" + key, fn(c) {
    match aj() { Some(j) => c.box(style=tile_card_agent, fn() { agent_card(c, src, r, j, across=true) }) |> ignore; None => () }
    @settings.station_peek_part(c, r.station)
  }, tile=true, padded=false)
  @sf.presses_node(parent, open, menu=fn(_, _) { held() })
  // Only the whole tile's own target changes; making its parent inert would also
  // disable the agent and station's separate controls under keyboard and mouse.
  parent.takes(fn(w, h, _) { if whole() { [(0.0, 0.0, w, h)] } else { [] } })
  .points(By(whole)).focusable(By(whole))
  .says(By(fn() { if whole() { Some(@view.said(Button, label=said())) } else { None } })) |> ignore
  parent.show(fn() { station().map_or(false, fn(s) { s.via != "" }) }, fn(d) {
    d.over(Is(true)).width_share(Is(1.0)).row(Is(true)).lies_along(Is(End)).offset(Is((3.0, 13.0))) |> ignore
    d.box(fn(dot) { chat_via_dot_node(dot, fn() { station().unwrap().via }, 10.0, 2.0, ground~) }) |> ignore
  })
}

///|
fn chat_key_dot_node(parent : @view.View, alarm : () -> String, ground : () -> Int64) -> Unit {
  parent.show(fn() { alarm() != "" }, fn(d) {
    d.over(Is(true)).offset(Is((18.0, 4.0))) |> ignore
    d.box(fn(dot) {
      dot.width(Is(Some(10.0))).height(Is(Some(10.0))).radius(Is(5.0))
      .ground(By(fn() { @ui.tree_theme().color(if alarm() == "fail" { Danger } else { Warn }) }))
      .edge(By(fn() { (2.0, ground()) })) |> ignore
    }) |> ignore
  })
}
