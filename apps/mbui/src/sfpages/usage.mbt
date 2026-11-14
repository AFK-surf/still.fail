// 用量, one page in every frame (still.fail web/src/cloud/settings.tsx UsageSettings; the narrow app's mobile/Usage.tsx;
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
//
// Laid out as Codex's `/usage` with still.fail's own figures (the user, 2026-11-02: 「抄 codex」「连续多少天那个没用
// 」).

///|
/// What the page picked: its days, how the summary's year is drawn (0 by day, 1 by week, 2 their running total), what
/// the days' bars are split by ("" the core's choice), the day seen alone ("" all),
/// whether all the chats are shown, and the one seen alone (its list and key; "" none).
priv struct UsagePick {
  days : @signals.Signal[Int]
  summary : @signals.Signal[Bool]
  year : @signals.Signal[Int]
  split : @signals.Signal[String]
  rank : @signals.Signal[String]
  day : @signals.Signal[String]
  all : @signals.Signal[Bool]
  only : @signals.Signal[(String, String)]
}

///|
// kept across runs: said by the page's picks; usage_reset puts it back
let usage_pick : UsagePick = {
  days: @signals.signal(7, same=fn(a, b) { a == b }),
  summary: @signals.signal(false, same=fn(a, b) { a == b }),
  year: @signals.signal(0, same=fn(a, b) { a == b }),
  split: @signals.signal("", same=fn(a, b) { a == b }),
  rank: @signals.signal("chats", same=fn(a, b) { a == b }),
  day: @signals.signal("", same=fn(a, b) { a == b }),
  all: @signals.signal(false, same=fn(a, b) { a == b }),
  only: @signals.signal(("", ""), same=fn(a, b) { a == b }),
}

///|
fn usage_reset() -> Unit {
  usage_pick.days.set(7)
  usage_pick.summary.set(false)
  usage_pick.year.set(0)
  usage_pick.split.set("")
  usage_pick.rank.set("chats")
  usage_pick.day.set("")
  usage_pick.all.set(false)
  usage_pick.only.set(("", ""))
}

///|
/// The days the page shows.
// kept across runs: a table, never written
let usage_days_choices : Array[Int] = [7, 30]

///|
/// What the page asks of the core (a topic and its params): its `usage` view of its workspace's `days`, `split` ("" the
/// core's choice), of the one picked alone (`only`: its list and key), of the day picked (`day`). The chart's is asked
/// with neither: it keeps the whole period and all its parts, so picks do not replace its legend or scale.
fn usage_ask(
  here : Here,
  days : Int,
  split : String,
  only? : (String, String) = ("", ""),
  day? : String = "",
) -> (String, Map[String, Json]) {
  let args : Map[String, Json] = { "scope": str(here.workspace), "days": Json::number(days.to_double()) }
  if only.0 != "" {
    args["only"] = { "list": str(only.0), "key": str(only.1) }
  }
  if split != "" {
    args["split"] = str(split)
  }
  if day != "" {
    args["day"] = str(day)
  }
  ("usage", args)
}

///|
/// What the page reads as it is drawn with these picks (usage_ask's): what was spent, then the chart's.
fn usage_reads(here : Here, days : Int, split : String, only : (String, String), day : String) -> Array[(String, Map[String, Json])] {
  [usage_ask(here, days, split, only~, day~), usage_ask(here, days, split)]
}

///|
/// What usage_node's readers say they have read anew by, what a choice pressed asked handed to them (sfbase's
/// switch_answered, shown_read).
// kept across runs: a name, never written
let usage_shown_at : String = "usage"

///|
/// The part picked in this chart, if the pick belongs to its split.
fn usage_chart_only(v : Json?) -> String {
  let (list, key) = usage_pick.only.get()
  if list != "" && list == text(v, "split") { key } else { "" }
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
/// A part's colour: the first four's own, the rest's (其他, no key) the theme's grey.
fn usage_series_ink(series : Array[Json], i : Int) -> Int64 {
  if i < series.length() && text(Some(series[i]), "key") == "" {
    @sf.theme().p.subtle
  } else {
    @sf.usage_series(i)
  }
}

///|
/// The first of the chats shown until all are asked for (Ranking's `first`).
let ug_first : Int = 8

///|
// kept across runs: a value (no field of it changes)
let ug_hero_label : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Muted, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let ug_prices_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_prices_lit : @ui.TextStyle = ug_prices_words.then(@ui.text_style(color=Fg))

///|
/// The cost of the days (the page's one figure on its own: a large title's words).
// kept across runs: a value (no field of it changes)
let ug_hero_value : @ui.TextStyle = @ui.text_style(size=Xl5, weight=Bold, tracking=Tight, color=Fg, wrap=false)

///|
/// A change: its figure in the words' ink, what it is against muted.
// kept across runs: a value (no field of it changes)
let ug_change : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_change_versus : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// A figure: its value large and bold, what it is muted under it (Codex's bold over secondary), both in the middle.
// kept across runs: a value (no field of it changes)
let ug_figure_value : @ui.TextStyle = @ui.text_style(size=Xl2, leading=L8, weight=Bold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_figure_label : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_grid_label : @ui.TextStyle = @ui.text_style(size=Caption, leading=L3, color=Muted, wrap=false)

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
// kept across runs: a value (no field of it changes)
let ug_legend_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let ug_legend_lit : @ui.TextStyle = ug_legend_words.then(@ui.text_style(color=Fg))

///|
/// A figure at a line's end (what it spent, a share): muted.
// kept across runs: a value (no field of it changes)
let ug_line_end : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// A card's title: the ui's size, semibold, in the words' ink.
// kept across runs: a value (no field of it changes)
let ug_card_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, w=Full)

///|
/// What the most spent day spent, over its bar (the caption's, semibold).
// kept across runs: a value (no field of it changes)
let ug_peak : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_label : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_label_on : @ui.TextStyle = ug_label.then(@ui.text_style(weight=Medium, color=AccentText))

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
// kept across runs: a value (no field of it changes)
let ug_more_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Link, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_more_lit : @ui.TextStyle = ug_more_words.then(@ui.text_style(color=Link))

///|
// kept across runs: a value (no field of it changes)
let ug_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, w=Full)

///|
// kept across runs: a value (no field of it changes)
let ug_empty : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
/// A station's name over its prices (priceStation: the title's size, semibold).
// kept across runs: a value (no field of it changes)
let up_station : @ui.TextStyle = @ui.text_style(size=Ui, leading=L7, weight=Semibold, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let ug_tile_value : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_tile_label : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_legend_cost : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ug_scale_label : @ui.TextStyle = @ui.text_style(size=Caption, leading=L3, color=Subtle, wrap=false)

