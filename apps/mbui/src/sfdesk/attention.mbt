// What wants the viewer, beside the rail's bell or under 待处理 (ember web/src/Attention.tsx, Attention.css.ts): the
// stations' trouble and the services left up long (with the bell), then each workspace's chats that want the viewer
// (the core's `workspaceMarks`), each leading to its chat; one looked at stays listed, quiet, until it is answered or
// let go here (忽略, `decision.dismiss`). A station's trouble is the same: looked at, it no longer lights the bell; let
// go, it is no longer listed, both until the trouble changes (kept on this device).

///|
/// What the panel keeps: what was let go in it (忽略) until the core no longer lists it, by station and chat; the
/// stations' trouble as looked at when it opened, as it shows it while open (None: closed).
priv struct Attention {
  gone : Array[String]
  mut trouble_seen : String?
}

///|
let attention : Attention = { gone: [], trouble_seen: None }

///|
fn attention_reset() -> Unit {
  attention.gone.clear()
  attention.trouble_seen = None
}

///|
/// 待处理's panel (Attention.tsx): beside the rail's bell, 10 past it (with no bell in the rail, under 待处理 under
/// 新建对话, 6 under it), 300 wide. With the bell, the stations' trouble (looked at as it opens: no longer lighting the
/// bell; 忽略: no longer listed, both until the trouble changes, kept on this device) and the services left up long
/// first; then each workspace's chats that want the viewer (the one in view's first), 忽略 on the row pointed at
/// (`decision.dismiss`); pressed, its chat; 全部决定 (奏) and 通知设置 at its foot.
fn attention_panel(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let close = fn() { wide.attention_open = false }
  let railed = rail_items(src, w.id).contains("attention")
  let trigger = c.id(if railed { "rail/attention" } else { "side/attention" })
  // its stations all reached again: a trouble later in the same words is new (said once the frame is built)
  c.after_build("attention/forget", fn() { trouble_forget(src, w) })
  // looked at as it opens (kept at once), drawn as looked at once it closes: new while it is first read
  if wide.attention_open && attention.trouble_seen is None {
    attention.trouble_seen = Some(trouble_kept(src, w, "seen"))
    let now = station_trouble_words(src, w)
    if railed && now != "" && now != trouble_kept(src, w, "gone") {
      c.tell("attention/seen", fn() { trouble_keep(src, w, "seen", Json::string(now)) })
    }
  } else if !wide.attention_open {
    attention.trouble_seen = None
  }
  let p = @kit.popover(
    c,
    "attention",
    wide.attention_open,
    trigger,
    side=if railed { Right } else { Bottom },
    along=Start,
    offset=if railed { attention_off_rail } else { attention_off_side },
    look=@sf.beside_look(Px(attention_w), inner=att_list),
    fn() { attention_rows(c, src, w, railed, close) },
  )
  wide.attention_open = p.value
}

///|
/// The panel 300 wide (Attention.css.ts panel: its trigger's width, 300 at least), 10 past the rail's bell, 6 under
/// 待处理.
let attention_w : Double = 300.0

///|
let attention_off_rail : Double = 10.0

///|
let attention_off_side : Double = 6.0

///|
/// What is wrong with the workspace's stations, in words (the chats' `trouble`, useStationTrouble); "" none.
fn station_trouble_words(src : Source, w : Workspace) -> String {
  let chats = (src.topic)("chats", { "scope": Json::string(w.id), "mine": Json::boolean(false) }).value
  text(field(chats, "trouble"), "text")
}

///|
/// What this device did with the stations' trouble (`seen`, `gone`): the words it had then, "" none (the prefs'
/// `trouble`, by `<workspace>\n<what>`).
fn trouble_kept(src : Source, w : Workspace, what : String) -> String {
  match field(field((src.topic)("prefs", {}).value, "trouble"), w.id + "\n" + what) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
fn trouble_keep(src : Source, w : Workspace, what : String, words : Json) -> Unit {
  let m : Map[String, Json] = {}
  m[w.id + "\n" + what] = words
  (src.call)("prefs.set", Json::object({ "trouble": Json::object(m) }), fn(_) {  })
}

///|
/// The stations all reached: what was kept of their trouble let go.
fn trouble_forget(src : Source, w : Workspace) -> Unit {
  if station_trouble_words(src, w) == "" && (trouble_kept(src, w, "seen") != "" || trouble_kept(src, w, "gone") != "") {
    trouble_keep(src, w, "seen", Json::null())
    trouble_keep(src, w, "gone", Json::null())
  }
}

///|
/// The stations' trouble listed in the bell (not let go), and whether it is new (not looked at): ("", false) none.
fn bell_trouble(src : Source, w : Workspace) -> (String, Bool) {
  let words = station_trouble_words(src, w)
  if words == "" || words == trouble_kept(src, w, "gone") {
    return ("", false)
  }
  let seen = match attention.trouble_seen {
    Some(s) => s
    None => trouble_kept(src, w, "seen")
  }
  (words, words != seen)
}

///|
/// Whether the rail's bell has its dot: some came since they last looked (the badge, less what was let go here), or,
/// besides, the stations' trouble not looked at or services left up long (Attention.tsx `lit`).
pub fn bell_lit(src : Source, w : Workspace) -> Bool {
  let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) }).value
  let gone_fresh = attention_groups(src, w, false).fold(init=0, fn(n, g) {
    n + g.2.filter(fn(i) { attention.gone.contains(attention_key(i)) && !flag(Some(i), "seen") }).length()
  })
  count(marks, "badge") - gone_fresh > 0 || bell_trouble(src, w).1 || long_jobs(src, w) > 0
}

///|
/// A wanting chat by its station and chat (keyOf).
fn attention_key(i : Json) -> String {
  let v = Some(i)
  let session = text(v, "session")
  text(v, "station") + "/" + (if session != "" { session } else { number(v, "thread").to_int64().to_string() })
}

///|
/// Each workspace's chats that want the viewer, the one in view's first (the cards alone when the badge counts
/// those), those let go here left out unless `all`: (workspace, its name, its chats).
fn attention_groups(src : Source, w : Workspace, shown : Bool) -> Array[(String, String, Array[Json])] {
  let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) }).value
  let only = text(marks, "badgeCounts") == "decisions"
  let groups : Array[(String, String, Array[Json])] = []
  match field(marks, "workspaces") {
    Some(Object(by)) => {
      let order = by.keys().to_array()
      order.sort_by(fn(a, b) { if a == w.id { -1 } else if b == w.id { 1 } else { 0 } })
      for ws in order {
        let list = items(by.get(ws), "items").filter(fn(i) {
          (!only || text(Some(i), "kind") == "wait") && (!shown || !attention.gone.contains(attention_key(i)))
        })
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
  let (trouble, trouble_new) = if railed { bell_trouble(src, w) } else { ("", false) }
  let jobs = if railed { long_jobs(src, w) } else { 0 }
  let several = groups.length() > 1 || groups.iter().any(fn(g) { g.0 != w.id })
  if groups.length() == 0 && trouble == "" && jobs == 0 {
    c.box(style=att_empty, fn() { c.text(@sf.t("web-main.attention.empty"), style=att_empty_words) |> ignore }) |> ignore
  }
  let mut first = true
  let group = fn(name : String, body : () -> Unit) {
    c.box(style=if first { att_group } else { att_group_next }, fn() {
      if name != "" {
        c.box(style=att_group_name, fn() { c.text(name, style=att_group_words) |> ignore }) |> ignore
      }
      body()
    })
    |> ignore
    first = false
  }
  if trouble != "" {
    group("Station", fn() {
      attention_item(c, "attention/trouble", "alert", !trouble_new, trouble, "", @sf.t("web-main.attention.dismissTrouble"), Some(fn() {
        c.tell("attention/gone", fn() { trouble_keep(src, w, "gone", Json::string(trouble)) })
      }), fn() {
        close()
        rail_go(c, src, w, "stations")
      })
    })
  }
  if jobs > 0 {
    group("", fn() { open_jobs(c, src, w) })
  }
  for g in groups {
    group(if several { g.1 } else { "" }, fn() {
      for i in g.2 {
        let v = Some(i)
        let key = attention_key(i)
        let session = text(v, "session")
        let title = text(v, "title")
        let thread = number(v, "thread")
        let seq = field(v, "seq")
        // let go (忽略): a decision waiting on the viewer (the core says where it is in the chat)
        let dismiss = if text(v, "kind") == "wait" && thread > 0.0 && seq is Some(Number(_, ..)) {
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
          flag(v, "seen"),
          if title != "" { title } else { @sf.t("web-main.attention.untitled") },
          attention_line(v),
          @sf.t("web-main.attention.dismissNote"),
          dismiss,
          fn() {
            close()
            if g.0 != w.id {
              app.picked = g.0
              (src.call)("prefs.set", Json::object({ "workspace": Json::string(g.0) }), fn(_) {  })
              desk_home()
            }
            let chat : ChatRef = {
              station: text(v, "station"),
              session: if session != "" { session } else { "thread:" + thread.to_int64().to_string() },
              title,
              station_name: text(v, "stationName"),
            }
            while app.nav.depth() > 1 {
              if !app.nav.pop() {
                break
              }
            }
            app.nav.replace(Home)
            app.nav.push(Chat(chat))
          },
        )
      }
    })
  }
  // 全部决定 and 通知设置: small words, quiet (Attention.css.ts foot, link)
  c.box(style=att_foot, fn() {
    if attention_link(c, "attention/desk", @sf.t("web-main.attention.desk")) {
      close()
      @sfbase.go_place("decisions") |> ignore
    }
    if attention_link(c, "attention/settings", @sf.t("web-main.attention.settings")) {
      close()
      open_settings_at(@settings.Route::Notifications)
    }
  })
  |> ignore
}

///|
/// A row of 待处理's panel (Attention.css.ts item): its dot (amber waiting on the viewer, red gone wrong; a ring once
/// looked at), its title (500 until looked at, then muted) and its line; 忽略 at its end while pointed at, when it can
/// be let go (`note` its tip). Pressed, `go`.
fn attention_item(
  c : @ui.Ctx,
  key : String,
  kind : String,
  seen : Bool,
  title : String,
  line : String,
  note : String,
  dismiss : (() -> Unit)?,
  go : () -> Unit,
) -> Unit {
  let id = c.id(key)
  let drop = c.id(key + "/dismiss")
  c.cursor(id, Hand)
  if c.clicked(id) {
    go()
  }
  let hover = c.lit(id) || c.lit(drop)
  let alert = kind == "alert"
  let b = c.box(style=if hover { att_item_on } else { att_item }, id~, fn() {
    // (its kind in words: role="img")
    let ink = if alert { @sf.theme().p.red } else { @sf.theme().p.warn_ink }
    let dot = c.box(style=if seen { att_dot_seen } else { att_dot.then(@ui.style(bg=Data(ink))) }, fn() {  })
    c.semantics(dot, Image, label=@sf.t(if alert { "web-main.attention.alertOne" } else { "web-main.attention.waitOne" }))
    c.box(style=att_text, fn() {
      c.text(title, style=if seen { att_title_seen } else { att_title }) |> ignore
      if line != "" {
        c.text(line, style=att_line) |> ignore
      }
    })
    |> ignore
    match dismiss {
      // (always to a finger, which hovers over nothing)
      Some(d) if @sf.pointed_or_finger(hover) => {
        c.cursor(drop, Hand)
        if c.clicked(drop) {
          d()
        }
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
fn attention_link(c : @ui.Ctx, key : String, label : String) -> Bool {
  let id = c.id(key)
  c.cursor(id, Hand)
  let b = c.box(id~, fn() { c.text(label, style=if c.lit(id) { att_link_on } else { att_link }) |> ignore })
  c.semantics(b, Link, id~, label~)
  c.clicked(id)
}


///|
/// The panel's rows 2 apart (Attention.css.ts panel); a group's 1, the next group 6 further (group + group).
// kept across runs: a value (no field of it changes)
let att_list : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let att_group : @ui.Style = @ui.css("w=Full gap=SPx")

///|
// kept across runs: a value (no field of it changes)
let att_group_next : @ui.Style = @ui.css("w=Full gap=SPx pt=S1_5")

///|
/// A group's name (groupName): 4 above, 2 under, 10 in; 12, muted.
// kept across runs: a value (no field of it changes)
let att_group_name : @ui.Style = @ui.css("w=Full px=S2_5 pt=S1 pb=S0_5")

///|
// kept across runs: a value (no field of it changes)
let att_group_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L4_75, wrap=false)

///|
/// Nothing waiting (empty): 10 round, 13, muted.
// kept across runs: a value (no field of it changes)
let att_empty : @ui.Style = @ui.css("w=Full p=S2_5")

///|
// kept across runs: a value (no field of it changes)
let att_empty_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L6)

///|
/// A row (item): 6 by 10 in, its dot and words 8 apart, its corner the panel's inner (--panel-in); pointed at, on the
/// pointer's ground.
// kept across runs: a value (no field of it changes)
let att_item : @ui.Style = @ui.style(row=true, w=Full, px=S2_5, py=S1_5, gap=S2, align=ACenter, radius=@sf.panel_in)

///|
// kept across runs: a value (no field of it changes)
let att_item_on : @ui.Style = att_item.then(@ui.css("bg=Hover"))

///|
/// Its dot, 7 round, in the amber's ink (red gone wrong); once looked at, a ring 1.5 wide in the muted grey.
// kept across runs: a value (no field of it changes)
let att_dot : @ui.Style = @ui.style(w=@sf.attention_dot, h=@sf.attention_dot, radius=Full)

///|
// kept across runs: a value (no field of it changes)
let att_dot_seen : @ui.Style = att_dot.then(@ui.css("bg=Clear border=B1_5 border_color=Muted"))

///|
// kept across runs: a value (no field of it changes)
let att_text : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let att_title : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, leading=L6, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let att_title_seen : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L6, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let att_line : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L4_75, wrap=false)

///|
/// 忽略 (dismiss): a small pill, 1 by 6 in, 12, muted; in ink on the pointer's ground pointed at.
// kept across runs: a value (no field of it changes)
let att_dismiss : @ui.Style = @ui.css("px=S1_5 py=SPx radius=Full")

///|
// kept across runs: a value (no field of it changes)
let att_dismiss_on : @ui.Style = @ui.css("px=S1_5 py=SPx radius=Full bg=Hover")

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
/// A wanting chat's line without its lead (the core's `what`: 要你帮忙：, 出问题：, 奏 · taken off; the dot before it
/// says that), else its station's name (Attention.tsx line).
fn attention_line(v : Json?) -> String {
  match text(v, "what") {
    "" => text(v, "stationName")
    s => s
  }
}

