// What wants the viewer and they have not looked at yet, beside the rail's bell or under 待处理 (still.fail
// web/src/Attention.tsx, Attention.css.ts): the stations' trouble and the services left up long (with the bell), then
// each workspace's chats that came to want the viewer and were not read since (the core's `workspaceMarks` items),
// each leading to its chat: a card until read (then its row still says it), a failure until the chat runs again,
// an unread chat the app's number counts until read (全部已读 reads them at once, leaving cards and failures);
// one let go here neither (忽略: a card's `decision.dismiss`, a failure's `prefs.failsGone` until it fails again). A
// station's trouble is the same: listed until the panel has shown it, then the Station's place
// says it, until the trouble changes (kept on this device).
//
// Only what has come to you and you have not seen; there is no list of every open decision (奏 removed, the user,
// 2026-10-30: 「把奏删掉吧」).

///|
/// What the panel keeps: what was let go in it (忽略) until the core no longer lists it, by station and chat; the
/// stations' trouble as looked at before it opened, as it shows it while open (None: closed).
priv struct Attention {
  gone : Array[String]
  mut trouble_seen : String?
  /// A clearing already asked of this core, until its prefs change or the station has trouble again. A call's
  /// answer can arrive before the prefs topic; no frame in between sends the same write again.
  trouble_forgotten : Map[String, (Int, String, String)]
}

///|
let attention : Attention = { gone: [], trouble_seen: None, trouble_forgotten: {} }

///|
fn attention_reset() -> Unit {
  attention.gone.clear()
  attention.trouble_seen = None
  attention.trouble_forgotten.clear()
}

///|
/// 待处理's panel opened or closed, whatever does it: closed, this opening of it over (what it kept as it opened, the
/// stations' trouble as looked at before, let go: the next opening reads it anew), at that moment.
fn attention_set(open : Bool) -> Unit {
  if !open {
    attention.trouble_seen = None
  } else {
    // (beside the rail's bell where it is as it opens, whatever opens it: rail_node's)
    attention_from.val = rail_place_at("attention")
  }
  wide.attention_open.set(open)
}

///|
/// The window's width as 待处理's panel was last drawn (attention_panel: a turn closes it).
let attention_size : FixedArray[Double] = [0.0]

///|
/// 待处理's panel: beside the rail's bell, 10 past it (with no bell in the rail, under 待处理 under
/// 新建对话, 6 under it), 300 wide. With the bell, the stations' trouble not looked at yet (looked at as it opens:
/// listed while open, then no longer, until the trouble changes, kept on this device) and the services left up long
/// first; then each workspace's chats that want the viewer, not read since (the one in view's first), 忽略 on the row
/// pointed at (`decision.dismiss`); pressed, its chat; 全部已读 and 通知设置 at its foot, which stays as the rest
/// scrolls.
fn attention_panel(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let close = fn() { attention_set(false) }
  // (the window turned beside the system's tabs: what it opened from is elsewhere, closed: rail_native.mbt)
  if native_turned(c, attention_size) {
    close()
  }
  let railed = rail_items(src, w.id).contains("attention")
  let trigger = c.id(if railed || @sf.native_on() { "rail/attention" } else { "side/attention" })
  // its stations all reached again: a trouble later in the same words is new (said once the frame is built)
  c.after_build("attention/forget", fn() { trouble_forget(src, w) })
  // looked at as it opens (kept at once), no longer listed once it closes: listed while it is first read
  if wide.attention_open.get() && attention.trouble_seen is None {
    attention.trouble_seen = Some(trouble_kept(src, w, "seen"))
    let now = station_trouble_words(src, w)
    if railed && now != "" {
      c.tell("attention/seen", fn() { trouble_keep(src, w, "seen", Json::string(now)) })
    }
    // the services left up long it lists: shown, no longer lighting it (still listed)
    if railed && long_jobs_lit(src, w) {
      c.tell("attention/jobs-seen", fn() { long_jobs_seen(src, w) })
    }
  }
  // (dismissed by the hand, Escape or a press outside it and the bell: closed at that moment)
  c.with_dismissed(fn(_) { attention_set(false) }, fn() {
    @kit.popover(
      c,
      "attention",
      wide.attention_open.get(),
      trigger,
      // (the system's bell: in its column down the side, beside it from its top; at the top's lead, under it from its left)
      side=if @sf.native_side() {
        Left
      } else if railed && !@sf.native_on() {
        Right
      } else {
        Bottom
      },
      along=Start,
      offset=if railed { attention_off_rail } else { attention_off_side },
      // (the rail's bell a node of the window's tree: beside where it was as it was pressed, rail_node's)
      // (opened before the bell was placed, a fixture's: where it is now)
      at?=if railed && !@sf.native_on() {
        match attention_from.val {
          Some(r) => Some(r)
          None => rail_place_at("attention")
        }
      } else {
        None
      },
      // (and a press of it its own, none outside the panel)
      anchor_node?=if railed && !@sf.native_on() { rail_drawn.get("attention") } else { None },
      // (its foot under what scrolls, held at the panel's foot: 全部已读 is wanted most when the list is longest,
      // pengxiao 2026-11-12)
      look=fn(c, s, body) {
        @sf.small_panel(c, w=Px(attention_w), fn() {
          @sf.within_room(c, s, body, inner=att_list)
          attention_foot(c, src, w, close)
        })
        |> ignore
      },
      fn() { attention_rows(c, src, w, railed, close) },
    )
    |> ignore
  })
}

///|
/// 待处理's panel open (a screen's fixture).
pub fn open_attention() -> Unit {
  attention_set(true)
}

///|
/// The panel 300 wide (300 at least), 10 past the rail's bell, 6 under
/// 待处理.
let attention_w : Double = 300.0

///|
let attention_off_rail : Double = 10.0

///|
let attention_off_side : Double = 6.0

///|
/// What is wrong with the workspace's stations, in words (the chats' `trouble`, useStationTrouble); "" none.
fn station_trouble_words(src : Source, w : Workspace) -> String {
  chats_trouble_words(@sfbase.chats_topic(src, w.id).value)
}

///|
fn chats_trouble_words(chats : Json?) -> String {
  text(field(chats, "trouble"), "text")
}

///|
/// What this device did with the stations' trouble (`seen`; `gone` from before it was no longer listed once seen): the
/// words it had then, "" none (the prefs' `trouble`, by `<workspace>\n<what>`).
fn trouble_kept(src : Source, w : Workspace, what : String) -> String {
  match field(field(src.topic("prefs", {}).get().value, "trouble"), w.id + "\n" + what) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
fn trouble_keep(src : Source, w : Workspace, what : String, words : Json) -> Unit {
  let m : Map[String, Json] = Map([])
  m[w.id + "\n" + what] = words
  (src.call)("prefs.set", Json::object({ "trouble": Json::object(m) }), @sfbase.answer_unread)
}

///|
/// The stations all reached: what was kept of their trouble let go.
fn trouble_forget(src : Source, w : Workspace) -> Unit {
  // No value yet (for example just after switching workspaces) says nothing about whether its stations recovered.
  let chats = @sfbase.chats_topic(src, w.id)
  guard chats.error is None && chats.value is Some(value) else { return }
  let seen = trouble_kept(src, w, "seen")
  let gone = trouble_kept(src, w, "gone")
  if chats_trouble_words(Some(value)) != "" || (seen == "" && gone == "") {
    attention.trouble_forgotten.remove(w.id)
    return
  }
  let (generation, _) = (src.generation)("prefs", {})
  let clearing = (generation, seen, gone)
  if attention.trouble_forgotten.get(w.id) == Some(clearing) { return }
  attention.trouble_forgotten[w.id] = clearing
  let patch : Map[String, Json] = Map([])
  patch[w.id + "\nseen"] = Json::null()
  patch[w.id + "\ngone"] = Json::null()
  (src.call)("prefs.set", { "trouble": Json::object(patch) }, @sfbase.answer_unread)
}

///|
/// The stations' trouble listed in the bell: not looked at before (while the panel is open, before it opened); ""
/// none.
fn bell_trouble(src : Source, w : Workspace) -> String {
  let words = station_trouble_words(src, w)
  let seen = match attention.trouble_seen {
    Some(s) => s
    None => trouble_kept(src, w, "seen")
  }
  if words == seen {
    ""
  } else {
    words
  }
}

///|
/// Whether the rail's bell has its dot: something in its panel, the chats (less what was let go here), the stations'
/// trouble not looked at or services left up long it has not shown yet.
pub fn bell_lit(src : Source, w : Workspace) -> Bool {
  // (each read whatever the others hold: what it reads never comes and goes with another's value, its topics held
  // all along, not let go of as 待处理 comes to list a chat and asked again as it lists none; sfapp's
  // bell_reads_wbtest)
  let chats = attention_groups(src, w, true).length() > 0
  let trouble = bell_trouble(src, w) != ""
  let jobs = long_jobs_lit(src, w)
  chats || trouble || jobs
}

///|
/// A wanting chat by its station and chat, a failure by itself (keyOf: the same chat failing again is listed anew).
fn attention_key(i : Json) -> String {
  let v = Some(i)
  if text(v, "failure") != "" {
    return text(v, "failure")
  }
  let session = text(v, "session")
  let chat = text(v, "station") + "/" + (if session != "" { session } else { number(v, "thread").to_int64().to_string() })
  // (read here: what is said in it after is listed anew)
  if text(v, "kind") == "done" {
    chat + "@" + number(v, "seq").to_int64().to_string()
  } else {
    chat
  }
}

///|
/// Whether 待处理 lists any chat (what a bell with no services or stations of its own, the phone's, lights by).
pub fn attention_any(src : Source, w : Workspace) -> Bool {
  attention_groups(src, w, true).length() > 0
}

///|
/// The unread 待处理 lists, read up to their last message: gone at once, back if that could not be done.
fn attention_read_all(src : Source, list : Array[Json]) -> Unit {
  for i in list {
    let v = Some(i)
    let key = attention_key(i)
    attention.gone.push(key)
    act(
      src,
      @sf.t("web-main.attention.readAll"),
      "",
      "chat.read",
      { "station": Json::string(text(v, "station")), "thread": Json::number(number(v, "thread")), "seq": field(v, "seq").unwrap() },
      failed=fn() { attention.gone.retain(fn(k) { k != key }) },
    )
  }
}

///|
/// 待处理 as a panel of its own, where there is no bell to open it beside (a phone's Home).
pub fn open_attention_panel(src : Source, w : Workspace, from : @sf.Anchor) -> Unit {
  @sf.panel(
    @sf.t("web-main.attention.entry"),
    fn(c, close) { c.box(style=att_sheet, fn() { attention_rows(c, src, w, false, close) }) |> ignore },
    from~,
    foot=fn(c, close) { c.box(style=att_sheet, fn() { attention_foot(c, src, w, close) }) |> ignore },
  )
}

///|
/// In a box of its own, what it holds stays within the sheet's sides, under its title.
// kept across runs: a value (no field of it changes)
let att_sheet : @ui.Style = @ui.css("w=Full")

///|
/// Each workspace's chats in 待处理 (the core's marks' items), the one in view's first, those let go here left out
/// when `shown`: (workspace, its name, its chats).
fn attention_groups(src : Source, w : Workspace, shown : Bool) -> Array[(String, String, Array[Json])] {
  let marks = src.topic("workspaceMarks", @sfbase.marks_asked()).get().value
  let groups : Array[(String, String, Array[Json])] = []
  match field(marks, "workspaces") {
    Some(Object(by)) => {
      let order = by.keys().to_array()
      order.sort_by(fn(a, b) { if a == w.id { -1 } else if b == w.id { 1 } else { 0 } })
      for ws in order {
        let list = items(by.get(ws), "items").filter(fn(i) { !shown || !attention.gone.contains(attention_key(i)) })
        if list.length() > 0 {
          groups.push((ws, text(Some(list[0]), "workspaceName"), list))
        }
      }
    }
    _ => ()
  }
  groups
}

///|
/// What 待处理's panel holds, read while it is open.
fn attention_rows(c : @ui.Ctx, src : Source, w : Workspace, railed : Bool, close : () -> Unit) -> Unit {
  let groups = attention_groups(src, w, true)
  let trouble = if railed { bell_trouble(src, w) } else { "" }
  let jobs = if railed { long_jobs(src, w) } else { 0 }
  let several = groups.length() > 1 || groups.iter().any(fn(g) { g.0 != w.id })
  if groups.length() == 0 && trouble == "" && jobs == 0 {
    c.box(style=att_empty, fn() { c.text(@sf.t("web-main.attention.empty"), style=att_empty_words) |> ignore }) |> ignore
  }
  let mut first = true
  // (a small panel's groups: a named one its name's room over it, one with none 6 under the one before)
  let group = fn(name : String, lead : ((@ui.Ctx) -> Unit)?, body : () -> Unit) {
    if name == "" && !first {
      c.box(style=att_group_next, fn() { @sf.panel_group(c, body) }) |> ignore
    } else {
      @sf.panel_group(c, label=name, lead?=lead, body)
    }
    first = false
  }
  if trouble != "" {
    group("Station", None, fn() {
      attention_item(c, "attention/trouble", "alert", trouble, "", "", None, fn() {
        close()
        @sfbase.go_place("stations") |> ignore
      })
    })
  }
  if jobs > 0 {
    group("", None, fn() { open_jobs(c, src, w) })
  }
  for g in groups {
    // each workspace's mark before its name, as the core says it with its chats (MarkItem's workspaceEmoji, workspaceIcon)
    let first_item = Some(g.2[0])
    let lead = fn(c : @ui.Ctx) {
      @sf.workspace_badge(c, g.1, text(first_item, "workspaceEmoji"), text(first_item, "workspaceIcon"), att_ws_mark)
    }
    group(if several { g.1 } else { "" }, Some(lead), fn() {
      for i in g.2 {
        let v = Some(i)
        let key = attention_key(i)
        let session = text(v, "session")
        let title = text(v, "title")
        let thread = number(v, "thread")
        let seq = field(v, "seq")
        // let go (忽略): a failure, until the chat fails again (kept on this device: prefs' failsGone)
        let failure = text(v, "failure")
        let alert = text(v, "kind") == "alert"
        // a decision waiting on the viewer (the core says where it is in the chat)
        let dismiss = if alert && failure != "" {
          Some(fn() {
            attention.gone.push(key)
            let m : Map[String, Json] = Map([])
            m[text(v, "workspace")] = Json::array([Json::string(failure)])
            act(
              src,
              @sf.t("web-main.decisions.dismissWhat"),
              "",
              "prefs.set",
              { "failsGone": Json::object(m) },
              // not let go: listed again
              failed=fn() { attention.gone.retain(fn(k) { k != key }) },
            )
          })
        } else if text(v, "kind") == "wait" && thread > 0.0 && seq is Some(Number(_, ..)) {
          Some(fn() {
            attention.gone.push(key)
            act(
              src,
              @sf.t("web-main.decisions.dismissWhat"),
              "",
              "decision.dismiss",
              { "station": Json::string(text(v, "station")), "thread": Json::number(thread), "seq": seq.unwrap() },
              // not let go: listed again
              failed=fn() { attention.gone.retain(fn(k) { k != key }) },
            )
          })
        } else {
          None
        }
        attention_item(
          c,
          "attention/" + key,
          text(v, "kind"),
          if title != "" { title } else { @sf.t("web-main.attention.untitled") },
          attention_line(v),
          @sf.t(if alert { "web-main.attention.dismissFailNote" } else { "web-main.attention.dismissNote" }),
          dismiss,
          fn() {
            close()
            @sfbase.history_push()
            if g.0 != w.id {
              app.picked.set(g.0)
              (src.call)("prefs.set", Json::object({ "workspace": Json::string(g.0) }), @sfbase.answer_unread)
              desk_home()
            }
            let chat : ChatRef = {
              station: text(v, "station"),
              session: if session != "" { session } else { "thread:" + thread.to_int64().to_string() },
              title,
              station_name: text(v, "stationName"),
            }
            @sfbase.nav_over_home([Chat(chat)])
            @sfbase.show_chosen()
          },
        )
      }
    })
  }
}

///|
/// 待处理's foot: 全部已读 while it lists unread, 通知设置, small words, quiet (link).
fn attention_foot(c : @ui.Ctx, src : Source, w : Workspace, close : () -> Unit) -> Unit {
  let unread = attention_groups(src, w, true)
    .iter()
    .flat_map(fn(g) { g.2.iter() })
    .filter(fn(i) { text(Some(i), "kind") == "done" && number(Some(i), "thread") > 0.0 && field(Some(i), "seq") is Some(Number(_, ..)) })
    .collect()
  c.box(style=att_foot, fn() {
    if unread.length() > 0 {
      attention_link(c, "attention/read-all", @sf.t("web-main.attention.readAll"), on_press=fn() {
        attention_read_all(src, unread)
      })
    }
    attention_link(c, "attention/settings", @sf.t("web-main.attention.settings"), on_press=fn() {
      close()
      open_settings_at(@settings.Route::Notifications)
    })
  })
  |> ignore
}

///|
/// A row of 待处理's panel: its dot (amber waiting on the viewer, red gone wrong, blue unread), its title
/// (500) and its line; 忽略 at its end while pointed at, when it can be let go (`note` its tip). Pressed, `go`.
fn attention_item(
  c : @ui.Ctx,
  key : String,
  kind : String,
  title : String,
  line : String,
  note : String,
  dismiss : (() -> Unit)?,
  go : () -> Unit,
) -> Unit {
  let id = c.id(key)
  let drop = c.id(key + "/dismiss")
  c.on_press(id, fn() {
    go()
  })
  let hover = c.lit(id) || c.lit(drop)
  let b = c.box(style=if hover { att_item_on } else { att_item }, id~, fn() {
    // (its kind in words: role="img")
    let (ground, said) : (@ui.Color, String) = match kind {
      "alert" => (Data(@sf.theme().p.red), "web-main.attention.alertOne")
      "done" => (@sf.mark_blue, "web-main.chatMark.done")
      _ => (Data(@sf.theme().p.warn_ink), "web-main.attention.waitOne")
    }
    c.box(style=att_mark, fn() {
      let dot = c.box(style=att_dot.then(@ui.style(bg=ground)), fn() {  })
      c.semantics(dot, Image, label=@sf.t(said))
    })
    |> ignore
    c.box(style=att_text, fn() {
      c.text(title, style=att_title) |> ignore
      if line != "" {
        c.text(line, style=att_line) |> ignore
      }
    })
    |> ignore
    match dismiss {
      // (always to a finger, which hovers over nothing)
      Some(d) if @sf.pointed_or_finger(c, hover) => {
        c.on_press(drop, fn() {
          d()
        })
        let on = c.lit(drop)
        let x = c.box(style=if on { att_dismiss_on } else { att_dismiss }, id=drop, fn() {
          c.text(@sf.t("web-main.attention.dismiss"), style=if on { att_dismiss_on_words } else { att_dismiss_words })
          |> ignore
        })
        c.semantics(x, Button, id=drop, label=@sf.t("web-main.attention.dismiss"))
        @sf.tip(c, key + "/dismiss-tip", drop, note)
      }
      _ => ()
    }
  })
  c.semantics(b, Button, id~, label=title)
}

///|
/// Words to press at 待处理's foot, quiet, in ink pointed at.
fn attention_link(c : @ui.Ctx, key : String, label : String, on_press? : () -> Unit) -> Unit {
  let id = c.id(key)
  let b = c.box(id~, fn() { c.text(label, style=if c.lit(id) { att_link_on } else { att_link }) |> ignore })
  c.semantics(b, Link, id~, label~)
  match on_press {
    Some(f) => c.on_press(id, f)
    None => ()
  }
}


///|
/// The panel's groups 2 apart; one with no name 6 further (group + group).
// kept across runs: a value (no field of it changes)
let att_list : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let att_group_next : @ui.Style = @ui.css("w=Full pt=S1_5")

///|
/// A workspace's mark before its name over its chats.
let att_ws_mark : Double = 14.0

///|
/// Nothing waiting (empty): 10 round, 13, muted.
// kept across runs: a value (no field of it changes)
let att_empty : @ui.Style = @ui.css("w=Full p=S2_5")

///|
// kept across runs: a value (no field of it changes)
let att_empty_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L6)

///|
/// A row (item): 6 by 10 in, its dot's column and words 10 apart, its corner the panel's inner (--panel-in); pointed
/// at, on the pointer's ground. Its words start where a long job's do above it (open_job_row), not 11 left of them.
// kept across runs: a value (no field of it changes)
let att_item : @ui.Style = @ui.style(row=true, w=Full, px=S2_5, py=S1_5, gap=S2_5, align=ACenter, radius=@sf.panel_in)

///|
// kept across runs: a value (no field of it changes)
let att_item_on : @ui.Style = att_item.then(@ui.css("bg=Hover"))

///|
/// Its dot's column: the 16 a long job's dot and a workspace's mark stand in (open_job_mark), the dot in its middle.
// kept across runs: a value (no field of it changes)
let att_mark : @ui.Style = @ui.css("w=S4 align=ACenter justify=JCenter")

///|
/// Its dot, 7 round, in the amber's ink (red gone wrong).
// kept across runs: a value (no field of it changes)
let att_dot : @ui.Style = @ui.style(w=@sf.attention_dot, h=@sf.attention_dot, radius=Full)

///|
// kept across runs: a value (no field of it changes)
let att_text : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let att_title : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, leading=L6, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let att_line : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L4_75, wrap=false)

///|
/// 忽略 (dismiss): a small pill, 1 by 6 in, 12, muted; in ink on the pointer's ground pointed at. Shown only under
/// the pointer, it makes the row no taller (its words' line 19, the pill 21, the title's 20): its ground reaches the
/// 1 over and under past them (align.mbt bleed_y).
// kept across runs: a value (no field of it changes)
let att_dismiss : @ui.Style = @ui.css("px=S1_5 radius=Full").then(@sf.bleed_y(att_dismiss_bleed))

///|
let att_dismiss_bleed : Double = 1.0

///|
// kept across runs: a value (no field of it changes)
let att_dismiss_on : @ui.Style = att_dismiss.then(@ui.css("bg=Hover"))

///|
// kept across runs: a value (no field of it changes)
let att_dismiss_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L4_75, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let att_dismiss_on_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, leading=L4_75, wrap=false)

///|
/// The foot (foot): its words 12 apart, 8 by 10 in and 4 under, 4 more over it.
// kept across runs: a value (no field of it changes)
let att_foot : @ui.Style = @ui.css("row w=Full gap=S3 px=S2_5 pt=S3 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let att_link : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L4_75, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let att_link_on : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, leading=L4_75, wrap=false)

///|
/// A wanting chat's line without its lead (the core's `what`: 要你帮忙：, 出问题：, 待处理 · taken off; the dot before it
/// says that), else its station's name.
fn attention_line(v : Json?) -> String {
  match text(v, "what") {
    "" => text(v, "stationName")
    s => s
  }
}

