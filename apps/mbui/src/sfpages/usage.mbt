// 用量, one page in every frame (ember web/src/cloud/settings.tsx UsageSettings; the narrow app's mobile/Usage.tsx;
// Usage.tsx; Usage.css.ts): what the agents spent over the last 7 or 30 days (picked at the page's head), as the core's
// `usage` view says it, laid out by what someone opening it wants to know, most first:
// - whether the spending is as it should be: the cost of the days large, against the days before as many, the days'
//   bars (one pressed seen alone), and what it is made of (a bar of who spent it, or of the models with one person),
//   all on a card in the page's theme;
// - whether the subscriptions last: each one's allowance (what is left, when it fills) beside what it spent;
// - what the money went to: the chats that cost the most, each with who it was for and its model, opened from there;
// - who, which models and which accounts: the three side by side, the first few and the rest, one pressed seen alone;
// - the calls and tokens, under the rest.
// Everything shown is the core's: the page only picks the days, the one alone and the day.

///|
/// What the page picked: its days, the day seen alone ("" all), whether all the chats are shown, and the one seen
/// alone (its list and key; "" none).
priv struct UsagePick {
  days : @signals.Signal[Int]
  day : @signals.Signal[String]
  all : @signals.Signal[Bool]
  only : @signals.Signal[(String, String)]
}

///|
// kept across runs: said by the page's picks; usage_reset puts it back
let usage_pick : UsagePick = {
  days: @signals.signal(7, same=fn(a, b) { a == b }),
  day: @signals.signal("", same=fn(a, b) { a == b }),
  all: @signals.signal(false, same=fn(a, b) { a == b }),
  only: @signals.signal(("", ""), same=fn(a, b) { a == b }),
}

///|
fn usage_reset() -> Unit {
  usage_pick.days.set(7)
  usage_pick.day.set("")
  usage_pick.all.set(false)
  usage_pick.only.set(("", ""))
}

///|
/// The days the page shows (Usage.tsx DAYS).
// kept across runs: a table, never written
let usage_days_choices : Array[Int] = [7, 30]

///|
/// 用量 (UsageSettings): its head (what it counts by a mark beside its title), the days at its end and 分享卡片 once
/// something was spent; the view once read, a wait till then, what went wrong.
pub fn usage_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let days = usage_pick.days.get()
  let topic = (core.topic)("usage", usage_args(here, days))
  let v = topic.value
  let body : Array[() -> Unit] = []
  match (v, topic.error) {
    (Some(_), _) =>
      body.push(fn() { usage_body(c, core, v) })
    (None, Some(e)) =>
      body.push(fn() {
        c.text(@sf.t("web-pages.settings.usage.failed", args=[("error", error_text(e))]), style=desk_note_bad) |> ignore
      })
    (None, None) => body.push(fn() { @sf.waiting(c, fn() { usage_body(c, core.quiet(), Some(usage_sample())) }) })
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
/// What the page asks the core's `usage` view for: its workspace's `days`, of the one picked alone, of the day picked.
fn usage_args(here : Here, days : Int) -> Map[String, Json] {
  let args : Map[String, Json] = { "scope": str(here.workspace), "days": Json::number(days.to_double()) }
  let (only_list, only_key) = usage_pick.only.get()
  if only_list != "" {
    args["only"] = { "list": str(only_list), "key": str(only_key) }
  }
  if usage_pick.day.get() != "" {
    args["day"] = str(usage_pick.day.get())
  }
  args
}

///|
/// The page's body under its head: the overview, then (once something was spent) the allowances, the chats, what it is
/// made of, the days and the calls and tokens, each on a card 16 apart; or that nothing was spent, or what it waits
/// on; how it is counted last.
fn usage_body(c : @ui.Ctx, core : Core, v : Json?) -> Unit {
  c.box(style=ug_body, fn() {
    usage_overview(c, core, v)
    if flag(v, "empty") {
      let wait = field(v, "wait")
      let failing = failing_of(wait)
      if flag(wait, "reading") || failing.length() > 0 {
        @sf.waiting(c, fn() { usage_shown(c, core.quiet(), Some(usage_sample())) }, note={
          reading: flag(wait, "reading"),
          text: "",
          failing,
        })
      } else {
        c.box(style=ug_card, fn() {
          c.box(style=ug_empty_box, fn() { c.text(@sf.t("web-main.usage.none"), style=ug_empty) |> ignore }) |> ignore
        })
        |> ignore
      }
    } else {
      usage_shown(c, core, v)
    }
    usage_notes(c, v)
  })
  |> ignore
}

///|
/// What was spent (`v`), under the overview (the days' bars are on it): the allowances (where any), the chats, what it
/// is made of, the calls and tokens.
fn usage_shown(c : @ui.Ctx, core : Core, v : Json?) -> Unit {
  usage_accounts(c, v)
  usage_chats(c, core, v)
  usage_makeup(c, v)
  usage_details(c, v)
}

///|
/// What was spent, made up, for what the page shows while it is read (usage_shown in its bones): the totals, a week's
/// days, a few chats and the makeup.
fn usage_sample() -> Json {
  let w = fn(n : Int) { Json::string(@sf.sample_words(n)) }
  let costs = [3.0, 5.0, 2.0, 6.0, 4.0, 7.0, 5.0]
  let top = 8.0
  let items = fn(n : Int) {
    Json::array(
      [0.5, 0.3, 0.15, 0.05].mapi(fn(i, share) {
        Json::object({
          "key": Json::string("sample\{n}/\{i}"),
          "title": w(4),
          "sub": w(6),
          "costText": w(3),
          "shareText": w(2),
          "share": Json::number(share),
        })
      }),
    )
  }
  let list = fn(key : String, n : Int) {
    Json::object({ "key": Json::string(key), "title": w(2), "items": items(n), "parts": items(n) })
  }
  {
    "tiles": Json::array([0, 1, 2, 3].map(fn(_) { Json::object({ "label": w(2), "value": w(4), "sub": w(5) }) })),
    "daily": Json::array(
      costs.mapi(fn(i, cost) {
        Json::object({
          "day": Json::string("sample" + i.to_string()),
          "name": w(3),
          "tick": w(3),
          "costText": w(4),
          "callsText": w(3),
          "cost": Json::number(cost),
        })
      }),
    ),
    "top": Json::number(top),
    "ticks": [{ "value": Json::number(top / 2.0), "label": w(2) }, { "value": Json::number(top), "label": w(2) }],
    "lists": [list("people", 0), list("chats", 1), list("profiles", 2), list("models", 3)],
    "basis": w(24),
  }
}

///|
/// What was spent in all: the cost of the days large against the days before, the way to the prices at its head's end;
/// the days' bars under it in the theme's accent, one pressed seen alone; a bar of what it
/// is made of (who spent it, or the models where one person did) with each part named under it; what the page is
/// narrowed to (one alone, a day) said last, each taken off there.
fn usage_overview(c : @ui.Ctx, core : Core, v : Json?) -> Unit {
  let tiles = items(v, "tiles")
  if tiles.length() == 0 {
    return
  }
  let cost = Some(tiles[0])
  c.box(style=ug_card, fn() {
    c.box(style=ug_hero_head, flow=true, fn() {
      let period = text(v, "period")
      c.text(if period == "" { text(cost, "label") } else { text(cost, "label") + " · " + period }, style=ug_hero_label)
      |> ignore
      usage_prices_link(c, core)
    })
    |> ignore
    c.box(style=ug_hero_figures, flow=true, fn() {
      c.text(text(cost, "value"), style=ug_hero_value) |> ignore
      usage_change(c, v, cost)
    })
    |> ignore
    if !flag(v, "empty") && items(v, "daily").length() > 0 {
      usage_chart(c, v)
    }
    // what it is made of: the list the core splits by (people where several spent, else models)
    let lists = items(v, "lists")
    match lists.search_by(fn(l) { text(Some(l), "key") == text(v, "split") }) {
      Some(i) if !flag(v, "empty") => usage_split_bar(c, Some(lists[i]))
      _ => ()
    }
    usage_narrowed(c, v)
  })
  |> ignore
}

///|
/// 查看价目表 →, the way to the prices the cost is counted at.
fn usage_prices_link(c : @ui.Ctx, core : Core) -> Unit {
  let id = c.id("usage-prices")
  if c.clicked(id) {
    (core.push)(UsagePrices(usage_pick.days.get()))
  }
  let b = c.box(style=ug_prices, id~, fn() {
    c.text(@sf.t("web-main.usage.seePrices"), style=if c.lit(id) { ug_prices_lit } else { ug_prices_words }) |> ignore
  })
  c.semantics(b, Link, id~, label=@sf.t("web-main.usage.costPrices"))
}

///|
/// A list's first few and the rest as one bar, each its share of it in its colour 2 apart, and under it each named
/// with what it spent (a dot of its colour first); one pressed is seen alone (not a chat's, nor the rest).
fn usage_split_bar(c : @ui.Ctx, list : Json?) -> Unit {
  let kind = text(list, "key")
  let parts = items(list, "parts")
  if parts.length() == 0 {
    return
  }
  c.box(style=ug_split, fn() {
    c.box(style=ug_split_bar, fn() {
      for i, p in parts {
        let share = number(Some(p), "share")
        if share > 0.0 {
          c.box(style=ug_split_part.then(@ui.style(w=Grow(share), bg=Data(usage_part_ink(parts, i)))), fn() {  })
          |> ignore
        }
      }
    })
    |> ignore
    c.box(style=ug_split_names, flow=true, fn() {
      for i, p in parts {
        let pv = Some(p)
        usage_part_name(c, kind, pv, usage_part_ink(parts, i), "usage-split/")
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A part's colour: the first four's own, the rest's (其他, no key) the theme's grey.
fn usage_part_ink(parts : Array[Json], i : Int) -> Int64 {
  if i < parts.length() && text(Some(parts[i]), "key") == "" {
    @sf.theme().p.subtle
  } else {
    @sf.usage_series(i)
  }
}

///|
/// A part named: a dot of its colour, its name, what it spent; pressed, seen
/// alone (a person, account or model; not the rest), its name lit under the pointer.
fn usage_part_name(c : @ui.Ctx, kind : String, pv : Json?, ink : Int64, key : String) -> Unit {
  let alone = kind != "chats" && text(pv, "key") != "" && usage_pick.only.get() != (kind, text(pv, "key"))
  let id = if alone { c.id(key + kind + "/" + text(pv, "key")) } else { 0 }
  if alone && c.clicked(id) {
    usage_pick.only.set((kind, text(pv, "key")))
    usage_pick.all.set(false)
  }
  let lit = alone && c.lit(id)
  let b = c.box(style=ug_name, id~, fn() {
    c.box(style=ug_dot.then(@ui.style(bg=Data(ink))), fn() {  }) |> ignore
    c.text(text(pv, "title"), style=if lit { ug_name_lit } else { ug_name_words }) |> ignore
    c.text(text(pv, "costText"), style=ug_name_cost) |> ignore
  })
  if alone {
    c.semantics(b, Button, id~, label=@sf.t("web-main.usage.only", args=[("name", text(pv, "title"))]))
  }
}

///|
/// What the page is narrowed to, each a chip that takes it off: the one seen alone (只看 林), the day (只看 10/5).
fn usage_narrowed(c : @ui.Ctx, v : Json?) -> Unit {
  let only = field(v, "only")
  let day = text(v, "day")
  if !(only is Some(Object(_))) && day == "" {
    return
  }
  c.box(style=ug_chips, flow=true, fn() {
    if only is Some(Object(_)) {
      let name = text(only, "title")
      if @sf.chip(c, @sf.t("web-main.usage.only", args=[("name", name)]), key="usage-only", icon="close",
        said=@sf.t("web-main.usage.onlyOff", args=[("name", name)])) {
        usage_pick.only.set(("", ""))
      }
    }
    if day != "" {
      let name = text(v, "period")
      if @sf.chip(c, @sf.t("web-main.usage.only", args=[("name", name)]), key="usage-day-only", icon="close",
        said=@sf.t("web-main.usage.onlyOff", args=[("name", name)])) {
        usage_pick.day.set("")
      }
    }
  })
  |> ignore
}

///|
/// A card's title (what it shows).
fn usage_card_title(c : @ui.Ctx, words : String) -> Unit {
  c.text(words, style=ug_card_title) |> ignore
}

///|
/// The subscriptions with an allowance the core can read (none: no card): each its windows as rings one inside
/// another (Activity's, as the card shared of the week draws the subscriptions'), each as full as what is left of it,
/// the first window outside; beside them its name and what it spent in the days, and each window in its ring's colour:
/// its name, what is left (in the warning's ink where it runs low) and when it fills.
fn usage_accounts(c : @ui.Ctx, v : Json?) -> Unit {
  let accounts = items(v, "accounts")
  if accounts.length() == 0 {
    return
  }
  c.box(style=ug_card, fn() {
    usage_card_title(c, @sf.t("web-main.usage.accounts"))
    c.box(style=ug_accounts, fn() {
      for a in accounts {
        let av = Some(a)
        let quota = field(av, "quota")
        let windows = if @sf.has_quota(quota) { items(quota, "windows") } else { [] }
        c.box(style=ug_account, fn() {
          if windows.length() > 0 {
            let rings = windows.mapi(fn(i, w) { (number(Some(w), "left") / 100.0, @sf.usage_series(i)) })
            @sf.rings(c, rings, ug_ring_side, ug_ring_track, most=windows.length()) |> ignore
          }
          c.box(style=ug_account_text, fn() {
            // (what it spent under its name where their line has not the room)
            c.box(style=ug_account_head, flow=true, fn() {
              c.text(text(av, "title"), style=ug_account_title) |> ignore
              c.text(@sf.t("web-main.usage.spent", args=[("cost", text(av, "costText"))]), style=ug_name_cost) |> ignore
            })
            |> ignore
            for i, w in windows {
              let wv = Some(w)
              let left = number(wv, "left").to_int().to_string()
              let low = text(wv, "level") is ("amber" | "red")
              c.box(style=ug_window, flow=true, fn() {
                c.box(style=ug_dot.then(@ui.style(bg=Data(@sf.usage_series(i)))), fn() {  }) |> ignore
                c.text(text(wv, "label"), style=ug_name_cost) |> ignore
                c.text(@sf.t("web-main.quota.figure", args=[("left", left)]), style=if low { ug_window_low } else { ug_window_left })
                |> ignore
                if text(wv, "refills") != "" {
                  c.text(text(wv, "refills"), style=ug_window_refills) |> ignore
                }
              })
              |> ignore
            }
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

///|
/// The chats that cost the most (the first 8 until all are asked for), each its name, who it was for and its model,
/// what it spent and its share; one pressed opens it.
fn usage_chats(c : @ui.Ctx, core : Core, v : Json?) -> Unit {
  let list = match items(v, "lists").search_by(fn(l) { text(Some(l), "key") == "chats" }) {
    Some(i) => Some(items(v, "lists")[i])
    None => None
  }
  let all_items = items(list, "items")
  if all_items.length() == 0 {
    return
  }
  c.box(style=ug_card, fn() {
    usage_card_title(c, @sf.t("web-main.usage.topChats"))
    c.box(style=ug_rows, fn() {
      for i, it in all_items {
        if usage_pick.all.get() || i < ug_first {
          usage_chat_row(c, core, it, i + 1)
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
/// What it is made of, the people, the models and the accounts side by side (under each other where they have not the
/// room): each a ring of its parts (a donut, the first's share in its middle) and beside it its first few and the rest,
/// a dot of its colour, its name, what it spent and its share; one pressed is seen alone.
fn usage_makeup(c : @ui.Ctx, v : Json?) -> Unit {
  let lists = items(v, "lists").filter(fn(l) { text(Some(l), "key") != "chats" && items(Some(l), "parts").length() > 0 })
  if lists.length() == 0 {
    return
  }
  c.box(style=ug_card, fn() {
    usage_card_title(c, @sf.t("web-main.usage.makeup"))
    c.box(style=ug_makeup, flow=true, fn() {
      for l in lists {
        let lv = Some(l)
        let kind = text(lv, "key")
        let parts = items(lv, "parts")
        c.box(style=ug_makeup_list, fn() {
          c.text(text(lv, "title"), style=ug_makeup_title) |> ignore
          c.box(style=ug_makeup_body, flow=true, fn() {
            c.box(style=ug_donut, fn() {
              let shares = parts.mapi(fn(i, p) { (number(Some(p), "share"), usage_part_ink(parts, i)) })
              @sf.donut(c, shares, ug_donut_side, ug_donut_width, @sf.theme().p.line) |> ignore
              c.layer(fn() {
                c.box(style=ug_donut_mid, fn() { c.text(text(Some(parts[0]), "shareText"), style=ug_donut_figure) |> ignore })
                |> ignore
              })
              |> ignore
            })
            |> ignore
            c.box(style=ug_makeup_legend, fn() {
              for i, p in parts {
                let pv = Some(p)
                c.box(style=ug_legend_row, fn() {
                  usage_part_name(c, kind, pv, usage_part_ink(parts, i), "usage-makeup/")
                  c.box(style=ug_grow, fn() {  }) |> ignore
                  c.text(text(pv, "shareText"), style=ug_row_share_words) |> ignore
                })
                |> ignore
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
  })
  |> ignore
}



///|
/// The calls and tokens (明细), side by side, each against the days before, in lines where they have not the room.
fn usage_details(c : @ui.Ctx, v : Json?) -> Unit {
  let tiles = items(v, "tiles")
  if tiles.length() < 2 {
    return
  }
  c.box(style=ug_card, fn() {
    usage_card_title(c, @sf.t("web-main.usage.details"))
    c.box(style=ug_stats, flow=true, fn() {
      for i in 1..<tiles.length() {
        let tv = Some(tiles[i])
        c.box(style=ug_stat, fn() {
          c.text(text(tv, "label"), style=ug_stat_label) |> ignore
          c.text(text(tv, "value"), style=ug_stat_value) |> ignore
          if text(tv, "change") != "" {
            c.text(text(tv, "change") + " " + text(v, "versus"), style=usage_trend_words(tv)) |> ignore
          }
          c.text(text(tv, "sub"), style=ug_stat_sub) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A total's change against the days before (↑18% on the orange thinned, 比前 7 天 after it), on the figure's baseline;
/// none where the core says none.
fn usage_change(c : @ui.Ctx, v : Json?, tv : Json?) -> Unit {
  if text(tv, "change") == "" {
    return
  }
  let words = match text(tv, "trend") {
    "up" => ug_hero_up
    "down" => ug_hero_down
    _ => ug_hero_same
  }
  c.box(style=ug_change_line, fn() {
    c.box(style=ug_change_pill, fn() { c.text(text(tv, "change"), style=words) |> ignore }) |> ignore
    c.text(text(v, "versus"), style=ug_change_versus) |> ignore
  })
  |> ignore
}

///|
/// A change's words: up in the accent's words, down in the words' ink, the same in the muted.
fn usage_trend_words(tv : Json?) -> @ui.TextStyle {
  match text(tv, "trend") {
    "up" => ug_trend_up
    "down" => ug_trend_down
    _ => ug_trend_same
  }
}

///|
/// Each day's cost as a bar on the scale's lines (DaysChart), the day seen alone in full and the others faded (all in
/// full with none). A day pressed is seen alone, pressed again all of them again; a finger slid across the days lets
/// go on the one it ends on.
fn usage_chart(c : @ui.Ctx, v : Json?) -> Unit {
  let daily = items(v, "daily")
  let top = number(v, "top")
  let many = flag(v, "many")
  let shown = usage_pick.day.get()
  // (once a frame: a tap is the drag's and the day's click both)
  let mut pressed = false
  let press = fn(key : String) {
    if !pressed {
      pressed = true
      usage_pick.day.set(if usage_pick.day.get() == key { "" } else { key })
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
  match c.drag_of(area) {
    Some(d) => {
      let tapped = d.take_tap()
      let ended = d.take_end()
      let finger = if tapped || ended { under(d.x) } else { "" }
      if tapped && finger != "" {
        press(finger)
      } else if ended && finger != "" {
        usage_pick.day.set(finger)
      }
    }
    None => ()
  }
  // the day most was spent on (said over its bar; the one shown's instead, with one)
  let mut peak = ""
  let mut most = 0.0
  for d in daily {
    if number(Some(d), "cost") > most {
      most = number(Some(d), "cost")
      peak = text(Some(d), "day")
    }
  }
  let said = if shown != "" { shown } else { peak }
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
            press(key)
          }
          let b = c.box(style=ug_day, id~, fn() {
            usage_bar(c, number(dv, "cost"), top, many, shown == "" || key == shown, if key == said {
              text(dv, "costText")
            } else {
              ""
            })
          })
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
            c.text(text(dv, "tick"), style=if shown != "" && text(dv, "day") == shown { ug_label_on } else { ug_label }) |> ignore
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



///|
/// The first of the chats shown until all are asked for (Ranking's `first`).
let ug_first : Int = 8

///|
/// A day's bar, as high as its share of the scale's top, 16 wide at most (as wide as its day with many days), round at
/// its ends: the theme's accent running thinner to its foot; a day other than the one shown in the theme's line. `said`
/// over it: what the most spent day spent (the one shown's, with one).
fn usage_bar(c : @ui.Ctx, cost : Double, top : Double, many : Bool, on : Bool, said : String) -> Unit {
  if top <= 0.0 || cost <= 0.0 {
    return
  }
  let h = @sf.usage_plot * @cmp.minimum(1.0, cost / top)
  if said != "" {
    c.text(said, style=ug_peak) |> ignore
  }
  c.box(style=(if many { ug_bar_many } else { ug_bar }).then(@ui.style(h=Fixed(h))), fn() {
    if on {
      let accent = @sf.theme().p.accent
      @sf.gradient(c, ug_bar_w, h, 180.0, accent, @sf.alpha(accent, 0.3))
    } else {
      c.box(style=ug_bar_off, fn() {  }) |> ignore
    }
  })
  |> ignore
}

///|
/// A chat and what it spent (Row): its rank; its name and its cost in bold on a line, who it was for, its model and
/// where it is under them; a bar of its share under them, from its words on, its share in words at its end. Pressed, it
/// opens (the hover's ground under the pointer).
fn usage_chat_row(c : @ui.Ctx, core : Core, it : Json, rank : Int) -> Unit {
  let iv = Some(it)
  let chat = field(iv, "chat")
  let opens = chat is Some(Object(_))
  let id = if opens { c.id("usage-item/chats/" + text(iv, "key")) } else { 0 }
  if opens && c.clicked(id) {
    (core.open_chat)(text(chat, "station"), text(chat, "session"), text(iv, "title"))
  }
  c.box(style=if opens { ug_row_link } else { ug_row }, id~, fn() {
    c.box(style=ug_row_line, fn() {
      // (the first three on a badge: the first in the accent, the next two on the tint)
      let (badge, figure) = if rank == 1 {
        (ug_rank_first, ug_rank_first_words)
      } else if rank <= 3 {
        (ug_rank_top, ug_rank_top_words)
      } else {
        (ug_rank_box, ug_rank)
      }
      c.box(style=badge, fn() { c.text(rank.to_string(), style=figure) |> ignore }) |> ignore
      // (its name and cost on a line, what it is on the next, alone: the room of large words on a phone)
      c.box(style=ug_row_text, fn() {
        // (its cost under it where their line has not the room)
        c.box(style=ug_row_pair, flow=true, fn() {
          c.text(text(iv, "title"), style=ug_row_title) |> ignore
          c.text(text(iv, "costText"), style=ug_cost) |> ignore
        })
        |> ignore
        if text(iv, "sub") != "" {
          c.text(text(iv, "sub"), style=ug_row_sub) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
    c.box(style=ug_row_share_room, fn() { usage_share_bar(c, number(iv, "share"), text(iv, "shareText"), @sf.theme().p.accent) })
    |> ignore
  })
  |> ignore
}

///|
/// A share's bar in `ink` (1% at least for one spent at all), its share in words at its end.
fn usage_share_bar(c : @ui.Ctx, share : Double, words : String, ink : Int64) -> Unit {
  c.box(style=ug_share, fn() {
    let k = if share <= 0.0 { 0.0 } else { @cmp.minimum(1.0, @cmp.maximum(0.01, share)) }
    if k > 0.0 {
      c.box(style=ug_share_part.then(@ui.style(w=Grow(k), bg=Data(ink))), fn() {  }) |> ignore
    }
    let rest = 1.0 - k
    if rest > 0.0 {
      c.box(style=ug_share_rest.then(@ui.style(w=Grow(rest))), fn() {  }) |> ignore
    }
  })
  |> ignore
  c.box(style=ug_row_share_box, fn() { c.text(words, style=ug_row_share_words) |> ignore }) |> ignore
}

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
/// The page's cards 16 apart, its notes under them.
// kept across runs: a value (no field of it changes)
let ug_body : @ui.Style = @ui.css("w=Full gap=S4")

///|
/// A card of the page: its words 20 in, 16 apart, the ladder's corner (what lies in its corners, a share's bar, the
/// lists' choice, round by the ladder's there: mbui works it out).
// kept across runs: a value (no field of it changes)
let ug_card : @ui.Style = @ui.css("w=Full p=S5 gap=S4 radius=Xl3 bg=Card")

///|
/// The overview's head: what its figure is (折合费用 · 近 7 天) and, at its end, the way to the prices.
// kept across runs: a value (no field of it changes)
let ug_hero_head : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ug_hero_label : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Muted, w=@sf.grow)

///|
/// 查看价目表 → (muted, the words' ink under the pointer).
// kept across runs: a value (no field of it changes)
let ug_prices : @ui.Style = @ui.css("px=S2 py=S1 radius=Inner")

///|
// kept across runs: a value (no field of it changes)
let ug_prices_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_prices_lit : @ui.TextStyle = ug_prices_words.then(@ui.text_style(color=Fg))

///|
/// The cost large and its change after it on its baseline, under it where the line has not the room.
// kept across runs: a value (no field of it changes)
let ug_hero_figures : @ui.Style = @ui.css("row w=Full gap=S3 align=AEnd")

///|
/// The cost of the days (the page's one figure on its own: a large title's words).
// kept across runs: a value (no field of it changes)
let ug_hero_value : @ui.TextStyle = @ui.text_style(size=Xl5, weight=Bold, tracking=Tight, color=Fg, wrap=false)

///|
/// ↑18% on a tint, then 比前 7 天 (6 by 2 in, round), on the figure's foot.
// kept across runs: a value (no field of it changes)
let ug_change_line : @ui.Style = @ui.css("row gap=S2 pb=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ug_change_pill : @ui.Style = @ui.css("px=S2 py=S0_5 radius=Full bg=AccentBg")

///|
// kept across runs: a value (no field of it changes)
let ug_change_versus : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// A change's words: up in the accent's (more spent), down in the words' ink, the same muted.
// kept across runs: a value (no field of it changes)
let ug_trend_up : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=AccentText)

///|
// kept across runs: a value (no field of it changes)
let ug_trend_down : @ui.TextStyle = ug_trend_up.then(@ui.text_style(color=Fg))

///|
// kept across runs: a value (no field of it changes)
let ug_trend_same : @ui.TextStyle = ug_trend_up.then(@ui.text_style(color=Muted))

///|
/// The overview's change: up in the accent's words, down in the words' ink, the same muted.
// kept across runs: a value (no field of it changes)
let ug_hero_up : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Semibold, color=AccentText, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_hero_down : @ui.TextStyle = ug_hero_up.then(@ui.text_style(color=Fg))

///|
// kept across runs: a value (no field of it changes)
let ug_hero_same : @ui.TextStyle = ug_hero_up.then(@ui.text_style(color=Muted))

///|
/// What the cost is made of: its bar (8 high, round, its parts 2 apart), the parts named under it, 10 apart.
// kept across runs: a value (no field of it changes)
let ug_split : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let ug_split_bar : @ui.Style = @ui.css("row w=Full h=S2 gap=S0_5 radius=Full clip")

///|
// kept across runs: a value (no field of it changes)
let ug_split_part : @ui.Style = @ui.css("h=Full")

///|
/// The parts named, in lines where they have not the room, 4 apart and 16 across.
// kept across runs: a value (no field of it changes)
let ug_split_names : @ui.Style = @ui.css("row w=Full gap=S1")

///|
/// A part named: a dot 8, its name (cut short where its line has not the room), what it spent, 6 apart (pressed: its
/// name in the accent's words under the pointer).
// kept across runs: a value (no field of it changes)
let ug_name : @ui.Style = @ui.css("row w=Cut gap=S1_5 py=S0_5 mr=S3 align=ACenter")


///|
// kept across runs: a value (no field of it changes)
let ug_dot : @ui.Style = @ui.css("w=S2 h=S2 radius=Full")

///|
// kept across runs: a value (no field of it changes)
let ug_name_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let ug_name_lit : @ui.TextStyle = ug_name_words.then(@ui.text_style(color=AccentText))

///|
// kept across runs: a value (no field of it changes)
let ug_name_cost : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// What the page is narrowed to: its chips, 8 apart, in lines where they have not the room.
// kept across runs: a value (no field of it changes)
let ug_chips : @ui.Style = @ui.css("row w=Full gap=S2")

///|
/// The allowances, 16 apart: each its name and what it spent on a line, its windows' chips under them, 8 apart.
// kept across runs: a value (no field of it changes)
let ug_accounts : @ui.Style = @ui.css("w=Full gap=S4")

///|
// kept across runs: a value (no field of it changes)
let ug_account : @ui.Style = @ui.css("row w=Full gap=S4 align=ACenter")

///|
/// Beside an account's rings: its name and what it spent, each window under them.
// kept across runs: a value (no field of it changes)
let ug_account_text : @ui.Style = @ui.style(w=@sf.grow, gap=S1)

///|
/// An account's rings: 72 across, their track the ring's colour at 16%.
let ug_ring_side : Double = 72.0

///|
let ug_ring_track : Int64 = 40L

///|
/// A window: its ring's dot, its name, what is left (semibold; the warning's ink running low), when it fills.
// kept across runs: a value (no field of it changes)
let ug_window : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ug_window_left : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_window_low : @ui.TextStyle = ug_window_left.then(@ui.text_style(color=WarnInk))

///|
// kept across runs: a value (no field of it changes)
let ug_window_refills : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_account_head : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ug_account_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Fg, wrap=false, w=@sf.grow)

///|
/// What it is made of: the people, the models and the accounts side by side, each 200 at least, 24 apart (under each
/// other where they have not the room).
// kept across runs: a value (no field of it changes)
let ug_makeup : @ui.Style = @ui.css("row w=Full gap=S6")

///|
// kept across runs: a value (no field of it changes)
let ug_makeup_list : @ui.Style = @ui.style(w=@sf.grow, min_w=S56, gap=S3)

///|
/// A list's donut and its parts beside it, 16 apart, in the middle of each other; its parts under it where they have
/// not 176 beside it (three lists side by side).
// kept across runs: a value (no field of it changes)
let ug_makeup_body : @ui.Style = @ui.css("row w=Full gap=S4 align=ACenter")

///|
/// The donut: 76 across, 10 wide; the first part's share in its middle, semibold.
let ug_donut_side : Double = 76.0

///|
let ug_donut_width : Double = 10.0

///|
// kept across runs: a value (no field of it changes)
let ug_donut : @ui.Style = @ui.style(w=Fixed(ug_donut_side), h=Fixed(ug_donut_side))

///|
// kept across runs: a value (no field of it changes)
let ug_donut_mid : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let ug_donut_figure : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, wrap=false)

///|
/// Beside the donut: each part on a line, its share at the line's end.
// kept across runs: a value (no field of it changes)
let ug_makeup_legend : @ui.Style = @ui.style(w=@sf.grow, min_w=S44, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let ug_legend_row : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ug_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let ug_makeup_title : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false, w=Full)

///|
/// The other totals side by side, each 96 at least, in lines where three have not the room.
// kept across runs: a value (no field of it changes)
let ug_stats : @ui.Style = @ui.css("row w=Full gap=S4")

///|
// kept across runs: a value (no field of it changes)
let ug_stat : @ui.Style = @ui.style(w=@sf.grow, min_w=S24, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let ug_stat_label : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let ug_stat_value : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, wrap=false, w=Full)

///|
/// What it is made of (日均 202 次), in lines where the total is narrower than it: none of it cut.
// kept across runs: a value (no field of it changes)
let ug_stat_sub : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, w=Full)

///|
/// A card's title: the ui's size, semibold, in the words' ink.
// kept across runs: a value (no field of it changes)
let ug_card_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, w=Full)

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
let ug_tick_words : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, color=Muted, wrap=false)

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
let ug_bar : @ui.Style = @ui.style(w=Full, max_w=@sf.usage_bar_max, radius=Full, clip=true)

///|
/// A bar's gradient: drawn for a bar 16 wide (stretched to its width), its foot the accent at 30%.
let ug_bar_w : Double = 16.0

///|
/// What the most spent day spent, over its bar (the caption's, semibold).
// kept across runs: a value (no field of it changes)
let ug_peak : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_bar_many : @ui.Style = @ui.css("w=Full radius=Full clip")

///|
/// A day's bar but the one shown: faded.
// kept across runs: a value (no field of it changes)
let ug_bar_off : @ui.Style = @ui.css("w=Full h=Full bg=Line")

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
let ug_label : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_label_on : @ui.TextStyle = ug_label.then(@ui.text_style(weight=Medium, color=AccentText))

///|
// kept across runs: a value (no field of it changes)
let ug_share : @ui.Style = @ui.style(row=true, w=@sf.grow, h=S1, radius=Full, bg=TintStrong, clip=true)

///|
// kept across runs: a value (no field of it changes)
let ug_share_part : @ui.Style = @ui.css("h=Full radius=Full")

///|
// kept across runs: a value (no field of it changes)
let ug_share_rest : @ui.Style = @ui.css("h=Full")

///|
// kept across runs: a value (no field of it changes)
let ug_rows : @ui.Style = @ui.css("w=Full")

///|
/// A row (row: 10 by 12 in, the field's corner, 12 apart in a line; its share's bar 6 under).
// kept across runs: a value (no field of it changes)
let ug_row : @ui.Style = @ui.css("w=Full px=S3 py=S2_5 gap=S1_5 radius=Inner")

///|
// kept across runs: a value (no field of it changes)
let ug_row_link : @ui.Style = ug_row.then(@ui.css("hovered{bg=Hover}"))

///|
// kept across runs: a value (no field of it changes)
let ug_row_line : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ug_rank_box : @ui.Style = @ui.css("w=S6 h=S6 align=ACenter justify=JCenter")

///|
/// The first three's badges: round, the first on the accent's ground in its words' ink, the next two on the tint.
// kept across runs: a value (no field of it changes)
let ug_rank_first : @ui.Style = ug_rank_box.then(@ui.css("radius=Full bg=AccentBg"))

///|
// kept across runs: a value (no field of it changes)
let ug_rank_top : @ui.Style = ug_rank_box.then(@ui.css("radius=Full bg=TintStrong"))

///|
// kept across runs: a value (no field of it changes)
let ug_rank : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_rank_first_words : @ui.TextStyle = ug_rank.then(@ui.text_style(weight=Bold, color=AccentText))

///|
// kept across runs: a value (no field of it changes)
let ug_rank_top_words : @ui.TextStyle = ug_rank.then(@ui.text_style(weight=Bold, color=Fg))

///|
// kept across runs: a value (no field of it changes)
let ug_row_text : @ui.Style = @ui.style(w=@sf.grow, gap=SPx)

///|
// kept across runs: a value (no field of it changes)
let ug_row_pair : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ug_row_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Fg, wrap=false, w=@sf.grow)

///|
/// What it is (its calls and tokens), in lines where the row is narrower than it: none of it cut.
// kept across runs: a value (no field of it changes)
let ug_row_sub : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let ug_cost : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Bold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_row_share_box : @ui.Style = @ui.css("w=S10 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let ug_row_share_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// The share's bar from the row's words on (its lead's 20 and the 12 after it), its share's words after it.
// kept across runs: a value (no field of it changes)
let ug_row_share_room : @ui.Style = @ui.css("row w=Full pl=S9 gap=S3 align=ACenter")

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
      // (the table's words start with the card's words; when it scrolls, it reaches past them to the ladder's inset)
      c.box(style=up_table_across, fn() {
        @sf.markdown(c, md.join("\n"), key="prices/" + text(tv, "station"), tree~, size=@sf.text_scale.base.0, bleed=@sf.card_pad - @sf.corner_inset) |> ignore
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
/// A station's prices' table at its card's foot, as far past the card's words under it as its scroll reaches to either side.
// kept across runs: a value (no field of it changes)
let up_table_across : @ui.Style = @ui.css("w=Full").then(@ui.style(mb=@sf.room_of(@sf.corner_inset - @sf.card_pad)))

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
