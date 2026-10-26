// The chats' sidebar as the web's lists (ember web/src/Sidebar.tsx ChatList, Sidebar.css.ts navSlider, navTrack;
// pages/Archive.tsx ArchiveRows, ArchivePage; Archive.css.ts): under the band (新建对话 and the filter), one track of
// the lists side by side, 全部, 我参与的, 监控中, 奏 and 已归档, slid from one to another as the list shown changes
// (240 ms, ease out); only those in view are drawn. 已归档 is a list of the sidebar's like the others: a field to look
// for one, its days, each archived chat a row (put back or deleted while pointed at), pressed its chat beside the
// list; opened, the newest of them is open beside it, or with none what the archive is.

///|
/// The sidebar `width` wide (its 8 at the left over the rail's empty side), the one the block holds (side_place): the
/// chats' lists (奏 and 已归档 among them) for the chats' places; the files' (files_nav.mbt); a place's own (the app's:
/// the settings', the stations', the profiles').
fn sidebar(c : @ui.Ctx, src : Source, w : Workspace, width : Double) -> Unit {
  match side_place() {
    "files" => files_nav(c, src, w.id)
    "settings" => settings_side(c, src, w)
    "stations" => stations_side(c, src, w)
    "profiles" => profiles_side(c, src, w)
    _ => lists_side(c, src, w, width)
  }
}

///|
/// The chats' sidebar `width` wide: the band over the lists (sfpages' chats_lists: 全部, 我参与的, 监控中, then 奏 and
/// 已归档 on its track).
fn lists_side(c : @ui.Ctx, src : Source, w : Workspace, width : Double) -> Unit {
  ignore(width)
  let mode = list_mode(src, w)
  if mode != 4 {
    @sfpages.archive_kept.landed = false
  }
  // (read now: the rows are made as the list is laid out, after the closed bar's drawing is over)
  let band = band_h(src, w)
  let t = @sf.theme()
  let frame : @sfpages.ListsFrame = {
    ..@sfpages.bare_lists(band, 0.0, side_top_h(), if side_folded() || wide.tape { apart_ground() } else { t.p.sidebar }, mode, Side),
    others: [fn() { decisions_pane(c, src, w) }, fn() { archive_pane(c, src, w) }],
  }
  // under a finger's search (sfpages' search.mbt): the band and the foot away with the lists, the search over them
  let away = @sfpages.search_away(c)
  c.box(style=lists_fill, fn() {
    @sfpages.chats_lists(c, src, w, frame)
    let b = c.layer(fn() { lists_band(c, src, w) })
    // with no bell in the rail: the stations' trouble and the services up long, at the foot (the rail's bell has them
    // where it is: cloud/workspace.tsx WorkspaceSidebarFooter)
    let f = if !rail_items(src, w.id).contains("attention") { c.layer(fn() { lists_foot(c, src, w) }) } else { 0 }
    if away > 0.0 {
      c.look(b, { ..@ui.still_look, alpha: 1.0 - away })
      if f != 0 {
        c.look(f, { ..@ui.still_look, alpha: 1.0 - away })
      }
    }
    @sfpages.chats_search(c, src, w, side_top_h(), Side)
  })
  |> ignore
}

///|
/// The lists' foot band (Sidebar.css.ts navFoot, navFootStatus): what is wrong with the stations (StationTrouble: their
/// glyph and its words, red while one fails, leading to them; beside the rail only then), and 运行中 N (OpenJobsChip:
/// the services left up long, their panel over it). Nothing when neither is, nor with the bell in the rail (they are in
/// its panel).
fn lists_foot(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  // with the bell in the rail, they are in its panel (workspace.tsx WorkspaceSidebarFooter)
  if rail_items(src, w.id).contains("attention") {
    return
  }
  let chats = (src.topic)("chats", { "scope": Json::string(w.id), "mine": Json::boolean(false) }).value
  let trouble = field(chats, "trouble")
  let jobs = long_jobs(src, w)
  if trouble is None && jobs == 0 {
    return
  }
  c.box(style=foot_fill, fn() {
    // (on the sidebar's own ground, whole, as the band over the lists: lists_band)
    let band = c.box(style=foot_band.then(@ui.style(bg=Data(@sf.mix(apart_ground(), wide.band, t.p.sidebar)))), fn() {
      match trouble {
        Some(Object(_)) => {
          let go = c.id("side/station-trouble")
          if c.clicked(go) {
            @sfbase.go_place("stations") |> ignore
          }
          c.box(style=foot_trouble, id=go, fn() {
            @sf.station_glyph(c, stations_at_glance(src, w.id).0, foot_glyph, t.p.text, t.p.red) |> ignore
            c.text(
              text(trouble, "text"),
              style=if text(trouble, "state") == "error" { foot_trouble_red } else { foot_trouble_words },
            )
            |> ignore
          })
          |> ignore
        }
        _ => ()
      }
      if jobs > 0 {
        let chip = c.id("side/open-jobs")
        if c.clicked(chip) {
          wide.jobs_open = !wide.jobs_open
        }
        let b = c.box(style=foot_chip, id=chip, fn() {
          c.box(style=foot_chip_dot, fn() {  }) |> ignore
          c.text(@sf.t("web-main.jobs.chip", args=[("n", jobs.to_string())]), style=foot_chip_words) |> ignore
        })
        c.semantics(b, Button, id=chip, label=@sf.t("web-main.jobs.long"))
        let p = @kit.popover(
          c,
          "side/open-jobs",
          wide.jobs_open,
          chip,
          side=Top,
          along=End,
          offset=6.0,
          // (scrolling in itself past 420, or 60% of the window: openJobsPop; or what the room it has leaves it)
          look=@sf.beside_look(Px(open_jobs_pop_w), most=dmin(open_jobs_pop_most, c.height * 0.6)),
          fn() { open_jobs(c, src, w) },
        )
        wide.jobs_open = p.value
      }
    })
    // over the lists: their scroll bar keeps clear of it (the web's --nav-foot)
    c.floats_over(band)
  })
  |> ignore
}

///|
/// The stations' glyph in the foot's line (Sidebar.css.ts stationTroubleMark: 18).
let foot_glyph : Double = 18.0

///|
// kept across runs: a value (no field of it changes)
let foot_fill : @ui.Style = @ui.css("w=Full h=Full justify=JEnd")

///|
/// 8 in, its line and the chip 6 apart (Sidebar.css.ts navFoot, navFootStatus).
// kept across runs: a value (no field of it changes)
let foot_band : @ui.Style = @ui.css("row w=Full p=S2 gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let foot_trouble : @ui.Style = @ui.css("row w=Full min_h=S8 px=S2_5 gap=S2 align=ACenter hovered{bg=Hover}").then(
  @ui.style(radius=@sf.side_row_radius),
)

///|
// kept across runs: a value (no field of it changes)
let foot_trouble_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let foot_trouble_red : @ui.TextStyle = @ui.text_style(size=Ui, color=Danger, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let foot_chip : @ui.Style = @ui.css("row h=S6 px=S2 gap=S1_5 align=ACenter bg=Hover radius=Full hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let foot_chip_dot : @ui.Style = @ui.css("w=S1_5 h=S1_5 bg=Positive radius=Full")

///|
// kept across runs: a value (no field of it changes)
let foot_chip_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
/// 已归档 as one of the lists (sfpages' archive.mbt, standing in the side column): under the band over the lists, its
/// newest open beside it as it opens.
fn archive_pane(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let key = "side/archive/" + w.id
  let lines = @sfpages.archive_lines(c, src, w, Side, key)
  // opened: its newest chat beside it (ArchivePage)
  let kept = @sfpages.archive_kept
  if app.nav.top() == Archived && !kept.landed && kept.q == "" {
    match items(kept.last, "days").get(0) {
      Some(d) =>
        match items(Some(d), "items").get(0) {
          Some(it) => {
            kept.landed = true
            archive_open(it)
          }
          None => ()
        }
      None => if kept.last is Some(_) { kept.landed = true }
    }
  }
  // (read now: the rows are made as the list is laid out, after the closed bar's drawing is over)
  let band = band_h(src, w)
  c.list(key, lines.length() + 2, 54.0, fn(i) {
    if i == 0 {
      side_space(c, band + 4.0)
    } else if i > lines.length() {
      side_space(c, @sf.list_foot_in(Side))
    } else {
      (lines[i - 1])()
    }
  })
  |> ignore
}

///|
/// An archived chat's page beside the list: over the archive, in place of another's.
fn archive_open(it : Json) -> Unit {
  let v = Some(it)
  let r : ChatRef = {
    station: text(v, "station"),
    session: text(v, "session"),
    title: text(v, "title"),
    station_name: text(v, "place"),
  }
  match app.nav.top() {
    Chat(open) if open.station == r.station && open.session == r.session => ()
    Chat(_) => app.nav.replace(Chat(r))
    _ => app.nav.push(Chat(r))
  }
}

///|
/// The archive open with none of its chats beside it (ArchivePage): what it is.
fn archive_main(c : @ui.Ctx) -> Unit {
  let note = text(@sfpages.archive_kept.last, "note")
  c.box(style=arch_empty, fn() {
    c.text(@sf.t("web-pages.archive.title"), style=arch_empty_title) |> ignore
    if note != "" {
      c.text(note, style=arch_empty_words) |> ignore
    }
    c.text(@sf.t("web-pages.archive.about"), style=arch_empty_words) |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let lists_fill : @ui.Style = @ui.css("w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let arch_empty : @ui.Style = @ui.css("w=Full h=Full px=S10 gap=S2 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let arch_empty_title : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let arch_empty_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, center=true, leading=L6)

///|
/// 待处理 under 新建对话 where the rail has no bell (Attention.tsx AttentionEntry, not the rail's): the bell, its
/// words, how many there are (a small red count, none read since they came); pressed, the panel of them under it.
/// Nothing while there is nothing.
fn side_todo(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let n = todo_all(src, w)
  if !todo_shown(src, w) {
    return
  }
  c.box(style=todo_box, fn() {
    if band_row(c, "side/attention", wide.attention_open, fn() {
        band_mark(c, "bell", t.p.muted)
        band_words(c, @sf.t("web-main.attention.entry"))
        c.box(style=todo_slot, fn() {
          if n > 0 {
            c.box(style=todo_count, fn() { c.text(n.to_string(), style=todo_count_words) |> ignore }) |> ignore
          }
        })
        |> ignore
      }) {
      wide.attention_open = !wide.attention_open
    }
  })
  |> ignore
}

///|
/// 待处理's row in the band: 2 above it, 8 in, 8 under (Sidebar.css.ts navTodo).
// kept across runs: a value (no field of it changes)
let todo_box : @ui.Style = @ui.css("w=Full pt=S0_5 px=S2 pb=S2")

///|
/// Its count's place, as wide as the lists' menu button above it, centred under it.
// kept across runs: a value (no field of it changes)
let todo_slot : @ui.Style = @ui.css("w=S8 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let todo_count : @ui.Style = @ui.css("min_w=S4 h=S4 px=S1 align=ACenter justify=JCenter bg=Danger radius=Full")

///|
// kept across runs: a value (no field of it changes)
let todo_count_words : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, color=OnPrimary, wrap=false)

///|
/// How many are in 待处理 in every workspace (the core's marks' items), less those let go in its panel.
fn todo_all(src : Source, w : Workspace) -> Int {
  attention_groups(src, w, true).fold(init=0, fn(n, g) { n + g.2.length() })
}

///|
/// Whether 待处理 is under 新建对话: no bell in the rail, and something there (or its panel open).
fn todo_shown(src : Source, w : Workspace) -> Bool {
  !rail_items(src, w.id).contains("attention") && (todo_all(src, w) > 0 || wide.attention_open)
}

///|
/// The band's height over the lists: its top row, 新建对话's (6 + a row + 2; in the closed bar 6 + a row + 6), 待处理's
/// when there (2 + a row + 8); a row as high as the theme's band (32; touch's the search field's 38).
fn band_h(src : Source, w : Workspace) -> Double {
  side_top_h() +
  band_new_top +
  band_row_h() +
  side_new_under +
  (if wide.tape && !wide.in_bar { band_new_tape_over() } else { 0.0 }) +
  (if wide.in_bar { bar_band_in - side_new_under } else { 0.0 }) +
  (if todo_shown(src, w) { side_todo_around + band_row_h() } else { 0.0 })
}

///|
/// 新建对话's row's room under it (2), and in the closed bar from its side and under it (6: Sidebar.css.ts navNew, closed).
let side_new_under : Double = 2.0

///|
let bar_band_in : Double = 6.0

///|
/// 待处理's room over and under its row (2 + 8).
let side_todo_around : Double = 10.0
