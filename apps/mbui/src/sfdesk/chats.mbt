// The band over the sidebar's chats' lists (ember web/src/SidebarList.tsx NavTop; SidebarActions.tsx): 新建对话 and the
// filter; the lists under it are sfpages' (sidebar.mbt).

///|
/// The band over the lists (SidebarList.tsx NavTop): its top row, then 新建对话 and the filter (SidebarActions.tsx),
/// then 待处理 where the rail has no bell; on the sidebar's own ground, whole (no glass: asked, 2026-10-24), the closed
/// bar's as it closes (moved with it).
fn lists_band(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let filter = filter_of(src, w.id)
  let (view, _) = chats_of(src, w.id, "all")
  c.box(style=side_full.then(@ui.style(bg=Data(@sf.mix(closed_ground(), wide.band, t.p.sidebar)))), fn() {
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
          new_chat()
        }
      })
      |> ignore
      match view {
        // (lit while it narrows the chats or another list is shown: 奏, 已归档)
        Some(v) if v.stations > 0 => filter_button(c, src, w, filter, list_place(list_mode(src, w)), list_mode(src, w) != 0, in_bar)
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
/// A new chat (新建对话, ⌘N): where the shell has it (beside the list on the wide frame, risen on the stack).
pub fn new_chat() -> Unit {
  open_page(NewChat)
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
fn filter_button(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  filter : String,
  shown : String,
  narrowed : Bool,
  in_bar : Bool,
) -> Unit {
  let t = @sf.theme()
  let id = c.id("side/filter")
  c.cursor(id, Hand)
  // its menu (sfpages' filter_menu): a filter its list, 奏 its place, 已归档 the archive's list (rail_go)
  if c.clicked(id) {
    @sfpages.filter_menu(Of(id), if shown == "chats" { "all" } else { shown }, fn(f) {
      match f {
        "decisions" => go_place("decisions")
        "all" => rail_go(c, src, w, "chats")
        f => rail_go(c, src, w, f)
      }
    })
  }
  let narrowed = narrowed || filter != "all"
  // its ground and colour moved over 140 ms (page.css.ts iconBtn: transition background, color)
  let hot = @kit.animate(c, "side/filter/hover", if c.lit(id) || @sfpages.filter_menu_open() { 1.0 } else { 0.0 }, transition=nav_fade)
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
// kept across runs: a value (no field of it changes)
let filter_box : @ui.Style = @ui.css("w=S8 h=S8 radius=Xl align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let filter_box_bar : @ui.Style = @ui.style(w=S8, h=S8, radius=@sf.rail_corner, align=ACenter, justify=JCenter)

