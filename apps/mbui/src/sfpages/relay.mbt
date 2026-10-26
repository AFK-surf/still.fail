// A chat relayed to a channel (docs/relay.md; web/src/Relay.tsx useRelay, RelayDialog, and the phone's RelaySheet in
// mobile/Chat.tsx; Relay.css.ts), one on every screen: from a chat's row's menu, its title bar's panel or its info, the
// picking opens through the presenters (a dialog with 取消 and 接力 at its foot, a sheet from the foot with touch
// short of Large). It offers the channels and groups one of the station's connects' bots is in (the chat's own bot as
// it opens, another picked above), those relayed to before first, found by typing; one picked, with a note if wanted,
// 接力 has the station start the conversation there and the chat's agent go on in it too, and the panel goes with a
// toast saying where. A Slack message's link typed (pasted) into the search offers that message's thread instead. What
// it offers, and in what order, is the core's (sfbase relay.mbt, relay-pick.ts). The search takes the focus as it opens
// with keyboard and mouse, not with touch (where that would bring the keyboard up over the list: useRelay's `focus`).

///|
/// The editor to be given the focus as it is next drawn (the search as it opens, the note once a place is picked:
/// their autoFocus), "" none.
let relay_focus : Ref[String] = Ref("")

///|
/// As at the start (the package's reset).
fn relay_focus_reset() -> Unit {
  relay_focus.val = ""
}

///|
/// Relays chat `thread` of `r`'s station: its places asked for (sfbase relay.mbt), the picking presented from `from`.
pub fn open_relay(src : Source, r : ChatRef, thread : Double, from~ : @sf.Anchor) -> Unit {
  relay_open(src, r.station, thread)
  relay_focus.val = if @sf.native_input() is Finger { "" } else { "relay/search" }
  @sf.panel(
    @sf.t("web-main.relay.title"),
    fn(c, _) {
      let view = relay_view(c, src)
      relay_body(c, src, view, opt_text(view, "link"), relaying.picked)
    },
    from~,
    description=@sf.t("web-main.relay.lead"),
    live=fn() { (@sf.t("web-main.relay.title"), "", @sf.t("web-main.relay.lead")) },
    foot=fn(c, close) {
      let view = relay_view(c, src)
      let picked = relaying.picked
      let ready = picked is Some(_) || opt_text(view, "link") is Some(_)
      let label = match picked {
        Some(row) => @sf.t("web-main.relay.goTo", args=[("place", text(Some(row), "name"))])
        None => @sf.t("web-main.relay.go")
      }
      if @sf.button(c, @sf.t("common.cancel"), key="relay/cancel", tone=Ghost) {
        close()
      }
      if @sf.button(c, label, key="relay/go", tone=Primary, busy=relaying.busy, disabled=!ready) {
        relay_go(src, view, done=close)
      }
    },
    gone=fn() {
      if !relaying.busy {
        relay_reset()
      }
    },
  )
}

///|
/// Editor `key` given the focus as it is drawn where it is asked to be (autoFocus: in the dialog, whose ids its are).
fn relay_focused(c : @ui.Ctx, key : String) -> Unit {
  if relay_focus.val == key {
    if c.has_focus(c.id(key)) {
      relay_focus.val = ""
    } else {
      c.focus_editor(key)
    }
  }
}

///|
/// The dialog's search, its places, then the note (Relay.css.ts body: one column, 12 apart).
fn relay_body(c : @ui.Ctx, src : Source, view : Json?, link : String?, picked : Json?) -> Unit {
  c.box(style=relay_column, fn() {
    // the bots to go on through, when there are several (scopes)
    let bots = items(view, "bots")
    if bots.length() > 0 && picked is None && link is None {
      let on = text(view, "bot")
      c.box(style=relay_scopes, fn() {
        for b in bots {
          let id = text(Some(b), "id")
          if relay_scope(c, src, id, text(Some(b), "label"), id == on) {
            relaying.bot = id
            relaying.all = false
          }
        }
      })
      |> ignore
    }
    if picked is None {
      @sf.input(c, "relay/search", placeholder=@sf.t("web-main.relay.searchOrLink"), field=relaying.query) |> ignore
      relay_focused(c, "relay/search")
    }
    match (link, picked) {
      (Some(_), _) =>
        relay_list(c, fn() {
          relay_place(c, "relay/thread", "slack", @sf.t("web-main.relay.thread"), Some(@sf.t("web-main.relay.kind.thread")), true, false)
          |> ignore
          relay_via(c, src, text(view, "bot"))
        })
      (None, Some(row)) =>
        relay_list(c, fn() {
          if relay_place(c, "relay/picked", text(Some(row), "kind"), text(Some(row), "name"), Some(text(Some(row), "note")), true, true) {
            relaying.picked = None
            relay_focus.val = "relay/search"
          }
          relay_via(c, src, text(Some(row), "connect"))
        })
      (None, None) =>
        match relaying.read {
          0 => @sf.wait_line(c, @sf.t("web-main.relay.reading"), key="relay/reading")
          2 => c.text(relaying.error, style=relay_failed) |> ignore
          _ if relaying.connects.length() == 0 => relay_said(c, @sf.t("web-main.relay.noConnects"), relay_empty)
          _ =>
            match view {
              None => @sf.wait_line(c, @sf.t("web-main.relay.reading"), key="relay/reading")
              Some(_) => relay_places(c, view)
            }
        }
    }
    if picked is Some(_) || link is Some(_) {
      c.box(style=relay_note_field, fn() {
        c.text(@sf.t("web-main.relay.note"), style=relay_note_label) |> ignore
        @sf.input(c, "relay/note", placeholder=@sf.t("web-main.relay.notePlaceholder"), field=relaying.note) |> ignore
        relay_focused(c, "relay/note")
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The places of the bot gone on through as the core offers them (list): 最近接力过 over those relayed to before,
/// why none are, 显示全部 under the recent ones, the connects whose places were not read.
fn relay_places(c : @ui.Ctx, view : Json?) -> Unit {
  let rows = items(view, "rows")
  let recent = flag(view, "recent")
  relay_list(c, fn() {
    if recent {
      c.box(style=relay_group_head_box, fn() { c.text(@sf.t("web-main.relay.recent"), style=relay_group_head) |> ignore })
      |> ignore
    }
    for row in rows {
      let key = "relay/place/" + text(Some(row), "connect") + "/" + text(field(Some(row), "place"), "id")
      if relay_place(c, key, text(Some(row), "kind"), text(Some(row), "name"), opt_text(Some(row), "aside"), false, false) {
        relaying.picked = Some(row)
        relay_focus.val = "relay/note"
      }
    }
    match text(view, "empty") {
      "noPlaces" => relay_said(c, @sf.t("web-main.relay.noPlaces"), relay_empty)
      "noMatch" => relay_said(c, @sf.t("web-main.relay.noMatch"), relay_empty)
      _ => ()
    }
    let total = number(view, "total").to_int()
    if recent && total > rows.length() {
      let id = c.id("relay/all")
      if c.clicked(id) {
        relaying.all = true
      }
      let label = @sf.t("web-main.relay.showAll", args=[("count", total.to_string())])
      let b = c.box(style=relay_more, id~, fn() { c.text(label, style=relay_more_words) |> ignore })
      c.semantics(b, Button, id~, label~)
    }
    for e in items(view, "unread") {
      match e {
        String(e) => relay_said(c, @sf.t("web-main.relay.unread", args=[("error", e)]), relay_unread)
        _ => ()
      }
    }
  })
}

///|
/// Why none, why not read (empty, unread), 4 by 8 in.
fn relay_said(c : @ui.Ctx, words : String, style : @ui.TextStyle) -> Unit {
  c.box(style=relay_note_box, fn() { c.text(words, style~) |> ignore }) |> ignore
}

///|
/// The places, scrolling within the dialog past 300 (list: 2 apart).
fn relay_list(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.capped("relay/list", relay_list_most, fn() { c.box(style=relay_list_box, body) |> ignore }) |> ignore
}

///|
/// A place to pick (place): its platform's mark, its name, what relaying there does at its end (`note`, with 更换 after
/// it where `change`); picked (`on`), on the accent's ground. True on the frame after a press.
fn relay_place(c : @ui.Ctx, key : String, kind : String, name : String, note : String?, on : Bool, change : Bool) -> Bool {
  let id = c.id(key)
  let b = c.box(style=if on { relay_place_on } else { relay_place_box }, id~, fn() {
    relay_mark(c, kind)
    c.text(name, style=if on { relay_place_name_on } else { relay_place_name }) |> ignore
    c.box(style=relay_grow, fn() {  }) |> ignore
    match note {
      Some(n) =>
        c.rich(
          if change {
            [@ui.span(n + " · "), @ui.span(@sf.t("web-main.relay.change"), weight=relay_change_weight)]
          } else {
            [@ui.span(n)]
          },
          style=if on { relay_place_note_on } else { relay_place_note },
        )
        |> ignore
      None => ()
    }
  })
  c.semantics(b, Button, id~, label=name)
  c.clicked(id)
}

///|
/// A platform's mark (ElsewhereLogo, 16): Feishu's for Feishu and Lark, else Slack's.
fn relay_mark(c : @ui.Ctx, kind : String) -> Unit {
  match kind {
    "feishu" | "lark" => @sf.feishu_mark(c, relay_mark_size) |> ignore
    _ => @sf.slack_mark(c, relay_mark_size) |> ignore
  }
}

///|
/// A connect's bot as people see it (ConnectAvatar, 16): its picture; its kind's mark (three fifths of it) till that
/// is said.
fn relay_avatar(c : @ui.Ctx, src : Source, conn : Json) -> Unit {
  match opt_text(Some(conn), "botImage") {
    Some(picture) if picture != "" =>
      @sf.avatar(c, text(Some(conn), "id"), text(Some(conn), "name"), (src.picture)(picture, c.page_stint()), relay_mark_size)
    _ =>
      c.box(style=relay_avatar_box, fn() {
        match text(Some(conn), "kind") {
          "feishu" | "lark" => @sf.feishu_mark(c, relay_kind_size) |> ignore
          _ => @sf.slack_mark(c, relay_kind_size) |> ignore
        }
      })
      |> ignore
  }
}

///|
/// A bot to go on through (scope): its picture and name; the one gone on through filled. True on the frame after a
/// press.
fn relay_scope(c : @ui.Ctx, src : Source, bot : String, label : String, on : Bool) -> Bool {
  let id = c.id("relay/bot/" + bot)
  let lit = !on && c.lit(id)
  let b = c.box(style=if on { relay_scope_on } else { relay_scope_box }, id~, fn() {
    match relay_connect(bot) {
      Some(conn) => relay_avatar(c, src, conn)
      None => ()
    }
    c.text(label, style=if on { relay_scope_name_on } else if lit { relay_scope_name_lit } else { relay_scope_name }) |> ignore
  })
  c.semantics(b, Button, id~, label~, selected=on)
  c.clicked(id)
}

///|
/// Which bot the agent speaks through there, under the place picked (Via): 「那里由 [picture] Claude 回复」, in line
/// with the place's name.
fn relay_via(c : @ui.Ctx, src : Source, bot : String) -> Unit {
  let conn = match relay_connect(bot) {
    Some(conn) => conn
    None => return
  }
  let words = @sf.t("web-main.relay.via", args=[("bot", "\u{E000}")])
  let split : Array[String] = words.split("\u{E000}").map(fn(w) { w.to_owned() }).collect()
  c.box(style=relay_via_box, fn() {
    c.box(style=relay_via_indent, fn() {  }) |> ignore
    c.text(split[0], style=relay_via_words) |> ignore
    c.box(style=relay_via_bot, fn() {
      relay_avatar(c, src, conn)
      c.text(text(Some(conn), "name"), style=relay_via_name) |> ignore
    })
    |> ignore
    if split.length() > 1 {
      c.text(split[1], style=relay_via_words) |> ignore
    }
  })
  |> ignore
}

///|
/// The places' most before they scroll (list: maxHeight 300); a mark and a bot's picture (16), its kind's mark in it
/// (three fifths: ConnectKindIcon).
let relay_list_most : Double = 300.0

///|
let relay_mark_size : Double = 16.0

///|
let relay_kind_size : Double = 10.0

///|
/// A bot's chip's height (scope: 26), a place's least (place: 34).
let relay_scope_h : Double = 26.0

///|
let relay_place_h : Double = 34.0

///|
/// 更换 on the place picked (change: 500).
let relay_change_weight : Int = 500

///|
/// One column, 12 apart (body).
// kept across runs: a value (no field of it changes)
let relay_column : @ui.Style = @ui.css("w=Full gap=S3")

///|
/// The places, 2 apart (list).
// kept across runs: a value (no field of it changes)
let relay_list_box : @ui.Style = @ui.css("w=Full gap=SPx")

///|
/// 最近接力过 (groupHead: 2 by 8 in, the meta's size, muted).
// kept across runs: a value (no field of it changes)
let relay_group_head_box : @ui.Style = @ui.css("px=S2 py=S0_5")

///|
// kept across runs: a value (no field of it changes)
let relay_group_head : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
/// The bots, 6 apart, wrapping (scopes).
// kept across runs: a value (no field of it changes)
let relay_scopes : @ui.Style = @ui.css("row w=Full gap=S1_5")

///|
/// A bot's chip (scope): 26 high, 10 in, its picture 5 before its name, round at its ends, on the text's 6%; the one
/// gone on through on the text.
// kept across runs: a value (no field of it changes)
let relay_scope_box : @ui.Style = @ui.css("row px=S2_5 gap=S1_25 radius=Full bg=Tint align=ACenter").then(
  @ui.style(h=Fixed(relay_scope_h)),
)

///|
// kept across runs: a value (no field of it changes)
let relay_scope_on : @ui.Style = relay_scope_box.then(@ui.css("bg=Fg"))

///|
/// Its name (scopeName): muted, the text's pointed at, the canvas's on the text.
// kept across runs: a value (no field of it changes)
let relay_scope_name : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let relay_scope_name_lit : @ui.TextStyle = relay_scope_name.then(@ui.text_style(color=Fg))

///|
// kept across runs: a value (no field of it changes)
let relay_scope_name_on : @ui.TextStyle = relay_scope_name.then(@ui.text_style(color=Bg))

///|
/// A place (place): 34 high at least, 6 by 10 in, its parts 8 apart, an option's corner; the hover grey pointed at,
/// picked on the accent's ground.
// kept across runs: a value (no field of it changes)
let relay_place_box : @ui.Style = @ui.css("row w=Full px=S2_5 py=S1_5 gap=S2 radius=Xl align=ACenter hovered{bg=Hover}").then(
  @ui.style(min_h=Fixed(relay_place_h)),
)

///|
// kept across runs: a value (no field of it changes)
let relay_place_on : @ui.Style = relay_place_box.then(@ui.css("bg=AccentBg hovered{bg=AccentBg}"))

///|
// kept across runs: a value (no field of it changes)
let relay_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
/// Its name (placeName: the ui's size, cut short with an ellipsis), the accent's text picked.
// kept across runs: a value (no field of it changes)
let relay_place_name : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, max_lines=1)

///|
// kept across runs: a value (no field of it changes)
let relay_place_name_on : @ui.TextStyle = relay_place_name.then(@ui.text_style(color=AccentText))

///|
/// What relaying there does (placeNote: the meta's size, muted; the accent's text picked).
// kept across runs: a value (no field of it changes)
let relay_place_note : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let relay_place_note_on : @ui.TextStyle = relay_place_note.then(@ui.text_style(color=AccentText))

///|
/// 显示全部 (more: 4 by 8 in, the accent's text, the meta's size).
// kept across runs: a value (no field of it changes)
let relay_more : @ui.Style = @ui.css("px=S2 py=S1")

///|
// kept across runs: a value (no field of it changes)
let relay_more_words : @ui.TextStyle = @ui.text_style(size=Meta, color=AccentText, wrap=false)

///|
/// Why none, why not read (empty, unread: 4 by 8 in, the meta's size, muted or red); why the places were not read at
/// all (fieldError).
// kept across runs: a value (no field of it changes)
let relay_note_box : @ui.Style = @ui.css("w=Full px=S2 py=S1")

///|
// kept across runs: a value (no field of it changes)
let relay_empty : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let relay_unread : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, w=Full)

///|
// kept across runs: a value (no field of it changes)
let relay_failed : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, w=Full)

///|
/// The note (noteField: its label over its field, 6 apart; noteLabel: the meta's size, muted).
// kept across runs: a value (no field of it changes)
let relay_note_field : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let relay_note_label : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// Via: in line with the place's name (2 down, the row's 10 in, its mark's 16 and the 8 after it: 34), the meta's
/// size, muted; the bot (viaBot) its picture 4 before its name, in the text's colour.
// kept across runs: a value (no field of it changes)
let relay_via_box : @ui.Style = @ui.css("row w=Full pt=S0_5 px=S2_5 align=ACenter")

///|
/// As wide as a place's mark and the 8 after it.
// kept across runs: a value (no field of it changes)
let relay_via_indent : @ui.Style = @ui.css("w=S6")

///|
// kept across runs: a value (no field of it changes)
let relay_via_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let relay_via_bot : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let relay_via_name : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
/// A bot's kind's mark where it has no picture: on a 16 square.
// kept across runs: a value (no field of it changes)
let relay_avatar_box : @ui.Style = @ui.css("w=S4 h=S4 align=ACenter justify=JCenter")
