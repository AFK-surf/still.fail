// still.fail at a desktop's width (macOS, Windows): the web app's wide frame (ember web/src/cloud/workspace.tsx
// WorkspaceShell, styles/shell.css.ts), which the desktop app shows too. Above the web's breakpoint (701 wide) the
// rail at the left (Rail.tsx: the places, the workspaces, settings), the sidebar beside it on the same ground (the
// chats' list, or the settings', the files', 奏's: wide_side.mbt), and the page the stack has on top in the rest
// (the chat open, a settings page, a folder…); below it the phone's pages as before. Both are the same stack of pages
// (app.nav) and the same core topics: the window resized across the breakpoint shows the same place either way.

///|
/// From this width on, the wide frame (the web's `(min-width: 701px)`).
pub let wide_from : Double = 701.0

///|
/// The rail's width; the sidebar's own (Rail.tsx SIDEBAR: 240, from 180 to 480).
let rail_w : Double = 56.0

///|
let side_min : Double = 180.0

///|
let side_max : Double = 480.0

///|
/// The web's corners are its tokens times its superellipse's 1.25 (global.css.ts --corner-scale).
fn corner(r : Double) -> Double {
  r * 1.25
}

///|
/// What the wide frame keeps of its own (the rest is the stack's and the core's).
priv struct Wide {
  /// the sidebar's width, and whether it is folded to the rail (⌘\)
  mut side_w : Double
  mut folded : Bool
  /// the sidebar's edge dragged: from where, from what width; and whether it moved (a press alone folds)
  mut edge_x : Double
  mut edge_w : Double
  mut edge_moved : Bool
  /// a chat's row's menu open (its right click): its row's key, the item, where
  mut menu : (String, ChatItem, Double, Double)?
  /// a row being renamed in place: its key
  mut renaming : String
  /// the lists' filter menu open, 待处理's panel open
  mut filter_open : Bool
  mut attention_open : Bool
  /// ⌘K's panel open, what is typed in it, the row chosen
  mut switcher : Bool
  mut chosen : Int
  /// 快捷键一览 (⌘/) open
  mut keys_open : Bool
  /// the chat last opened here by the frame (the core's last chat taken once per workspace)
  mut landed : String
}

///|
let wide : Wide = {
  side_w: 240.0,
  folded: false,
  edge_x: -1.0,
  edge_w: 0.0,
  edge_moved: false,
  menu: None,
  renaming: "",
  filter_open: false,
  attention_open: false,
  switcher: false,
  chosen: 0,
  keys_open: false,
  landed: "",
}

///|
/// Whether this frame is drawn wide (what the phone's parts read where they differ: the chat's rows' sides, the
/// composer's Enter).
let wide_on : Ref[Bool] = Ref(false)

///|
/// Whether a window this wide is drawn wide.
pub fn is_wide(c : @ui.Ctx) -> Bool {
  c.width >= wide_from
}

///|
fn wide_reset() -> Unit {
  wide.side_w = 240.0
  wide.folded = false
  wide.edge_x = -1.0
  wide.menu = None
  wide.renaming = ""
  wide.filter_open = false
  wide.attention_open = false
  wide.switcher = false
  wide.chosen = 0
  wide.keys_open = false
  wide.landed = ""
  wide_on.val = false
}

///|
/// The sidebar's width now (none folded).
fn side_now() -> Double {
  if wide.folded {
    0.0
  } else {
    wide.side_w
  }
}

///|
/// The wide frame (WorkspaceShell): the rail and the sidebar on the sidebar's ground, the page in the rest; over them
/// the menus and panels that are open.
fn wide_frame(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  all : Array[Workspace],
  invited : Bool,
) -> Unit {
  let t = @sf.theme()
  // a desktop's page: the wheel and the trackpad scroll, a drag is the pointer's own
  c.mouse_drags_lists(false)
  let side = side_now()
  let main_w = dmax(0.0, c.width - rail_w - side)
  // the core's chat last open, else a new chat: there is always a page beside the list (workspace.tsx WorkspaceHome)
  land(src, w)
  c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    c.box(dir=Row, w=Px(rail_w + side), h=Fill(1.0), bg=t.p.sidebar, clip=true, fn() {
      rail(c, src, w, all)
      if side > 0.0 {
        c.box(w=Px(side + 8.0), h=Fill(1.0), fn() { sidebar(c, src, w, side + 8.0) }) |> ignore
      }
    })
    |> ignore
    c.box(w=Px(main_w), h=Fill(1.0), clip=true, fn() {
      c.sized(main_w, c.height, fn() {
        c.nav_flat(app.nav, fn(page) { main_page(c, src, w, all, invited, page) }, bg=t.p.bg)
        |> ignore
      })
    })
    |> ignore
  })
  |> ignore
  sidebar_edge(c, side)
  // back (⌘[, a mouse's back button) a page of the stack, where there is one
  if app.nav.depth() > 1 && !app.menu && !sheet_open() {
    c.take_back(fn() { app.nav.pop() |> ignore })
  }
}

///|
/// The chats' place with nothing open: the chat the core says was open last in this workspace, else a new chat
/// (workspace.tsx WorkspaceHome; once per workspace, so closing the chat goes back to the list on a phone).
fn land(src : Source, w : Workspace) -> Unit {
  if app.nav.depth() != 1 || app.nav.top() != Home {
    return
  }
  // come back to the chats (a chat closed, settings left): a new chat, as the web's empty place is
  if wide.landed == w.id {
    app.nav.push(NewChat)
    return
  }
  let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) })
  guard marks.value is Some(_) else { return }
  wide.landed = w.id
  let chat = field(field(field(marks.value, "workspaces"), w.id), "chat")
  let station = text(chat, "station")
  let key = text(chat, "key")
  if station != "" && key != "" {
    app.nav.push(Chat({ station, session: key, title: "", station_name: "" }))
  } else {
    app.nav.push(NewChat)
  }
}

///|
/// The page in the wide frame's pane: the chat (wide_chat.mbt), else the phone's page of the same (its own bar at its
/// top), the stack's top as it is.
fn main_page(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  all : Array[Workspace],
  invited : Bool,
  page : Page,
) -> Unit {
  match page {
    Chat(r) => wide_chat_page(c, src, w, r)
    // the chats' list is the sidebar's: nothing open (yet), the page's ground
    Home => ()
    // settings' own home is its first page (the web goes to 外观)
    Settings => setting_page(c, src, w, @settings.Route::Appearance)
    // a place of the rail's other than the chats': its page, under its title
    Place(p) => wide_place(c, src, w, p)
    // 文件: the stations' folders, under its bar (the phone's place has the bottom bar's room)
    Files => files_page(c, src, w)
    _ => page_view(c, src, w, all, invited, page)
  }
}

// ── the rail (Rail.tsx) ─────────────────────────────────────────────────

///|
/// The rail's places when none were chosen (Rail.tsx RAIL_DEFAULT).
let rail_default : Array[String] = [
  "attention", "chats", "files", "stations", "profiles", "connects", "usage",
]

///|
/// The rail's places in workspace `ws`, as kept (the prefs' `rails`), those this app has.
fn rail_items(src : Source, ws : String) -> Array[String] {
  let prefs = (src.topic)("prefs", {}).value
  let kept = match field(field(prefs, "rails"), ws) {
    Some(Array(a)) => a.map(fn(x) { text(Some(x), "") })
    _ =>
      match field(prefs, "rail") {
        Some(Array(a)) => a.map(fn(x) { text(Some(x), "") })
        _ => []
      }
  }
  let known = [
    "chats", "decisions", "attention", "files", "stations", "profiles", "connects",
    "usage",
  ]
  let items = kept.filter(fn(k) { known.contains(k) })
  if items.length() == 0 {
    rail_default
  } else {
    items
  }
}

///|
/// The place lit in the rail: what the stack's root is, settings while a settings page is open.
fn lit_place() -> String {
  let pages = app.nav.pages()
  for p in pages {
    match p {
      Settings | Setting(_) | Archived => return "settings"
      _ => ()
    }
  }
  // the place of the page nearest the top that has one
  let mut k = pages.length() - 1
  while k >= 0 {
    match pages[k] {
      Files | Drive(_) | DriveRead(_) | DrivePlay(_) => return "files"
      Decisions => return "decisions"
      Place(p) => return p
      Home | Chat(_) | NewChat => return "chats"
      _ => ()
    }
    k = k - 1
  }
  "chats"
}

///|
/// The rail: its top (in a window with its buttons in the app's top row, their row, dragging the window), the places,
/// then the workspaces and settings at its foot.
fn rail(c : @ui.Ctx, src : Source, w : Workspace, all : Array[Workspace]) -> Unit {
  let t = @sf.theme()
  let lit = lit_place()
  // its places centred on its 56; the sidebar reaches 8 into it (Sidebar.css.ts), so its own box is 48
  c.box(w=Px(rail_w - 8.0), h=Fill(1.0), pl=9.0, pb=9.0, gap=6.0, align=AStart, fn() {
    let top = c.id("rail/top")
    if @host.window_inset() {
      c.window_drag(top)
    }
    c.box(w=Px(38.0), h=Px(if @host.window_inset() { 41.0 } else { 5.0 }), id=top, fn() {  }) |> ignore
    for place in rail_items(src, w.id) {
      rail_place(c, src, w, place, lit == place)
    }
    c.spacer()
    // the workspaces, a square each (RailWorkspaces), the one in view marked at its left
    for x in all {
      let id = c.id("rail/ws/" + x.id)
      c.cursor(id, Hand)
      if c.clicked(id) && x.id != w.id {
        app.picked = x.id
        (src.call)("prefs.set", Json::object({ "workspace": Json::string(x.id) }), fn(_) {  })
        home()
      }
      let on = x.id == w.id
      c.box(w=Px(38.0), h=Px(38.0), align=ACenter, justify=JCenter, id~, fn() {
        c.box(
          w=Px(30.0),
          h=Px(30.0),
          radius=corner(9.0),
          bg=t.p.hover,
          align=ACenter,
          justify=JCenter,
          fn() {
            if @sf.has_station_mark(x.emoji, x.icon) {
              @sf.station_mark(c, x.emoji, x.icon, 18.0, t.p.text)
            } else {
              c.text(
                initial(x.name),
                size=13.0,
                weight=600,
                color=if on || c.hovered(id) { t.p.text } else { t.p.muted },
                wrap=false,
              )
              |> ignore
            }
          },
        )
        |> ignore
        if on {
          c.layer(fn() {
            c.box(pt=12.0, fn() {
              c.box(w=Px(3.0), h=Px(14.0), tx=-2.0, radius=2.0, bg=t.p.text, fn() {  }) |> ignore
            })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
    // settings
    let gear = c.id("rail/settings")
    c.cursor(gear, Hand)
    if c.clicked(gear) {
      open_settings()
    }
    rail_ground(c, gear, lit == "settings", fn(color) {
      @sf.icon(c, "settings", size=20.0, color~) |> ignore
    })
  })
  |> ignore
}

///|
/// A place's 38 to press, its ground (hovered, lit) 30 square under the icon (Rail.css.ts item).
fn rail_ground(c : @ui.Ctx, id : Int, on : Bool, body : (Int64) -> Unit) -> Unit {
  let t = @sf.theme()
  let hover = c.hovered(id)
  c.box(w=Px(38.0), h=Px(38.0), align=ACenter, justify=JCenter, id~, fn() {
    c.box(
      w=Px(30.0),
      h=Px(30.0),
      radius=corner(9.0),
      bg=if on {
        t.p.selected
      } else if hover {
        t.p.hover
      } else {
        0L
      },
      align=ACenter,
      justify=JCenter,
      fn() { body(if on || hover { t.p.text } else { t.p.muted }) },
    )
    |> ignore
  })
  |> ignore
}

///|
/// One place of the rail: its icon (奏 its word), what waits on it a dot at its corner; pressed, its page.
fn rail_place(c : @ui.Ctx, src : Source, w : Workspace, place : String, on : Bool) -> Unit {
  let t = @sf.theme()
  let id = c.id("rail/" + place)
  c.cursor(id, Hand)
  if c.clicked(id) {
    match place {
      "attention" => {
        wide.attention_open = !wide.attention_open
        wide.menu = None
      }
      "chats" =>
        // the chats again: the chat last open stays open beside the list
        if app.nav.pages()[0] == Home && lit_place() == "chats" {
          ()
        } else {
          go_place(c, "chats", [], -1)
          wide.landed = ""
        }
      p => go_place(c, p, [], -1)
    }
  }
  let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) })
  let dot = match place {
    "attention" => count(marks.value, "badge") > 0
    "decisions" => count(field(field(marks.value, "workspaces"), w.id), "decisions") > 0
    _ => false
  }
  c.box(fn() {
    rail_ground(c, id, on || (place == "attention" && wide.attention_open), fn(color) {
      if place == "decisions" {
        c.text("奏", size=16.0, weight=600, color~, wrap=false, line=20.0) |> ignore
      } else {
        @sf.icon(c, rail_icon(place), size=20.0, color~) |> ignore
      }
    })
    if dot {
      c.layer(align=AEnd, fn() {
        c.box(pt=4.0, pr=4.0, fn() {
          c.box(w=Px(12.0), h=Px(12.0), radius=6.0, bg=t.p.sidebar, pad=2.0, fn() {
            c.box(w=Fill(1.0), h=Fill(1.0), radius=4.0, bg=t.p.red, fn() {  }) |> ignore
          })
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
/// A place's icon in the rail (Rail.tsx RAIL_ICONS; the stations' its glyph there, a server here).
fn rail_icon(place : String) -> String {
  match place {
    "attention" => "bell"
    "chats" => "chats"
    "files" => "folder"
    "profiles" => "quota"
    "connects" => "im"
    "usage" => "chart"
    _ => "server"
  }
}

///|
/// Settings from the rail's gear (or ⌘,): its first page, 外观, the sidebar its list.
fn open_settings() -> Unit {
  lower_sheet()
  app.menu = false
  while app.nav.depth() > 1 {
    if !app.nav.pop() {
      break
    }
  }
  app.nav.push(Setting(@settings.Route::Appearance))
}

///|
/// The sidebar's edge (Rail.tsx SidebarEdge): a strip over its right edge, dragged to resize it (180 to 480), pressed
/// alone to fold it to the rail or open it again; its line and its grip show while the pointer is on it.
fn sidebar_edge(c : @ui.Ctx, side : Double) -> Unit {
  let t = @sf.theme()
  let id = c.id("sidebar-edge")
  let (px, _, down) = c.pointer()
  c.cursor(id, if wide.folded { Hand } else { ResizeX })
  if c.pressed(id) {
    if wide.edge_x < 0.0 {
      wide.edge_x = px
      wide.edge_w = wide.side_w
      wide.edge_moved = false
    } else if !wide.folded {
      let d = px - wide.edge_x
      if d.abs() >= 3.0 {
        wide.edge_moved = true
      }
      if wide.edge_moved {
        wide.side_w = dmax(side_min, dmin(side_max, wide.edge_w + d))
      }
    }
  }
  if c.clicked(id) && !wide.edge_moved {
    wide.folded = !wide.folded
  }
  if !down {
    wide.edge_x = -1.0
  }
  let shown = c.hovered(id) || c.pressed(id)
  c.layer(fn() {
    c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), fn() {
      c.box(w=Px(rail_w + side - 6.0 - (if wide.folded { 4.0 } else { 0.0 })), fn() {  }) |> ignore
      c.box(w=Px(12.0), h=Fill(1.0), align=AStart, justify=JCenter, id~, fn() {
        if shown {
          c.layer(fn() {
            c.box(w=Fill(1.0), h=Fill(1.0), pl=6.0, pt=8.0, pb=8.0, fn() {
              c.box(w=Px(1.0), h=Fill(1.0), bg=t.p.line_strong, fn() {  }) |> ignore
            })
            |> ignore
          })
          |> ignore
        }
        c.box(pl=4.0, fn() {
          c.box(
            w=Px(5.0),
            h=Px(if shown { 48.0 } else { 24.0 }),
            radius=2.5,
            bg=if shown { t.p.line_strong } else { 0L },
            fn() {  },
          )
          |> ignore
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
/// A new chat (新建对话, ⌘N): its page beside the list.
fn new_chat_wide() -> Unit {
  match app.nav.top() {
    NewChat => ()
    _ => {
      lower_sheet()
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
fn open_row(item : ChatItem) -> Unit {
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
  lower_sheet()
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
/// A place of the rail's (Station, Profile, 连接, 用量) in the pane: its title as a page's head (pages.css.ts), what
/// the settings' page of it shows under it.
fn wide_place(c : @ui.Ctx, src : Source, w : Workspace, place : String) -> Unit {
  let t = @sf.theme()
  let side = dmax(24.0, (c.width - 792.0) / 2.0) + 16.0
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    let head = c.id("place-head")
    if @host.window_inset() {
      c.window_drag(head)
    }
    c.box(w=Fill(1.0), pl=side, pr=side, pt=40.0, pb=12.0, id=head, fn() {
      c.text(place_label(place), size=22.0, weight=600, color=t.p.text, wrap=false, line=34.0) |> ignore
    })
    |> ignore
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      match @settings.route_of(place) {
        Some(r) => {
          let core = settings_core(src, w)
          @settings.page(c, core, @settings.here_of(core, w.id, w.name), r, root=true)
        }
        None => ()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The desktop's window for still.fail (before @ui.run): 1280 by 820 at first, as still.fail's desktop app opens
/// (apps/desktop main.ts), its size not kept (the desktop app keeps none either); at least 360 by 560, a phone's page
/// below the breakpoint. Its title bar the system's (macOS, Windows).
pub fn desktop_window() -> Unit {
  @host.window_setup(360.0, 560.0, 1280.0, 820.0)
}
