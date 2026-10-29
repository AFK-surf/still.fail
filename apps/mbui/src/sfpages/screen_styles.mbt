// How the remote screen's viewer looks (ember apps/android app/remote/ScreenViewer.kt), its sizes as Android says
// them: on the scale's steps where they are one, else named in src/sf/tokens.mbt.

// ── the page ──────────────────────────────────────────────────────────────

///|
/// The page: the theme's ground; 全屏, black as a video is.
// kept across runs: a value (no field of it changes)
let screen_page_box : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
// kept across runs: a value (no field of it changes)
let screen_page_full : @ui.Style = @ui.css("w=Full h=Full bg=Theater")

///|
// kept across runs: a value (no field of it changes)
let screen_fill : @ui.Style = @ui.css("w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let screen_fill_w : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let screen_row : @ui.Style = @ui.css("row w=Full h=Full")

///|
/// Over the frame's top, in its middle, 12 down (接管 sideways and 全屏).
// kept across runs: a value (no field of it changes)
let screen_top_center : @ui.Style = @ui.css("w=Full pt=S3 align=ACenter")

///|
/// Over the frame's foot, in its middle, 8 up (the keys row while the keyboard is up).
// kept across runs: a value (no field of it changes)
let screen_foot_center : @ui.Style = @ui.css("w=Full h=Full p=S2 align=ACenter justify=JEnd")

///|
/// 左键 and 右键 side by side, 8 apart, nothing drawn round them: moved together.
// kept across runs: a value (no field of it changes)
let mouse_pair_box : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
/// One of them, floating on its own: round, 44 (a press's least), on the floating ground (the ink at 8% pressed).
// kept across runs: a value (no field of it changes)
let mouse_button_box : @ui.Style = @ui.css(
  #|w=S11 h=S11 radius=Full bg=Floating shadow=Sm align=ACenter justify=JCenter pressed{bg=Hover}
)

///|
/// Over the frame's foot, at its end, 12 in (the mouse's buttons, 全屏 and sideways).
// kept across runs: a value (no field of it changes)
let screen_foot_end : @ui.Style = @ui.css("w=Full h=Full p=S3 align=AEnd justify=JEnd")

///|
/// Over the frame's top right corner, 12 in (全屏's folded tools).
// kept across runs: a value (no field of it changes)
let screen_top_end : @ui.Style = @ui.css("w=Full p=S3 align=AEnd")

///|
/// One of those two (`style`) where it stands in the window's corner: its 12 clear of a corner too square for its
/// round buttons (@sf.window_corner_clear, a Mac's 16), and past what the system has at the sides turned sideways.
fn screen_corner_end(style : @ui.Style) -> @ui.Style {
  let in_ = @sf.window_corner_clear(@ui.Space::S3.px())
  style.then(@ui.style(p=@sf.room_of(in_))).then(@sf.sides_clear(in_))
}

///|
/// 接管 upright, under the bar: 12 from the sides, 4 over and under.
// kept across runs: a value (no field of it changes)
let take_over_place : @ui.Style = @ui.css("w=Full px=S3 py=S1 align=ACenter")

// ── buttons ───────────────────────────────────────────────────────────────

///|
/// A round button (40), the ink at 10% under it while it is on.
// kept across runs: a value (no field of it changes)
let round_button_box : @ui.Style = @ui.css(
  #|w=S10 h=S10 radius=Full align=ACenter justify=JCenter selected{bg=A(Fg,O10)}
)

///|
let round_icon : Double = 20.0

///|
/// Upright: the bar, 56 high, 6 in at its start and 10 at its end, 8 between.
// kept across runs: a value (no field of it changes)
let screen_bar : @ui.Style = @ui.css("row w=Full h=S14 pl=S1_5 pr=S2_5 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let screen_bar_words : @ui.Style = @ui.css("w=Full")

///|
/// The title (15 on 20, semibold), the line under it (12 on 16, muted); one line each, cut short where the bar's
/// buttons leave them less (a window's name, the core's line of who is on it: a bar has no second line to give them).
// kept across runs: a value (no field of it changes)
let screen_title_words : @ui.TextStyle = @ui.text_style(
  size=Ui,
  leading=L6,
  weight=Semibold,
  color=Fg,
  wrap=false,
  w=Cut,
)

///|
// kept across runs: a value (no field of it changes)
let screen_line_words : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, color=Muted, wrap=false, w=Cut)

///|
/// 全屏's tools: a capsule floating still, a round button 4 in from its edge, 4 between.
// kept across runs: a value (no field of it changes)
let full_tools_box : @ui.Style = @ui.css("p=S1 gap=S1 align=ACenter radius=Xl4 bg=Floating shadow=Sm")

// ── the rail ──────────────────────────────────────────────────────────────

///|
/// Sideways: 60 wide, 8 over and under, the buttons 4 apart in its middle.
// kept across runs: a value (no field of it changes)
let rail_box : @ui.Style = @ui.style(w=@sf.rail_w, h=Full, py=S2, gap=S1, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let rail_people : @ui.Style = @ui.css("")

///|
/// The count of the others on it: over the button's top right, 4 out and 2 up.
// kept across runs: a value (no field of it changes)
let rail_badge_place : @ui.Style = @ui.css("w=Full align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let rail_badge : @ui.Style = @ui.css("min_w=S3_5 h=S3_5 radius=Full bg=Fg align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let rail_badge_words : @ui.TextStyle = @ui.text_style(
  size=Caption,
  weight=Semibold,
  color=Bg,
  center=true,
  wrap=false,
)

///|
/// The line said, beside the rail (64 from its start) over its foot (8 up), 280 at most.
// kept across runs: a value (no field of it changes)
let rail_say_place : @ui.Style = @ui.css("w=Full h=Full pl=S16 pb=S2 justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let rail_say_box : @ui.Style = @ui.style(
  max_w=@sf.rail_say_max,
  px=S3_5,
  py=S2,
  radius=Xl2,
  bg=Floating,
  shadow=Sm,
)

///|
// kept across runs: a value (no field of it changes)
let rail_say_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Fg, max_lines=2)

// ── the foot and the keys row ─────────────────────────────────────────────

///|
/// Upright, under the frame: 56 high, 8 from the sides, 6 between.
// kept across runs: a value (no field of it changes)
let screen_foot : @ui.Style = @ui.css("row w=Full h=S14 px=S2 gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let keys_row_box : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
/// A key: 36 high, 40 wide at least, round, 10 in, its words or mark in a row (never squeezed: a key short of room
/// leaves whole); the ink at 6%, or the ink while it is held.
// kept across runs: a value (no field of it changes)
let row_key_box : @ui.Style = @ui.css(
  #|row h=S9 min_w=S10 px=S2_5 radius=Full bg=Tint align=ACenter justify=JCenter selected{bg=Fg}
)

///|
let key_icon : Double = 18.0

///|
// kept across runs: a value (no field of it changes)
let row_key_words : @ui.TextStyle = @ui.text_style(
  size=Ui,
  leading=L4_75,
  weight=Semibold,
  color=Fg,
  wrap=false,
)

///|
// kept across runs: a value (no field of it changes)
let row_key_on_words : @ui.TextStyle = row_key_words.then(@ui.text_style(color=Bg))

///|
/// The keys row floating over the frame: a capsule 4 round it.
// kept across runs: a value (no field of it changes)
let keys_capsule_box : @ui.Style = @ui.css("p=S1 radius=Full bg=Floating shadow=Sm")

// ── 接管 ─────────────────────────────────────────────────────────────────

///|
/// Who drives it and 接管: a capsule floating still, 480 at most, one line high (44: 接管 6 in), its dot and 接管 in its
/// ends concentric with them (@sf.capsule_in), 10 between.
// kept across runs: a value (no field of it changes)
let take_over_box : @ui.Style = @ui.style(
  row=true,
  max_w=@sf.take_over_max,
  pl=@sf.capsule_end_room(take_over_h, take_over_dot_side),
  pr=S1_5,
  py=S1_5,
  gap=S2_5,
  align=ACenter,
  radius=Full,
  bg=Floating,
  shadow=Sm,
)

///|
// kept across runs: a value (no field of it changes)
let take_over_dot : @ui.Style = @ui.css("w=S2 h=S2 radius=Full bg=Warn")

///|
/// The capsule's height: 接管's 32 and 6 over and under it; its dot's (8: S2).
let take_over_h : Double = 44.0

///|
let take_over_dot_side : Double = 8.0

///|
// kept across runs: a value (no field of it changes)
let take_over_words_box : @ui.Style = @ui.css("w=Cut")

///|
// kept across runs: a value (no field of it changes)
let take_over_words : @ui.TextStyle = @ui.text_style(
  size=Ui,
  leading=L4_75,
  weight=Semibold,
  color=Fg,
  wrap=false,
  w=Cut,
)

///|
/// 接管: the main solid button (the ink, the page's colour on it), 32 high, 14 in, its corner 16.
// kept across runs: a value (no field of it changes)
let take_over_button : @ui.Style = @ui.css("h=S8 px=S3_5 radius=Full bg=Fg align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let take_over_button_words : @ui.TextStyle = @ui.text_style(
  size=Ui,
  leading=L4_75,
  weight=Semibold,
  color=Bg,
  wrap=false,
)

// ── the stage ─────────────────────────────────────────────────────────────

///|
// kept across runs: a value (no field of it changes)
let stage_box : @ui.Style = @ui.css("w=Full h=Full clip")

///|
/// The frame as it was, faded while the view is on its way back (40%).
// kept across runs: a value (no field of it changes)
let frame_faded : @ui.Style = @ui.css("opacity=O40")

///|
// kept across runs: a value (no field of it changes)
let frame_clear : @ui.Style = @ui.css("")

///|
/// Over: the screen's place gone dark, what happened in its middle.
// kept across runs: a value (no field of it changes)
let over_box : @ui.Style = @ui.css("clip align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let stage_center : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
/// Over the frame's foot: 16 in, 420 at most, 8 between.
// kept across runs: a value (no field of it changes)
let stage_foot : @ui.Style = @ui.css("w=Full h=Full p=S4 align=ACenter justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let stage_foot_column : @ui.Style = @ui.style(w=Full, max_w=@sf.phone_max, gap=S2, align=ACenter)

///|
/// Why 控制 does not drive it: floating still, 14 and 8 in, an icon (16) 8 before the words (13 on 18, three lines).
// kept across runs: a value (no field of it changes)
let undriven_box : @ui.Style = @ui.css("row px=S3_5 py=S2 gap=S2 align=ACenter radius=Xl2 bg=Floating shadow=Sm")

///|
let undriven_icon : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let undriven_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, max_lines=3)

///|
/// On its way (Waiting.kt WaitPill floating over the frame): 24 round it, the capsule floating still with no ground of
/// its own, 12 and 6 in, the spinner (12) 8 before the words (13 on 18, the ink, two lines).
// kept across runs: a value (no field of it changes)
let wait_pill_box : @ui.Style = @ui.css("row px=S3 py=S1_5 gap=S2 align=ACenter radius=Full bg=Floating shadow=Sm")

///|
/// Not shown yet (a wait is said once it has been a moment), its room kept.
// kept across runs: a value (no field of it changes)
let unseen : @ui.Style = @ui.css("opacity=O0")

///|
let wait_spinner : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let wait_pill_words : @ui.TextStyle = @ui.text_style(
  size=Meta,
  leading=L5,
  color=Fg,
  center=true,
  max_lines=2,
)

///|
/// What happened (16 on 22, semibold, white) and why (13 on 18, white at 70%, 4 under), 24 in, 320 at most.
// kept across runs: a value (no field of it changes)
let ended_box : @ui.Style = @ui.style(p=S6, max_w=@sf.ended_max, gap=S1, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let ended_title : @ui.TextStyle = @ui.text_style(
  size=Title,
  leading=L7,
  weight=Semibold,
  color=OnVeil,
  center=true,
)

///|
// kept across runs: a value (no field of it changes)
let ended_why : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=A(OnVeil, O70), center=true)

///|
/// 重新打开 (Controls.kt Button at 34 high, 16 in, 12 more under the words): the ink with the page's colour on it in
/// the dark theme, a solid light grey with the ink on it in the light one (on the screen's dark veil, not the page: the
/// neutral ground, the ink at an opacity, came out as dark as the veil, 1.2 to 1 under its words).
// kept across runs: a value (no field of it changes)
let again_solid : @ui.Style = @ui.style(
  h=@sf.row_key,
  px=S4,
  radius=Full,
  bg=Fg,
  align=ACenter,
  justify=JCenter,
)

///|
// kept across runs: a value (no field of it changes)
let again_soft : @ui.Style = again_solid.then(@ui.css("bg=Faint"))

///|
// kept across runs: a value (no field of it changes)
let again_solid_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Bg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let again_soft_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, wrap=false)

// ── the files sent ────────────────────────────────────────────────────────

///|
/// The files' panel: floating still, as wide as the foot, a card's corner of the ladder's (its rows' keys concentric
/// with it: drop_key_in).
// kept across runs: a value (no field of it changes)
let drops_box : @ui.Style = @ui.style(w=Full, radius=@sf.card_radius, bg=Floating, shadow=Sm, clip=true)

///|
/// A file's row: 18 in at its start, 12 between; its key at its top end as far in as makes it concentric with the
/// panel's corner (drop_key_in), the first's in its top one; as tall as keeps the last's out of its foot one
/// (drop_row_least).
// kept across runs: a value (no field of it changes)
let drop_row_box : @ui.Style = @ui.style(
  row=true,
  w=Full,
  min_h=Fixed(drop_row_least),
  pl=S4_5,
  pr=@sf.room_of(drop_key_in),
  py=@sf.room_of(drop_key_in),
  gap=S3,
)

///|
/// How far in a row's round key stands from the panel's top and end (the ladder's card corner less its half).
let drop_key_in : Double = @sf.capsule_in(@sf.card_corner, drop_key_side)

///|
/// A row's least height: its key at its top, and under it as far as the panel's foot corner is round.
let drop_row_least : Double = drop_key_in + drop_key_side + @sf.card_corner

///|
/// A row's key's side (@sf.row_key).
let drop_key_side : Double = 34.0

///|
/// Its mark by its first line, as high as its keys, across their middle.
// kept across runs: a value (no field of it changes)
let drop_icon_box : @ui.Style = @ui.style(h=@sf.row_key, justify=JCenter)

///|
let drop_icon : Double = 20.0

///|
/// Its name, taking what its first line leaves its keys.
// kept across runs: a value (no field of it changes)
let drop_words : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let drop_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let drop_path_words : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, color=Muted, max_lines=2)

///|
// kept across runs: a value (no field of it changes)
let drop_failed_words : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, color=Danger, max_lines=3)

///|
// kept across runs: a value (no field of it changes)
let drop_going_words : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let drop_buttons : @ui.Style = @ui.css("row pt=S2 gap=S2")

///|
/// How far it has got: a track of the ink at 8%, 3 high, 5 under the words, filled in the accent.
// kept across runs: a value (no field of it changes)
let drop_track_place : @ui.Style = @ui.css("w=Full pt=S1_25")

///|
// kept across runs: a value (no field of it changes)
let drop_track : @ui.Style = @ui.style(
  row=true,
  w=Full,
  h=@sf.track_h,
  radius=Full,
  bg=TintStrong,
  clip=true,
)

///|
// kept across runs: a value (no field of it changes)
let drop_track_fill : @ui.Style = @ui.css("h=Full radius=Full bg=Accent")

///|
/// A small round key at a row's end (34).
// kept across runs: a value (no field of it changes)
let row_key_round : @ui.Style = @ui.style(
  w=@sf.row_key,
  h=@sf.row_key,
  radius=Full,
  align=ACenter,
  justify=JCenter,
)

///|
let drop_key_icon : Double = 16.0

///|
/// A button that is not the main one (Controls.kt Button: 38 high, 16 in, the chip under the ink's words, 14 semibold).
// kept across runs: a value (no field of it changes)
let soft_button_box : @ui.Style = @ui.style(
  h=@sf.button_38,
  px=S4,
  radius=Full,
  bg=Neutral,
  align=ACenter,
  justify=JCenter,
)

///|
// kept across runs: a value (no field of it changes)
let soft_button_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, wrap=false)

// ── how the view goes (screen_panel.mbt) ─────────────────────────────────

///|
/// Under the title, live: the signal mark, how long it has been seen, the core's line, 6 apart.
// kept across runs: a value (no field of it changes)
let screen_line_row : @ui.Style = @ui.css("row w=Full h=S4 gap=S1_5 align=ACenter")

///|
/// How long it has been seen (12 on 16, muted, its figures as wide as each other).
// kept across runs: a value (no field of it changes)
let screen_time_words : @ui.TextStyle = @ui.text_style(
  size=Caption,
  leading=L4,
  color=Muted,
  wrap=false,
  tabular=true,
)

///|
/// With keyboard and mouse, how the view goes in the viewer's bar (the web's netChip): 32 high, round, the page's hover
/// under the pointer; the mark on its tile 4 in, the time 10 from the end, 8 between.
// kept across runs: a value (no field of it changes)
let net_chip_box : @ui.Style = @ui.css("row h=S8 pl=S1 pr=S2_5 gap=S2 align=ACenter radius=Full hovered{bg=Hover}")

///|
/// The signal mark's tile: 24, round, the ink at 6% under it.
// kept across runs: a value (no field of it changes)
let net_mark_tile : @ui.Style = @ui.css("w=S6 h=S6 radius=Full bg=Tint align=ACenter justify=JCenter")

///|
/// Who drives it and 接管 among the viewer's bar's tools: its dot, the words (cut short first) and 接管, 10 apart.
// kept across runs: a value (no field of it changes)
let take_over_bar_row : @ui.Style = @ui.css("row gap=S2_5 align=ACenter")

///|
/// The signal mark's bars side by side, 2 apart, standing on its foot.
// kept across runs: a value (no field of it changes)
let bars_row : @ui.Style = @ui.css("row gap=S0_5 align=AEnd")

///|
/// Its bars: 4 wide, 4, 8 and 12 high, rounded.
// kept across runs: a value (no field of it changes)
let bar_low : @ui.Style = @ui.css("w=S1 h=S1 radius=Sm")

///|
// kept across runs: a value (no field of it changes)
let bar_mid : @ui.Style = @ui.css("w=S1 h=S2 radius=Sm")

///|
// kept across runs: a value (no field of it changes)
let bar_high : @ui.Style = @ui.css("w=S1 h=S3 radius=Sm")

///|
/// The view's figures (the web's netPanel: 280 wide, 10 between its parts).
let net_panel_w : Double = 280.0

///|
// kept across runs: a value (no field of it changes)
let net_panel_box : @ui.Style = @ui.css("w=Full px=S2_5 py=S2 gap=S2_5")

///|
/// Its head: the mark at 20, the round trip beside it (15, semibold), 10 apart.
// kept across runs: a value (no field of it changes)
let net_head_box : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let net_head_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, wrap=false, tabular=true)

///|
/// A group of its figures, a row each 4 apart: set apart from the one before by its room (6 more than the panel's 10
/// between its parts), no line over it (only a menu's parts are set apart by one).
// kept across runs: a value (no field of it changes)
let net_group_box : @ui.Style = @ui.css("w=Full pt=S1_5")

///|
// kept across runs: a value (no field of it changes)
let net_rows : @ui.Style = @ui.css("w=Full gap=S1")

///|
/// A figure's row: its name in a column 88 wide, its value beside it, 12 apart.
// kept across runs: a value (no field of it changes)
let net_row_box : @ui.Style = @ui.css("row w=Full gap=S3")

///|
let net_name_w : Double = 88.0

///|
// kept across runs: a value (no field of it changes)
let net_row_name : @ui.Style = @ui.style(w=Fixed(net_name_w))

///|
// kept across runs: a value (no field of it changes)
let net_name_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let net_value_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, tabular=true)

// ── 控制中心 (screen_panel.mbt) ───────────────────────────────────────────

///|
/// A choice of it (画质, 缩放): a segmented row in by a panel row's padding.
// kept across runs: a value (no field of it changes)
let center_choice : @ui.Style = @ui.css("w=Full px=S2_5 py=S1")

///|
/// The combos' tiles: rows of three, 8 apart, in by a panel row's padding.
// kept across runs: a value (no field of it changes)
let tiles_box : @ui.Style = @ui.css("w=Full px=S2_5 py=S1 gap=S2")

///|
// kept across runs: a value (no field of it changes)
let tiles_row : @ui.Style = @ui.css("row w=Full gap=S2")

///|
/// A tile: its icon over its name, on the ink at 6% (8% pressed), 64 high, its corner 12.
// kept across runs: a value (no field of it changes)
let tile_box : @ui.Style = @ui.style(w=@sf.grow).then(
  @ui.css("h=S16 gap=S1_5 radius=Xl bg=Tint align=ACenter justify=JCenter pressed{bg=Hover}"),
)

///|
// kept across runs: a value (no field of it changes)
let tile_gap : @ui.Style = @ui.style(w=@sf.grow).then(@ui.css("h=S16"))

///|
/// A key's tile in 常用键: its name alone, 44 high, its corner 12.
// kept across runs: a value (no field of it changes)
let key_tile_box : @ui.Style = @ui.style(w=@sf.grow).then(
  @ui.css("h=S11 radius=Xl bg=Tint align=ACenter justify=JCenter pressed{bg=Hover}"),
)

///|
// kept across runs: a value (no field of it changes)
let key_tile_gap : @ui.Style = @ui.style(w=@sf.grow).then(@ui.css("h=S11"))

///|
// kept across runs: a value (no field of it changes)
let key_tile_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Fg, weight=Semibold, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tile_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Fg, wrap=false)

///|
/// All of the window, what its frame keeps it from (the system's bars) and the page inside it.
// kept across runs: a value (no field of it changes)
let screen_whole : @ui.Style = @ui.css("w=Full h=Full")

///|
/// What its frame leaves it.
// kept across runs: a value (no field of it changes)
let screen_within : @ui.Style = @ui.style(w=Full, h=@sf.grow)
