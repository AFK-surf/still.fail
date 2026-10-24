// The search (ember web/src/Switcher.tsx Finder, Found; web/src/mobile/Home.tsx SearchPage, FoundRow, FoundChatRow,
// FoundItemRow; Switcher.css.ts, mobile/Home.css.ts mFound…): one in every tier, its words and what they find; where
// it sits is its frame's (⌘K's panel over the window, the phone's page over Home's list: sfdesk's switcher.mbt, sfapp's
// search.mbt). What a few words find in the workspace is the core's `search` (docs/search.md: its chats, the messages
// that have them, what every station finds besides, each kind under its heading, a few of each; 查看更多 that kind
// alone, 全部结果 back to all), and what can be done here by its name the core's `commands.find` of what the frame
// offers. With nothing typed, the latest chats where the frame says so (⌘K), then what can be done. A finger's rows the
// phone's, a mouse's the web desktop's (↑ / ↓ choose, Enter or a press opens).

///|
/// What can be done here, as the frame offers it (Switcher.tsx Offered): a key's action it answers now, or one of its
/// own; for one the core does not name (a settings page), its `label`, `group`, other `words`, and whether it is only
/// found by typing; its icon, its keys (a key's action's, as kept on this device), what it does.
pub(all) struct Offered {
  id : String
  label : String
  group : String
  words : String
  typed : Bool
  icon : String
  keys : String
  run : () -> Unit
}

///|
/// A command as the list shows it (Switcher.tsx Listed): its part, its part's heading, its name, as the core says.
priv struct Listed {
  id : String
  group : String
  heading : String
  label : String
}

///|
/// A line of the list (Switcher.tsx Found, SearchPage's rows, and the headings and words between).
priv enum FindLine {
  Head(String)
  /// over one kind alone: back to every kind (全部结果)
  Back
  /// 查看更多 under a kind: that kind alone
  More(String)
  Command(Listed, Offered)
  Chat(FoundChat)
  Message(FoundMessage)
  Item(FoundItem)
  /// a line of quiet words (none found, the core too old to search)
  Note(String)
  /// the stations still answering, or one that could not be searched (red)
  Wait(String, Bool)
  /// what the core says of the rest
  Said(String)
}

///|
/// The search as it stands: the kind looked at alone ("" every kind); the row chosen; its field and what is typed; the
/// view last read (kept while the next words are looked up) and whether reading it failed; what was last asked of
/// `commands.find`, its last answer and what it answered (kept: the list opened again with the same words has it at
/// once; for other words none until the core has answered them); the lines as last drawn (what Enter opens); the list
/// to go back to its top (into one kind or out of it).
priv struct Finder {
  mut kind : String
  mut chosen : Int
  field : @ui.Field
  mut query : String
  mut kept : SearchView?
  mut kept_of : (Int, String, String)
  mut failed : Bool
  mut asked : String
  mut listed : Array[Listed]
  mut listed_for : String
  mut lines : Array[FindLine]
  mut picks : Array[Int]
  mut to_top : Bool
}

///|
let finder : Finder = {
  kind: "",
  chosen: 0,
  field: @ui.Field::new(),
  query: "",
  kept: None,
  kept_of: (-1, "", ""),
  failed: false,
  asked: "",
  listed: [],
  listed_for: "",
  lines: [],
  picks: [],
  to_top: false,
}

///|
fn finder_reset() -> Unit {
  finder_cleared()
  finder.asked = ""
  finder.listed.clear()
  finder.listed_for = ""
}

///|
/// What one opening of the search leaves behind, put back as it closes (its frame says when).
pub fn finder_cleared() -> Unit {
  finder.kind = ""
  finder.chosen = 0
  finder.query = ""
  finder.field.set("")
  finder.kept = None
  finder.kept_of = (-1, "", "")
  finder.failed = false
  finder.lines = []
  finder.picks = []
  finder.to_top = false
}

///|
/// The search opened with `words` typed and `kind` alone ("" every kind): a made-up run's start.
pub fn finder_start(words : String, kind? : String = "") -> Unit {
  finder_cleared()
  finder.query = words
  finder.field.set(words)
  finder.kind = kind
}

///|
/// The field the frame's editor writes the words in.
pub fn finder_field() -> @ui.Field {
  finder.field
}

///|
/// The kind looked at alone ("" every kind).
pub fn finder_kind() -> String {
  finder.kind
}

///|
/// What is typed now.
pub fn finder_query() -> String {
  finder.query
}

///|
/// The words in the field as the frame's editor has them now: the first line chosen again when they change.
pub fn finder_typed(words : String) -> Unit {
  if words != finder.query {
    finder.query = words
    finder.chosen = if finder.kind != "" { 1 } else { 0 }
  }
}

///|
/// Esc or back: in one kind's list, back to all of them. Whether it went back (else the frame closes the search).
pub fn finder_back() -> Bool {
  if finder.kind == "" {
    return false
  }
  finder.kind = ""
  finder.chosen = 0
  finder.to_top = true
  true
}

///|
/// Enter: the line chosen opened (`close` first, where the frame closes the search as one opens).
pub fn finder_enter(close : () -> Unit) -> Unit {
  match finder.picks.get(finder.chosen) {
    Some(k) => finder_go(finder.lines[k], close)
    None => ()
  }
}

///|
/// What of `offered` the core lists for `query` (`commands.find`: by name, id or other words, part by part; with nothing
/// typed all but what is only found by typing), each with its name; none until it has answered these words. Asked once
/// the frame is built, when what is asked changes.
fn commands_of(c : @ui.Ctx, src : Source, query : String, offered : Array[Offered]) -> Array[(Listed, Offered)] {
  let out : Array[(Listed, Offered)] = []
  if offered.is_empty() {
    return out
  }
  let params : Json = {
    "query": Json::string(query),
    "offered": Json::array(
      offered.map(fn(o) {
        let m : Map[String, Json] = { "id": Json::string(o.id) }
        if o.label != "" {
          m["label"] = Json::string(o.label)
        }
        if o.group != "" {
          m["group"] = Json::string(o.group)
        }
        if o.words != "" {
          m["words"] = Json::string(o.words)
        }
        if o.typed {
          m["typed"] = Json::boolean(true)
        }
        Json::object(m)
      }),
    ),
  }
  let asked = params.stringify()
  if asked != finder.asked {
    c.after_build("switcher/commands.find", fn() {
      if finder.asked != asked {
        finder.asked = asked
        (src.call)("commands.find", params, fn(res) {
          match res {
            Ok(v) if finder.asked == asked => {
              let listed : Array[Listed] = []
              for g in items(Some(v), "groups") {
                let g = Some(g)
                for f in items(g, "commands") {
                  listed.push({
                    id: text(Some(f), "id"),
                    group: text(g, "group"),
                    heading: text(g, "title"),
                    label: text(Some(f), "label"),
                  })
                }
              }
              finder.listed = listed
              finder.listed_for = asked
            }
            _ => ()
          }
        })
      }
    })
  }
  if finder.listed_for != asked {
    return out
  }
  for l in finder.listed {
    for o in offered {
      if o.id == l.id {
        out.push((l, o))
        break
      }
    }
  }
  out
}

///|
/// What the words find (the `search` topic over the workspace: with none, the latest chats), the last view read while
/// the next is looked up; whether reading it failed.
fn search_of(src : Source, scope : String, query : String) -> SearchView? {
  let params : Map[String, Json] = { "scope": Json::string(scope), "query": Json::string(query) }
  if finder.kind != "" {
    params["kind"] = Json::string(finder.kind)
  }
  let topic = (src.topic)("search", params)
  finder.failed = topic.error is Some(_)
  match topic.value {
    Some(v) => {
      let of = (topic.version, query, finder.kind)
      if finder.kept_of != of || finder.kept is None {
        finder.kept = Some(search_view(v))
        finder.kept_of = of
      }
    }
    None => ()
  }
  finder.kept
}

///|
/// The list's lines (Finder, SearchPage): one kind alone, 全部结果 first; with words, what can be done first, then the
/// chats (查看更多 under them), the messages (查看更多), each kind the stations found under its heading (查看更多),
/// none found, the stations still answering or failing, what the core says of the rest. With none typed, the latest
/// chats where `idle_chats` (⌘K's), then what can be done.
fn lines_of(view : SearchView?, typed : Bool, idle_chats : Bool, commands : Array[(Listed, Offered)]) -> Array[FindLine] {
  let lines : Array[FindLine] = []
  let kind = finder.kind
  let actions = if kind != "" { [] } else { commands }
  let add_actions = fn() {
    for k, x in actions {
      if k == 0 || actions[k - 1].0.group != x.0.group {
        lines.push(Head(x.0.heading))
      }
      lines.push(Command(x.0, x.1))
    }
  }
  if kind != "" && typed {
    lines.push(Back)
  }
  if typed && view is None && finder.failed {
    lines.push(Note(@sf.t("android-chat.search.update")))
  }
  if typed {
    add_actions()
  }
  let chats = match view {
    Some(v) if typed || idle_chats => v.chats
    _ => []
  }
  if chats.length() > 0 && (actions.length() > 0 || typed) {
    lines.push(Head(@sf.t("web-main.switcher.chats")))
  }
  for ch in chats {
    lines.push(Chat(ch))
  }
  match view {
    Some(v) if typed && kind == "" && v.chats_more => lines.push(More("chat"))
    _ => ()
  }
  if !typed {
    add_actions()
  }
  match view {
    Some(v) if typed => {
      if v.messages.length() > 0 {
        lines.push(Head(@sf.t("web-main.switcher.messages")))
      }
      for m in v.messages {
        lines.push(Message(m))
      }
      if kind == "" && v.messages_more {
        lines.push(More("message"))
      }
      for g in v.groups {
        lines.push(Head(g.title))
        for it in g.items {
          lines.push(Item(it))
        }
        if kind == "" && g.more {
          lines.push(More(g.kind))
        }
      }
      let none = v.chats.length() == 0 &&
        v.messages.length() == 0 &&
        v.groups.iter().all(fn(g) { g.items.length() == 0 }) &&
        actions.length() == 0
      if none && !v.reading {
        lines.push(Note(@sf.t("web-main.switcher.noMatch")))
      }
      if v.reading {
        lines.push(Wait(v.wait_text.unwrap_or(@sf.t("common.reading")), false))
      }
      for f in v.failing {
        lines.push(Wait(f, true))
      }
      match v.note {
        Some(n) => lines.push(Said(n))
        None => ()
      }
    }
    Some(v) if idle_chats && v.chats.length() == 0 && actions.length() == 0 && !v.reading =>
      lines.push(Note(@sf.t("web-main.switcher.none")))
    _ => ()
  }
  lines
}

///|
/// A line picked (Enter, a press): a command done, a chat opened (a message at it, its words marked), something else
/// where the core says it opens, each after `close`; 查看更多 its kind alone, 全部结果 all again.
fn finder_go(line : FindLine, close : () -> Unit) -> Unit {
  let words = match finder.kept {
    Some(v) => v.words
    None => []
  }
  match line {
    Back => ignore(finder_back())
    More(kind) => {
      finder.kind = kind
      finder.chosen = 1
      finder.to_top = true
    }
    Command(_, o) => {
      close()
      (o.run)()
    }
    Chat(ch) => {
      close()
      open_page(Chat(@sfbase.chat_ref_of(ch.item)))
    }
    Message(m) => {
      close()
      @sfbase.open_chat_found(@sfbase.chat_ref_of(m.chat), m.seq, words)
    }
    Item(it) => {
      close()
      @sfbase.open_found(it)
    }
    Head(_) | Note(_) | Wait(_, _) | Said(_) => ()
  }
}

///|
/// Whether a line is one to choose (↑ / ↓, Enter).
fn pickable(l : FindLine) -> Bool {
  match l {
    Head(_) | Note(_) | Wait(_, _) | Said(_) => false
    _ => true
  }
}

///|
/// The search's list in the box it is given, for workspace `w`: what the words in the field find and what of `offered`
/// can be done by them; with nothing typed the latest chats where `idle_chats`. `most`: as tall as its lines up to so
/// much (⌘K's panel), else the box's height. `close`: what the frame does as a line opens (⌘K closes; the phone's page
/// stays under the chat). ↑ / ↓ choose a line.
pub fn finder_list(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  offered : Array[Offered],
  close : () -> Unit,
  idle_chats? : Bool = false,
  most? : Double,
) -> Unit {
  let finger = @sf.touch_system()
  let query = finder.query.trim(chars=" \t\n\r\u{3000}").to_string()
  let typed = query != ""
  let commands = commands_of(c, src, query, offered)
  let view = search_of(src, w.id, query)
  let lines = lines_of(view, typed, idle_chats, commands)
  let picks : Array[Int] = []
  let pick_of : Array[Int] = []
  for i, l in lines {
    if pickable(l) {
      pick_of.push(picks.length())
      picks.push(i)
    } else {
      pick_of.push(-1)
    }
  }
  finder.lines = lines
  finder.picks = picks
  if finder.chosen >= picks.length() {
    finder.chosen = if picks.length() > 0 { picks.length() - 1 } else { 0 }
  }
  let mut keyed = false
  if c.key_pressed(@ui.key_code_down, in_field=true) && finder.chosen < picks.length() - 1 {
    finder.chosen += 1
    keyed = true
  }
  if c.key_pressed(@ui.key_code_up, in_field=true) && finder.chosen > 0 {
    finder.chosen -= 1
    keyed = true
  }
  let key = "switcher/list"
  if keyed {
    match picks.get(finder.chosen) {
      Some(k) => c.list_scroll_to(key, if k > switcher_lead { k - switcher_lead } else { 0 })
      None => ()
    }
  }
  if finder.to_top {
    finder.to_top = false
    c.list_scroll_to(key, 0)
  }
  // (several stations: an item found says which it is on, on a finger's row)
  let several = match (src.topic)("stations", { "scope": Json::string(w.id) }).value {
    Some(Array(a)) => a.length() > 1
    _ => false
  }
  let est = lines.fold(init=0.0, fn(h, l) { h + finder_h(l, finger) })
  let h : @ui.Size = match most {
    Some(m) => Px(dmin(m, est))
    None => Fill(1.0)
  }
  c.list(
    key,
    lines.length(),
    if finger { touch_row_h } else { switcher_row_h },
    fn(i) {
      let line = lines[i]
      let lk = "switcher/row/" + finder_key(line)
      let k = pick_of[i]
      if k < 0 {
        quiet_line(c, line)
        return
      }
      let id = c.id(lk)
      c.cursor(id, Hand)
      if c.clicked(id) {
        finder_go(line, close)
      }
      if !finger && c.lit(id) {
        finder.chosen = k
      }
      if finger {
        touch_line(c, src, lk, id, line, several, close)
      } else {
        mouse_line(c, lk, id, line, k == finder.chosen)
      }
    },
    h~,
  )
  |> ignore
}

///|
/// How many lines stay over the one the keys chose as the list scrolls to it.
let switcher_lead : Int = 3

///|
/// A line's key: what it is, so the pointer and the list keep it.
fn finder_key(line : FindLine) -> String {
  match line {
    Head(w) => "h/" + w
    Back => "back"
    More(k) => "more/" + k
    Command(l, _) => "cmd/" + l.id
    Chat(ch) => "c/" + ch.item.station + "/" + ch.item.id
    Message(m) => "m/" + m.station + "/" + m.chat.session + "/" + m.seq.to_string()
    Item(it) => "i/" + it.key
    Note(w) => "note/" + w
    Wait(w, _) => "wait/" + w
    Said(w) => "said/" + w
  }
}

///|
/// A line's height, as the list first takes it: a mouse's heading 32, row 38, one of two lines 54; a finger's rows 66
/// (50 for something found with no words of its own), its heading 41.
fn finder_h(l : FindLine, finger : Bool) -> Double {
  if finger {
    return match l {
      Head(_) => touch_head_h
      Item(it) if it.text == "" => found_short_h
      Back | More(_) | Note(_) | Wait(_, _) | Said(_) => touch_quiet_h
      _ => touch_row_h
    }
  }
  match l {
    Head(_) => switcher_head_h
    Message(_) | Item(_) => switcher_row_said_h
    Chat(ch) => if ch.found is Some(_) { switcher_row_said_h } else { switcher_row_h }
    Note(_) | Wait(_, _) | Said(_) => switcher_row_said_h
    _ => switcher_row_h
  }
}

///|
let switcher_row_h : Double = 38.0

///|
let switcher_row_said_h : Double = 54.0

///|
let switcher_head_h : Double = 32.0

///|
let touch_head_h : Double = 41.0

///|
let touch_quiet_h : Double = 44.0

///|
let found_short_h : Double = 50.0

///|
/// What is not chosen: a heading (a mouse's small and muted, a finger's the phone's section), none found, the stations
/// still answering, what the core says.
fn quiet_line(c : @ui.Ctx, line : FindLine) -> Unit {
  let finger = @sf.touch_system()
  match line {
    Head(words) =>
      if finger {
        list_heading(c, words)
      } else {
        c.box(style=switcher_head, fn() { c.text(words, style=switcher_head_words) |> ignore }) |> ignore
      }
    Note(words) =>
      c.box(style=if finger { found_note_box } else { switcher_none_box }, fn() {
        c.text(words, style=if finger { found_note_words } else { switcher_none }) |> ignore
      })
      |> ignore
    Wait(words, error) =>
      c.box(style=if finger { if error { found_failing_box } else { found_wait_box } } else { switcher_note_box }, fn() {
        @sf.wait_line(c, words, key="search", error~)
      })
      |> ignore
    Said(words) =>
      c.box(style=if finger { found_wait_box } else { switcher_note_box }, fn() {
        c.text(words, style=if finger { found_said_words } else { switcher_note }) |> ignore
      })
      |> ignore
    _ => ()
  }
}

///|
/// A mouse's line (Finder's rows): a command its icon, its name, its keys; a chat its picture, its title, where and when
/// (found by words its title shows late or not at all: that part first, its title under it); a message what it says
/// with the words, its chat under it; something else (ItemRow) what it is, where and when, its line with the words;
/// the chosen one lit.
fn mouse_line(c : @ui.Ctx, key : String, id : Int, line : FindLine, chosen : Bool) -> Unit {
  let t = @sf.theme()
  let tall = match line {
    Message(_) | Item(_) => true
    Chat(ch) => ch.found is Some(_)
    _ => false
  }
  let row = if tall { switcher_row_said } else { switcher_row }
  let mark = fn(icon : String) {
    c.box(style=switcher_picture, fn() { @sf.icon(c, icon, size=switcher_icon, color=t.p.muted) |> ignore })
    |> ignore
  }
  // a chat's picture (ChatPicture): its first agent's maker's mark
  let picture = fn(item : ChatItem) {
    match item.agents.get(0) {
      Some(a) =>
        c.box(style=switcher_picture, fn() { @sf.maker_mark(c, a.maker, a.runtime, switcher_logo) |> ignore })
        |> ignore
      None => mark("chat")
    }
  }
  c.box(style=row, selected=chosen, id~, fn() {
    match line {
      Back => {
        mark("chevron-left")
        c.text(@sf.t("web-main.switcher.back"), style=switcher_title) |> ignore
      }
      More(_) => {
        mark("more")
        c.text(@sf.t("web-main.switcher.more"), style=switcher_title_muted) |> ignore
      }
      Command(l, o) => {
        mark(o.icon)
        c.text(l.label, style=switcher_title) |> ignore
        if o.keys != "" {
          c.text(o.keys, style=switcher_meta) |> ignore
        }
      }
      Chat(ch) => {
        picture(ch.item)
        let meta = @sf.join_meta([
          if ch.archived { @sf.t("web-main.switcher.archived") } else { "" },
          ch.item.station_name,
          ch.item.ago,
        ])
        match ch.found {
          Some(found) =>
            c.box(style=switcher_said, fn() {
              c.box(style=switcher_said_head, fn() {
                @sf.found_line(c, "sw/" + key, found, ch.marks, switcher_found_words, t.p.text)
                c.text(meta, style=switcher_meta) |> ignore
              })
              |> ignore
              c.text(ch.item.title, style=switcher_under) |> ignore
            })
            |> ignore
          None => {
            c.text(ch.item.title, style=switcher_title) |> ignore
            c.text(meta, style=switcher_meta) |> ignore
          }
        }
      }
      Message(m) => {
        picture(m.chat)
        c.box(style=switcher_said, fn() {
          c.box(style=switcher_said_head, fn() {
            @sf.found_line(c, "sw/" + key, m.text, m.marks, switcher_found_words, t.p.text)
            c.text(@sf.join_meta([m.by, m.ago]), style=switcher_meta) |> ignore
          })
          |> ignore
          c.text(m.chat.title, style=switcher_under) |> ignore
        })
        |> ignore
      }
      Item(it) => {
        mark(if it.kind == "file" && it.dir { "folder" } else { @sf.kind_icon(it.kind) })
        c.box(style=switcher_said, fn() {
          c.box(style=switcher_said_head, fn() {
            c.text(it.title, style=switcher_title) |> ignore
            c.text(
              @sf.join_meta([if it.kind != "station" { it.station_name } else { "" }, it.ago]),
              style=switcher_meta,
            )
            |> ignore
          })
          |> ignore
          if it.text != "" {
            @sf.found_line(c, "sw/i/" + key, it.text, it.marks, switcher_under_words, t.p.text)
          }
        })
        |> ignore
      }
      Head(_) | Note(_) | Wait(_, _) | Said(_) => ()
    }
  })
  |> ignore
}

///|
/// A finger's line (SearchPage's rows): a chat as the chats' list has it (found by words its title shows late or not
/// at all: those first, its title under it, as a message is); a message what it says with the words, over its chat,
/// who and when; something else its kind's icon, what it is, where (with several stations) and when, over its line with
/// the words; a command its icon and its name; 全部结果 and 查看更多 in the accent. Rippled where pressed.
fn touch_line(
  c : @ui.Ctx,
  src : Source,
  key : String,
  id : Int,
  line : FindLine,
  several : Bool,
  close : () -> Unit,
) -> Unit {
  let t = @sf.theme()
  match line {
    Back =>
      c.box(style=found_back_row, id~, fn() {
        @sf.icon(c, "chevron-left", size=found_chevron, color=t.p.accent) |> ignore
        c.text(@sf.t("android-chat.search.all"), style=found_link_words) |> ignore
        @motion.ripple(c, id, 0.0)
      })
      |> ignore
    More(_) =>
      c.box(style=found_more_row, id~, fn() {
        c.text(@sf.t("android-chat.search.more"), style=found_link_words) |> ignore
        @motion.ripple(c, id, 0.0)
      })
      |> ignore
    Chat(ch) =>
      match ch.found {
        Some(found) => {
          let meta = @sf.join_meta([if ch.archived { @sf.t("android-chat.search.archived") } else { "" }, ch.item.ago])
          hit_row(c, key, id, found, ch.marks, meta, ch.item.title)
        }
        // (the chats' list's row: pressed, its chat where the shell has it)
        None => chat_row(c, src, ch.item, "agents", found=true, opened=fn(r) { close(); open_page(Chat(r)) }) |> ignore
      }
    Message(m) => hit_row(c, key, id, m.text, m.marks, @sf.join_meta([m.by, m.ago]), m.chat.title)
    Item(it) =>
      c.box(style=if it.text == "" { found_item_row_short } else { found_item_row }, id~, fn() {
        c.box(style=found_icon_box, fn() {
          if it.kind == "station" {
            @sf.station_mark(c, it.station_emoji, it.station_icon, found_icon, t.p.muted, none="server")
          } else {
            @sf.icon(c, if it.kind == "file" && it.dir { "folder" } else { @sf.kind_icon(it.kind) }, size=found_icon, color=t.p.muted)
            |> ignore
          }
        })
        |> ignore
        c.box(style=found_column, fn() {
          c.box(style=found_line_22, fn() {
            c.text(it.title, style=found_title) |> ignore
            let meta = @sf.join_meta([if several && it.kind != "station" { it.station_name } else { "" }, it.ago])
            if meta != "" {
              c.text(meta, style=found_meta) |> ignore
            }
          })
          |> ignore
          if it.text != "" {
            c.box(style=found_line_20, fn() {
              @sf.found_line(c, "i/" + it.key, it.text, it.marks, found_item_words, t.p.text)
            })
            |> ignore
          }
        })
        |> ignore
        @motion.ripple(c, id, 0.0)
      })
      |> ignore
    Command(l, o) =>
      c.box(style=found_item_row_short, id~, fn() {
        c.box(style=found_icon_box, fn() { @sf.icon(c, o.icon, size=found_icon, color=t.p.muted) |> ignore }) |> ignore
        c.text(l.label, style=found_title) |> ignore
        @motion.ripple(c, id, 0.0)
      })
      |> ignore
    Head(_) | Note(_) | Wait(_, _) | Said(_) => ()
  }
}

///|
/// A message or a chat found by words (HitRow): what has them on its first line, the row's width (they bold, stroked
/// under); where it is (its chat) under it, who and when beside that.
fn hit_row(
  c : @ui.Ctx,
  key : String,
  id : Int,
  text : String,
  marks : Array[(Int, Int)],
  meta : String,
  under : String,
) -> Unit {
  let t = @sf.theme()
  c.box(style=found_hit_row, id~, fn() {
    c.box(style=found_line_22, fn() { @sf.found_line(c, key, text, marks, found_hit_words, t.p.text) }) |> ignore
    c.box(style=found_line_20, fn() {
      c.text(under, style=found_under) |> ignore
      if meta != "" {
        c.text(meta, style=found_meta) |> ignore
      }
    })
    |> ignore
    @motion.ripple(c, id, 0.0)
  })
  |> ignore
}

// ── a mouse's look (Switcher.css.ts) ───────────────────────────────────

///|
/// A heading (12, muted, 12 in, 10 over and 4 under).
// kept across runs: a value (no field of it changes)
let switcher_head : @ui.Style = @ui.css("w=Full px=S3 pt=S2_5 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let switcher_head_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// A row (Switcher.css.ts row): 38 high at least, 8 over and under and 12 in, its parts 10 apart, rounded as its panel's
/// corner leaves for it (concentric), a row's of the ladder's where it is in none (laid out Small, in the lists' box);
/// chosen, on the words' 7%.
// kept across runs: a value (no field of it changes)
let switcher_row : @ui.Style = @ui.style(
  row=true,
  w=Full,
  min_h=Fixed(switcher_row_h),
  px=S3,
  py=S2,
  gap=S2_5,
  align=ACenter,
  radius=InnerOr(@sf.row_radius),
  selected=@ui.patch(bg=Tint),
)

///|
// kept across runs: a value (no field of it changes)
let switcher_row_said : @ui.Style = switcher_row.then(@ui.css("align=AStart"))

///|
// kept across runs: a value (no field of it changes)
let switcher_picture : @ui.Style = @ui.css("w=S5 h=S5 align=ACenter justify=JCenter")

///|
let switcher_icon : Double = 16.0

///|
let switcher_logo : Double = 18.0

///|
// kept across runs: a value (no field of it changes)
let switcher_title : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let switcher_title_muted : @ui.TextStyle = switcher_title.then(@ui.text_style(color=Muted))

///|
// kept across runs: a value (no field of it changes)
let switcher_meta : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let switcher_said : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let switcher_said_head : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let switcher_found_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, max_lines=1, w=Full)

///|
// kept across runs: a value (no field of it changes)
let switcher_under : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let switcher_under_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, max_lines=1, w=Full)

///|
// kept across runs: a value (no field of it changes)
let switcher_none_box : @ui.Style = @ui.css("w=Full px=S3 py=S3_5")

///|
// kept across runs: a value (no field of it changes)
let switcher_none : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let switcher_note_box : @ui.Style = @ui.css("w=Full px=S3 pt=S2 pb=S2_5")

///|
// kept across runs: a value (no field of it changes)
let switcher_note : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, w=Full)

// ── a finger's look (mobile/Home.css.ts mFound…, Search.kt) ─────────────

///|
/// 查看更多 (MoreRow): 22 in, 10 over and under.
// kept across runs: a value (no field of it changes)
let found_more_row : @ui.Style = @ui.style(w=Full, pl=@sf.found_start, pr=S4, pt=S2_5, pb=S2_5)

///|
// kept across runs: a value (no field of it changes)
let found_link_words : @ui.TextStyle = @ui.text_style(size=Base, color=Link, wrap=false)

///|
/// 全部结果 (BackRow): 16 in, 10 over, 4 under; its chevron 4 before the words.
// kept across runs: a value (no field of it changes)
let found_back_row : @ui.Style = @ui.css("row w=Full pl=S4 pr=S4 pt=S2_5 pb=S1 gap=S1 align=ACenter")

///|
let found_chevron : Double = 16.0

///|
/// A line of quiet words (SearchNote): 22 in, 16 over and under.
// kept across runs: a value (no field of it changes)
let found_note_box : @ui.Style = @ui.style(w=Full, px=@sf.found_start, py=S4)

///|
// kept across runs: a value (no field of it changes)
let found_note_words : @ui.TextStyle = @ui.text_style(size=Base, color=Muted, w=Full)

///|
/// The stations still answering (WaitLine: 22 in, 12 over and under), one that could not be searched (6).
// kept across runs: a value (no field of it changes)
let found_wait_box : @ui.Style = @ui.style(w=Full, px=@sf.found_start, py=S3)

///|
// kept across runs: a value (no field of it changes)
let found_failing_box : @ui.Style = @ui.style(w=Full, px=@sf.found_start, py=S1_5)

///|
/// What the core says of the rest: 13 on 18.
// kept across runs: a value (no field of it changes)
let found_said_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Muted, w=Full)

///|
/// A message or a chat found by its words (HitRow): 66 high, 22 in on the left and 16 on the right.
// kept across runs: a value (no field of it changes)
let found_hit_row : @ui.Style = @ui.style(w=Full, h=@sf.found_row_h, pl=@sf.found_start, pr=S4, justify=JCenter)

///|
/// Something else found (ItemRow): 66 high with its line of words, 50 without; its icon 12 before what it is.
// kept across runs: a value (no field of it changes)
let found_item_row : @ui.Style = @ui.style(
  row=true,
  w=Full,
  h=@sf.found_row_h,
  pl=@sf.found_start,
  pr=S4,
  gap=S3,
  align=ACenter,
)

///|
// kept across runs: a value (no field of it changes)
let found_item_row_short : @ui.Style = found_item_row.then(@ui.style(h=@sf.found_row_short_h))

///|
// kept across runs: a value (no field of it changes)
let found_icon_box : @ui.Style = @ui.css("w=S5 h=S5 align=ACenter justify=JCenter")

///|
let found_icon : Double = 18.0

///|
// kept across runs: a value (no field of it changes)
let found_column : @ui.Style = @ui.style(w=@sf.grow, justify=JCenter)

///|
/// A row's lines: its first 22 high, the one under it 20; what is beside 8 apart.
// kept across runs: a value (no field of it changes)
let found_line_22 : @ui.Style = @ui.style(row=true, w=Full, h=@sf.found_line_h, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let found_line_20 : @ui.Style = @ui.css("row w=Full h=S5 gap=S2 align=ACenter")

///|
/// A hit's line: 15 on 22, one line cut at its end; an item's: 14 on 20.
// kept across runs: a value (no field of it changes)
let found_hit_words : @ui.TextStyle = @ui.text_style(size=Lg, leading=L7, color=Fg, max_lines=1, w=Full)

///|
// kept across runs: a value (no field of it changes)
let found_item_words : @ui.TextStyle = @ui.text_style(size=Base, leading=L6, color=Muted, max_lines=1, w=Full)

///|
/// Under a hit: where it is (its chat), 14 on 20, muted, one line.
// kept across runs: a value (no field of it changes)
let found_under : @ui.TextStyle = @ui.text_style(size=Base, leading=L6, color=Muted, wrap=false, w=@sf.grow)

///|
/// Who and when, beside it: 12, muted.
// kept across runs: a value (no field of it changes)
let found_meta : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// An item's title: 15 on 22, one line.
// kept across runs: a value (no field of it changes)
let found_title : @ui.TextStyle = @ui.text_style(size=Lg, leading=L7, color=Fg, wrap=false, w=@sf.grow)
