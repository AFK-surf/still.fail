// What the agents spent (settings/Usage.kt UsageScreen; the core's `usage` view for the last 7 or 30 days, picked in
// the bar): a few totals, each day's cost as a bar split by who it was for (tapped, the day says its numbers), and who,
// which chats, which accounts and which models spent the most. Everything shown is the core's.

///|
priv struct UsageState {
  mut days : Int
  /// the day tapped ("" the last)
  mut day : String
  /// the list shown (-1: none picked yet, the first; in the wide frame the people's, as the web's), and whether all
  /// of it
  mut list : Int
  mut all : Bool
}

///|
let usage_state : UsageState = { days: 7, day: "", list: -1, all: false }

///|
/// The people a day's bar is split by (Usage.kt LIGHT, DARK); the rest in the subtle grey.
// kept across runs: a table, never written
let usage_light : Array[Int64] = [0xEF6A3CFFL, 0x2A78D6FFL, 0x1BAF7AFFL, 0x4A3AA7FFL]

///|
// kept across runs: a table, never written
let usage_dark : Array[Int64] = [0xE0602FFFL, 0x3987E5FFL, 0x199E70FFL, 0x9085E9FFL]

///|
fn series_color(series : Array[Json], i : Int) -> Int64 {
  let t = @sf.theme()
  if i < series.length() && text(Some(series[i]), "key") == "" {
    @sf.alpha(t.p.subtle, 0.45)
  } else {
    (if t.dark { usage_dark } else { usage_light })[i % 4]
  }
}

///|
fn usage_page(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let t = @sf.theme()
  let days = usage_state.days
  let topic = (core.topic)("usage", { "scope": str(here.workspace), "days": Json::number(days.to_double()) })
  let v = topic.value
  let choices = [7, 30]
  place_page(
    c,
    core,
    tr("android-misc.bar.place.usage"),
    about=tr("web-pages.settings.usage.lead"),
    actions=fn() {
      let at = if days == 30 { 1 } else { 0 }
      let picked = seg(c, "usage-days", choices.map(fn(n) { fill("android-misc.usage.days", [("n", n.to_string())]) }), at)
      if picked != at {
        usage_state.days = choices[picked]
        usage_state.day = ""
      }
    },
    fn() {
      let blocks : Array[() -> Unit] = []
      match v {
        None =>
          blocks.push(fn() {
            waiting_cards(
              c,
              error=match topic.error {
                Some(e) => fill("android-misc.usage.loadFailed", [("error", error_text(e))])
                None => ""
              },
            )
          })
        Some(_) => {
          blocks.push(fn() { usage_tiles(c, core, v) })
          let wait = field(v, "wait")
          if flag(v, "empty") && note_waits(wait) {
            blocks.push(fn() { waiting_cards(c, count=2, failing=failing_of(wait)) })
          } else if flag(v, "empty") {
            blocks.push(fn() { place_empty(c, tr("android-misc.usage.none"), note=tr("android-misc.usage.note")) })
          } else {
            // (the wide frame's on the page, as the web's: no card)
            blocks.push(fn() {
              if wide.val {
                inset(c, fn() { usage_days(c, v) })
              } else {
                card(c, fn() { usage_days(c, v) }) |> ignore
              }
            })
            blocks.push(fn() { usage_lists(c, core, v) })
          }
          blocks.push(fn() {
            // (the wide frame's at the column's edge, 28 under the lists, as the web's notes)
            c.box(style=if wide.val { usage_notes_wide } else { usage_notes }, fn() {
              // how it is counted, under what was counted (nothing counted: the empty place says it already)
              let lines = strings(v, "notes")
              if !flag(v, "empty") {
                lines.push(text(v, "basis"))
              }
              for l in lines {
                if l != "" {
                  c.text(l, style=usage_note) |> ignore
                }
              }
            })
            |> ignore
          })
        }
      }
      blocks.push(fn() { gap(c, 30.0) })
      scroll_page(c, "usage/" + days.to_string(), blocks)
    },
  )
}

///|
// kept across runs: a value (no field of it changes)
let usage_tile : @ui.Style = @ui.style(w=@sf.grow, px=S4, py=S3_5, gap=S0_5, radius=Xl3, bg=Card)

///|
// kept across runs: a value (no field of it changes)
let usage_tile_link : @ui.Style = usage_tile.then(@ui.css("hovered{bg=Hover}"))

///|
// kept across runs: a value (no field of it changes)
let usage_tile_label : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false, leading=L5)

///|
// kept across runs: a value (no field of it changes)
let usage_tile_sub : @ui.TextStyle = @ui.text_style(size=Xs, color=Subtle, wrap=false, w=Full, leading=L5)

///|
/// How it is counted, under what was counted: 24 in on a phone, 6 over and under, 4 apart; the meta's 12 subtle.
// kept across runs: a value (no field of it changes)
let usage_notes : @ui.Style = @ui.css("w=Full px=S6 py=S1_5 gap=S1")

///|
// kept across runs: a value (no field of it changes)
let usage_notes_wide : @ui.Style = @ui.css("w=Full px=S4 pt=S7 gap=S1")

///|
// kept across runs: a value (no field of it changes)
let usage_note : @ui.TextStyle = @ui.text_style(size=Xs, color=Subtle, w=Full)

///|
/// The totals, two to a row (Usage.kt Tiles); the first one's last line the way to the prices.
fn usage_tiles(c : @ui.Ctx, core : Core, v : Json?) -> Unit {
  let t = @sf.theme()
  let tiles = items(v, "tiles")
  // (the wide frame's all in a row, as the web's, at the column's edge)
  let per = if wide.val { 4 } else { 2 }
  c.box(style=if wide.val { usage_tiles_wide } else { usage_tiles_box }, fn() {
    let mut i = 0
    while i < tiles.length() {
      let pair = [tiles[i]]
      for j in 1..<per {
        if i + j < tiles.length() {
          pair.push(tiles[i + j])
        }
      }
      let first = i == 0
      c.box(dir=Row, w=Fill(1.0), gap=10.0, fn() {
        for k, tile in pair {
          let tv = Some(tile)
          // the first's last line is the way to the prices
          let pid = if first && k == 0 { c.id("usage-prices") } else { 0 }
          if pid != 0 && hit(c, pid) {
            (core.push)(UsagePrices(usage_state.days))
          }
          let sub = if first && k == 0 { tr("android-misc.usage.seePrices") } else { text(tv, "sub") }
          if wide.val {
            // the web's tile (Usage.css.ts tile: 14 by 16 in, 2 apart, the card's corner; its words on the page's
            // 1.5 lines), the way to the prices the hover's ground under the pointer
            if pid != 0 {
              c.cursor(pid, Hand)
            }
            c.box(style=if pid != 0 { usage_tile_link } else { usage_tile }, id=pid, fn() {
              c.text(text(tv, "label"), style=usage_tile_label) |> ignore
              c.text(text(tv, "value"), style=@sf.title.then(@sf.one_line)) |> ignore
              c.text(sub, style=usage_tile_sub) |> ignore
            })
            |> ignore
            continue
          }
          c.box(w=Fill(1.0), padx=16.0, pady=14.0, radius=18.0, bg=t.p.card, id=pid, fn() {
            c.text(text(tv, "label"), size=12.0, color=t.p.muted, wrap=false, line=17.0) |> ignore
            c.text(text(tv, "value"), style=@sf.title.then(@sf.one_line)) |> ignore
            c.text(sub, size=12.0, color=t.p.subtle, wrap=false, w=Fill(1.0), line=17.0) |> ignore
          })
          |> ignore
        }
        for _ in pair.length()..<per {
          c.box(w=Fill(1.0), fn() {  }) |> ignore
        }
      })
      |> ignore
      i += per
    }
  })
  |> ignore
}

///|
/// The totals' room: 12 in on a phone, 10 under them; in the wide frame 16 in (the column's edge), 8 further under the
/// head than its own room, where the web's are (pageHead: 28 under it), and 28 over the days (the page's sections).
// kept across runs: a value (no field of it changes)
let usage_tiles_box : @ui.Style = @ui.css("w=Full px=S3 pb=S2_5 gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let usage_tiles_wide : @ui.Style = @ui.css("w=Full px=S4 pt=S2 pb=S7 gap=S2_5")

///|
/// Each day's cost as a bar on the scale's lines, split by who it was for (Usage.kt Days): the day tapped (the last at
/// first) says its numbers over them, and with several people what each of them spent that day under them.
fn usage_days(c : @ui.Ctx, v : Json?) -> Unit {
  let daily = items(v, "daily")
  let series = items(v, "series")
  let top = number(v, "top")
  let ticks = items(v, "ticks")
  let several = series.length() > 1
  let many = daily.length() > 10
  let mut day : Json? = None
  for d in daily {
    if text(Some(d), "day") == usage_state.day {
      day = Some(d)
    }
  }
  if day is None && daily.length() > 0 {
    day = Some(daily[daily.length() - 1])
  }
  // the day's numbers over the bars: its cost large, its calls beside it (Usage.kt: by their baselines; here by their
  // feet, the calls lifted to the cost's baseline)
  if day is Some(_) {
    c.text(if flag(day, "today") { tr("android-misc.usage.today") } else { text(day, "label") }, style=usage_day_name)
    |> ignore
    c.box(style=usage_figures, fn() {
      c.text(text(day, "costText"), style=usage_cost_words) |> ignore
      c.box(style=usage_calls_box, fn() { c.text(text(day, "callsText"), style=usage_calls_words) |> ignore }) |> ignore
    })
    |> ignore
  }
  c.box(style=usage_plot_box, fn() {
    // the scale's lines across, each said at the right just over it, where no bar is
    if top > 0.0 {
      for k in ticks {
        let y = @sf.usage_plot * (1.0 - number(Some(k), "value") / top)
        c.layer(fn() { c.box(style=usage_tick_rule, ty=y, fn() {  }) |> ignore }) |> ignore
        c.layer(fn() {
          c.box(style=usage_tick_row, ty=y - @sf.usage_tick_rise, fn() {
            c.text(text(Some(k), "label"), style=usage_tick_words) |> ignore
          })
          |> ignore
        })
        |> ignore
      }
    }
    c.box(style=if many { usage_days_row_many } else { usage_days_row }, fn() {
      for d in daily {
        let dv = Some(d)
        let id = c.id("usage-day/" + text(dv, "day"))
        if hit(c, id) {
          usage_state.day = text(dv, "day")
        }
        c.box(style=usage_day_col, id~, fn() { usage_bar(c, dv, series, top, many) }) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
  c.box(style=usage_base, fn() {  }) |> ignore
  c.box(style=if many { usage_labels_many } else { usage_labels }, fn() {
    let n = daily.length()
    for i, d in daily {
      let dv = Some(d)
      let today = flag(dv, "today")
      let on = text(dv, "day") == text(day, "day")
      let shown = !many || today || (n - 1 - i) % 7 == 0
      c.box(style=usage_label_cell, fn() {
        c.text(
          if !shown {
            ""
          } else if today {
            tr("android-misc.usage.today")
          } else {
            text(dv, "label")
          },
          style=if on { usage_label_on } else { usage_label_words },
        )
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
  // with several people: each of them (the rest too), what they spent that day and its share of the day's
  if several && day is Some(_) {
    let parts = items(day, "parts")
    let words = strings(day, "partsText")
    let cost = number(day, "cost")
    c.box(style=usage_people, fn() {
      for i, s in series {
        let p = if i < parts.length() {
          match parts[i] {
            Number(n, ..) => n
            _ => 0.0
          }
        } else {
          0.0
        }
        let share = if cost > 0.0 { dmin(1.0, dmax(0.0, p / cost)) } else { 0.0 }
        // (a fill as wide as its share: a row of two, Fill by their parts; a little of it shown for a little spent)
        let fill = if share > 0.0 { dmax(share, 0.01) } else { 0.0 }
        let rest = 1.0 - fill
        c.box(style=usage_person, fn() {
          c.box(style=usage_person_row, fn() {
            c.box(style=usage_person_dot, bg=series_color(series, i), fn() {  }) |> ignore
            c.text(text(Some(s), "name"), style=usage_person_name) |> ignore
            c.text(if i < words.length() { words[i] } else { "" }, style=usage_person_part) |> ignore
          })
          |> ignore
          // its share of the day, on the chip's ground
          c.box(style=usage_share_room, fn() {
            c.box(style=usage_share_track, fn() {
              if fill > 0.0 {
                c.box(style=usage_share_fill, w=Fill(fill), bg=series_color(series, i), fn() {  }) |> ignore
              }
              c.box(w=Fill(rest), fn() {  }) |> ignore
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
}

///|
/// A day's bar (Usage.kt Bar), as high as its share of the scale's top, at most 16 wide (as wide as its day once days
/// are many): its people's parts one over another, the first at the foot, 1 apart, each round at its ends but the
/// foot's, which stands square on the line (the foot's part the corner longer, cut there).
fn usage_bar(c : @ui.Ctx, dv : Json?, series : Array[Json], top : Double, many : Bool) -> Unit {
  let cost = number(dv, "cost")
  if top <= 0.0 || cost <= 0.0 {
    return
  }
  let h = @sf.usage_plot * dmin(1.0, cost / top)
  let r = if many { @sf.usage_part_r_many } else { @sf.usage_part_r }
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
  let room = dmax(0.0, h - (parts.length() - 1).to_double())
  let hr = h + r
  c.box(style=if many { usage_bar_many } else { usage_bar_box }, h=Px(h), fn() {
    c.box(style=usage_bar_parts, h=Px(hr), fn() {
      // top first: the column is laid out from the top, the first person at the foot
      let mut j = parts.length() - 1
      while j >= 0 {
        let (k, p) = parts[j]
        let ph = room * p / cost + (if j == 0 { r } else { 0.0 })
        c.box(style=if many { usage_part_many } else { usage_part }, h=Px(ph), bg=series_color(series, k), fn() {  })
        |> ignore
        j -= 1
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The day picked: its name, its cost large (Xl3, as the tiles' figures), its calls beside it lifted onto the cost's
/// baseline.
// kept across runs: a value (no field of it changes)
let usage_day_name : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let usage_figures : @ui.Style = @ui.css("row pt=S0_5 pb=S4 gap=S2 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let usage_cost_words : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let usage_calls_box : @ui.Style = @ui.css("pb=S1")

///|
// kept across runs: a value (no field of it changes)
let usage_calls_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false)

///|
/// The plot, its scale's lines and their words (in the 24 at its right where no bar is), the days 6 apart (2 when many).
// kept across runs: a value (no field of it changes)
let usage_plot_box : @ui.Style = @ui.style(w=Full, h=@sf.usage_plot_h)

///|
// kept across runs: a value (no field of it changes)
let usage_tick_rule : @ui.Style = @ui.css("w=Full h=SPx bg=Line")

///|
// kept across runs: a value (no field of it changes)
let usage_tick_row : @ui.Style = @ui.css("row w=Full justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let usage_tick_words : @ui.TextStyle = @ui.text_style(size=Xs3, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let usage_days_row : @ui.Style = @ui.css("row w=Full h=Full pr=S6 gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let usage_days_row_many : @ui.Style = @ui.css("row w=Full h=Full pr=S6 gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let usage_day_col : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JEnd")

///|
/// A bar: at most 16 wide, cut at the foot; its parts 1 apart, round 4 (2 when many).
// kept across runs: a value (no field of it changes)
let usage_bar_box : @ui.Style = @ui.style(w=Full, max_w=@sf.usage_bar_max, clip=true)

///|
// kept across runs: a value (no field of it changes)
let usage_bar_many : @ui.Style = @ui.css("w=Full clip")

///|
// kept across runs: a value (no field of it changes)
let usage_bar_parts : @ui.Style = @ui.css("w=Full gap=SPx")

///|
// kept across runs: a value (no field of it changes)
let usage_part : @ui.Style = @ui.css("w=Full radius=Base")

///|
// kept across runs: a value (no field of it changes)
let usage_part_many : @ui.Style = @ui.css("w=Full radius=Sm")

///|
/// The days' foot and their dates under it.
// kept across runs: a value (no field of it changes)
let usage_base : @ui.Style = @ui.css("w=Full h=SPx bg=Line")

///|
// kept across runs: a value (no field of it changes)
let usage_labels : @ui.Style = @ui.css("row w=Full pt=S1_5 pr=S6 gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let usage_labels_many : @ui.Style = @ui.css("row w=Full pt=S1_5 pr=S6 gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let usage_label_cell : @ui.Style = @ui.css("w=Full align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let usage_label_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let usage_label_on : @ui.TextStyle = @ui.text_style(size=Xs2, weight=Medium, color=Fg, wrap=false)

///|
/// Each of the day's people: a dot of theirs, their name, what they spent, its share under the name on the chip's
/// ground.
// kept across runs: a value (no field of it changes)
let usage_people : @ui.Style = @ui.css("w=Full pt=S4 gap=S3")

///|
// kept across runs: a value (no field of it changes)
let usage_person : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let usage_person_row : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let usage_person_dot : @ui.Style = @ui.css("w=S2 h=S2 radius=Full")

///|
// kept across runs: a value (no field of it changes)
let usage_person_name : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let usage_person_part : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let usage_share_room : @ui.Style = @ui.css("row w=Full h=S1 pl=S4")

///|
// kept across runs: a value (no field of it changes)
let usage_share_track : @ui.Style = @ui.css("row w=Full h=Full radius=Sm bg=Neutral clip")

///|
// kept across runs: a value (no field of it changes)
let usage_share_fill : @ui.Style = @ui.css("h=Full radius=Sm")

///|
/// The lists, one at a time, the first eight until asked for all (Usage.kt Lists).
fn usage_lists(c : @ui.Ctx, core : Core, v : Json?) -> Unit {
  let t = @sf.theme()
  let lists = items(v, "lists")
  if lists.length() == 0 {
    return
  }
  let at = if usage_state.list >= 0 && usage_state.list < lists.length() {
    usage_state.list
  } else if wide.val {
    // the web's first shown (Usage.tsx Rankings: "people")
    lists.search_by(fn(l) { text(Some(l), "key") == "people" }).unwrap_or(0)
  } else {
    0
  }
  let list = Some(lists[at])
  let kind = text(list, "key")
  // (its Seg, rounded 10, in its top corners: the card's corner taken from it, concentric: Usage.kt:204; the wide
  // frame's on the page, as the web's)
  let body = fn() {
    let picked = seg(c, "usage-lists", lists.map(fn(l) { text(Some(l), "title") }), at, fill=true)
    if picked != at {
      usage_state.list = picked
      usage_state.all = false
    }
    // (8 under its switch in the wide frame: listHead)
    gap(c, if wide.val { 8.0 } else { 6.0 })
    let all_items = items(list, "items")
    let shown : Array[Json] = []
    for i, x in all_items {
      if usage_state.all || i < 8 {
        shown.push(x)
      }
    }
    for i, it in shown {
      if wide.val {
        usage_row_wide(c, core, it, i + 1, kind)
      } else {
        usage_item(c, core, it, i + 1, kind)
      }
    }
    if all_items.length() > 8 {
      c.box(padx=4.0, pady=10.0, fn() {
        if tap_text(
            c,
            "usage-all",
            if usage_state.all {
              tr("android-misc.usage.collapse")
            } else {
              fill("android-misc.usage.showAll", [("n", all_items.length().to_string())])
            },
            color=t.p.muted,
            size=if wide.val { 13.0 } else { 14.0 },
          ) {
          usage_state.all = !usage_state.all
        }
      })
      |> ignore
    }
  }
  if wide.val {
    // 28 under the days, as the page's sections are
    gap(c, 28.0)
    inset(c, body)
  } else {
    card(c, corner=@sf.seg_card_radius, body) |> ignore
  }
}

///|
/// A person, chat, account or model and what it spent (Usage.kt ItemRow): its rank or picture, its name and what it
/// is, its cost and share, a bar of its share under its words. A chat's opens it.
fn usage_item(c : @ui.Ctx, core : Core, it : Json, rank : Int, kind : String) -> Unit {
  let t = @sf.theme()
  let iv = Some(it)
  let chat = field(iv, "chat")
  let opens = kind == "chats" && chat is Some(Object(_))
  let id = c.id("usage-item/" + kind + "/" + text(iv, "key"))
  if opens && hit(c, id) {
    (core.open_chat)(text(chat, "station"), text(chat, "session"), text(iv, "title"))
  }
  c.box(
    w=Fill(1.0),
    pady=10.0,
    radius=12.0,
    id=if opens { id } else { 0 },
    fn() {
      c.box(dir=Row, w=Fill(1.0), gap=12.0, align=ACenter, fn() {
        let person = field(iv, "person")
        if kind == "people" && person is Some(Object(_)) {
          let shown = field(person, "shown")
          avatar(
            c,
            core,
            match text(person, "email") {
              "" => text(person, "id")
              e => e
            },
            match text(shown, "name") {
              "" => text(iv, "title")
              n => n
            },
            22.0,
            picture=text(shown, "picture"),
          )
        } else {
          c.box(w=Px(22.0), align=AEnd, fn() {
            c.text(rank.to_string(), size=12.0, color=t.p.subtle, wrap=false) |> ignore
          })
          |> ignore
        }
        c.box(w=Fill(1.0), fn() {
          c.text(text(iv, "title"), size=15.0, weight=500, color=t.p.text, wrap=false, w=Fill(1.0), line=21.0) |> ignore
          c.text(join([text(iv, "sub"), text(iv, "detail")], " · "), size=12.0, color=t.p.muted, wrap=false, w=Fill(1.0), line=17.0)
          |> ignore
        })
        |> ignore
        c.box(align=AEnd, fn() {
          c.text(text(iv, "costText"), size=15.0, weight=600, color=t.p.text, wrap=false, line=21.0) |> ignore
          c.text(text(iv, "shareText"), size=12.0, color=t.p.muted, wrap=false, line=17.0) |> ignore
        })
        |> ignore
      })
      |> ignore
      c.box(w=Fill(1.0), pl=34.0, pt=6.0, fn() {
        c.box(dir=Row, w=Fill(1.0), h=Px(4.0), radius=2.0, bg=t.p.chip, clip=true, fn() {
          let share = number(iv, "share")
          let k = if share <= 0.0 { 0.0 } else { dmin(1.0, dmax(0.01, share)) }
          if k > 0.0 {
            c.box(w=Fill(k), h=Fill(1.0), bg=@sf.alpha(t.p.subtle, 0.5), fn() {  }) |> ignore
          }
          if k < 1.0 {
            c.box(w=Fill(1.0 - k), h=Fill(1.0), fn() {  }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
      // Usage.kt ItemRow: a chat's clickable over its clip, Smooth(LIST_ROW_CORNER)
      if opens {
        @motion.ripple(c, id, @sf.row_corner)
      }
    },
  )
  |> ignore
}

///|
/// A row of the lists in the wide frame, as the web's (Usage.css.ts row: 10 by 12 in, 12 apart; its rank 20 wide at
/// its end in the meta's 12 subtle, or a person's picture 20; its title the ui's 13 in 500 over what it is in the
/// meta's muted, 1 apart; its cost in bold over its share; its share's bar 4 high 6 under them, from its words on). A
/// chat's is the hover's ground under the pointer and opens it.
fn usage_row_wide(c : @ui.Ctx, core : Core, it : Json, rank : Int, kind : String) -> Unit {
  let t = @sf.theme()
  let iv = Some(it)
  let chat = field(iv, "chat")
  let opens = kind == "chats" && chat is Some(Object(_))
  let id = c.id("usage-item/" + kind + "/" + text(iv, "key"))
  if opens {
    c.cursor(id, Hand)
    if hit(c, id) {
      (core.open_chat)(text(chat, "station"), text(chat, "session"), text(iv, "title"))
    }
  }
  c.box(style=if opens { usage_row_link } else { usage_row }, id=if opens { id } else { 0 }, fn() {
    c.box(style=usage_row_line, fn() {
      let person = field(iv, "person")
      if kind == "people" && person is Some(Object(_)) {
        let shown = field(person, "shown")
        avatar(
          c,
          core,
          match text(person, "email") {
            "" => text(person, "id")
            e => e
          },
          match text(shown, "name") {
            "" => text(iv, "title")
            n => n
          },
          usage_lead,
          picture=text(shown, "picture"),
        )
      } else {
        c.box(style=usage_rank_box, fn() { c.text(rank.to_string(), style=usage_rank) |> ignore }) |> ignore
      }
      c.box(style=usage_row_text, fn() {
        c.text(text(iv, "title"), style=usage_row_title) |> ignore
        c.text(join([text(iv, "sub"), text(iv, "detail")], " · "), style=usage_row_sub) |> ignore
      })
      |> ignore
      c.box(style=usage_row_cost, fn() {
        c.text(text(iv, "costText"), style=usage_cost) |> ignore
        c.text(text(iv, "shareText"), style=usage_row_sub_end) |> ignore
      })
      |> ignore
    })
    |> ignore
    c.box(style=usage_row_share_room, fn() {
      c.box(style=usage_row_share_track, fn() {
        let share = number(iv, "share")
        let k = if share <= 0.0 { 0.0 } else { dmin(1.0, dmax(0.01, share)) }
        if k > 0.0 {
          c.box(style=usage_row_share_fill, w=Fill(k), fn() {  }) |> ignore
        }
        if k < 1.0 {
          c.box(w=Fill(1.0 - k), fn() {  }) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  ignore(t)
}

///|
/// A row's lead (its rank's room, a person's picture): 20.
let usage_lead : Double = 20.0

///|
// kept across runs: a value (no field of it changes)
let usage_row : @ui.Style = @ui.css("w=Full px=S3 py=S2_5 gap=S1_5 radius=Xl")

///|
// kept across runs: a value (no field of it changes)
let usage_row_link : @ui.Style = usage_row.then(@ui.css("hovered{bg=Hover}"))

///|
// kept across runs: a value (no field of it changes)
let usage_row_line : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let usage_rank_box : @ui.Style = @ui.css("w=S5 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let usage_rank : @ui.TextStyle = @ui.text_style(size=Xs, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let usage_row_text : @ui.Style = @ui.style(w=@sf.grow, gap=SPx)

///|
// kept across runs: a value (no field of it changes)
let usage_row_title : @ui.TextStyle = @ui.text_style(size=Lg, weight=Medium, color=Fg, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let usage_row_sub : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let usage_row_sub_end : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let usage_row_cost : @ui.Style = @ui.css("gap=SPx align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let usage_cost : @ui.TextStyle = @ui.text_style(size=Lg, weight=Bold, color=Fg, wrap=false)

///|
/// The share's bar: from the row's words on (its lead's 20 and the 12 after it), 4 high on the hover's ground, what
/// it had in the strong line's grey.
// kept across runs: a value (no field of it changes)
let usage_row_share_room : @ui.Style = @ui.css("w=Full pl=S8")

///|
// kept across runs: a value (no field of it changes)
let usage_row_share_track : @ui.Style = @ui.css("row w=Full h=S1 radius=Full bg=Hover clip")

///|
// kept across runs: a value (no field of it changes)
let usage_row_share_fill : @ui.Style = @ui.css("h=Full radius=Full bg=Border")
