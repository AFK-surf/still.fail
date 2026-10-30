// The archive (settings/Archive.kt ArchiveScreen, the core's `archive` topic): chats archived by hand or by their
// station once they idled, of every station online in one list, newest first by the day they were archived. Each can
// be opened to read (its composer restores it), put back in the list (`chat.archive` with archived false), and one
// whose agents are done deleted for good (`session.delete`). Only those with the words looked for, and the newest so
// many, more as it is scrolled near its end.

///|
/// How many the archive shows at first, and how many more each time (Topics.ARCHIVE_PAGE).
let archive_page_size : Int = 60

///|
/// What the archive's page keeps while it is on the stack: the words looked for, how many it asks for, the last view
/// read (shown while another is asked for).
priv struct ArchiveState {
  q : @signals.Signal[String]
  limit : @signals.Signal[Int]
  last : @signals.Signal[Json?]
}

///|
let archive_state : ArchiveState = {
  q: @signals.signal("", same=fn(a, b) { a == b }),
  limit: @signals.signal(archive_page_size, same=fn(a, b) { a == b }),
  last: @signals.signal(None, same=fn(a, b) { a == b }),
}

///|
/// The archive as it was left: no words looked for, the first page (the page pushed again).
fn archive_reset() -> Unit {
  archive_state.q.set("")
  archive_state.limit.set(archive_page_size)
  archive_state.last.set(None)
}

///|
priv enum ArchiveEntry {
  Room(Double)
  Search
  Wait(Json?, String)
  Error(String)
  Note(String)
  Empty
  Day(String)
  Item(Json)
}

///|
fn archive_page(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let params : Map[String, Json] = { "scope": str(here.workspace) }
  if archive_state.q.get() != "" {
    params["q"] = str(archive_state.q.get())
  }
  params["limit"] = Json::number(archive_state.limit.get().to_double())
  let topic = (core.topic)("archive", params)
  match topic.value {
    Some(_) => archive_state.last.set(topic.value)
    None => ()
  }
  let view = archive_state.last.get()
  // under the app's top bar at the bar's top, from under it, scrolling under it (Archive.kt: contentPadding top)
  let top = top_room()
  let entries : Array[ArchiveEntry] = if top > 0.0 { [Room(top), Search] } else { [Search] }
  let days = items(view, "days")
  let wait = field(view, "wait")
  if view is None || (days.length() == 0 && note_waits(wait)) {
    entries.push(
      Wait(
        wait,
        match (view, topic.error) {
          (None, Some(e)) => error_text(e)
          _ => ""
        },
      ),
    )
  } else {
    for e in items(view, "errors") {
      entries.push(Error(text(Some(e), "text")))
    }
    match opt_text(view, "note") {
      Some(n) => entries.push(Note(n))
      None => ()
    }
    if days.length() == 0 && archive_state.q.get() == "" {
      entries.push(Empty)
    }
    for d in days {
      entries.push(Day(text(Some(d), "label")))
      for it in items(Some(d), "items") {
        entries.push(Item(it))
      }
    }
  }
  // a screen or so before its end, the next ones
  // (read back by whether it is near its end alone: not built again as it scrolls)
  match c.list_info_as("settings/archive", fn(i) { i.map(fn(i) { (i.last >= i.count - 12, i.count) }) }) {
    Some(info) =>
      if flag(view, "more") &&
        info.last >= info.count - 12 &&
        topic.value is Some(_) &&
        info.count == entries.length() {
        archive_state.limit.set(archive_state.limit.get() + archive_page_size)
      }
    None => ()
  }
  place_page(c, core, tr("android-misc.bar.place.archive"), back=tr("android-misc.bar.place.chats"), fn() {
    c.list("settings/archive", entries.length(), 54.0, fn(i) {
      match entries[i] {
        Room(h) => gap(c, h)
        Search => archive_search(c)
        Wait(note, error) =>
          waiting_rows(
            c,
            fn() {
              section_header(c, @sf.sample_words(2))
              for i, n in [(7, 4), (10, 5), (6, 4), (12, 6), (8, 4), (9, 5), (5, 4)] {
                archive_row(c, core.quiet(), {
                  "station": "sample",
                  "session": Json::string("sample" + i.to_string()),
                  "title": Json::string(@sf.sample_words(n.0)),
                  "place": Json::string(@sf.sample_words(n.1)),
                  "clock": Json::string(@sf.sample_words(3)),
                })
              }
            },
            error~,
            failing=failing_of(note),
          )
        Error(e) => {
          let t = @sf.theme()
          c.box(w=Fill(1.0), padx=20.0, pady=8.0, fn() {
            c.text(e, size=t.t.meta, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
          })
          |> ignore
        }
        Note(n) => {
          let t = @sf.theme()
          c.box(w=Fill(1.0), padx=20.0, pady=12.0, fn() {
            c.text(n, size=t.t.meta, color=t.p.muted, w=Fill(1.0), line=20.0) |> ignore
          })
          |> ignore
        }
        Empty => place_empty(c, tr("android-misc.archive.note"))
        Day(label) => section_header(c, label)
        Item(it) => archive_row(c, core, it)
      }
    })
    |> ignore
  })
}

///|
/// Looking for one by its title or last line (ArchiveSearch): the chats' search field, over the list.
fn archive_search(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), pl=16.0, pr=16.0, pt=4.0, pb=8.0, fn() {
    c.box(
      dir=Row,
      w=Fill(1.0),
      h=Px(38.0),
      radius=19.0,
      bg=@sf.alpha(t.p.text, 0.06),
      padx=12.0,
      gap=8.0,
      align=ACenter,
      fn() {
        @sf.icon(c, "search", size=17.0, color=t.p.muted) |> ignore
        let r = c.editor(
          "archive-q",
          placeholder=tr("web-pages.archive.search"),
          font_size=16.0,
          max_lines=1,
          plain=true,
          line=22.0,
          color=t.p.text,
          placeholder_color=t.p.muted,
          caret_color=t.p.accent,
        )
        let q = r.text.trim(chars=" \t\n").to_owned()
        if q != archive_state.q.get() {
          archive_state.q.set(q)
          archive_state.limit.set(archive_page_size)
        }
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// An archived chat (ArchiveRow): its title, when (and where) at its line's end, then 还原 and 删除; its last
/// message the line under it. Tapped, its chat (read there, restored from its composer).
fn archive_row(c : @ui.Ctx, core : Core, it : Json) -> Unit {
  let t = @sf.theme()
  let v = Some(it)
  let station = text(v, "station")
  let session = text(v, "session")
  let title = text(v, "title")
  let busy = is_doing(core, ["chat.archive"], [("station", station), ("session", session)]) ||
    is_doing(core, ["session.delete"], [("station", station), ("key", session)])
  let failed = match failed_of(core, ["chat.archive"], [("station", station), ("session", session)]) {
    Some(f) => Some(f)
    None => failed_of(core, ["session.delete"], [("station", station), ("key", session)])
  }
  let id = c.id("archived/" + station + "/" + session)
  let mut acted = false
  c.box(
    w=Fill(1.0),
    pl=20.0,
    pr=10.0,
    pt=6.0,
    pb=6.0,
    id~,
    fn() {
      c.box(dir=Row, w=Fill(1.0), h=Px(34.0), gap=10.0, align=ACenter, fn() {
        c.text(title, size=t.t.ui, color=t.p.text, wrap=false, w=Fill(1.0), line=22.0) |> ignore
        // (read as how it was archived: ArchiveRow's contentDescription = item.how)
        c.box(label=text(v, "how"), fn() {
          c.text(join([text(v, "place"), text(v, "clock")], "  "), size=t.t.caption, color=t.p.subtle, wrap=false)
          |> ignore
        })
        |> ignore
        if busy {
          c.box(w=Px(34.0), h=Px(34.0), align=ACenter, justify=JCenter, fn() { spinner(c) }) |> ignore
        } else {
          // (恢复 and 删除 as far apart as makes each a press's room across: @sf.keys_row)
          c.box(style=@sf.keys_row(size=round_action_side), fn() {
            if failed is Some(_) {
              c.box(w=Px(34.0), h=Px(34.0), align=ACenter, justify=JCenter, fn() {
                doing_mark(c, false, failed)
              })
              |> ignore
            }
            if round_action(c, "restore/" + session, "retry", label=fill("android-misc.archive.restoreNamed", [("title", title)])) {
              acted = true
              let p : Map[String, Json] = {
                "station": str(station),
                "session": str(session),
                "archived": Json::boolean(false),
              }
              match field(v, "thread") {
                Some(Number(_, ..) as n) => p["thread"] = n
                _ => ()
              }
              act(
                core,
                tr("android-misc.archive.restoreWhat"),
                "chat.archive",
                Json::object(p),
                done=tr("android-misc.archive.restored"),
              )
            }
            if flag(v, "deletable") && round_action(c, "delete/" + session, "trash", label=fill("android-misc.archive.deleteNamed", [("title", title)])) {
              acted = true
              confirm(
                fill("android-misc.archive.deleteTitle", [("title", title)]),
                tr("android-misc.archive.deleteText"),
                tr("common.delete"),
                danger=true,
                fn() {
                  act(
                    core,
                    tr("android-misc.archive.deleteWhat"),
                    "session.delete",
                    obj([("station", str(station)), ("key", str(session))]),
                    done=tr("android-misc.archive.deleted"),
                  )
                },
              )
            }
          })
          |> ignore
        }
      })
      |> ignore
      c.box(w=Fill(1.0), pr=10.0, fn() {
        c.text(text(v, "last"), size=t.t.meta, color=t.p.muted, wrap=false, w=Fill(1.0), line=20.0) |> ignore
      })
      |> ignore
      // Archive.kt Row: clickable over the whole row
      @motion.ripple(c, id, 0.0)
    },
  )
  |> ignore
  if hit(c, id) && !acted {
    (core.open_chat)(station, session, title)
  }
}

///|
let round_action_side : Double = 34.0

///|
/// A round action of a row (Archive.kt Action): its icon, 16 in a 34 circle. True on the frame after a tap.
fn round_action(c : @ui.Ctx, key : String, icon : String, label? : String = "") -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  let b = c.box(
    w=Px(34.0),
    h=Px(34.0),
    radius=17.0,
    align=ACenter,
    justify=JCenter,
    id~,
    fn() {
      @sf.icon(c, icon, size=16.0, color=t.p.muted) |> ignore
      // Archive.kt Action: clip(CircleShape).clickable
      @motion.ripple(c, id, 17.0)
    },
  )
  // what it says to a screen reader (Archive.kt Action: its contentDescription)
  c.semantics(b, Button, id~, label~)
  hit(c, id)
}
