// A chat's bar laid out Small as nodes of the window's tree (chat_bar's and bar_frame's, over the chat's page made once:
// narrow_made's "chat"), made once and changed as what it shows does: back, the title, its station while no agent is
// in it, its people, its agents' marks; 归档 coming and going as nothing is left in it or something is again, its
// services and jobs, what it is (ⓘ) and what is done with it ("…"). On the bar's glass once the chat's view is read,
// the page's ground under it till then (its title what it was opened by, nothing at its end).

///|
/// The bar of the chat page `page` is (none over any other) in node `v`, over the page's old view, from source `src`;
/// its pictures asked for on the page's time on top, `stint`.
fn chat_bar_node(v : @view.View, src : Source, page : () -> Page?, stint : () -> Int) -> Unit {
  let chat = fn() {
    match page() {
      Some(Chat(r)) => Some(r)
      _ => None
    }
  }
  // (by the chat it is of, given it: another one become in its place another bar)
  v.pick(fn() { { chat: chat() } }, fn(b, which) {
    guard which.chat is Some(r) else { return }
    chat_bar_of(b, src, r, stint)
  })
}

///|
/// The chat a page's bar is of (chat_bar_node), one told from another by where it is (its station and session), not by
/// the title it was opened by.
priv struct BarOf {
  chat : ChatRef?
}

///|
impl Eq for BarOf with equal(a, b) {
  a.chat.map(fn(r) { (r.station, r.session) }) == b.chat.map(fn(r) { (r.station, r.session) })
}

///|
let chat_bar_expand_ms : Double = 280.0

///|
let chat_bar_collapse_ms : Double = 260.0

///|
priv struct ChatBarState {
  manual_expanded : @signals.Signal[Bool]
  open_way : @sf.EdgeWay
  row2_h : @signals.Signal[Double]
  extra_target : @signals.Signal[Double]
  mut settled_initial : Bool
}

///|
let chat_bar_states : Map[String, ChatBarState] = Map([])

///|
fn chat_bar_reset() -> Unit {
  chat_bar_states.clear()
}

///|
fn chat_bar_key(r : ChatRef) -> String {
  r.station + "\u{1}" + r.session
}

///|
fn chat_bar_state(r : ChatRef) -> ChatBarState {
  let k = chat_bar_key(r)
  match chat_bar_states.get(k) {
    Some(s) => s
    None => {
      let s = {
        manual_expanded: @signals.signal(false, same=fn(a, b) { a == b }),
        open_way: @sf.EdgeWay::new(0.0),
        row2_h: @signals.signal(0.0, same=fn(a, b) { a == b }),
        extra_target: @signals.signal(0.0, same=fn(a, b) { a == b }),
        settled_initial: false,
      }
      chat_bar_states[k] = s
      s
    }
  }
}

///|
fn bar_extra_target(r : ChatRef) -> Double {
  match chat_bar_states.get(chat_bar_key(r)) {
    Some(s) => s.extra_target.get()
    None => 0.0
  }
}

///|
fn bar_extra_shown(v : @view.View, r : ChatRef) -> Double {
  match chat_bar_states.get(chat_bar_key(r)) {
    Some(s) => s.open_way.shown(v) * s.row2_h.get()
    None => 0.0
  }
}

///|
fn bar_clamp01(v : Double) -> Double {
  if v < 0.0 {
    0.0
  } else if v > 1.0 {
    1.0
  } else {
    v
  }
}

///|
fn bar_trailing_width(held : @view.View, agents : Array[Agent], station : Station?) -> Double {
  let th = @sf.theme()
  let cap_sp = @sf.node_sp(held, th.t.caption)
  if agents.length() == 0 {
    match station {
      None => 0.0
      Some(s) => {
        let pad_l = if s.via != "" { station_dot_in } else { station_tag_end }
        let has_dot = s.via != ""
        let has_mark = @sf.has_station_mark(s.emoji, s.icon)
        let parts = (if has_dot { 1 } else { 0 }) + (if has_mark { 1 } else { 0 }) + 1
        let nw = @sf.node_words_w(s.name, cap_sp, weight=400)
        let raw = pad_l +
          station_tag_end +
          (if has_dot { via_dot_side } else { 0.0 }) +
          (if has_mark { 12.0 } else { 0.0 }) +
          4.0 * (parts - 1).to_double() +
          nw
        8.0 + dmin(104.0, raw)
      }
    }
  } else {
    let m = mark_side()
    let first_w = match station {
      None => m
      Some(s) => {
        let (most, inside, _) = station_part_type()
        let iw = if @sf.has_station_mark(s.emoji, s.icon) {
          mark_station()
        } else {
          @sf.node_words_w(s.name, cap_sp, weight=400)
        }
        m + dmin(most, inside * 2.0 + iw)
      }
    }
    8.0 + first_w + (8.0 + m) * (agents.length() - 1).to_double()
  }
}

///|
/// Chat `r`'s bar (chat_bar_node) in `b`.
fn chat_bar_of(b : @view.View, src : Source, r : ChatRef, stint : () -> Int) -> Unit {
  let state = chat_bar_state(r)
  let mid_w_sig : @signals.Signal[Double] = @signals.signal(0.0, same=fn(a, b) { a == b })
  let view = fn() { view_of_chat(src, r).0 }
  let read = fn() { view() is Some(_) }
  let title_now = fn() {
    match view() {
      Some(v) => v.title
      None => r.title
    }
  }
  let station_now = fn() {
    let w = match workspace_in_view(src).0 {
      Some(w) => w.id
      None => ""
    }
    station_marks(src, w).iter().find_first(fn(s) { s.address == r.station })
  }
  b.box(fn(g) {
    let metrics = fn() {
      let mid_w = mid_w_sig.get()
      if !read() || mid_w <= 0.0 {
        return (false, false)
      }
      let th = @sf.theme()
      let sp = @sf.node_sp(g, th.t.title)
      let title_w = @sf.node_words_w(title_now(), sp, weight=600)
      // 3 CJK em (~1em each) + ellipsis (~0.75em): scales with font size without shaping an unrecorded literal in CI textref.
      let three_w = dmax(44.0, sp * 3.75)
      let agents = match view() {
        Some(v) => v.agents
        None => []
      }
      let avail = dmax(0.0, mid_w - 16.0 - bar_trailing_width(g, agents, station_now()))
      let overflows = title_w > avail
      let must_expand = overflows && avail < three_w
      let can_toggle = overflows && !must_expand
      (must_expand, can_toggle)
    }
    let must_expand_sig : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })
    let can_toggle_sig : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })
    let can_toggle = fn() { can_toggle_sig.get() }
    let expanded = fn() {
      must_expand_sig.get() || (can_toggle_sig.get() && state.manual_expanded.get())
    }
    g.reacts(metrics, fn(m) {
      must_expand_sig.set(m.0)
      can_toggle_sig.set(m.1)
    })
    g.reacts(fn() { (mid_w_sig.get() > 0.0, expanded(), state.row2_h.get()) }, fn(cur) {
      if cur.0 && !state.settled_initial {
        state.settled_initial = true
        state.open_way.put(if cur.1 { 1.0 } else { 0.0 })
        state.extra_target.set(if cur.1 { cur.2 } else { 0.0 })
      } else if state.settled_initial {
        if cur.1 != (state.open_way.target() >= 0.5) {
          state.open_way.go(
            g,
            if cur.1 { 1.0 } else { 0.0 },
            if cur.1 { chat_bar_expand_ms } else { chat_bar_collapse_ms },
          )
        }
        let target_h = if cur.1 { cur.2 } else { 0.0 }
        if state.extra_target.get() != target_h {
          state.extra_target.set(target_h)
        }
      }
    })
    // (frosted over the messages once they are read, as chat_bar's glass; on the page's ground till then)
    g.glass(By(fn() { if read() { Some(@sf.glass_bar()) } else { None } })) |> ignore
    g.reacts(can_toggle, fn(ok) {
      if !ok && state.manual_expanded.get() {
        state.manual_expanded.set(false)
      }
    })
    g.box(fn(row) {
      row
      .row(Is(true))
      .padding(By(fn() { (4.0, status_top_now(row.window().0), 16.0, 0.0) }))
      .min_height(By(fn() { Some(status_top_now(row.window().0) + bar_h) }))
      .lines_up(Is(Some(Middle)))
      |> ignore
      // back (Chat.kt BarFrame: 40 round, its chevron 22 in the accent's ink)
      @sf.round_key_node(
        row,
        "chevron-left",
        fn() { tr("common.back") },
        fn() { @sfbase.go_back() |> ignore },
        side=40.0,
        icon_size=22.0,
        ink=fn() { @sf.theme().p.accent_text },
      )
      // the title and what follows it, in one row
      bar_middle_node(row, src, r, view, stint, state, expanded, can_toggle, mid_w_sig)
      row.show(read, fn(end) { bar_end_node(end, src, r, view) })
    })
    |> ignore
    g.show(fn() { expanded() || state.open_way.shown(g) > 0.0 }, fn(row2_host) {
      row2_host.box(fn(row2_room) {
        let p = fn() { state.open_way.shown(row2_room) }
        row2_room
        .opens(
          By(fn() {
            let v = p()
            if v >= 1.0 && expanded() {
              None
            } else {
              Some(bar_clamp01(v))
            }
          }),
          from_foot=true,
        )
        .clips(By(fn() { p() < 1.0 }))
        |> ignore
      row2_room.box(fn(row2_pad) {
        row2_pad.padding(Is((0.0, 8.0, 0.0, 0.0))) |> ignore
        row2_pad.box(fn(row2_box) {
          let hp = fn() { state.open_way.shown(row2_box) }
          @sf.presses_node(
            row2_box,
            fn() {
              if expanded() && can_toggle() && hp() >= 1.0 {
                state.manual_expanded.set(false)
              }
            },
            on=fn() { expanded() && can_toggle() && hp() >= 1.0 },
          )
          row2_box
          .row(Is(true))
          .min_height(By(fn() { if can_toggle() { Some(44.0) } else { None } }))
          .padding(Is((16.0, 0.0, 16.0, 8.0)))
          .lines_up(Is(Some(Middle)))
          .alpha(By(fn() { bar_clamp01((hp() - 0.15) / 0.85) }))
          |> ignore
          row2_box.by_room(fn(p2, rr2) {
            p2.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
            let t2 = p2.box(fn(t2) {
              t2
              .words(By(title_now))
              .words_look(By(fn() {
                let th = @sf.theme()
                { size: th.t.title, weight: 600, line: chat_title_line, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 }
              }))
              .ink(By(fn() { @sf.theme().p.text }))
              |> ignore
            })
            p2.reacts(fn() { (rr2.tall(t2), can_toggle()) }, fn(cur) {
              if cur.0 > 0.0 && (expanded() || state.row2_h.get() <= 0.0) {
                let box_h = if cur.1 { dmax(44.0, cur.0 + 8.0) } else { cur.0 + 8.0 }
                state.row2_h.set(8.0 + box_h)
              }
            })
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// What the middle of a chat's bar shows, once its view is read (`shown`: the view, the station it is on, its first
/// five people), and what tells one such from another (`key`: what of them the bar draws), each as `key` says.
priv struct BarMarks {
  key : String
  shown : (ChatView, Station?, Array[Person])?
}

///|
impl Eq for BarMarks with equal(a, b) {
  a.key == b.key
}

///|
/// The middle of the bar of chat `r` (its view `view`), in row `row`: its title, kept whole while what follows it may
/// leave the row for it, cut short only once nothing more may; then, once the view is read, its station's tag while no
/// agent is in it, its people (the first to leave the row short of room), its agents' marks, the first's with the
/// station it runs on: all in the one row, as bar_frame's, made again as any of them changes.
fn bar_middle_node(
  row : @view.View,
  src : Source,
  r : ChatRef,
  view : () -> ChatView?,
  stint : () -> Int,
  state : ChatBarState,
  expanded : () -> Bool,
  can_toggle : () -> Bool,
  mid_w_sig : @signals.Signal[Double],
) -> Unit {
  let marks = fn() {
    let w = match workspace_in_view(src).0 {
      Some(w) => w.id
      None => ""
    }
    match view() {
      Some(v) => {
        let station = station_marks(src, w).iter().find_first(fn(s) { s.address == r.station })
        let people = if v.people.length() > 5 { v.people[:5].to_owned() } else { v.people }
        let s = match station {
          Some(s) => "\{s.name}\u{1}\{s.emoji}\u{1}\{s.icon}\u{1}\{s.via}"
          None => ""
        }
        let ps = people.map(fn(p) { "\{p.id}\u{1}\{p.display}\u{1}\{p.picture}" }).join("\u{2}")
        let ag = v.agents.map(fn(x) { "\{x.key}\u{1}\{x.maker}\u{1}\{x.runtime}\u{1}\{x.badge}\u{1}\{x.who}" }).join("\u{2}")
        { key: "read\u{3}" + s + "\u{3}" + ps + "\u{3}" + ag, shown: Some((v, station, people)) }
      }
      None => { key: "", shown: None }
    }
  }
  // (made again as what it shows changes, given what it shows)
  row.pick(marks, fn(mid_outer, marks) {
    mid_outer
    .grow(Is(1.0))
    .basis(Is(Some(0.0)))
    .min_width(Is(Some(0.0)))
    |> ignore
    mid_outer.by_room(fn(mid, mid_room) {
      // (giving way before the title, what follows it leaving the row first: View::drops)
      mid
      .row(Is(true))
      .min_width(Is(Some(0.0)))
      .padding(Is((8.0, 0.0, 8.0, 0.0)))
      .gap(Is(8.0))
      .lines_up(Is(Some(Middle)))
      .fits(Is(true))
      |> ignore
      mid.reacts(fn() { mid_room.width() }, fn(w) {
        if marks.shown is Some(_) && w > 0.0 && mid_w_sig.get() != w {
          mid_w_sig.set(w)
        }
      })
      mid.box(fn(t_box) {
        let tp = fn() { state.open_way.shown(t_box) }
        @sf.presses_node(
          t_box,
          fn() {
            if !expanded() && can_toggle() && tp() <= 0.0 {
              state.manual_expanded.set(true)
            }
          },
          on=fn() { !expanded() && can_toggle() && tp() <= 0.0 },
        )
        t_box
        .row(Is(true))
        .lines_up(Is(Some(Middle)))
        .fit_whole(By(fn() { !expanded() }))
        .grow(By(fn() { if expanded() { 1.0 } else { 0.0 } }))
        .basis(By(fn() { if expanded() { Some(0.0) } else { None } }))
        .cuts(Is(true))
        .min_width(Is(Some(0.0)))
        .min_height(By(fn() { if !expanded() && can_toggle() && tp() <= 0.0 { Some(44.0) } else { None } }))
        .alpha(By(fn() { bar_clamp01(1.0 - tp() / 0.45) }))
        .offset(By(fn() { (0.0, 5.0 * bar_clamp01(tp() / 0.5)) }))
        |> ignore
        t_box.box(fn(t) {
          t
          .words(By(fn() {
            match view() {
              Some(v) => v.title
              None => r.title
            }
          }))
          .words_look(By(fn() {
            let th = @sf.theme()
            { size: th.t.title, weight: 600, line: chat_title_line, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
          }))
          .ink(By(fn() { @sf.theme().p.text }))
          .cuts(Is(true))
          .allow_ellipsis(Is(true))
          .min_width(Is(Some(0.0)))
          |> ignore
        })
        |> ignore
      })
      |> ignore
      guard marks.shown is Some((v, station, people)) else { return }
      if v.agents.length() == 0 {
        match station {
          Some(s) => station_chip_node(mid, r.station, s, stint)
          None => ()
        }
      }
      if people.length() > 0 {
        mid.box(fn(p) {
          p.drops(Is(bar_drop_people)).laid_nowhere(By(expanded)) |> ignore
          people_stack_node(p, src, people, 16.0, stint)
        })
        |> ignore
      }
      for i, ag in v.agents {
        let key = ag.key
        mid.box(fn(k) {
          // each opens its card, said as the agent (with the station it runs on, the first's)
          @sf.presses_node(k, fn() { open_agent(src, r, key) })
          let label = match station {
            Some(s) if i == 0 => ag.who + " · " + s.name
            _ => ag.who
          }
          k.says(Is(Some(@view.said(Button, label~)))) |> ignore
          if i == 0 {
            agent_station_node(k, ag, station, stint)
          } else {
            model_mark_node(k, ag, mark_side())
          }
        })
        |> ignore
      }
    })
    |> ignore
  })
}

///|
/// At the end of chat `r`'s bar (its view `view`, read), in `e`: 归档 while nothing is left in it, coming and going
/// (chat_bar's: 280 ms, ArchiveEase, its room before it with it, fading from or to 85% of its size), its services and
/// jobs while it has any (a dot when one died lately or a service is started again), what it is and "…".
fn bar_end_node(e : @view.View, src : Source, r : ChatRef, view : () -> ChatView?) -> Unit {
  e.row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
  // (its "…" is its chat's whole row's: held while its page is open (let go of as it is left, chat_left), asked as it
  // opens: @sfpages.chat_menu_of)
  @signals.untracked(fn() { @sfbase.chat_whole_held(src, r) }) |> ignore
  let archivable = fn() {
    match view() {
      Some(v) => v.archivable && !v.archived
      None => false
    }
  }
  let doing_key = "archive/" + r.station + "/" + r.session
  e.box(fn(k) {
    // (there as it is made where it is so; set off as it becomes so or stops, at that cause's moment: reacts' first
    // run, as it is made, goes nowhere, the way already there)
    let share = @sf.EdgeWay::new(if @signals.untracked(archivable) { 1.0 } else { 0.0 })
    k.reacts(archivable, fn(on) { share.go_by(k, if on { 1.0 } else { 0.0 }, archive_tween) })
    let s = fn() { share.shown(k) }
    k
    .row(Is(true))
    .width(By(fn() { Some((nav_key_side + bar_keys_apart()) * s()) }))
    .clips(Is(true))
    .lies_along(Is(End))
    .laid_nowhere(By(fn() { s() <= 0.0 && !archivable() }))
    |> ignore
    k.box(fn(b) {
      b
      .width(Is(Some(nav_key_side)))
      .min_width(Is(Some(nav_key_side)))
      .height(Is(Some(nav_key_side)))
      .lines_up(Is(Some(Middle)))
      .lies_along(Is(Middle))
      .alpha(By(s))
      .scale(By(fn() { 0.85 + 0.15 * s() }))
      .presses(By(archivable))
      |> ignore
      b.show(fn() { @sfbase.doing(doing_key) }, fn(sp) { @sf.spinner_node(sp) |> ignore })
      b.show(fn() { !@sfbase.doing(doing_key) }, fn(key) {
        @sf.round_key_node(
          key,
          "archive",
          fn() { tr("android-chat.archive") },
          // (the chat's view as it is at the press)
          fn() {
            match view() {
              Some(v) if v.archivable && !v.archived => archive_chat(src, r, v)
              _ => ()
            }
          },
          icon_size=20.0,
        )
      })
    })
    |> ignore
  })
  |> ignore
  // its services and jobs, while it has any
  let jobs = fn() { src.topic("chatJobs", chat_jobs_summary_params(r)).get().value }
  let has_jobs = fn() {
    let j = jobs()
    flag(j, "hasJobs") || items(j, "jobs").length() > 0
  }
  e.show(has_jobs, fn(k) {
    k.row(Is(true)).padding(By(fn() { (bar_keys_apart(), 0.0, 0.0, 0.0) })) |> ignore
    @sf.round_key_node(k, "web", fn() { "" }, fn() { open_chat_jobs(src, r) }, icon_size=20.0)
    let alarm = fn() { text(jobs(), "alarm") }
    k.show(fn() { alarm() == "fail" || alarm() == "restart" }, fn(d) {
      d
      .over(Is(true))
      .lines_up(Is(Some(End)))
      .padding(Is((0.0, 6.0, 6.0, 0.0)))
      |> ignore
      d.box(fn(ring) {
        ring
        .width(Is(Some(11.0)))
        .height(Is(Some(11.0)))
        .radius(Is(5.5))
        .padding(Is((2.0, 2.0, 2.0, 2.0)))
        .ground(By(fn() { @sf.theme().p.bg }))
        |> ignore
        ring.box(fn(dot) {
          dot
          .grow(Is(1.0))
          .radius(Is(3.5))
          .ground(By(fn() { if alarm() == "fail" { @sf.theme().p.red } else { 0xD9962BFFL } }))
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
  })
  // what it is (its info's sheet), then what is done with it ("…": the menu a row of the list has)
  e.box(fn(k) {
    k.row(Is(true)).padding(By(fn() { (bar_keys_apart(), 0.0, 0.0, 0.0) })) |> ignore
    @sf.round_key_node(k, "info", fn() { tr("android-chat.info.title") }, fn() { open_info(src, r) }, icon_size=20.0)
  })
  |> ignore
  e.box(fn(k) {
    k.row(Is(true)).padding(By(fn() { (bar_keys_apart(), 0.0, 0.0, 0.0) })) |> ignore
    k.box(fn(more) {
      @sf.round_key_node(
        more,
        "more",
        fn() { tr("common.more") },
        fn() {
          let w = match workspace_in_view(src).0 {
            Some(w) => w.id
            None => ""
          }
          let chat = src.topic("chat", chat_params(r)).get().value
          let (x, y, mw, mh) = more.placed_window_now()
          @sfpages.open_chat_menu(src, w, r, @sfpages.chat_extra_items(src, r, chat), from=At(x, y, mw, mh))
        },
        icon_size=18.0,
      )
    })
    |> ignore
  })
  |> ignore
}

///|
/// The station's tag in a chat's bar while no agent is in it (station_chip's, as nodes): a tap opens its card.
fn station_chip_node(v : @view.View, address : String, s : Station, stint : () -> Int) -> Unit {
  v.box(fn(k) {
    @sf.presses_node(k, fn() {
      let (x, y, w, h) = k.placed_window_now()
      @settings.open_station_peek(address, from=At(x, y, w, h))
    })
    k
    .row(Is(true))
    .max_width(Is(Some(104.0)))
    .padding(Is((if s.via != "" { station_dot_in } else { station_tag_end }, 2.0, station_tag_end, 2.0)))
    .gap(Is(4.0))
    .radius(Is(12.0))
    .edge(By(fn() { (1.0, @sf.theme().p.line) }))
    .lines_up(Is(Some(Middle)))
    .says(Is(Some(@view.said(Group, label=s.name))))
    |> ignore
    if s.via != "" {
      via_dot_node(k, s.via, via_dot_side, 0.0)
    }
    if @sf.has_station_mark(s.emoji, s.icon) {
      @sf.station_mark_node(k, fn() { s.emoji }, fn() { s.icon }, 12.0, fn() { @sf.theme().p.muted }, stint)
    }
    k.box(fn(t) {
      t
      .words(Is(s.name))
      .words_look(By(fn() {
        { size: @sf.theme().t.caption, weight: 400, line: 16.0, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
      }))
      .ink(By(fn() { @sf.theme().p.muted }))
      .cuts(Is(true))
      .min_width(Is(Some(0.0)))
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// How a station is reached as a dot (via_dot's, as a node), `size` across, ringed `ring` in the page's ground.
fn via_dot_node(v : @view.View, via : String, size : Double, ring : Double) -> Unit {
  let inner = size - ring * 2.0
  v.box(fn(d) {
    d
    .width(Is(Some(size)))
    .height(Is(Some(size)))
    .radius(Is(size / 2.0))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .row(Is(true))
    .ground(By(fn() { if ring > 0.0 { @sf.theme().p.bg } else { 0L } }))
    |> ignore
    d.box(fn(i) {
      i
      .width(Is(Some(inner)))
      .height(Is(Some(inner)))
      .radius(Is(inner / 2.0))
      .ground(By(fn() {
        let p = @sf.theme().p
        match via {
          "direct" => p.online
          "relay" => 0xD9962BFFL
          "offline" => p.red
          _ => p.muted
        }
      }))
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// People overlapping a little, each ringed in the page's ground (people_stack's, as nodes): side by side, each drawn 5
/// over the one before it, the first over them all.
fn people_stack_node(v : @view.View, src : Source, people : Array[Person], size : Double, stint : () -> Int) -> Unit {
  let step = size + 3.0
  let n = people.length()
  v.width(Is(Some(step * n.to_double()))).height(Is(Some(step))) |> ignore
  // (the last made first, each under the one after it in the tree's order)
  for j in 0..<n {
    let i = n - 1 - j
    let p = people[i]
    v.box(fn(d) {
      d
      .over(Is(true))
      .width(Is(Some(step)))
      .height(Is(Some(step)))
      .radius(Is(step / 2.0))
      .offset(Is(((step - 5.0) * i.to_double(), 0.0)))
      .ground(By(fn() { @sf.theme().p.bg }))
      .row(Is(true))
      .lines_up(Is(Some(Middle)))
      .lies_along(Is(Middle))
      |> ignore
      @sf.avatar_node(
        d,
        fn() { p.id },
        fn() { p.display },
        fn() { if p.picture != "" { (src.picture)(p.picture, stint()) } else { "" } },
        size,
      )
    })
    |> ignore
  }
}

///|
/// An agent's mark in the bar (model_mark's, as nodes), `size` square: its maker's mark on a soft tile, its state on
/// the corner.
fn model_mark_node(v : @view.View, a : Agent, size : Double) -> Unit {
  v.box(fn(m) {
    m.width(Is(Some(size))).height(Is(Some(size))) |> ignore
    mark_tile_node(m, a, size)
    @sfpages.agent_badge_node(m, a.badge, size)
  })
  |> ignore
}

///|
/// The maker's tile of an agent's mark, `size` square, its maker's mark in its middle.
fn mark_tile_node(v : @view.View, a : Agent, size : Double) -> Unit {
  v.box(fn(t) {
    t
    .width(Is(Some(size)))
    .height(Is(Some(size)))
    .radius(Is(mark_corner(size)))
    .ground(By(fn() { mark_ground().0 }))
    .edge(By(fn() { (mark_ground().1, @sf.theme().p.line) }))
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    |> ignore
    @sf.maker_mark_node(t, a.maker, a.runtime, mark_logo(size)) |> ignore
  })
  |> ignore
}

///|
/// The chat's first agent with the station it runs on, one tile (agent_station_mark's, as nodes): the maker's square,
/// then the station's mark or name; the agent's state on the maker's corner, how the station is reached on the tile's.
/// Until the station is known, the agent's mark alone.
fn agent_station_node(v : @view.View, a : Agent, station : Station?, stint : () -> Int) -> Unit {
  let m = mark_side()
  match station {
    None => model_mark_node(v, a, m)
    Some(s) =>
      v.box(fn(o) {
        o.box(fn(tile) {
          tile
          .row(Is(true))
          .height(Is(Some(m)))
          .radius(Is(6.0))
          .ground(By(fn() { mark_ground().0 }))
          .edge(By(fn() { (mark_ground().1, @sf.theme().p.line) }))
          .lines_up(Is(Some(Middle)))
          |> ignore
          tile.box(fn(mk) {
            mk.width(Is(Some(m))).height(Is(Some(m))).row(Is(true)).lines_up(Is(Some(Middle))).lies_along(Is(Middle))
            |> ignore
            @sf.maker_mark_node(mk, a.maker, a.runtime, mark_logo(m)) |> ignore
          })
          |> ignore
          // the station's part: its mark, or its name kept short
          let (most, inside, said_line) = station_part_type()
          tile.box(fn(sp) {
            sp.max_width(Is(Some(most))).padding(Is((inside, 0.0, inside, 0.0))).row(Is(true)).lines_up(Is(Some(Middle)))
            |> ignore
            if @sf.has_station_mark(s.emoji, s.icon) {
              @sf.station_mark_node(sp, fn() { s.emoji }, fn() { s.icon }, mark_station(), fn() { @sf.theme().p.muted }, stint)
            } else {
              sp.box(fn(t) {
                t
                .words(Is(s.name))
                .words_look(By(fn() {
                  { size: @sf.theme().t.caption, weight: 400, line: said_line, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
                }))
                .ink(By(fn() { @sf.theme().p.muted }))
                .cuts(Is(true))
                .min_width(Is(Some(0.0)))
                |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        })
        |> ignore
        // the agent's state on the maker's corner, how the station is reached on the tile's: each 3 past it
        o.box(fn(over) {
          over.over(Is(true)) |> ignore
          over.box(fn(b) {
            b.over(Is(true)).width(Is(Some(m))).height(Is(Some(m))) |> ignore
            @sfpages.agent_badge_node(b, a.badge, m)
          })
          |> ignore
          if s.via != "" {
            over.box(fn(d) {
              d.over(Is(true)).lines_up(Is(Some(End))) |> ignore
              d.box(fn(at) {
                at.offset(Is((3.0, m - 7.0))) |> ignore
                via_dot_node(at, s.via, 10.0, 2.0)
              })
              |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
  }
}
