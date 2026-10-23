// ⌘K's list (ember web/src/Switcher.tsx Finder): what a few words find in the workspace (the core's `search`, as the
// phone's search reads it: search.mbt) — its chats, the messages that have them, and what the stations find besides,
// each kind under its heading, 查看更多 that kind alone (全部结果 or Esc back) — and what can be done here by its name
// (the keys' actions, settings' pages once typed). With nothing typed, the latest chats, then what can be done.

///|
/// Something ⌘K's list can do (Switcher.tsx Listed): its part, its words, its icon, its keys, what it does.
priv struct SwCommand {
  id : String
  group : String
  label : String
  icon : String
  keys : String
  /// found only by typing (a settings page)
  typed : Bool
  run : () -> Unit
}

///|
/// A line of ⌘K's list.
priv enum SwLine {
  Head(String)
  Back
  More(String)
  Command(SwCommand)
  Chat(FoundChat)
  Message(FoundMessage)
  Item(FoundItem)
}

///|
/// Whether a line is one the keys and the pointer choose (headings are not).
fn sw_pickable(l : SwLine) -> Bool {
  !(l is Head(_))
}

///|
/// The kind looked at alone ("" every kind), and the view last read (kept while the next words are looked up).
priv struct Sw {
  mut kind : String
  mut kept : SearchView?
  mut kept_of : (Int, String, String)
}

///|
let sw : Sw = { kind: "", kept: None, kept_of: (-1, "", "") }

///|
fn sw_reset() -> Unit {
  sw.kind = ""
  sw.kept = None
  sw.kept_of = (-1, "", "")
}

///|
/// What can be done now (Switcher.tsx commandsFor): the open chat's (find, its services), the app's (a new chat, the
/// sidebar, settings, the shortcuts), settings' pages (typed only); whose name or id has `query`, in their parts' order.
fn sw_commands(c : @ui.Ctx, query : String) -> Array[SwCommand] {
  let mac = @ui.platform() == 0
  let cmd = if mac { "⌘" } else { "Ctrl+" }
  let shift = if mac { "⇧" } else { "Shift+" }
  let all : Array[SwCommand] = []
  match app.nav.top() {
    Chat(r) => {
      all.push({
        id: "chat.find",
        group: "chat",
        label: tr("web-main.keymap.chat.find"),
        icon: "search",
        keys: cmd + "F",
        typed: false,
        run: fn() { find_open(c, r) },
      })
      all.push({
        id: "chat.jobs",
        group: "chat",
        label: tr("web-main.keymap.chat.jobs"),
        icon: "web",
        keys: cmd + shift + "J",
        typed: false,
        run: fn() { wide.jobs_open = true },
      })
    }
    _ => ()
  }
  all.push({
    id: "chat.new",
    group: "global",
    label: tr("web-main.keymap.chat.new"),
    icon: "compose",
    keys: cmd + "N",
    typed: false,
    run: new_chat_wide,
  })
  all.push({
    id: "sidebar.toggle",
    group: "global",
    label: tr("web-main.keymap.sidebar.toggle"),
    icon: "panel-open",
    keys: cmd + "\\",
    typed: false,
    run: fn() { wide.folded = !wide.folded },
  })
  all.push({
    id: "settings",
    group: "global",
    label: tr("web-main.keymap.settings"),
    icon: "settings",
    keys: cmd + ",",
    typed: false,
    run: open_settings,
  })
  all.push({
    id: "shortcuts",
    group: "global",
    label: tr("web-main.keymap.shortcuts"),
    icon: "command",
    keys: cmd + "/",
    typed: false,
    run: fn() { wide.keys_open = true },
  })
  let pages : Array[(String, @settings.Route, String)] = [
    ("appearance", @settings.Route::Appearance, tr("web-pages.settings.nav.appearance")),
    ("notifications", @settings.Route::Notifications, tr("web-pages.settings.nav.notifications")),
    ("permissions", @settings.Route::Permissions, tr("web-pages.settings.nav.permissions")),
    ("archive", @settings.Route::Archiving, tr("web-pages.archiving.title")),
    ("memory", @settings.Route::Memories, tr("web-pages.settings.nav.memory")),
    ("security", @settings.Route::Security, tr("web-pages.security.title")),
    ("vault", @settings.Route::Vault, tr("web-pages.vault.title")),
    ("changelog", @settings.Route::Changelog, tr("web-pages.settings.nav.changelog")),
    ("about", @settings.Route::About, tr("web-pages.settings.nav.about")),
  ]
  for p in pages {
    let (key, route, label) = p
    all.push({
      id: "settings." + key,
      group: "settings",
      label,
      icon: "settings",
      keys: "",
      typed: true,
      run: fn() {
        open_settings()
        app.nav.replace(Setting(route))
      },
    })
  }
  let q = lower(query.trim(chars=" ").to_string())
  let found = if q == "" {
    all.filter(fn(x) { !x.typed })
  } else {
    all.filter(fn(x) { lower(x.label).contains(q) || lower(x.id).contains(q) })
  }
  let out : Array[SwCommand] = []
  for g in ["chat", "global", "settings"] {
    for x in found {
      if x.group == g {
        out.push(x)
      }
    }
  }
  out
}

///|
/// What the words find (the `search` topic over the workspace), the last view read while the next is looked up.
fn sw_read(src : Source, w : Workspace, query : String) -> SearchView? {
  let params : Map[String, Json] = { "scope": Json::string(w.id), "query": Json::string(query) }
  if sw.kind != "" {
    params["kind"] = Json::string(sw.kind)
  }
  let topic = (src.topic)("search", params)
  match topic.value {
    Some(v) => {
      let of = (topic.version, query, sw.kind)
      if sw.kept_of != of || sw.kept is None {
        sw.kept = Some(search_view(v))
        sw.kept_of = of
      }
    }
    None => ()
  }
  sw.kept
}

///|
/// ⌘K's lines, as drawn (Switcher.tsx Finder): with words, what can be done first, the chats (those the list's titles
/// have at once, then what the search adds), the messages, each kind the stations found; with none, the latest chats
/// then what can be done.
fn sw_lines(c : @ui.Ctx, src : Source, w : Workspace, query : String) -> Array[SwLine] {
  let lines : Array[SwLine] = []
  let typed = query != ""
  let commands = if sw.kind != "" { [] } else { sw_commands(c, query) }
  let add_commands = fn() {
    for i, x in commands {
      if i == 0 || commands[i - 1].group != x.group {
        lines.push(Head(tr("web-main.switcher.group." + x.group)))
      }
      lines.push(Command(x))
    }
  }
  if sw.kind != "" {
    lines.push(Back)
  }
  if typed {
    add_commands()
  }
  // the chats: the list's titles that have the words, then those the search found besides
  let chats : Array[FoundChat] = []
  let view = if typed { sw_read(src, w, query) } else { None }
  if sw.kind == "" || sw.kind == "chat" {
    match chats_of(src, w.id, "all") {
      (Some(v), _) =>
        for d in v.days {
          for item in d.items {
            if !typed || lower(item.title).contains(lower(query)) {
              chats.push({ item, found: None, marks: [], archived: false })
            }
          }
        }
      _ => ()
    }
  }
  match view {
    Some(v) =>
      for ch in v.chats {
        if !chats.iter().any(fn(x) { x.item.station == ch.item.station && x.item.id == ch.item.id }) {
          chats.push(ch)
        }
      }
    None => ()
  }
  let chats = if chats.length() > sw_most { chats[:sw_most].to_owned() } else { chats }
  if chats.length() > 0 && (typed || commands.length() > 0) {
    lines.push(Head(tr("web-main.switcher.chats")))
  }
  for ch in chats {
    lines.push(Chat(ch))
  }
  match view {
    Some(v) if sw.kind == "" && v.chats_more => lines.push(More("chat"))
    _ => ()
  }
  if !typed {
    add_commands()
  }
  match view {
    Some(v) => {
      if v.messages.length() > 0 {
        lines.push(Head(tr("web-main.switcher.messages")))
      }
      for m in v.messages {
        lines.push(Message(m))
      }
      if sw.kind == "" && v.messages_more {
        lines.push(More("message"))
      }
      for g in v.groups {
        lines.push(Head(g.title))
        for it in g.items {
          lines.push(Item(it))
        }
        if sw.kind == "" && g.more {
          lines.push(More(g.kind))
        }
      }
    }
    None => ()
  }
  lines
}

///|
/// At most this many chats in the list.
let sw_most : Int = 12

///|
/// A line chosen (Enter, a press): a command done once the list is closed, a chat opened (a message at it, its words
/// marked), something else where it opens; 查看更多 its kind alone, 全部结果 all again.
fn sw_go(c : @ui.Ctx, line : SwLine, view_words : Array[String]) -> Unit {
  let close = fn() {
    wide.switcher = false
    c.blur()
  }
  match line {
    Head(_) => ()
    Back => {
      sw.kind = ""
      wide.chosen = 0
    }
    More(kind) => {
      sw.kind = kind
      wide.chosen = 1
    }
    Command(x) => {
      close()
      (x.run)()
    }
    Chat(ch) => {
      close()
      open_row(ch.item)
    }
    Message(m) => {
      close()
      open_chat_found(chat_ref_of(m.chat), m.seq, view_words)
    }
    Item(it) => {
      close()
      open_found(it)
    }
  }
}

///|
/// A line drawn (Switcher.tsx's rows): a heading small and muted; a command its icon, its name, its keys; a chat its
/// title, where and when (found by words its title shows late or not at all: that part first, its title under it); a
/// message what it says with the words, its chat under it; something else what it is, its line with the words.
fn sw_line(c : @ui.Ctx, key : String, line : SwLine, chosen : Bool) -> Unit {
  let t = @sf.theme()
  match line {
    Head(words) => c.box(style=sw_head, fn() { c.text(words, style=sw_head_words) |> ignore }) |> ignore
    _ => {
      let row = if chosen { sw_row_on } else { sw_row }
      let tall = match line {
        Message(_) | Item(_) => true
        Chat(ch) => ch.found is Some(_)
        _ => false
      }
      let mark = fn(icon : String) {
        c.box(style=sw_mark, fn() { @sf.icon(c, icon, size=sw_icon, color=t.p.muted) |> ignore }) |> ignore
      }
      // a chat's picture (Switcher.tsx ChatPicture): its first agent's maker's mark
      let picture = fn(item : ChatItem) {
        match item.agents.get(0) {
          Some(a) => c.box(style=sw_mark, fn() { @sf.maker_mark(c, a.maker, a.runtime, sw_logo) |> ignore }) |> ignore
          None => mark("chat")
        }
      }
      c.box(style=if tall { row.then(sw_row_tall) } else { row }, id=c.id(key), fn() {
        match line {
          Back => {
            mark("chevron-left")
            c.text(tr("web-main.switcher.back"), style=sw_title) |> ignore
          }
          More(_) => {
            mark("more")
            c.text(tr("web-main.switcher.more"), style=sw_title_muted) |> ignore
          }
          Command(x) => {
            mark(x.icon)
            c.text(x.label, style=sw_title) |> ignore
            if x.keys != "" {
              c.text(x.keys, style=sw_meta) |> ignore
            }
          }
          Chat(ch) => {
            picture(ch.item)
            let meta = join_meta([
              if ch.archived { tr("web-main.switcher.archived") } else { "" },
              ch.item.station_name,
              ch.item.ago,
            ])
            match ch.found {
              Some(found) =>
                c.box(style=sw_said, fn() {
                  c.box(style=sw_said_head, fn() {
                    found_line(c, "sw/" + key, found, ch.marks, sw_found_words, t.p.text)
                    c.text(meta, style=sw_meta) |> ignore
                  })
                  |> ignore
                  c.text(ch.item.title, style=sw_under) |> ignore
                })
                |> ignore
              None => {
                c.text(ch.item.title, style=sw_title) |> ignore
                c.text(meta, style=sw_meta) |> ignore
              }
            }
          }
          Message(m) => {
            picture(m.chat)
            c.box(style=sw_said, fn() {
              c.box(style=sw_said_head, fn() {
                found_line(c, "sw/" + key, m.text, m.marks, sw_found_words, t.p.text)
                c.text(join_meta([m.by, m.ago]), style=sw_meta) |> ignore
              })
              |> ignore
              c.text(m.chat.title, style=sw_under) |> ignore
            })
            |> ignore
          }
          Item(it) => {
            mark(if it.kind == "file" && it.dir { "folder" } else { kind_icon(it.kind) })
            c.box(style=sw_said, fn() {
              c.box(style=sw_said_head, fn() {
                c.text(it.title, style=sw_title) |> ignore
                c.text(join_meta([if it.kind != "station" { it.station_name } else { "" }, it.ago]), style=sw_meta)
                |> ignore
              })
              |> ignore
              if it.text != "" {
                found_line(c, "sw/i/" + key, it.text, it.marks, sw_under_words, t.p.text)
              }
            })
            |> ignore
          }
          Head(_) => ()
        }
      })
      |> ignore
    }
  }
}

///|
/// A line's key: what it is, so the pointer and the list keep it.
fn sw_key(line : SwLine) -> String {
  match line {
    Head(w) => "h/" + w
    Back => "back"
    More(k) => "more/" + k
    Command(x) => "cmd/" + x.id
    Chat(ch) => "c/" + ch.item.station + "/" + ch.item.id
    Message(m) => "m/" + m.station + "/" + m.chat.session + "/" + m.seq.to_string()
    Item(it) => "i/" + it.key
  }
}

///|
let sw_icon : Double = 16.0

///|
/// A chat's picture: its maker's mark, 18 (ChatPicture's ModelLogo).
let sw_logo : Double = 18.0

///|
/// A line's height, as the list first takes it: a heading 26, a row 36, one of two lines 52.
fn sw_line_h(l : SwLine) -> Double {
  match l {
    Head(_) => 26.0
    Message(_) | Item(_) => 52.0
    Chat(ch) => if ch.found is Some(_) { 52.0 } else { 36.0 }
    _ => 36.0
  }
}

///|
let sw_row_est : Double = 36.0

///|
/// What the panel holds besides its list: its field's 48, its 12 in at its top and foot, 4 between.
let sw_panel_rest : Double = 76.0

///|
/// Lines kept over the one the keys chose as the list scrolls to it.
let sw_lead : Int = 3

///|
/// A heading (Switcher.css.ts section): 12 muted, 10 in, 8 over and 2 under.
// kept across runs: a value (no field of it changes)
let sw_head : @ui.Style = @ui.style(w=Full, px=S2_5, pt=S2, pb=S0_5)

///|
// kept across runs: a value (no field of it changes)
let sw_head_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// A row (Switcher.css.ts row): 38 high, 10 in, its parts 8 apart, the field's corner; chosen on the words' tint.
// kept across runs: a value (no field of it changes)
let sw_row : @ui.Style = @ui.style(row=true, w=Full, min_h=S9, px=S2_5, gap=S2, align=ACenter, radius=Xl)

///|
// kept across runs: a value (no field of it changes)
let sw_row_on : @ui.Style = sw_row.then(@ui.style(bg=Tint))

///|
/// A row of two lines (a message, a chat found by its words, something else): 6 over and under.
// kept across runs: a value (no field of it changes)
let sw_row_tall : @ui.Style = @ui.style(py=S1_5)

///|
// kept across runs: a value (no field of it changes)
let sw_mark : @ui.Style = @ui.style(w=S5, h=S5, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let sw_title : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let sw_title_muted : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let sw_meta : @ui.TextStyle = @ui.text_style(size=Xs, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sw_said : @ui.Style = @ui.style(w=@sf.grow, gap=SPx)

///|
// kept across runs: a value (no field of it changes)
let sw_said_head : @ui.Style = @ui.style(row=true, w=Full, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let sw_found_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, max_lines=1, w=Full)

///|
// kept across runs: a value (no field of it changes)
let sw_under : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let sw_under_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, max_lines=1, w=Full)
