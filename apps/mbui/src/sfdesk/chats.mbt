// The band over the sidebar's chats' lists (ember web/src/SidebarList.tsx NavTop; SidebarActions.tsx): 新建对话 and the
// filter; the lists under it are sfpages' (sidebar.mbt).

///|
/// The band over the lists (SidebarList.tsx NavTop): its top row, then 新建对话 and the filter (SidebarActions.tsx),
/// then 待处理 where the rail has no bell; on the sidebar's own ground, whole (no glass: asked, 2026-10-24), the closed
/// bar's as it closes (moved with it).
fn lists_band(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let (view, _) = chats_of(src, w.id, "all")
  let band = c.box(style=side_full.then(@ui.style(bg=Data(@sf.mix(apart_ground(), wide.band.get(), t.p.sidebar)))), fn() {
    side_top(c)
    // in the closed bar, what stands in its top right corner (the filter) 6 from its top and side, the band ending 6
    // under it (Sidebar.css.ts navNew, closed)
    let in_bar = wide.in_bar.get()
    c.box(style=if in_bar { band_new_bar() } else if wide.tape.get() { band_new_tape() } else { nav_new() }, fn() {
      let is_new = app.nav.top() is NewChat
      c.box(style=side_full, fn() {
        // (on one line with the search's field under it: its ground's edge, its mark and its words the band's; in the
        // column of the system's glass instead where the rail's places are there: rail_native.mbt)
        // (新建对话 the system's tab bar's own action where it has the places: the row the card's title there, the list
        // shown in the workspace, on the line of the page's title beside it: rail_native.mbt)
        if @sf.native_on() {
          // (as high as 新建对话's row, the filter beside it on the tape's line: band_new_tape_over)
          workspace_heading(c, src, w)
        } else if band_row(c, "side/new", is_new, fn() {
            band_mark(c, "compose", t.p.muted)
            band_words(c, @sf.t("web-main.sidebar.newChat"))
          }) {
          new_chat()
        }
      })
      |> ignore
      // catching up on what changed while away, before 更新 and the filter (the keys' size: brand.mbt)
      let (syncing, said) = match view {
        Some({ syncing: Some(y), .. }) => (true, y)
        _ => (false, "")
      }
      @sf.sync_key(c, "side/syncing", update_key_side, update_key_mark, syncing, said)
      // 更新 here, before the filter, wherever the sidebar shows this row (brand.mbt update_in_row)
      if update_shown() {
        update_in_row(c, src)
      }
      if @sf.native_on() {
        sidebar_glass(c, "sidebar/search", @sf.t("android-chat.search.field"), "search", [])
      }
      match view {
        // (never lit for the list shown: asked 2026-10-27)
        Some(v) if v.stations > 0 => filter_button(c, src, w, list_place(list_mode(src, w)), in_bar)
        _ => ()
      }
    })
    |> ignore
    // with no bell in the rail: 待处理 under 新建对话 (cloud/workspace.tsx SidebarTodo); the column's beside the system's
    if !@sf.native_on() {
      side_todo(c, src, w)
    }
  })
  // over the lists: their scroll bar keeps clear of it (the web's --nav-top)
  c.floats_over(band)
}

///|
/// The workspace icon and name share one native glass capsule.
fn workspace_heading(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let id = c.id("side/workspaces")
  let size = @sf.band_row_h()
  let b = c.box(style=@ui.style(w=Full, h=Fixed(size)), id~, fn() {  })
  native_workspace(c, src, w, b, id)
  c.semantics(b, Button, id~, label=w.name)
}

///|
/// Icon-only controls in the same native glass as the workspace switch.
fn sidebar_glass(c : @ui.Ctx, key : String, title : String, icon : String, menu : Array[(String, String, Bool, String)]) -> Unit {
  let id = c.id(key)
  let size = @sf.band_row_h()
  let b = c.box(style=@ui.style(w=Fixed(size), h=Fixed(size)), id~, fn() { })
  native_sidebar_items[id] = { id: key, title, icon: @sf.icon_path(icon), dot: false, prominent: false, menu }
  c.semantics(b, Button, id~, label=title)
}

///|
/// 新建对话's row and the filter beside it stand in every list's action's band (nav_new); in the closed bar the filter
/// where its link to the bar's top right corner puts it (filter_bar_link: as far from its top and side as the link is
/// in, the row's middle on it), 6 under.
fn band_new_bar() -> @ui.Style {
  let lift = (band_row_h() - filter_side) / 2.0
  let top = dmax(0.0, filter_bar_in - lift)
  band_new_bar_look.then(@ui.style(pr=@sf.room_of(filter_bar_in), pt=@sf.room_of(top), gap=@sf.keys_gap()))
}

///|
// kept across runs: a value (no field of it changes)
let band_new_bar_look : @ui.Style = @ui.css("row w=Full pl=S2 pb=S1_5 align=ACenter")

///|
/// The filter in the closed bar, linked to the corner it stands in, the bar's top right (@ui.CornerOf: the bar's there,
/// the window's less its 6 where it follows the window), `filter_bar_in` in from its top and side: its ground's corner
/// and its place both from this one link (band_new_bar, filter_box_bar), its corner following that one corner, not the
/// rail's places' at the bar's other side (the user, 2026-10-25: 「它应该关联它这边的那个圆角」).
fn filter_bar_link() -> @ui.CornerOf {
  Follow(@sf.closed_bar_of(rail_closed_ground_in), filter_bar_in, @sf.small_corner)
}

///|
/// How far in from the closed bar's top and side the filter stands (as the rail's places do from its edges).
let filter_bar_in : Double = 6.0

///|
/// In the sidebar's panel on the tape (laid out Medium, its corners @sf.tape_side_corners): the filter (a circle 32
/// across) in its top right corner on the tape's line, concentric with it (@sf.line_end_in, band_new_tape_over), under
/// the band's top row; where the corner is too square for that (it follows a round window), clear of it.
fn band_new_tape() -> @ui.Style {
  if @sf.native_on() {
    // The glass's outside edge follows the day heading's words, including the
    // list row's inner padding, not just the card's outer content margin.
    let list = @sf.theme().chat_list
    let inset = @sf.room_of(list.band_in + list.heading_in)
    return nav_new().then(@ui.style(pl=inset, pr=inset, pt=S1))
  }
  let corner = @sf.tape_side_corners()[1].radius()
  nav_new().then(
    @ui.style(
      pr=@sf.room_of(@sf.line_end_in(corner, band_new_end, side=filter_side)),
      pt=@sf.room_of(band_new_top + band_new_tape_over()),
    ),
  )
}

///|
/// How far under the top of the tape's sidebar the middle of its first row is (新建对话's, band_new_tape): the rail's
/// first place beside it stands on that line.
fn tape_first_row_mid() -> Double {
  side_top_h() + band_new_top + band_new_tape_over() + band_row_h() / 2.0
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
/// middle (as high as a band's row is: band_row_h), its top where it is concentric with the panel's corner: the tape's one line
/// (@sf.tape_bar_over), a page's bar's beside it.
fn band_new_tape_over() -> Double {
  let brand = side_top_h()
  let lift = (band_row_h() - filter_side) / 2.0
  let alone = brand + band_new_top + lift
  // (on the tape's line in the tape's corner; under a taller top row, 更新's or the window's buttons', it can not
  // stand so high: where it stands alone)
  let at = if (@sf.tape_side_corners()[1].radius() - @sf.tape_corner).abs() <= 0.5 {
    @sf.tape_line
  } else {
    alone
  }
  // (as high as its row reaches where the line is a little higher still, its top at the band's: the line 10.78, a
  // mouse's band's row 11, within the half a point the corner rule allows)
  if at < brand + lift - 0.5 {
    0.0
  } else {
    dmax(at, brand + lift) - alone
  }
}

///|
/// A row's icon (16).
let side_icon : Double = 16.0

///|
/// A new chat (新建对话, ⌘N): where the shell has it (beside the list on the wide frame, risen on the stack), the cursor in
/// its composer on any screen (its keyboard up with touch: composer_take_focus). On the tape
/// its page comes over: a new chat is opened to be written in (pengxiao, 2026-10-25: opened from the sidebar in use,
/// it showed beside it with the sidebar still in use).
pub fn new_chat() -> Unit {
  open_page(NewChat)
  // (on the tape its page brought over, from the sidebar in use too)
  if is_wide(@ui.current()) {
    bring_page()
  }
  // what it is opened for: the cursor in its words, its keyboard up with touch
  @sfpages.composer_take_focus()
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
let side_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L6)

///|
// kept across runs: a value (no field of it changes)
let side_words_bad : @ui.TextStyle = @ui.text_style(size=Ui, color=Danger, leading=L6)

///|
/// The list's filter (components.tsx MineFilter, compact): a circle 32 across, unmarked whichever list is shown, its tip 筛选会话; pressed, its menu (filter_menu).
fn filter_button(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  shown : String,
  in_bar : Bool,
) -> Unit {
  if @sf.native_on() {
    let rows = [("all", "web-main.filter.chats.all"), ("mine", "web-main.filter.chats.mine"),
      ("watching", "web-main.filter.watching"), ("archive", "web-main.filter.archived")].map(fn(p) {
        ("sidebar/filter/" + p.0, @sf.t(p.1), p.0 == (if shown == "chats" { "all" } else { shown }), "")
      })
    sidebar_glass(c, "sidebar/filter", @sf.t("web-main.filter.chats.named", args=[("named", filter_named(shown))]), "filter", rows)
    return
  }
  let t = @sf.theme()
  let id = c.id("side/filter")
  // its menu (sfpages' filter_menu): a filter its list, 已归档 the archive's list (rail_go)
  if c.clicked(id) {
    @sfpages.filter_menu(Of(id), if shown == "chats" { "all" } else { shown }, fn(f) {
      match f {
        "all" => rail_go(c, src, w, "chats")
        f => rail_go(c, src, w, f)
      }
    })
  }
  // its ground and colour moved over 140 ms (page.css.ts iconBtn: transition background, color)
  let hot = @kit.animate(c, "side/filter/hover", if c.lit(id) || @sfpages.filter_menu_open() { 1.0 } else { 0.0 }, transition=nav_fade)
  let ground = @sf.alpha(t.p.hover, hot)
  // (in the closed bar's corner, concentric with it as the rail's places are: Sidebar.css.ts navNew, closed)
  let look = if in_bar { filter_box_bar() } else { filter_box }
  let b = c.box(style=look.then(@ui.style(bg=Data(ground))), id~, fn() {
    @sf.icon(c, "filter", size=side_icon, color=@sf.mix(t.p.text, hot, t.p.muted)) |> ignore
  })
  c.semantics(b, Button, id~, label=@sf.t("web-main.filter.chats.named", args=[("named", filter_named(shown))]))
  @sf.tip(c, "side/filter-tip", id, @sf.t("web-main.filter.chats"))
}

///|
/// The list shown (list_place), named (MineFilter `named`): 已归档, 我参与的, 监控中, else 全部.
fn filter_named(filter : String) -> String {
  match filter {
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
/// In the closed bar's top right corner, its ground's corner linked to that corner (filter_bar_link: concentric with it,
/// a Mac's 6.4; as round as its half where the bar's corner is round enough, drawn so), never a circle that does not
/// follow it.
fn filter_box_bar() -> @ui.Style {
  filter_box.then(@ui.style(radius=Linked(filter_bar_link())))
}
