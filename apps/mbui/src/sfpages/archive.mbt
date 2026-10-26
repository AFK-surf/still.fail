// 已归档 (web Archive.tsx ArchiveRows, mobile/Archive.tsx; the core's `archive` topic): the chats archived by hand or by
// their station once they idled, of every station online in one list, newest first by the day they were archived;
// what to look for over them, more as it is scrolled near its end. A row its chat's title, its station's mark with
// several, the last thing said under it, when and how it was archived; 恢复 (`chat.archive`, archived false) and 删除
// (`session.delete`, one whose agents are done) at its top right, under the pointer or always to a finger; pressed,
// its chat. One list wherever it stands (`at`): a side column's beside its chats (the shell's sidebar), or across the
// whole page (its page of its own).

///|
/// The archive's list as it is looked at: the words looked for, how many asked for, the last read (shown while
/// another is asked for); whether the newest was opened beside it since the archive was opened (the shell's).
pub(all) struct ArchiveKept {
  mut q : String
  mut limit : Int
  mut last : Json?
  mut landed : Bool
}

///|
// kept across runs: what the archive was left at; archive_reset empties it
pub let archive_kept : ArchiveKept = { q: "", limit: archive_more, last: None, landed: false }

///|
/// How many the archive's list shows at first, and how many more each time it is scrolled near its end (Archive.tsx
/// ARCHIVE_PAGE).
pub let archive_more : Int = 60

///|
/// As at the start: nothing looked for, the first so many, nothing read, nothing opened beside it.
pub fn archive_reset() -> Unit {
  archive_kept.q = ""
  archive_kept.limit = archive_more
  archive_kept.last = None
  archive_kept.landed = false
}

///|
/// An archive's line.
priv enum ArchiveLine {
  Search
  Failing(String)
  Waiting
  Said(String)
  Day(String)
  Row(Json)
}

///|
/// The archive's lines standing `at` (what to look for, what went wrong, its days and their rows), each a line of the
/// list `list` the frame draws them in (as it is scrolled near its end, the next ones asked for).
pub fn archive_lines(c : @ui.Ctx, src : Source, w : Workspace, at : @sf.ListAt, list : String) -> Array[() -> Unit] {
  let params : Map[String, Json] = { "scope": Json::string(w.id), "limit": Json::number(archive_kept.limit.to_double()) }
  if archive_kept.q != "" {
    params["q"] = Json::string(archive_kept.q)
  }
  let topic = (src.topic)("archive", params)
  match topic.value {
    Some(_) => archive_kept.last = topic.value
    None => ()
  }
  let view = archive_kept.last
  let days = items(view, "days")
  let lines : Array[ArchiveLine] = [Search]
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
    if days.length() == 0 {
      // (the core's words for why there is none; none looked for and none said, what the archive is)
      let note = text(view, "note")
      if note != "" {
        lines.push(Said(note))
      } else if archive_kept.q == "" {
        lines.push(Said(@sf.t("android-misc.archive.note")))
      }
    }
    for d in days {
      lines.push(Day(text(Some(d), "label")))
      for it in items(Some(d), "items") {
        lines.push(Row(it))
      }
    }
  }
  // near its end, the next ones
  match c.list_info(list) {
    Some(info) =>
      if flag(view, "more") && info.last >= info.count - 12 && topic.value is Some(_) {
        archive_kept.limit += archive_more
      }
    None => ()
  }
  lines.mapi(fn(i, line) {
    let next = lines.get(i + 1)
    fn() {
      c.box(style=@sf.list_line(at), fn() {
        match line {
          // (its 4 under it, as the web's margins: in a heading's 14 over it, not on top of it)
          Search => archive_search(c, at, next is Some(Waiting | Row(_)))
          Failing(words) => archive_said(c, words, true, at)
          Waiting => @sf.waiting(c, dense=true, count=6)
          Said(words) => archive_said(c, words, false, at)
          Day(label) => @sf.list_heading(c, label, at)
          Row(it) => archived_row(c, src, it, next is Some(Row(_)), at)
        }
      })
      |> ignore
    }
  })
}

///|
/// Looking for one (Archive.css.ts search): a field at the list's top on the pointer's ground, as what stands over the
/// list is (the theme's band's: its height, its words' room, its mark, its words); across the whole page, as far in as
/// a side column's line is.
fn archive_search(c : @ui.Ctx, at : @sf.ListAt, gap : Bool) -> Unit {
  let t = @sf.theme()
  let l = t.chat_list
  let (size, line) = c.text_size(Ui)
  let room = match at {
    Side => if gap { arch_field_box } else { arch_field_alone }
    Whole => (if gap { arch_field_box } else { arch_field_alone }).then(@ui.style(px=@sf.room_of(l.band_in)))
  }
  c.box(style=room, fn() {
    c.box(style=arch_field.then(@ui.style(h=Fixed(l.band_h), px=@sf.room_of(l.band_pad))), fn() {
      @sf.icon(c, "search", size=l.band_icon, color=t.p.muted) |> ignore
      let r = c.editor(
        "archive-q",
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
      if q != archive_kept.q {
        archive_kept.q = q
        archive_kept.limit = archive_more
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// What the list says in place of its rows (Sidebar.css.ts navEmpty): muted, or in red what went wrong; as far in as
/// its headings.
fn archive_said(c : @ui.Ctx, words : String, bad : Bool, at : @sf.ListAt) -> Unit {
  c.box(style=arch_said_box.then(@sf.list_heading_in(at)), fn() {
    c.text(words, style=if bad { arch_said_bad } else { arch_said_words }) |> ignore
  })
  |> ignore
}

///|
/// An archived chat's row (ArchiveRow): its title (its station's mark at its end, with several), the last thing said
/// under it, when it was archived there while pointed at (how, on hover); over the title's end then, putting it back
/// and deleting it (one under way: turning). Pressed, its chat.
fn archived_row(c : @ui.Ctx, src : Source, it : Json, more : Bool, at : @sf.ListAt) -> Unit {
  let t = @sf.theme()
  let v = Some(it)
  let station = text(v, "station")
  let session = text(v, "session")
  let title = text(v, "title")
  let key = station + "/" + session
  let id = c.id("archived/" + key)
  let back = c.id("archived-back/" + key)
  let drop = c.id("archived-drop/" + key)
  if c.clicked(id) {
    open_page(Chat({ station, session, title, station_name: text(v, "place") }))
  }
  let on = match app.nav.top() {
    Chat(r) => r.station == station && r.session == session
    _ => false
  }
  let busy = archive_doing(src, station, session)
  // across the whole page (a phone's: mobile/Archive.tsx Row), when and its keys at its first line's end, a finger's
  // size; in a side column, over its first line's end while pointed at (always to a finger, which hovers over nothing:
  // Archive.css.ts actions `hover: none`)
  let whole = at == Whole
  let over = !whole && @sf.pointed_or_finger(c, c.lit(id) || c.lit(back) || c.lit(drop) || busy)
  let l = t.chat_list
  c.box(style=if more { @sf.list_more(at) } else { row_last }, fn() {
    // (the library's list row, a chat's as high as its rows are: @sf.list_row)
    @sf.list_row(
      c,
      id,
      at,
      @sf.nav_ground(c, "archived/" + key, c.lit(id) || c.pressed(id), on),
      high=true,
      // (恢复 and 删除 over its first line's end)
      end_room=if over {
        @sf.row_keys_room(if flag(v, "deletable") { 2 } else { 1 })
      } else {
        0.0
      },
      fn() {
        @sf.name_words(c, title, l.title) |> ignore
        if @sf.has_station_mark(text(v, "stationEmoji"), text(v, "stationIcon")) {
          // (where it was, on hover: Archive.tsx's tip)
          let kind = c.id("archived-kind/" + key)
          c.box(style=kind_slot, id=kind, taps=false, points=true, fn() {
            @sf.station_mark(c, text(v, "stationEmoji"), text(v, "stationIcon"), kind_mark, t.p.muted)
          })
          |> ignore
          @sf.tip(c, "archived-kind-tip/" + key, kind, text(v, "place"))
        }
        if whole {
          c.box(label=text(v, "how"), fn() { c.text(text(v, "clock"), style=row_time) |> ignore }) |> ignore
          // (their room at the line's end, a key's each; they stand over the row, as a side column's do: pressed, theirs,
          // not the row's)
          for _ in 0..<(if flag(v, "deletable") { 2 } else { 1 }) {
            c.box(style=arch_key_room, fn() {  }) |> ignore
          }
          c.layer(fn() { c.box(style=arch_keys_whole, fn() { archived_actions(c, src, it, back, drop, busy, arch_key_whole) }) |> ignore })
          |> ignore
        }
      },
      fn() {
        c.box(style=l.meta, fn() {
          @sf.name_words(c, text(v, "last"), l.last) |> ignore
          // (its clock while pointed at; always to a finger, which hovers over nothing; how it was archived over it)
          if !whole && @sf.pointed_or_finger(c, c.hovered(id)) {
            let clock = c.id("archived-clock/" + key)
            c.box(id=clock, taps=false, points=true, fn() { c.text(text(v, "clock"), style=arch_clock) |> ignore }) |> ignore
            @sf.tip(c, "archived-clock-tip/" + key, clock, text(v, "how"))
          }
        })
        |> ignore
      },
    )
    |> ignore
    // 恢复 and 删除 at its top right while pointed at (or one under way), always to a finger (concentric with its
    // corner: @sf.row_corner_keys)
    if over {
      @sf.row_corner_keys(c, fn() { archived_actions(c, src, it, back, drop, busy, @sf.row_key_box) })
    }
  })
  |> ignore
}

///|
/// An archived chat's 恢复 and 删除 (Archive.css.ts actions: 2 apart, @sf.row_key_box); one under way: turning.
fn archived_actions(c : @ui.Ctx, src : Source, it : Json, back : Int, drop : Int, busy : Bool, key_box : @ui.Style) -> Unit {
  let t = @sf.theme()
  let v = Some(it)
  let station = text(v, "station")
  let session = text(v, "session")
  let title = text(v, "title")
  let key = station + "/" + session
  if !busy && c.clicked(back) {
    archive_restore(src, it)
  }
  let b = c.box(style=key_box, id=back, fn() {
    if busy {
      @sf.spinner(c, size=arch_spin) |> ignore
    } else {
      @sf.icon(c, "retry", size=arch_icon, color=if c.lit(back) { t.p.text } else { t.p.muted }) |> ignore
    }
  })
  c.semantics(b, Button, id=back, label=@sf.t("web-pages.archive.restoreNamed", args=[("title", title)]))
  @sf.tip(c, "archived-back-tip/" + key, back, @sf.t("web-pages.archive.restore"))
  if flag(v, "deletable") {
    if !busy && c.clicked(drop) {
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
    let d = c.box(style=key_box, id=drop, fn() {
      @sf.icon(c, "trash", size=arch_icon, color=if c.lit(drop) { t.p.red } else { t.p.muted }) |> ignore
    })
    c.semantics(d, Button, id=drop, label=@sf.t("web-pages.archive.deleteNamed", args=[("title", title)]))
    @sf.tip(c, "archived-drop-tip/" + key, drop, @sf.t("common.delete"))
  }
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
/// The archive as a page of its own (a small screen's, from the filter's menu): its list across the page, its title
/// over it, back to the chats.
pub fn archive_page(c : @ui.Ctx, src : Source, w : Workspace, frame : PageFrame, on_back : () -> Unit) -> Unit {
  let key = "archive"
  @sf.page(c, on_back~, frame~, key, @sf.t("android-misc.bar.place.archive"), archive_lines(c, src, w, Whole, @sf.page_list(key)), listed=true)
}

// ── styles (Archive.css.ts) ─────────────────────────────────────────────

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
/// Across the whole page, the keys at its first line's end (mArchiveActions: no room between them) and each a finger's
/// 32 round (mArchiveAction's 34, on the ladder's step), the pointer's ground on it.
// kept across runs: a value (no field of it changes)
let arch_keys_whole : @ui.Style = @ui.css("row w=Full h=Full align=ACenter justify=JEnd")

///|
/// A key's room on the line it stands over (arch_key_whole's width).
// kept across runs: a value (no field of it changes)
let arch_key_room : @ui.Style = @ui.css("w=S8")

///|
// kept across runs: a value (no field of it changes)
let arch_key_whole : @ui.Style = @ui.css("w=S8 h=S8 radius=Full align=ACenter justify=JCenter hovered{bg=Hover}")

///|
/// What the list says in place of its rows (Sidebar.css.ts navEmpty: 16 over and under, 13 on 20, muted; navError red).
// kept across runs: a value (no field of it changes)
let arch_said_box : @ui.Style = @ui.css("w=Full py=S4")

///|
// kept across runs: a value (no field of it changes)
let arch_said_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L6)

///|
// kept across runs: a value (no field of it changes)
let arch_said_bad : @ui.TextStyle = @ui.text_style(size=Ui, color=Danger, leading=L6)
