// What opens over the wide frame (ember web/ui controls.css.ts popover and menuList, Switcher.tsx and Switcher.css.ts,
// Attention.tsx, Shortcuts.tsx): a chat's row's menu (its right click), the lists' filter, 待处理's panel beside the
// rail, ⌘K's switcher and ⌘/'s shortcuts over a scrim. Each is mbui's (@kit's menus, popover and dialog, the layer
// under them: the keys a menu's, the focus kept in what is open, a screen reader told what it is) in the web's look.
// A press outside one, or Esc, closes it.

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
/// A small panel's look (controls.css.ts popover, @sf.panel) for mbui's menus and popovers, `w` wide.
fn wide_panel(c : @ui.Ctx, w : Double, body : () -> Unit) -> Unit {
  @sf.panel(c, w=Px(w), body) |> ignore
}

///|
/// How a small panel comes (controls.css.ts popover's popKeyframes): from 97% and clear to itself over 140 ms
/// (--ease-out), from its top; it goes at once, as the web's does.
// kept across runs: a value (no field of it changes)
let wide_pop_in : @motion.Trans = @motion.trans(fade=0.0, scale=0.97, ox=0.5, oy=0.0, spec=@motion.tween(140.0, ease=Out))

///|
// kept across runs: a value (no field of it changes)
let wide_pop_out : @motion.Trans = @motion.trans(spec=@motion.tween(0.0))

///|
/// A menu's item (controls.css.ts menuItem), as mbui's menus draw it: 34 high at least, 7 by 10 in, its icon (14,
/// muted) and words (13); the pointer's or the keyboard's ground on it; the one chosen checked at its end.
fn wide_menu_row(c : @ui.Ctx, s : @kit.MenuItemState, icon : String) -> Unit {
  let t = @sf.theme()
  let checked = match s.entry.kind {
    Choice(true) | Check(true) => true
    _ => false
  }
  c.box(
    dir=Row,
    w=Fill(1.0),
    min_h=34.0,
    padx=10.0,
    pady=7.0,
    gap=8.0,
    align=ACenter,
    radius=@ui.concentric(20.0, 6.0),
    bg=if s.hot { t.p.hover } else { 0L },
    fn() {
      if icon != "" {
        @sf.icon(c, icon, size=14.0, color=t.p.muted) |> ignore
      }
      c.text(s.entry.label, style=wide_row_words) |> ignore
      if checked {
        @sf.icon(c, "check", size=14.0, color=t.p.text) |> ignore
      }
    },
  )
  |> ignore
}

///|
/// A menu of the wide frame (mbui's dropdown menu, in the web's look): `entries` with their icons (by value), `w` wide,
/// `offset` under `trigger` lined up `along` it, or at `at`; what was chosen. The arrows, letters, Enter and Escape as a
/// menu's; a press outside closes it.
fn wide_menu(
  c : @ui.Ctx,
  key : String,
  open : Bool,
  trigger : Int,
  entries : Array[@kit.Entry],
  icons : Map[String, String],
  w : Double,
  along? : @ui.Along = Start,
  offset? : Double = 6.0,
  at? : (Double, Double, Double, Double),
) -> @kit.Menu {
  @kit.dropdown_menu(
    c,
    key,
    open,
    trigger,
    entries,
    along~,
    offset~,
    min_w=w,
    at?,
    enter=wide_pop_in,
    exit=wide_pop_out,
    look=fn(c, w, body) { wide_panel(c, w, body) },
    item_look=fn(c, s) { wide_menu_row(c, s, icons.get(s.entry.value).unwrap_or("")) },
  )
}

///|
/// Everything open over the wide frame, drawn after it.
fn wide_overlays(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  row_menu(c, src)
  rail_menu(c, src, w)
  wide_filter_menu(c, src, w)
  attention_panel(c, src, w)
  switcher(c, src, w)
  keys_dialog(c)
}

///|
/// The lists' filter's menu (components.tsx MineFilter): 全部会话, 我参与的, 监控中 (the one in use checked), 奏, then
/// 已归档; 200 wide under the filter's button, its right edge under the button's.
fn wide_filter_menu(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let filter = filter_of(src, w.id)
  let chats = lit_place() == "chats"
  let entries = ["all", "mine", "watching"].map(fn(f) {
    let label = match f {
      "all" => tr("web-main.filter.chats.all")
      "mine" => tr("web-main.filter.chats.mine")
      _ => tr("web-main.filter.watching")
    }
    @kit.menu_radio(f, filter == f && chats, label~)
  })
  entries.push(@kit.menu_item("decisions", label=tr("web-main.rail.decisions")))
  entries.push(@kit.menu_separator())
  entries.push(@kit.menu_item("archived", label=tr("web-main.filter.archived")))
  let m = wide_menu(c, "filter-menu", wide.filter_open, c.id("side/filter"), entries, { "archived": "archive" }, 200.0, along=End)
  wide.filter_open = m.open
  match m.chosen {
    Some("decisions") => go_place(c, "decisions", [], -1)
    Some("archived") => {
      while app.nav.depth() > 1 {
        if !app.nav.pop() {
          break
        }
      }
      app.nav.push(Archived)
    }
    Some(f) => {
      if !chats {
        go_place(c, "chats", [], -1)
      }
      app.filters[w.id] = f
      let pick : Map[String, Json] = {}
      pick[w.id] = Json::string(f)
      (src.call)("prefs.set", Json::object({ "listFilter": Json::object(pick) }), fn(_) {  })
    }
    None => ()
  }
}

///|
/// 待处理's panel beside the rail (Attention.tsx): each workspace's chats that want the viewer (a card or a need
/// waiting, an agent gone wrong), the one in view's first; pressed, its chat; 全部决定 (奏) and 通知设置 at its foot.
fn attention_panel(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let close = fn() { wide.attention_open = false }
  let trigger = c.id("rail/attention")
  // 10 past the rail, its top the button's (mbui's popover by it, on its right)
  let offset = match c.rect_of(trigger) {
    Some((bx, _, bw, _)) => rail_w + 10.0 - bx - bw
    None => 10.0
  }
  let p = @kit.popover(
    c,
    "attention",
    wide.attention_open,
    trigger,
    side=Right,
    along=Start,
    offset~,
    look=fn(c, _, body) { wide_panel(c, 320.0, body) },
    fn() { attention_rows(c, src, w, t, close) },
  )
  wide.attention_open = p.value
}

///|
/// What 待处理's panel holds (its chats by workspace, then 全部决定 and 通知设置), read while it is open.
fn attention_rows(c : @ui.Ctx, src : Source, w : Workspace, t : @sf.Theme, close : () -> Unit) -> Unit {
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
        radius=@ui.concentric(20.0, 6.0),
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
  panel_line(c)
  c.box(dir=Row, w=Fill(1.0), gap=4.0, fn() {
    if panel_button(c, "attention/desk", tr("web-main.attention.desk")) {
      close()
      go_place(c, "decisions", [], -1)
    }
    if panel_button(c, "attention/settings", tr("web-main.attention.settings")) {
      close()
      open_settings()
      app.nav.replace(Setting(@settings.Route::Home))
    }
  })
  |> ignore
}

///|
/// A row's words in a small panel (menuItem: 13 on 20, the ink, on one line, as wide as the row leaves).
// kept across runs: a value (no field of it changes)
let wide_row_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, leading=L5, wrap=false, w=Full)

///|
/// A line between a small panel's parts (controls.css.ts menuSep: 1 high, 6 over and under, 4 in, the words' colour at
/// 12%).
fn panel_line(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), pady=6.0, padx=4.0, fn() {
    c.box(w=Fill(1.0), h=Px(1.0), bg=@sf.alpha(t.p.text, 0.12), fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// A button in a small panel, as its rows are (controls.css.ts menuItem): 34 high at least, 7 by 10 in, its words
/// (13); the pointer's ground on it. True on the frame after a press.
fn panel_button(c : @ui.Ctx, key : String, label : String) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.cursor(id, Hand)
  let b = c.box(
    w=Fill(1.0),
    min_h=34.0,
    padx=10.0,
    pady=7.0,
    justify=JCenter,
    radius=@ui.concentric(20.0, 6.0),
    bg=if c.hovered(id) || c.pressed(id) { t.p.hover } else { 0L },
    id~,
    fn() { c.text(label, style=wide_row_words) |> ignore },
  )
  c.semantics(b, Button, id~, label~)
  c.clicked(id)
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

