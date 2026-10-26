// The cards over the rail's places as the pointer rests on them (the core's `railCard` view, views/rail-cards.ts;
// 2026-10-26 用户：「好几个 tab 都可以 hover 出卡片，比如 chat，stations，profiles，usage」「显示一些有用的统计信息」, then
// 「stations 和 profiles tab 的 hover 卡片去掉吧，分享放到 usage 的 hover 卡片上」): 对话 and 用量, each the same card: a line
// saying how the place stands, its figures side by side (each its value over what it is of, one that wants a look in
// its colour), the last 7 days as bars where it has them, what it is made of a line each; 分享卡片 at its foot where
// the core offers it (用量's).

///|
/// Place `place`'s card of workspace `w` (chats, usage), as its core says it.
pub fn rail_card(c : @ui.Ctx, src : Source, w : Workspace, place : String) -> Unit {
  let card = (src.topic)("railCard", { "scope": Json::string(w.id), "place": Json::string(place) }).value
  c.box(style=rc_box, fn() {
    c.text(text(card, "head"), style=rc_head) |> ignore
    let stats = items(card, "stats")
    if stats.length() > 0 {
      c.box(style=rc_stats, fn() {
        for s in stats {
          let s = Some(s)
          c.box(style=rc_stat, fn() {
            c.text(text(s, "value"), style=rc_value.then(toned(text(s, "tone")))) |> ignore
            c.text(text(s, "label"), style=rc_label) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
    let days = items(card, "days")
    if days.length() > 0 {
      rc_days(c, days)
    }
    let rows = items(card, "rows")
    if rows.length() > 0 {
      c.box(style=rc_rows, fn() {
        for r in rows {
          rc_row(c, Some(r))
        }
      })
      |> ignore
    }
    if flag(card, "share") {
      let id = c.id("rail/share")
      if c.clicked(id) {
        share_card_open(src, w)
      }
      c.box(style=rc_share, id~, label=@sf.t("web-main.stations.shareCard"), fn() {
        @sf.icon(c, "photo", size=16.0, color=@sf.theme().p.text) |> ignore
        c.text(@sf.t("web-main.stations.shareCard"), style=rc_share_words) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// What a line is made of: its name, what is at its end (a model's, what it cost).
fn rc_row(c : @ui.Ctx, r : Json?) -> Unit {
  c.box(style=rc_line, fn() {
    c.box(style=rc_name_room, fn() { c.text(text(r, "name"), style=rc_name) |> ignore }) |> ignore
    c.text(text(r, "value"), style=rc_end) |> ignore
  })
  |> ignore
}

///|
/// The last 7 days, a bar each as tall as its share of the most on a day (3 at least: a day with nothing still seen),
/// today's in the words' colour, each day's date under it.
fn rc_days(c : @ui.Ctx, days : Array[Json]) -> Unit {
  c.box(style=rc_days_row, fn() {
    for d in days {
      let d = Some(d)
      let today = flag(d, "today")
      let h = dmax(rc_bar_least, number(d, "share") * rc_bars_h)
      c.box(style=rc_day, fn() {
        c.box(style=rc_bar_room, fn() {
          c.box(style=(if today { rc_bar_today } else { rc_bar }).then(@ui.style(h=Fixed(h))), fn() {  }) |> ignore
        })
        |> ignore
        c.text(text(d, "label"), style=if today { rc_day_today } else { rc_day_label }) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// Words in a tone the core gave: red (gone wrong, used up), amber (wants a look); else as they are.
fn toned(tone : String) -> @ui.TextStyle {
  match tone {
    "red" => rc_red
    "amber" => rc_amber
    _ => rc_plain
  }
}

///|
/// The card's parts 10 apart.
// kept across runs: a value (no field of it changes)
let rc_box : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let rc_head : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, wrap=false, w=Cut)

///|
/// The figures side by side, each as wide.
// kept across runs: a value (no field of it changes)
let rc_stats : @ui.Style = @ui.css("row w=Full gap=S3")

///|
// kept across runs: a value (no field of it changes)
let rc_stat : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
/// A figure's value, large as a title, over what it is of.
// kept across runs: a value (no field of it changes)
let rc_value : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let rc_label : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let rc_red : @ui.TextStyle = @ui.text_style(color=Danger)

///|
// kept across runs: a value (no field of it changes)
let rc_amber : @ui.TextStyle = @ui.text_style(color=WarnInk)

///|
// kept across runs: a value (no field of it changes)
let rc_plain : @ui.TextStyle = @ui.text_style()

///|
/// The lines, 8 apart.
// kept across runs: a value (no field of it changes)
let rc_rows : @ui.Style = @ui.css("w=Full gap=S2")

///|
/// A line: its name, what is at its end.
// kept across runs: a value (no field of it changes)
let rc_line : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let rc_name_room : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let rc_name : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let rc_end : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// The days' bars side by side, 4 apart.
// kept across runs: a value (no field of it changes)
let rc_days_row : @ui.Style = @ui.css("row w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let rc_day : @ui.Style = @ui.style(w=@sf.grow, gap=S1, align=ACenter)

///|
/// A bar's room: as tall as the most on a day's, its bar standing on its foot.
// kept across runs: a value (no field of it changes)
let rc_bar_room : @ui.Style = @ui.css("w=Full justify=JEnd").then(@ui.style(h=Fixed(rc_bars_h)))

///|
let rc_bars_h : Double = 28.0

///|
let rc_bar_least : Double = 3.0

///|
// kept across runs: a value (no field of it changes)
let rc_bar : @ui.Style = @ui.css("w=Full radius=Sm bg=A(Fg,O15)")

///|
// kept across runs: a value (no field of it changes)
let rc_bar_today : @ui.Style = @ui.css("w=Full radius=Sm bg=Fg")

///|
// kept across runs: a value (no field of it changes)
let rc_day_label : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let rc_day_today : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, color=Fg, wrap=false)

///|
/// 分享卡片: a block across the card at its foot, round as its corners (login_card's lc_open).
// kept across runs: a value (no field of it changes)
let rc_share : @ui.Style = @ui.css(
  "row w=Full h=S8 mt=S1 px=S3 gap=S1_5 radius=Inner bg=A(Fg,O5) align=ACenter justify=JCenter hovered{bg=Hover}",
)

///|
// kept across runs: a value (no field of it changes)
let rc_share_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)
