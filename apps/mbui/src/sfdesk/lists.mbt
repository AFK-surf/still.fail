// The chats' sidebar as the web's lists (ember web/src/Sidebar.tsx ChatList, Sidebar.css.ts navSlider, navTrack;
// pages/Archive.tsx ArchiveRows, ArchivePage; Archive.css.ts): under the band (新建对话 and the filter), one track of
// the lists side by side, 全部, 我参与的, 监控中, 奏 and 已归档, slid from one to another as the list shown changes
// (240 ms, ease out); only those in view are drawn. 已归档 is a list of the sidebar's like the others: a field to look
// for one, its days, each archived chat a row (put back or deleted while pointed at), pressed its chat beside the
// list; opened, the newest of them is open beside it, or with none what the archive is.

///|
/// The sidebar `width` wide (its 8 at the left over the rail's empty side): the chats' lists (奏 and 已归档 among them)
/// for the chats' places; the files' (files_nav.mbt); a place's own (the app's: the settings', the stations', the profiles').
fn sidebar(c : @ui.Ctx, src : Source, w : Workspace, width : Double) -> Unit {
  match lit_place() {
    "files" => files_nav(c, src, w.id)
    "settings" => settings_side(c, src, w)
    "stations" | "profiles" => place_sidebar(c, src, w)
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
    archive_side.landed = false
  }
  // (read now: the rows are made as the list is laid out, after the closed bar's drawing is over)
  let band = band_h(src, w)
  let t = @sf.theme()
  let frame : @sfpages.ListsFrame = {
    ..@sfpages.bare_lists(band, 0.0, side_top_h(), if side_folded() || wide.tape { closed_ground() } else { t.p.sidebar }, mode),
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
    @sfpages.chats_search(c, src, w, side_top_h())
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
    let band = c.box(style=foot_band.then(@ui.style(bg=Data(@sf.mix(closed_ground(), wide.band, t.p.sidebar)))), fn() {
      match trouble {
        Some(Object(_)) => {
          let go = c.id("side/station-trouble")
          c.cursor(go, Hand)
          if c.clicked(go) {
            rail_go(c, src, w, "stations")
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
        c.cursor(chip, Hand)
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
          look=fn(c, _, body) { @sf.small_panel(c, w=Px(open_jobs_pop_w), body) |> ignore },
          // (scrolling in itself past 420, or 60% of the window: openJobsPop)
          fn() { c.capped("side/open-jobs/list", dmin(open_jobs_pop_most, c.height * 0.6), fn() { open_jobs(c, src, w) }) |> ignore },
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
let foot_trouble : @ui.Style = @ui.css("row w=Full min_h=S8 px=S2_5 gap=S2 align=ACenter radius=Xl hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let foot_trouble_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let foot_trouble_red : @ui.TextStyle = @ui.text_style(size=Sm, color=Danger, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let foot_chip : @ui.Style = @ui.css("row h=S6 px=S2 gap=S1_5 align=ACenter bg=Hover radius=Full hovered{bg=Selected}")

///|
// kept across runs: a value (no field of it changes)
let foot_chip_dot : @ui.Style = @ui.css("w=S1_5 h=S1_5 bg=Positive radius=Full")

///|
// kept across runs: a value (no field of it changes)
let foot_chip_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
/// An archive's line.
priv enum ArchiveLine {
  Top
  Search
  Failing(String)
  Waiting
  Said(String)
  Day(String)
  Row(Json)
}

///|
/// 已归档 as one of the lists (ArchiveRows): what to look for, its days, a row each; the newest open beside it as it
/// opens.
fn archive_pane(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let params : Map[String, Json] = { "scope": Json::string(w.id), "limit": Json::number(archive_side.limit.to_double()) }
  if archive_side.q != "" {
    params["q"] = Json::string(archive_side.q)
  }
  let topic = (src.topic)("archive", params)
  match topic.value {
    Some(_) => archive_side.last = topic.value
    None => ()
  }
  let view = archive_side.last
  let days = items(view, "days")
  let lines : Array[ArchiveLine] = [Top, Search]
  if view is None {
    lines.push(
      match topic.error {
        Some(e) => Failing(text(Some(e), "message"))
        None => Waiting
      },
    )
  } else {
    for e in items(view, "errors") {
      lines.push(Failing(text(Some(e), "text")))
    }
    if days.length() == 0 && text(view, "note") != "" {
      lines.push(Said(text(view, "note")))
    }
    for d in days {
      lines.push(Day(text(Some(d), "label")))
      for it in items(Some(d), "items") {
        lines.push(Row(it))
      }
    }
  }
  // opened: its newest chat beside it (ArchivePage)
  if app.nav.top() == Archived && !archive_side.landed && archive_side.q == "" {
    match days.get(0) {
      Some(d) =>
        match items(Some(d), "items").get(0) {
          Some(it) => {
            archive_side.landed = true
            archive_open(it)
          }
          None => ()
        }
      None => if view is Some(_) { archive_side.landed = true }
    }
  }
  // near its end, the next ones
  match c.list_info("side/archive/" + w.id) {
    Some(info) =>
      if flag(view, "more") && info.last >= info.count - 12 && topic.value is Some(_) && info.count == lines.length() {
        archive_side.limit += archive_side_page
      }
    None => ()
  }
  // (read now: the rows are made as the list is laid out, after the closed bar's drawing is over)
  let band = band_h(src, w)
  c.list("side/archive/" + w.id, lines.length(), 54.0, fn(i) {
    c.box(style=lists_inset, fn() {
      match lines[i] {
        Top => side_space(c, band + 4.0)
        // (its 4 under it, as the web's margins: in a heading's 14 over it, not on top of it)
        Search => archive_search_side(c, i + 1 < lines.length() && lines[i + 1] is (Waiting | Row(_)))
        Failing(words) => side_said(c, words, true)
        Waiting => side_breathing(c)
        Said(words) => side_said(c, words, false)
        Day(label) => @sfpages.list_heading(c, label)
        Row(it) => archive_side_row(c, src, it, i + 1 < lines.length() && lines[i + 1] is Row(_))
      }
    })
    |> ignore
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
/// Looking for one (Archive.css.ts search): a field as tall as a row at the list's top, on the pointer's ground.
fn archive_search_side(c : @ui.Ctx, gap : Bool) -> Unit {
  let t = @sf.theme()
  c.box(style=if gap { arch_field_box } else { arch_field_alone }, fn() {
    c.box(style=arch_field, fn() {
      @sf.icon(c, "search", size=14.0, color=t.p.muted) |> ignore
      let r = c.editor(
        "side/archive-q",
        placeholder=@sf.t("web-pages.archive.search"),
        font_size=13.0,
        max_lines=1,
        plain=true,
        line=20.0,
        color=t.p.text,
        placeholder_color=t.p.subtle,
        caret_color=t.p.accent,
      )
      let q = r.text.trim(chars=" \t\n").to_string()
      if q != archive_side.q {
        archive_side.q = q
        archive_side.limit = archive_side_page
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// An archived chat's row (ArchiveRow): its title (its station's mark at its end, with several), the last thing said
/// under it, when it was archived there while pointed at (how, on hover); over the title's end then, putting it back
/// and deleting it (one under way: turning). Pressed, its chat beside the list.
fn archive_side_row(c : @ui.Ctx, src : Source, it : Json, more : Bool) -> Unit {
  let t = @sf.theme()
  let v = Some(it)
  let station = text(v, "station")
  let session = text(v, "session")
  let title = text(v, "title")
  let key = station + "/" + session
  let id = c.id("side/archived/" + key)
  let back = c.id("side/archived-back/" + key)
  let drop = c.id("side/archived-drop/" + key)
  c.cursor(id, Hand)
  if c.clicked(id) {
    archive_open(it)
  }
  let on = match app.nav.top() {
    Chat(r) => r.station == station && r.session == session
    _ => false
  }
  let busy = archive_doing(src, station, session)
  // (always to a finger, which hovers over nothing: Archive.css.ts actions `hover: none`)
  let over = c.lit(id) || c.lit(back) || c.lit(drop) || busy || @ui.pointing() is Finger
  c.box(style=if more { arch_wrap } else { arch_wrap_last }, fn() {
    c.box(style=arch_row, selected=on, id~, fn() {
      c.box(style=arch_text, fn() {
        c.box(style=if over { arch_head_room } else { arch_head }, fn() {
          c.text(title, style=arch_title) |> ignore
          if @sf.has_station_mark(text(v, "stationEmoji"), text(v, "stationIcon")) {
            c.box(style=@sfpages.kind_slot, fn() {
              @sf.station_mark(c, text(v, "stationEmoji"), text(v, "stationIcon"), 12.0, t.p.muted)
            })
            |> ignore
          }
        })
        |> ignore
        c.box(style=arch_meta, fn() {
          c.text(text(v, "last"), style=arch_last) |> ignore
          // (its clock while pointed at; always to a finger, which hovers over nothing)
          if c.hovered(id) || @ui.pointing() is Finger {
            c.text(text(v, "clock"), style=arch_clock) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    // 恢复 and 删除 over the title's end while pointed at (or one under way), always to a finger
    if over {
      c.layer(fn() {
        c.box(style=arch_actions, fn() {
          c.cursor(back, Hand)
          if c.clicked(back) && !busy {
            archive_restore(src, it)
          }
          let b = c.box(style=arch_action, id=back, fn() {
            if busy {
              @sf.spinner(c, size=12.0) |> ignore
            } else {
              @sf.icon(c, "retry", size=14.0, color=if c.lit(back) { t.p.text } else { t.p.muted }) |> ignore
            }
          })
          c.semantics(b, Button, id=back, label=@sf.t("web-pages.archive.restoreNamed", args=[("title", title)]))
          @sf.tip(c, "side/archived-back-tip/" + key, back, @sf.t("web-pages.archive.restore"))
          if flag(v, "deletable") {
            c.cursor(drop, Hand)
            if c.clicked(drop) && !busy {
              @sf.confirm(
                @sf.t("web-pages.archive.deleteConfirm", args=[("title", title)]),
                @sf.t("web-pages.archive.deleteText"),
                @sf.t("common.delete"),
                danger=true,
                fn() {
                  act(
                    src,
                    @sf.t("common.delete"),
                    "",
                    "session.delete",
                    { "station": Json::string(station), "key": Json::string(session) },
                    done=@sf.t("web-pages.archive.deleted"),
                  )
                },
              )
            }
            let d = c.box(style=arch_action, id=drop, fn() {
              @sf.icon(c, "trash", size=14.0, color=if c.lit(drop) { t.p.red } else { t.p.muted }) |> ignore
            })
            c.semantics(d, Button, id=drop, label=@sf.t("web-pages.archive.deleteNamed", args=[("title", title)]))
          }
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
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
/// A list's lines 8 in from the sidebar's sides (Sidebar.css.ts navScroll).
// kept across runs: a value (no field of it changes)
let lists_inset : @ui.Style = @ui.css("w=Full px=S2")

///|
// kept across runs: a value (no field of it changes)
let arch_field_box : @ui.Style = @ui.css("w=Full pb=S1")

///|
// kept across runs: a value (no field of it changes)
let arch_field_alone : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let arch_field : @ui.Style = @ui.css("row w=Full h=S8 px=S2_5 gap=S2 align=ACenter bg=Hover radius=Xl")

///|
/// A row 2 from the next (Sidebar.css.ts navSessionWrap).
// kept across runs: a value (no field of it changes)
let arch_wrap : @ui.Style = @ui.css("w=Full pb=S0_5")

///|
/// The last of a day's rows: its heading's 14 under it alone.
// kept across runs: a value (no field of it changes)
let arch_wrap_last : @ui.Style = @ui.css("w=Full")

///|
/// A chat's row's shape (Sidebar.css.ts navRow, navSession): 54 high, 10 in, its corner the nav's; the pointer's ground
/// on hover, the selected one's when its chat is beside the list.
// kept across runs: a value (no field of it changes)
let arch_row : @ui.Style = @ui.style(
  row=true,
  w=Full,
  h=@sf.side_row_h,
  px=S2_5,
  align=ACenter,
  radius=Xl,
  hovered=@ui.patch(bg=Hover),
  selected=@ui.patch(bg=Selected),
)

///|
// kept across runs: a value (no field of it changes)
let arch_text : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
/// The title's line, 20 high; pointed at, room at its end for the two buttons (Archive.css.ts head: 52).
// kept across runs: a value (no field of it changes)
let arch_head : @ui.Style = @ui.css("row w=Full h=S5 gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let arch_head_room : @ui.Style = @ui.css("row w=Full h=S5 pr=S12 gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let arch_meta : @ui.Style = @ui.css("row w=Full h=S4_5 gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let arch_title : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, leading=L6, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let arch_last : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, leading=L5, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let arch_clock : @ui.TextStyle = @ui.text_style(size=Xs2, color=Subtle, leading=L5, wrap=false)

///|
/// The buttons, centred on the title line (Archive.css.ts actions: 5 down, 6 in, 2 apart).
// kept across runs: a value (no field of it changes)
let arch_actions : @ui.Style = @ui.css("row w=Full pt=S1_25 pr=S1_5 gap=S0_5 justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let arch_action : @ui.Style = @ui.css("w=S6 h=S6 align=ACenter justify=JCenter radius=Lg hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let arch_empty : @ui.Style = @ui.css("w=Full h=Full px=S10 gap=S2 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let arch_empty_title : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let arch_empty_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, center=true, leading=L6)

///|
/// 待处理 under 新建对话 where the rail has no bell (Attention.tsx AttentionEntry, not the rail's): the bell, its
/// words, how many came since they were looked at (a small red count) or, all looked at, how many there are, quiet;
/// pressed, the panel of them under it. Nothing while there is nothing.
fn side_todo(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) }).value
  let all = todo_all(src, w)
  let n = count(marks, "badge")
  if !todo_shown(src, w) {
    return
  }
  c.box(style=todo_box, fn() {
    if nav_row(c, "side/attention", wide.attention_open, fn() {
        @sf.icon(c, "bell", size=16.0, color=t.p.muted) |> ignore
        nav_words(c, @sf.t("web-main.attention.entry"))
        c.box(style=todo_slot, fn() {
          if n > 0 {
            c.box(style=todo_count, fn() { c.text(n.to_string(), style=todo_count_words) |> ignore }) |> ignore
          } else {
            c.text(all.to_string(), style=todo_quiet) |> ignore
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
let todo_count_words : @ui.TextStyle = @ui.text_style(size=Xs2, weight=Semibold, color=OnPrimary, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let todo_quiet : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// How many want the person in every workspace (the core's marks' items).
fn todo_all(src : Source, w : Workspace) -> Int {
  let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) }).value
  let mut all = 0
  match field(marks, "workspaces") {
    Some(Object(by)) =>
      for _, v in by {
        all += items(Some(v), "items").length()
      }
    _ => ()
  }
  all
}

///|
/// Whether 待处理 is under 新建对话: no bell in the rail, and something there (or its panel open).
fn todo_shown(src : Source, w : Workspace) -> Bool {
  !rail_items(src, w.id).contains("attention") && (todo_all(src, w) > 0 || wide.attention_open)
}

///|
/// The band's height over the lists: its top row, 新建对话's (6 + 32 + 2; in the closed bar 6 + 32 + 6), 待处理's when
/// there (2 + 32 + 8).
fn band_h(src : Source, w : Workspace) -> Double {
  side_top_h() +
  side_new_h +
  (if wide.tape && !wide.in_bar { band_new_tape_over } else { 0.0 }) +
  (if wide.in_bar { bar_band_in - side_new_under } else { 0.0 }) +
  (if todo_shown(src, w) { side_todo_h } else { 0.0 })
}

///|
/// 新建对话's row's room under it (2), and in the closed bar from its side and under it (6: Sidebar.css.ts navNew, closed).
let side_new_under : Double = 2.0

///|
let bar_band_in : Double = 6.0

///|
let side_new_h : Double = 40.0

///|
let side_todo_h : Double = 42.0
