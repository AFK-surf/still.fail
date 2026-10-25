// The chats' lists' sizes on the screen in force (docs/architecture.md: sizes, row heights and density are the
// theme's, by the screen's kind): a computer's the web's sidebar (Sidebar.css.ts navSession…, RowPicture.css.ts,
// ChatMark.css.ts), a touch device's the phone's home (mobile/Home.css.ts mChatRow…, Home.kt). The rows, their second
// line, what stands at its end, the days' headings, the list's waiting and how its rows and panes move. One set of
// pages draws them (sfpages' sidebar.mbt, chat_row.mbt, chat_mark.mbt, row_picture.mbt), taking them from here.

///|
/// A chats' list on this screen (Theme::lists).
pub(all) struct Lists {
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
  /// a day's heading (navHeading; the phone's section header)
  heading : @ui.Style
  heading_words : @ui.TextStyle
  /// read the first time: how many rows breathe while it reads, and while what it waits on says so; dense (a
  /// computer's)
  waiting_rows : Int
  waiting_noted : Int
  waiting_dense : Bool
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
pub let mouse_lists : Lists = {
  row_h: 54.0,
  row: @ui.style(row=true, w=Full, h=side_row_h, px=S2_5, py=row_in, gap=S2, align=AStart, radius=side_row_radius),
  text: @ui.css("w=Full gap=S0_5"),
  text_settled: @ui.css("w=Full gap=S0_5 opacity=O45"),
  head: @ui.css("row w=Full h=S5 gap=S1_5 align=ACenter"),
  // (pointed at, room at its end for 归档: 24)
  head_room: @ui.css("row w=Full h=S5 pr=S6 gap=S1_5 align=ACenter"),
  meta: @ui.css("row w=Full h=S4_5 gap=S1_5 align=ACenter"),
  title: @ui.text_style(size=Sm, color=Fg, leading=L6, wrap=false, w=Full),
  title_unread: @ui.text_style(size=Sm, weight=Medium, color=Fg, leading=L6, wrap=false, w=Full),
  last: @ui.text_style(size=Xs, color=Muted, leading=L5, wrap=false, w=Full),
  more: @ui.css("w=Full pb=S0_5"),
  // (as far from the row's foot as from its end: its last face concentric with the row's foot corner when its ground
  // shows, where its line's middle would have it 8: 7 in, the face 16 in the line's 18)
  aside_lift: capsule_in(row_corner, mouse_face_d) - (mouse_row_in + (mouse_meta_h - mouse_face_d) / 2.0),
  state_quiet: @ui.text_style(size=Xs, color=Muted, leading=L5, wrap=false, w=Full),
  state_turn: @ui.text_style(size=Xs, color=Fg, leading=L5, wrap=false, w=Full),
  state_alert: @ui.text_style(size=Xs, color=Danger, leading=L5, wrap=false, w=Full),
  state_lead: @ui.text_style(weight=Semibold),
  agent_mark: 12.0,
  face_d: mouse_face_d,
  face: @ui.css("w=S4 h=S4"),
  face_after: @ui.style(w=side_face_step, h=S4),
  face_ground: @ui.css("w=S4_5 h=S4_5 radius=Full"),
  face_ring: @ui.css("w=S5 h=S5 radius=Full border=B1 border_color=Fg"),
  top_in: 4.0,
  foot_in: 12.0,
  heading: @ui.css("w=Full px=S2 pt=S3_5 pb=S1"),
  heading_words: @ui.text_style(size=Xs, color=Muted, leading=L5, wrap=false),
  waiting_rows: 6,
  waiting_noted: 6,
  waiting_dense: true,
  slide: @motion.tween(list_slide_ms, ease=Out),
  move: @motion.move_spring,
}

///|
/// A touch device's (mobile/Home.css.ts mChatRow: 66 high, 22 in on the left and 16 on the right, two lines in its
/// middle; its title 16 on 22, 600 while something in it is unread; its second line 14 on 20; faces 18, marks 14; the
/// phone's section header 15 bold in ink, 20 in, 14 above and 6 under).
// kept across runs: a value (no field of it changes)
pub let touch_lists : Lists = {
  row_h: touch_list_row_h,
  row: @ui.style(row=true, w=Full, h=Fixed(touch_list_row_h), pl=phone_row_in, pr=S4, gap=S1_5, align=ACenter),
  text: @ui.css("w=Full justify=JCenter"),
  text_settled: @ui.css("w=Full justify=JCenter opacity=O45"),
  head: @ui.style(row=true, w=Full, h=Fixed(touch_title_h), gap=S2, align=ACenter),
  head_room: @ui.style(row=true, w=Full, h=Fixed(touch_title_h), gap=S2, align=ACenter),
  meta: @ui.css("row w=Full h=S5 gap=S2 align=ACenter"),
  title: @ui.text_style(size=Xl, color=Fg, leading=L7, wrap=false, w=Full),
  title_unread: @ui.text_style(size=Xl, weight=Semibold, color=Fg, leading=L7, wrap=false, w=Full),
  last: @ui.text_style(size=Base, color=Muted, leading=L6, wrap=false, w=Full),
  more: full_width,
  aside_lift: 0.0,
  state_quiet: @ui.text_style(size=Base, color=Muted, leading=L6, wrap=false, w=Full),
  state_turn: @ui.text_style(size=Base, color=Fg, leading=L6, wrap=false, w=Full),
  state_alert: @ui.text_style(size=Base, color=Danger, leading=L6, wrap=false, w=Full),
  // (bold, as the phone's: Home.kt StateLine)
  state_lead: @ui.text_style(weight=Bold),
  agent_mark: 14.0,
  face_d: 18.0,
  face: @ui.css("w=S4_5 h=S4_5"),
  face_after: @ui.style(w=touch_face_step, h=S4_5),
  face_ground: @ui.css("w=S5 h=S5 radius=Full"),
  face_ring: @ui.style(w=touch_face_ring, h=touch_face_ring, radius=Full, border=B1, border_color=Fg),
  top_in: 0.0,
  foot_in: 0.0,
  heading: @ui.css("w=Full px=S5 pt=S3_5 pb=S1_5"),
  heading_words: @ui.text_style(size=Lg, weight=Semibold, color=Fg, wrap=false),
  waiting_rows: 7,
  waiting_noted: 4,
  waiting_dense: false,
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
