// The chats' sidebar as the web's lists (ember web/src/Sidebar.tsx ChatList, Sidebar.css.ts navSlider, navTrack;
// pages/Archive.tsx ArchiveRows, ArchivePage; Archive.css.ts): under the band (新建对话 and the filter), one track of
// the lists side by side, 全部, 我参与的, 监控中 and 已归档, slid from one to another as the list shown changes
// (240 ms, ease out); only those in view are drawn. 已归档 is a list of the sidebar's like the others: a field to look
// for one, its days, each archived chat a row (put back or deleted while pointed at), pressed its chat beside the
// list; opened, the newest of them is open beside it, or with none what the archive is.

///|
/// The sidebar `width` wide (its 8 at the left over the rail's empty side), the one the block holds (side_place): the
/// chats' lists (已归档 among them) for the chats' places; the files' (files_nav.mbt); a place's own (the app's:
/// the settings', the stations', the profiles').
fn sidebar(c : @ui.Ctx, src : Source, w : Workspace, width : Double) -> Unit {
  match side_place() {
    "files" => files_nav(c, src, w.id)
    "settings" => settings_side(c, src, w)
    "stations" => stations_side(c, src, w)
    "profiles" => profiles_side(c, src, w)
    // (the chats' lists: made once over the block, side_node.mbt)
    _ => ignore(width)
  }
}

///|
/// The stations' glyph in the foot's line (Sidebar.css.ts stationTroubleMark: 18).
let foot_glyph : Double = 18.0

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
/// An archived chat's page beside the list: over the archive, in place of another's.
fn archive_open(it : Json) -> Unit {
  let v = Some(it)
  let r : ChatRef = {
    station: text(v, "station"),
    session: text(v, "session"),
    title: text(v, "title"),
    station_name: text(v, "place"),
  }
  @sfbase.history_push()
  match app.nav.top() {
    Chat(open) if open.station == r.station && open.session == r.session => ()
    Chat(_) => app.nav.replace(Chat(r))
    _ => app.nav.push(Chat(r))
  }
}

///|
/// Deleted for good, once said so (its 删除, under the pointer or in its menu).
fn archive_delete(src : Source, it : Json) -> Unit {
  let v = Some(it)
  @sf.confirm(
    @sf.t("web-pages.archive.deleteConfirm", args=[("title", text(v, "title"))]),
    @sf.t("web-pages.archive.deleteText"),
    @sf.t("common.delete"),
    danger=true,
    fn() {
      act(
        src,
        @sf.t("common.delete"),
        "",
        "session.delete",
        { "station": Json::string(text(v, "station")), "key": Json::string(text(v, "session")) },
        done=@sf.t("web-pages.archive.deleted"),
      )
    },
  )
}

///|
/// Put back in the list (`chat.archive` with archived false), said once done.
fn archive_restore(src : Source, it : Json) -> Unit {
  let v = Some(it)
  let p : Map[String, Json] = {
    "station": Json::string(text(v, "station")),
    "session": Json::string(text(v, "session")),
    "archived": Json::boolean(false),
  }
  match field(v, "thread") {
    Some(Number(_, ..) as n) => p["thread"] = n
    _ => ()
  }
  act(src, @sf.t("web-pages.archive.restore"), "", "chat.archive", Json::object(p), done=@sf.t("web-pages.archive.restored"))
}

///|
/// Whether an archived chat's putting back or deleting is under way (the core's `doing`).
fn archive_doing(src : Source, station : String, session : String) -> Bool {
  for d in items((src.topic)("doing", {}).value, "doing") {
    let call = text(Some(d), "call")
    let p = field(Some(d), "params")
    if text(Some(d), "stage") == "failed" || text(p, "station") != station {
      continue
    }
    if (call == "chat.archive" && text(p, "session") == session) || (call == "session.delete" && text(p, "key") == session) {
      return true
    }
  }
  false
}

///|
/// The archive open with none of its chats beside it (ArchivePage): what it is.
fn archive_main(c : @ui.Ctx) -> Unit {
  let note = text(archive_side.last, "note")
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
let arch_field : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter bg=Hover radius=Xl")

///|
// kept across runs: a value (no field of it changes)
let arch_clock : @ui.TextStyle = @ui.text_style(size=Caption, color=Subtle, leading=L5, wrap=false)

///|
/// Their marks (14; turning, 12).
let arch_icon : Double = 14.0

///|
let arch_spin : Double = 12.0

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
    if band_row(c, "side/attention", wide.attention_open.get(), fn() {
        band_mark(c, "bell", t.p.muted)
        band_words(c, @sf.t("web-main.attention.entry"))
        c.box(style=todo_slot, fn() {
          if n > 0 {
            c.box(style=todo_count, fn() { c.text(n.to_string(), style=todo_count_words) |> ignore }) |> ignore
          }
        })
        |> ignore
      }) {
      attention_set(!wide.attention_open.get())
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
  // (待处理 a tab of the system's: rail_native.mbt)
  !@sf.native_on() &&
  !rail_items(src, w.id).contains("attention") && (todo_all(src, w) > 0 || wide.attention_open.get())
}

///|
/// The band's height over the lists: its top row, 新建对话's (6 + a row + 2; in the closed bar 6 + a row + 6), 待处理's
/// when there (2 + a row + 8); a row as high as the theme's band (32; touch's the search field's 38).
fn band_h(src : Source, w : Workspace) -> Double {
  side_top_h() +
  band_row_h() +
  (if wide.tape {
    band_new_top + side_new_under + band_new_tape_over()
  } else {
    band_pane_top() + band_pane_under()
  }) +
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
