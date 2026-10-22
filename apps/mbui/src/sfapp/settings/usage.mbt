// What the agents spent (settings/Usage.kt UsageScreen; the core's `usage` view for the last 7 or 30 days, picked in
// the bar): a few totals, each day's cost as a bar split by who it was for (tapped, the day says its numbers), and who,
// which chats, which accounts and which models spent the most. Everything shown is the core's.

///|
priv struct UsageState {
  mut days : Int
  /// the day tapped ("" the last)
  mut day : String
  /// the list shown, and whether all of it
  mut list : Int
  mut all : Bool
}

///|
let usage_state : UsageState = { days: 7, day: "", list: 0, all: false }

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
            blocks.push(fn() { card(c, fn() { usage_days(c, v) }) |> ignore })
            blocks.push(fn() { usage_lists(c, core, v) })
          }
          blocks.push(fn() {
            c.box(w=Fill(1.0), padx=24.0, pady=6.0, gap=4.0, fn() {
              // how it is counted, under what was counted (nothing counted: the empty place says it already)
              let lines = strings(v, "notes")
              if !flag(v, "empty") {
                lines.push(text(v, "basis"))
              }
              for l in lines {
                if l != "" {
                  c.text(l, size=12.0, color=t.p.subtle, w=Fill(1.0), line=17.0) |> ignore
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
/// The totals, two to a row (Usage.kt Tiles); the first one's last line the way to the prices.
fn usage_tiles(c : @ui.Ctx, core : Core, v : Json?) -> Unit {
  let t = @sf.theme()
  let tiles = items(v, "tiles")
  c.box(w=Fill(1.0), padx=12.0, pb=10.0, gap=10.0, fn() {
    let mut i = 0
    while i < tiles.length() {
      let pair = [tiles[i]]
      if i + 1 < tiles.length() {
        pair.push(tiles[i + 1])
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
          c.box(w=Fill(1.0), padx=16.0, pady=14.0, radius=18.0, bg=t.p.card, id=pid, fn() {
            c.text(text(tv, "label"), size=12.0, color=t.p.muted, wrap=false, line=17.0) |> ignore
            c.text(text(tv, "value"), style=@sf.title.then(@sf.one_line)) |> ignore
            c.text(
              if first && k == 0 {
                tr("android-misc.usage.seePrices")
              } else {
                text(tv, "sub")
              },
              size=12.0,
              color=t.p.subtle,
              wrap=false,
              w=Fill(1.0),
              line=17.0,
            )
            |> ignore
          })
          |> ignore
        }
        if pair.length() == 1 {
          c.box(w=Fill(1.0), fn() {  }) |> ignore
        }
      })
      |> ignore
      i += 2
    }
  })
  |> ignore
}

///|
/// Each day's cost as a bar split by who it was for (Usage.kt Days): the day tapped (the last at first) says its
/// numbers under them.
fn usage_days(c : @ui.Ctx, v : Json?) -> Unit {
  let t = @sf.theme()
  let daily = items(v, "daily")
  let series = items(v, "series")
  let max = number(v, "max")
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
  let gap_w = if many { 3.0 } else { 6.0 }
  if several {
    c.box(dir=Row, w=Fill(1.0), pb=10.0, gap=12.0, align=ACenter, fn() {
      for i, s in series {
        c.box(dir=Row, gap=5.0, align=ACenter, fn() {
          c.box(w=Px(8.0), h=Px(8.0), radius=2.0, bg=series_color(series, i), fn() {  }) |> ignore
          c.text(text(Some(s), "name"), size=12.0, color=t.p.muted, wrap=false) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  }
  c.box(dir=Row, w=Fill(1.0), h=Px(150.0), gap=gap_w, fn() {
    for d in daily {
      let dv = Some(d)
      let id = c.id("usage-day/" + text(dv, "day"))
      if hit(c, id) {
        usage_state.day = text(dv, "day")
      }
      let on = text(dv, "day") == text(day, "day")
      c.box(w=Fill(1.0), h=Fill(1.0), radius=4.0, bg=if on { t.p.chip } else { 0L }, align=ACenter, justify=JEnd, id~, fn() {
        let cost = number(dv, "cost")
        if max > 0.0 && cost > 0.0 {
          let share = dmin(1.0, dmax(0.0, cost / max))
          c.box(w=Fill(1.0), max_w=28.0, h=Px(150.0 * share), radius=4.0, clip=true, gap=2.0, justify=JEnd, fn() {
            let parts = items(dv, "parts")
            let mut k = parts.length() - 1
            while k >= 0 {
              let p = match parts[k] {
                Number(n, ..) => n
                _ => 0.0
              }
              if p > 0.0 {
                c.box(w=Fill(1.0), h=Fill(dmax(p / cost, 0.001)), bg=series_color(series, k), fn() {  }) |> ignore
              }
              k -= 1
            }
          })
          |> ignore
        }
      })
      |> ignore
    }
  })
  |> ignore
  c.box(w=Fill(1.0), h=Px(1.0), bg=t.p.line, fn() {  }) |> ignore
  c.box(dir=Row, w=Fill(1.0), pt=6.0, gap=gap_w, fn() {
    let n = daily.length()
    for i, d in daily {
      let dv = Some(d)
      let today = flag(dv, "today")
      let shown = !many || today || (n - 1 - i) % 7 == 0
      c.box(w=Fill(1.0), align=ACenter, fn() {
        c.text(
          if !shown {
            ""
          } else if today {
            tr("android-misc.usage.today")
          } else {
            text(dv, "label")
          },
          size=11.0,
          color=if today { t.p.text } else { t.p.subtle },
          wrap=false,
        )
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
  match day {
    Some(_) =>
      c.box(w=Fill(1.0), pt=12.0, gap=3.0, fn() {
        c.text(
          (if flag(day, "today") { tr("android-misc.usage.today") } else { text(day, "label") }) +
          " · " +
          text(day, "costText") +
          " · " +
          text(day, "callsText"),
          size=13.0,
          weight=500,
          color=t.p.text,
          w=Fill(1.0),
          line=18.0,
        )
        |> ignore
        if several && number(day, "cost") > 0.0 {
          let parts = items(day, "parts")
          let words = strings(day, "partsText")
          for i, s in series {
            let p = if i < parts.length() {
              match parts[i] {
                Number(n, ..) => n
                _ => 0.0
              }
            } else {
              0.0
            }
            if p > 0.0 {
              c.box(dir=Row, w=Fill(1.0), gap=6.0, align=ACenter, fn() {
                c.box(w=Px(8.0), h=Px(8.0), radius=2.0, bg=series_color(series, i), fn() {  }) |> ignore
                c.text(text(Some(s), "name"), size=12.0, color=t.p.muted, wrap=false, w=Fill(1.0)) |> ignore
                c.text(if i < words.length() { words[i] } else { "" }, size=12.0, color=t.p.muted, wrap=false) |> ignore
              })
              |> ignore
            }
          }
        }
      })
      |> ignore
    None => ()
  }
}

///|
/// The lists, one at a time, the first eight until asked for all (Usage.kt Lists).
fn usage_lists(c : @ui.Ctx, core : Core, v : Json?) -> Unit {
  let t = @sf.theme()
  let lists = items(v, "lists")
  if lists.length() == 0 {
    return
  }
  let at = if usage_state.list < lists.length() { usage_state.list } else { 0 }
  let list = Some(lists[at])
  let kind = text(list, "key")
  // (its Seg, rounded 10, in its top corners: the card's corner taken from it, concentric: Usage.kt:204)
  card(c, corner=@sf.seg_card_radius, fn() {
    let picked = seg(c, "usage-lists", lists.map(fn(l) { text(Some(l), "title") }), at, fill=true)
    if picked != at {
      usage_state.list = picked
      usage_state.all = false
    }
    gap(c, 6.0)
    let all_items = items(list, "items")
    let shown : Array[Json] = []
    for i, x in all_items {
      if usage_state.all || i < 8 {
        shown.push(x)
      }
    }
    for i, it in shown {
      usage_item(c, core, it, i + 1, kind)
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
            size=14.0,
          ) {
          usage_state.all = !usage_state.all
        }
      })
      |> ignore
    }
  })
  |> ignore
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
    bg=if opens && c.pressed(id) { @sf.alpha(t.p.text, 0.05) } else { 0L },
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
    },
  )
  |> ignore
}
