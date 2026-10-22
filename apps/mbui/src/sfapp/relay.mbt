// A chat relayed to a channel (docs/relay.md; ember apps/android chat/screens/Relay.kt), from its sheet (ChatInfo.kt):
// the sheet that picks where. The search (or a pasted Slack message link, which offers that message's thread), the
// workspaces to look in when there are several, the places relayed to before as it opens (all of them asked for or
// searched), the one picked with the note, 「接力到 …」. Done, the sheet goes at once and a toast says where it went.

///|
/// The places as asked (`chat.relayPlaces`), for the chat they are of, and what was chosen in the sheet.
priv struct Relaying {
  /// the thread the places were asked for (-1: none yet)
  mut thread : Double
  /// 0 being read, 1 read, 2 not (`error` says why)
  mut read : Int
  mut connects : Array[Json]
  mut error : String
  /// the workspace looked in (a connect's id), "" all of them
  mut scope : String
  /// all the places shown, not only those relayed to before
  mut all : Bool
  /// the place picked: its connect and the place
  mut picked : (Json, Json)?
}

///|
let relaying : Relaying = {
  thread: -1.0,
  read: 0,
  connects: [],
  error: "",
  scope: "",
  all: false,
  picked: None,
}

///|
/// What is typed to find a place (or a Slack message's link), and the note said with the chat where it goes.
let relay_query : @ui.Field = @ui.Field::new()

///|
let relay_note : @ui.Field = @ui.Field::new()

///|
/// As the sheet was before it was ever opened (app.mbt reset).
fn relay_reset() -> Unit {
  relaying.thread = -1.0
  relaying.read = 0
  relaying.connects = []
  relaying.error = ""
  relaying.scope = ""
  relaying.all = false
  relaying.picked = None
  relay_query.set("")
  relay_note.set("")
}

///|
/// How many places relayed to before are offered as the sheet opens, before 显示全部; with no more than this many places
/// in all, all of them are (Relay.kt RECENT, FEW).
let relay_recent : Int = 5

///|
let relay_few : Int = 8

///|
/// The sheet opened for the chat's `thread`: its places asked for (a tap's: Relay.kt LaunchedEffect(thread)).
fn open_relay(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double) -> Unit {
  relay_reset()
  relaying.thread = thread
  (src.call)("chat.relayPlaces", { "station": Json::string(r.station), "thread": Json::number(thread) }, fn(res) {
    if relaying.thread != thread {
      return
    }
    match res {
      Ok(v) => {
        relaying.connects = items(Some(v), "connects")
        relaying.read = 1
      }
      Err(e) => {
        relaying.error = text(Some(e), "message")
        relaying.read = 2
      }
    }
  })
  open_sheet(c, Relay(r, thread))
}

///|
/// Whether `s` is a link to a Slack message (https://…/archives/<channel>/p<16 digits>): the station finds its
/// workspace among its connects' (Relay.kt SLACK_LINK).
fn slack_link(s : String) -> Bool {
  let rest = if s.has_prefix("https://") {
    s.view(start_offset=8)
  } else if s.has_prefix("http://") {
    s.view(start_offset=7)
  } else {
    return false
  }
  let rest = rest.to_owned()
  match rest.find("/archives/") {
    Some(i) if i > 0 && !rest.view(end_offset=i).contains("/") && !rest.view(end_offset=i).contains(" ") => {
      let after = rest.view(start_offset=i + 10).to_owned()
      let mut k = 0
      while k < after.length() {
        let ch = after.code_unit_at(k).to_int()
        if (ch >= 65 && ch <= 90) || (ch >= 48 && ch <= 57) {
          k = k + 1
        } else {
          break
        }
      }
      if k == 0 || k + 18 > after.length() || after.code_unit_at(k).to_int() != 47 ||
        after.code_unit_at(k + 1).to_int() != 112 {
        return false
      }
      for j in (k + 2)..<(k + 18) {
        let ch = after.code_unit_at(j).to_int()
        if ch < 48 || ch > 57 {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// A connect as people know it: its workspace (Slack) or tenant (Feishu), else its bot's name.
fn relay_workspace(conn : Json) -> String {
  match opt_text(Some(conn), "team") {
    Some(t) if t != "" => t
    _ => text(Some(conn), "name")
  }
}

///|
fn relay_place_name(p : Json) -> String {
  if text(Some(p), "kind") == "channel" {
    (if flag(Some(p), "private") { "🔒 " } else { "" }) + "#" + text(Some(p), "name")
  } else {
    text(Some(p), "name")
  }
}

///|
/// What relaying to a place does: a new thread, a new topic, or the group's conversation taken over.
fn relay_kind_note(p : Json) -> String {
  tr(
    match text(Some(p), "kind") {
      "channel" => "web-main.relay.kind.channel"
      "topics" => "web-main.relay.kind.topics"
      _ => "web-main.relay.kind.group"
    },
  )
}

///|
/// The places offered (Relay.kt arrange): those matching what was typed (starting with it first), relayed to before
/// (latest first), by name; nothing typed, only the recent ones of many unless all were asked for. With whether they
/// are the recent ones, and how many there are in all.
fn relay_arrange(connects : Array[Json], query : String, all : Bool) -> (Array[(Json, Json)], Bool, Int) {
  let q = query.trim(chars=" \n\t").to_owned().to_lower()
  let rows : Array[(Json, Json)] = []
  for conn in connects {
    for p in items(Some(conn), "places") {
      rows.push((conn, p))
    }
  }
  let name = fn(r : (Json, Json)) { text(Some(r.1), "name").to_lower() }
  let used = fn(r : (Json, Json)) {
    match field(Some(r.1), "used") {
      Some(Number(n, ..)) => n
      _ => -1.0
    }
  }
  let shown = rows.filter(fn(r) { q == "" || name(r).contains(q) })
  shown.sort_by(fn(a, b) {
    let sa = if q != "" && name(a).has_prefix(q) { 0 } else { 1 }
    let sb = if q != "" && name(b).has_prefix(q) { 0 } else { 1 }
    if sa != sb {
      sa.compare(sb)
    } else if used(a) != used(b) {
      used(b).compare(used(a))
    } else {
      name(a).compare(name(b))
    }
  })
  let before = shown.filter(fn(r) { used(r) >= 0.0 })
  if q == "" && !all && rows.length() > relay_few && before.length() > 0 {
    (before.iter().take(relay_recent).collect(), true, rows.length())
  } else {
    (shown, false, rows.length())
  }
}

///|
/// The sheet's parts, top to bottom: what it is listed so (a list, as tall as the sheet: its places can be many).
priv enum RelayPart {
  Lead
  Search
  Picked(String, String?, String, Bool)
  Reading
  Failed(String)
  Note(String)
  Scopes
  Recent
  Place(Json, Json, Bool)
  NoRows(String)
  ShowAll(Int)
  Unread(String)
  NoteLabel
  NoteField
  Go(String, Bool)
}

///|
/// The sheet's body, 20 in from its sides (Relay.kt: padding(start = 20.dp, end = 20.dp)), as tall as the sheet.
// kept across runs: a value (no field of it changes)
let relay_body : @ui.Style = @ui.style(w=Full, h=Full, px=S5)

///|
/// A part's height before it is laid out (a place's row, 40).
let relay_row_est : Double = 40.0

///|
/// The sheet's share of the screen (Relay.kt SheetSpec(0.9f)).
let relay_share : Double = 0.9

///|
/// The relay sheet (Relay.kt openRelay): 90% of the screen.
fn relay_sheet(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double) -> Unit {
  let query = relay_query.text()
  let link = if slack_link(query.trim(chars=" \n\t").to_owned()) { Some(query.trim(chars=" \n\t").to_owned()) } else { None }
  let parts : Array[RelayPart] = [Lead]
  let chosen = relaying.picked
  if chosen is None {
    parts.push(Search)
  }
  match (link, chosen) {
    (Some(_), _) => parts.push(Picked("", None, tr("web-main.relay.kind.thread"), false))
    (None, Some((conn, p))) =>
      parts.push(
        Picked(
          relay_place_name(p),
          Some(relay_workspace(conn)),
          relay_kind_note(p) + " · " + tr("web-main.relay.change"),
          true,
        ),
      )
    (None, None) =>
      match relaying.read {
        0 => parts.push(Reading)
        2 => parts.push(Failed(relaying.error))
        _ =>
          if relaying.connects.length() == 0 {
            parts.push(Note(tr("web-main.relay.noConnects")))
          } else {
            let several = relaying.connects.length() > 1
            if several {
              parts.push(Scopes)
            }
            let looked = relaying.connects.filter(fn(conn) { relaying.scope == "" || text(Some(conn), "id") == relaying.scope })
            let (rows, recent, total) = relay_arrange(looked, query, relaying.all)
            if recent {
              parts.push(Recent)
            }
            for row in rows {
              parts.push(Place(row.0, row.1, several && relaying.scope == ""))
            }
            if rows.length() == 0 {
              parts.push(
                NoRows(
                  tr(if query.trim(chars=" \n\t").to_owned() == "" { "web-main.relay.noPlaces" } else { "web-main.relay.noMatch" }),
                ),
              )
            }
            if recent && total > rows.length() {
              parts.push(ShowAll(total))
            }
            for conn in looked {
              match opt_text(Some(conn), "error") {
                Some(e) =>
                  parts.push(
                    Unread(
                      (if several { relay_workspace(conn) + " · " } else { "" }) +
                      fill("web-main.relay.unread", [("error", e)]),
                    ),
                  )
                None => ()
              }
            }
          }
      }
  }
  if chosen is Some(_) || link is Some(_) {
    parts.push(NoteLabel)
    parts.push(NoteField)
  }
  parts.push(
    Go(
      match chosen {
        Some((_, p)) => fill("web-main.relay.goTo", [("place", relay_place_name(p))])
        None => tr("web-main.relay.go")
      },
      link is Some(_) || chosen is Some(_),
    ),
  )
  sheet_frame(c, "relay", c.height * relay_share, fn() {
    sheet_head(c, tr("web-main.relay.title"))
    c.box(style=relay_body, fn() {
      c.list("relay/" + r.station + "/" + thread.to_string(), parts.length(), relay_row_est, fn(i) {
        relay_part(c, src, r, thread, parts[i], link)
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// The relay sheet's parts, 10 apart (Relay.kt openRelay's column).
// kept across runs: a value (no field of it changes)
let relay_part_box : @ui.Style = @ui.style(w=Full, pb=S2_5)

///|
/// Its words of 13: its lead, what it says when it has nothing to show; in red, what went wrong.
// kept across runs: a value (no field of it changes)
let relay_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let relay_words_red : @ui.TextStyle = relay_words.then(@ui.text_style(color=Danger))

///|
/// Its small words (12) in their own room, 8 in and 4 down: 最近接力过, nothing found, a workspace not read.
// kept across runs: a value (no field of it changes)
let relay_small_room : @ui.Style = @ui.style(px=S2, py=S1)

///|
// kept across runs: a value (no field of it changes)
let relay_small : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let relay_small_red : @ui.TextStyle = relay_small.then(@ui.text_style(color=Danger))

///|
/// 正在读取频道…: a spinner before it, 8 apart.
// kept across runs: a value (no field of it changes)
let relay_reading : @ui.Style = @ui.style(row=true, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let relay_reading_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false)

///|
/// The workspaces to look in, 6 apart, 6 over the places.
// kept across runs: a value (no field of it changes)
let relay_scopes : @ui.Style = @ui.style(row=true, gap=S1_5, pb=S1_5)

///|
/// A workspace's chip (ScopeChip): 10 by 5 in, round at its ends (its corner 13 on its 26), its mark 5 before its name;
/// chosen, in ink.
// kept across runs: a value (no field of it changes)
let relay_chip : @ui.Style = @ui.style(row=true, px=S2_5, py=S1_25, gap=S1_25, radius=Full, bg=Neutral, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let relay_chip_on : @ui.Style = relay_chip.then(@ui.style(bg=Fg))

///|
// kept across runs: a value (no field of it changes)
let relay_chip_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let relay_chip_words_on : @ui.TextStyle = relay_chip_words.then(@ui.text_style(color=Bg))

///|
/// 显示全部: in the link's ink, 8 by 6 in, its corner 8, rippled where it is pressed.
// kept across runs: a value (no field of it changes)
let relay_show_all : @ui.Style = @ui.style(px=S2, py=S1_5, radius=Lg)

///|
// kept across runs: a value (no field of it changes)
let relay_show_all_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Link, wrap=false)

///|
/// 开头附一句（可选）, 4 under what is over it.
// kept across runs: a value (no field of it changes)
let relay_note_label : @ui.Style = @ui.style(pt=S1)

///|
/// 接力, the sheet's last, 24 over its foot.
// kept across runs: a value (no field of it changes)
let relay_go_room : @ui.Style = @ui.style(w=Full, pb=S6)

///|
/// A field (Controls.kt Field): on the card's ground, a hairline round it, 14 by 12 in, its corner 12.
// kept across runs: a value (no field of it changes)
let relay_field_box : @ui.Style = @ui.style(w=Full, px=S3_5, py=S3, radius=Xl, bg=Card, border=B1, border_color=Line)

///|
/// A place's row (PlaceRow): 40 high at least, 10 by 8 in, its parts 8 apart, its corner the scale's nearest to
/// Smooth(10.dp) (12); picked, on the accent's ground; rippled where it is pressed (clip(Smooth(10)).clickable).
// kept across runs: a value (no field of it changes)
let relay_place : @ui.Style = @ui.style(
  row=true,
  w=Full,
  min_h=S10,
  px=S2_5,
  py=S2,
  gap=S2,
  radius=Xl,
  align=ACenter,
)

///|
// kept across runs: a value (no field of it changes)
let relay_place_on : @ui.Style = relay_place.then(@ui.style(bg=AccentBg))

///|
// kept across runs: a value (no field of it changes)
let relay_place_name_words : @ui.TextStyle = @ui.text_style(size=Lg, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let relay_place_name_on : @ui.TextStyle = relay_place_name_words.then(@ui.text_style(color=AccentText))

///|
// kept across runs: a value (no field of it changes)
let relay_place_aside : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let relay_place_aside_on : @ui.TextStyle = relay_place_aside.then(@ui.text_style(color=AccentText))

///|
/// A part of the relay sheet (Relay.kt openRelay's column, 10 apart).
fn relay_part(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double, part : RelayPart, link : String?) -> Unit {
  c.box(style=relay_part_box, fn() {
    match part {
      Lead => c.text(tr("web-main.relay.lead"), style=relay_words) |> ignore
      Search => relay_field(c, "relay/search", relay_query, tr("web-main.relay.searchOrLink"))
      Picked(name, where_, note, change) =>
        if relay_place_row(c, "relay/picked", None, if name == "" { tr("web-main.relay.thread") } else { name }, where_, Some(note), true) &&
          change {
          relaying.picked = None
        }
      Reading =>
        c.box(style=relay_reading, fn() {
          @sf.spinner(c, size=14.0) |> ignore
          c.text(tr("web-main.relay.reading"), style=relay_reading_words) |> ignore
        })
        |> ignore
      Failed(e) => c.text(e, style=relay_words_red) |> ignore
      Note(words) => c.text(words, style=relay_words) |> ignore
      Scopes =>
        c.box(style=relay_scopes, fn() {
          if relay_scope_chip(c, "relay/scope/", None, tr("web-main.relay.allWorkspaces"), relaying.scope == "") {
            relaying.scope = ""
          }
          for conn in relaying.connects {
            let id = text(Some(conn), "id")
            if relay_scope_chip(c, "relay/scope/" + id, Some(text(Some(conn), "kind")), relay_workspace(conn), relaying.scope == id) {
              relaying.scope = id
            }
          }
        })
        |> ignore
      Recent =>
        c.box(style=relay_small_room, fn() { c.text(tr("web-main.relay.recent"), style=relay_small) |> ignore }) |> ignore
      Place(conn, p, show_where) =>
        if relay_place_row(
            c,
            "relay/place/" + text(Some(conn), "id") + "/" + text(Some(p), "id"),
            Some(text(Some(conn), "kind")),
            relay_place_name(p),
            if show_where { Some(relay_workspace(conn)) } else { None },
            if text(Some(p), "kind") == "channel" { None } else { Some(relay_kind_note(p)) },
            false,
          ) {
          relaying.picked = Some((conn, p))
        }
      NoRows(words) => c.box(style=relay_small_room, fn() { c.text(words, style=relay_small) |> ignore }) |> ignore
      Unread(words) => c.box(style=relay_small_room, fn() { c.text(words, style=relay_small_red) |> ignore }) |> ignore
      ShowAll(n) => {
        let id = c.id("relay/all")
        if c.clicked(id) {
          relaying.all = true
        }
        c.box(style=relay_show_all, id~, fn() {
          c.text(fill("web-main.relay.showAll", [("count", n.to_string())]), style=relay_show_all_words) |> ignore
          // Relay.kt: clip(Smooth(8)).clickable
          @motion.ripple(c, id, 8.0)
        })
        |> ignore
      }
      NoteLabel =>
        c.box(style=relay_note_label, fn() { c.text(tr("web-main.relay.note"), style=relay_small) |> ignore }) |> ignore
      NoteField => relay_field(c, "relay/note", relay_note, tr("web-main.relay.notePlaceholder"))
      Go(label, enabled) =>
        c.box(style=relay_go_room, fn() {
          if sheet_button(c, "relay/go", label, true, enabled) {
            let to = relaying.picked
            let note = relay_note.text()
            close_sheet(c)
            let p : Map[String, Json] = {
              "station": Json::string(r.station),
              "thread": Json::number(thread),
              "note": Json::string(note),
            }
            match (link, to) {
              (Some(l), _) => p["link"] = Json::string(l)
              (None, Some((conn, place))) => {
                p["connect"] = Json::string(text(Some(conn), "id"))
                p["channel"] = Json::string(text(Some(place), "id"))
              }
              (None, None) => ()
            }
            act(src, tr("web-main.relay.verb"), "", "chat.relay", Json::object(p), ok=fn(v) {
              toast_later(fill("web-main.relay.done", [("place", text(Some(v), "place"))]))
            })
            relay_reset()
          }
        })
        |> ignore
    }
  })
  |> ignore
}

///|
/// A field of the relay sheet (Controls.kt Field): mbui's field in its look, one line, its words 15 on 21.
fn relay_field(c : @ui.Ctx, key : String, field : @ui.Field, placeholder : String) -> Unit {
  @kit.text_field(
    c,
    key,
    placeholder~,
    enter_sends=false,
    size=15.0,
    line=21.0,
    look=fn(c, s, editor) { c.box(id=s.id, style=relay_field_box, editor) |> ignore },
    field~,
  )
  |> ignore
}

///|
/// A workspace to look in (or all of them): its platform's mark and name; chosen, filled (Relay.kt ScopeChip).
fn relay_scope_chip(c : @ui.Ctx, key : String, kind : String?, label : String, on : Bool) -> Bool {
  let id = c.id(key)
  c.box(style=if on { relay_chip_on } else { relay_chip }, id~, fn() {
    match kind {
      Some("slack") => @sf.slack_mark(c, relay_mark_small) |> ignore
      Some(_) => @sf.feishu_mark(c, relay_mark_small) |> ignore
      None => ()
    }
    c.text(label, style=if on { relay_chip_words_on } else { relay_chip_words }) |> ignore
    // Relay.kt ScopeChip: clip(Smooth(13)).clickable
    @motion.ripple(c, id, 13.0)
  })
  |> ignore
  c.clicked(id)
}

///|
/// A platform's mark on a workspace's chip (13), and on a place's row (16).
let relay_mark_small : Double = 13.0

///|
let relay_mark : Double = 16.0

///|
/// A place to pick (Relay.kt PlaceRow): its platform's mark, its name, its workspace (among several), what relaying
/// there does at the row's end; picked, on the accent's ground. True on the frame after a tap.
fn relay_place_row(
  c : @ui.Ctx,
  key : String,
  kind : String?,
  name : String,
  where_ : String?,
  note : String?,
  on : Bool,
) -> Bool {
  let id = c.id(key)
  let aside = if on { relay_place_aside_on } else { relay_place_aside }
  c.box(style=if on { relay_place_on } else { relay_place }, id~, fn() {
    match kind {
      Some("feishu") | Some("lark") => @sf.feishu_mark(c, relay_mark) |> ignore
      _ => @sf.slack_mark(c, relay_mark) |> ignore
    }
    c.text(name, style=if on { relay_place_name_on } else { relay_place_name_words }) |> ignore
    match where_ {
      Some(w) => c.text(w, style=aside) |> ignore
      None => ()
    }
    c.spacer()
    match note {
      Some(n) => c.text(n, style=aside) |> ignore
      None => ()
    }
    // Relay.kt PlaceRow: clip(Smooth(10)).clickable
    @motion.ripple(c, id, 10.0)
  })
  |> ignore
  c.clicked(id)
}
