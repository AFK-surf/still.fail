// The band over the sidebar's chats' lists (ember web/src/SidebarList.tsx NavTop; SidebarActions.tsx): 新建对话 and the
// filter; the lists under it are sfpages' (sidebar.mbt).

///|
/// A value in the band's open and floating looks, on the block's own trajectory between them (`at`'s: the old views'
/// as the frame has said it, else the tree's where its block is).
fn band_between(open : Double, bar : Double, at? : BandAt = band_at_old()) -> Double {
  open + (bar - open) * at.band
}

///|
/// What a sidebar's band is laid out by, as its block stands: its top row's height, where the block's move has got
/// between open and the floating bar, whether on the tape or drawn in the closed bar, what linked corners are worked
/// out from. The old views' (band_at_old) or a node's of the tree where its block is (side_node's, from
/// SideAt and @ui.tree_corner_roots_now).
priv struct BandAt {
  brand : Double
  band : Double
  tape : Bool
  in_bar : Bool
  roots : @ui.CornerRoots
}

///|
/// BandAt as the old views have it: as the frame said it as it drew the block (fold_bars, tape_under).
fn band_at_old() -> BandAt {
  { brand: side_top_h(), band: wide.band, tape: wide.tape, in_bar: wide.in_bar, roots: @ui.corner_roots() }
}

///|
/// The top and bottom of the action's band. Its list uses these same values for the room over its rows.
fn band_pane_top(at? : BandAt = band_at_old()) -> Double {
  let lift = (band_row_h() - filter_side) / 2.0
  band_between(band_new_top, dmax(0.0, filter_bar_in - lift), at~)
}

///|
fn band_pane_under(at? : BandAt = band_at_old()) -> Double {
  band_between(side_new_under, bar_band_in, at~)
}

///|
/// The action and filter follow the block from the open band's insets to the floating bar's insets.
fn band_new_pane(at? : BandAt = band_at_old()) -> @ui.Style {
  let inset = @sf.theme().chat_list.band_in
  nav_new().then(@ui.style(
    pl=@sf.room_of(band_between(inset, bar_band_start, at~)),
    pr=@sf.room_of(band_between(inset, filter_bar_in, at~)),
    pt=@sf.room_of(band_pane_top(at~)),
    pb=@sf.room_of(band_pane_under(at~)),
  ))
}

///|
/// The action's inset at the start of the floating bar.
let bar_band_start : Double = 8.0

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
fn band_new_tape(at? : BandAt = band_at_old()) -> @ui.Style {
  if @sf.native_on() {
    // The glass's outside edge follows the day heading's words, including the
    // list row's inner padding, not just the card's outer content margin.
    let list = @sf.theme().chat_list
    let inset = @sf.room_of(list.band_in + list.heading_in)
    return nav_new().then(@ui.style(pl=inset, pr=inset, pt=S1))
  }
  let corner = @sf.tape_side_corners()[1].radius(at.roots)
  nav_new().then(
    @ui.style(
      pr=@sf.room_of(@sf.line_end_in(corner, band_new_end, side=filter_side)),
      pt=@sf.room_of(band_new_top + band_new_tape_over(at~)),
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
fn band_new_tape_over(at? : BandAt = band_at_old()) -> Double {
  let brand = at.brand
  let lift = (band_row_h() - filter_side) / 2.0
  let alone = brand + band_new_top + lift
  // (on the tape's line in the tape's corner; under a taller top row, 更新's or the window's buttons', it can not
  // stand so high: where it stands alone)
  let line = if (@sf.tape_side_corners()[1].radius(at.roots) - @sf.tape_corner).abs() <= 0.5 {
    @sf.tape_line
  } else {
    alone
  }
  // (as high as its row reaches where the line is a little higher still, its top at the band's: the line 10.78, a
  // mouse's band's row 11, within the half a point the corner rule allows)
  if line < brand + lift - 0.5 {
    0.0
  } else {
    dmax(line, brand + lift) - alone
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
/// The list shown (list_place), named (MineFilter `named`): 已归档, 我参与的, 监控中, else 全部.
fn filter_named(filter : String) -> String {
  match filter {
    "archive" => @sf.t("web-main.filter.archived")
    "mine" => @sf.t("web-main.filter.chats.mine")
    "watching" => @sf.t("web-main.filter.watching")
    "hidden" => @sf.t("web-main.filter.hidden")
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
