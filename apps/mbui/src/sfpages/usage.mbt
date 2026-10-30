// 用量, one page in every frame (ember web/src/cloud/settings.tsx UsageSettings; the narrow app's mobile/Usage.tsx; Usage.tsx UsageBody, Tiles, DaysChart, Bar,
// Rankings, Ranking, Row, Notes; Usage.css.ts): what the agents spent over the last 7 or 30 days (picked at the page's
// head), as the core's `usage` view says it: a few totals (the first the way to the prices), each day's cost as a bar
// split by who it was for (the day pointed at or picked says its numbers, and with several people what each spent),
// who, which chats, which accounts and which models spent the most, how it is counted. Everything shown is the
// core's: the page only picks the days, the day and the list shown.

///|
/// What the page picked: its days, the day clicked ("" the last) and the one pointed at ("" none), the list shown
/// ("" the people's) and whether all of it.
priv struct UsagePick {
  days : @signals.Signal[Int]
  day : @signals.Signal[String]
  pointed : @signals.Signal[String]
  list : @signals.Signal[String]
  all : @signals.Signal[Bool]
}

///|
// kept across runs: said by the page's picks; usage_reset puts it back
let usage_pick : UsagePick = {
  days: @signals.signal(7, same=fn(a, b) { a == b }),
  day: @signals.signal("", same=fn(a, b) { a == b }),
  pointed: @signals.signal("", same=fn(a, b) { a == b }),
  list: @signals.signal("", same=fn(a, b) { a == b }),
  all: @signals.signal(false, same=fn(a, b) { a == b }),
}

///|
fn usage_reset() -> Unit {
  usage_pick.days.set(7)
  usage_pick.day.set("")
  usage_pick.pointed.set("")
  usage_pick.list.set("")
  usage_pick.all.set(false)
}

///|
/// The days the page shows (Usage.tsx DAYS).
// kept across runs: a table, never written
let usage_days_choices : Array[Int] = [7, 30]

///|
/// 用量 (UsageSettings): its head (what it counts by a mark beside its title), the days at its end and 分享卡片 once
/// something was spent; the view once read, a wait till then, what went wrong.
pub fn usage_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let days = usage_pick.days.get()
  let topic = (core.topic)("usage", { "scope": str(here.workspace), "days": Json::number(days.to_double()) })
  let v = topic.value
  let body : Array[() -> Unit] = []
  match (v, topic.error) {
    (Some(_), _) =>
      body.push(fn() { usage_body(c, core, look, v) })
    (None, Some(e)) =>
      body.push(fn() {
        c.text(@sf.t("web-pages.settings.usage.failed", args=[("error", error_text(e))]), style=desk_note_bad) |> ignore
      })
    (None, None) => body.push(fn() { @sf.waiting(c, fn() { usage_body(c, core.quiet(), look, Some(usage_sample())) }) })
  }
  @sf.page(c, on_back=core.pop, frame~, "usage/" + days.to_string(),
    @sf.t("web-pages.settings.usage.title"),
    about=@sf.t("web-pages.settings.usage.lead"),
    actions=fn() {
      // the card to share of the agents' week, once something was spent (as 用量's card over the rail offers it:
      // 2026-10-26 用户「分享放到 usage 的 hover 卡片上」), before the days (they stand in the bar's corner, as they did):
      // its mark alone, named in its tip, beside the days on a phone's line too
      if v is Some(_) && !flag(v, "empty") &&
        @sf.icon_button(c, "photo", key="usage-share", label=@sf.t("web-main.stations.shareCard")) {
        (core.share_card)()
      }
      let at = if days == 30 { 1 } else { 0 }
      let labels = usage_days_choices.map(fn(n) { @sf.t("web-main.usage.days", args=[("n", n.to_string())]) })
      let picked = @sf.segmented(c, "usage-days", labels, at)
      if picked != at {
        usage_pick.days.set(usage_days_choices[picked])
        usage_pick.day.set("")
      }
    },
    body,
  )
}

///|
/// The page's body under its head (UsageBody): the totals, the days and the lists (or that nothing was spent, or what
/// it waits on), how it is counted; 28 apart.
fn usage_body(c : @ui.Ctx, core : Core, look : Look, v : Json?) -> Unit {
  c.box(style=ug_body, fn() {
    usage_totals(c, core, v)
    if flag(v, "empty") {
      let wait = field(v, "wait")
      let failing = failing_of(wait)
      if flag(wait, "reading") || failing.length() > 0 {
        @sf.waiting(c, fn() { usage_shown(c, core.quiet(), look, Some(usage_sample())) }, note={
          reading: flag(wait, "reading"),
          text: "",
          failing,
        })
      } else {
        c.box(style=ug_empty_box, fn() { c.text(@sf.t("web-main.usage.none"), style=ug_empty) |> ignore }) |> ignore
      }
    } else {
      usage_shown(c, core, look, v)
    }
    usage_notes(c, v)
  })
  |> ignore
}

///|
/// What was spent (`v`): the days, the lists; narrow, each on a card, as the narrow app's.
fn usage_shown(c : @ui.Ctx, core : Core, look : Look, v : Json?) -> Unit {
  match look {
    Narrow => {
      c.box(style=ug_narrow_card, fn() { usage_chart(c, v) }) |> ignore
      c.box(style=ug_narrow_card, fn() { usage_rankings(c, core, v) }) |> ignore
    }
    Wide => {
      usage_chart(c, v)
      usage_rankings(c, core, v)
    }
  }
}

///|
/// What was spent, made up, for what the page shows while it is read (usage_body in its bones): the four totals, a
/// week's days, the people's list.
fn usage_sample() -> Json {
  let w = fn(n : Int) { Json::string(@sf.sample_words(n)) }
  let costs = [3.0, 5.0, 2.0, 6.0, 4.0, 7.0, 5.0]
  let top = 8.0
  {
    "tiles": Json::array([0, 1, 2, 3].map(fn(_) { Json::object({ "label": w(2), "value": w(4), "sub": w(5) }) })),
    "daily": Json::array(
      costs.mapi(fn(i, cost) {
        Json::object({
          "day": Json::string("sample" + i.to_string()),
          "name": w(3),
          "costText": w(4),
          "callsText": w(3),
          "cost": Json::number(cost),
          "parts": [Json::number(cost)],
        })
      }),
    ),
    "series": [{ "key": "sample" }],
    "top": Json::number(top),
    "ticks": [{ "value": Json::number(top / 2.0), "label": w(2) }, { "value": Json::number(top), "label": w(2) }],
    "lists": [
      {
        "key": "people",
        "title": w(2),
        "items": Json::array(
          [0.5, 0.3, 0.15, 0.05].mapi(fn(i, share) {
            Json::object({
              "key": Json::string("sample" + i.to_string()),
              "title": w(4),
              "sub": w(6),
              "costText": w(3),
              "shareText": w(2),
              "share": Json::number(share),
            })
          }),
        ),
      },
      { "key": "chats", "title": w(2), "items": [] },
      { "key": "models", "title": w(2), "items": [] },
    ],
    "basis": w(24),
  }
}

///|
/// The totals, four in a row (Tiles): what each is, its figure large, a line under it; the first's the way to the
/// prices (查看价目表 under it, the hover's ground under the pointer).
fn usage_totals(c : @ui.Ctx, core : Core, v : Json?) -> Unit {
  // (four in a row, or two over two where four have not the room: in pairs that go on in lines, never three and one,
  // as the web's narrow page has them)
  let tiles = items(v, "tiles")
  c.box(style=ug_tiles, flow=true, fn() {
    for k in 0..<((tiles.length() + 1) / 2) {
      c.box(style=ug_pair, keep=true, fn() { usage_tile_pair(c, core, tiles, k * 2) }) |> ignore
    }
  })
  |> ignore
}

///|
/// The two tiles from `from` (one where it is the last).
fn usage_tile_pair(c : @ui.Ctx, core : Core, tiles : Array[Json], from : Int) -> Unit {
  for i in from..<@cmp.minimum(from + 2, tiles.length()) {
    let tv = Some(tiles[i])
    let prices = i == 0
    let id = if prices { c.id("usage-prices") } else { 0 }
    if prices {
      if c.clicked(id) {
        (core.push)(UsagePrices(usage_pick.days.get()))
      }
    }
    let b = c.box(style=if prices { ug_tile_link } else { ug_tile }, id~, fn() {
      c.text(text(tv, "label"), style=ug_tile_label) |> ignore
      c.text(text(tv, "value"), style=ug_tile_value) |> ignore
      c.text(if prices { @sf.t("web-main.usage.seePrices") } else { text(tv, "sub") }, style=ug_tile_sub) |> ignore
    })
    if prices {
      c.semantics(b, Link, id~, label=@sf.t("web-main.usage.costPrices"))
    }
  }
}

///|
/// A series' colour (Usage.tsx seriesClass): the first four people's own, the rest the strong line's grey.
fn usage_series_ink(series : Array[Json], i : Int) -> Int64 {
  if i < series.length() && text(Some(series[i]), "key") == "" {
    // (the rest's: a grey that still stands off the card where its day's bar is faded, ug_bar_off)
    @sf.theme().p.subtle
  } else {
    @sf.usage_series(i)
  }
}

///|
/// Each day's cost as a bar on the scale's lines, split by who it was for (DaysChart): the day under the finger, else
/// the one pointed at, else the one picked, else the last says its numbers over them (the others' bars faded), and with
/// several people what each spent that day under them. The days and their dates are one drag across: a finger slid
/// over them shows the day under it as it goes, and the day it lets go on stays picked.
fn usage_chart(c : @ui.Ctx, v : Json?) -> Unit {
  let t = @sf.theme()
  let daily = items(v, "daily")
  let series = items(v, "series")
  let top = number(v, "top")
  let many = flag(v, "many")
  let find = fn(key : String) -> Json? {
    match daily.search_by(fn(d) { key != "" && text(Some(d), "day") == key }) {
      Some(i) => Some(daily[i])
      None => None
    }
  }
  // the day nearest a finger's x, by the columns drawn last frame
  let under = fn(x : Double) -> String {
    let mut best = ""
    let mut gap = 0.0
    for d in daily {
      let key = text(Some(d), "day")
      match c.rect_of(c.id("usage-day/" + key)) {
        Some((cx, _, cw, _)) => {
          let g = (x - (cx + cw / 2.0)).abs()
          if best == "" || g < gap {
            best = key
            gap = g
          }
        }
        None => ()
      }
    }
    best
  }
  let area = c.id("usage-days")
  let mut finger = ""
  match c.drag_of(area) {
    Some(d) => {
      let tapped = d.take_tap()
      let ended = d.take_end()
      if d.down || tapped || ended {
        finger = under(d.x)
      }
      if (tapped || ended) && finger != "" {
        usage_pick.day.set(finger)
      }
    }
    None => ()
  }
  let day = match find(finger) {
    Some(d) => Some(d)
    None =>
      match find(usage_pick.pointed.get()) {
        Some(d) => Some(d)
        None =>
          match find(usage_pick.day.get()) {
            Some(d) => Some(d)
            None => daily.last()
          }
      }
  }
  let shown = text(day, "day")
  let mut pointed = ""
  c.box(style=ug_chart, fn() {
    if day is Some(_) {
      let dv = day
      c.box(style=ug_day_head, fn() {
        c.text(text(dv, "name"), style=ug_day_name)
        |> ignore
        c.box(style=ug_day_figures, fn() {
          c.text(text(dv, "costText"), style=ug_day_cost) |> ignore
          c.box(style=ug_day_calls_box, fn() { c.text(text(dv, "callsText"), style=ug_day_calls) |> ignore }) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    c.drag_area(area, axis=Horizontal, w=Fill(1.0), fn() {
      c.box(style=ug_plot, fn() {
        // the scale's lines across under the bars, each said at the right just over it
        if top > 0.0 {
          for k in items(v, "ticks") {
            let y = @sf.usage_plot * (1.0 - number(Some(k), "value") / top)
            c.layer(fn() { c.box(style=ug_tick, ty=y, fn() {  }) |> ignore }) |> ignore
            c.layer(fn() {
              c.box(style=ug_tick_line, ty=y - @sf.usage_tick_rise, fn() {
                c.text(text(Some(k), "label"), style=ug_tick_words) |> ignore
              })
              |> ignore
            })
            |> ignore
          }
        }
        // a day: its whole column is what is clicked, its bar at its foot
        c.box(style=if many { ug_days_many } else { ug_days }, fn() {
          for d in daily {
            let dv = Some(d)
            let key = text(dv, "day")
            let id = c.id("usage-day/" + key)
            if c.clicked(id) {
              usage_pick.day.set(key)
            }
            if c.lit(id) {
              pointed = key
            }
            let b = c.box(style=ug_day, id~, fn() { usage_bar(c, dv, series, top, many, key == shown) })
            c.semantics(b, Button, id~, label=text(dv, "label") + " " + text(dv, "costText"))
          }
        })
        |> ignore
      })
      |> ignore
      c.box(style=ug_base, fn() {  }) |> ignore
      c.box(style=if many { ug_labels_many } else { ug_labels }, fn() {
        for d in daily {
          let dv = Some(d)
          c.box(style=ug_label_cell, fn() {
            c.box(style=ug_label_room, fn() {
              c.text(text(dv, "tick"), style=if text(dv, "day") == shown { ug_label_on } else { ug_label }) |> ignore
            })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
    // with several people: each of them, what they spent the day shown, its share of the day's under it
    if series.length() > 1 && day is Some(_) {
      let shares = items(day, "shares")
      let words = strings(day, "partsText")
      c.box(style=ug_day_rows, fn() {
        for i, s in series {
          // (its share of the day's: the core's)
          let share = match shares.get(i) {
            Some(Number(p, ..)) => p
            _ => 0.0
          }
          let ink = usage_series_ink(series, i)
          c.box(style=ug_day_row, fn() {
            c.box(style=ug_day_row_line, fn() {
              c.box(style=ug_dot.then(@ui.style(bg=Data(ink))), fn() {  }) |> ignore
              c.text(text(Some(s), "name"), style=ug_who) |> ignore
              c.text(words.get(i).unwrap_or(""), style=ug_part_words) |> ignore
            })
            |> ignore
            c.box(style=ug_share_room, fn() {
              c.box(style=ug_share, fn() {
                if share > 0.0 {
                  c.box(style=ug_share_part.then(@ui.style(w=Grow(share), bg=Data(ink))), fn() {  }) |> ignore
                }
                let rest = 1.0 - share
                if rest > 0.0 {
                  c.box(style=ug_share_rest.then(@ui.style(w=Grow(rest))), fn() {  }) |> ignore
                }
              })
              |> ignore
            })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
  })
  |> ignore
  usage_pick.pointed.set(pointed)
  ignore(t)
}

///|
/// A day's bar (Bar), as high as its share of the scale's top, 16 wide at most (as wide as its day with many days):
/// its people's parts one over another, the first at the foot, 1 apart, each round at its ends but the foot's, which
/// stands square on the line (the foot's part a corner longer, cut there). A day other than the one shown is faded.
fn usage_bar(c : @ui.Ctx, dv : Json?, series : Array[Json], top : Double, many : Bool, on : Bool) -> Unit {
  let cost = number(dv, "cost")
  if top <= 0.0 || cost <= 0.0 {
    return
  }
  let parts : Array[(Int, Double)] = []
  for k, p in items(dv, "parts") {
    match p {
      Number(n, ..) if n > 0.0 => parts.push((k, n))
      _ => ()
    }
  }
  if parts.length() == 0 {
    return
  }
  let h = @sf.usage_plot * @cmp.minimum(1.0, cost / top)
  let r = if many { @sf.usage_part_r_many } else { @sf.usage_part_r }
  let room = @cmp.maximum(0.0, h - (parts.length() - 1).to_double())
  let look = (if many { ug_bar_many } else { ug_bar }).then(@ui.style(h=Fixed(h)))
  c.box(style=if on { look } else { look.then(ug_bar_off) }, fn() {
    c.box(style=ug_bar_parts.then(@ui.style(h=Fixed(h + r))), fn() {
      // the top first: the column is laid out from its top, the first person at the foot
      let mut j = parts.length() - 1
      while j >= 0 {
        let (k, p) = parts[j]
        let ph = room * p / cost + (if j == 0 { r } else { 0.0 })
        c.box(
          style=(if many { ug_part_many } else { ug_part }).then(@ui.style(h=Fixed(ph), bg=Data(usage_series_ink(series, k)))),
          fn() {  },
        )
        |> ignore
        j -= 1
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The lists, one at a time (Rankings): which, at their head (the people's first), then the most spent first, the
/// first 8 until all are asked for (Ranking).
fn usage_rankings(c : @ui.Ctx, core : Core, v : Json?) -> Unit {
  let lists = items(v, "lists")
  if lists.length() == 0 {
    return
  }
  let want = if usage_pick.list.get() == "" { "people" } else { usage_pick.list.get() }
  let at = lists.search_by(fn(l) { text(Some(l), "key") == want }).unwrap_or(0)
  let list = Some(lists[at])
  let kind = text(list, "key")
  c.box(style=ug_rankings, fn() {
    c.box(style=ug_list_head, fn() {
      let titles = lists.map(fn(l) { text(Some(l), "title") })
      // (narrow: as wide as the card, each an equal share; wide: each as wide as ug_list_pick_w at least)
      let picked = @sf.segmented(c, "usage-lists", titles, at, item_w=ug_list_pick_w)
      if picked != at {
        usage_pick.list.set(text(Some(lists[picked]), "key"))
        usage_pick.all.set(false)
      }
    })
    |> ignore
    let all_items = items(list, "items")
    c.box(style=ug_rows, fn() {
      for i, it in all_items {
        if usage_pick.all.get() || i < ug_first {
          usage_row(c, core, it, i + 1, kind)
        }
      }
      if all_items.length() > ug_first {
        let id = c.id("usage-all")
        if c.clicked(id) {
          usage_pick.all.set(!usage_pick.all.get())
        }
        let words = if usage_pick.all.get() {
          @sf.t("web-main.fold")
        } else {
          @sf.t("web-main.usage.showAll", args=[("n", all_items.length().to_string())])
        }
        let b = c.box(style=ug_more, id~, fn() {
          c.text(words, style=if c.lit(id) { ug_more_lit } else { ug_more_words }) |> ignore
        })
        c.semantics(b, Button, id~, label=words)
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The first of a list shown until all are asked for (Ranking's `first`).
let ug_first : Int = 8

///|
/// Each of the lists' choice as wide as the widest (Usage.css.ts pickLists: 300 at least for the three).
let ug_list_pick_w : Double = 100.0

///|
/// A person, chat, account or model and what it spent (Row): its rank, or a person's picture; its name over what it
/// is; its cost in bold over its share; a bar of its share under them, from its words on. A chat's opens it (the
/// hover's ground under the pointer).
fn usage_row(c : @ui.Ctx, core : Core, it : Json, rank : Int, kind : String) -> Unit {
  let iv = Some(it)
  let chat = field(iv, "chat")
  let opens = kind == "chats" && chat is Some(Object(_))
  let id = if opens { c.id("usage-item/" + kind + "/" + text(iv, "key")) } else { 0 }
  if opens {
    if c.clicked(id) {
      (core.open_chat)(text(chat, "station"), text(chat, "session"), text(iv, "title"))
    }
  }
  c.box(style=if opens { ug_row_link } else { ug_row }, id~, fn() {
    c.box(style=ug_row_line, fn() {
      let person = field(iv, "person")
      if kind == "people" && person is Some(Object(_)) {
        let shown = field(person, "shown")
        let picture = text(shown, "picture")
        @sf.avatar(
          c,
          match text(person, "email") {
            "" => text(person, "id")
            e => e
          },
          match text(shown, "name") {
            "" => text(iv, "title")
            n => n
          },
          if picture == "" { "" } else { (core.picture)(picture, c.page_stint()) },
          ug_lead,
        )
      } else {
        c.box(style=ug_rank_box, fn() { c.text(rank.to_string(), style=ug_rank) |> ignore }) |> ignore
      }
      c.box(style=ug_row_text, fn() {
        c.text(text(iv, "title"), style=ug_row_title) |> ignore
        c.text(join([text(iv, "sub"), text(iv, "detail")], " · "), style=ug_row_sub) |> ignore
      })
      |> ignore
      c.box(style=ug_row_cost, fn() {
        c.text(text(iv, "costText"), style=ug_cost) |> ignore
        c.text(text(iv, "shareText"), style=ug_row_share_words) |> ignore
      })
      |> ignore
    })
    |> ignore
    c.box(style=ug_row_share_room, fn() {
      c.box(style=ug_share, fn() {
        let share = number(iv, "share")
        let k = if share <= 0.0 { 0.0 } else { @cmp.minimum(1.0, @cmp.maximum(0.01, share)) }
        if k > 0.0 {
          c.box(style=ug_row_share_fill.then(@ui.style(w=Grow(k))), fn() {  }) |> ignore
        }
        let rest = 1.0 - k
        if rest > 0.0 {
          c.box(style=ug_share_rest.then(@ui.style(w=Grow(rest))), fn() {  }) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A row's lead (its rank's room, a person's picture): 20.
let ug_lead : Double = 20.0

///|
/// How it is counted (Notes): the core's notes, then its basis.
fn usage_notes(c : @ui.Ctx, v : Json?) -> Unit {
  c.box(style=ug_notes, fn() {
    let lines = strings(v, "notes")
    lines.push(text(v, "basis"))
    for l in lines {
      if l != "" {
        c.text(l, style=ug_note) |> ignore
      }
    }
  })
  |> ignore
}

// ── styles (Usage.css.ts) ───────────────────────────────────────────────

///|
/// The narrow page's chart and lists each on a card of the ladder's (its words 20 in; what lies in its corners, a
/// share's bar, the lists' choice, round by the ladder's there: mbui works it out).
// kept across runs: a value (no field of it changes)
let ug_narrow_card : @ui.Style = @ui.css("w=Full p=S5 radius=Xl3 bg=Card")

///|
/// The page's parts 28 apart (usage).
// kept across runs: a value (no field of it changes)
let ug_body : @ui.Style = @ui.css("w=Full gap=S7")

///|
/// The totals four in a row, 10 apart (tiles); a tile 14 by 16 in, 2 apart, the card's corner on the card's ground.
// kept across runs: a value (no field of it changes)
let ug_tiles : @ui.Style = @ui.css("row w=Full gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let ug_tile : @ui.Style = @ui.style(w=@sf.grow, min_w=S28, px=S4, py=S3_5, gap=S0_5, radius=Xl3, bg=Card)

///|
/// Two of the totals side by side, sharing what their line has (each 112 at least).
// kept across runs: a value (no field of it changes)
let ug_pair : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S2_5)

///|
// kept across runs: a value (no field of it changes)
let ug_tile_link : @ui.Style = ug_tile.then(@ui.css("hovered{bg=Hover}"))

///|
// kept across runs: a value (no field of it changes)
let ug_tile_label : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Full)

///|
/// Its figure (tileValue: the heading's 22 on 30, 600).
// kept across runs: a value (no field of it changes)
let ug_tile_value : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Fg, wrap=false, w=Full)

///|
/// What it is made of (tileSub), in lines where the tile is narrower than it: none of it cut.
// kept across runs: a value (no field of it changes)
let ug_tile_sub : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, w=Full)

///|
// kept across runs: a value (no field of it changes)
let ug_chart : @ui.Style = @ui.css("w=Full")

///|
/// The day shown over the bars (dayHead: 2 apart, 16 over them): its name, its cost large with its calls beside it, on
/// its baseline.
// kept across runs: a value (no field of it changes)
let ug_day_head : @ui.Style = @ui.css("w=Full pb=S4 gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let ug_day_name : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_day_figures : @ui.Style = @ui.css("row gap=S2 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let ug_day_cost : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_day_calls_box : @ui.Style = @ui.css("pb=S1")

///|
// kept across runs: a value (no field of it changes)
let ug_day_calls : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
/// The plot (150 high), its scale's lines across it, said at the right just over each in the caption's 11 subtle.
// kept across runs: a value (no field of it changes)
let ug_plot : @ui.Style = @ui.style(w=Full, h=@sf.usage_plot_h)

///|
// kept across runs: a value (no field of it changes)
let ug_tick : @ui.Style = @ui.css("w=Full h=SPx bg=Line")

///|
// kept across runs: a value (no field of it changes)
let ug_tick_line : @ui.Style = @ui.css("row w=Full justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let ug_tick_words : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, color=Subtle, wrap=false)

///|
/// The days side by side, 6 apart (2 with many), clear of the scale's words at the right (24).
// kept across runs: a value (no field of it changes)
let ug_days : @ui.Style = @ui.css("row w=Full h=Full pr=S6 gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let ug_days_many : @ui.Style = ug_days.then(@ui.css("gap=S0_5"))

///|
// kept across runs: a value (no field of it changes)
let ug_day : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JEnd")

///|
/// A bar: 16 wide at most (as wide as its day with many), its parts 1 apart, round 4 (2 with many).
// kept across runs: a value (no field of it changes)
let ug_bar : @ui.Style = @ui.style(w=Full, max_w=@sf.usage_bar_max, clip=true)

///|
// kept across runs: a value (no field of it changes)
let ug_bar_many : @ui.Style = @ui.css("w=Full clip")

///|
/// A day's bar but the one shown: faded.
// kept across runs: a value (no field of it changes)
let ug_bar_off : @ui.Style = @ui.css("opacity=O40")

///|
// kept across runs: a value (no field of it changes)
let ug_bar_parts : @ui.Style = @ui.css("w=Full gap=SPx")

///|
// kept across runs: a value (no field of it changes)
let ug_part : @ui.Style = @ui.css("w=Full radius=Base")

///|
// kept across runs: a value (no field of it changes)
let ug_part_many : @ui.Style = @ui.css("w=Full radius=Sm")

///|
/// The plot's foot (its border-bottom).
// kept across runs: a value (no field of it changes)
let ug_base : @ui.Style = @ui.css("w=Full h=SPx bg=Line")

///|
/// Each day's name under its bar (labels: 6 under the plot, as far apart as the days), the one shown in the words' ink
/// in 500; whole, past its day's width on either side when the days are narrow (30 of them on a phone: a date a week).
// kept across runs: a value (no field of it changes)
let ug_labels : @ui.Style = @ui.css("row w=Full pt=S1_5 pr=S6 gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let ug_labels_many : @ui.Style = ug_labels.then(@ui.css("gap=S0_5"))

///|
// kept across runs: a value (no field of it changes)
let ug_label_cell : @ui.Style = @ui.css("w=Full align=ACenter")

///|
/// Room for a date as wide as the widest (今天, 10/31), centred on its day however narrow the day is.
// kept across runs: a value (no field of it changes)
let ug_label_room : @ui.Style = @ui.css("w=S12 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ug_label : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_label_on : @ui.TextStyle = ug_label.then(@ui.text_style(weight=Medium, color=Fg))

///|
/// The people under the days (dayRows: 16 under the labels, 12 apart): a dot 8, who, what they spent; their share's
/// bar 4 high 6 under it, from who on.
// kept across runs: a value (no field of it changes)
let ug_day_rows : @ui.Style = @ui.css("w=Full pt=S4 gap=S3")

///|
// kept across runs: a value (no field of it changes)
let ug_day_row : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let ug_day_row_line : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ug_dot : @ui.Style = @ui.css("w=S2 h=S2 radius=Full")

///|
// kept across runs: a value (no field of it changes)
let ug_who : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let ug_part_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_share_room : @ui.Style = @ui.css("row w=Full pl=S4")

///|
// kept across runs: a value (no field of it changes)
let ug_share : @ui.Style = @ui.css("row w=Full h=S1 radius=Full bg=TintStrong clip")

///|
// kept across runs: a value (no field of it changes)
let ug_share_part : @ui.Style = @ui.css("h=Full radius=Full")

///|
// kept across runs: a value (no field of it changes)
let ug_share_rest : @ui.Style = @ui.css("h=Full")

///|
/// The lists (listHead: their choice, 8 over the rows).
// kept across runs: a value (no field of it changes)
let ug_rankings : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let ug_list_head : @ui.Style = @ui.css("row w=Full pb=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ug_rows : @ui.Style = @ui.css("w=Full")

///|
/// A row (row: 10 by 12 in, the field's corner, 12 apart in a line; its share's bar 6 under).
// kept across runs: a value (no field of it changes)
let ug_row : @ui.Style = @ui.css("w=Full px=S3 py=S2_5 gap=S1_5 radius=Xl")

///|
// kept across runs: a value (no field of it changes)
let ug_row_link : @ui.Style = ug_row.then(@ui.css("hovered{bg=Hover}"))

///|
// kept across runs: a value (no field of it changes)
let ug_row_line : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ug_rank_box : @ui.Style = @ui.css("w=S5 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let ug_rank : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_row_text : @ui.Style = @ui.style(w=@sf.grow, gap=SPx)

///|
// kept across runs: a value (no field of it changes)
let ug_row_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Fg, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let ug_row_sub : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let ug_row_cost : @ui.Style = @ui.css("gap=SPx align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let ug_cost : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Bold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_row_share_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// The share's bar from the row's words on (its lead's 20 and the 12 after it), what it had in the strong line's grey.
// kept across runs: a value (no field of it changes)
let ug_row_share_room : @ui.Style = @ui.css("row w=Full pl=S8")

///|
/// Its share, filled in the quieter words' grey: a step off its track (the line's: ug_share) in either theme, where
/// the edges' grey (Border) was the track's own in the dark.
// kept across runs: a value (no field of it changes)
let ug_row_share_fill : @ui.Style = @ui.css("h=Full radius=Full bg=Subtle")

///|
/// 显示全部 / 收起 (more: 4 under the rows, 6 by 12 in, the field's corner; the hover's ground and the words' ink
/// under the pointer).
// kept across runs: a value (no field of it changes)
let ug_more : @ui.Style = @ui.css("mt=S1 px=S3 py=S1_5 radius=Xl hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let ug_more_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_more_lit : @ui.TextStyle = ug_more_words.then(@ui.text_style(color=Fg))

///|
/// How it is counted (notes: 4 apart, the meta's 12 subtle).
// kept across runs: a value (no field of it changes)
let ug_notes : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let ug_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, w=Full)

///|
/// Nothing spent (empty: 28 over and under, in the middle, the ui's 13 muted).
// kept across runs: a value (no field of it changes)
let ug_empty_box : @ui.Style = @ui.css("w=Full py=S7 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ug_empty : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
/// The prices the usage is counted at (UsagePricesSettings, Usage.tsx PriceTables): each station's, on a card of its own,
/// its name, what its prices are, and a table of its models and their rates (as a message's table is drawn); none, said.
/// The prices are each station's, through the core; no table of the app's own. One page in every frame (the narrow app's
/// UsagePricesScreen too), laid out by its width (page_look.mbt): narrow, each station's card 12 from the page's sides.
pub fn usage_prices_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, days : Int) -> Unit {
  let look = look_of(c)
  let topic = (core.topic)("usage", { "scope": str(here.workspace), "days": Json::number(days.to_double()) })
  let v = topic.value
  let blocks : Array[() -> Unit] = []
  match v {
    None =>
      blocks.push(fn() {
        @sf.waiting(
          c,
          fn() { prices_sample(c) },
          error=match topic.error {
            Some(e) => @sf.t("web-pages.settings.prices.failed", args=[("error", @settings.error_text(e))])
            None => ""
          },
        )
      })
    Some(_) => {
      let tables = items(v, "prices")
      let wait = field(v, "wait")
      // none yet while stations are still read (each failure said), else none to show
      if tables.length() == 0 && (flag(wait, "reading") || failing_of(wait).length() > 0) {
        blocks.push(fn() { block_waiting(c, fn() { prices_sample(c) }, wait~) })
      } else if tables.length() == 0 {
        blocks.push(fn() { up_said(c, look, @sf.t("web-main.usage.noPrices")) })
      }
      for table in tables {
        blocks.push(fn() { price_card(c, Some(table)) })
      }
    }
  }
  @sf.page(c, on_back=core.pop, frame~, "usage-prices/" + days.to_string(),
    @sf.t("web-pages.settings.prices.title"),
    lead=@sf.t("web-pages.settings.prices.lead"),
    blocks,
  )
}

///|
/// A station's prices (`tv`) on a card of its own: its name, what its prices are, and a table of its models and their
/// rates, as a message's table is drawn (`tree`: that table read already, a made-up one's).
fn price_card(c : @ui.Ctx, tv : Json?, tree? : Json? = None) -> Unit {
  @sf.page_card(c, fn() {
    c.text(text(tv, "station"), style=up_station) |> ignore
    c.text(text(tv, "note"), style=desk_note) |> ignore
    let rows = items(tv, "rows")
    if rows.length() == 0 {
      c.text(@sf.t("web-main.usage.noModelUsage"), style=desk_note) |> ignore
    } else {
      // a table as a message's (its model, then each rate)
      let head = [@sf.t("web-main.model.models")]
      head.append(items(Some(rows[0]), "rates").map(fn(r) { text(Some(r), "label") }))
      let line = fn(cells : Array[String]) { "| " + cells.map(fn(x) { x.replace_all(old="|", new="\\|") }).join(" | ") + " |" }
      let md = [line(head), line(head.map(fn(_) { "---" }))]
      for r in rows {
        let cells = [text(Some(r), "model")]
        cells.append(items(Some(r), "rates").map(fn(x) { text(Some(x), "value") }))
        md.push(line(cells))
      }
      // (across the card's foot, its ground reaching past the card's words to the ladder's inset, round by
      // the ladder's next step there: concentric with the card's foot corners)
      c.box(style=up_table_across, fn() {
        @sf.markdown(c, md.join("\n"), key="prices/" + text(tv, "station"), tree~, size=@sf.text_scale.base.0) |> ignore
      })
      |> ignore
    }
  })
}

///|
/// The prices to come while they are read (the library's Waiting, in its bones): a made-up station's card and its
/// table, as price_card draws them.
fn prices_sample(c : @ui.Ctx) -> Unit {
  let w = fn(n : Int) { Json::string(@sf.sample_words(n)) }
  let models = [6, 8, 5, 7]
  let rows = models.map(fn(n) {
    Json::object({ "model": w(n), "rates": Json::array([0, 1, 2].map(fn(_) { Json::object({ "label": w(3), "value": w(4) }) })) })
  })
  let cell = fn(n : Int) { Json::array([Json::string("td"), Json::array([w(n)])]) }
  let row = fn(first : Int) { Json::array([Json::string("tr"), Json::array([cell(first), cell(3), cell(3), cell(3)])]) }
  let table = Json::array([Json::string("table"), Json::array([row(3)] + models.map(row))])
  price_card(c, Some({ "station": w(4), "note": w(18), "rows": Json::array(rows) }), tree=Some(Json::array([table])))
}

///|
/// A station's prices' table at its card's foot (@sf.block_across, and as far past the card's words under it).
// kept across runs: a value (no field of it changes)
let up_table_across : @ui.Style = @ui.css("w=Full").then(@sf.block_across).then(
  @ui.style(mb=@sf.room_of(@sf.corner_inset - @sf.card_pad)),
)

///|
/// What a page says in place of what it lists (none: muted; narrow, 24 in as a page's note is).
fn up_said(c : @ui.Ctx, look : Look, words : String) -> Unit {
  match look {
    Narrow => c.box(style=@sf.pg_lead_box, fn() { c.text(words, style=@sf.pg_lead) |> ignore }) |> ignore
    Wide => c.text(words, style=desk_muted) |> ignore
  }
}

///|
/// A station's name over its prices (priceStation: the title's size, semibold).
// kept across runs: a value (no field of it changes)
let up_station : @ui.TextStyle = @ui.text_style(size=Ui, leading=L7, weight=Semibold, color=Fg, w=Full)
