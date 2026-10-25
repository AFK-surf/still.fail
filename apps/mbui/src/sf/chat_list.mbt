// The chats' lists' sizes on the screen in force (docs/architecture.md: sizes, row heights and density are the
// theme's, by the screen's kind): a computer's the web's sidebar (Sidebar.css.ts navSession…, RowPicture.css.ts,
// ChatMark.css.ts), a touch device's the phone's home (mobile/Home.css.ts mChatRow…, Home.kt). The rows, their second
// line, what stands at its end, the days' headings, the list's waiting and how its rows and panes move. One set of
// pages draws them (sfpages' sidebar.mbt, chat_row.mbt, chat_mark.mbt, row_picture.mbt), taking them from here.

///|
/// A chats' list on this screen (Theme::chat_list).
pub(all) struct ChatList {
  /// a row's height as the list first takes it (navSession 54, mChatRow 66)
  row_h : Double
  /// the row: its box, its words' column (settled: at 45%), its title's line (with room for 归档 at its end where a
  /// pointer shows it), its second line
  row : @ui.Style
  text : @ui.Style
  text_settled : @ui.Style
  head : @ui.Style
  head_room : @ui.Style
  meta : @ui.Style
  /// its title (unread: heavier) and what was said last
  title : @ui.TextStyle
  title_unread : @ui.TextStyle
  last : @ui.TextStyle
  /// a row beside a rail: a touch device's as far in from its list's left as from its right
  beside_rail : @ui.Style
  /// a row with another under it (2 between on a computer, none on a touch device)
  more : @ui.Style
  /// how far over its second line's middle what stands at its end does (concentric with a computer's row's foot
  /// corner)
  aside_lift : Double
  /// its second line from where its chat stands (chat_mark's state line): quiet, the viewer's turn, a message that did
  /// not go; a card's lead word
  state_quiet : @ui.TextStyle
  state_turn : @ui.TextStyle
  state_alert : @ui.TextStyle
  state_lead : @ui.TextStyle
  /// what stands at its end (row_picture): an agent's mark, a face across, a face's box and one after the first (3 of
  /// it over the one before), the pixel of ground round a face, who started it ringed
  agent_mark : Double
  face_d : Double
  face : @ui.Style
  face_after : @ui.Style
  face_ground : @ui.Style
  face_ring : @ui.Style
  /// the room over its first row and under its last, past what the frame gives (navScroll's padding; none on a touch
  /// device)
  top_in : Double
  foot_in : Double
  /// what stands over a sidebar's list, in a line with its rows (新建对话, 待处理, the search's field): how far in from
  /// the list's edge its ground is, its words from its ground, its mark, its height, its words: one set, so they stand
  /// on one line (a computer's the web's navNew row: 8, 10, 16, 32, 13; a touch device's the phone's search field: 16,
  /// 12, 17, 38, 15)
  band_in : Double
  band_pad : Double
  band_icon : Double
  band_h : Double
  band_words : @ui.TextStyle
  /// a sidebar's other lists (the files' places, the settings'): their box, a row (one of a list's items, its words
  /// from the top), a row's words (the title's), where something goes while there is none, a folder that takes a drop
  side_list : @ui.Style
  side_row : @ui.Style
  side_row_tall : @ui.Style
  side_hint : @ui.Style
  side_drop : @ui.Style
  /// a day's heading, a sidebar list's (navHeading; the phone's section header)
  heading : @ui.Style
  /// beside a rail: in as its rows are there (a touch device's 14 to their 16)
  heading_beside_rail : @ui.Style
  heading_words : @ui.TextStyle
  /// read the first time: how many rows breathe while it reads, and while what it waits on says so; dense (a
  /// computer's)
  waiting_rows : Int
  waiting_noted : Int
  waiting_dense : Bool
  /// whether the screen has keys to find and choose with: ⌘K, ↑ ↓ and Enter in what is found, the one chosen shown so (a
  /// computer's); else the search is at the list's top, scrolled to (a touch device's: Home.kt top)
  keys : Bool
  /// what search finds, a line each (Found)
  found : Found
  /// how its panes slide one to another (navTrack: 240 ease-out; mHomePane: 240 standard) and how a row moves as the
  /// list changes (motion.ts MOVE; the phone's row spring)
  slide : @motion.Spec
  move : @motion.Spec
}

///|
/// A computer's (Sidebar.css.ts navRow, navSession: 54 high, 7 by 10 in, its words from the top, its corner a sidebar
/// row's; two lines 2 apart, its title 13 on 20, 500 while something in it is unread; its second line 12 on 18; faces
/// 16, marks 12; navHeading 12 on 18, muted, 14 above and 4 under).
// kept across runs: a value (no field of it changes)
pub let mouse_chat_list : ChatList = {
  row_h: 54.0,
  row: @ui.style(row=true, w=Full, h=side_row_h, px=S2_5, py=row_in, gap=S2, align=AStart, radius=side_row_radius),
  text: @ui.css("w=Full gap=S0_5"),
  text_settled: @ui.css("w=Full gap=S0_5 opacity=O45"),
  head: @ui.css("row w=Full h=S5 gap=S1_5 align=ACenter"),
  // (pointed at, room at its end for 归档: 24)
  head_room: @ui.css("row w=Full h=S5 pr=S6 gap=S1_5 align=ACenter"),
  meta: @ui.css("row w=Full h=S4_5 gap=S1_5 align=ACenter"),
  title: @ui.text_style(size=Ui, color=Fg, leading=L6, wrap=false, w=Full),
  title_unread: @ui.text_style(size=Ui, weight=Medium, color=Fg, leading=L6, wrap=false, w=Full),
  last: @ui.text_style(size=Meta, color=Muted, leading=L5, wrap=false, w=Full),
  beside_rail: @ui.css(""),
  more: @ui.css("w=Full pb=S0_5"),
  // (as far from the row's foot as from its end: its last face concentric with the row's foot corner when its ground
  // shows, where its line's middle would have it 8: 7 in, the face 16 in the line's 18)
  aside_lift: capsule_in(row_corner, mouse_face_d) - (mouse_row_in + (mouse_meta_h - mouse_face_d) / 2.0),
  state_quiet: @ui.text_style(size=Meta, color=Muted, leading=L5, wrap=false, w=Full),
  state_turn: @ui.text_style(size=Meta, color=Fg, leading=L5, wrap=false, w=Full),
  state_alert: @ui.text_style(size=Meta, color=Danger, leading=L5, wrap=false, w=Full),
  state_lead: @ui.text_style(weight=Semibold, w=Hug),
  agent_mark: 12.0,
  face_d: mouse_face_d,
  face: @ui.css("w=S4 h=S4"),
  face_after: @ui.style(w=side_face_step, h=S4),
  face_ground: @ui.css("w=S4_5 h=S4_5 radius=Full"),
  face_ring: @ui.css("w=S5 h=S5 radius=Full border=B1 border_color=Fg"),
  top_in: 4.0,
  foot_in: 12.0,
  band_in: 8.0,
  band_pad: 10.0,
  band_icon: 16.0,
  band_h: 32.0,
  band_words: @ui.text_style(size=Sm, color=Fg, leading=L6, wrap=false, w=Full),
  side_list: @ui.css("w=Full h=Full px=S2"),
  side_row: @ui.css("row w=Full min_h=S8 px=S2_5 py=S1_5 gap=S2").then(@ui.style(radius=side_row_radius)),
  side_row_tall: @ui.css("row w=Full min_h=S8 px=S2_5 gap=S2 align=AStart").then(
    @ui.style(py=row_in, radius=side_row_radius),
  ),
  side_hint: @ui.css("row w=Full px=S2_5 py=S1_5 gap=S2 align=ACenter"),
  side_drop: @ui.css("w=Full radius=Xl"),
  heading: @ui.css("w=Full px=S2 pt=S3_5 pb=S1"),
  heading_beside_rail: @ui.css("w=Full px=S2 pt=S3_5 pb=S1"),
  heading_words: @ui.text_style(size=Meta, color=Muted, leading=L5, wrap=false),
  waiting_rows: 6,
  waiting_noted: 6,
  waiting_dense: true,
  keys: true,
  found: mouse_found,
  slide: @motion.tween(list_slide_ms, ease=Out),
  move: @motion.move_spring,
}

///|
/// A touch device's (mobile/Home.css.ts mChatRow: 66 high, 22 in on the left and 16 on the right, two lines in its
/// middle; its title 16 on 22, 600 while something in it is unread; its second line 14 on 20; faces 18, marks 14; the
/// phone's section header 15 bold in ink, 20 in, 14 above and 6 under).
// kept across runs: a value (no field of it changes)
pub let touch_chat_list : ChatList = {
  row_h: touch_list_row_h,
  row: @ui.style(row=true, w=Full, h=Fixed(touch_list_row_h), pl=phone_row_in, pr=S4, gap=S1_5, align=ACenter),
  text: @ui.css("w=Full justify=JCenter"),
  text_settled: @ui.css("w=Full justify=JCenter opacity=O45"),
  head: @ui.style(row=true, w=Full, h=Fixed(touch_title_h), gap=S2, align=ACenter),
  head_room: @ui.style(row=true, w=Full, h=Fixed(touch_title_h), gap=S2, align=ACenter),
  meta: @ui.css("row w=Full h=S5 gap=S2 align=ACenter"),
  title: @ui.text_style(size=Ui, color=Fg, leading=L7, wrap=false, w=Full),
  title_unread: @ui.text_style(size=Ui, weight=Semibold, color=Fg, leading=L7, wrap=false, w=Full),
  last: @ui.text_style(size=Meta, color=Muted, leading=L6, wrap=false, w=Full),
  beside_rail: @ui.css("pl=S4"),
  more: full_width,
  aside_lift: 0.0,
  state_quiet: @ui.text_style(size=Meta, color=Muted, leading=L6, wrap=false, w=Full),
  state_turn: @ui.text_style(size=Meta, color=Fg, leading=L6, wrap=false, w=Full),
  state_alert: @ui.text_style(size=Meta, color=Danger, leading=L6, wrap=false, w=Full),
  // (bold, as the phone's: Home.kt StateLine)
  state_lead: @ui.text_style(weight=Bold, w=Hug),
  agent_mark: 14.0,
  face_d: 18.0,
  face: @ui.css("w=S4_5 h=S4_5"),
  face_after: @ui.style(w=touch_face_step, h=S4_5),
  face_ground: @ui.css("w=S5 h=S5 radius=Full"),
  face_ring: @ui.style(w=touch_face_ring, h=touch_face_ring, radius=Full, border=B1, border_color=Fg),
  top_in: 0.0,
  foot_in: 0.0,
  band_in: 16.0,
  band_pad: 12.0,
  band_icon: 17.0,
  band_h: 38.0,
  band_words: @ui.text_style(size=Lg, color=Fg, wrap=false, w=Full),
  // (as wide as their box, their rows in by their own, square: SidebarList.css.ts phone)
  side_list: @ui.css("w=Full h=Full"),
  side_row: @ui.css("row w=Full pr=S4 py=S2_5 gap=S2 align=ACenter").then(@ui.style(pl=phone_row_in)),
  side_row_tall: @ui.css("row w=Full pr=S4 py=S2_5 gap=S2 align=ACenter").then(@ui.style(pl=phone_row_in)),
  side_hint: @ui.css("row w=Full pr=S4 py=S2_5 gap=S2 align=ACenter").then(@ui.style(pl=phone_row_in)),
  side_drop: @ui.css("w=Full"),
  heading: @ui.css("w=Full px=S5 pt=S3_5 pb=S1_5"),
  heading_beside_rail: @ui.css("w=Full pl=S3_5 pr=S5 pt=S3_5 pb=S1_5"),
  heading_words: @ui.text_style(size=Body, weight=Semibold, color=Fg, wrap=false),
  waiting_rows: 7,
  waiting_noted: 4,
  waiting_dense: false,
  keys: false,
  found: touch_found,
  slide: @motion.tween(list_slide_ms, ease=Standard),
  move: @motion.row_spring,
}

///|
/// A touch device's chat row's height and its title's line (mobile/Home.css.ts mChatRow, mChatLine1).
pub let touch_list_row_h : Double = 66.0

///|
let touch_title_h : Double = 22.0

///|
/// How long the lists' track slides (navTrack, mHomePane: 240).
pub let list_slide_ms : Double = 240.0

///|
/// A computer's face at a row's end, its row's padding over its foot (row_in) and its second line's height (meta: S4_5).
let mouse_face_d : Double = 16.0

///|
let mouse_row_in : Double = 7.0

///|
let mouse_meta_h : Double = 18.0

///|
/// What search finds on this screen (sfpages' switcher.mbt: ⌘K's list, the phone's search page), one design: a line
/// each, its mark (an icon, an agent's maker, a station's mark), its first line (what it is, or the words found in it)
/// with who, where and when at its end, and where it is under it (its chat, its line with the words) where it says one;
/// the kinds under their headings; 全部结果 and 查看更多 in the link's ink; quiet words, the stations still answering.
/// Its sizes the screen's: a computer's the web's ⌘K (Switcher.css.ts: rows 38, two lines 54, 13 and 12), a touch
/// device's the phone's search (mobile/Home.css.ts mFound…: rows 50, two lines 66, 15 and 14).
pub(all) struct Found {
  /// a line's height as the list first takes it: one line, two, a heading, quiet words
  row_h : Double
  two_h : Double
  head_h : Double
  quiet_h : Double
  /// a line (chosen by the keys: on the words' tint), one of two lines
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
  /// a kind's heading
  head : @ui.Style
  head_words : @ui.TextStyle
  /// quiet words (none found), the stations still answering (one that failed closer), what the core says
  quiet : @ui.Style
  quiet_words : @ui.TextStyle
  wait : @ui.Style
  wait_failing : @ui.Style
  said_words : @ui.TextStyle
}

///|
/// A computer's (Switcher.css.ts: a row 38 high at least, 8 over and under and 12 in, its parts 10 apart, rounded as
/// its panel's corner leaves for it; chosen, on the words' 7%; its mark 20, icons 16, makers 18; 13 and 12; a heading
/// 12 muted, 12 in, 10 over and 4 under).
// kept across runs: a value (no field of it changes)
pub let mouse_found : Found = {
  row_h: mouse_found_row_h,
  two_h: 54.0,
  head_h: 32.0,
  quiet_h: 54.0,
  row: @ui.style(
    row=true,
    w=Full,
    min_h=Fixed(mouse_found_row_h),
    px=S3,
    py=S2,
    gap=S2_5,
    align=ACenter,
    radius=InnerOr(row_radius),
    selected=@ui.patch(bg=Tint),
  ),
  two: @ui.style(
    row=true,
    w=Full,
    min_h=Fixed(mouse_found_row_h),
    px=S3,
    py=S2,
    gap=S2_5,
    align=AStart,
    radius=InnerOr(row_radius),
    selected=@ui.patch(bg=Tint),
  ),
  mark: @ui.css("w=S5 h=S5 align=ACenter justify=JCenter"),
  icon: 16.0,
  logo: 18.0,
  column: @ui.style(w=grow, gap=S0_5),
  first: @ui.css("row w=Full gap=S2_5 align=ACenter"),
  second: @ui.css("row w=Full gap=S2_5 align=ACenter"),
  title: @ui.text_style(size=Sm, color=Fg, wrap=false, w=grow),
  words: @ui.text_style(size=Sm, color=Fg, max_lines=1, w=Full),
  under: @ui.text_style(size=Sm, color=Muted, wrap=false, w=grow),
  under_words: @ui.text_style(size=Sm, color=Muted, max_lines=1, w=grow),
  meta: @ui.text_style(size=Xs, color=Muted, wrap=false),
  link: @ui.text_style(size=Sm, color=Link, wrap=false, w=grow),
  head: @ui.css("w=Full px=S3 pt=S2_5 pb=S1"),
  head_words: @ui.text_style(size=Xs, color=Muted, wrap=false),
  quiet: @ui.css("w=Full px=S3 py=S3_5"),
  quiet_words: @ui.text_style(size=Sm, color=Muted),
  wait: @ui.css("w=Full px=S3 pt=S2 pb=S2_5"),
  wait_failing: @ui.css("w=Full px=S3 pt=S2 pb=S2_5"),
  said_words: @ui.text_style(size=Xs, color=Muted, w=Full),
}

///|
/// A touch device's (mobile/Home.css.ts mFound…, Search.kt: a row 50 high, 66 with a line under, 22 in on the left
/// and 16 on the right, its parts 12 apart; its mark 20, icons and makers 18; 15 on 22 and 14 on 20; the phone's
/// section header for a kind's heading; quiet words 22 in, 16 over and under).
// kept across runs: a value (no field of it changes)
pub let touch_found : Found = {
  row_h: touch_found_row_h,
  two_h: touch_found_two_h,
  head_h: 41.0,
  quiet_h: 44.0,
  row: @ui.style(row=true, w=Full, min_h=Fixed(touch_found_row_h), pl=found_start, pr=S4, gap=S3, align=ACenter),
  two: @ui.style(row=true, w=Full, min_h=Fixed(touch_found_two_h), pl=found_start, pr=S4, gap=S3, align=ACenter),
  mark: @ui.css("w=S5 h=S5 align=ACenter justify=JCenter"),
  icon: 18.0,
  logo: 18.0,
  column: @ui.style(w=grow, justify=JCenter),
  first: @ui.style(row=true, w=Full, h=found_line_h, gap=S2, align=ACenter),
  second: @ui.css("row w=Full h=S5 gap=S2 align=ACenter"),
  title: @ui.text_style(size=Lg, leading=L7, color=Fg, wrap=false, w=grow),
  words: @ui.text_style(size=Lg, leading=L7, color=Fg, max_lines=1, w=Full),
  under: @ui.text_style(size=Base, leading=L6, color=Muted, wrap=false, w=grow),
  under_words: @ui.text_style(size=Base, leading=L6, color=Muted, max_lines=1, w=grow),
  meta: @ui.text_style(size=Xs, color=Muted, wrap=false),
  link: @ui.text_style(size=Base, color=Link, wrap=false, w=grow),
  head: @ui.css("w=Full px=S5 pt=S3_5 pb=S1_5"),
  head_words: @ui.text_style(size=Lg, weight=Semibold, color=Fg, wrap=false),
  quiet: @ui.style(w=Full, px=found_start, py=S4),
  quiet_words: @ui.text_style(size=Base, color=Muted, w=Full),
  wait: @ui.style(w=Full, px=found_start, py=S3),
  wait_failing: @ui.style(w=Full, px=found_start, py=S1_5),
  said_words: @ui.text_style(size=Sm, leading=L5, color=Muted, w=Full),
}

///|
/// A line of what is found, as high as it is at least: a computer's 38, a touch device's 50 (66 with a line under).
let mouse_found_row_h : Double = 38.0

///|
let touch_found_row_h : Double = 50.0

///|
let touch_found_two_h : Double = 66.0
