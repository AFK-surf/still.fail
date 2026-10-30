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
/// found by typing; for one whose name the core words with something, the version an update goes to and the station
/// updated ("" none); its icon, its keys (a key's action's, as kept on this device), what it does.
pub(all) struct Offered {
  id : String
  label : String
  group : String
  words : String
  typed : Bool
  version : String
  station : String
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
  kept : @signals.Signal[SearchView?]
  kept_of : @signals.Signal[(Int, String, String)]
  failed : @signals.Signal[Bool]
  asked : @signals.Signal[String]
  listed : @sf.LiveArray[Listed]
  listed_for : @signals.Signal[String]
  lines : @signals.Signal[Array[FindLine]]
  picks : @signals.Signal[Array[Int]]
  mut to_top : Bool
  /// the `search` topic read last (its params), let go of as the next words are read or the search closes: one read
  /// and kept is shown to the core, which asks its stations again with each change of theirs (each a search of the
  /// machine's files there)
  mut held : Map[String, Json]?
}

///|
let finder : Finder = {
  kind: "",
  chosen: 0,
  chosen_shown: false,
  field: @ui.Field::new(),
  query: "",
  kept: @signals.signal(None),
  kept_of: @signals.signal((-1, "", ""), same=fn(a, b) { a == b }),
  failed: @signals.signal(false, same=fn(a, b) { a == b }),
  asked: @signals.signal("", same=fn(a, b) { a == b }),
  listed: @sf.LiveArray::new(),
  listed_for: @signals.signal("", same=fn(a, b) { a == b }),
  lines: @signals.signal([]),
  picks: @signals.signal([]),
  to_top: false,
  held: None,
}

///|
/// How the search read last is let go of as the search closes.
let finder_leave : Ref[(() -> Unit)?] = Ref::new(None)

///|
fn finder_reset() -> Unit {
  finder_cleared()
  finder.asked.set("")
  finder.listed.clear()
  finder.listed_for.set("")
}

///|
/// What one opening of the search leaves behind, put back as it closes (its frame says when).
pub fn finder_cleared() -> Unit {
  match finder_leave.val {
    Some(leave) => leave()
    None => ()
  }
  finder_leave.val = None
  finder.held = None
  finder.kind = ""
  finder.chosen = 0
  finder.query = ""
  finder.field.set("")
  // (as it is, nothing set: what is cleared as a page is built changes nothing it reads where it was clear)
  @signals.untracked(fn() {
    if finder.kept.get() is Some(_) {
      finder.kept.set(None)
    }
    if finder.lines.get().length() > 0 {
      finder.lines.set([])
    }
    if finder.picks.get().length() > 0 {
      finder.picks.set([])
    }
  })
  finder.kept_of.set((-1, "", ""))
  finder.failed.set(false)
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
  match finder.picks.get().get(finder.chosen) {
    Some(k) if finder.chosen_shown => finder_go(finder.lines.get()[k], close)
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
        if o.version != "" {
          m["version"] = Json::string(o.version)
        }
        if o.station != "" {
          m["station"] = Json::string(o.station)
        }
        Json::object(m)
      }),
    ),
  }
  let asked = params.stringify()
  if asked != finder.asked.get() {
    c.after_build("switcher/commands.find", fn() {
      if finder.asked.get() != asked {
        finder.asked.set(asked)
        (src.call)("commands.find", params, fn(res) {
          match res {
            Ok(v) if finder.asked.get() == asked => {
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
              finder.listed.replace(listed)
              finder.listed_for.set(asked)
            }
            _ => ()
          }
        })
      }
    })
  }
  if finder.listed_for.get() != asked {
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
  match finder.held {
    Some(before) if before != params => (src.leave)("search", before)
    _ => ()
  }
  finder.held = Some(params)
  finder_leave.val = Some(fn() { (src.leave)("search", params) })
  let topic = (src.topic)("search", params)
  finder.failed.set(topic.error is Some(_))
  match topic.value {
    Some(v) => {
      let of = (topic.version, query, finder.kind)
      if finder.kept_of.get() != of || finder.kept.get() is None {
        finder.kept.set(Some(search_view(v)))
        finder.kept_of.set(of)
      }
    }
    None => ()
  }
  finder.kept.get()
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
  if typed && view is None && finder.failed.get() {
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
  let words = match finder.kept.get() {
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
/// stays under the chat). ↑ / ↓ choose a line; a line says who, where and when under its words where the box it is
/// drawn into is narrow (found_stacked). `at`: where its list stands (a panel's, ⌘K's, as a side column's; the
/// phone's search across the whole screen), its lines in and rounded so.
pub fn finder_list(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  offered : Array[Offered],
  close : () -> Unit,
  idle_chats? : Bool = false,
  most? : Double,
  at? : @sf.ListAt = Side,
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
  finder.lines.set(lines)
  finder.picks.set(picks)
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
  let stacked = found_stacked(c.width)
  let est = lines.fold(init=0.0, fn(h, l) { h + finder_h(l, f.found, stacked) })
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
        quiet_line(c, line, at)
        return
      }
      let id = c.id(lk)
      if c.clicked(id) {
        finder_go(line, close)
      }
      // (the pointer over a line chooses it, as the keys do)
      if f.keys && c.hand_on(id) {
        finder.chosen = k
      }
      found_line(c, lk, id, line, f.keys && k == finder.chosen, several, at, stacked)
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
/// A line's height, as the list first takes it (the theme's: one line, two, a heading, quiet words; `stacked`: who,
/// where and when under its words, two).
fn finder_h(l : FindLine, f : @sf.Found, stacked : Bool) -> Double {
  match l {
    Head(_) => f.head_h
    Message(_) => f.two_h
    Item(it) => if it.text == "" && !stacked { f.row_h } else { f.two_h }
    Chat(ch) => if ch.found is Some(_) || stacked { f.two_h } else { f.row_h }
    Note(_) | Wait(_, _) | Said(_) => f.quiet_h
    _ => f.row_h
  }
}

///|
/// What is not chosen: a kind's heading, none found, the stations still answering, what the core says.
fn quiet_line(c : @ui.Ctx, line : FindLine, at : @sf.ListAt) -> Unit {
  let f = @sf.theme().chat_list.found
  let inn = @sf.found_line_in(at)
  match line {
    Head(words) =>
      c.box(style=f.head.then(@sf.found_head_in(at)), fn() { c.text(words, style=f.head_words) |> ignore }) |> ignore
    Note(words) => c.box(style=f.quiet.then(inn), fn() { c.text(words, style=f.quiet_words) |> ignore }) |> ignore
    Wait(words, error) =>
      c.box(style=(if error { f.wait_failing } else { f.wait }).then(inn), fn() {
        @sf.wait_line(c, words, key="search", error~)
      })
      |> ignore
    Said(words) => c.box(style=f.wait.then(inn), fn() { c.text(words, style=f.said_words) |> ignore }) |> ignore
    _ => ()
  }
}

///|
/// A line of what was found (Finder's rows, SearchPage's): its mark, then what it is, or the words found in it (they
/// bold, stroked under), with who, where and when at its end; where it is under that (its chat; an item's line with the
/// words) where it says one. A chat its agent's maker, a message its chat's; a station its mark; something else its
/// kind's icon; a command its icon, its keys at its end; 全部结果 and 查看更多 in the link's ink. `chosen`: by the keys,
/// on the words' tint; pressed, rippled where a finger presses. `several`: more than one station, so where is said.
/// `list_at`: where its list stands, the line in and rounded so (@sf.found_row_in). `narrow`: its list too narrow for
/// who, where and when beside its words (found_stacked).
fn found_line(
  c : @ui.Ctx,
  key : String,
  id : Int,
  line : FindLine,
  chosen : Bool,
  several : Bool,
  list_at : @sf.ListAt,
  narrow : Bool,
) -> Unit {
  let t = @sf.theme()
  let f = t.chat_list.found
  // who, where and when (`meta`), said at the end of its words
  let meta_all : Array[String] = match line {
    Chat(ch) =>
      [
        if ch.archived { @sf.t("web-main.switcher.archived") } else { "" },
        if several { ch.item.station_name } else { "" },
        ch.item.ago,
      ]
    Message(m) => [m.by, m.ago]
    Item(it) => [if it.kind != "station" && several { it.station_name } else { "" }, it.ago]
    _ => []
  }
  let parts = meta_all.filter(fn(p) { p != "" })
  let meta = @sf.join_meta(parts)
  // where the line is narrow, who, where and when go under its words, its first line all theirs (found_stacked)
  let stacked = meta != "" && narrow
  let two = stacked ||
    (match line {
      Message(_) => true
      Item(it) => it.text != ""
      Chat(ch) => ch.found is Some(_)
      _ => false
    })
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
  // its words: the first line (`first`), and under it `under` where there is one; who, where and when (`meta`) at the
  // first line's end where the line is wide enough to leave the words theirs, else at the end of the line under it,
  // beside where it is (`stacked`)
  let words = fn(first : () -> Unit, meta : String, under : () -> Unit) {
    let said = fn() {
      if meta != "" && stacked && parts.length() > 1 && meta == @sf.join_meta(parts) {
        // (beside where it is, who and where leave the line before its name is cut to fewer than four of its
        // size; when stays)
        for i, part in parts {
          if i + 1 < parts.length() {
            c.box(drop=1, fn() { c.text(part + " ·", style=f.meta) |> ignore }) |> ignore
          } else {
            c.text(part, style=f.meta) |> ignore
          }
        }
      } else if meta != "" {
        c.text(meta, style=f.meta) |> ignore
      }
    }
    c.box(style=f.column, fn() {
      c.box(style=f.first, fn() {
        first()
        if !stacked {
          said()
        }
      })
      |> ignore
      if stacked {
        c.box(style=f.second, fn() {
          under()
          said()
        })
        |> ignore
      } else {
        under()
      }
    })
    |> ignore
  }
  c.box(style=(if two { f.two } else { f.row }).then(@sf.found_row_in(list_at)), selected=chosen, id~, fn() {
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
        match ch.found {
          Some(found) =>
            words(fn() { @sf.found_line(c, "sw/" + key, found, ch.marks, f.words, t.p.text) }, meta, fn() {
              @sf.name_words(c, ch.item.title, f.under) |> ignore
            })
          None => words(fn() { @sf.name_words(c, ch.item.title, f.title) |> ignore }, meta, fn() {  })
        }
      }
      Message(m) => {
        picture(m.chat)
        words(fn() { @sf.found_line(c, "sw/" + key, m.text, m.marks, f.words, t.p.text) }, meta, fn() {
          @sf.name_words(c, m.chat.title, f.under) |> ignore
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
        words(fn() { @sf.name_words(c, it.title, f.title) |> ignore }, meta, fn() {
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

///|
/// Narrower than this, a line says who, where and when under its first line (beside where it is, where it says one):
/// its first line all its words' (a chat's title, the words found), one line or two (as a file's row puts its size and
/// time under its name narrower than its row_stack_below).
let found_stack_below : Double = 440.0

///|
/// Whether a line in a list `width` wide says who, where and when under its words.
fn found_stacked(width : Double) -> Bool {
  width < found_stack_below
}
