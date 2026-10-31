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
    _ => lists_side(c, src, w, width)
  }
}

///|
/// The chats' sidebar `width` wide: the band over the lists (sfpages' chats_lists: 全部, 我参与的, 监控中, then
/// 已归档 on its track).
fn lists_side(c : @ui.Ctx, src : Source, w : Workspace, width : Double) -> Unit {
  ignore(width)
  let mode = list_mode(src, w)
  if mode != 3 {
    archive_side.landed = false
  }
  // (read now: the rows are made as the list is laid out, after the closed bar's drawing is over)
  let band = band_h(src, w)
  let t = @sf.theme()
  let frame : @sfpages.ListsFrame = {
    ..@sfpages.bare_lists(band, 0.0, side_top_h(), if side_folded() || wide.tape { apart_ground() } else { t.p.sidebar }, mode, Side),
    others: [fn() { archive_pane(c, src, w) }],
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
          wide.jobs_open.set(!wide.jobs_open.get())
        }
        let b = c.box(style=foot_chip, id=chip, fn() {
          c.box(style=foot_chip_dot, fn() {  }) |> ignore
          c.text(@sf.t("web-main.jobs.chip", args=[("n", jobs.to_string())]), style=foot_chip_words) |> ignore
        })
        c.semantics(b, Button, id=chip, label=@sf.t("web-main.jobs.long"))
        let p = @kit.popover(
          c,
          "side/open-jobs",
          wide.jobs_open.get(),
          chip,
          side=Top,
          along=End,
          offset=6.0,
          // (scrolling in itself past 420, or 60% of the window: openJobsPop; or what the room it has leaves it)
          look=@sf.beside_look(Px(open_jobs_pop_w), most=dmin(open_jobs_pop_most, c.height * 0.6)),
          fn() { open_jobs(c, src, w) },
        )
        wide.jobs_open.set(p.value)
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
/// An archive's line.
priv enum ArchiveLine {
  Top
  Search
  Failing(String)
  Waiting
  Said(String)
  Day(String)
  Row(Json)
  Foot
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
  lines.push(Foot)
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
  // (read back by whether it is near its end alone: not built again as it scrolls)
  match c.list_info_as("side/archive/" + w.id, fn(i) { i.map(fn(i) { (i.last >= i.count - 12, i.count) }) }) {
    Some(info) =>
      if flag(view, "more") && info.last >= info.count - 12 && topic.value is Some(_) && info.count == lines.length() {
        archive_side.limit += archive_side_page
      }
    None => ()
  }
  // (read now: the rows are made as the list is laid out, after the closed bar's drawing is over)
  let band = band_h(src, w)
  c.list("side/archive/" + w.id, lines.length(), 54.0, fn(i) {
    c.box(style=@sf.list_line(Side), fn() {
      match lines[i] {
        Top => side_space(c, band + 4.0)
        // (its 4 under it, as the web's margins: in a heading's 14 over it, not on top of it)
        Search => archive_search_side(c, i + 1 < lines.length() && lines[i + 1] is (Waiting | Row(_)))
        Failing(words) => side_said(c, words, true)
        Waiting => @sf.waiting(c, fn() { archive_sample(c) })
        Said(words) => side_said(c, words, false)
        Day(label) => @sf.list_heading(c, label, Side)
        Row(it) => archive_side_row(c, src, it, i + 1 < lines.length() && lines[i + 1] is Row(_))
        Foot => side_space(c, @sf.list_foot_in(Side))
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
  @sfbase.history_push()
  match app.nav.top() {
    Chat(open) if open.station == r.station && open.session == r.session => ()
    Chat(_) => app.nav.replace(Chat(r))
    _ => app.nav.push(Chat(r))
  }
}

///|
/// Looking for one (Archive.css.ts search): a field at the list's top on the pointer's ground, as what stands over a
/// sidebar's list is (the theme's band's: its height, its words' room, its mark, its words).
fn archive_search_side(c : @ui.Ctx, gap : Bool) -> Unit {
  let t = @sf.theme()
  let l = t.chat_list
  let (size, line) = c.text_size(Ui)
  c.box(style=if gap { arch_field_box } else { arch_field_alone }, fn() {
    c.box(style=arch_field.then(@ui.style(h=Fixed(l.band_h), px=@sf.room_of(l.band_pad))), fn() {
      @sf.icon(c, "search", size=l.band_icon, color=t.p.muted) |> ignore
      let r = c.editor(
        "side/archive-q",
        placeholder=@sf.t("web-pages.archive.search"),
        font_size=size,
        max_lines=1,
        plain=true,
        line~,
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
  if c.clicked(id) {
    archive_open(it)
    @sfbase.show_chosen()
  }
  let on = match app.nav.top() {
    Chat(r) => r.station == station && r.session == session
    _ => false
  }
  let busy = archive_doing(src, station, session)
  // its 恢复 and 删除 while pointed at (shown only under the hand), or one under way; where the native input is touch
  // they are held for (its menu), as a chat's row's 归档 is: no keys drawn too small for a finger (@sf.more_held)
  let over = busy || (!@sf.more_held() && c.hand_lit(c.lit(id) || c.lit(back) || c.lit(drop)))
  // right clicked, or held long by a finger (Ctx::menu_asked): 恢复 and 删除
  match c.menu_asked(id) {
    Some((x, y)) if !busy => archive_menu(c, src, it, id, x, y)
    _ => ()
  }
  let l = @sf.theme().chat_list
  c.box(style=if more { @sf.list_more(Side) } else { @sfpages.row_last }, fn() {
    // (the library's list row, a chat's as high as its rows are: @sf.list_row)
    @sf.list_row(
      c,
      id,
      Side,
      nav_ground(c, "side/archived/" + key, c.lit(id) || c.pressed(id), on),
      high=true,
      // (恢复 and 删除 over its first line's end)
      end_room=if over { @sf.row_keys_room(if flag(v, "deletable") { 2 } else { 1 }) } else { 0.0 },
      fn() {
        @sf.name_words(c, title, l.title) |> ignore
        if @sf.has_station_mark(text(v, "stationEmoji"), text(v, "stationIcon")) {
          // (where it was, on hover: Archive.tsx's tip)
          let kind = c.id("side/archived-kind/" + key)
          c.box(style=@sfpages.kind_slot, id=kind, taps=false, points=true, fn() {
            @sf.station_mark(c, text(v, "stationEmoji"), text(v, "stationIcon"), @sfpages.kind_mark_of(text(v, "stationIcon")), t.p.muted)
          })
          |> ignore
          @sf.tip(c, "side/archived-kind-tip/" + key, kind, text(v, "place"))
        }
      },
      fn() {
        c.box(style=l.meta, fn() {
          @sf.name_words(c, text(v, "last"), l.last) |> ignore
          // (its clock while pointed at; always to a finger, which hovers over nothing; how it was archived over it)
          if @sf.pointed_or_finger(c, c.hovered(id)) {
            let clock = c.id("side/archived-clock/" + key)
            c.box(id=clock, taps=false, points=true, fn() { c.text(text(v, "clock"), style=arch_clock) |> ignore }) |> ignore
            @sf.tip(c, "side/archived-clock-tip/" + key, clock, text(v, "how"))
          }
        })
        |> ignore
      },
    )
    |> ignore
    // 恢复 and 删除 at its top right while pointed at (or one under way), always to a finger (concentric with its
    // corner: @sf.row_corner_keys)
    if over {
      @sf.row_corner_keys(c, fn() { archive_actions(c, src, it, back, drop, busy) })
    }
  })
  |> ignore
}

///|
/// The archive's rows to come while it is read (the library's Waiting, in its bones): made-up chats' rows, as
/// archive_side_row draws them.
fn archive_sample(c : @ui.Ctx) -> Unit {
  let rows = [(7, 13), (10, 9), (6, 15), (12, 11), (8, 14), (9, 10)]
  for i, n in rows {
    let it : Json = {
      "station": "sample",
      "session": Json::string("sample" + i.to_string()),
      "title": Json::string(@sf.sample_words(n.0)),
      "last": Json::string(@sf.sample_words(n.1)),
      "clock": Json::string(@sf.sample_words(3)),
    }
    archive_side_row(c, @sfbase.sample_source, it, i + 1 < rows.length())
  }
}

///|
/// An archived chat's 恢复 and 删除 (Archive.css.ts actions: 2 apart, @sf.row_key_box); one under way: turning.
fn archive_actions(c : @ui.Ctx, src : Source, it : Json, back : Int, drop : Int, busy : Bool) -> Unit {
  let t = @sf.theme()
  let v = Some(it)
  let station = text(v, "station")
  let session = text(v, "session")
  let title = text(v, "title")
  let key = station + "/" + session
  if !busy && c.clicked(back) {
    archive_restore(src, it)
  }
  let b = c.box(style=@sf.row_key_box, id=back, fn() {
    if busy {
      @sf.spinner(c, size=arch_spin) |> ignore
    } else {
      @sf.icon(c, "retry", size=arch_icon, color=if c.lit(back) { t.p.text } else { t.p.muted }) |> ignore
    }
  })
  c.semantics(b, Button, id=back, label=@sf.t("web-pages.archive.restoreNamed", args=[("title", title)]))
  @sf.tip(c, "side/archived-back-tip/" + key, back, @sf.t("web-pages.archive.restore"))
  if flag(v, "deletable") {
    if !busy && c.clicked(drop) {
      archive_delete(src, it)
    }
    let d = c.box(style=@sf.row_key_box, id=drop, fn() {
      @sf.icon(c, "trash", size=arch_icon, color=if c.lit(drop) { t.p.red } else { t.p.muted }) |> ignore
    })
    c.semantics(d, Button, id=drop, label=@sf.t("web-pages.archive.deleteNamed", args=[("title", title)]))
    @sf.tip(c, "side/archived-drop-tip/" + key, drop, @sf.t("common.delete"))
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
/// Its menu, right clicked or held (its 恢复 and 删除 as its keys under the pointer: archive_actions); held by a finger,
/// from the row.
fn archive_menu(c : @ui.Ctx, src : Source, it : Json, id : Int, x : Double, y : Double) -> Unit {
  let held = @sf.menu_held(c, "archived")
  let items : Array[@sf.MenuItem?] = [
    Some(@sf.menu_item_of(@sf.t("web-pages.archive.restore"), icon="retry", fn() { archive_restore(src, it) })),
  ]
  if flag(Some(it), "deletable") {
    items.push(Some(@sf.menu_item_of(@sf.t("common.delete"), icon="trash", danger=true, fn() { archive_delete(src, it) })))
  }
  @sf.menu(items, from=if held { Of(id) } else { @sf.at_point(x, y) }, title=text(Some(it), "title"))
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
let arch_field_box : @ui.Style = @ui.css("w=Full pb=S1")

///|
// kept across runs: a value (no field of it changes)
let arch_field_alone : @ui.Style = @ui.css("w=Full")

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
