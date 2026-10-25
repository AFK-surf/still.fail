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
  let band = c.box(style=side_full.then(@ui.style(bg=Data(@sf.mix(apart_ground(), wide.band, t.p.sidebar)))), fn() {
    side_top(c)
    // in the closed bar, what stands in its top right corner (the filter) 6 from its top and side, the band ending 6
    // under it (Sidebar.css.ts navNew, closed)
    let in_bar = wide.in_bar
    c.box(style=if in_bar { band_new_bar } else if wide.tape { band_new_tape() } else { nav_new }, fn() {
      let is_new = app.nav.top() is NewChat
      c.box(style=side_full, fn() {
        // (on the tape over the search's field: its ground's edge on the field's, its icon and words on the field's)
        let over = if wide.tape { tape_new_over_search } else { 0.0 }
        if band_row(c, "side/new", is_new, fn() {
            c.box(tx=-compose_in + over, fn() { @sf.icon(c, "compose", size=side_icon, color=t.p.muted) |> ignore })
            |> ignore
            c.box(style=side_full, tx=over, fn() { band_words(c, @sf.t("web-main.sidebar.newChat")) }) |> ignore
          }) {
          new_chat()
        }
      })
      |> ignore
      // (on the tape 更新 here, before the filter: brand.mbt update_in_row)
      if wide.tape && !in_bar && update_shown() {
        update_in_row(c, src)
      }
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
  // over the lists: their scroll bar keeps clear of it (the web's --nav-top)
  c.floats_over(band)
}

///|
/// 新建对话's row and the filter beside it stand in every list's action's band (nav_new); in the closed bar 6 from its
/// side and 6 under.
// kept across runs: a value (no field of it changes)
let band_new_bar : @ui.Style = @ui.css("row w=Full pl=S2 pr=S1_5 pt=S1_5 pb=S1_5 gap=S1 align=ACenter")

///|
/// In the sidebar's panel on the tape (laid out Medium, its corners @sf.tape_side_corners): the filter (a circle 32
/// across) in its top right corner on the tape's line, concentric with it (@sf.line_end_in, band_new_tape_over), under
/// the band's top row; where the corner is too square for that (it follows a round window), clear of it.
fn band_new_tape() -> @ui.Style {
  let corner = @sf.tape_side_corners()[1].radius()
  nav_new.then(
    @ui.style(
      pl=S4,
      pr=@sf.room_of(@sf.line_end_in(corner, band_new_end)),
      pt=@sf.room_of(band_new_top + band_new_tape_over()),
    ),
  )
}

///|
/// How far under the top of the tape's sidebar the middle of its first row is (新建对话's, band_new_tape): the rail's
/// first place beside it stands on that line.
fn tape_first_row_mid() -> Double {
  side_top_h() + band_new_top + band_new_tape_over() + nav_row_h() / 2.0
}

///|
/// nav_new's end and top (px=S2, pt=S1_5).
let band_new_end : Double = 8.0

///|
let band_new_top : Double = 6.0

///|
/// The filter's side: a circle 32 across.
let filter_side : Double = 32.0

///|
/// How much taller 新建对话's row is in a panel of the tape (band_new_tape over nav_new's 6): the filter, in the row's
/// middle (as high as a row is: nav_row_h), its top where it is concentric with the panel's corner: the tape's one line
/// (@sf.tape_bar_over), a page's bar's beside it.
fn band_new_tape_over() -> Double {
  let brand = side_top_h()
  let lift = (nav_row_h() - filter_side) / 2.0
  let alone = brand + band_new_top + lift
  // (on the tape's line in the ladder's pane corner; under a taller top row, 更新's or the window's buttons', it can not
  // stand so high: where it stands alone)
  let at = if (@sf.tape_side_corners()[1].radius() - @sf.pane_corner).abs() <= 0.5 {
    @sf.tape_line
  } else {
    alone
  }
  if at < brand + lift {
    0.0
  } else {
    at - alone
  }
}

///|
/// A row's icon (16), 新建对话's a pixel in (Sidebar.css.ts navCompose: aligned with the 14px check under it).
let side_icon : Double = 16.0

///|
let compose_in : Double = 1.0

///|
/// On the tape 新建对话 stands over the search's field, as a ground the same (pengxiao, 2026-10-25: their edges, lit and
/// not, out of line): its ground 16 in as the field's (band_new_tape), and its icon and words drawn on as far as the
/// field's are (its 12 in and a 17 icon, to the row's 10 and 16).
let tape_new_over_search : Double = 3.0

///|
/// A new chat (新建对话, ⌘N): where the shell has it (beside the list on the wide frame, risen on the stack), the cursor in
/// its composer on any screen (its keyboard up on a touch device: composer_take_focus). On the tape
/// its page comes over: a new chat is opened to be written in (pengxiao, 2026-10-25: opened from the sidebar in use,
/// it showed beside it with the sidebar still in use).
pub fn new_chat() -> Unit {
  open_page(NewChat)
  // what it is opened for: the cursor in its words, its keyboard up on a touch device
  @sfpages.composer_take_focus()
  if wide.tape {
    wide.tape_ask = Some(Page)
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
/// The list's filter (components.tsx MineFilter, compact): a circle 32 across, in the accent's ground while it narrows the
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
        "decisions" => @sfbase.go_place("decisions") |> ignore
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
let filter_box : @ui.Style = @ui.css("w=S8 h=S8 radius=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let filter_box_bar : @ui.Style = @ui.css("w=S8 h=S8 radius=Full align=ACenter justify=JCenter")

