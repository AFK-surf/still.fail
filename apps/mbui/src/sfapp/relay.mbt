// A chat relayed to a channel (docs/relay.md; ember apps/android chat/screens/Relay.kt), from its sheet (ChatInfo.kt):
// the sheet that picks where; what it offers, and in what order, is the core's (sfbase relay.mbt, relay-pick.ts). The bot to go on through when there are several (the chat's own as it opens), the search
// (or a pasted Slack message link, which offers that message's thread), its places relayed to before as it opens (all of them asked for or
// searched), the one picked with the note, 「接力到 …」. Done, the sheet goes at once and a toast says where it went.

///|
/// The sheet opened for the chat's `thread`: its places asked for (sfbase relay.mbt).
fn open_relay(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double) -> Unit {
  relay_open(src, r.station, thread)
  open_sheet(c, Relay(r, thread))
}

///|
/// The kind of a row's connect, for its mark ("slack", "feishu", "lark").
fn relay_kind(row : Json) -> String {
  text(Some(row), "kind")
}

///|
/// The sheet's parts, top to bottom: what it is listed so (a list, as tall as the sheet: its places can be many).
priv enum RelayPart {
  Lead
  Search
  /// the place picked: its name, note, whether it can be changed, and the bot replying there (the words saying so,
  /// U+E000 where its name goes, and its connect)
  Picked(String, String, Bool, (String, Json)?)
  Reading
  Failed(String)
  Note(String)
  Bots(Array[Json], String)
  Recent
  /// a place offered: a row of the core's view
  Place(Json)
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
let relay_body : @ui.Style = @ui.css("w=Full h=Full px=S5")

///|
/// A part's height before it is laid out (a place's row, 40).
let relay_row_est : Double = 40.0

///|
/// The sheet's share of the screen (Relay.kt SheetSpec(0.9f)).
let relay_share : Double = 0.9

///|
/// The relay sheet (Relay.kt openRelay): 90% of the screen.
fn relay_sheet(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double) -> Unit {
  let view = relay_view(c, src)
  let link = opt_text(view, "link")
  let parts : Array[RelayPart] = [Lead]
  let chosen = relaying.picked
  let via = fn(id : String) {
    relay_connect(id).map(fn(conn) { (fill("web-main.relay.via", [("bot", "\u{E000}")]), conn) })
  }
  let bots = items(view, "bots")
  if bots.length() > 0 && chosen is None && link is None {
    parts.push(Bots(bots, text(view, "bot")))
  }
  if chosen is None {
    parts.push(Search)
  }
  match (link, chosen) {
    (Some(_), _) => parts.push(Picked("", tr("web-main.relay.kind.thread"), false, via(text(view, "bot"))))
    (None, Some(row)) =>
      parts.push(
        Picked(text(Some(row), "name"), text(Some(row), "note") + " · " + tr("web-main.relay.change"), true, via(text(Some(row), "connect"))),
      )
    (None, None) =>
      match relaying.read {
        0 => parts.push(Reading)
        2 => parts.push(Failed(relaying.error))
        _ if relaying.connects.length() == 0 => parts.push(Note(tr("web-main.relay.noConnects")))
        _ =>
          match view {
            None => parts.push(Reading)
            Some(_) => {
              let rows = items(view, "rows")
              let recent = flag(view, "recent")
              if recent {
                parts.push(Recent)
              }
              for row in rows {
                parts.push(Place(row))
              }
              match text(view, "empty") {
                "noPlaces" => parts.push(NoRows(tr("web-main.relay.noPlaces")))
                "noMatch" => parts.push(NoRows(tr("web-main.relay.noMatch")))
                _ => ()
              }
              let total = number(view, "total").to_int()
              if recent && total > rows.length() {
                parts.push(ShowAll(total))
              }
              for e in items(view, "unread") {
                match e {
                  String(e) => parts.push(Unread(fill("web-main.relay.unread", [("error", e)])))
                  _ => ()
                }
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
        Some(row) => fill("web-main.relay.goTo", [("place", text(Some(row), "name"))])
        None => tr("web-main.relay.go")
      },
      link is Some(_) || chosen is Some(_),
    ),
  )
  sheet_frame(c, "relay", c.height * relay_share, fn() {
    sheet_head(c, tr("web-main.relay.title"))
    c.box(style=relay_body, fn() {
      c.list("relay/" + r.station + "/" + thread.to_string(), parts.length(), relay_row_est, fn(i) {
        relay_part(c, src, parts[i], view)
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// The relay sheet's parts, 10 apart (Relay.kt openRelay's column).
// kept across runs: a value (no field of it changes)
let relay_part_box : @ui.Style = @ui.css("w=Full pb=S2_5")

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
let relay_small_room : @ui.Style = @ui.css("px=S2 py=S1")

///|
// kept across runs: a value (no field of it changes)
let relay_small : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let relay_small_red : @ui.TextStyle = relay_small.then(@ui.text_style(color=Danger))

///|
/// 正在读取频道…: a spinner before it, 8 apart.
// kept across runs: a value (no field of it changes)
let relay_reading : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let relay_reading_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false)

///|
/// The bots to go on through, 6 apart.
// kept across runs: a value (no field of it changes)
let relay_scopes : @ui.Style = @ui.css("row gap=S1_5 pb=S1_5")

///|
/// A bot's chip (BotChip): 10 by 5 in, round at its ends (its corner 13 on its 26), its picture 5 before its name;
/// chosen, in ink.
// kept across runs: a value (no field of it changes)
let relay_chip : @ui.Style = @ui.css("row px=S2_5 py=S1_25 gap=S1_25 radius=Full bg=Neutral align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let relay_chip_on : @ui.Style = relay_chip.then(@ui.css("bg=Fg"))

///|
// kept across runs: a value (no field of it changes)
let relay_chip_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let relay_chip_words_on : @ui.TextStyle = relay_chip_words.then(@ui.text_style(color=Bg))

///|
/// 显示全部: in the link's ink, 8 by 6 in, its corner 8, rippled where it is pressed.
// kept across runs: a value (no field of it changes)
let relay_show_all : @ui.Style = @ui.css("px=S2 py=S1_5 radius=Lg")

///|
// kept across runs: a value (no field of it changes)
let relay_show_all_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Link, wrap=false)

///|
/// 开头附一句（可选）, 4 under what is over it.
// kept across runs: a value (no field of it changes)
let relay_note_label : @ui.Style = @ui.css("pt=S1")

///|
/// 接力, the sheet's last, 24 over its foot.
// kept across runs: a value (no field of it changes)
let relay_go_room : @ui.Style = @ui.css("w=Full pb=S6")

///|
/// A field (Controls.kt Field): on the card's ground, a hairline round it, 14 by 12 in, its corner 12.
// kept across runs: a value (no field of it changes)
let relay_field_box : @ui.Style = @ui.css("w=Full px=S3_5 py=S3 radius=Xl bg=Card border=B1 border_color=Line")

///|
/// A place's row (PlaceRow): 40 high at least, 10 by 8 in, its parts 8 apart, its corner the scale's nearest to
/// Smooth(10.dp) (12); picked, on the accent's ground; rippled where it is pressed (clip(Smooth(10)).clickable).
// kept across runs: a value (no field of it changes)
let relay_place : @ui.Style = @ui.css("row w=Full min_h=S10 px=S2_5 py=S2 gap=S2 radius=Xl align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let relay_place_on : @ui.Style = relay_place.then(@ui.css("bg=AccentBg"))

///|
/// Which bot the agent speaks through there, under the place picked (Relay.kt): in line with the place's name (the
/// row's 10 in, its mark's 16 and the 8 after it), the bot's picture before its name.
// kept across runs: a value (no field of it changes)
let relay_via : @ui.Style = @ui.css("row w=Full px=S2_5 pt=S0_5 align=ACenter")

///|
/// As wide as the row's mark and the 8 after it.
// kept across runs: a value (no field of it changes)
let relay_via_indent : @ui.Style = @ui.css("w=S6")

///|
// kept across runs: a value (no field of it changes)
let relay_via_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let relay_via_bot : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

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
fn relay_part(c : @ui.Ctx, src : Source, part : RelayPart, view : Json?) -> Unit {
  c.box(style=relay_part_box, fn() {
    match part {
      Lead => c.text(tr("web-main.relay.lead"), style=relay_words) |> ignore
      Search => relay_field(c, "relay/search", relaying.query, tr("web-main.relay.searchOrLink"))
      Picked(name, note, change, via) => {
        if relay_place_row(c, "relay/picked", None, if name == "" { tr("web-main.relay.thread") } else { name }, Some(note), true) &&
          change {
          relaying.picked = None
        }
        if via is Some((words, conn)) {
          let split = words.split("\u{E000}").map(fn(w) { w.to_owned() }).collect()
          c.box(style=relay_via, fn() {
            c.box(style=relay_via_indent, fn() {  }) |> ignore
            c.text(split[0], style=relay_via_words) |> ignore
            relay_bot_picture(c, src, conn)
            c.text(" " + text(Some(conn), "name"), style=relay_via_bot) |> ignore
            if split.length() > 1 {
              c.text(split[1], style=relay_via_words) |> ignore
            }
          })
          |> ignore
        }
      }
      Reading =>
        c.box(style=relay_reading, fn() {
          @sf.spinner(c, size=14.0) |> ignore
          c.text(tr("web-main.relay.reading"), style=relay_reading_words) |> ignore
        })
        |> ignore
      Failed(e) => c.text(e, style=relay_words_red) |> ignore
      Note(words) => c.text(words, style=relay_words) |> ignore
      Bots(bots, on) =>
        c.box(style=relay_scopes, fn() {
          for b in bots {
            let id = text(Some(b), "id")
            if relay_bot_chip(c, src, id, text(Some(b), "label"), id == on) {
              relaying.bot = id
              relaying.all = false
            }
          }
        })
        |> ignore
      Recent =>
        c.box(style=relay_small_room, fn() { c.text(tr("web-main.relay.recent"), style=relay_small) |> ignore }) |> ignore
      Place(row) =>
        if relay_place_row(
            c,
            "relay/place/" + text(Some(row), "connect") + "/" + text(field(Some(row), "place"), "id"),
            Some(relay_kind(row)),
            text(Some(row), "name"),
            opt_text(Some(row), "aside"),
            false,
          ) {
          relaying.picked = Some(row)
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
      NoteField => relay_field(c, "relay/note", relaying.note, tr("web-main.relay.notePlaceholder"))
      Go(label, enabled) =>
        c.box(style=relay_go_room, fn() {
          if sheet_button(c, "relay/go", label, true, enabled) {
            close_sheet(c)
            relay_go(src, view)
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
/// A bot to go on through: its picture and name; chosen, filled (Relay.kt BotChip).
fn relay_bot_chip(c : @ui.Ctx, src : Source, bot : String, label : String, on : Bool) -> Bool {
  let id = c.id("relay/bot/" + bot)
  c.box(style=if on { relay_chip_on } else { relay_chip }, id~, fn() {
    match relay_connect(bot) {
      Some(conn) => relay_bot_picture(c, src, conn)
      None => ()
    }
    c.text(label, style=if on { relay_chip_words_on } else { relay_chip_words }) |> ignore
    // Relay.kt BotChip: clip(Smooth(13)).clickable
    @motion.ripple(c, id, 13.0)
  })
  |> ignore
  c.clicked(id)
}

///|
/// A bot's picture, 16 across (Relay.kt BotPicture); its platform's mark until the platform said it.
fn relay_bot_picture(c : @ui.Ctx, src : Source, conn : Json) -> Unit {
  match opt_text(Some(conn), "botImage") {
    Some(picture) if picture != "" => avatar(c, src, text(Some(conn), "id"), text(Some(conn), "name"), picture, relay_mark)
    _ =>
      match text(Some(conn), "kind") {
        "feishu" | "lark" => @sf.feishu_mark(c, relay_mark) |> ignore
        _ => @sf.slack_mark(c, relay_mark) |> ignore
      }
  }
}

///|
/// A platform's mark, and a bot's picture, on a place's row and a bot's chip (16).
let relay_mark : Double = 16.0

///|
/// A place to pick (Relay.kt PlaceRow): its platform's mark, its name, what relaying there does at the row's end;
/// picked, on the accent's ground. True on the frame after a tap.
fn relay_place_row(
  c : @ui.Ctx,
  key : String,
  kind : String?,
  name : String,
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
