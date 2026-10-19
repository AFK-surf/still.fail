// What opens over the wide frame (ember web/ui controls.css.ts popover and menuList, Switcher.tsx and Switcher.css.ts,
// Attention.tsx, Shortcuts.tsx): a chat's row's menu (its right click), the lists' filter, 待处理's panel beside the
// rail, ⌘K's switcher and ⌘/'s shortcuts over a scrim. A press outside one, or Esc, closes it.

///|
/// A small panel's ground (glass.ts panel): the canvas in light, the raised grey in dark, a hairline round it.
fn panel_ground() -> Int64 {
  let t = @sf.theme()
  if t.dark {
    t.p.raised
  } else {
    t.p.canvas
  }
}

///|
/// A popover (controls.css.ts popover) of `width` at (x, y) in the window, kept inside it (`est`: about how tall it
/// is), its rows 6 in; a press outside it closes it (`close`).
fn popover(
  c : @ui.Ctx,
  key : String,
  x : Double,
  y : Double,
  width : Double,
  est : Double,
  close : () -> Unit,
  body : () -> Unit,
  trigger? : Int = 0,
) -> Unit {
  let t = @sf.theme()
  let id = c.id(key)
  let (px, py, _) = c.pointer()
  let inside = fn(r : (Double, Double, Double, Double)?) {
    match r {
      Some((rx, ry, rw, rh)) => px >= rx && px < rx + rw && py >= ry && py < ry + rh
      None => false
    }
  }
  // a press outside it closes it (not on what opened it: that press toggles it)
  if cui.press_new && c.rect_of(id) is Some(_) && !inside(c.rect_of(id)) && !(trigger != 0 && inside(c.rect_of(trigger))) {
    close()
    return
  }
  let at_x = dmax(8.0, dmin(x, c.width - width - 8.0))
  let at_y = dmax(8.0, dmin(y, c.height - est - 8.0))
  c.layer(fn() {
    c.box(
      w=Px(width),
      tx=at_x,
      ty=at_y,
      pad=6.0,
      radius=corner(20.0),
      bg=panel_ground(),
      border=1.0,
      border_color=t.p.line,
      shadow=24.0,
      shadow_y=8.0,
      shadow_color=t.p.shadow,
      id~,
      body,
    )
    |> ignore
  })
  |> ignore
}

///|
/// A menu's item (controls.css.ts menuItem): 34 high at least, 7 by 10 in, its icon (14, muted) and words (13); the
/// pointer's ground on hover. True on the frame after a press.
fn menu_item(c : @ui.Ctx, key : String, icon : String, label : String, checked? : Bool = false) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.cursor(id, Hand)
  c.box(
    dir=Row,
    w=Fill(1.0),
    min_h=34.0,
    padx=10.0,
    pady=7.0,
    gap=8.0,
    align=ACenter,
    radius=corner(20.0) - 6.0,
    bg=if c.hovered(id) || c.pressed(id) { t.p.hover } else { 0L },
    id~,
    fn() {
      if icon != "" {
        @sf.icon(c, icon, size=14.0, color=t.p.muted) |> ignore
      }
      c.box(w=Fill(1.0), fn() { c.text(label, size=13.0, color=t.p.text, wrap=false, line=20.0) |> ignore })
      |> ignore
      if checked {
        @sf.icon(c, "check", size=14.0, color=t.p.text) |> ignore
      }
    },
  )
  |> ignore
  c.clicked(id)
}

///|
/// A line between a menu's parts.
fn menu_line(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), pady=4.0, padx=4.0, fn() {
    c.box(w=Fill(1.0), h=Px(1.0), bg=t.p.line, fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// Everything open over the wide frame, drawn after it.
fn wide_overlays(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  wide_filter_menu(c, src, w)
  attention_panel(c, src, w)
}

///|
/// The lists' filter's menu (components.tsx MineFilter): 全部会话, 我参与的, 监控中 (the one in use checked), 奏, then
/// 已归档.
fn wide_filter_menu(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  if !wide.filter_open {
    return
  }
  let close = fn() { wide.filter_open = false }
  let (x, y) = match c.rect_of(c.id("side/filter")) {
    Some((bx, by, bw, bh)) => (bx + bw - 200.0, by + bh + 6.0)
    None => (rail_w + side_now() - 208.0, 60.0)
  }
  let filter = filter_of(src, w.id)
  popover(c, "filter-menu", x, y, 200.0, 220.0, close, trigger=c.id("side/filter"), fn() {
    for f in ["all", "mine", "watching"] {
      let label = match f {
        "all" => tr("web-main.filter.chats.all")
        "mine" => tr("web-main.filter.chats.mine")
        _ => tr("web-main.filter.watching")
      }
      if menu_item(c, "filter-menu/" + f, "", label, checked=filter == f && lit_place() == "chats") {
        close()
        if lit_place() != "chats" {
          go_place(c, "chats", [], -1)
        }
        app.filters[w.id] = f
        let pick : Map[String, Json] = {}
        pick[w.id] = Json::string(f)
        (src.call)("prefs.set", Json::object({ "listFilter": Json::object(pick) }), fn(_) {  })
      }
    }
    if menu_item(c, "filter-menu/decisions", "", tr("web-main.rail.decisions")) {
      close()
      go_place(c, "decisions", [], -1)
    }
    menu_line(c)
    if menu_item(c, "filter-menu/archived", "archive", tr("web-main.filter.archived")) {
      close()
      while app.nav.depth() > 1 {
        if !app.nav.pop() {
          break
        }
      }
      app.nav.push(Archived)
    }
  })
}

///|
/// 待处理's panel beside the rail (Attention.tsx): each workspace's chats that want the viewer (a card or a need
/// waiting, an agent gone wrong), the one in view's first; pressed, its chat; 全部决定 (奏) and 通知设置 at its foot.
fn attention_panel(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  if !wide.attention_open {
    return
  }
  let t = @sf.theme()
  let close = fn() { wide.attention_open = false }
  let y = match c.rect_of(c.id("rail/attention")) {
    Some((_, by, _, _)) => by
    None => 40.0
  }
  let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) })
  let groups : Array[(String, String, Array[Json])] = []
  match field(marks.value, "workspaces") {
    Some(Object(by)) => {
      let order = by.keys().to_array()
      order.sort_by(fn(a, b) { if a == w.id { -1 } else if b == w.id { 1 } else { 0 } })
      for ws in order {
        let list = items(by.get(ws), "items")
        if list.length() > 0 {
          groups.push((ws, text(Some(list[0]), "workspaceName"), list))
        }
      }
    }
    _ => ()
  }
  let several = groups.length() > 1 || groups.iter().any(fn(g) { g.0 != w.id })
  popover(c, "attention", rail_w + 10.0, y, 320.0, 360.0, close, trigger=c.id("rail/attention"), fn() {
    if groups.length() == 0 {
      c.box(w=Fill(1.0), padx=10.0, pady=12.0, fn() {
        c.text(tr("web-main.attention.empty"), size=13.0, color=t.p.muted, wrap=false) |> ignore
      })
      |> ignore
    }
    for g in groups {
      if several {
        c.box(padx=10.0, pt=6.0, pb=2.0, fn() {
          c.text(g.1, size=12.0, color=t.p.muted, wrap=false) |> ignore
        })
        |> ignore
      }
      for i in g.2 {
        let v = Some(i)
        let session = text(v, "session")
        let key = "attention/" + text(v, "station") + "/" + session + "/" + number(v, "thread").to_string()
        let id = c.id(key)
        c.cursor(id, Hand)
        if c.clicked(id) {
          close()
          if g.0 != w.id {
            app.picked = g.0
            (src.call)("prefs.set", Json::object({ "workspace": Json::string(g.0) }), fn(_) {  })
            home()
          }
          let chat : ChatRef = {
            station: text(v, "station"),
            session: if session != "" { session } else { "thread:" + number(v, "thread").to_int64().to_string() },
            title: text(v, "title"),
            station_name: text(v, "stationName"),
          }
          while app.nav.depth() > 1 {
            if !app.nav.pop() {
              break
            }
          }
          app.nav.replace(Home)
          app.nav.push(Chat(chat))
        }
        c.box(
          dir=Row,
          w=Fill(1.0),
          padx=10.0,
          pady=7.0,
          gap=8.0,
          align=AStart,
          radius=corner(20.0) - 6.0,
          bg=if c.hovered(id) { t.p.hover } else { 0L },
          opacity=if flag(v, "seen") { 0.6 } else { 1.0 },
          id~,
          fn() {
            c.box(pt=6.0, fn() {
              c.box(
                w=Px(8.0),
                h=Px(8.0),
                radius=4.0,
                bg=if text(v, "kind") == "alert" { mark_red } else { mark_blue },
                fn() {  },
              )
              |> ignore
            })
            |> ignore
            c.box(w=Fill(1.0), gap=1.0, fn() {
              let title = text(v, "title")
              c.text(
                if title != "" { title } else { tr("web-main.attention.untitled") },
                size=13.0,
                weight=500,
                color=t.p.text,
                wrap=false,
                line=20.0,
              )
              |> ignore
              c.text(attention_line(v), size=12.0, color=t.p.muted, wrap=false, line=18.0) |> ignore
            })
            |> ignore
          },
        )
        |> ignore
      }
    }
    menu_line(c)
    c.box(dir=Row, w=Fill(1.0), gap=4.0, fn() {
      if menu_item(c, "attention/desk", "", tr("web-main.attention.desk")) {
        close()
        go_place(c, "decisions", [], -1)
      }
      if menu_item(c, "attention/settings", "", tr("web-main.attention.settings")) {
        close()
        open_settings()
        app.nav.replace(Setting(@settings.Route::Home))
      }
    })
    |> ignore
  })
}

///|
/// A wanting chat's line without its lead (要你帮忙：, 出问题：, 奏 · ): the dot before it says that.
fn attention_line(v : Json?) -> String {
  let s = text(v, "text")
  for lead in ["要你帮忙：", "需要你处理：", "出问题：", "出错：", "奏 · "] {
    if s.has_prefix(lead) {
      return s.view(start_offset=lead.length()).to_owned()
    }
  }
  if s == "" {
    text(v, "stationName")
  } else {
    s
  }
}

