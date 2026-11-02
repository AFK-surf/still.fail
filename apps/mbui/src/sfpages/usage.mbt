// 用量, one page in every frame (ember web/src/cloud/settings.tsx UsageSettings; the narrow app's mobile/Usage.tsx;
// Usage.tsx; Usage.css.ts): what the agents spent over the last 7 or 30 days (picked at the page's head), as the core's
// `usage` view says it, laid out by what someone opening it wants to know, most first:
// as Codex's usage history:
// - how much the agents used, and on what: the cost of the days large (the one figure the models' tokens add up to),
//   against the days before as many; the days' bars, each split by who spent it or by model (as picked; by model
//   where one person did), the parts named, one pressed seen alone; a day pressed seen alone;
// - what it went to: the chats that cost the most, each with who it was for and its model and its share, opened from
//   there (what can be done about it is done in a chat: one idling, one on too dear a model).
// Not here: the subscriptions' allowances (the profiles' page says them, now), nor the calls and tokens (no model's
// tokens are another's: nothing to decide by).
// Everything shown is the core's: the page only picks the days, the split, the one alone and the day.

///|
/// What the page picked: its days, how the summary's year is drawn (0 by day, 1 by week, 2 their running total), what
/// the days' bars are split by ("" the core's choice), the day seen alone ("" all),
/// whether all the chats are shown, and the one seen alone (its list and key; "" none).
priv struct UsagePick {
  days : @signals.Signal[Int]
  year : @signals.Signal[Int]
  split : @signals.Signal[String]
  day : @signals.Signal[String]
  all : @signals.Signal[Bool]
  only : @signals.Signal[(String, String)]
}

///|
// kept across runs: said by the page's picks; usage_reset puts it back
let usage_pick : UsagePick = {
  days: @signals.signal(7, same=fn(a, b) { a == b }),
  year: @signals.signal(0, same=fn(a, b) { a == b }),
  split: @signals.signal("", same=fn(a, b) { a == b }),
  day: @signals.signal("", same=fn(a, b) { a == b }),
  all: @signals.signal(false, same=fn(a, b) { a == b }),
  only: @signals.signal(("", ""), same=fn(a, b) { a == b }),
}

///|
fn usage_reset() -> Unit {
  usage_pick.days.set(7)
  usage_pick.year.set(0)
  usage_pick.split.set("")
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
/// What the page asks the core's `usage` view for: its workspace's `days`, split as picked, of the one picked alone, of
/// the day picked.
fn usage_args(here : Here, days : Int) -> Map[String, Json] {
  let args : Map[String, Json] = { "scope": str(here.workspace), "days": Json::number(days.to_double()) }
  let (only_list, only_key) = usage_pick.only.get()
  if only_list != "" {
    args["only"] = { "list": str(only_list), "key": str(only_key) }
  }
  if usage_pick.split.get() != "" {
    args["split"] = str(usage_pick.split.get())
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
    usage_summary(c, v)
    usage_overview(c, core, v)
    if flag(v, "empty") {
      let wait = field(v, "wait")
      let failing = failing_of(wait)
      // (nothing yet while it is still read: the card that says none, in its bones, so the page stays as tall when
      // it turns out none was spent: a page of a few chats' bones went down a third of a screen at once there)
      let none = fn() {
        c.box(style=ug_card, fn() {
          c.box(style=ug_empty_box, fn() { c.text(@sf.t("web-main.usage.none"), style=ug_empty) |> ignore }) |> ignore
        })
        |> ignore
      }
      if flag(wait, "reading") || failing.length() > 0 {
        @sf.waiting(c, none, note={ reading: flag(wait, "reading"), text: "", failing })
      } else {
        none()
      }
    } else {
      usage_shown(c, core, v)
    }
    usage_notes(c, v)
  })
  |> ignore
}

///|
/// What was spent (`v`), under the overview (the days' bars and what they are made of are on it): the chats it went to.
fn usage_shown(c : @ui.Ctx, core : Core, v : Json?) -> Unit {
  usage_chats(c, core, v)
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
/// What the workspace's agents did since counting began (the core's `summary`; after Codex's usage summary,
/// codex-rs/tui/src/analytics/summary_panel.rs), none where no station told it: whose it is over five figures (the
/// tokens in all, the chats archived, the tasks run across devices, the decisions answered by a tap, the devices at
/// work); the year (activity); each device's work and where the chats came from, side by side on a wide page; when it
/// is as of. 760 across at most, in the
/// card's middle, as Codex keeps it 110 columns.
fn usage_summary(c : @ui.Ctx, v : Json?) -> Unit {
  let sv = field(v, "summary")
  if !(sv is Some(Object(_))) {
    return
  }
  c.box(style=ug_card, fn() {
    c.box(style=ug_sum, fn() {
      if text(sv, "title") != "" {
        c.text(text(sv, "title"), style=ug_sum_title) |> ignore
      }
      c.box(style=ug_figures, flow=true, fn() {
        for f in items(sv, "figures") {
          c.box(style=ug_figure, fn() {
            c.text(text(Some(f), "value"), style=ug_figure_value) |> ignore
            c.text(text(Some(f), "label"), style=ug_figure_label) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      // (half the year where the page is a phone's: its weeks as many as stay big enough to see)
      usage_year(c, field(sv, "activity"), if c.width < 600.0 { 26 } else { 52 })
      c.box(style=ug_lists, flow=true, fn() {
        usage_named(c, field(sv, "stations"))
        if field(sv, "places") is Some(Object(_)) {
          usage_named(c, field(sv, "places"))
        }
      })
      |> ignore
      c.text(text(sv, "asOf"), style=ug_note) |> ignore
      if text(sv, "partial") != "" {
        c.text(text(sv, "partial"), style=ug_note) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A list of the summary's (each device's work, where the chats came from): its title, each its name muted at the
/// line's start (cut short where its line has not the room) and its value at its end (Codex's columns).
fn usage_named(c : @ui.Ctx, lv : Json?) -> Unit {
  c.box(style=ug_named, fn() {
    c.text(text(lv, "title"), style=ug_named_title) |> ignore
    for it in items(lv, "items") {
      c.box(style=ug_line, fn() {
        c.text(text(Some(it), "name"), style=ug_named_name) |> ignore
        c.text(text(Some(it), "value"), style=ug_named_value) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The year (Codex's token activity, activity_chart.rs): its title and how long over it, how it is drawn at the title's
/// end (by day, by week, their running total); the last `weeks` of its 52 a column each, Sunday's row first, each row
/// its day's name first; by day each a square in its level's colour (Codex's palette: the words' ink faint where none,
/// the accent at 22, 42, 68 and 100% by level), a day after today none; by week or their running total each week a bar
/// of its rows from the foot; each month's name over the week its first days are in; under it the levels from less to
/// more, or what a column is.
fn usage_year(c : @ui.Ctx, av : Json?, weeks : Int) -> Unit {
  let views = strings(av, "views")
  let shown = if usage_pick.year.get() < views.length() { usage_pick.year.get() } else { 0 }
  let first = 52 - weeks
  c.box(style=ug_year, fn() {
    c.box(style=ug_line, fn() {
      c.box(style=ug_year_head, fn() {
        c.text(text(av, "title"), style=ug_named_title) |> ignore
        c.text(text(av, "sub"), style=ug_named_name) |> ignore
      })
      |> ignore
      if views.length() > 1 {
        let picked = @sf.segmented(c, "usage-year", views, shown)
        if picked != shown {
          usage_pick.year.set(picked)
        }
      }
    })
    |> ignore
    let cells = numbers(av, "cells")
    let bars = numbers(av, if shown == 1 { "weekly" } else { "cumulative" })
    let tips = strings(av, if shown == 0 {
      "tips"
    } else if shown == 1 {
      "weekTips"
    } else {
      "runningTips"
    })
    let palette = @sf.theme().p
    let faint = @sf.alpha(palette.text, if @sf.theme().dark { 0.14 } else { 0.18 })
    let ink = fn(level : Int) -> Int64 {
      match level {
        0 => faint
        1 => @sf.alpha(palette.accent, 0.22)
        2 => @sf.alpha(palette.accent, 0.42)
        3 => @sf.alpha(palette.accent, 0.68)
        _ => palette.accent
      }
    }
    c.box(style=ug_grid, fn() {
      // the months' names over their weeks: each over its weeks until the next's (Codex's month_labels), the first's
      // from the first week shown
      c.box(style=ug_grid_row, fn() {
        c.box(style=ug_grid_lead, fn() {  }) |> ignore
        let starts = items(av, "months").filter(fn(m) { number(Some(m), "week").to_int() >= first })
        let lead = match starts.get(0) {
          Some(m) => number(Some(m), "week").to_int() - first
          None => 52 - first
        }
        if lead > 0 {
          c.box(style=ug_months.then(@ui.style(w=Grow(lead.to_double()))), fn() {  }) |> ignore
        }
        for i, m in starts {
          let from = number(Some(m), "week").to_int()
          let until = match starts.get(i + 1) {
            Some(n) => number(Some(n), "week").to_int()
            None => 52
          }
          c.box(style=ug_months.then(@ui.style(w=Grow((until - from).to_double()))), fn() {
            // (none where its weeks have not the room for it: the year's last month, its first week only; Codex's
            // month_labels leaves out one that does not fit)
            c.text(text(Some(m), "label"), style=ug_grid_label, shorter=[""]) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      let weekdays = strings(av, "weekdays")
      for row in 0..<7 {
        c.box(style=ug_grid_row, fn() {
          c.box(style=ug_grid_lead, fn() {
            // (Monday's, Wednesday's and Friday's, as GitHub's: a name a row is taller than the rows)
            c.text(if shown == 0 && row % 2 == 1 && row < weekdays.length() { weekdays[row] } else { "" }, style=ug_grid_label) |> ignore
          })
          |> ignore
          for w in first..<52 {
            let fill = if shown == 0 {
              let k = w * 7 + row
              let l = if k < cells.length() { cells[k].to_int() } else { -1 }
              if l < 0 { None } else { Some(ink(l)) }
            } else {
              let h = if w < bars.length() { bars[w].to_int() } else { 0 }
              if 7 - row <= h { Some(palette.accent) } else { None }
            }
            // what it is, said as the pointer rests on it (a day's date and tokens; by week, its week's, the whole column)
            let k = if shown == 0 { w * 7 + row } else { w }
            let tip = if k < tips.length() { tips[k] } else { "" }
            let id = c.id("usage-year/" + w.to_string() + "/" + row.to_string())
            match fill {
              Some(color) => c.box(style=ug_cell.then(@ui.style(bg=Data(color))), id~, aspect=1.0, fn() {  }) |> ignore
              None => c.box(style=ug_cell, id~, aspect=1.0, fn() {  }) |> ignore
            }
            @sf.tip(c, "usage-year/" + w.to_string() + "/" + row.to_string(), id, tip, side=Top)
          }
        })
        |> ignore
      }
    })
    |> ignore
    if shown == 0 {
      c.box(style=ug_legend_line, fn() {
        c.text(text(av, "less"), style=ug_grid_label) |> ignore
        for l in 0..<5 {
          c.box(style=ug_legend_cell.then(@ui.style(bg=Data(ink(l)))), fn() {  }) |> ignore
        }
        c.text(text(av, "more"), style=ug_grid_label) |> ignore
      })
      |> ignore
      let none = strings(av, "captions")
      if none.length() > 0 && none[0] != "" {
        c.text(none[0], style=ug_grid_label) |> ignore
      }
    } else {
      let captions = strings(av, "captions")
      if shown < captions.length() {
        c.text(captions[shown], style=ug_grid_label) |> ignore
      }
    }
  })
  |> ignore
}

///|
/// A list of numbers of `v`'s at `key` (none where it is not one).
fn numbers(v : Json?, key : String) -> Array[Double] {
  match field(v, key) {
    Some(Array(xs)) =>
      xs.map(fn(x) {
        match x {
          Number(n, ..) => n
          _ => 0.0
        }
      })
    _ => []
  }
}

///|
/// What was spent in all (Codex's usage history): the cost of the days large and its change against the days before
/// after it, the way to the prices at its head's end; what the days' bars are split by, each part named in its colour,
/// and the choice of by whom or by which model; the days' bars, each its parts stacked, one pressed seen alone; what
/// the page is narrowed to (one alone, a day) said last, each taken off there.
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
      usage_split(c, v)
      usage_chart(c, v)
    }
    usage_narrowed(c, v)
  })
  |> ignore
}

///|
/// The days' bars' parts named (the core's `series`, each a dot of its colour; one pressed seen alone, not the rest), and
/// at the line's end what they are split by, 按人 or 按模型 (按人 only where several spent: a list of one has no parts).
fn usage_split(c : @ui.Ctx, v : Json?) -> Unit {
  let lists = items(v, "lists")
  let choices = ["people", "models"].filter(fn(k) {
    lists.iter().any(fn(l) { text(Some(l), "key") == k && items(Some(l), "parts").length() > 0 })
  })
  let split = text(v, "split")
  c.box(style=ug_split_line, flow=true, fn() {
    c.box(style=ug_legend, flow=true, fn() {
      let series = items(v, "series")
      for i, sv in series {
        let pv = Some(sv)
        let key = text(pv, "key")
        let alone = key != "" && usage_pick.only.get() != (split, key)
        let id = if alone { c.id("usage-series/" + split + "/" + key) } else { 0 }
        if alone && c.clicked(id) {
          usage_pick.only.set((split, key))
          usage_pick.all.set(false)
        }
        let lit = alone && c.lit(id)
        let b = c.box(style=ug_legend_item, id~, fn() {
          c.box(style=ug_dot.then(@ui.style(bg=Data(usage_series_ink(series, i)))), fn() {  }) |> ignore
          c.text(text(pv, "name"), style=if lit { ug_legend_lit } else { ug_legend_words }) |> ignore
        })
        if alone {
          c.semantics(b, Button, id~, label=@sf.t("web-main.usage.only", args=[("name", text(pv, "name"))]))
        }
      }
    })
    |> ignore
    if choices.length() > 1 {
      let labels = choices.map(fn(k) {
        match lists.search_by(fn(l) { text(Some(l), "key") == k }) {
          Some(i) => text(Some(lists[i]), "title")
          None => k
        }
      })
      let at = choices.search(split).unwrap_or(0)
      let picked = @sf.segmented(c, "usage-split", labels, at)
      if picked != at {
        usage_pick.split.set(choices[picked])
        usage_pick.only.set(("", ""))
      }
    }
  })
  |> ignore
}

///|
/// A part's colour: the first four's own, the rest's (其他, no key) the theme's grey.
fn usage_series_ink(series : Array[Json], i : Int) -> Int64 {
  if i < series.length() && text(Some(series[i]), "key") == "" {
    @sf.theme().p.subtle
  } else {
    @sf.usage_series(i)
  }
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
/// The chats that cost the most (the first 8 until all are asked for), each its name and what it spent, who it was for,
/// its model and where it is and its share, a bar of its share under them; one pressed opens it.
fn usage_chats(c : @ui.Ctx, core : Core, v : Json?) -> Unit {
  let list = match items(v, "lists").search_by(fn(l) { text(Some(l), "key") == "chats" }) {
    Some(i) => Some(items(v, "lists")[i])
    None => None
  }
  let all_items = items(list, "items")
  if all_items.length() == 0 {
    return
  }
  c.box(style=ug_card_rows, fn() {
    usage_card_title(c, @sf.t("web-main.usage.topChats"))
    c.box(style=ug_rows, fn() {
      for i, it in all_items {
        if usage_pick.all.get() || i < ug_first {
          usage_chat_row(c, core, it)
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
/// The cost's change against the days before (↑18% in the words' ink, 比前 7 天 muted after it), on its foot; none
/// where the core says none. Not coloured: a change is not a fault.
fn usage_change(c : @ui.Ctx, v : Json?, tv : Json?) -> Unit {
  if text(tv, "change") == "" {
    return
  }
  c.box(style=ug_change_line, fn() {
    c.text(text(tv, "change"), style=ug_change) |> ignore
    c.text(text(v, "versus"), style=ug_change_versus) |> ignore
  })
  |> ignore
}

///|
/// Each day's cost as a bar on the days' foot (DaysChart), the day seen alone in full and the others faded (all in
/// full with none). A day pressed is seen alone, pressed again all of them again; a finger slid across the days lets
/// go on the one it ends on.
fn usage_chart(c : @ui.Ctx, v : Json?) -> Unit {
  let daily = items(v, "daily")
  let series = items(v, "series")
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
            usage_bar(c, dv, series, top, many, shown == "" || key == shown, if key == said {
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
/// A day's bar (`d`), as high as its share of the scale's top, as wide as @sf.usage_bar_max at most (as wide as its day
/// with many days), round at its top: its parts stacked in their colours, the first at its foot; a day other than the
/// one shown on the tint. `said` over it: what
/// the most spent day spent (the one shown's, with one).
fn usage_bar(c : @ui.Ctx, d : Json?, series : Array[Json], top : Double, many : Bool, on : Bool, said : String) -> Unit {
  let cost = number(d, "cost")
  if top <= 0.0 || cost <= 0.0 {
    return
  }
  let h = @sf.usage_plot * @cmp.minimum(1.0, cost / top)
  if said != "" {
    c.text(said, style=ug_peak) |> ignore
  }
  let style = if many { ug_bar_many } else { ug_bar }
  if !on {
    c.box(style=style.then(@ui.style(h=Fixed(h), bg=TintStrong)), fn() {  }) |> ignore
    return
  }
  // its parts, the first at its foot (a day of none of them: the accent's whole)
  let shares = match field(d, "shares") {
    Some(Array(xs)) =>
      xs.map(fn(x) {
        match x {
          Number(n, ..) => n
          _ => 0.0
        }
      })
    _ => []
  }
  c.box(style=style.then(@ui.style(h=Fixed(h))), fn() {
    if shares.length() == 0 {
      c.box(style=ug_bar_part.then(@ui.style(h=@sf.grow, bg=Accent)), fn() {  }) |> ignore
    }
    for k = shares.length() - 1; k >= 0; k = k - 1 {
      if shares[k] > 0.0 {
        c.box(style=ug_bar_part.then(@ui.style(h=Grow(shares[k]), bg=Data(usage_series_ink(series, k)))), fn() {  })
        |> ignore
      }
    }
  })
  |> ignore
}

///|
/// A chat and what it spent (Row): its name and its cost on a line, who it was for, its model and where it is and its
/// share under them, a bar of its share last. Pressed, it opens (the hover's ground under the pointer).
fn usage_chat_row(c : @ui.Ctx, core : Core, it : Json) -> Unit {
  let iv = Some(it)
  let chat = field(iv, "chat")
  let opens = chat is Some(Object(_))
  let id = if opens { c.id("usage-item/chats/" + text(iv, "key")) } else { 0 }
  if opens && c.clicked(id) {
    (core.open_chat)(text(chat, "station"), text(chat, "session"), text(iv, "title"))
  }
  let lit = opens && c.lit(id)
  c.box(style=if opens { ug_row_link } else { ug_row }, id~, fn() {
    // (its name and cost on a line, what it is on the next with its share at its end)
    c.box(style=ug_line, fn() {
      c.text(text(iv, "title"), style=if lit { ug_row_title_lit } else { ug_row_title }) |> ignore
      c.text(text(iv, "costText"), style=ug_cost) |> ignore
    })
    |> ignore
    c.box(style=ug_line, fn() {
      c.text(text(iv, "sub"), style=ug_row_sub) |> ignore
      c.text(text(iv, "shareText"), style=ug_line_end) |> ignore
    })
    |> ignore
    usage_track(c, number(iv, "share"))
  })
  |> ignore
}

///|
/// A share's bar in the accent on the tint (1% at least for one spent at all).
fn usage_track(c : @ui.Ctx, share : Double) -> Unit {
  c.box(style=ug_track, fn() {
    let k = if share <= 0.0 { 0.0 } else { @cmp.minimum(1.0, @cmp.maximum(0.01, share)) }
    if k > 0.0 {
      c.box(style=ug_track_part.then(@ui.style(w=Grow(k), bg=Accent)), fn() {  }) |> ignore
    }
    let rest = 1.0 - k
    if rest > 0.0 {
      c.box(style=ug_track_rest.then(@ui.style(w=Grow(rest))), fn() {  }) |> ignore
    }
  })
  |> ignore
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
/// A card of the page: its words 20 in, 20 apart, the ladder's corner (what lies in its corners round by the ladder's
/// there: mbui works it out).
// kept across runs: a value (no field of it changes)
let ug_card : @ui.Style = @ui.css("w=Full p=S5 gap=S5 radius=Xl3 bg=Card")

///|
/// A card whose rows reach its foot (the allowances, the chats, the makeup): its last row's ground as far from its
/// foot as from its sides (@sf.corner_inset), so that ground stands concentric in the card's corners.
// kept across runs: a value (no field of it changes)
let ug_card_rows : @ui.Style = ug_card.then(@ui.style(pb=@sf.room_of(@sf.corner_inset)))

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
/// ↑18% 比前 7 天 on the cost's foot, 4 apart.
// kept across runs: a value (no field of it changes)
let ug_change_line : @ui.Style = @ui.css("row gap=S1 pb=S1_5 align=ACenter")

///|
/// A change: its figure in the words' ink, what it is against muted.
// kept across runs: a value (no field of it changes)
let ug_change : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_change_versus : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// The summary's column: 760 across at most, in its card's middle, its parts 24 apart.
// kept across runs: a value (no field of it changes)
let ug_sum : @ui.Style = @ui.style(w=Full, max_w=@sf.usage_summary_w, gap=S6, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let ug_sum_title : @ui.TextStyle = @ui.text_style(size=Lg, leading=L7, weight=Semibold, color=Fg, wrap=false, w=Cut)

///|
/// The five figures side by side, as many to a line as have 96 across, 16 apart.
// kept across runs: a value (no field of it changes)
let ug_figures : @ui.Style = @ui.css("row w=Full gap=S4 justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let ug_figure : @ui.Style = @ui.style(w=@sf.grow, min_w=S24, gap=S0_5, align=ACenter)

///|
/// A figure: its value large and bold, what it is muted under it (Codex's bold over secondary), both in the middle.
// kept across runs: a value (no field of it changes)
let ug_figure_value : @ui.TextStyle = @ui.text_style(size=Xl2, leading=L8, weight=Bold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_figure_label : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// The year: its head, its grid, what is under it, 12 apart.
// kept across runs: a value (no field of it changes)
let ug_year : @ui.Style = @ui.css("w=Full gap=S3")

///|
// kept across runs: a value (no field of it changes)
let ug_year_head : @ui.Style = @ui.style(w=@sf.grow, gap=SPx)

///|
/// The grid: a row of the months' names, then a row a weekday, 2 apart; each row its name 20 across, then its weeks
/// (the months' row its months, one room each across their weeks).
// kept across runs: a value (no field of it changes)
let ug_grid : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let ug_grid_row : @ui.Style = @ui.css("row w=Full gap=S0_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ug_grid_lead : @ui.Style = @ui.css("w=S5")

///|
/// A month's room in the months' row: as wide as its weeks (with their gaps), its name at its start, cut at its end.
// kept across runs: a value (no field of it changes)
let ug_months : @ui.Style = @ui.css("h=S3_5 clip")

///|
/// A day: as wide as its week's share of the row, as high. own corner: a cell of a chart, not a box in a corner
// kept across runs: a value (no field of it changes)
let ug_cell : @ui.Style = @ui.style(w=@sf.grow, radius=Sm)

///|
// kept across runs: a value (no field of it changes)
let ug_grid_label : @ui.TextStyle = @ui.text_style(size=Caption, leading=L3, color=Muted, wrap=false)

///|
/// 少 □■■■■ 多: the levels 10 across, 2 apart.
// kept across runs: a value (no field of it changes)
let ug_legend_line : @ui.Style = @ui.css("row gap=S0_5 align=ACenter")

///|
/// A level of the legend. own corner: as a day's
// kept across runs: a value (no field of it changes)
let ug_legend_cell : @ui.Style = @ui.style(w=@sf.usage_level_side, h=@sf.usage_level_side, radius=Sm)

///|
/// Each device's work and where the chats came from: side by side, 32 apart, each 240 at least (under each other where
/// they have not the room).
// kept across runs: a value (no field of it changes)
let ug_lists : @ui.Style = @ui.css("row w=Full gap=S8 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let ug_named : @ui.Style = @ui.style(w=@sf.grow, min_w=S60, gap=S2)

///|
// kept across runs: a value (no field of it changes)
let ug_named_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_named_name : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let ug_named_value : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Fg, wrap=false)

///|
/// The bars' parts named and what they are split by, at the line's end (under the names where they have not the room).
// kept across runs: a value (no field of it changes)
let ug_split_line : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
/// The parts named, 12 apart, in lines where they have not the room.
// kept across runs: a value (no field of it changes)
let ug_legend : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S3, align=ACenter)

///|
/// A part named: a dot 8 of its colour, its name (cut short where its line has not the room), 6 apart (pressed: its
/// name in the accent's words under the pointer).
// kept across runs: a value (no field of it changes)
let ug_legend_item : @ui.Style = @ui.css("row w=Cut gap=S1_5 py=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ug_dot : @ui.Style = @ui.css("w=S2 h=S2 radius=Full")

///|
// kept across runs: a value (no field of it changes)
let ug_legend_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let ug_legend_lit : @ui.TextStyle = ug_legend_words.then(@ui.text_style(color=Fg))

///|
/// What the page is narrowed to: its chips, 8 apart, in lines where they have not the room.
// kept across runs: a value (no field of it changes)
let ug_chips : @ui.Style = @ui.css("row w=Full gap=S2")

///|
/// A line of a row: its words at its start (cut short where it has not the room), its figures at its end, 12 apart.
// kept across runs: a value (no field of it changes)
let ug_line : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
/// A figure at a line's end (what it spent, a share): muted.
// kept across runs: a value (no field of it changes)
let ug_line_end : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// A chat's row: its lines, its bar 6 under them, its words in line with the card's title (pressed: the hover's ground
/// under the pointer).
// kept across runs: a value (no field of it changes)
let ug_row : @ui.Style = @ui.style(w=Full, px=@sf.room_of(@sf.card_pad - @sf.corner_inset), py=S2, gap=S1_5, radius=InnerOr(Xl2))

///|
// kept across runs: a value (no field of it changes)
let ug_row_link : @ui.Style = ug_row.then(@ui.css("hovered{bg=Hover}"))

///|
/// A share's bar: 4 high, round, on the tint.
// kept across runs: a value (no field of it changes)
let ug_track : @ui.Style = @ui.css("row w=Full h=S1 radius=Full bg=TintStrong clip")

///|
// kept across runs: a value (no field of it changes)
let ug_track_part : @ui.Style = @ui.css("h=Full radius=Full")

///|
// kept across runs: a value (no field of it changes)
let ug_track_rest : @ui.Style = @ui.css("h=Full")

///|
/// A card's title: the ui's size, semibold, in the words' ink.
// kept across runs: a value (no field of it changes)
let ug_card_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, w=Full)

///|
/// The plot (150 high).
// kept across runs: a value (no field of it changes)
let ug_plot : @ui.Style = @ui.style(w=Full, h=@sf.usage_plot_h)

///|
/// The days side by side, 6 apart (2 with many).
// kept across runs: a value (no field of it changes)
let ug_days : @ui.Style = @ui.css("row w=Full h=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let ug_days_many : @ui.Style = ug_days.then(@ui.css("gap=S0_5"))

///|
// kept across runs: a value (no field of it changes)
let ug_day : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JEnd")

///|
/// A bar: @sf.usage_bar_max wide at most (as wide as its day with many), round 4, its parts clipped to it. own corner: a
/// bar of a chart, not a box in a corner of the ladder's
// kept across runs: a value (no field of it changes)
let ug_bar : @ui.Style = @ui.style(w=Full, max_w=@sf.usage_bar_max, radius=Base, clip=true)

///|
/// What the most spent day spent, over its bar (the caption's, semibold).
// kept across runs: a value (no field of it changes)
let ug_peak : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, weight=Semibold, color=Fg, wrap=false)

///|
/// With many days: as wide as its day, round 2. own corner: as a bar's
// kept across runs: a value (no field of it changes)
let ug_bar_many : @ui.Style = @ui.css("w=Full radius=Sm clip")

///|
/// A part of a bar: as wide as it, as high as its share of it.
// kept across runs: a value (no field of it changes)
let ug_bar_part : @ui.Style = @ui.css("w=Full")

///|
/// The plot's foot (its border-bottom).
// kept across runs: a value (no field of it changes)
let ug_base : @ui.Style = @ui.css("w=Full h=SPx bg=Line")

///|
/// Each day's name under its bar (labels: 6 under the plot, as far apart as the days), the one shown in the accent's
/// words in 500; whole, past its day's width on either side when the days are narrow (30 of them on a phone: a date a
/// week).
// kept across runs: a value (no field of it changes)
let ug_labels : @ui.Style = @ui.css("row w=Full pt=S1_5 gap=S1_5")

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
/// A card's rows: out across its room to @sf.corner_inset from its edges (their grounds there), their words in line
/// with its title.
// kept across runs: a value (no field of it changes)
let ug_rows : @ui.Style = @ui.style(mx=@sf.room_of(@sf.corner_inset - @sf.card_pad))

///|
// kept across runs: a value (no field of it changes)
let ug_row_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Fg, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let ug_row_title_lit : @ui.TextStyle = ug_row_title.then(@ui.text_style(color=AccentText))

///|
/// What it is (who it was for, its model, where), cut short where its line has not the room.
// kept across runs: a value (no field of it changes)
let ug_row_sub : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let ug_cost : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, wrap=false)

///|
/// 显示全部 / 收起 (more: its words in line with the rows', a row's corner; the hover's ground and the words' ink
/// under the pointer).
// kept across runs: a value (no field of it changes)
let ug_more : @ui.Style = @ui.style(px=@sf.room_of(@sf.card_pad - @sf.corner_inset), py=S2, radius=InnerOr(Xl2)).then(@ui.css("hovered{bg=Hover}"))

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
