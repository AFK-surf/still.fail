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
  /// rows to come, breathing
  Breathing
  /// room for the band over the list
  Top
  Foot
}

///|
/// The sidebar `width` wide (its 8 at the left over the rail's empty side): what the place lists.
fn sidebar(c : @ui.Ctx, src : Source, w : Workspace, width : Double) -> Unit {
  ignore(width)
  match lit_place() {
    "settings" => settings_side(c, src, w)
    "files" => files_side(c, src, w)
    "decisions" => decisions_side(c, src, w)
    _ => chats_side(c, src, w)
  }
}

///|
/// The band's first row (Sidebar.css.ts brand): beside the rail only a margin (8); in a window with its buttons in the
/// app's top row, their row (44), which drags the window.
fn side_top(c : @ui.Ctx) -> Unit {
  let id = c.id("side/top")
  if @ui.window_inset() {
    c.window_drag(id)
  }
  c.box(w=Fill(1.0), h=Px(if @ui.window_inset() { 44.0 } else { 8.0 }), id~, fn() {  }) |> ignore
}

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
    radius=corner(12.0),
    bg=if on {
      t.p.selected
    } else if c.hovered(id) || c.pressed(id) {
      t.p.hover
    } else {
      0L
    },
    id~,
    body,
  )
  |> ignore
  c.clicked(id)
}

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
/// The chats' sidebar (ChatList): 新建对话 and the filter in the band, the list's days under it.
fn chats_side(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let filter = filter_of(src, w.id)
  let (view, error) = chats_of(src, w.id, filter)
  match view {
    Some(v) => open_listed(v)
    None => ()
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
          _ =>
            if v.stations > 0 {
              tr("web-main.sidebar.none")
            } else {
              tr("web-main.sidebar.noStation.before") +
              tr("web-main.sidebar.noStation.link") +
              tr("web-main.sidebar.noStation.after")
            }
        }
        lines.push(Words(words, false))
      }
      for d in v.days {
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
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    c.list("side/chats/" + w.id + "/" + filter, lines.length(), 54.0, fn(i) {
      c.box(w=Fill(1.0), padx=8.0, fn() {
        match lines[i] {
          Heading(label) => nav_heading(c, label)
          Chat(item) => {
            let on = match open {
              Some(r) => r.station == item.station && (r.session == item.session || r.session == item.id)
              None => false
            }
            side_chat_row(c, src, item, lead, on)
          }
          Words(words, bad) =>
            c.box(w=Fill(1.0), padx=10.0, pt=16.0, pb=16.0, fn() {
              c.text(words, size=13.0, color=if bad { t.p.red } else { t.p.muted }, line=20.0) |> ignore
            })
            |> ignore
          Breathing => side_breathing(c)
          // the band: its top row, 新建对话's (6 + 32 + 2), and 4
          Top => c.box(h=Px((if @ui.window_inset() { 44.0 } else { 8.0 }) + 40.0 + 4.0), fn() {  }) |> ignore
          Foot => c.box(h=Px(12.0), fn() {  }) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
    // the band over the list: its top row, then 新建对话 and the filter
    c.layer(fn() {
      c.box(w=Fill(1.0), glass=@sf.glass_bar(), fn() {
        side_top(c)
        c.box(dir=Row, w=Fill(1.0), pl=8.0, pr=8.0, pt=6.0, pb=2.0, gap=4.0, align=ACenter, fn() {
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
            Some(v) if v.stations > 0 => filter_button(c, filter)
            _ => ()
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The list's filter (components.tsx MineFilter, compact): a 32 square, in the accent's ground while it narrows the
/// list; pressed, its menu.
fn filter_button(c : @ui.Ctx, filter : String) -> Unit {
  let t = @sf.theme()
  let id = c.id("side/filter")
  c.cursor(id, Hand)
  if c.clicked(id) {
    wide.filter_open = !wide.filter_open
    wide.menu = None
  }
  let narrowed = filter != "all"
  c.box(
    w=Px(32.0),
    h=Px(32.0),
    radius=corner(12.0),
    align=ACenter,
    justify=JCenter,
    bg=if narrowed {
      t.p.accent_bg
    } else if c.hovered(id) || wide.filter_open {
      t.p.hover
    } else {
      0L
    },
    id~,
    fn() {
      @sf.icon(
        c,
        "filter",
        size=16.0,
        color=if narrowed {
          t.p.accent_text
        } else if c.hovered(id) {
          t.p.text
        } else {
          t.p.muted
        },
      )
      |> ignore
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
fn side_chat_row(c : @ui.Ctx, src : Source, item : ChatItem, lead : String, on : Bool) -> Unit {
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
  let hover = c.hovered(id) || c.hovered(c.id("side/archive/" + key))
  let dim = if item.offline is Some(_) { 0.5 } else { 1.0 }
  c.box(w=Fill(1.0), pb=2.0, fn() {
    c.box(
      dir=Row,
      w=Fill(1.0),
      h=Px(54.0),
      padx=10.0,
      pady=7.0,
      gap=8.0,
      align=AStart,
      radius=corner(12.0),
      bg=if on {
        t.p.selected
      } else if hover || c.pressed(id) {
        t.p.hover
      } else {
        0L
      },
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
            if item.offline is Some(_) || item.reconnecting is Some(_) {
              c.box(w=Px(16.0), align=ACenter, fn() {
                @sf.icon(c, "unplug", size=12.0, color=t.p.subtle) |> ignore
              })
              |> ignore
            } else if item.connect {
              c.box(w=Px(16.0), align=ACenter, fn() { @sf.slack_mark(c, 12.0) |> ignore }) |> ignore
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
              row_aside(c, src, item, lead, face_size=16.0)
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
            radius=corner(8.0),
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
/// A row archived from the list (its 归档, its menu's): the chat beside the list goes to the one after it.
fn archive_row(c : @ui.Ctx, src : Source, item : ChatItem) -> Unit {
  match item.watch_ask {
    // one keeping watch asks first (its watch runs on in the archive): said, not done from here
    Some(ask) => say(c, ask)
    None => {
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
  }
}

// ── settings (cloud/settings.tsx SettingsNav) ───────────────────────────

///|
/// The settings' sidebar: back to the chats, then its pages by where they act (this device, the stations, the cloud);
/// those in the rail (Station, Profile, 连接, 用量) are reached there.
fn settings_side(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let here = match app.nav.top() {
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
      page(@settings.Route::Home, "notifications", "bell", tr("web-pages.settings.nav.notifications"))
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
      page(@settings.Route::Archive, "archive", "archive", tr("web-pages.archiving.title"))
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

// ── the files (cloud/workspace.tsx FilesSidebar) ────────────────────────

///|
/// The files' sidebar: each station's folders, under its name (· 离线 while it is away): its home where its viewer
/// may browse all of it, then each folder it lends; a row opens it beside the list.
fn files_side(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let (list, error) = dv_stations(src, w.id)
  let here = match app.nav.top() {
    Drive(at) => Some(at)
    _ => None
  }
  let open = fn(at : DriveAt) {
    while app.nav.depth() > 1 {
      if !app.nav.pop() {
        break
      }
    }
    app.nav.push(Drive(at))
  }
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    side_top(c)
    c.box(w=Fill(1.0), h=Fill(1.0), padx=8.0, pt=4.0, fn() {
      match (list, error) {
        (None, Some(e)) =>
          c.box(padx=10.0, pt=16.0, fn() { c.text(e, size=13.0, color=t.p.red, line=20.0) |> ignore })
          |> ignore
        (None, None) => side_breathing(c)
        (Some(stations), _) => {
          let lending = stations.filter(fn(s) { s.drive && (s.anywhere || s.roots.length() > 0) })
          if lending.length() == 0 {
            c.box(padx=10.0, pt=16.0, fn() {
              c.text(tr("web-main.rail.filesNone"), size=13.0, color=t.p.muted, line=20.0) |> ignore
            })
            |> ignore
          }
          for s in lending {
            nav_heading(c, if s.online { s.name } else { s.name + " · 离线" })
            if s.anywhere {
              let at : DriveAt = { station: s.station, root: None, path: "" }
              if nav_row(c, "files-nav/" + s.station + "/home", here == Some(at), fn() {
                  @sf.icon(c, "folder", size=16.0, color=t.p.muted) |> ignore
                  nav_words(c, tr("web-pages.drive.home"))
                }) {
                open(at)
              }
            }
            for root in s.roots {
              let at : DriveAt = { station: s.station, root: Some(root.path), path: "" }
              let on = match here {
                Some(h) => h.station == s.station && h.root == Some(root.path)
                None => false
              }
              if nav_row(c, "files-nav/" + s.station + "/" + root.path, on, fn() {
                  @sf.icon(c, "folder", size=16.0, color=t.p.muted) |> ignore
                  nav_words(c, root.name)
                }) {
                open(at)
              }
            }
          }
        }
      }
    })
    |> ignore
  })
  |> ignore
}

// ── 奏 (DecisionDesk.tsx DecisionRows) ───────────────────────────────────

///|
/// 奏's sidebar: the decisions waiting for the viewer, the one shown first lit; its question in two lines at most,
/// its chat and station under it; pressed, it is the one the page shows. None: 暂无待决的奏折.
fn decisions_side(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let topic = (src.topic)("decisions", { "workspace": Json::string(w.id) })
  let shown = shown_decisions(items(topic.value, "items"))
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    side_top(c)
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
