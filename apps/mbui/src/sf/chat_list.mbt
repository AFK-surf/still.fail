// The chats' lists' sizes on the screen in force (docs/architecture.md: sizes, row heights and density are the
// theme's, by the native input): keyboard and mouse's the web's sidebar (Sidebar.css.ts navSession…, RowPicture.css.ts,
// ChatMark.css.ts), touch's the phone's home (mobile/Home.css.ts mChatRow…, Home.kt). The rows, their second
// line, what stands at its end, the days' headings, the list's waiting and how its rows and panes move. One set of
// pages draws them (sfpages' sidebar.mbt, chat_row.mbt, chat_mark.mbt, row_picture.mbt), taking them from here.

///|
/// A chats' list on this screen (Theme::chat_list).
pub(all) struct ChatList {
  /// a row's height as the list first takes it (navSession 54, mChatRow 66)
  row_h : Double
  /// the row (how far in its words are and whether its ground is rounded: where its list stands, list_row_in): its box, its words' column (settled: at 45%), its title's line (with room for 归档 at its end where a
  /// pointer shows it), its second line
  row : @ui.Style
  text : @ui.Style
  head : @ui.Style
  meta : @ui.Style
  /// its title's line's height (a row's mark beside it: a sidebar list's item's)
  head_h : Double
  /// its title (unread: heavier) and what was said last
  title : @ui.TextStyle
  title_unread : @ui.TextStyle
  last : @ui.TextStyle
  /// a row with another under it across the whole screen (2 between with keyboard and mouse, none with touch; in a
  /// side column: list_more)
  more : @ui.Style
  /// in a side column, where its ground is rounded (list_row_in): how far in from the row's end and foot what stands in
  /// its foot's end corner is (list_row `corner`: a chat's people), concentric with the row's corner
  aside_end : Double
  /// its second line from where its chat stands (chat_mark's state line): quiet, the viewer's turn, a message that did
  /// not go; a card's lead word
  state_quiet : @ui.TextStyle
  state_turn : @ui.TextStyle
  state_alert : @ui.TextStyle
  state_lead : @ui.TextStyle
  /// where a chat stands at the end of its messages (sfpages' chat_state): its icon's column, 10 wide (the row's
  /// leadSlot), as high as a line of the state's words, its icon in the middle (wrapping, the first line's)
  state_slot : @ui.Style
  /// what stands at its end (row_picture): an agent's mark, a face across, a face's box and one after the first (3 of
  /// it over the one before), the pixel of ground round a face, who started it ringed
  agent_mark : Double
  face_d : Double
  face : @ui.Style
  face_after : @ui.Style
  face_ground : @ui.Style
  face_ring : @ui.Style
  /// the room over its first row and under its last, past what the frame gives (navScroll's padding; none on a touch
  /// device, across the whole screen its rows' grounds reaching its edges); under its last in a side column
  /// (list_foot_in): navScroll's with keyboard and mouse, touch's as far as its rows stand in from the column's sides
  /// (band_in), its last row's ground as clear of its foot, in a panel's foot corners as in its sides
  top_in : Double
  foot_in : Double
  side_foot_in : Double
  /// what stands over a sidebar's list, in a line with its rows (新建对话, 待处理, the search's field): how far in from
  /// the list's edge its ground is, its words from its ground, its mark, its height, its words: one set, so they stand
  /// on one line (keyboard and mouse's the web's navNew row: 8, 10, 16, 32, 13; touch's the phone's search field: 16,
  /// 12, 17, 38, 15)
  band_in : Double
  band_pad : Double
  band_icon : Double
  band_h : Double
  band_words : @ui.TextStyle
  /// a row as high as what it holds (list_row: a station's, a folder's, a profile's, laid out as a chat's: its mark
  /// beside its first line, its words from the top)
  item : @ui.Style
  /// a sidebar's other lists (the files' places, the settings'), in a side column (list_line Side): their box, a row of
  /// one line, where something goes while there is none, a folder that takes a drop
  side_list : @ui.Style
  side_row : @ui.Style
  side_hint : @ui.Style
  side_drop : @ui.Style
  /// a day's heading, a sidebar list's (navHeading; the phone's section header): over and under it (how far in:
  /// where its list stands, list_heading_in), and in a side column how far in from the line its rows stand on (a
  /// computer's 8; touch's its rows' words')
  heading : @ui.Style
  heading_in : Double
  heading_words : @ui.TextStyle
  /// read the first time: how many rows are shown in their bones while it reads, and while what it waits on says so
  waiting_rows : Int
  waiting_noted : Int
  /// whether the screen has keys to find and choose with: ⌘K, ↑ ↓ and Enter in what is found, the one chosen shown so (a
  /// computer's); else the search is at the list's top, scrolled to (touch's: Home.kt top)
  keys : Bool
  /// what search finds, a line each (Found)
  found : Found
  /// how its panes slide one to another (navTrack: 240 ease-out; mHomePane: 240 standard) and how a row moves as the
  /// list changes (motion.ts MOVE; the phone's row spring)
  slide : @motion.Spec
  move : @motion.Spec
}

///|
/// Keyboard and mouse's (Sidebar.css.ts navRow, navSession: 54 high, 7 by 10 in, its words from the top, its corner a sidebar
/// row's; two lines 2 apart, its title 13 on 20, 500 while something in it is unread; its second line 12 on 18; faces
/// 16, marks 12; navHeading 12 on 18, muted, 14 above and 4 under).
// kept across runs: a value (no field of it changes)
pub let mouse_chat_list : ChatList = {
  row_h: 54.0,
  // (its title's line's middle where 归档's is: row_top_in_y)
  row: @ui.style(
    row=true,
    w=Full,
    h=side_row_h,
    pt=room(row_top_in_y),
    pb=room(row_foot_in_y),
    gap=S2,
    align=AStart,
  ),
  // (SidebarList.css.ts item: 7 over and under, as a chat's row)
  item: @ui.style(row=true, w=Full, min_h=S8, py=row_in, gap=S2, align=AStart),
  text: @ui.css("w=Full gap=S0_5"),
  head: @ui.css("row w=Full h=S5 gap=S1_5 align=ACenter"),
  // (pointed at, room at its end for 归档: 24)
  head_h: mouse_head_h,
  meta: @ui.css("row w=Full h=S4_5 gap=S1_5 align=ACenter"),
  title: @ui.text_style(size=Ui, color=Fg, leading=L6, wrap=false, w=Full),
  title_unread: @ui.text_style(size=Ui, weight=Medium, color=Fg, leading=L6, wrap=false, w=Full),
  last: @ui.text_style(size=Meta, color=Muted, leading=L5, wrap=false, w=Full),
  more: @ui.css("w=Full pb=S0_5"),
  // (as far from the row's foot as from its end: its last face concentric with the row's foot corner when its ground
  // shows)
  aside_end: capsule_in(row_corner, mouse_face_d),
  state_quiet: @ui.text_style(size=Meta, color=Muted, leading=L5, wrap=false, w=Full),
  state_turn: @ui.text_style(size=Meta, color=Fg, leading=L5, wrap=false, w=Full),
  state_alert: @ui.text_style(size=Meta, color=Danger, leading=L5, wrap=false, w=Full),
  state_lead: @ui.text_style(weight=Semibold, w=Hug),
  state_slot: @ui.css("w=S2_5 h=S4_5 justify=JCenter"),
  agent_mark: 12.0,
  face_d: mouse_face_d,
  face: @ui.css("w=S4 h=S4"),
  face_after: @ui.style(w=side_face_step, h=S4),
  face_ground: @ui.css("w=S4_5 h=S4_5 radius=Full"),
  face_ring: @ui.css("w=S5 h=S5 radius=Full border=B1 border_color=Fg"),
  top_in: 4.0,
  foot_in: 12.0,
  side_foot_in: 12.0,
  band_in: mouse_band_in,
  band_pad: mouse_band_pad,
  band_icon: 16.0,
  band_h: 32.0,
  band_words: @ui.text_style(size=Ui, color=Fg, leading=L6, wrap=false, w=Full),
  side_list: @ui.css("w=Full h=Full px=S2"),
  side_row: @ui.css("row w=Full min_h=S8 px=S2_5 py=S1_5 gap=S2").then(@ui.style(radius=side_row_radius)),
  side_hint: @ui.css("row w=Full px=S2_5 py=S1_5 gap=S2 align=ACenter"),
  side_drop: @ui.css("w=Full").then(@ui.style(radius=side_row_radius)),
  heading: @ui.css("w=Full pt=S3_5 pb=S1"),
  heading_in: 8.0,
  heading_words: @ui.text_style(size=Meta, color=Muted, leading=L5, wrap=false),
  waiting_rows: 10,
  waiting_noted: 6,
  keys: true,
  found: mouse_found,
  slide: @motion.move(),
  move: @motion.move_spring,
}

///|
/// Touch's (mobile/Home.css.ts mChatRow: 66 high, 22 in on the left and 16 on the right, two lines in its
/// middle; its title 16 on 22, 600 while something in it is unread; its second line 14 on 20; faces 18, marks 14; the
/// phone's section header 15 bold in ink, 20 in, 14 above and 6 under).
// kept across runs: a value (no field of it changes)
pub let touch_chat_list : ChatList = {
  row_h: touch_list_row_h,
  row: @ui.style(row=true, w=Full, h=Fixed(touch_list_row_h), gap=S1_5, align=ACenter),
  // (SidebarList.css.ts phone: 10 over and under, its mark's column 8 from its words)
  item: @ui.css("row w=Full py=S2_5 gap=S2 align=AStart"),
  text: @ui.css("w=Full justify=JCenter"),
  head: @ui.style(row=true, w=Full, h=Fixed(touch_title_h), gap=S2, align=ACenter),
  head_h: touch_title_h,
  meta: @ui.css("row w=Full h=S5 gap=S2 align=ACenter"),
  title: @ui.text_style(size=Ui, color=Fg, leading=L7, wrap=false, w=Full),
  title_unread: @ui.text_style(size=Ui, weight=Semibold, color=Fg, leading=L7, wrap=false, w=Full),
  last: @ui.text_style(size=Meta, color=Muted, leading=L6, wrap=false, w=Full),
  more: full_width,
  aside_end: capsule_in(row_corner, touch_face_d),
  state_quiet: @ui.text_style(size=Meta, color=Muted, leading=L6, wrap=false, w=Full),
  state_turn: @ui.text_style(size=Meta, color=Fg, leading=L6, wrap=false, w=Full),
  state_alert: @ui.text_style(size=Meta, color=Danger, leading=L6, wrap=false, w=Full),
  // (bold, as the phone's: Home.kt StateLine)
  state_lead: @ui.text_style(weight=Bold, w=Hug),
  state_slot: @ui.css("w=S2_5 h=S5 justify=JCenter"),
  agent_mark: 14.0,
  face_d: touch_face_d,
  face: @ui.css("w=S4_5 h=S4_5"),
  face_after: @ui.style(w=touch_face_step, h=S4_5),
  face_ground: @ui.css("w=S5 h=S5 radius=Full"),
  face_ring: @ui.style(w=touch_face_ring, h=touch_face_ring, radius=Full, border=B1, border_color=Fg),
  top_in: 0.0,
  foot_in: 0.0,
  side_foot_in: touch_band_in,
  band_in: touch_band_in,
  band_pad: touch_band_pad,
  band_icon: 17.0,
  band_h: 38.0,
  band_words: @ui.text_style(size=Ui, color=Fg, wrap=false, w=Full),
  // (in a side column as keyboard and mouse's are, their grounds in and rounded, a finger's height and words)
  side_list: @ui.style(w=Full, h=Full, px=room(touch_band_in)),
  side_row: @ui.css("row w=Full py=S2_5 gap=S2 align=ACenter").then(@ui.style(px=room(touch_band_pad), radius=side_row_radius)),
  side_hint: @ui.css("row w=Full py=S2_5 gap=S2 align=ACenter").then(@ui.style(px=room(touch_band_pad))),
  side_drop: @ui.css("w=Full").then(@ui.style(radius=side_row_radius)),
  heading: @ui.css("w=Full pt=S3_5 pb=S1_5"),
  heading_in: touch_band_pad,
  heading_words: @ui.text_style(size=Body, weight=Semibold, color=Fg, wrap=false),
  waiting_rows: 9,
  waiting_noted: 4,
  keys: false,
  found: touch_found,
  slide: @motion.move(),
  move: @motion.row_spring,
}

///|
/// What stands over a sidebar's list: how far in its ground is and its words from it (band_in, band_pad).
let mouse_band_in : Double = 8.0

///|
let mouse_band_pad : Double = 10.0

///|
let touch_band_in : Double = 16.0

///|
let touch_band_pad : Double = 12.0

///|
/// Where a list stands: in a side column beside a page (the wide frame's sidebar, on the tape or keyboard and mouse's) or a
/// panel over it (⌘K's), or across the whole screen (a phone's home, its search). How far in its rows are and whether their grounds are rounded follow it,
/// not the native input (asked, 2026-10-25: touch's square rows, lit, in a tape's sidebar beside 新建对话's
/// round ground).
pub(all) enum ListAt {
  Side
  Whole
} derive(Eq)

///|
/// Where a list's lines stand (Sidebar.css.ts navScroll): in a side column as far in from its sides as what stands
/// over the list (band_in: 新建对话's ground, the search's field), clear of its edge; across the whole screen, a row's
/// ground its whole width.
pub fn list_line(at : ListAt) -> @ui.Style {
  match at {
    Side => @ui.style(w=Full, px=room(list_line_in(at)))
    Whole => full_width
  }
}

///|
/// How far in from each side of its box a list's lines stand (list_line).
pub fn list_line_in(at : ListAt) -> Double {
  match at {
    Side => theme().chat_list.band_in
    Whole => 0.0
  }
}

///|
/// How far under its last line a list's box goes, past what the frame gives (Sidebar.css.ts navScroll's foot): in a
/// side column the theme's side_foot_in, its last row clear of the column's foot as of its sides; across the whole
/// screen its foot_in.
pub fn list_foot_in(at : ListAt) -> Double {
  let l = theme().chat_list
  match at {
    Side => l.side_foot_in
    Whole => l.foot_in
  }
}

///|
/// How far in a chat row's words are from its ground, and its ground's corner: in a side column its words as
/// 新建对话's (band_pad) from both sides (navSession: a navRow's 10 either side; what stands in its foot's end corner
/// placed there by itself: list_row `corner`), rounded as a sidebar's row; across the whole screen as the phone's
/// (mChatRow: 22 at the left, 16 at the right), square.
pub fn list_row_in(at : ListAt) -> @ui.Style {
  let l = theme().chat_list
  match at {
    Side => @ui.style(px=room(l.band_pad), radius=side_row_radius)
    Whole => whole_row_in
  }
}

///|
// kept across runs: a value (no field of it changes)
let whole_row_in : @ui.Style = @ui.style(pl=phone_row_in, pr=S4)

///|
/// What holds a row of a list moved across in it (a finger's swipe): the row's own place, what moves in it cut to the
/// row's ground's corners where its list stands (list_row_in): rounded in a side column, square across the whole screen.
pub fn list_row_slot(at : ListAt) -> @ui.Style {
  match at {
    Side => side_row_slot
    Whole => whole_row_slot
  }
}

///|
// kept across runs: a value (no field of it changes)
let side_row_slot : @ui.Style = @ui.style(w=Full, clip=true, radius=side_row_radius)

///|
// kept across runs: a value (no field of it changes)
let whole_row_slot : @ui.Style = @ui.css("w=Full clip")

///|
/// How far in a list's heading is: in a side column the theme's (heading_in, from the list's line); across the whole
/// screen the phone's section header's (20).
pub fn list_heading_in(at : ListAt) -> @ui.Style {
  match at {
    Side => @ui.style(px=room(theme().chat_list.heading_in))
    Whole => whole_heading_in
  }
}

///|
// kept across runs: a value (no field of it changes)
let whole_heading_in : @ui.Style = @ui.css("px=S5")

///|
/// How far in a found line is and its corner, where its list stands: in a side column or a panel (⌘K's, the tape's
/// sidebar's search) 12 in, rounded as a menu's row (Switcher.css.ts: 12 in); across the whole screen the phone's
/// (mFound: 22 at the left, 16 at the right), square.
pub fn found_row_in(at : ListAt) -> @ui.Style {
  match at {
    Side => found_side_row
    Whole => found_whole_row
  }
}

///|
// kept across runs: a value (no field of it changes)
let found_side_row : @ui.Style = @ui.style(px=S3, radius=InnerOr(row_radius))

///|
// kept across runs: a value (no field of it changes)
let found_whole_row : @ui.Style = @ui.style(pl=found_start, pr=S4)

///|
/// How far in a found list's quiet words are (none found, the stations still answering, what the core says): as its
/// lines' words, in a side column or a panel 12, across the whole screen the phone's 22.
pub fn found_line_in(at : ListAt) -> @ui.Style {
  match at {
    Side => found_side_in
    Whole => found_whole_in
  }
}

///|
// kept across runs: a value (no field of it changes)
let found_side_in : @ui.Style = @ui.css("px=S3")

///|
// kept across runs: a value (no field of it changes)
let found_whole_in : @ui.Style = @ui.style(px=found_start)

///|
/// How far in a found kind's heading is: in a side column or a panel as its lines' words (12), across the whole
/// screen the phone's section header's (20).
pub fn found_head_in(at : ListAt) -> @ui.Style {
  match at {
    Side => found_side_in
    Whole => whole_heading_in
  }
}

///|
/// Touch's chat row's height and its title's line (mobile/Home.css.ts mChatRow, mChatLine1).
pub let touch_list_row_h : Double = 66.0

///|
let touch_title_h : Double = 22.0

///|
/// Touch's chat row's second line (meta: S5) and a face at its end.
let touch_meta_h : Double = 20.0

///|
let touch_face_d : Double = 18.0

///|
/// Keyboard and mouse's face at a row's end, its row's padding over its foot (row_in) and its second line's height (meta: S4_5).
let mouse_face_d : Double = 16.0

///|
let mouse_row_in : Double = 7.0

///|
/// Keyboard and mouse's chat row's title's line's height (head: S5).
let mouse_head_h : Double = 20.0

///|
let mouse_meta_h : Double = 18.0

///|
/// What search finds on this screen (sfpages' switcher.mbt: ⌘K's list, the phone's search page), one design: a line
/// each, its mark (an icon, an agent's maker, a station's mark), its first line (what it is, or the words found in it)
/// with who, where and when at its end, and where it is under it (its chat, its line with the words) where it says one;
/// the kinds under their headings; 全部结果 and 查看更多 in the link's ink; quiet words, the stations still answering.
/// Its sizes the screen's: keyboard and mouse's the web's ⌘K (Switcher.css.ts: rows 38, two lines 54, 13 and 12), a touch
/// device's the phone's search (mobile/Home.css.ts mFound…: rows 50, two lines 66, 15 and 14).
pub(all) struct Found {
  /// a line's height as the list first takes it: one line, two, a heading, quiet words
  row_h : Double
  two_h : Double
  head_h : Double
  quiet_h : Double
  /// a line (chosen by the keys: on the words' tint), one of two lines (how far in and whether rounded: where the
  /// list stands, found_row_in)
  row : @ui.Style
  two : @ui.Style
  /// its mark's box, an icon's size and an agent's maker's in it
  mark : @ui.Style
  icon : Double
  logo : Double
  /// its words' column, its first line (two lines' first), the line under it where who and when are beside it
  column : @ui.Style
  first : @ui.Style
  second : @ui.Style
  /// what it is, the words found (marked), where it is under it, its line with the words (marked), who and when
  title : @ui.TextStyle
  words : @ui.TextStyle
  under : @ui.TextStyle
  under_words : @ui.TextStyle
  meta : @ui.TextStyle
  /// 全部结果 and 查看更多
  link : @ui.TextStyle
  /// a kind's heading (how far in: found_head_in)
  head : @ui.Style
  head_words : @ui.TextStyle
  /// quiet words (none found), the stations still answering (one that failed closer), what the core says (how far
  /// in: found_line_in)
  quiet : @ui.Style
  quiet_words : @ui.TextStyle
  wait : @ui.Style
  wait_failing : @ui.Style
  said_words : @ui.TextStyle
}

///|
/// Keyboard and mouse's (Switcher.css.ts: a row 38 high at least, 8 over and under and 12 in, its parts 10 apart, rounded as
/// its panel's corner leaves for it; chosen, on the words' 7%; its mark 20, icons 16, makers 18; 13 and 12; a heading
/// 12 muted, 12 in, 10 over and 4 under).
// kept across runs: a value (no field of it changes)
pub let mouse_found : Found = {
  row_h: mouse_found_row_h,
  two_h: 54.0,
  head_h: 32.0,
  quiet_h: 54.0,
  row: @ui.style(row=true, w=Full, min_h=Fixed(mouse_found_row_h), py=S2, gap=S2_5, align=ACenter, selected=@ui.patch(bg=Tint)),
  two: @ui.style(row=true, w=Full, min_h=Fixed(mouse_found_row_h), py=S2, gap=S2_5, align=AStart, selected=@ui.patch(bg=Tint)),
  mark: @ui.css("w=S5 h=S5 align=ACenter justify=JCenter"),
  icon: 16.0,
  logo: 18.0,
  column: @ui.style(w=grow, gap=S0_5),
  first: @ui.css("row w=Full gap=S2_5 align=ACenter"),
  second: @ui.css("row w=Full gap=S2_5 align=ACenter"),
  title: @ui.text_style(size=Ui, color=Fg, wrap=false, w=grow),
  words: @ui.text_style(size=Ui, color=Fg, max_lines=1, w=Full),
  under: @ui.text_style(size=Meta, color=Muted, wrap=false, w=grow),
  under_words: @ui.text_style(size=Meta, color=Muted, max_lines=1, w=grow),
  meta: @ui.text_style(size=Meta, color=Muted, wrap=false),
  link: @ui.text_style(size=Ui, color=Link, wrap=false, w=grow),
  head: @ui.css("w=Full pt=S2_5 pb=S1"),
  head_words: @ui.text_style(size=Meta, color=Muted, wrap=false),
  quiet: @ui.css("w=Full py=S3_5"),
  quiet_words: @ui.text_style(size=Meta, color=Muted),
  wait: @ui.css("w=Full pt=S2 pb=S2_5"),
  wait_failing: @ui.css("w=Full pt=S2 pb=S2_5"),
  said_words: @ui.text_style(size=Meta, color=Muted, w=Full),
}

///|
/// Touch's (mobile/Home.css.ts mFound…, Search.kt: a row 50 high, 66 with a line under, 22 in on the left
/// and 16 on the right, its parts 12 apart; its mark 20, icons and makers 18; 15 on 22 and 14 on 20; the phone's
/// section header for a kind's heading; quiet words 22 in, 16 over and under).
// kept across runs: a value (no field of it changes)
pub let touch_found : Found = {
  row_h: touch_found_row_h,
  two_h: touch_found_two_h,
  head_h: 41.0,
  quiet_h: 44.0,
  row: @ui.style(row=true, w=Full, min_h=Fixed(touch_found_row_h), gap=S3, align=ACenter),
  two: @ui.style(row=true, w=Full, min_h=Fixed(touch_found_two_h), gap=S3, align=ACenter),
  mark: @ui.css("w=S5 h=S5 align=ACenter justify=JCenter"),
  icon: 18.0,
  logo: 18.0,
  column: @ui.style(w=grow, justify=JCenter),
  first: @ui.style(row=true, w=Full, h=found_line_h, gap=S2, align=ACenter),
  second: @ui.css("row w=Full h=S5 gap=S2 align=ACenter"),
  title: @ui.text_style(size=Ui, leading=L7, color=Fg, wrap=false, w=grow),
  words: @ui.text_style(size=Ui, leading=L7, color=Fg, max_lines=1, w=Full),
  under: @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false, w=grow),
  under_words: @ui.text_style(size=Meta, leading=L6, color=Muted, max_lines=1, w=grow),
  meta: @ui.text_style(size=Meta, color=Muted, wrap=false),
  link: @ui.text_style(size=Ui, color=Link, wrap=false, w=grow),
  head: @ui.css("w=Full pt=S3_5 pb=S1_5"),
  head_words: @ui.text_style(size=Ui, weight=Semibold, color=Fg, wrap=false),
  quiet: @ui.css("w=Full py=S4"),
  quiet_words: @ui.text_style(size=Meta, color=Muted, w=Full),
  wait: @ui.css("w=Full py=S3"),
  wait_failing: @ui.css("w=Full py=S1_5"),
  said_words: @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full),
}

///|
/// A line of what is found, as high as it is at least: keyboard and mouse's 38, touch's 50 (66 with a line under).
let mouse_found_row_h : Double = 38.0

///|
let touch_found_row_h : Double = 50.0

///|
let touch_found_two_h : Double = 66.0
