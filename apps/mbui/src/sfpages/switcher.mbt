// The search (ember web/src/Switcher.tsx Finder, Found; web/src/mobile/Home.tsx SearchPage, FoundRow, FoundChatRow,
// FoundItemRow; Switcher.css.ts, mobile/Home.css.ts mFound…): one in every tier, its words and what they find; where
// it sits is its frame's (⌘K's panel over the window, the phone's page over Home's list: sfdesk's switcher.mbt, sfapp's
// search.mbt). What a few words find in the workspace is the core's `search` (docs/search.md: its chats, the messages
// that have them, what every station finds besides, each kind under its heading, a few of each; 查看更多 that kind
// alone, 全部结果 back to all), and what can be done here by its name the core's `commands.find` of what the frame
// offers. With nothing typed, the latest chats where the frame says so (⌘K), then what can be done. One line for all it
// finds (its sizes the theme's: @sf.Found); where the screen has keys, ↑ / ↓ choose and Enter opens, a press anywhere.

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
/// The search as it stands: the kind looked at alone ("" every kind); the row chosen, and whether it is shown so (a
/// mouse's lines mark it; a finger's mark none, so its keyboard's search key opens nothing); its field and what is
/// typed; the view last read (kept while the next words are looked up) and whether reading it failed; what was last
/// asked of `commands.find`, its last answer and what it answered (kept: the list opened again with the same words has
/// it at once; for other words none until the core has answered them); the lines as last drawn (what Enter opens); the
/// list to go back to its top (into one kind or out of it).
priv struct Finder {
  mut kind : String
  mut chosen : Int
  mut chosen_shown : Bool
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
  chosen_shown: false,
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
/// Enter: the line chosen opened where it is shown chosen (`close` first, where the frame closes the search as one
/// opens).
pub fn finder_enter(close : () -> Unit) -> Unit {
  match finder.picks.get(finder.chosen) {
    Some(k) if finder.chosen_shown => finder_go(finder.lines[k], close)
    _ => ()
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
  let f = @sf.theme().chat_list
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
  // (chosen by the keys where the screen has them: shown so, Enter opens it)
  finder.chosen_shown = f.keys
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
  // (several stations: what is found says which it is on)
  let several = match (src.topic)("stations", { "scope": Json::string(w.id) }).value {
    Some(Array(a)) => a.length() > 1
    _ => false
  }
  let est = lines.fold(init=0.0, fn(h, l) { h + finder_h(l, f.found) })
  let h : @ui.Size = match most {
    Some(m) => Px(dmin(m, est))
    None => Fill(1.0)
  }
  c.list(
    key,
    lines.length(),
    f.found.row_h,
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
      // (the pointer over a line chooses it, as the keys do)
      if f.keys && c.lit(id) {
        finder.chosen = k
      }
      found_line(c, lk, id, line, f.keys && k == finder.chosen, several)
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
/// A line's height, as the list first takes it (the theme's: one line, two, a heading, quiet words).
fn finder_h(l : FindLine, f : @sf.Found) -> Double {
  match l {
    Head(_) => f.head_h
    Message(_) => f.two_h
    Item(it) => if it.text == "" { f.row_h } else { f.two_h }
    Chat(ch) => if ch.found is Some(_) { f.two_h } else { f.row_h }
    Note(_) | Wait(_, _) | Said(_) => f.quiet_h
    _ => f.row_h
  }
}

///|
/// What is not chosen: a kind's heading, none found, the stations still answering, what the core says.
fn quiet_line(c : @ui.Ctx, line : FindLine) -> Unit {
  let f = @sf.theme().chat_list.found
  match line {
    Head(words) => c.box(style=f.head, fn() { c.text(words, style=f.head_words) |> ignore }) |> ignore
    Note(words) => c.box(style=f.quiet, fn() { c.text(words, style=f.quiet_words) |> ignore }) |> ignore
    Wait(words, error) =>
      c.box(style=if error { f.wait_failing } else { f.wait }, fn() { @sf.wait_line(c, words, key="search", error~) })
      |> ignore
    Said(words) => c.box(style=f.wait, fn() { c.text(words, style=f.said_words) |> ignore }) |> ignore
    _ => ()
  }
}

///|
/// A line of what was found (Finder's rows, SearchPage's): its mark, then what it is, or the words found in it (they
/// bold, stroked under), with who, where and when at its end; where it is under that (its chat; an item's line with the
/// words) where it says one. A chat its agent's maker, a message its chat's; a station its mark; something else its
/// kind's icon; a command its icon, its keys at its end; 全部结果 and 查看更多 in the link's ink. `chosen`: by the keys,
/// on the words' tint; pressed, rippled where a finger presses. `several`: more than one station, so where is said.
fn found_line(c : @ui.Ctx, key : String, id : Int, line : FindLine, chosen : Bool, several : Bool) -> Unit {
  let t = @sf.theme()
  let f = t.chat_list.found
  let two = match line {
    Message(_) => true
    Item(it) => it.text != ""
    Chat(ch) => ch.found is Some(_)
    _ => false
  }
  let mark = fn(icon : String) {
    c.box(style=f.mark, fn() { @sf.icon(c, icon, size=f.icon, color=t.p.muted) |> ignore }) |> ignore
  }
  // a chat's picture (ChatPicture): its first agent's maker's mark
  let picture = fn(item : ChatItem) {
    match item.agents.get(0) {
      Some(a) => c.box(style=f.mark, fn() { @sf.maker_mark(c, a.maker, a.runtime, f.logo) |> ignore }) |> ignore
      None => mark("chat")
    }
  }
  // its words: the first line (`first`, with `meta` at its end), and under it `under` where there is one
  let words = fn(first : () -> Unit, meta : String, under : () -> Unit) {
    c.box(style=f.column, fn() {
      c.box(style=f.first, fn() {
        first()
        if meta != "" {
          c.text(meta, style=f.meta) |> ignore
        }
      })
      |> ignore
      under()
    })
    |> ignore
  }
  let at = fn(station : String) { if several { station } else { "" } }
  c.box(style=if two { f.two } else { f.row }, selected=chosen, id~, fn() {
    match line {
      Back => {
        mark("chevron-left")
        c.text(@sf.t("web-main.switcher.back"), style=f.link) |> ignore
      }
      More(_) => {
        mark("more")
        c.text(@sf.t("web-main.switcher.more"), style=f.link) |> ignore
      }
      Command(l, o) => {
        mark(o.icon)
        words(fn() { c.text(l.label, style=f.title) |> ignore }, o.keys, fn() {  })
      }
      Chat(ch) => {
        picture(ch.item)
        let meta = @sf.join_meta([
          if ch.archived { @sf.t("web-main.switcher.archived") } else { "" },
          at(ch.item.station_name),
          ch.item.ago,
        ])
        match ch.found {
          Some(found) =>
            words(fn() { @sf.found_line(c, "sw/" + key, found, ch.marks, f.words, t.p.text) }, meta, fn() {
              c.text(ch.item.title, style=f.under) |> ignore
            })
          None => words(fn() { c.text(ch.item.title, style=f.title) |> ignore }, meta, fn() {  })
        }
      }
      Message(m) => {
        picture(m.chat)
        words(fn() { @sf.found_line(c, "sw/" + key, m.text, m.marks, f.words, t.p.text) }, @sf.join_meta([m.by, m.ago]), fn() {
          c.text(m.chat.title, style=f.under) |> ignore
        })
      }
      Item(it) => {
        if it.kind == "station" {
          c.box(style=f.mark, fn() {
            @sf.station_mark(c, it.station_emoji, it.station_icon, f.icon, t.p.muted, none="server")
          })
          |> ignore
        } else {
          mark(if it.kind == "file" && it.dir { "folder" } else { @sf.kind_icon(it.kind) })
        }
        let meta = @sf.join_meta([if it.kind != "station" { at(it.station_name) } else { "" }, it.ago])
        words(fn() { c.text(it.title, style=f.title) |> ignore }, meta, fn() {
          if it.text != "" {
            @sf.found_line(c, "sw/i/" + key, it.text, it.marks, f.under_words, t.p.text)
          }
        })
      }
      Head(_) | Note(_) | Wait(_, _) | Said(_) => ()
    }
    @sf.row_ripple(c, id)
  })
  |> ignore
}
