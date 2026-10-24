// The chats' lists of the sidebar (ember web/src/Sidebar.tsx ChatPane, ChatRow, ArchiveButton; SidebarList.tsx
// NavTop; SidebarActions.tsx; RowPicture.tsx RowAside; Sidebar.css.ts navSession…): one of 全部, 我参与的, 监控中, its
// days under the frosted band (新建对话 and the filter), a row each: its mark before its title, where it stands or the
// last thing said under it, who is in it at that line's end; pointed at, its time there and 归档 at its top right;
// pressed, its chat beside the list; right clicked, its menu (the app's: sfapp's row_menu).

///|
/// One of the lists' lines.
priv enum SideItem {
  /// a day's (or a group's) heading
  Heading(String)
  Chat(ChatItem)
  /// the list's words in place of rows (none, failing)
  Words(String, Bool)
  /// no station at all: where to add one, its link to the stations
  NoStation
  /// rows to come, breathing
  Breathing
  /// room for the band over the list
  Top
  Foot
}

///|
/// One of the chats' lists (ChatPane): all of them, the viewer's or the watching ones, its days under the band.
fn chats_pane(c : @ui.Ctx, src : Source, w : Workspace, pages : Pages, filter : String) -> Unit {
  let key = "side/chats/" + w.id + "/" + filter
  let (view, error) = chats_of(src, w.id, filter)
  match view {
    Some(v) if filter == filter_of(src, w.id) => open_listed(v)
    _ => ()
  }
  let lines : Array[SideItem] = [Top]
  match view {
    None =>
      match error {
        Some(e) => lines.push(Words(e, true))
        None => lines.push(Breathing)
      }
    Some(v) => {
      let (reading, empty) = match v.note {
        Some(n) => (n.reading, n.empty)
        None => (false, false)
      }
      if v.days.length() == 0 && reading {
        lines.push(Breathing)
      }
      if v.days.length() == 0 && empty {
        let words = match filter {
          "mine" => @sf.t("web-main.sidebar.noneMine")
          "watching" => @sf.t("web-main.sidebar.noneWatching")
          _ => if v.stations > 0 { @sf.t("web-main.sidebar.none") } else { "" }
        }
        lines.push(if words == "" { NoStation } else { Words(words, false) })
      }
      // while the pointer is over the list or it moves, the rows keep their places (listMotion.ts useHeldOrder)
      for d in held_order(key, v.days, side_held(c, key) && !pin_moved(key, v.days)) {
        lines.push(Heading(d.label))
        for item in d.items {
          lines.push(Chat(item))
        }
      }
    }
  }
  lines.push(Foot)
  let lead = match view {
    Some(v) => v.leading
    None => "agents"
  }
  let open = match app.nav.top() {
    Chat(r) => Some(r)
    _ => None
  }
  // the rows and days move as the list changes (listMotion.ts useListMotion: by their keys)
  let keys = lines.map(side_line_key)
  let lid = @motion.list_keys(
    c,
    key,
    keys.filter(fn(k) { k.has_prefix("h/") || k.has_prefix("r/") }).map(fn(k) { key + "\u{1}" + k }),
    liftable=fn(k) { !k.contains("\u{1}h/") },
  )
  // (read now: the rows are made as the list is laid out, after the closed bar's drawing is over)
  let band = band_h(src, w)
  c.box(style=lists_fill, fn() {
    c.list(key, lines.length(), side_row_h, fn(i) {
      let n = c.box(style=lists_inset, fn() {
        match lines[i] {
          Heading(label) => nav_heading(c, label)
          Chat(item) => {
            let on = match open {
              Some(r) => r.station == item.station && (r.session == item.session || r.session == item.id)
              None => false
            }
            // 2 between it and a row under it, none before a day's heading (Sidebar.css.ts navSessionWrap + navSessionWrap)
            side_chat_row(c, src, pages, item, lead, on, i + 1 < lines.length() && lines[i + 1] is Chat(_))
          }
          Words(words, bad) => side_said(c, words, bad)
          // (Sidebar.tsx: the stations' page by its link)
          NoStation => side_said(c, "", false, stations=Some(fn() { go_place(pages, "stations") }))
          Breathing => side_breathing(c)
          // the band: its top row, 新建对话's (6 + 32 + 2), and 4 (navScroll's padding)
          Top => side_space(c, band + lists_top_in)
          Foot => side_space(c, lists_foot_in)
        }
      })
      match lines[i] {
        Heading(_) | Chat(_) => row_moving(c, lid, key, keys[i], n)
        _ => ()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A chat's row's height (Sidebar.css.ts navSession: 7, its title's 20, 2, its second line's 18, 7), the room over the
/// list under the band and at its foot (navScroll: 4, 12).
let side_row_h : Double = 54.0

///|
let lists_top_in : Double = 4.0

///|
let lists_foot_in : Double = 12.0

///|
/// How a row or a day's heading moves as the list changes (listMotion.ts useListMotion): from where it was to where it
/// is on motion.ts MOVE (a spring, 0.28 s, no bounce), carrying on from wherever it had got to; growing in where it is
/// when new (240 ms after 100, from 90% and nothing: its cubic-bezier(.2, .7, .2, 1)); one gone drawn where it was as it
/// shrinks to 90% and fades (LEAVE: 200 ms, ease-out), the rows after it closing over it; one going up past others over
/// them.
fn row_moving(c : @ui.Ctx, lid : Int, list : String, key : String, i : Int) -> Unit {
  @motion.layout(
    c,
    i,
    list + "\u{1}" + key,
    spec=@motion.move_spring,
    enter=@motion.trans(fade=0.0, scale=row_from, spec=row_enter),
    exit=@motion.trans(fade=0.0, scale=row_from, spec=row_leave),
  )
  if @motion.lifted(c, lid, list + "\u{1}" + key) >= 0.0 {
    c.put_over(i)
  }
}

///|
let row_from : Double = 0.9

///|
// kept across runs: a value (no field of it changes)
let row_enter : @motion.Spec = @motion.tween(row_enter_ms, ease=Out, delay=row_enter_after)

///|
// kept across runs: a value (no field of it changes)
let row_leave : @motion.Spec = @motion.tween(row_leave_ms, ease=CssOut)

///|
let row_enter_ms : Double = 240.0

///|
let row_enter_after : Double = 100.0

///|
let row_leave_ms : Double = 200.0

///|
/// A line's key among the list's (listMotion.ts: a row by its station and key, a day by its heading).
fn side_line_key(line : SideItem) -> String {
  match line {
    Heading(label) => "h/" + label
    Chat(item) => "r/" + @sfbase.row_name(item)
    Words(_, _) => "words"
    NoStation => "no-station"
    Breathing => "breathing"
    Top => "top"
    Foot => "foot"
  }
}

///|
/// Whether a row shown in list `key` was pinned or let go since: it moves at once, even while the list is held still
/// under the pointer (Sidebar.tsx pinMoved).
fn pin_moved(key : String, days : Array[ChatDay]) -> Bool {
  let was : Map[String, Bool] = {}
  for d in shown_days.get(key).unwrap_or([]) {
    for item in d.items {
      was[@sfbase.row_name(item)] = item.pinned == Some(true)
    }
  }
  for d in days {
    for item in d.items {
      match was.get(@sfbase.row_name(item)) {
        Some(p) if p != (item.pinned == Some(true)) => return true
        _ => ()
      }
    }
  }
  false
}

///|
/// Whether the list `key` keeps its rows where they are: the pointer over the sidebar (open, or shown a while), or
/// the list moving.
fn side_held(c : @ui.Ctx, key : String) -> Bool {
  let (px, _, _) = c.pointer()
  c.list_moving(key) ||
  (wide.peeking && px >= closed_bar_in + rail_closed_w && px < closed_bar_in + rail_closed_w + wide.side_w) ||
  (!wide.folded && px >= rail_w - side_into_rail && px < rail_w + wide.side_w)
}

///|
/// The band over the lists (SidebarList.tsx NavTop): its top row, then 新建对话 and the filter (SidebarActions.tsx),
/// then 待处理 where the rail has no bell; the sidebar's own ground at 72% over a 20px blur (Sidebar.css.ts band), the
/// closed bar's as it closes (moved with it).
fn lists_band(c : @ui.Ctx, src : Source, w : Workspace, pages : Pages) -> Unit {
  let t = @sf.theme()
  let filter = filter_of(src, w.id)
  let (view, _) = chats_of(src, w.id, "all")
  c.box(style=side_full, glass=@sf.glass_floating(tint=@sf.mix(closed_ground(), wide.band, t.p.sidebar)), fn() {
    side_top(c)
    // in the closed bar, what stands in its top right corner (the filter) 6 from its top and side, the band ending 6
    // under it (Sidebar.css.ts navNew, closed)
    let in_bar = wide.in_bar
    c.box(style=if in_bar { band_new_bar } else { band_new }, fn() {
      let is_new = app.nav.top() is NewChat
      c.box(style=side_full, fn() {
        if nav_row(c, "side/new", is_new, fn() {
            c.box(tx=-compose_in, fn() { @sf.icon(c, "compose", size=side_icon, color=t.p.muted) |> ignore }) |> ignore
            nav_words(c, @sf.t("web-main.sidebar.newChat"))
          }) {
          new_chat(pages)
        }
      })
      |> ignore
      match view {
        // (lit while it narrows the chats or another list is shown: 奏, 已归档)
        Some(v) if v.stations > 0 => filter_button(c, filter, list_place(list_mode(src, w)), list_mode(src, w) != 0, in_bar)
        _ => ()
      }
    })
    |> ignore
    // with no bell in the rail: 待处理 under 新建对话 (cloud/workspace.tsx SidebarTodo)
    side_todo(c, src, w)
  })
  |> ignore
}

///|
/// 新建对话's row and the filter beside it (Sidebar.css.ts navNew: 6 8 2, 4 apart; in the closed bar 6 from its side
/// and 6 under).
// kept across runs: a value (no field of it changes)
let band_new : @ui.Style = @ui.css("row w=Full pl=S2 pr=S2 pt=S1_5 pb=S0_5 gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let band_new_bar : @ui.Style = @ui.css("row w=Full pl=S2 pr=S1_5 pt=S1_5 pb=S1_5 gap=S1 align=ACenter")

///|
/// A row's icon (16), 新建对话's a pixel in (Sidebar.css.ts navCompose: aligned with the 14px check under it).
let side_icon : Double = 16.0

///|
let compose_in : Double = 1.0

///|
/// A new chat (新建对话, ⌘N): its page beside the list.
pub fn new_chat(pages : Pages) -> Unit {
  match app.nav.top() {
    NewChat => ()
    _ => {
      (pages.lower)()
      while app.nav.depth() > 1 {
        if !app.nav.pop() {
          break
        }
      }
      if app.nav.top() != Home {
        app.nav.replace(Home)
      }
      app.nav.push(NewChat)
    }
  }
}

///|
/// A chat's row pressed: its chat the page beside the list (in place of what was open), the list's place kept.
pub fn open_row(pages : Pages, item : ChatItem) -> Unit {
  let r : ChatRef = {
    station: item.station,
    session: item.session,
    title: item.title,
    station_name: item.station_name,
  }
  match app.nav.top() {
    Chat(open) if open.station == r.station && open.session == r.session => return
    _ => ()
  }
  (pages.lower)()
  wide.menu = None
  // the chats' place under it: settings or another place left for the chat
  if lit_place() != "chats" {
    while app.nav.depth() > 1 {
      if !app.nav.pop() {
        break
      }
    }
    app.nav.replace(Home)
    app.nav.push(Chat(r))
    return
  }
  if app.nav.depth() > 1 {
    app.nav.replace(Chat(r))
  } else {
    app.nav.push(Chat(r))
  }
}

///|
/// Room in a list, `h` high (for the band over it, at its foot).
fn side_space(c : @ui.Ctx, h : Double) -> Unit {
  c.box(style=@ui.style(h=Fixed(h)), fn() {  }) |> ignore
}

///|
/// What a list says in place of its rows (Sidebar.css.ts navEmpty): muted, or in red what went wrong; with
/// `stations`, where to add a station, its link going there.
fn side_said(c : @ui.Ctx, words : String, bad : Bool, stations? : (() -> Unit)? = None) -> Unit {
  let t = @sf.theme()
  c.box(style=side_said_box, fn() {
    match stations {
      Some(go) =>
        c.rich(
          [
            @ui.span(@sf.t("web-main.sidebar.noStation.before")),
            @ui.span(@sf.t("web-main.sidebar.noStation.link"), link="stations"),
            @ui.span(@sf.t("web-main.sidebar.noStation.after")),
          ],
          style=side_words,
          link_color=t.p.blue,
          on_link=fn(_) { go() },
        )
        |> ignore
      None => c.text(words, style=if bad { side_words_bad } else { side_words }) |> ignore
    }
  })
  |> ignore
}

///|
/// What a list says in place of its rows (Sidebar.css.ts navEmpty: 16 by 10 in, 13 on 20, muted; navError red).
// kept across runs: a value (no field of it changes)
let side_said_box : @ui.Style = @ui.css("w=Full px=S2_5 py=S4")

///|
// kept across runs: a value (no field of it changes)
let side_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, leading=L6)

///|
// kept across runs: a value (no field of it changes)
let side_words_bad : @ui.TextStyle = @ui.text_style(size=Sm, color=Danger, leading=L6)

///|
/// The list's filter (components.tsx MineFilter, compact): a 32 square, in the accent's ground while it narrows the
/// list or another list is shown (`narrowed`), its tip 筛选会话; pressed, its menu (filter_menu).
fn filter_button(c : @ui.Ctx, filter : String, shown : String, narrowed : Bool, in_bar : Bool) -> Unit {
  let t = @sf.theme()
  let id = c.id("side/filter")
  c.cursor(id, Hand)
  if c.clicked(id) {
    wide.filter_open = !wide.filter_open
    wide.menu = None
  }
  let narrowed = narrowed || filter != "all"
  // its ground and colour moved over 140 ms (page.css.ts iconBtn: transition background, color)
  let hot = @kit.animate(c, "side/filter/hover", if c.hovered(id) || wide.filter_open { 1.0 } else { 0.0 }, transition=nav_fade)
  let lit = @kit.animate(c, "side/filter/on", if narrowed { 1.0 } else { 0.0 }, transition=nav_fade)
  let ground = @sf.over(@sf.alpha(t.p.hover, hot * (1.0 - lit)), @sf.alpha(t.p.accent_bg, lit))
  // (in the closed bar's corner, concentric with it as the rail's places are: Sidebar.css.ts navNew, closed)
  let look = if in_bar { filter_box_bar } else { filter_box }
  let b = c.box(style=look.then(@ui.style(bg=Data(ground))), id~, fn() {
    @sf.icon(c, "filter", size=side_icon, color=@sf.mix(t.p.accent_text, lit, @sf.mix(t.p.text, hot, t.p.muted))) |> ignore
  })
  c.semantics(b, Button, id~, label=@sf.t("web-main.filter.chats.named", args=[("named", filter_named(shown))]))
  @sf.tip(c, "side/filter-tip", id, @sf.t("web-main.filter.chats"))
}

///|
/// The list shown (list_place), named (MineFilter `named`): 奏, 已归档, 我参与的, 监控中, else 全部.
fn filter_named(filter : String) -> String {
  match filter {
    "decisions" => @sf.t("web-main.decisions.title")
    "archive" => @sf.t("web-main.filter.archived")
    "mine" => @sf.t("web-main.filter.chats.mine")
    "watching" => @sf.t("web-main.filter.watching")
    _ => @sf.t("web-main.filter.all")
  }
}

///|
/// The filter's menu (components.tsx MineFilter's DropdownMenu, controls.css.ts chooserMenu): 全部会话, 我参与的, 监控中,
/// 奏, then 已归档, the list shown checked; under the button, its right edge under the button's, 6 below it. Chosen, that
/// list: 奏's and the archive's their page, a filter the chats' (from 奏 or the archive, back to the chats).
fn filter_menu(c : @ui.Ctx, src : Source, w : Workspace, pages : Pages) -> Unit {
  let shown = list_place(list_mode(src, w))
  let entries = [
    @kit.menu_radio("all", shown == "chats", label=@sf.t("web-main.filter.chats.all")),
    @kit.menu_radio("mine", shown == "mine", label=@sf.t("web-main.filter.chats.mine")),
    @kit.menu_radio("watching", shown == "watching", label=@sf.t("web-main.filter.watching")),
    @kit.menu_radio("decisions", shown == "decisions", label=@sf.t("web-main.decisions.title")),
    @kit.menu_separator(),
    @kit.menu_radio("archive", shown == "archive", label=@sf.t("web-main.filter.archived")),
  ]
  let m = @sf.menu(c, "filter-menu", wide.filter_open, c.id("side/filter"), entries, {}, @sf.chooser_menu_w, along=End)
  wide.filter_open = m.open
  match m.chosen {
    Some("decisions") => go_place(pages, "decisions")
    Some("archive") => rail_go(c, src, w, pages, "archive")
    Some(f) => rail_go(c, src, w, pages, if f == "all" { "chats" } else { f })
    None => ()
  }
}

///|
// kept across runs: a value (no field of it changes)
let filter_box : @ui.Style = @ui.css("w=S8 h=S8 radius=Xl align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let filter_box_bar : @ui.Style = @ui.style(w=S8, h=S8, radius=@sf.rail_corner, align=ACenter, justify=JCenter)

///|
/// A chat's row (Sidebar.tsx ChatRow): its state's mark before its title (500 while something in it is unread), its
/// station's mark, then where it stands or the last thing said, who is in it at the second line's end; pointed at, the
/// time in their place and 归档 at its top right; pressed, its chat beside the list; right clicked, its menu.
fn side_chat_row(
  c : @ui.Ctx,
  src : Source,
  pages : Pages,
  item : ChatItem,
  lead : String,
  on : Bool,
  more : Bool,
) -> Unit {
  let t = @sf.theme()
  let key = item.station + "/" + item.id
  let id = c.id("side/row/" + key)
  // what in it has a tip of its own (the state line's icon, the station's mark, the unplugged one): pointed at or
  // pressed, the row is
  let slot = c.id("side/lead/" + key)
  let kind = c.id("side/kind/" + key)
  let away = c.id("side/away/" + key)
  let archive = c.id("side/archive/" + key)
  // its state line (ChatMark.tsx WaitingText), the icon leading it in it
  let line = c.id("side/line/" + key)
  let parts = [id, slot, kind, away, line]
  c.cursor(id, Hand)
  if parts.iter().any(fn(p) { c.clicked(p) }) && wide.renaming != key {
    // pressed on its state line while the core says which message that is about, nothing in it unread: its chat goes
    // there as it opens (ChatMark.tsx jumpFromLine)
    match item.state_about {
      Some(seq) if (c.clicked(line) || c.clicked(slot)) && !item.unread && item.thread is Some(_) =>
        @sfbase.go_to({ station: item.station, session: item.session, title: item.title, station_name: item.station_name }, seq)
      _ => ()
    }
    open_row(pages, item)
  }
  let menu = item.offline is None && !item.pending
  // (right clicked, or held by a finger: Ctx::menu_asked, each part asked once)
  let asked = parts.fold(init=None, fn(at, p) { if at is Some(_) { at } else { c.menu_asked(p) } })
  match asked {
    Some((x, y)) if menu => {
      // (at a mouse's pointer; held by a finger, under the row, which it would cover, from the finger's way along it,
      // as the phone's row menu is)
      let (x, y) = match c.rect_of(id) {
        Some((_, ry, _, rh)) if @ui.pointing() is Finger => (x, ry + rh)
        _ => (x, y)
      }
      wide.menu = Some((key, item, x, y))
      wide.filter_open = false
      wide.attention_open = false
    }
    _ => ()
  }
  // its menu open (beside the pointer, not over the page: ContextMenu modal false), still pointed at while the pointer
  // stays on it; held open by a finger, lit while it is open (a lifted finger is nowhere)
  let menu_on = match wide.menu {
    Some((k, _, _, _)) if k == key && @ui.pointing() is Finger => true
    Some((k, _, _, _)) if k == key =>
      match c.rect_of(id) {
        Some((rx, ry, rw, rh)) => {
          let (px, py, _) = c.pointer()
          px >= rx && px < rx + rw && py >= ry && py < ry + rh
        }
        None => false
      }
    _ => false
  }
  let hover = parts.iter().any(fn(p) { c.hovered(p) }) || c.hovered(archive) || menu_on
  // its 归档 key while pointed at by a mouse; a finger holding it has its menu, 归档 in it (held, the row shows its
  // time in place of who is in it, as the phone's: mobile/Home.css.ts mRowAside `data-held`)
  let archive_key = hover && menu && @ui.pointing() is Mouse
  let pressed = parts.iter().any(fn(p) { c.pressed(p) })
  let ground = nav_ground(c, "side/row/" + key, hover || pressed, on)
  let offline = item.offline is Some(_)
  c.box(style=if more { side_row_more } else { side_row_last }, fn() {
    c.box(style=side_row.then(@ui.style(bg=Data(ground))), id~, fn() {
      c.box(style=if item.settled { side_text_settled } else { side_text }, fn() {
        c.box(style=if archive_key { side_head_room } else { side_head }, fn() {
          let tone = row_tone(item)
          if tone != "" {
            c.box(style=side_mark_slot, fn() { row_mark(c, key, tone) }) |> ignore
          }
          if wide.renaming == key {
            side_rename(c, src, item)
          } else {
            let title = if item.unread { side_title_unread } else { side_title }
            c.text(item.title, style=if offline { title.then(side_dim) } else { title }) |> ignore
          }
          // the station it runs on, by its mark (the core gives one only with several stations)
          if @sf.has_station_mark(item.station_emoji, item.station_icon) && wide.renaming != key {
            let b = c.box(style=side_kind, id=kind, fn() {
              @sf.station_mark(c, item.station_emoji, item.station_icon, side_kind_mark, if offline {
                t.p.subtle
              } else {
                t.p.muted
              })
            })
            // (a picture with its words, not a button of its own: the row is pressed through it)
            c.semantics(b, Image, id=kind, label=item.station_name)
            @sf.tip(c, "side/kind-tip/" + key, kind, item.station_name)
          }
          // pinned, renamed or archived, until the station answers: turning; failed, a red mark a few seconds more,
          // why on hover (the menu that asked has closed)
          match row_doing(src, item) {
            Some(why) =>
              c.box(style=side_kind, fn() {
                if why == "" {
                  @sf.spinner(c, size=side_kind_mark) |> ignore
                } else {
                  let mark = c.id("side/row-failed/" + key)
                  let b = c.box(id=mark, fn() { chat_mark(c, "alert") |> ignore })
                  c.semantics(b, Image, id=mark, label=why)
                  @sf.tip(c, "side/row-failed-tip/" + key, mark, why)
                }
              })
              |> ignore
            None => ()
          }
          // its station offline, or its link coming back: unplugged (the core says which, row by row); one that came
          // from elsewhere (Slack) says so
          match (item.offline, item.reconnecting) {
            (Some(why), _) | (None, Some(why)) => {
              let b = c.box(style=side_kind, id=away, fn() {
                @sf.icon(c, "unplug", size=side_kind_mark, color=t.p.subtle) |> ignore
              })
              c.semantics(b, Image, id=away, label=why)
              @sf.tip(c, "side/away-tip/" + key, away, why)
            }
            _ =>
              if item.connect {
                let said = if item.origin_text != "" { item.origin_text } else { "Slack" }
                let b = c.box(style=side_kind, id=away, fn() { @sf.slack_mark(c, side_kind_mark) |> ignore })
                c.semantics(b, Image, id=away, label=said)
                @sf.tip(c, "side/away-tip/" + key, away, said)
              }
          }
        })
        |> ignore
        c.box(style=if offline { side_meta.then(side_meta_dim) } else { side_meta }, fn() {
          let state = match item.state_text {
            Some(s) => Some(s)
            None => item.decision_text
          }
          match state {
            Some(s) =>
              c.box(style=side_state, id=line, fn() {
                state_line(
                  c,
                  "side/state/" + key,
                  slot,
                  s,
                  lead=item.state_lead,
                  lead_text=item.state_lead_text,
                  rest=item.state_rest,
                  alert=item.unsent,
                )
              })
              |> ignore
            None => c.text(item.last.unwrap_or(""), style=state_quiet) |> ignore
          }
          if hover {
            c.text(item.ago, style=side_time) |> ignore
          } else {
            side_aside(c, src, item, lead, on)
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    // 归档, at the row's top right while it is pointed at (Sidebar.css.ts rowArchive: 5 down, 6 in)
    if archive_key && wide.renaming != key {
      c.layer(fn() {
        c.box(style=side_archive_at, fn() {
          c.cursor(archive, Hand)
          if c.clicked(archive) {
            archive_row(c, src, item)
          }
          let b = c.box(style=side_archive, id=archive, fn() {
            @sf.icon(c, "archive", size=side_icon, color=if c.hovered(archive) { t.p.text } else { t.p.muted }) |> ignore
          })
          c.semantics(b, Button, id=archive, label=@sf.t("web-main.chat.archiveNamed", args=[("title", item.title)]))
          @sf.tip(c, "side/archive-tip/" + key, archive, @sf.t("web-main.chat.archive"))
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A chat's row (Sidebar.css.ts navRow, navSession): 54 high, 7 by 10 in, its words from the top, its corner the
/// nav's; its ground the pointer's, or the selected one's when its chat is beside the list (nav_ground).
// kept across runs: a value (no field of it changes)
let side_row : @ui.Style = @ui.style(
  row=true,
  w=Full,
  h=Fixed(side_row_h),
  px=S2_5,
  py=@sf.row_in,
  gap=S2,
  align=AStart,
  radius=Xl,
)

///|
/// Its two lines, 2 apart; faded with all its work over (navSessionText, the core's `settled`).
// kept across runs: a value (no field of it changes)
let side_text : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let side_text_settled : @ui.Style = @ui.css("w=Full gap=S0_5 opacity=O45")

///|
/// Its title's line (navSessionHead: 20 high, 6 apart); pointed at, room at its end for 归档 (24).
// kept across runs: a value (no field of it changes)
let side_head : @ui.Style = @ui.css("row w=Full h=S5 gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let side_head_room : @ui.Style = @ui.css("row w=Full h=S5 pr=S6 gap=S1_5 align=ACenter")

///|
/// The title's mark's column (navMarkSlot: 10, the mark in its middle).
// kept across runs: a value (no field of it changes)
let side_mark_slot : @ui.Style = @ui.css("w=S2_5 align=ACenter")

///|
/// The title (navSessionTitle: 13 on 20, as long as there is room; 500 while something in it is unread; offline at
/// half).
// kept across runs: a value (no field of it changes)
let side_title : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, leading=L6, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let side_title_unread : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, leading=L6, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let side_dim : @ui.TextStyle = @ui.text_style(color=A(Fg, O50))

///|
/// (its state line where the core says one: the words pressed for the message it is about)
// kept across runs: a value (no field of it changes)
let side_state : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
/// The second line (navSessionMeta: 18 high, 6 apart; offline at half).
// kept across runs: a value (no field of it changes)
let side_meta : @ui.Style = @ui.css("row w=Full h=S4_5 gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let side_meta_dim : @ui.Style = @ui.css("opacity=O50")

///|
/// When, in the aside's place while pointed at (navTime: 11, subtle).
// kept across runs: a value (no field of it changes)
let side_time : @ui.TextStyle = @ui.text_style(size=Xs2, color=Subtle, leading=L5, wrap=false)

///|
/// What stands at a row's title's end (Sidebar.css.ts sessionKind): a column 16 wide, its mark (12) in the middle.
// kept across runs: a value (no field of it changes)
let side_kind : @ui.Style = @ui.css("w=S4 align=ACenter")

///|
let side_kind_mark : Double = 12.0

///|
/// A chat's row in the list, 2 over the row under it (Sidebar.css.ts navSessionWrap + navSessionWrap: margin-top 2).
// kept across runs: a value (no field of it changes)
let side_row_more : @ui.Style = @ui.css("w=Full pb=S0_5")

///|
// kept across runs: a value (no field of it changes)
let side_row_last : @ui.Style = @ui.css("w=Full")

///|
/// 归档 at the row's top right (rowArchive: 5 down, 6 in, 24 square; page.css.ts iconBtn's corner, the pointer's
/// ground on it).
// kept across runs: a value (no field of it changes)
let side_archive_at : @ui.Style = @ui.css("w=Full pt=S1_25 pr=S1_5 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let side_archive : @ui.Style = @ui.css("w=S6 h=S6 radius=Lg align=ACenter justify=JCenter hovered{bg=Hover}")

///|
/// Who is in a chat at its row's second line's end, as the web's sidebar draws them (RowPicture.tsx RowAside, 16): its
/// agents' marks (a maker's once, 12 in a column 16 wide, 4 apart; past three, +N) and its people (16 round, each 3 over
/// the one before with a pixel of the row's ground round it; who started it, of more than one, ringed in ink a pixel
/// past that, over the others), those that lead first, 6 apart. `on`: the row is the page in view (its ground).
fn side_aside(c : @ui.Ctx, src : Source, item : ChatItem, lead : String, on : Bool) -> Unit {
  let groups = row_agent_groups(item)
  let people = item.people
  let with_people = people.length() > 0 && (lead == "people" || people.iter().any(fn(p) { !p.mine }))
  if groups.length() == 0 && !with_people {
    return
  }
  let agents = fn() {
    let said = item.agents.map(fn(a) { a.text }).filter(fn(s) { s != "" })
    c.box(style=side_aside_agents, label=said.join(@sf.t("web-main.list.separator")), fn() {
      for k, g in groups {
        if k < aside_most {
          c.box(style=side_aside_agent, fn() { @sf.maker_mark(c, g.maker, g.runtime, side_agent_mark) |> ignore })
          |> ignore
        }
      }
      if groups.length() > aside_most {
        c.text("+\{groups.length() - aside_most}", style=side_aside_more) |> ignore
      }
    })
    |> ignore
  }
  // (the row's ground round each face: the folded bar's, a floating panel's, when the list is in it)
  let ground = if on {
    side_face_on
  } else if wide.folded {
    side_face_bar
  } else {
    side_face_ground
  }
  let faces = fn() {
    let shown = if people.length() > aside_most { people[:aside_most].to_array() } else { people }
    c.box(style=side_aside_faces, label=item.people_text, fn() {
      for i, p in shown {
        let starter = people.length() > 1 && p.id == item.creator
        let slot = c.box(style=if i == 0 { side_face } else { side_face_after }, fn() {
          c.box(style=side_face, tx=if i == 0 { 0.0 } else { -side_face_over }, fn() {
            c.layer(fn() { c.box(style=ground, tx=-face_ring_in, ty=-face_ring_in, fn() {  }) |> ignore }) |> ignore
            let picture = if p.picture != "" { (src.picture)(p.picture, c.page_stint()) } else { "" }
            @sf.avatar(c, if p.email != "" { p.email } else { p.id }, p.name, picture, side_face_d)
            if starter {
              c.layer(fn() { c.box(style=side_face_ring, tx=-face_ring_out, ty=-face_ring_out, fn() {  }) |> ignore })
              |> ignore
            }
          })
          |> ignore
        })
        // who started it over the rest, a pixel more after it
        if starter {
          c.put_over(slot)
          c.box(style=side_face_gap, fn() {  }) |> ignore
        }
      }
      if people.length() > shown.length() {
        c.text("+\{people.length() - shown.length()}", style=side_aside_more) |> ignore
      }
    })
    |> ignore
  }
  c.box(style=side_aside_row, fn() {
    if lead == "people" {
      if with_people {
        faces()
      }
      if groups.length() > 0 {
        agents()
      }
    } else {
      if groups.length() > 0 {
        agents()
      }
      if with_people {
        faces()
      }
    }
  })
  |> ignore
}

///|
/// A face at a row's end: 16 across; 3 over the one before it (RowPicture.css.ts aside overlap(3)); its ground a pixel
/// round it, who started it ringed 2 out; three shown at most.
let side_face_d : Double = 16.0

///|
let side_face_over : Double = 3.0

///|
let face_ring_in : Double = 1.0

///|
let face_ring_out : Double = 2.0

///|
let aside_most : Int = 3

///|
/// An agent's mark at a row's end: 4 less than the faces (RowAside: size - 4).
let side_agent_mark : Double = 12.0

///|
/// What stands at a row's second line's end (RowPicture.css.ts aside, Sidebar.css.ts navSessionMeta): the agents and
/// the people 6 apart, each 2 in.
// kept across runs: a value (no field of it changes)
let side_aside_row : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let side_aside_agents : @ui.Style = @ui.css("row pl=S0_5 gap=S1 align=ACenter")

///|
/// An agent's mark in a column 16 wide and high (RowPicture.css.ts asideAgent).
// kept across runs: a value (no field of it changes)
let side_aside_agent : @ui.Style = @ui.css("w=S4 h=S4 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let side_aside_faces : @ui.Style = @ui.css("row pl=S0_5 align=ACenter")

///|
/// How many more than are shown (RowPicture.css.ts asideMore): 12, muted.
// kept across runs: a value (no field of it changes)
let side_aside_more : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// A face, 16 round; one after the first takes 13 (3 of it over the one before).
// kept across runs: a value (no field of it changes)
let side_face : @ui.Style = @ui.css("w=S4 h=S4")

///|
// kept across runs: a value (no field of it changes)
let side_face_after : @ui.Style = @ui.style(w=@sf.side_face_step, h=S4)

///|
/// The pixel after who started it (RowPicture.css.ts: marginRight 1).
// kept across runs: a value (no field of it changes)
let side_face_gap : @ui.Style = @ui.css("w=SPx h=S4")

///|
/// A pixel of the row's ground round a face (RowPicture.css.ts face: box-shadow 1px of --mark-around): the sidebar's,
/// the row in view's, the folded bar's (a floating panel's: shell.css.ts dock).
// kept across runs: a value (no field of it changes)
let side_face_ground : @ui.Style = @ui.css("w=S4_5 h=S4_5 radius=Full bg=Sidebar")

///|
// kept across runs: a value (no field of it changes)
let side_face_on : @ui.Style = @ui.css("w=S4_5 h=S4_5 radius=Full bg=Selected")

///|
// kept across runs: a value (no field of it changes)
let side_face_bar : @ui.Style = @ui.css("w=S4_5 h=S4_5 radius=Full bg=Surface")

///|
/// Who started it ringed in ink, a pixel of ground between: a line 1 wide from 1 to 2 out (RowPicture.css.ts
/// face[data-starter]::after).
// kept across runs: a value (no field of it changes)
let side_face_ring : @ui.Style = @ui.css("w=S5 h=S5 radius=Full border=B1 border_color=Fg")

///|
/// What its station has not answered yet of a chat's pin, rename or archive asked here (the core's `doing`, as
/// Sidebar.tsx's useDoingState): Some("") while under way, Some(why) a few seconds after it failed, else None.
fn row_doing(src : Source, item : ChatItem) -> String? {
  let mut out : String? = None
  for d in items((src.topic)("doing", {}).value, "doing") {
    let call = text(Some(d), "call")
    if call != "chat.pin" && call != "chat.rename" && call != "chat.archive" {
      continue
    }
    let p = field(Some(d), "params")
    if text(p, "station") != item.station || text(p, "session") != item.session {
      continue
    }
    // (the core always says why one failed)
    if text(Some(d), "stage") == "failed" && text(Some(d), "error") != "" {
      return Some(text(Some(d), "error"))
    }
    out = Some("")
  }
  out
}

///|
/// A row archived from the list (its 归档, its menu's): the chat beside the list goes to the one after it. One keeping
/// watch only once asked, in the core's words (its watch runs on in the archive).
pub fn archive_row(c : @ui.Ctx, src : Source, item : ChatItem) -> Unit {
  let run = fn() {
    match app.nav.top() {
      Chat(r) if r.station == item.station && (r.session == item.session || r.session == item.id) => {
        app.nav.pop() |> ignore
        wide.landed = ""
      }
      _ => ()
    }
    let params : Map[String, Json] = {
      "station": Json::string(item.station),
      "session": Json::string(item.session),
      "archived": Json::boolean(true),
    }
    match item.thread {
      Some(th) => params["thread"] = Json::number(th)
      None => ()
    }
    (src.call)("chat.archive", Json::object(params), fn(r) {
      match r {
        Ok(_) => say(c, @sf.t("web-main.chat.archived"))
        Err(e) => say(c, @sf.t("web-main.chat.archiveFailed", args=[("error", text(Some(e), "message"))]))
      }
    })
  }
  match item.watch_ask {
    Some(ask) =>
      @settings.confirm(@sf.t("android-chat.archive.ask", args=[("title", item.title)]), ask, @sf.t("android-chat.archive"), run)
    None => run()
  }
}
