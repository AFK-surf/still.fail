// ⌘K (the web's Switcher.tsx ChatSwitcher and Finder, Switcher.css.ts): a panel high on the window over a scrim, the
// search on top (搜索全部内容和操作), under it what a few words find in the workspace (the core's `search`, docs/search.md:
// its chats, the messages that have them, what every station finds besides, each kind under its heading, a few of each;
// 查看更多 that kind alone, 全部结果 or Esc back to all) and what can be done here by its name (the core's
// `commands.find` of what the frame offers now). With nothing typed, the latest chats, then what can be done. ↑ / ↓
// choose, Enter or a press opens; Esc (in one kind's list: back to all of them) or a press outside closes it.

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
/// A line of the list (Switcher.tsx Found, and the headings between).
priv enum SwLine {
  Head(String)
  Back
  More(String)
  Command(Listed, Offered)
  Chat(FoundChat)
  Message(FoundMessage)
  Item(FoundItem)
}

///|
/// ⌘K as it stands: open; the kind looked at alone ("" every kind); the row chosen; its field and what is typed; the
/// search's view last read (kept while the next words are looked up); what was last asked of `commands.find`, and its
/// last answer with what it answered (kept, so the list opened again with the same words has it at once; for other
/// words none until the core has answered them, not what other words found).
priv struct Switching {
  mut open : Bool
  mut kind : String
  mut chosen : Int
  field : @ui.Field
  mut query : String
  mut kept : SearchView?
  mut kept_of : (Int, String, String)
  mut asked : String
  mut listed : Array[Listed]
  mut listed_for : String
}

///|
let switching : Switching = {
  open: false,
  kind: "",
  chosen: 0,
  field: @ui.Field::new(),
  query: "",
  kept: None,
  kept_of: (-1, "", ""),
  asked: "",
  listed: [],
  listed_for: "",
}

///|
fn switcher_reset() -> Unit {
  switching.open = false
  switcher_closed()
  switching.asked = ""
  switching.listed.clear()
  switching.listed_for = ""
}

///|
/// What one opening of it leaves behind, put back as it closes.
fn switcher_closed() -> Unit {
  switching.kind = ""
  switching.chosen = 0
  switching.query = ""
  switching.field.set("")
  switching.kept = None
  switching.kept_of = (-1, "", "")
}

///|
/// Whether ⌘K is open.
pub fn switcher_open() -> Bool {
  switching.open
}

///|
/// ⌘K pressed (the keymap's chat.switch): open, empty; open already, closed.
pub fn switcher_toggle(c : @ui.Ctx) -> Unit {
  if switching.open {
    c.blur()
  }
  switching.open = !switching.open
  switcher_closed()
}

///|
/// Esc: in one kind's list, back to all of them; else closed (its field let go: the keyboard goes nowhere until another
/// is pressed). Whether it took it (open).
pub fn switcher_escape(c : @ui.Ctx) -> Bool {
  if !switching.open {
    return false
  }
  if switching.kind != "" {
    switching.kind = ""
    switching.chosen = 0
  } else {
    switching.open = false
    switcher_closed()
    c.blur()
  }
  true
}

///|
/// Opened with `words` typed (a made-up run's start).
pub fn switcher_open_with(words : String) -> Unit {
  switching.open = true
  switcher_closed()
  switching.query = words
  switching.field.set(words)
}

///|
/// What of `offered` the core lists for `query` (`commands.find`: by name, id or other words, part by part; with nothing
/// typed all but what is only found by typing), each with its name; none until it has answered these words (what other
/// words found is not shown for them, nor picked by Enter). Asked once the frame is built, when what is asked changes.
fn switcher_commands(c : @ui.Ctx, src : Source, query : String, offered : Array[Offered]) -> Array[(Listed, Offered)] {
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
  if asked != switching.asked {
    c.after_build("switcher/commands.find", fn() {
      if switching.asked != asked {
        switching.asked = asked
        (src.call)("commands.find", params, fn(res) {
          match res {
            Ok(v) if switching.asked == asked => {
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
              switching.listed = listed
              switching.listed_for = asked
            }
            _ => ()
          }
        })
      }
    })
  }
  let out : Array[(Listed, Offered)] = []
  if switching.listed_for != asked {
    return out
  }
  for l in switching.listed {
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
/// the next is looked up.
fn switcher_search(src : Source, scope : String, query : String) -> SearchView? {
  let params : Map[String, Json] = { "scope": Json::string(scope), "query": Json::string(query) }
  if switching.kind != "" {
    params["kind"] = Json::string(switching.kind)
  }
  let topic = (src.topic)("search", params)
  match topic.value {
    Some(v) => {
      let of = (topic.version, query, switching.kind)
      if switching.kept_of != of || switching.kept is None {
        switching.kept = Some(search_view(v))
        switching.kept_of = of
      }
    }
    None => ()
  }
  switching.kept
}

///|
/// The list's lines as drawn (Finder): one kind alone, 全部结果 first; with words, what can be done first, then the chats
/// (查看更多 under them), with none the chats then what can be done; the messages (查看更多); each kind the stations
/// found under its heading (查看更多).
fn switcher_lines(
  view : SearchView?,
  typed : Bool,
  commands : Array[(Listed, Offered)],
) -> Array[SwLine] {
  let lines : Array[SwLine] = []
  let kind = switching.kind
  let actions = if kind != "" { [] } else { commands }
  let add_actions = fn() {
    for k, x in actions {
      if k == 0 || actions[k - 1].0.group != x.0.group {
        lines.push(Head(x.0.heading))
      }
      lines.push(Command(x.0, x.1))
    }
  }
  if kind != "" {
    lines.push(Back)
  }
  if typed {
    add_actions()
  }
  let chats = match view {
    Some(v) => v.chats
    None => []
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
    }
    _ => ()
  }
  lines
}

///|
/// A line picked (Enter, a press): a command done once the list is closed, a chat opened (a message at it, its words
/// marked), something else where the core says it opens; 查看更多 its kind alone, 全部结果 all again.
fn switcher_go(c : @ui.Ctx, line : SwLine) -> Unit {
  let words = match switching.kept {
    Some(v) => v.words
    None => []
  }
  let close = fn() {
    switching.open = false
    switcher_closed()
    c.blur()
  }
  match line {
    Head(_) => ()
    Back => {
      switching.kind = ""
      switching.chosen = 0
    }
    More(kind) => {
      switching.kind = kind
      switching.chosen = 1
    }
    Command(_, o) => {
      close()
      (o.run)()
    }
    Chat(ch) => {
      close()
      open_page(Chat({ station: ch.item.station, session: ch.item.session, title: ch.item.title, station_name: ch.item.station_name }))
    }
    Message(m) => {
      close()
      open_chat_found(chat_ref_of(m.chat), m.seq, words)
    }
    Item(it) => {
      close()
      open_found(it)
    }
  }
}

///|
/// ⌘K over the page (ChatSwitcher): over a scrim, 14% down the window, 560 wide at most (32 short of the window), 480
/// high at most (72% of the window); its search, then the list of what is found and what can be done, the row the keys
/// or the pointer chose lit. Drawn each frame; nothing while closed.
fn switcher(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  if !switching.open {
    switcher_closed()
    return
  }
  let scope = w.id
  let offered = switcher_offered(c, src)
  let t = @sf.theme()
  let query = switching.query.trim(chars=" ").to_string()
  let typed = query != ""
  let commands = switcher_commands(c, src, query, offered)
  let view = switcher_search(src, scope, query)
  let lines = switcher_lines(view, typed, commands)
  let picks : Array[Int] = []
  // each line's place among those chosen (-1 a heading's)
  let pick_of : Array[Int] = []
  for i, l in lines {
    if l is Head(_) {
      pick_of.push(-1)
    } else {
      pick_of.push(picks.length())
      picks.push(i)
    }
  }
  if switching.chosen >= picks.length() {
    switching.chosen = if picks.length() > 0 { picks.length() - 1 } else { 0 }
  }
  let mut keyed = false
  if c.key_pressed(@ui.key_code_down, in_field=true) && switching.chosen < picks.length() - 1 {
    switching.chosen += 1
    keyed = true
  }
  if c.key_pressed(@ui.key_code_up, in_field=true) && switching.chosen > 0 {
    switching.chosen -= 1
    keyed = true
  }
  // the list as tall as its lines (as much as the panel holds), scrolled to the line the keys chose
  let most = dmin(switcher_most_h, c.height * switcher_most_share)
  let est = lines.fold(init=0.0, fn(h, l) { h + switcher_line_h(l) })
  let list_h = dmin(most - switcher_panel_rest, est)
  if keyed {
    match picks.get(switching.chosen) {
      Some(k) => c.list_scroll_to("switcher/list", if k > switcher_lead { k - switcher_lead } else { 0 })
      None => ()
    }
  }
  let reading = match view {
    Some(v) => v.reading
    None => false
  }
  let note = match view {
    Some(v) if typed => [v.wait_text.unwrap_or(""), v.note.unwrap_or("")].filter(fn(w) { w != "" }).join(" · ")
    _ => ""
  }
  let panel = c.id("switcher")
  // what is typed as this frame takes it (its words in, Enter)
  let typed_now = Ref(switching.query)
  // mbui's layer over the page (modal: its scrim takes the presses outside, Tab stays in it; Esc, back or a press
  // outside dismiss it), the panel 14% down the window in its middle
  let o = c.overlay("switcher-layer", modal=true, scrim=t.p.overlay, initial_focus=0, fn() {
    // (as high as its search and its list, the list held to what the panel holds: list_h)
    let i = c.box(
      style=switcher_panel,
      bg=@sf.panel_ground(),
      shadow=@sf.dialog_shadow,
      shadow_y=@sf.dialog_shadow_y,
      shadow_color=t.p.shadow,
      id=panel,
      fn() {
        c.box(style=switcher_search_box, fn() {
          let res = c.editor(
            "switcher/field",
            placeholder=@sf.t("web-main.switcher.search"),
            font_size=switcher_search_size,
            line=switcher_search_line,
            max_lines=1,
            plain=true,
            color=t.p.text,
            placeholder_color=t.p.subtle,
            caret_color=t.p.accent,
            enter_sends=true,
            field=switching.field,
          )
          // (modal, its search the only field: it has the keys while it is open, the composer's given up as it opens)
          if !res.focused {
            c.focus_editor("switcher/field")
          }
          match res.submitted {
            // Enter: the words as they were (the field gives them up as it sends them), the line chosen opened
            Some(typed) => {
              switching.field.set(typed)
              typed_now.val = typed
              match picks.get(switching.chosen) {
                Some(k) => switcher_go(c, lines[k])
                None => ()
              }
            }
            None =>
              if res.text != switching.query {
                switching.query = res.text
                typed_now.val = res.text
                switching.chosen = if switching.kind != "" { 1 } else { 0 }
              }
          }
        })
        |> ignore
        if view is Some(_) && picks.length() == 0 && !reading {
          c.box(style=switcher_none_box, fn() {
            c.text(
              @sf.t(if typed { "web-main.switcher.noMatch" } else { "web-main.switcher.none" }),
              style=switcher_none,
            )
            |> ignore
          })
          |> ignore
        }
        c.list(
          "switcher/list",
          lines.length(),
          switcher_row_h,
          fn(i) {
            let line = lines[i]
            let key = "switcher/row/" + switcher_key(line)
            let k = pick_of[i]
            if k >= 0 {
              let id = c.id(key)
              c.cursor(id, Hand)
              if c.clicked(id) {
                switcher_go(c, line)
              }
              if c.lit(id) {
                switching.chosen = k
              }
              switcher_line(c, key, id, line, k == switching.chosen)
            } else {
              switcher_line(c, key, 0, line, false)
            }
          },
          h=Px(list_h),
        )
        |> ignore
        if note != "" {
          c.box(style=switcher_note_box, fn() { c.text(note, style=switcher_note) |> ignore }) |> ignore
        }
      },
    )
    c.place_by_size(i, fn(pw, _) { ((c.width - pw) / 2.0, c.height * switcher_top_share) })
  })
  // words changed in this frame: what they find and what can be done by them asked now, in the frame they came in
  // (whether Enter comes in the same frame or a later one, the core is asked the same)
  let now = typed_now.val.trim(chars=" ").to_string()
  if now != query {
    switcher_commands(c, src, now, offered) |> ignore
    switcher_search(src, scope, now) |> ignore
  }
  if o.dismissed is Some(_) {
    switching.open = false
    switcher_closed()
    c.blur()
  }
}

///|
/// A line drawn (Finder's rows): a heading small and muted; a command its icon, its name, its keys; a chat its picture,
/// its title, where and when (found by words its title shows late or not at all: that part first, its title under it);
/// a message what it says with the words, its chat under it; something else (ItemRow) what it is, where and when, its
/// line with the words.
fn switcher_line(c : @ui.Ctx, key : String, id : Int, line : SwLine, chosen : Bool) -> Unit {
  let t = @sf.theme()
  match line {
    Head(words) => c.box(style=switcher_head, fn() { c.text(words, style=switcher_head_words) |> ignore }) |> ignore
    _ => {
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
          Head(_) => ()
        }
      })
      |> ignore
    }
  }
}

///|
/// A line's key: what it is, so the pointer and the list keep it.
fn switcher_key(line : SwLine) -> String {
  match line {
    Head(w) => "h/" + w
    Back => "back"
    More(k) => "more/" + k
    Command(l, _) => "cmd/" + l.id
    Chat(ch) => "c/" + ch.item.station + "/" + ch.item.id
    Message(m) => "m/" + m.station + "/" + m.chat.session + "/" + m.seq.to_string()
    Item(it) => "i/" + it.key
  }
}

///|
/// A line's height, as the list first takes it: a heading 32 (12 and its 10 over and 4 under), a row 38, one of two
/// lines 54.
fn switcher_line_h(l : SwLine) -> Double {
  match l {
    Head(_) => switcher_head_h
    Message(_) | Item(_) => switcher_row_said_h
    Chat(ch) => if ch.found is Some(_) { switcher_row_said_h } else { switcher_row_h }
    _ => switcher_row_h
  }
}

///|
fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// The panel (Switcher.css.ts switcher): 14% down the window, 560 wide at most and 32 short of the window, 480 high at
/// most and 72% of the window; 12 in (EDGE), its corner from a row's (a pill 38 high 12 in: pillInner), a small panel's
/// ground and line, a deep shadow (0 24px 64px).
let switcher_top_share : Double = 0.14

///|
let switcher_most_h : Double = 480.0

///|
let switcher_most_share : Double = 0.72

///|
let switcher_edge : Double = 12.0

///|
let switcher_row_h : Double = 38.0

///|
let switcher_row_said_h : Double = 54.0

///|
let switcher_head_h : Double = 32.0

///|
// kept across runs: a value (no field of it changes)
let switcher_surface : @sf.Surface = @sf.surface(switcher_edge, @sf.pill_inner(switcher_edge, switcher_row_h))

///|
// kept across runs: a value (no field of it changes)
let switcher_panel : @ui.Style = switcher_surface
  .style()
  .then(
    @ui.style(w=Full, max_w=Fixed(switcher_w), border=B1, border_color=Line, clip=true),
  )

///|
let switcher_w : Double = 560.0

///|
/// What the panel holds besides its list: its search's 48, its 12 in at its top and foot, 4 over the list.
let switcher_panel_rest : Double = 76.0

///|
/// Lines kept over the one the keys chose as the list scrolls to it.
let switcher_lead : Int = 3

///|
/// The search (Switcher.css.ts search): 48 high, 12 in, the words a title's (16), the placeholder subtle.
// kept across runs: a value (no field of it changes)
let switcher_search_box : @ui.Style = @ui.css("row w=Full h=S12 px=S3 align=ACenter")

///|
let switcher_search_size : Double = 16.0

///|
let switcher_search_line : Double = 24.0

///|
/// A heading (Switcher.css.ts section): 12, muted, 12 in, 10 over and 4 under.
// kept across runs: a value (no field of it changes)
let switcher_head : @ui.Style = @ui.css("w=Full px=S3 pt=S2_5 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let switcher_head_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// A row (Switcher.css.ts row): 38 high at least, 8 over and under and 12 in (DIALOG_PAD less the panel's 12), its
/// parts 10 apart, rounded as the panel's corner leaves for it (inner); chosen, on the words' 7%.
// kept across runs: a value (no field of it changes)
let switcher_row : @ui.Style = @ui.style(
  row=true,
  w=Full,
  min_h=Fixed(switcher_row_h),
  px=S3,
  py=S2,
  gap=S2_5,
  align=ACenter,
  radius=switcher_surface.inner_radius(),
  selected=@ui.patch(bg=Tint),
)

///|
/// A row of two lines (a message, a chat found by its words, something else: Switcher.css.ts said): from its top.
// kept across runs: a value (no field of it changes)
let switcher_row_said : @ui.Style = switcher_row.then(@ui.css("align=AStart"))

///|
/// A picture's place (Switcher.css.ts picture): 20 square, what it holds in its middle.
// kept across runs: a value (no field of it changes)
let switcher_picture : @ui.Style = @ui.css("w=S5 h=S5 align=ACenter justify=JCenter")

///|
let switcher_icon : Double = 16.0

///|
/// A chat's picture: its maker's mark, 18 (ChatPicture's ModelLogo).
let switcher_logo : Double = 18.0

///|
/// A row's title (Switcher.css.ts title): the page's words (13), cut at its end.
// kept across runs: a value (no field of it changes)
let switcher_title : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let switcher_title_muted : @ui.TextStyle = switcher_title.then(@ui.text_style(color=Muted))

///|
/// What is said beside it (Switcher.css.ts meta): 12, muted.
// kept across runs: a value (no field of it changes)
let switcher_meta : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// A row of two lines' body (saidBody): its lines 2 apart; its first line (saidHead) what has the words and what is said
/// beside it, 10 apart.
// kept across runs: a value (no field of it changes)
let switcher_said : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let switcher_said_head : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let switcher_found_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, max_lines=1, w=Full)

///|
/// Its second line (saidText): muted, cut at its end.
// kept across runs: a value (no field of it changes)
let switcher_under : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let switcher_under_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, max_lines=1, w=Full)

///|
/// Nothing found (Switcher.css.ts none): 14 over and under, 12 in, the page's words muted.
// kept across runs: a value (no field of it changes)
let switcher_none_box : @ui.Style = @ui.css("w=Full px=S3 py=S3_5")

///|
// kept across runs: a value (no field of it changes)
let switcher_none : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted)

///|
/// What the list says under it (Switcher.css.ts note): the stations not answered yet, those offline or too old; 8 over,
/// 10 under, 12 in, 12 muted.
// kept across runs: a value (no field of it changes)
let switcher_note_box : @ui.Style = @ui.css("w=Full px=S3 pt=S2 pb=S2_5")

///|
// kept across runs: a value (no field of it changes)
let switcher_note : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, w=Full)

///|
/// What ⌘K offers of what the frame can do now (Switcher.tsx offered: the keys' actions it answers, and its own): the
/// open chat's (find, its services), the app's (a new chat, the sidebar, settings, the shortcuts), settings' pages (only
/// found by typing). The core names the keys' actions and finds what was typed among them (sfdesk/switcher.mbt).
fn switcher_offered(c : @ui.Ctx, src : Source) -> Array[Offered] {
  // an action's first keys as shown (as kept on this device: settings' 快捷键)
  let prefs = (src.topic)("prefs", {}).value
  let keys = fn(action : String) { @settings.key_label(prefs, action) }
  // the open chat's (ChatPage.tsx chat.find, chat.jobs)
  let all : Array[Offered] = match app.nav.top() {
    Chat(r) =>
      [
        {
          id: "chat.find",
          group: "",
          label: "",
          words: "",
          icon: "search",
          keys: keys("chat.find"),
          typed: false,
          run: fn() { chat_find_open(c, r) },
        },
        {
          id: "chat.jobs",
          group: "",
          label: "",
          words: "",
          icon: "web",
          keys: keys("chat.jobs"),
          typed: false,
          run: fn() { open_jobs_pop() },
        },
      ]
    _ => []
  }
  all.push({
    id: "chat.new",
    group: "",
    label: "",
    words: "",
    icon: "compose",
    keys: keys("chat.new"),
    typed: false,
    run: fn() { new_chat() },
  })
  all.push({
    id: "sidebar.toggle",
    group: "",
    label: "",
    words: "",
    icon: "panel-open",
    keys: keys("sidebar.toggle"),
    typed: false,
    run: fn() { sidebar_toggle() },
  })
  all.push({
    id: "settings",
    group: "",
    label: "",
    words: "",
    icon: "settings",
    keys: keys("settings"),
    typed: false,
    run: fn() { open_settings() },
  })
  all.push({
    id: "shortcuts",
    group: "",
    label: "",
    words: "",
    icon: "command",
    keys: keys("shortcuts"),
    typed: false,
    run: fn() { wide.keys_open = true },
  })
  let routes : Array[(String, @settings.Route, String)] = [
    ("appearance", @settings.Route::Appearance, @sf.t("web-pages.settings.nav.appearance")),
    ("notifications", @settings.Route::Notifications, @sf.t("web-pages.settings.nav.notifications")),
    ("permissions", @settings.Route::Permissions, @sf.t("web-pages.settings.nav.permissions")),
    ("archive", @settings.Route::Archiving, @sf.t("web-pages.archiving.title")),
    ("memory", @settings.Route::Memories, @sf.t("web-pages.settings.nav.memory")),
    ("security", @settings.Route::Security, @sf.t("web-pages.security.title")),
    ("vault", @settings.Route::Vault, @sf.t("web-pages.vault.title")),
    ("changelog", @settings.Route::Changelog, @sf.t("web-pages.settings.nav.changelog")),
    ("about", @settings.Route::About, @sf.t("web-pages.settings.nav.about")),
  ]
  for p in routes {
    let (key, route, label) = p
    all.push({
      id: "settings." + key,
      group: "settings",
      label,
      words: "",
      icon: "settings",
      keys: "",
      typed: true,
      run: fn() {
        open_settings_at(route)
      },
    })
  }
  all
}
