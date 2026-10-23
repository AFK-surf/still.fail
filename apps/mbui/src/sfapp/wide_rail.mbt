// What the rail's foot does besides drawing (wide.mbt rail_workspaces draws it; ember web/src/Rail.tsx RailWorkspaces,
// cloud/workspace.tsx WorkspaceSwitcher `adder`): the ＋'s menu over the workspaces, which makes one, adds another
// account and answers the invitations; and what the stations' place says (Sidebar.tsx RailStations).

///|
/// Whether the rail's ＋ menu is open; the sidebar shown (its workspace and group: `wide.side_w` and `wide.folded` are
/// its) and how it was kept; whether, folded, it is shown a while over the page.
priv struct RailWs {
  mut add_open : Bool
  mut side_key : String
  mut kept_w : Double
  mut kept_folded : Bool
  mut peeking : Bool
  /// the sidebar being drawn in the closed bar (what the web's sidebar does there, at once)
  mut in_bar : Bool
  /// the state the block was last built in (closed, shown a while, the sidebar's width): a move sets out as it changes
  mut moved_as : (Bool, Bool, Double)?
  /// where the move has got to this frame (wide_frame): the sidebar's top row's height, its frosted bands' ground (0
  /// the sidebar's, 1 the closed bar's), the lists' marks on the rail (0 gone, 1 in)
  mut brand_h : Double
  mut band : Double
  mut mark : Double
  /// the page's bars' padding at its left (clear of the closed bar) and their margins while the folded sidebar is shown
  /// a while: from its edge (the sidebar less 8 less how far the page moved) to the window's (how far it moved)
  mut bar_pl : Double
  mut bar_ml : Double
  mut bar_mr : Double
  /// how far the page moves aside while the folded sidebar is shown a while (worked out as it is shown: peek_shift),
  /// and where the page started as the last frame laid it out
  mut peek_shift : Double
  mut page_from : Double
  /// the services left up long, their panel open from the lists' foot
  mut jobs_open : Bool
  /// the rail being changed (自定义侧边条): its places outlined, each with its −, what can be added beside it
  mut editing : Bool
  /// what was let go in 待处理's panel (忽略, `decision.dismiss`) until the core no longer lists it, by station and chat
  gone : Array[String]
  /// the stations' trouble as looked at when the bell's panel opened, as it shows it while open (None: closed)
  mut trouble_seen : String?
}

///|
let rail_ws : RailWs = {
  add_open: false,
  side_key: "",
  kept_w: 0.0,
  kept_folded: false,
  peeking: false,
  in_bar: false,
  moved_as: None,
  brand_h: 0.0,
  band: 0.0,
  mark: 0.0,
  bar_pl: 0.0,
  peek_shift: 0.0,
  page_from: 0.0,
  bar_ml: 0.0,
  bar_mr: 0.0,
  jobs_open: false,
  editing: false,
  gone: [],
  trouble_seen: None,
}

///|
fn rail_ws_reset() -> Unit {
  rail_ws.add_open = false
  rail_ws.side_key = ""
  rail_ws.kept_w = 0.0
  rail_ws.kept_folded = false
  rail_ws.peeking = false
  rail_ws.in_bar = false
  rail_ws.moved_as = None
  rail_ws.brand_h = 0.0
  rail_ws.band = 0.0
  rail_ws.mark = 0.0
  rail_ws.bar_pl = 0.0
  rail_ws.peek_shift = 0.0
  rail_ws.page_from = 0.0
  rail_ws.bar_ml = 0.0
  rail_ws.bar_mr = 0.0
  rail_ws.jobs_open = false
  rail_ws.editing = false
  rail_ws.gone.clear()
  rail_ws.trouble_seen = None
  archive_side_reset()
}

///|
/// Which sidebar the place shows (Rail.tsx SidebarGroup), each its own width and folded or not: the files', the
/// profiles' and the stations' when in the rail, the chats' for the chats' places and the others in the rail, else the
/// settings'.
fn side_group(src : Source, ws : String) -> String {
  let place = lit_place()
  let railed = rail_items(src, ws)
  match place {
    "files" => "files"
    "profiles" if railed.contains("profiles") => "profiles"
    "stations" if railed.contains("stations") => "stations"
    "chats" | "decisions" => "chats"
    p if railed.contains(p) => "chats"
    _ => "settings"
  }
}

///|
/// A sidebar's own width where none was kept (the stations' a little wider: a line of meters on each row).
fn side_default(group : String) -> Double {
  if group == "stations" {
    280.0
  } else {
    240.0
  }
}

///|
/// The sidebar shown follows the place and the workspace, each as it was left on this device (prefs `sidebars`, by
/// `<workspace>\n<group>`: its width, `,closed` folded; Rail.tsx widthFor, folded); what changes of it is kept, once a
/// drag of its edge is over.
fn side_follow(src : Source, ws : String) -> Unit {
  let prefs = (src.topic)("prefs", {}).value
  // (not read yet: as it is until it is)
  if prefs is None {
    return
  }
  let group = side_group(src, ws)
  let key = ws + "\n" + group
  if rail_ws.side_key != key {
    let said = text(field(field(prefs, "sidebars"), key), "")
    let parts = said.split(",").map(fn(p) { p.to_string() }).collect()
    let closed = parts.contains("closed")
    let width = if parts.length() > 0 && parts[0] != "closed" { parts[0] } else { "" }
    wide.side_w = match size_of(width) {
      Some(n) if n > 0 => dmax(side_min, dmin(side_max, n.to_double()))
      _ => side_default(group)
    }
    wide.folded = closed
    rail_ws.side_key = key
    rail_ws.kept_w = wide.side_w
    rail_ws.kept_folded = wide.folded
    rail_ws.peeking = false
    return
  }
  if wide.edge_x >= 0.0 || (wide.side_w == rail_ws.kept_w && wide.folded == rail_ws.kept_folded) {
    return
  }
  rail_ws.kept_w = wide.side_w
  rail_ws.kept_folded = wide.folded
  let w = if wide.side_w == side_default(group) { "" } else { wide.side_w.round().to_int().to_string() }
  let v = match (w, wide.folded) {
    ("", false) => Json::null()
    ("", true) => Json::string("closed")
    (w, true) => Json::string(w + ",closed")
    (w, false) => Json::string(w)
  }
  (src.call)("prefs.set", Json::object({ "sidebars": Json::object(Map::from_array([(key, v)])) }), fn(_) {  })
}

///|
/// Folded, the sidebar shown a while over the page as the pointer comes onto the rail's closed bar (Rail.tsx
/// peekSidebar), until the pointer has been off it a moment (PEEK_LEAVE, 400 ms) and nothing from it is open (a row's
/// menu, the filter's, a row renamed in place).
fn side_peek(c : @ui.Ctx, bar_x : Double, bar_y : Double, bar_r : Double, bar_b : Double) -> Unit {
  if !wide.folded {
    rail_ws.peeking = false
    return
  }
  let (px, py, _) = c.pointer()
  // on it, or on its edge at its right (Rail.tsx PEEK_ON: the dock, the edge, what pops up from it)
  let over = (px >= bar_x && px < bar_r && py >= bar_y && py < bar_b) ||
    (rail_ws.peeking && px >= bar_r - 2.0 && px < bar_r + 10.0)
  if over && !rail_ws.peeking && px < bar_x + rail_closed_w {
    rail_ws.peeking = true
  }
  let held = wide.menu is Some(_) || wide.filter_open || wide.renaming != "" || rail_ws.add_open
  if @kit.after(c, "side/peek-away", rail_ws.peeking && !over && !held, peek_leave_ms) {
    rail_ws.peeking = false
  }
}

///|
/// How long the pointer is off the sidebar shown a while before it folds again (Rail.tsx PEEK_LEAVE).
let peek_leave_ms : Double = 400.0

///|
/// The rail in the closed bar (Rail.css.ts rail, closed): as narrow as the bar, its places 6 from its every edge.
let rail_closed_w : Double = 42.0

///|
/// The invitations waiting for any account signed in, with the account each is for.
fn invitations_waiting(src : Source) -> Array[(Json?, Json)] {
  let pending : Array[(Json?, Json)] = []
  match (src.topic)("workspaces", {}).value {
    Some(Array(a)) =>
      for e in a {
        for i in items(Some(e), "invitations") {
          pending.push((field(Some(e), "account"), i))
        }
      }
    _ => ()
  }
  pending
}

///|
/// The ＋'s menu, beside it, its foot level with the ＋'s (WorkspaceSwitcher `adder`): 新建 workspace, 添加另一个账号,
/// then the invitations waiting, each joined or ignored.
fn rail_ws_menu(c : @ui.Ctx, src : Source, add : Int) -> Unit {
  let entries : Array[@kit.Entry] = [
    @kit.menu_item("create", label=tr("web-pages.workspace.create")),
    @kit.menu_item("account", label=tr("web-pages.workspace.addAccount")),
  ]
  let icons : Map[String, String] = { "create": "plus", "account": "user-plus" }
  let pending = invitations_waiting(src)
  if pending.length() > 0 {
    entries.push(@kit.menu_separator())
    entries.push(@kit.menu_label(tr("web-pages.workspace.invitations")))
    for p in pending {
      let iv = Some(p.1)
      let id = text(iv, "id")
      let inviter = match text(iv, "inviter") {
        "" => tr("web-pages.cloud.someone")
        x => x
      }
      entries.push(@kit.menu_label(fill("web-pages.workspace.invitedYou", [("inviter", inviter), ("name", text(iv, "name"))])))
      entries.push(@kit.menu_item("join:" + id, label=tr("web-pages.cloud.join")))
      entries.push(@kit.menu_item("ignore:" + id, label=tr("web-pages.workspace.ignore")))
    }
  }
  // beside it, its foot level with the ＋'s, 10 past it (side right, align end, sideOffset 10)
  let m = @sf.menu(c, "rail/ws-menu", rail_ws.add_open, add, entries, icons, rail_menu_w, side=Right, along=End, offset=10.0)
  rail_ws.add_open = m.open
  match m.chosen {
    Some("create") => open_new_workspace()
    Some("account") => (src.sign_in)()
    Some(v) if v.has_prefix("join:") || v.has_prefix("ignore:") => {
      let join = v.has_prefix("join:")
      let id = v.view(start_offset=if join { 5 } else { 7 }).to_string()
      for p in pending {
        if text(Some(p.1), "id") == id {
          respond_invitation(src, p.0, id, join, text(Some(p.1), "name"))
        }
      }
    }
    _ => ()
  }
}

///|
/// What the stations' place says on hover (RailStations): what is wrong with them, else what the core waits on, else
/// how many and who works.
fn rail_stations_label(src : Source, ws : String) -> String {
  let chats = (src.topic)("chats", { "scope": Json::string(ws), "mine": Json::boolean(false) }).value
  let status = (src.topic)("status", { "workspace": Json::string(ws) }).value
  let trouble = text(field(chats, "trouble"), "text")
  let waiting = if text(status, "state") != "" { text(status, "text") } else { "" }
  let summary = text(field(chats, "glyph"), "summary")
  if trouble != "" {
    trouble
  } else if waiting != "" {
    waiting
  } else if summary != "" {
    summary
  } else {
    "Station"
  }
}
