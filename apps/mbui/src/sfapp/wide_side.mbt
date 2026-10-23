// The wide frame's sidebar (ember web/src/Sidebar.tsx, SidebarList.tsx, Sidebar.css.ts; cloud/workspace.tsx's
// FilesSidebar, cloud/settings.tsx SettingsNav, DecisionDesk.tsx DecisionRows): a frosted band at its top (in a window
// with its buttons in the app's top row, their row first, dragging the window) with the list's action, the list
// under it. Which list follows the place: the chats' (新建对话 and the filter, the days, a row each), the settings'
// pages, the folders each station lends, the decisions waiting (奏).

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
/// The sidebar `width` wide (its 8 at the left over the rail's empty side): what the place lists.
fn sidebar(c : @ui.Ctx, src : Source, w : Workspace, width : Double) -> Unit {
  match lit_place() {
    "settings" => settings_side(c, src, w)
    "files" => files_side(c, src, w)
    "stations" => stations_side(c, src, w)
    "profiles" => profiles_side(c, src, w)
    // the chats' lists, 奏 and 已归档 among them (wide_lists.mbt)
    _ => lists_side(c, src, w, width)
  }
}

///|
/// The band's first row (Sidebar.css.ts brand): beside the rail only a margin (8); in a window with its buttons in the
/// app's top row, their row (44), which drags the window.
fn side_top(c : @ui.Ctx) -> Unit {
  let id = c.id("side/top")
  if @ui.window_inset() && !wide.folded {
    c.window_drag(id)
  }
  c.box(w=Fill(1.0), h=Px(side_top_h()), id~, fn() {  }) |> ignore
}

///|
/// The band's first row's height: the window's buttons' row (44) where they are in the app's top row, else a margin
/// (8); none in the closed bar, which starts under that row (Sidebar.css.ts brand, closed): as far on its way as the
/// block is (moved with it, brand.tsx moveSidebar).
fn side_top_h() -> Double {
  (if @ui.window_inset() { side_top_inset } else { side_top_web }) * (1.0 - rail_ws.fold_e)
}

///|
let side_top_inset : Double = 44.0

///|
let side_top_web : Double = 8.0

///|
/// A row of a sidebar's list (Sidebar.css.ts navRow): 32 high at least, 6 by 10 in, its corner the nav's; the
/// pointer's ground on hover, the selected one's ground when it is the page in view. True on the frame after a press.
fn nav_row(
  c : @ui.Ctx,
  key : String,
  on : Bool,
  body : () -> Unit,
  pady? : Double = 6.0,
  align? : @ui.Align = ACenter,
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.cursor(id, Hand)
  c.box(
    dir=Row,
    w=Fill(1.0),
    min_h=32.0,
    padx=10.0,
    pady~,
    gap=8.0,
    align~,
    radius=12.0,
    bg=nav_ground(c, key, c.hovered(id) || c.pressed(id), on),
    id~,
    body,
  )
  |> ignore
  c.clicked(id)
}

///|
/// A row's or a place's ground as the web moves it (Sidebar.css.ts navRow, Rail.css.ts item: `transition: background
/// 140ms` ease out): the pointer's ground in and out, the lit one's, as the state changes.
fn nav_ground(c : @ui.Ctx, key : String, hover : Bool, on : Bool) -> Int64 {
  let t = @sf.theme()
  let h = @kit.animate(c, key + "/hover", if hover { 1.0 } else { 0.0 }, transition=nav_fade)
  let o = @kit.animate(c, key + "/on", if on { 1.0 } else { 0.0 }, transition=nav_fade)
  if h <= 0.0 && o <= 0.0 {
    0L
  } else {
    @sf.over(@sf.alpha(t.p.hover, h * (1.0 - o)), @sf.alpha(t.p.selected, o))
  }
}

///|
/// What a state's ground changes over (vars.dur: 140 ms, ease out).
// kept across runs: a value (no field of it changes)
let nav_fade : @motion.Spec = @motion.tween(@sf.dur_ms, ease=Out)

///|
/// A heading over a part of a list (Sidebar.css.ts navHeading): 12 on 18, muted, 14 above, 4 under.
fn nav_heading(c : @ui.Ctx, label : String) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), pl=8.0, pr=8.0, pt=14.0, pb=4.0, fn() {
    c.text(label, size=12.0, color=t.p.muted, wrap=false, line=18.0) |> ignore
  })
  |> ignore
}

///|
/// A row's words, 13 on 20, as long as there is room.
fn nav_words(c : @ui.Ctx, words : String, color? : Int64, weight? : Int = 400) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), fn() {
    c.text(words, size=13.0, weight~, color=color.unwrap_or(t.p.text), wrap=false, line=20.0)
    |> ignore
  })
  |> ignore
}

// ── the chats ───────────────────────────────────────────────────────────

///|
/// One of the chats' lists (ChatPane): all of them, the viewer's or the watching ones, its days under the band.
fn chats_pane(c : @ui.Ctx, src : Source, w : Workspace, filter : String) -> Unit {
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
          "mine" => tr("web-main.sidebar.noneMine")
          "watching" => tr("web-main.sidebar.noneWatching")
          _ => if v.stations > 0 { tr("web-main.sidebar.none") } else { "" }
        }
        lines.push(if words == "" { NoStation } else { Words(words, false) })
      }
      // while the pointer is over the list or it moves, the rows keep their places (listMotion.ts useHeldOrder,
      // Home's held_order)
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
  // the rows and days move as the list changes (listMotion.ts useListMotion: by their keys, as Home's)
  let keys = lines.map(side_line_key)
  let lid = @motion.list_keys(
    c,
    key,
    keys.filter(fn(k) { k.has_prefix("h/") || k.has_prefix("r/") }).map(fn(k) { key + "\u{1}" + k }),
    liftable=fn(k) { !k.contains("\u{1}h/") },
  )
  // (read now: the rows are made as the list is laid out, after the closed bar's drawing is over)
  let band = band_h(src, w)
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    c.list(key, lines.length(), 54.0, fn(i) {
      let n = c.box(w=Fill(1.0), padx=8.0, fn() {
        match lines[i] {
          Heading(label) => nav_heading(c, label)
          Chat(item) => {
            let on = match open {
              Some(r) => r.station == item.station && (r.session == item.session || r.session == item.id)
              None => false
            }
            // 2 between it and a row under it, none before a day's heading (Sidebar.css.ts navSessionWrap + navSessionWrap)
            side_chat_row(c, src, item, lead, on, i + 1 < lines.length() && lines[i + 1] is Chat(_))
          }
          Words(words, bad) => side_said(c, words, bad)
          // (Sidebar.tsx: the stations' page by its link)
          NoStation => side_said(c, "", false, stations=Some(fn() { rail_go(c, src, w, "stations") }))
          Breathing => side_breathing(c)
          // the band: its top row, 新建对话's (6 + 32 + 2), and 4
          Top => side_space(c, band + 4.0)
          Foot => side_space(c, 12.0)
        }
      })
      match lines[i] {
        Heading(_) | Chat(_) => moving(c, lid, key, keys[i], n)
        _ => ()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A line's key among the list's (listMotion.ts: a row by its station and key, a day by its heading).
fn side_line_key(line : SideItem) -> String {
  match line {
    Heading(label) => "h/" + label
    Chat(item) => "r/" + row_name(item)
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
      was[row_name(item)] = item.pinned == Some(true)
    }
  }
  for d in days {
    for item in d.items {
      match was.get(row_name(item)) {
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
  (rail_ws.peeking && px >= closed_bar_in + rail_closed_w && px < closed_bar_in + rail_closed_w + wide.side_w) ||
  (!wide.folded && px >= rail_w - 8.0 && px < rail_w + wide.side_w)
}

///|
/// The band over the lists (NavTop): its top row, then 新建对话 and the filter; the sidebar's own ground at 72% over a
/// 20px blur (Sidebar.css.ts band), not the page's paper.
fn lists_band(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let filter = filter_of(src, w.id)
  let (view, _) = chats_of(src, w.id, "all")
  // (in the closed bar, its ground the bar's: shell.css.ts dock, closed, sets the sidebar's ground to a panel's)
  // (its ground the block's: shell.css.ts dock, closed, a panel's; moved with it)
  c.box(w=Fill(1.0), glass=@sf.glass_floating(tint=@sf.mix(closed_ground(), rail_ws.fold_e, t.p.sidebar)), fn() {
    side_top(c)
    // in the closed bar, what stands in its top right corner (the filter) 6 from its top and side, the band ending 6
    // under it (Sidebar.css.ts navNew, closed)
    let in_bar = rail_ws.in_bar
    c.box(
      dir=Row,
      w=Fill(1.0),
      pl=8.0,
      pr=if in_bar { bar_band_in } else { 8.0 },
      pt=6.0,
      pb=if in_bar { bar_band_in } else { 2.0 },
      gap=4.0,
      align=ACenter,
      fn() {
      let is_new = app.nav.top() is NewChat
      c.box(w=Fill(1.0), fn() {
        if nav_row(c, "side/new", is_new, fn() {
            c.box(tx=-1.0, fn() { @sf.icon(c, "compose", size=16.0, color=t.p.muted) |> ignore })
            |> ignore
            nav_words(c, tr("web-main.sidebar.newChat"))
          }) {
          new_chat_wide()
        }
      })
      |> ignore
      match view {
        // (lit while it narrows the chats or another list is shown: 奏, 已归档)
        Some(v) if v.stations > 0 => filter_button(c, filter, list_mode(src, w) != 0, in_bar)
        _ => ()
      }
    },
    )
    |> ignore
    // with no bell in the rail: 待处理 under 新建对话 (cloud/workspace.tsx SidebarTodo)
    side_todo(c, src, w)
  })
  |> ignore
}

///|
/// Room in a list, `h` high (for the band over it, at its foot).
fn side_space(c : @ui.Ctx, h : Double) -> Unit {
  c.box(h=Px(h), fn() {  }) |> ignore
}

///|
/// What a list says in place of its rows (Sidebar.css.ts navEmpty): muted, or in red what went wrong; with
/// `stations`, where to add a station, its link going there.
fn side_said(c : @ui.Ctx, words : String, bad : Bool, stations? : (() -> Unit)? = None) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), padx=10.0, pt=16.0, pb=16.0, fn() {
    match stations {
      Some(go) =>
        c.rich(
          [
            @ui.span(tr("web-main.sidebar.noStation.before")),
            @ui.span(tr("web-main.sidebar.noStation.link"), link="stations"),
            @ui.span(tr("web-main.sidebar.noStation.after")),
          ],
          style=side_words,
          link_color=t.p.blue,
          on_link=fn(_) { go() },
        )
        |> ignore
      None => c.text(words, size=13.0, color=if bad { t.p.red } else { t.p.muted }, line=20.0) |> ignore
    }
  })
  |> ignore
}

///|
/// The list's filter (components.tsx MineFilter, compact): a 32 square, in the accent's ground while it narrows the
/// list or another list is shown (`narrowed`); pressed, its menu.
fn filter_button(c : @ui.Ctx, filter : String, narrowed : Bool, in_bar : Bool) -> Unit {
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
  c.box(
    w=Px(32.0),
    h=Px(32.0),
    // in the closed bar's corner, concentric with it as the rail's places are (9)
    radius=if in_bar { rail_ground_r } else { 12.0 },
    align=ACenter,
    justify=JCenter,
    bg=@sf.over(@sf.alpha(t.p.hover, hot * (1.0 - lit)), @sf.alpha(t.p.accent_bg, lit)),
    id~,
    fn() {
      @sf.icon(c, "filter", size=16.0, color=@sf.mix(t.p.accent_text, lit, @sf.mix(t.p.text, hot, t.p.muted))) |> ignore
    },
  )
  |> ignore
}

///|
/// Rows to come, breathing (Waiting shape rows, dense).
fn side_breathing(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  let breath = @sf.breath(c)
  c.box(w=Fill(1.0), pt=8.0, gap=12.0, padx=10.0, fn() {
    for k in 0..<6 {
      c.box(w=Fill(1.0), gap=6.0, opacity=breath, fn() {
        c.box(w=Px(if k % 2 == 0 { 120.0 } else { 150.0 }), h=Px(12.0), radius=6.0, bg=t.p.neutral_bg, fn() {  })
        |> ignore
        c.box(w=Px(180.0), h=Px(10.0), radius=5.0, bg=t.p.neutral_bg, fn() {  }) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A chat's row (Sidebar.tsx ChatRow): its state's mark before its title (500 while something in it is unread), its
/// station's mark, then where it stands or the last thing said, who is in it at the second line's end; pointed at, the
/// time in their place and 归档 at its top right; pressed, its chat beside the list; right clicked, its menu.
fn side_chat_row(c : @ui.Ctx, src : Source, item : ChatItem, lead : String, on : Bool, more : Bool) -> Unit {
  let t = @sf.theme()
  let key = item.station + "/" + item.id
  let id = c.id("side/row/" + key)
  c.cursor(id, Hand)
  if c.clicked(id) && wide.renaming != key {
    open_row(item)
  }
  let menu = item.offline is None && !item.pending
  match c.right_clicked(id) {
    Some((x, y)) if menu => {
      wide.menu = Some((key, item, x, y))
      wide.filter_open = false
      wide.attention_open = false
    }
    _ => ()
  }
  // its menu open (beside the pointer, not over the page: ContextMenu modal false), still pointed at while the pointer
  // stays on it
  let menu_on = match wide.menu {
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
  let hover = c.hovered(id) || c.hovered(c.id("side/archive/" + key)) || menu_on
  let dim = if item.offline is Some(_) { 0.5 } else { 1.0 }
  c.box(style=if more { side_row_more } else { side_row_last }, fn() {
    c.box(
      dir=Row,
      w=Fill(1.0),
      h=Px(54.0),
      padx=10.0,
      pady=7.0,
      gap=8.0,
      align=AStart,
      radius=12.0,
      bg=nav_ground(c, "side/row/" + key, hover || c.pressed(id), on),
      id~,
      fn() {
        c.box(w=Fill(1.0), gap=2.0, opacity=if item.settled { 0.45 } else { 1.0 }, fn() {
          c.box(dir=Row, w=Fill(1.0), h=Px(20.0), gap=6.0, pr=if hover && menu { 24.0 } else { 0.0 }, align=ACenter, fn() {
            let tone = row_tone(item)
            if tone != "" {
              c.box(w=Px(10.0), align=ACenter, fn() { chat_mark(c, tone, pop=key) }) |> ignore
            }
            if wide.renaming == key {
              side_rename(c, src, item)
            } else {
              c.box(w=Fill(1.0), opacity=dim, fn() {
                c.text(
                  item.title,
                  size=13.0,
                  weight=if item.unread { 500 } else { 400 },
                  color=t.p.text,
                  wrap=false,
                  line=20.0,
                )
                |> ignore
              })
              |> ignore
            }
            if @sf.has_station_mark(item.station_emoji, item.station_icon) {
              c.box(w=Px(16.0), align=ACenter, opacity=dim, fn() {
                @sf.station_mark(c, item.station_emoji, item.station_icon, 12.0, t.p.muted)
              })
              |> ignore
            }
            // pinned, renamed or archived, until the station answers: turning; failed, a red mark a few seconds more,
            // why on hover (the menu that asked has closed)
            match row_doing(src, item) {
              Some(why) =>
                c.box(style=side_kind, fn() {
                  if why == "" {
                    @sf.spinner(c, size=12.0) |> ignore
                  } else {
                    let mark = c.id("side/row-failed/" + key)
                    c.box(id=mark, fn() { chat_mark(c, "alert") }) |> ignore
                    @sf.tip(c, "side/row-failed-tip/" + key, mark, why)
                  }
                })
                |> ignore
              None => ()
            }
            if item.offline is Some(_) || item.reconnecting is Some(_) {
              c.box(style=side_kind, fn() {
                @sf.icon(c, "unplug", size=12.0, color=t.p.subtle) |> ignore
              })
              |> ignore
            } else if item.connect {
              c.box(style=side_kind, fn() { @sf.slack_mark(c, 12.0) |> ignore }) |> ignore
            }
          })
          |> ignore
          c.box(dir=Row, w=Fill(1.0), h=Px(18.0), gap=6.0, align=ACenter, opacity=dim, fn() {
            let state = match item.state_text {
              Some(s) => Some(s)
              None => item.decision_text
            }
            c.box(w=Fill(1.0), fn() {
              match state {
                Some(s) => state_line(c, s, size=12.0, line=18.0)
                None =>
                  match item.last {
                    Some(l) => c.text(l, size=12.0, color=t.p.muted, wrap=false, line=18.0) |> ignore
                    None => ()
                  }
              }
            })
            |> ignore
            if hover {
              c.text(item.ago, size=11.0, color=t.p.subtle, wrap=false, line=18.0) |> ignore
            } else {
              side_aside(c, src, item, lead, on)
            }
          })
          |> ignore
        })
        |> ignore
      },
    )
    |> ignore
    // 归档, at the row's top right while it is pointed at
    if hover && menu {
      c.layer(align=AEnd, fn() {
        c.box(pt=5.0, pr=6.0, fn() {
          let aid = c.id("side/archive/" + key)
          c.cursor(aid, Hand)
          if c.clicked(aid) {
            archive_row(c, src, item)
          }
          c.box(
            w=Px(24.0),
            h=Px(24.0),
            radius=8.0,
            align=ACenter,
            justify=JCenter,
            bg=if c.hovered(aid) { t.p.hover } else { 0L },
            id=aid,
            fn() {
              @sf.icon(c, "archive", size=16.0, color=if c.hovered(aid) { t.p.text } else { t.p.muted })
              |> ignore
            },
          )
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// Who is in a chat at its row's second line's end, as the web's sidebar draws them (RowPicture.tsx RowAside, 16): its
/// agents' marks (a maker's once, 12 in a column 16 wide, 4 apart; past three, +N) and its people (16 round, each 3 over
/// the one before with a pixel of the row's ground round it; who started it, of more than one, ringed in ink a pixel
/// past that, over the others), those that lead first, 6 apart. `on`: the row is the page in view (its ground).
fn side_aside(c : @ui.Ctx, src : Source, item : ChatItem, lead : String, on : Bool) -> Unit {
  let groups = row_agent_groups(item)
  let people = item.people
  let with_people = people.length() > 0 &&
    (lead == "people" || people.iter().any(fn(p) { !p.mine }))
  if groups.length() == 0 && !with_people {
    return
  }
  let agents = fn() {
    let said = item.agents.map(fn(a) { a.text }).filter(fn(s) { s != "" })
    c.box(style=side_aside_agents, label=said.join(tr("web-main.list.separator")), fn() {
      for k, g in groups {
        if k < 3 {
          c.box(style=side_aside_agent, fn() { @sf.maker_mark(c, g.maker, g.runtime, side_agent_mark) |> ignore })
          |> ignore
        }
      }
      if groups.length() > 3 {
        c.text("+\{groups.length() - 3}", style=side_aside_more) |> ignore
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
    let shown = if people.length() > 3 { people[:3].to_array() } else { people }
    c.box(style=side_aside_faces, label=item.people_text, fn() {
      for i, p in shown {
        let starter = people.length() > 1 && p.id == item.creator
        let slot = c.box(style=if i == 0 { side_face } else { side_face_after }, fn() {
          c.box(style=side_face, tx=if i == 0 { 0.0 } else { -side_face_over }, fn() {
            c.layer(fn() { c.box(style=ground, tx=-1.0, ty=-1.0, fn() {  }) |> ignore }) |> ignore
            let picture = if p.picture != "" { (src.picture)(p.picture, c.page_stint()) } else { "" }
            @sf.avatar(c, if p.email != "" { p.email } else { p.id }, p.name, picture, side_face_d)
            if starter {
              c.layer(fn() { c.box(style=side_face_ring, tx=-2.0, ty=-2.0, fn() {  }) |> ignore }) |> ignore
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
/// A face at a row's end: 16 across; 3 over the one before it (RowPicture.css.ts aside overlap(3)).
let side_face_d : Double = 16.0

///|
let side_face_over : Double = 3.0

///|
/// An agent's mark at a row's end: 4 less than the faces (RowAside: size - 4).
let side_agent_mark : Double = 12.0

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
/// What a list says in place of its rows (Sidebar.css.ts navEmpty): 13 on 20 (still.fail's L6), muted.
// kept across runs: a value (no field of it changes)
let side_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, leading=L6)

///|
/// What stands at a row's title's end (Sidebar.css.ts sessionKind): a column 16 wide, its mark in the middle.
// kept across runs: a value (no field of it changes)
let side_kind : @ui.Style = @ui.style(w=S4, align=ACenter)

///|
/// A chat's row in the list, 2 over the row under it (Sidebar.css.ts navSessionWrap + navSessionWrap: margin-top 2).
// kept across runs: a value (no field of it changes)
let side_row_more : @ui.Style = @ui.style(w=Full, pb=S0_5)

///|
// kept across runs: a value (no field of it changes)
let side_row_last : @ui.Style = @ui.style(w=Full)

///|
/// What stands at a row's second line's end (RowPicture.css.ts aside, Sidebar.css.ts navSessionMeta): the agents and
/// the people 6 apart, each 2 in.
// kept across runs: a value (no field of it changes)
let side_aside_row : @ui.Style = @ui.style(row=true, gap=S1_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let side_aside_agents : @ui.Style = @ui.style(row=true, pl=S0_5, gap=S1, align=ACenter)

///|
/// An agent's mark in a column 16 wide and high (RowPicture.css.ts asideAgent).
// kept across runs: a value (no field of it changes)
let side_aside_agent : @ui.Style = @ui.style(w=S4, h=S4, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let side_aside_faces : @ui.Style = @ui.style(row=true, pl=S0_5, align=ACenter)

///|
/// How many more than are shown (RowPicture.css.ts asideMore): 12, muted.
// kept across runs: a value (no field of it changes)
let side_aside_more : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// A face, 16 round; one after the first takes 13 (3 of it over the one before).
// kept across runs: a value (no field of it changes)
let side_face : @ui.Style = @ui.style(w=S4, h=S4)

///|
// kept across runs: a value (no field of it changes)
let side_face_after : @ui.Style = @ui.style(w=@sf.side_face_step, h=S4)

///|
/// The pixel after who started it (RowPicture.css.ts: marginRight 1).
// kept across runs: a value (no field of it changes)
let side_face_gap : @ui.Style = @ui.style(w=SPx, h=S4)

///|
/// A pixel of the row's ground round a face (RowPicture.css.ts face: box-shadow 1px of --mark-around): the sidebar's,
/// the row in view's, the folded bar's (a floating panel's: shell.css.ts dock).
// kept across runs: a value (no field of it changes)
let side_face_ground : @ui.Style = @ui.style(w=S4_5, h=S4_5, radius=Full, bg=Sidebar)

///|
// kept across runs: a value (no field of it changes)
let side_face_on : @ui.Style = @ui.style(w=S4_5, h=S4_5, radius=Full, bg=Selected)

///|
// kept across runs: a value (no field of it changes)
let side_face_bar : @ui.Style = @ui.style(w=S4_5, h=S4_5, radius=Full, bg=Surface)

///|
/// Who started it ringed in ink, a pixel of ground between: a line 1 wide from 1 to 2 out (RowPicture.css.ts
/// face[data-starter]::after).
// kept across runs: a value (no field of it changes)
let side_face_ring : @ui.Style = @ui.style(w=S5, h=S5, radius=Full, border=B1, border_color=Fg)

///|
/// A row archived from the list (its 归档, its menu's): the chat beside the list goes to the one after it. One keeping
/// watch only once asked, in the core's words (its watch runs on in the archive).
fn archive_row(c : @ui.Ctx, src : Source, item : ChatItem) -> Unit {
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
        Ok(_) => say(c, tr("web-main.chat.archived"))
        Err(e) => say(c, fill("web-main.chat.archiveFailed", [("error", text(Some(e), "message"))]))
      }
    })
  }
  match item.watch_ask {
    Some(ask) =>
      @settings.confirm(fill("android-chat.archive.ask", [("title", item.title)]), ask, tr("android-chat.archive"), run)
    None => run()
  }
}

// ── settings (cloud/settings.tsx SettingsNav) ───────────────────────────

///|
/// The settings' sidebar: back to the chats, then its pages by where they act (this device, the stations, the cloud);
/// those in the rail (Station, Profile, 连接, 用量) are reached there.
fn settings_side(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let here = match app.nav.top() {
    // (a page under one of them: that one lit)
    Setting(@settings.Route::StationArchiving(_)) => Some(@settings.Route::Archiving)
    Setting(@settings.Route::AutoCompletion) | Setting(@settings.Route::AutoPolicy(_)) =>
      Some(@settings.Route::AutoDecisions)
    Setting(r) => Some(r)
    Settings => Some(@settings.Route::Appearance)
    Archived => Some(@settings.Route::Archive)
    _ => None
  }
  let rails = rail_items(src, w.id)
  let page = fn(r : @settings.Route, key : String, icon : String, label : String) {
    if nav_row(c, "settings-nav/" + key, here == Some(r), fn() {
        @sf.icon(c, icon, size=16.0, color=t.p.muted) |> ignore
        nav_words(c, label)
      }) {
      while app.nav.depth() > 1 {
        if !app.nav.pop() {
          break
        }
      }
      app.nav.push(Setting(r))
    }
  }
  let here_of = @settings.here_of(settings_core(src, w), w.id, w.name)
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    side_top(c)
    c.box(w=Fill(1.0), h=Fill(1.0), padx=8.0, pt=4.0, fn() {
      if nav_row(c, "settings-nav/back", false, fn() {
          @sf.icon(c, "arrow-left", size=16.0, color=t.p.muted) |> ignore
          nav_words(c, tr("web-pages.settings.nav.backToChats"))
        }) {
        while app.nav.depth() > 1 {
          if !app.nav.pop() {
            break
          }
        }
        if app.nav.top() != Home {
          app.nav.replace(Home)
        }
        wide.landed = ""
      }
      nav_heading(c, tr("web-pages.settings.nav.client"))
      page(@settings.Route::Appearance, "appearance", "sliders", tr("web-pages.settings.nav.appearance"))
      page(@settings.Route::Notifications, "notifications", "bell", tr("web-pages.settings.nav.notifications"))
      page(@settings.Route::Permissions, "permissions", "key", tr("web-pages.settings.nav.permissions"))
      page(@settings.Route::Changelog, "changelog", "sparks", tr("web-pages.settings.nav.changelog"))
      page(@settings.Route::About, "about", "info", tr("web-pages.settings.nav.about"))
      // the desktop's own (cloud/settings.tsx: the client's part)
      page(@settings.Route::Shortcuts, "shortcuts", "command", tr("web-pages.settings.nav.shortcuts"))
      page(@settings.Route::Version, "version", "info", tr("web-pages.settings.nav.version"))
      if @ui.platform() == 0 {
        page(@settings.Route::LocalStation, "local-station", "monitor", tr("web-pages.localStation.title"))
      }
      nav_heading(c, "Station")
      if !rails.contains("stations") {
        page(@settings.Route::Stations, "stations", "server", "Station")
      }
      if !rails.contains("connects") {
        page(@settings.Route::Connects(""), "connects", "im", tr("web-pages.settings.nav.connects"))
      }
      if !rails.contains("profiles") {
        page(@settings.Route::Profiles(""), "profiles", "quota", "Profile")
      }
      page(@settings.Route::Archiving, "archive", "archive", tr("web-pages.archiving.title"))
      page(@settings.Route::AutoDecisions, "automatic-decisions", "check", tr("web-pages.automaticDecisions.title"))
      page(@settings.Route::Memories, "memory", "brain", tr("web-pages.settings.nav.memory"))
      if !rails.contains("usage") {
        page(@settings.Route::Usage, "usage", "chart", tr("web-pages.settings.nav.usage"))
      }
      nav_heading(c, "Cloud")
      page(@settings.Route::Workspace, "workspace", "users", "Workspace · " + w.name)
      page(@settings.Route::Security, "security", "shield-check", tr("web-pages.security.title"))
      page(@settings.Route::Vault, "vault", "key", tr("web-pages.vault.title"))
      page(@settings.Route::Me, "account", "user", if here_of.email != "" { here_of.email } else { w.email })
    })
    |> ignore
  })
  |> ignore
}

// ── 奏 (DecisionDesk.tsx DecisionRows) ───────────────────────────────────

///|
/// 奏's sidebar: the decisions waiting for the viewer, the one shown first lit; its question in two lines at most,
/// its chat and station under it; pressed, it is the one the page shows. None: 暂无待决的奏折.
fn decisions_pane(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let topic = (src.topic)("decisions", { "workspace": Json::string(w.id) })
  let shown = shown_decisions(items(topic.value, "items"))
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    // under the band (新建对话 and the filter stay over 奏's list, as over the chats')
    side_space(c, band_h(src, w))
    c.box(w=Fill(1.0), h=Fill(1.0), padx=8.0, pt=4.0, fn() {
      if shown.length() == 0 {
        c.box(padx=10.0, pt=16.0, fn() {
          c.text(tr("web-main.decisions.empty"), size=13.0, color=t.p.muted, line=20.0) |> ignore
        })
        |> ignore
      }
      for i, d in shown {
        let v = Some(d)
        let question = match text(v, "question") {
          "" => text(v, "text")
          q => q
        }
        if nav_row(c, "zou-nav/" + decision_key(d), i == 0, pady=8.0, align=AStart, fn() {
            c.box(w=Fill(1.0), gap=2.0, fn() {
              c.box(w=Fill(1.0), max_h=40.0, clip=true, fn() {
                c.text(question, size=13.0, weight=500, color=t.p.text, line=20.0) |> ignore
              })
              |> ignore
              c.text(text(v, "title") + " · " + text(v, "stationName"), size=12.0, color=t.p.subtle, wrap=false, line=18.0)
              |> ignore
            })
            |> ignore
          }) {
          // the one pressed shown first (the others after it as they were)
          dui.dlater.retain(fn(k) { k != decision_key(d) })
          for j, o in shown {
            if j < i {
              dui.dlater.push(decision_key(o))
            }
          }
        }
      }
    })
    |> ignore
  })
  |> ignore
}
