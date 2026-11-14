// A chat's bar on 中屏 and 大屏 (chat_page.mbt's chat_bar) as nodes of the window's tree, made once over the chat's page
// (chat_page_made's `over`), changed as what it shows does: its title (while a new one goes, that one with a turning
// ring; a red mark a while where it did not), its station while no agent is in it (its card over it), its people, its
// agents (each its history beside the chat, its card on hover; the first one tile with the station it runs on); at its
// end ⌘F's bar while the find is open in it (find_bar_node), else 归档 while nothing is left in it, its services and
// jobs, its station's screens, 对话信息, "…" and the side panel's switch while the panel is closed, none of them where
// the system's bars have them (rail_native.mbt's bar_chat, handed as the old view builds). Where it keeps clear at its
// ends is the frame's (ChatBarEnds: the window's corner on 大屏, the page's panel's on the tape); laid out as the old
// bar was, by the same styles. What opens under it (its info, its jobs) is the old view's as yet, opened by the signals
// its buttons set, beside them (chat_bar_from).

///|
/// Where a chat's bar keeps clear at its ends and over its buttons, as the frame it is in says (chat_bar_wide_node's):
/// how much taller it is over its buttons (`over`: the tape's line), how far it is moved in from its ends while the
/// folded sidebar is shown a while (`margins`, before and after: less than none before, drawn moved back), its room
/// at its start (`start`) and at its end (`end`, given whether the side panel is open beside it and ⌘F's bar is in it),
/// the corner its buttons share with the window's (`linked`: none on the tape), its ground as drawn in node `bar`
/// (`ground`: the page's; on the tape, the page's panel's, a step darker while that is behind the one in use).
pub(all) struct ChatBarEnds {
  over : () -> Double
  margins : () -> (Double, Double)
  start : () -> Double
  end : (Bool, Bool) -> Double
  linked : () -> @ui.CornerOf?
  ground : (@view.View) -> Int64
}

///|
/// The bar of the chat page `page` is (none over any other page) in node `v`, over the page's old view, from source
/// `src`, keeping clear at its ends as `ends` says; its tips in `tips`, its pictures asked for on the page's time on
/// top, `stint`.
pub fn chat_bar_wide_node(
  v : @view.View,
  src : Source,
  page : () -> Page?,
  ends : ChatBarEnds,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  let chat = fn() {
    match page() {
      Some(Chat(r)) => Some(r)
      _ => None
    }
  }
  // (by the chat it is of: another one become in its place another bar)
  v.pick(fn() { chat().map(fn(r) { (r.station, r.session) }) }, fn(b, which) {
    guard which is Some(_) else { return }
    guard @signals.untracked(chat) is Some(r) else { return }
    wide_bar_of(b, src, r, ends, tips, stint)
  })
}

///|
/// Chat `r`'s bar in `b` (chat_bar_wide_node's): its row as page_bar_row's (as high as a bar is, with what is over its
/// buttons; its margins while the folded sidebar is shown a while), its box (chat_bar_box's: its line under it, the
/// page's ground; its empty part dragging the window where the window's buttons are the app's), its rooms at its ends.
fn wide_bar_of(b : @view.View, src : Source, r : ChatRef, ends : ChatBarEnds, tips : @sf.TipLayer, stint : () -> Int) -> Unit {
  let view = fn() { view_of_chat(src, r).0 }
  // (what opens under it where the chat's page is made as nodes, as the bar is made: chat_pops_node; else the old
  // page's, beside its buttons as chat_bar_from says)
  let pops = @signals.untracked(fn() { @sfbase.chat_page_nodes.get() })
  if pops {
    chat_pops_node(b, src, r, view, stint)
  }
  let finding = fn() {
    match view() {
      Some(v) => @sfpages.find_chat() == chat_key(r) && v.thread is Some(_)
      None => false
    }
  }
  let beside = fn() {
    match view() {
      Some(v) => side_of(v).0.length() > 0
      None => false
    }
  }
  let high = fn() { @sf.wide_bar_h + (ends.over)() }
  b.by_room(fn(held, room) {
    held
    .row(Is(true))
    .height(By(fn() { Some(high()) }))
    // (drawn at none while the app's first page waits, as the page's old view is: sfbase's first_page_waits)
    .alpha(By(fn() { if @sfbase.first_page_waits.get() { 0.0 } else { 1.0 } }))
    // (its margins as spaces at its ends, one less than none taken back by drawing the row moved back as far)
    .offset(By(fn() { (dmin(0.0, (ends.margins)().0), 0.0) }))
    |> ignore
    bar_room_node(held, fn() { dmax(0.0, (ends.margins)().0) })
    held.box(fn(bar) {
      @sf.style_node(bar, fn() { chat_bar_box_node }, in_row=true)
      bar
      .ground(By(fn() { (ends.ground)(bar) }))
      .height(By(fn() { Some(high()) }))
      .padding(By(fn() { (0.0, (ends.over)(), 0.0, 1.0) }))
      // (its empty part drags the window, in one with its buttons in the app's top row: what is in it taking presses
      // all the same, so it is said to take them always)
      .presses(Is(true))
      .moves_window(By(fn() { @ui.window_inset() }))
      |> ignore
      bar_room_node(bar, ends.start)
      bar.box(fn(inner) {
        @sf.style_node(inner, fn() { chat_bar_inner }, in_row=true)
        wide_bar_title_row(inner, src, r, view, fn() { room.width() }, tips, stint)
        // ⌘F's bar, in place of the buttons while it is open: it covers none of the chat
        inner.pick(fn() { finding() }, fn(e, open) {
          if open {
            // (what holds it giving way as it does: the old row's had none of its own)
            e.row(Is(true)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
            @sfpages.find_bar_node(
              e,
              src,
              r,
              fn() { view().bind(fn(v) { v.thread }) },
              @sfpages.chat_find_list(r),
              tips,
            )
            |> ignore
          } else {
            wide_bar_keys(e, src, r, view, ends, tips, pops, stint)
          }
        })
      })
      |> ignore
      bar_room_node(bar, fn() { (ends.end)(beside(), finding()) })
    })
    |> ignore
    bar_room_node(held, fn() {
      let (ml, mr) = (ends.margins)()
      mr + dmin(0.0, ml)
    })
  })
  // (as high as the bar, what takes presses in it within it)
  .height(By(fn() { Some(high()) }))
  |> ignore
}

///|
/// The bar's box as chat_bar_box but for its ground, the frame's (ChatBarEnds' `ground`).
// kept across runs: a value (no field of it changes)
let chat_bar_box_node : @ui.Style = @ui.style(row=true, w=@sf.grow, h=@sf.wide_bar_h_size, pb=SPx, align=ACenter)

///|
/// The bar's title row in `inner` (chat_bar_title_row's: never narrower than what is left in it needs, ⌘F's field
/// beside it giving way first): the title, 42% of the bar's width (`across`) at most, 80 at least, cut short; then,
/// once the view is read, its station's tag while no agent is in it, its people (the first to leave the row short of
/// room), its agents (the last but the first leaving next), each made again as what it draws changes. Each of them the
/// row's own (what leaves it, as the old row's boxes: a row leaves out of what it holds, View::fits).
fn wide_bar_title_row(
  inner : @view.View,
  src : Source,
  r : ChatRef,
  view : () -> ChatView?,
  across : () -> Double,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  inner.box(fn(row) {
    @sf.style_node(row, fn() { chat_bar_title_row }, in_row=true)
    row.keeps_held(Is(true)).fits(Is(true)) |> ignore
    wide_bar_title(row, src, r, view, across, tips)
    // (the station the chat runs on, as the workspace's marks have it)
    let station = fn() {
      let w = match @sfbase.workspace_in_view(src).0 {
        Some(w) => w.id
        None => ""
      }
      @sfbase.station_marks(src, w).iter().find_first(fn(x) { x.address == r.station })
    }
    let station_key = fn() {
      match station() {
        Some(s) => "\{s.name}\u{1}\{s.emoji}\u{1}\{s.icon}\u{1}\{s.via}"
        None => ""
      }
    }
    let agents = fn() {
      match view() {
        Some(v) => v.agents
        None => []
      }
    }
    // (who is in it by its title, beside the system's bars too: the user, 2026-10-28)
    row.show(fn() { view() is Some(_) && agents().length() == 0 && station() is Some(_) }, fn(x) {
      x.pick(station_key, fn(y, _) {
        match @signals.untracked(station) {
          Some(s) => wide_station_tag(y, r.station, s, tips, stint)
          None => ()
        }
      })
    })
    let people = fn() {
      match view() {
        Some(v) => v.people
        None => []
      }
    }
    row.show(fn() { people().length() > 0 }, fn(p) {
      p.drops(Is(chat_bar_drop_people)) |> ignore
      p.pick(fn() { people().map(fn(p) { "\{p.id}\u{1}\{p.display}\u{1}\{p.picture}" }).join("\u{2}") }, fn(q, _) {
        wide_people(q, src, @signals.untracked(people), 5, tips, stint)
      })
    })
    // (each of its agents by what it draws: marked among several while its history shows; the first with the station)
    let agent_key = fn(i : Int, a : Agent) {
      let all = agents()
      let front = match view() {
        Some(v) => side_of(v).1
        None => ""
      }
      let marked = all.length() > 1 && front == a.key
      "\{i}\u{1}\{a.key}\u{1}\{a.maker}\u{1}\{a.runtime}\u{1}\{a.badge}\u{1}\{a.who}\u{1}\{marked}" +
      (if i == 0 { "\u{1}" + station_key() } else { "" })
    }
    let tile = fn(k : @view.View, i : Int) {
      let all = @signals.untracked(agents)
      guard i < all.length() else { return }
      let a = all[i]
      let front = match @signals.untracked(view) {
        Some(v) => side_of(v).1
        None => ""
      }
      let s = if i == 0 { @signals.untracked(station) } else { None }
      wide_agent_tile(k, src, r, a, all.length() > 1 && front == a.key, s, tips, stint)
    }
    row.show(fn() { agents().length() > 0 }, fn(f) {
      f.pick(fn() { agent_key(0, agents()[0]) }, fn(k, _) { tile(k, 0) })
    })
    row.each(
      fn() {
        let all = agents()
        Array::makei(dmax_int(0, all.length() - 1), fn(j) { (j + 1, agent_key(j + 1, all[j + 1])) })
      },
      fn(x) { x.1 },
      fn(k, it) {
        k.drops(Is(chat_bar_drop_agents)) |> ignore
        tile(k, @signals.untracked(fn() { it.get() }).0)
      },
    )
  })
  |> ignore
}

///|
/// The chat's title in its row (chat_title's): while a new one goes (`chat.rename`), that one, a turning ring beside
/// it; its own again where it did not, a red mark there a while saying why.
fn wide_bar_title(
  row : @view.View,
  src : Source,
  r : ChatRef,
  view : () -> ChatView?,
  across : () -> Double,
  tips : @sf.TipLayer,
) -> Unit {
  let on = [("station", r.station), ("session", r.session)]
  let renaming = fn() {
    let mut renaming = ""
    for d in items(src.topic("doing", {}).get().value, "doing") {
      let dv = Some(d)
      if text(dv, "call") == "chat.rename" &&
        text(dv, "stage") != "failed" &&
        on.iter().all(fn(kv) { text(field(dv, "params"), kv.0) == kv.1 }) {
        renaming = text(field(dv, "params"), "title")
      }
    }
    renaming
  }
  // (what shows: the one going while one goes)
  let title = fn() {
    match renaming() {
      "" =>
        match view() {
          Some(v) => v.title
          None => r.title
        }
      now => now
    }
  }
  let failed = fn() { core_failed(src, ["chat.rename"], on) }
  row.box(fn(t) {
    // (42% of the bar at most, 80 at least; giving way with ⌘F's field once the people have left, down to 4 of its
    // letters)
    @sf.style_node(t, fn() { chat_title_room.then(@ui.style(max_w=Fixed(dmax(chat_title_least, across() * chat_title_part)))) }, in_row=true)
    t.shrink(Is(1.0)) |> ignore
    @sf.words_node(
      t,
      title,
      fn() { chat_title_words },
    )
    |> ignore
    // (read out as its words, where they are)
    t.says(By(fn() { Some(@view.said(Text, label=title())) })) |> ignore
  })
  |> ignore
  row.show(fn() { renaming() != "" || failed() is Some(_) }, fn(d) {
    @sfpages.doing_mark_node(d, fn() { renaming() != "" }, failed, size=wide_doing_mark)
    @sf.tip_node(
      tips,
      d,
      fn() {
        match failed() {
          Some(why) => why
          None => @sf.t("web-pages.settings.stations.renaming")
        }
      },
      within=true,
    )
    |> ignore
  })
}

///|
/// The doing mark's size beside the title (doing_mark's, not inline: 14).
let wide_doing_mark : Double = 14.0

///|
/// The machine the chat runs on beside its title while it has no agent to share a tile with (chat_station's): how it is
/// reached a dot before it, its mark, its name, a quiet tag, its words' ink and the strong line under the hand; its
/// card over it as the pointer rests there, from the presenters as a finger taps it.
fn wide_station_tag(m : @view.View, address : String, s : Station, tips : @sf.TipLayer, stint : () -> Int) -> Unit {
  m.box(fn(k) {
    // (a mouse's press on it the bar's: lit by the pointer within it)
    let hot = fn() { @sf.lit_within_node(k) }
    @sf.style_node(
      k,
      fn() {
        let look = if hot() { chat_station_hot } else { chat_station_tag }
        if s.via != "" {
          look.then(@ui.style(pl=@sf.room_of(chat_station_dot_in)))
        } else {
          look
        }
      },
      in_row=true,
    )
    k.says(Is(Some(@view.said(Group, label=s.name)))) |> ignore
    @sf.hover_card_node(tips, k, fn(c) { @settings.station_peek_card_node(c, address, stint) }, tile=true, padded=false, tapped=fn() {
      @settings.open_station_peek(address, from=Node(k))
    })
    |> ignore
    if s.via != "" {
      wide_via_dot(k, s.via)
    }
    if @sf.has_station_mark(s.emoji, s.icon) {
      @sf.station_mark_node(k, fn() { s.emoji }, fn() { s.icon }, chat_station_mark, fn() {
        if hot() {
          @sf.theme().p.text
        } else {
          @sf.theme().p.muted
        }
      }, stint)
    }
    @sf.words_node(k, fn() { s.name }, fn() { if hot() { chat_station_words_hot } else { chat_station_words } }) |> ignore
  })
  |> ignore
}

///|
/// How a station is reached as a dot (via_dot's).
fn wide_via_dot(parent : @view.View, via : String) -> Unit {
  parent.box(fn(d) {
    @sf.style_node(
      d,
      fn() {
        match via {
          "direct" => via_direct
          "relay" => via_relay
          "offline" => via_offline
          _ => via_waiting
        }
      },
      in_row=true,
    )
  })
  |> ignore
}

///|
/// People overlapping a little (people_stack's): `most` of them at most, each a 16 circle ringed in the sidebar's
/// ground (their picture, or their initial on the paper), each over the one before; more, +n after them; their names in
/// its tip.
fn wide_people(
  parent : @view.View,
  src : Source,
  people : Array[Person],
  most : Int,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  let shown = if people.length() > most { people[:most].to_owned() } else { people }
  parent.box(fn(row) {
    @sf.style_node(row, fn() { people_row }, in_row=true)
    for i, p in shown {
      row.box(fn(ring) {
        @sf.style_node(
          ring,
          fn() {
            let t = @sf.theme()
            people_ring.then(@ui.style(bg=Data(t.p.sidebar))).then(if i == 0 { person_first } else { person_next })
          },
          in_row=true,
        )
        if p.picture != "" {
          // (the picture as the core gives it: Source.picture)
          @sf.avatar_node(ring, fn() { p.id }, fn() { p.display }, fn() { (src.picture)(p.picture, stint()) }, person_side)
        } else {
          // its initial on the paper, 600
          ring.box(fn(l) {
            @sf.style_node(l, fn() { people_letter_box.then(@ui.style(bg=Data(@sf.theme().p.paper))) })
            @sf.words_node(l, fn() { person_initial(p.display) }, fn() { people_letter }) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
    if people.length() > most {
      row.box(fn(n) {
        @sf.style_node(n, fn() { people_more_box }, in_row=true)
        @sf.words_node(n, fn() { "+\{people.length() - most}" }, fn() { people_more }) |> ignore
      })
      |> ignore
    }
    // (read out as a group named by what it shows, each one's letter and the more after them, as the old row's box was:
    // nothing pressed in it)
    let named = shown.map(fn(p) { person_initial(p.display) }) +
      (if people.length() > most { ["+\{people.length() - most}"] } else { [] })
    row.says(Is(Some(@view.said(Group, label=named.join(" "))))) |> ignore
    @sf.tip_node(
      tips,
      row,
      fn() {
        @sf.t("web-main.people.in", args=[("names", people.map(fn(p) { p.display }).join(@sf.t("web-main.list.separator")))])
      },
      within=true,
    )
    |> ignore
  })
  |> ignore
}

///|
/// One of the chat's agents in the bar (agent_tile's): its mark (20), pressed its history's tab opens (in front,
/// closes); its card as the pointer rests on it; marked among several while its history shows. The chat's first, one
/// tile with the station it runs on (`station`: its mark, or its name kept short; how it is reached a dot on the
/// tile's corner); with touch the tile itself the button, held its card and its station's as one.
fn wide_agent_tile(
  parent : @view.View,
  src : Source,
  r : ChatRef,
  a : Agent,
  marked : Bool,
  station : Station?,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  let said = fn() { @sf.t("web-pages.chat.historyOf", args=[("agent", a.who)]) }
  let badge_said = fn() { text(field(agent_json(src.topic("chat", chat_params(r)).get().value, a.key), "session"), "badgeText") }
  let toggle = fn() { side_toggle(src, r, a.key) }
  // (its card, given the hand's card: what is opened from it stands beside it; kept open while that is)
  let hand : Ref[@sf.HoverHand?] = Ref(None)
  let held : Ref[() -> Bool] = Ref(fn() { false })
  let card = fn() {
    match hand.val {
      Some(h) => (h.card)()
      None => None
    }
  }
  match station {
    Some(s) if @sf.tile_whole() =>
      // (with touch the tile itself the button, as it is drawn: tapped its history's; held, its card and its
      // station's as one: the user, 2026-10-27: 它们是一体的)
      parent.box(fn(t) {
        @sf.style_node(t, fn() { if marked { agent_station_on } else { agent_station } }, in_row=true)
        t.says(By(fn() { Some(@view.said(Button, label=said())) })) |> ignore
        hand.val = Some(
          @sf.hover_card_node(
            tips,
            t,
            fn(c) {
              c.box(fn(o) {
                @sf.style_node(o, fn() { tile_card_agent })
                held.val = @sfpages.agent_card_node(o, src, r, a.key, tips, card, across=true)
              })
              |> ignore
              @settings.station_peek_part_node(c, r.station, stint)
            },
            tile=true,
            padded=false,
            held=fn() { (held.val)() },
            press=toggle,
          ),
        )
        let hot = fn() { @sf.lit_node(t) }
        t.box(fn(g) {
          @sf.style_node(g, fn() { if hot() { agent_station_agent_hot } else { agent_station_agent } }, in_row=true)
          wide_tile_seam(g, true)
          wide_agent_mark(g, a, badge_said, joined=true)
        })
        |> ignore
        t.box(fn(p) {
          @sf.style_node(p, fn() { if hot() { agent_station_part_hot } else { agent_station_part } }, in_row=true)
          wide_tile_seam(p, false)
          wide_station_part(p, s, fn() { false }, stint)
        })
        |> ignore
        wide_tile_dot(t, s.via)
      })
      |> ignore
    Some(s) =>
      parent.box(fn(t) {
        @sf.style_node(t, fn() { if marked { agent_station_on } else { agent_station } }, in_row=true)
        let agent = t.box(fn(g) {
          let hot = fn() { @sf.lit_node(g) }
          @sf.style_node(g, fn() { if hot() { agent_station_agent_hot } else { agent_station_agent } }, in_row=true)
          wide_tile_seam(g, true)
          g.says(By(fn() { Some(@view.said(Button, label=said())) })) |> ignore
          hand.val = Some(
            @sf.hover_card_node(
              tips,
              g,
              fn(c) { held.val = @sfpages.agent_card_node(c, src, r, a.key, tips, card) },
              tile=true,
              held=fn() { (held.val)() },
              press=toggle,
            ),
          )
          wide_agent_mark(g, a, badge_said, joined=true)
        })
        t.box(fn(p) {
          // (a mouse's press on it the bar's: lit by the pointer within it, but where the agent's half reaches over it
          // (its room a press's, the press there the agent's): that half's alone there, lit and its card)
          let hot = fn() { @sf.lit_within_node(p, yields_to=agent) }
          @sf.style_node(p, fn() { if hot() { agent_station_part_hot } else { agent_station_part } }, in_row=true)
          wide_tile_seam(p, false)
          p.says(Is(Some(@view.said(Group, label=s.name)))) |> ignore
          @sf.hover_card_node(tips, p, fn(c) { @settings.station_peek_card_node(c, r.station, stint) }, tile=true, padded=false, yields_to=agent, tapped=fn() {
            @settings.open_station_peek(r.station, from=Node(p))
          })
          |> ignore
          wide_station_part(p, s, hot, stint)
        })
        |> ignore
        wide_tile_dot(t, s.via)
      })
      |> ignore
    None =>
      parent.box(fn(t) {
        @sf.style_node(t, fn() { if marked { agent_mark_btn_on } else { agent_mark_btn } }, in_row=true)
        t.says(By(fn() { Some(@view.said(Button, label=said())) })) |> ignore
        hand.val = Some(
          @sf.hover_card_node(
            tips,
            t,
            fn(c) { held.val = @sfpages.agent_card_node(c, src, r, a.key, tips, card) },
            tile=true,
            held=fn() { (held.val)() },
            press=toggle,
          ),
        )
        wide_agent_mark(t, a, badge_said, joined=false)
      })
      |> ignore
  }
}

///|
/// An agent's mark in the bar (agent_mark's, 20 across): its maker's mark on its tile (none of its own where `joined`:
/// the tile it is in paints its ground and hover), its badge at its corner, said as `said` says.
fn wide_agent_mark(parent : @view.View, a : Agent, said : () -> String, joined~ : Bool) -> Unit {
  parent.box(fn(m) {
    @sf.style_node(
      m,
      fn() {
        (if joined { wide_mark_contents } else { wide_mark_tile }).then(
          @ui.style(w=Fixed(wide_mark_side), h=Fixed(wide_mark_side), radius=@sf.agent_mark_corner(wide_mark_side)),
        )
      },
      in_row=true,
    )
    m.says(By(fn() { if said() == "" { None } else { Some(@view.said(Group, label=said())) } })) |> ignore
    @sf.maker_mark_node(m, a.maker, a.runtime, (wide_mark_side * wide_logo_of).round()) |> ignore
    @sfpages.agent_badge_node(m, a.badge, wide_mark_side)
  })
  |> ignore
}

///|
/// The mark's side in the bar, and how large its maker's mark is on it (agent_mark's .62).
let wide_mark_side : Double = 20.0

///|
let wide_logo_of : Double = 0.62

///|
// kept across runs: a value (no field of it changes)
let wide_mark_tile : @ui.Style = @ui.css("bg=Neutral align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let wide_mark_contents : @ui.Style = @ui.css("align=ACenter justify=JCenter")

///|
/// A half of the first agent's tile round at its outer end alone (agent_station_agent's and agent_station_part's
/// corners, which style_node does not take: square where the two meet), the agent's at its start (`first`).
fn wide_tile_seam(half : @view.View, first : Bool) -> Unit {
  let (r, s) = (agent_station_round, agent_station_seam)
  half.corners(Is(Some(if first { (r, s, s, r) } else { (s, r, r, s) }))) |> ignore
}

///|
/// The station's part of the first agent's tile: its mark (12; the words' ink while `hot`), or its name kept short.
fn wide_station_part(p : @view.View, s : Station, hot : () -> Bool, stint : () -> Int) -> Unit {
  if @sf.has_station_mark(s.emoji, s.icon) {
    @sf.station_mark_node(p, fn() { s.emoji }, fn() { s.icon }, chat_station_mark, fn() {
      if hot() {
        @sf.theme().p.text
      } else {
        @sf.theme().p.muted
      }
    }, stint)
  } else {
    @sf.words_node(p, fn() { s.name }, fn() { if hot() { chat_station_words_hot } else { chat_station_words } }) |> ignore
  }
}

///|
/// How the station is reached, a dot on the tile's bottom right corner, 3 past it, over the tile (none: "").
fn wide_tile_dot(t : @view.View, via : String) -> Unit {
  guard via != "" else { return }
  t.box(fn(o) {
    o.over(Is(true)) |> ignore
    @sf.style_node(o, fn() { agent_station_dot_room })
    o.box(fn(d) { @sf.style_node(d, fn() { corner_dot_of(via) }) }) |> ignore
  })
  |> ignore
}

///|
/// The bar's buttons at its end in `e` (chat_bar's keys_row, none where the system's bars have them): 归档 while
/// nothing is left in it, its services and jobs (a dot while one died lately or a service restarts), its station's
/// screens, 对话信息, "…", the side panel's switch while the panel is closed and an agent is in it.
fn wide_bar_keys(
  e : @view.View,
  src : Source,
  r : ChatRef,
  view : () -> ChatView?,
  ends : ChatBarEnds,
  tips : @sf.TipLayer,
  pops : Bool,
  stint : () -> Int,
) -> Unit {
  e.box(fn(k) {
    @sf.style_node(k, fn() { @sf.keys_row() }, in_row=true)
    let own = fn() { view() is Some(_) && !@sf.native_on() }
    let scope = fn() {
      match @sfbase.workspace_in_view(src).0 {
        Some(w) => w.id
        None => ""
      }
    }
    let chat = fn() { src.topic("chat", chat_params(r)).get().value }
    // nothing left in it (the core's `archivable`): archived with one press
    k.show(
      fn() {
        own() &&
        (match view() {
          Some(v) => v.archivable && !v.archived
          None => false
        })
      },
      fn(b) {
        @sf.icon_button_node(b, "archive", fn() { @sf.t("web-pages.chat.archive") }, fn() {
          match (@signals.untracked(view), @signals.untracked(fn() { @sfbase.workspace_in_view(src).0 })) {
            (Some(v), Some(w)) => archive_asked(src, w, r, v, @signals.untracked(chat))
            _ => ()
          }
        }, tips~, linked=ends.linked, shortcut="chat.archive")
        |> ignore
      },
    )
    // its services and jobs, while it has any
    let jobs = fn() { src.topic("chatJobs", chat_jobs_summary_params(r)).get().value }
    let has_jobs = fn() { flag(jobs(), "hasJobs") || items(jobs(), "jobs").length() > 0 }
    k.show(fn() { own() && has_jobs() }, fn(b) {
      let button = @sf.icon_button_node(b, "web", fn() { @sf.t("web-pages.chat.services") }, fn() { jobs_toggle() }, tips~, linked=ends.linked, shortcut="chat.jobs")
      // (its popover beside it, where it is as that is drawn: the nodes' (chat_pops_node), or the old page's
      // (chat_page's chat_bar_by))
      chat_bar_from.jobs_node = Some(button)
      if pops {
        chat_jobs_pop_node(b, src, r, Some(button))
      }
    })
    // (a dot on the row's first button, as the old bar's layer stood, drawn after its services' button: red while a
    // job died lately, amber while a service restarts)
    let alarm = fn() { if own() && has_jobs() { text(jobs(), "alarm") } else { "" } }
    k.show(fn() { alarm() != "" }, fn(o) {
      o.over(Is(true)) |> ignore
      @sf.style_node(o, fn() { jobs_alarm_room })
      o.box(fn(d) { @sf.style_node(d, fn() { if alarm() == "fail" { jobs_alarm_fail } else { jobs_alarm_restart } }) })
      |> ignore
    })
    // the way to its station's screens, while it has any; marked while an agent drives one
    k.show(
      fn() {
        own() &&
        (match view() {
          Some(v) => v.screens.length() > 0
          None => false
        })
      },
      fn(b) {
        b.box(fn(sb) {
          let me : Ref[@view.View?] = Ref(None)
          let button = @sf.icon_button_node(sb, "monitor", fn() { @sf.t("web-pages.chat.screen") }, fn() {
            match (@signals.untracked(view), me.val) {
              (Some(v), Some(at)) => chat_screens_open(r, v.screens, from=Node(at))
              _ => ()
            }
          }, tips~, linked=ends.linked, shortcut="chat.screen")
          me.val = Some(button)
          // (no count on it: how many there are is its menu's; the user, 2026-11-13: a count on the icon's corner hid it)
          let driven = fn() {
            match view() {
              Some(v) => chat_screens_driven(v.screens)
              None => false
            }
          }
          sb.show(driven, fn(o) {
            // (over the button, not after it: the old view's layer)
            o.over(Is(true)) |> ignore
            @sf.style_node(o, fn() { jobs_alarm_room })
            o.box(fn(d) { @sf.style_node(d, fn() { screen_driven_dot }) }) |> ignore
          })
        })
        |> ignore
      },
    )
    // what it is (its info's popover beside it: the nodes' (chat_pops_node), or the old view's, opened or closed as it is
    // let go), what is done with it ("…": the menu a row of the sidebar has)
    k.show(own, fn(b) {
      let button = @sf.icon_button_node(b, "info", fn() { @sf.t("web-pages.chat.info") }, fn() {
        chat_own.info_open.set(!chat_own.info_open.untracked())
      }, tips~, linked=ends.linked)
      chat_bar_from.info_node = Some(button)
      if pops {
        chat_info_pop_node(b, src, r, view, stint, Some(button))
      }
    })
    k.show(own, fn(b) {
      let me : Ref[@view.View?] = Ref(None)
      me.val = Some(
        @sf.icon_button_node(b, "more", fn() { @sf.t("common.more") }, fn() {
          let extra = @sfpages.chat_extra_items(src, r, @signals.untracked(chat))
          match me.val {
            Some(at) => @sfpages.open_chat_menu(src, @signals.untracked(scope), r, extra, from=Node(at), along=End)
            None => ()
          }
        }, tips~, linked=ends.linked),
      )
    })
    // the side panel's switch while it is closed: the first agent's history in it
    k.show(
      fn() {
        own() &&
        (match view() {
          Some(v) => side_of(v).0.length() == 0 && v.agents.length() > 0
          None => false
        })
      },
      fn(b) {
        @sf.icon_button_node(b, "panel-open", fn() { @sf.t("web-pages.chat.openPanel") }, fn() {
          match @signals.untracked(view) {
            Some(v) if v.agents.length() > 0 => side_change(src, r, "open", Some(v.agents[0].key))
            _ => ()
          }
        }, tips~, linked=ends.linked, shortcut="chat.history")
        |> ignore
      },
    )
  })
  |> ignore
}

///|
/// The bar's info and jobs buttons as they were last made (what the old view's popovers open beside, where each is as
/// they are drawn, and a press on which is no press outside them: chat_page's chat_bar_by).
priv struct ChatBarFrom {
  mut info_node : @view.View?
  mut jobs_node : @view.View?
}

///|
// kept across runs: put back by chat_page_reset
let chat_bar_from : ChatBarFrom = { info_node: None, jobs_node: None }
