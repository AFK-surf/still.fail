// The stacked chat's bar, made once: its title and marks follow the chat, its actions act at their press.

///|
fn chat_bar_node(parent : @view.View, src : Source, w : Workspace, r : ChatRef,
  view : () -> ChatView?, stint : () -> Int, frame : () -> PageFrame) -> Unit {
  let station = fn() {
    stations_of((src.topic)("stations", { "scope": Json::string(w.id) }).value)
    .iter().find_first(fn(s) { s.address == r.station })
  }
  parent.box(fn(bar) {
    bar.grow(Is(1.0)).glass(By(fn() { Some(@sf.glass_bar()) }))
    .row(Is(true)).padding(By(fn() { (4.0, frame().top, 16.0, 0.0) }))
    .min_height(By(fn() { Some(frame().top + chat_bar_h) }))
    .lines_up(Is(Some(Middle))) |> ignore
    @sf.round_key_node(bar, "chevron-left", fn() { tr("common.back") }, fn() {
      @sfbase.go_back() |> ignore
    }, side=40.0, icon_size=22.0, ink=fn() { @sf.theme().p.accent_text })
    bar.box(fn(middle) {
      middle.row(Is(true)).grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0)))
      .padding(Is((0.0, 0.0, 8.0, 0.0))).gap(Is(8.0)).lines_up(Is(Some(Middle))).fits(Is(true)) |> ignore
      middle.box(fn(title) {
        title.words(By(fn() { view().map(fn(v) { v.title }).unwrap_or(r.title) }))
        .words_look(By(fn() { { size: @sf.theme().t.title, weight: 600, line: chat_title_line, wrap: false, tracking: @view.letters_own, balance: false } }))
        .ink(By(fn() { @sf.theme().p.text })).cuts(Is(true), keep=true) |> ignore
      }) |> ignore
      middle.show(fn() { view().map_or(false, fn(v) { v.agents.length() == 0 }) && station() is Some(_) }, fn(s) {
        chat_station_chip_node(s, r.station, fn() { station().unwrap() }, stint)
      })
      let people = fn() {
        let all = view().map(fn(v) { v.people }).unwrap_or([])
        if all.length() > 5 { all[:5].to_owned() } else { all }
      }
      middle.show(fn() { people().length() > 0 }, fn(p) {
        p.drops(Is(bar_drop_people)).width(By(fn() { Some(19.0 * people().length().to_double()) })).height(Is(Some(19.0))) |> ignore
        // The first over the others: the same reverse drawing order as PeopleStack's.
        p.each(fn() { Array::makei(people().length(), fn(j) { people().length() - 1 - j }) }, fn(j) { j.to_string() }, fn(face, i) {
          let person = fn() { people()[i.get()] }
          face.over(Is(true)).offset(By(fn() { (14.0 * i.get().to_double(), 0.0) }))
          .width(Is(Some(19.0))).height(Is(Some(19.0))).radius(Is(9.5))
          .ground(By(fn() { @sf.theme().p.bg })).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
          @sf.avatar_node(face, fn() { person().id }, fn() { person().display }, fn() {
            let key = person().picture
            if key == "" { "" } else { (src.picture)(key, stint()) }
          }, 16.0)
        })
      })
      let agents = fn() { view().map(fn(v) { v.agents }).unwrap_or([]) }
      middle.each(fn() { agents().map(fn(a) { a.key }) }, fn(k) { k }, fn(tile, key) {
        let initial = @signals.untracked(fn() { agents().iter().find_first(fn(a) { a.key == key.get() }).unwrap() })
        let agent = fn() { agents().iter().find_first(fn(n) { n.key == key.get() }).unwrap_or(initial) }
        @sf.presses_node(tile, fn() { open_agent(src, r, key.get()) })
        let first = fn() { agents().length() > 0 && agents()[0].key == key.get() }
        chat_agent_tile_node(tile, agent, fn() { if first() { station() } else { None } }, stint)
      })
    }) |> ignore
    let archivable = fn() { view().map_or(false, fn(v) { v.archivable && !v.archived }) }
    let initial = Ref(@signals.untracked(archivable))
    bar.show(archivable, fn(room) {
      let look = @motion.presence_node(room, initial=initial.val,
        enter=@motion.trans(fade=0.0, scale=0.85, spec=archive_tween),
        exit=@motion.trans(fade=0.0, scale=0.85, spec=archive_tween))
      initial.val = false
      room.row(Is(true)).lies_along(Is(End)).width(By(fn() { Some((nav_key_side + bar_keys_apart()) * look().alpha) })) |> ignore
      room.box(fn(button) {
        button.width(Is(Some(nav_key_side))).min_width(Is(Some(nav_key_side))).height(Is(Some(nav_key_side)))
        .alpha(By(fn() { look().alpha })).scale(By(fn() { look().sx }))
        .presses(By(fn() { !room.leaving() })).hides(By(fn() { room.leaving() })) |> ignore
        let busy = fn() { doing("archive/" + r.station + "/" + r.session) }
        button.show(busy, fn(spin) {
          spin.width(Is(Some(nav_key_side))).height(Is(Some(nav_key_side))).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
          @sf.spinner_node(spin) |> ignore
        })
        button.show(fn() { !busy() }, fn(key) {
          @sf.round_key_node(key, "archive", fn() { tr("android-chat.archive") }, fn() {
            if archivable() { match view() { Some(v) => archive_chat(src, r, v); None => () } }
          }, icon_size=20.0)
        })
      }) |> ignore
    }, leave=archive_ms)
    initial.val = false
    let jobs = fn() { (src.topic)("chatJobs", chat_jobs_summary_params(r)).value }
    bar.show(fn() { view() is Some(_) && (flag(jobs(), "hasJobs") || items(jobs(), "jobs").length() > 0) }, fn(room) {
      room.padding(By(fn() { (bar_keys_apart(), 0.0, 0.0, 0.0) })) |> ignore
      room.box(fn(key) {
        @sf.round_key_node(key, "web", fn() { tr("android-misc.jobs.title") }, fn() { open_chat_jobs(src, r) }, icon_size=20.0)
        let alarm = fn() { text(jobs(), "alarm") }
        key.show(fn() { alarm() == "fail" || alarm() == "restart" }, fn(dot) {
          dot.over(Is(true)).offset(Is((nav_key_side - 17.0, 6.0))).width(Is(Some(11.0))).height(Is(Some(11.0)))
          .radius(Is(5.5)).ground(By(fn() { @sf.theme().p.bg })).padding(Is((2.0, 2.0, 2.0, 2.0))) |> ignore
          dot.box(fn(fill) {
            fill.grow(Is(1.0)).radius(Is(3.5)).ground(By(fn() { if alarm() == "fail" { @sf.theme().p.red } else { 0xD9962BFFL } })) |> ignore
          }) |> ignore
        })
      }) |> ignore
    })
    bar.show(fn() { view() is Some(_) }, fn(keys) {
      keys.row(Is(true)).gap(By(bar_keys_apart)).padding(By(fn() { (bar_keys_apart(), 0.0, 0.0, 0.0) })) |> ignore
      @sf.round_key_node(keys, "info", fn() { tr("android-chat.info.title") }, fn() { open_info(src, r) }, icon_size=20.0)
      keys.box(fn(more) {
        @sf.round_key_node(more, "more", fn() { tr("common.more") }, fn() {
          let (x, y, width, height) = more.placed_window_now()
          @sfpages.open_chat_menu(src, w.id, r, @sfpages.chat_extra_items(src, r, (src.topic)("chat", chat_params(r)).value),
            from=At(x, y, width, height))
        }, icon_size=18.0)
      }) |> ignore
    })
  }) |> ignore
}

///|
fn chat_station_chip_node(parent : @view.View, address : String, station : () -> Station, stint : () -> Int) -> Unit {
  parent.box(fn(chip) {
    chip.row(Is(true)).max_width(Is(Some(104.0))).gap(Is(4.0)).lines_up(Is(Some(Middle)))
    .padding(By(fn() { (if station().via != "" { station_dot_in } else { station_tag_end }, 2.0, station_tag_end, 2.0) }))
    .radius(Is(12.0)).edge(By(fn() { (1.0, @sf.theme().p.line) }))
    .says(By(fn() { Some(@view.said(Button, label=station().name)) })) |> ignore
    @sf.presses_node(chip, fn() {
      let (x, y, w, h) = chip.placed_window_now()
      @settings.open_station_peek(address, from=At(x, y, w, h))
    })
    chip.show(fn() { station().via != "" }, fn(dot) { chat_via_dot_node(dot, fn() { station().via }, via_dot_side, 0.0) })
    chip.show(fn() { @sf.has_station_mark(station().emoji, station().icon) }, fn(mark) {
      @sf.station_mark_node(mark, fn() { station().emoji }, fn() { station().icon }, 12.0, fn() { @sf.theme().p.muted }, stint)
    })
    chip.box(fn(name) {
      name.words(By(fn() { station().name })).words_look(By(fn() {
        { size: @sf.theme().t.caption, weight: 400, line: 16.0, wrap: false, tracking: @view.letters_own, balance: false }
      })).ink(By(fn() { @sf.theme().p.muted })) |> ignore
    }) |> ignore
  }) |> ignore
}

///|
fn chat_via_dot_node(parent : @view.View, via : () -> String, size : Double, ring : Double) -> Unit {
  parent.box(fn(outside) {
    outside.width(Is(Some(size))).height(Is(Some(size))).radius(Is(size / 2.0))
    .ground(By(fn() { if ring > 0.0 { @sf.theme().p.bg } else { 0L } }))
    .padding(Is((ring, ring, ring, ring))) |> ignore
    outside.box(fn(dot) {
      dot.grow(Is(1.0)).radius(Is((size - ring * 2.0) / 2.0)).ground(By(fn() {
        let t = @sf.theme().p
        match via() { "direct" => t.online; "relay" => 0xD9962BFFL; "offline" => t.red; _ => t.muted }
      })) |> ignore
    }) |> ignore
  }) |> ignore
}

///|
fn chat_agent_tile_node(parent : @view.View, agent : () -> Agent, station : () -> Station?, stint : () -> Int) -> Unit {
  let side = mark_side()
  parent.says(By(fn() { Some(@view.said(Button, label=agent().who + station().map(fn(s) { " · " + s.name }).unwrap_or(""))) })) |> ignore
  parent.box(fn(tile) {
    tile.row(Is(true)).height(Is(Some(side))).radius(Is(mark_corner(side)))
    .ground(By(fn() { mark_ground().0 })).edge(By(fn() { (mark_ground().1, @sf.theme().p.line) }))
    .lines_up(Is(Some(Middle))) |> ignore
    tile.box(fn(maker) {
      maker.width(Is(Some(side))).height(Is(Some(side))).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
      @sf.maker_mark_node(maker, fn() { agent().maker }, fn() { agent().runtime }, mark_logo(side)) |> ignore
    }) |> ignore
    tile.show(fn() { station() is Some(_) }, fn(s) {
      let (most, inside, line) = station_part_type()
      s.max_width(Is(Some(most))).padding(Is((inside, 0.0, inside, 0.0))).lines_up(Is(Some(Middle))) |> ignore
      let mark = fn() { station().map_or(false, fn(s) { @sf.has_station_mark(s.emoji, s.icon) }) }
      s.show(mark, fn(m) {
        @sf.station_mark_node(m, fn() { station().unwrap().emoji }, fn() { station().unwrap().icon }, mark_station(), fn() { @sf.theme().p.muted }, stint)
      })
      s.show(fn() { !mark() }, fn(name) {
        name.words(By(fn() { station().unwrap().name })).words_look(By(fn() {
          { size: @sf.theme().t.caption, weight: 400, line, wrap: false, tracking: @view.letters_own, balance: false }
        })).ink(By(fn() { @sf.theme().p.muted })) |> ignore
      })
    })
  }) |> ignore
  @sfpages.agent_badge_node(parent, fn() { agent().badge }, side, fn() { @sf.theme().p.bg })
  parent.show(fn() { station().map_or(false, fn(s) { s.via != "" }) }, fn(dot) {
    dot.over(Is(true)).width_share(Is(1.0)).row(Is(true)).lies_along(Is(End)).offset(Is((3.0, side - 7.0))) |> ignore
    chat_via_dot_node(dot, fn() { station().unwrap().via }, 10.0, 2.0)
  })
}
