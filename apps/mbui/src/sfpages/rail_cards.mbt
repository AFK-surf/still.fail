// The cards over the rail's places as the pointer rests on them (the core's `railCard` view, views/rail-cards.ts;
// 2026-10-26 用户：「好几个 tab 都可以 hover 出卡片，比如 chat，stations，profiles，usage」「显示一些有用的统计信息」, then
// 「stations 和 profiles tab 的 hover 卡片去掉吧，分享放到 usage 的 hover 卡片上」): 对话 and 用量, each the same card: a line
// saying how the place stands, its figures side by side (each its value over what it is of, one that wants a look in
// its colour), the last 7 days as bars where it has them, what it is made of a line each; 分享卡片 at its foot where
// the core offers it (用量's).

///|
/// Place `place`'s card of the workspace `ws` says (chats, usage) as nodes in `parent`, as its core says it now: its
/// line, its figures side by side, the last 7 days as bars, its lines, 分享卡片 where the core offers it. A figure the
/// core says opens a place (`go`: 对话's, the chats it counts) is pressed for it: `go` given that place.
pub fn rail_card_node(
  parent : @view.View,
  src : Source,
  ws : () -> Workspace?,
  place : String,
  go? : (String) -> Unit = fn(_) {  },
) -> Unit {
  let card = fn() {
    match ws() {
      Some(w) => src.topic("railCard", { "scope": Json::string(w.id), "place": Json::string(place) }).get().value
      None => None
    }
  }
  parent.box(fn(b) {
    @sf.style_node(b, fn() { rc_box })
    @sf.words_node(b, fn() { text(card(), "head") }, fn() { rc_head }) |> ignore
    b.show(fn() { items(card(), "stats").length() > 0 }, fn(row) {
      @sf.style_node(row, fn() {
        if items(card(), "stats").iter().any(fn(s) { text(Some(s), "go") != "" }) {
          rc_stats_go
        } else {
          rc_stats
        }
      })
      row.each(fn() { items(card(), "stats") }, fn(s) { text(Some(s), "label") }, fn(st, s) {
        let to = fn() { text(Some(s.get()), "go") }
        @sf.style_node(st, fn() { if to() == "" { rc_stat } else { rc_stat_go } }, in_row=true)
        st
        .presses(By(fn() { to() != "" }))
        .focusable(By(fn() { to() != "" }))
        .says(By(fn() {
          if to() == "" {
            None
          } else {
            Some(@view.said(Button, label=text(Some(s.get()), "label") + " " + text(Some(s.get()), "value")))
          }
        }))
        .on_press(fn() {
          let p = @signals.untracked(to)
          if p != "" {
            go(p)
          }
        })
        // (its ground the hover's as the hand is on it)
        .ground(By(fn() { if to() != "" && @sf.lit_node(st) { @sf.theme().p.hover } else { 0L } }))
        .radius(By(fn() { if to() == "" { 0.0 } else { rc_stat_corner() } }))
        |> ignore
        @sf.words_node(st, fn() { text(Some(s.get()), "value") }, fn() { rc_value.then(toned(text(Some(s.get()), "tone"))) })
        |> ignore
        @sf.words_node(st, fn() { text(Some(s.get()), "label") }, fn() { rc_label }) |> ignore
      })
    })
    b.show(fn() { items(card(), "days").length() > 0 }, fn(days) { rc_days_node(days, fn() { items(card(), "days") }) })
    b.show(fn() { items(card(), "rows").length() > 0 }, fn(rows) {
      @sf.style_node(rows, fn() { rc_rows })
      rows.each(fn() { items(card(), "rows") }, fn(r) { text(Some(r), "name") }, fn(line, r) {
        @sf.style_node(line, fn() { rc_line })
        line.box(fn(n) {
          @sf.style_node(n, fn() { rc_name_room }, in_row=true)
          @sf.words_node(n, fn() { text(Some(r.get()), "name") }, fn() { rc_name }) |> ignore
        })
        |> ignore
        @sf.words_node(line, fn() { text(Some(r.get()), "value") }, fn() { rc_end }) |> ignore
      })
    })
    b.show(fn() { flag(card(), "share") }, fn(k) {
      let label = fn() { @sf.t("web-main.stations.shareCard") }
      @sf.style_node(k, fn() { rc_share })
      k
      .presses(Is(true))
      .focusable(Is(true))
      .says(By(fn() { Some(@view.said(Button, label=label())) }))
      .on_press(fn() {
        match @signals.untracked(ws) {
          Some(w) => share_card_open(src, w)
          None => ()
        }
      })
      // (its ground the hover's as the hand is on it: rc_share's hovered; its corner concentric with the card's)
      .ground(By(fn() { if @sf.lit_node(k) { @sf.theme().p.hover } else { @sf.alpha(@sf.theme().p.text, 0.05) } }))
      .radius(By(fn() { rc_stat_corner() }))
      |> ignore
      @sf.icon_node(k, "share", 16.0, By(fn() { @sf.theme().p.text })) |> ignore
      @sf.words_node(k, label, fn() { rc_share_words }) |> ignore
    })
  })
  |> ignore
}

///|
/// The last 7 days as nodes in `row` (`days` as the core says them now), a bar each as tall as its share of the most
/// on a day (3 at least: a day with nothing still seen), today's in the words' colour, each day's date under it.
fn rc_days_node(row : @view.View, days : () -> Array[Json]) -> Unit {
  @sf.style_node(row, fn() { rc_days_row })
  row.each(days, fn(d) { text(Some(d), "label") }, fn(day, d) {
    let today = fn() { flag(Some(d.get()), "today") }
    @sf.style_node(day, fn() { rc_day }, in_row=true)
    day.box(fn(room) {
      @sf.style_node(room, fn() { rc_bar_room })
      room.box(fn(bar) {
        @sf.style_node(bar, fn() { if today() { rc_bar_today } else { rc_bar } })
        bar.height(By(fn() { Some(dmax(rc_bar_least, number(Some(d.get()), "share") * rc_bars_h)) })) |> ignore
      })
      |> ignore
    })
    |> ignore
    @sf.words_node(day, fn() { text(Some(d.get()), "label") }, fn() { if today() { rc_day_today } else { rc_day_label } })
    |> ignore
  })
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
/// The same of figures that are pressed, 20 apart: a pressed one's ground (rc_stat_go) reaches 10 past its words.
// kept across runs: a value (no field of it changes)
let rc_stats_go : @ui.Style = @ui.css("row w=Full gap=S5")

///|
// kept across runs: a value (no field of it changes)
let rc_stat : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
/// A figure that opens the chats it counts: its ground out past its words to the card's padding, 10 all round (the
/// figures 20 apart: the grounds of two side by side meet, never overlap), its words where they were; its corner
/// rc_stat_corner's.
// kept across runs: a value (no field of it changes)
let rc_stat_go : @ui.Style = rc_stat.then(@ui.css("p=S2_5")).then(
  @ui.style(mx=@sf.room_of(-rc_stat_out), my=@sf.room_of(-rc_stat_out)),
)

///|
/// A pressed figure's corner: concentric with the card's (a small panel's, @sf.r_menu) at its padding, where its ground
/// lies (as 分享卡片's, rc_share), where the theme's ranges let it be; else its own (Md).
fn rc_stat_corner() -> Double {
  let t = @ui.tree_theme()
  @ui.CornerOf::Follow(@ui.CornerOf::Own(@sf.r_menu), @sf.panel_pad, t.corner(Md)).radius(
    @ui.tree_corner_roots_now(),
  )
}

///|
/// How far a pressed figure's ground reaches past its words: its padding (p=S2_5), its words left where they were.
let rc_stat_out : Double = hover_words_in

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
/// 分享卡片: a block across the card at its foot, out past its words to its padding (hover_words_in: the panel's 6 from
/// its edges), 36 high, a small panel's row: a capsule concentric with its corners there (6 and 18, 24; login_card's lc_open);
/// on the words' colour at 5%, the hover's as the hand is on it (rail_card_node).
// kept across runs: a value (no field of it changes)
let rc_share : @ui.Style = @ui.css("row w=Full h=S9 mt=S1 px=S3 gap=S1_5 align=ACenter justify=JCenter").then(
  @ui.style(mx=@sf.room_of(-hover_words_in), mb=@sf.room_of(-hover_words_in)),
)

///|
// kept across runs: a value (no field of it changes)
let rc_share_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)
