// still.fail's design system (ember web/ui: styles/tokens.css.ts, the values
// in web/src/styles/global.css.ts, the phone's in mobile/styles/root.css.ts),
// for mbui: its colours, type and measures, said once here, so a view built
// with them looks as still.fail's own pages do.
//
// Two grounds: the wide screen's (white canvas, ink, the ember orange) and
// the narrow screen's (as the Android app: warm paper, its own greys, type a
// size up). Each light and dark. `begin` picks them each frame from the
// window's width and the appearance set.

///|
/// The colours a view reads (the web's names: `text` is --text, `bg` the
/// page's ground: the canvas on a wide screen, the warm paper on a narrow).
pub(all) struct Palette {
  bg : Int64
  canvas : Int64
  /// what floats over the page (a bar, a capsule)
  raised : Int64
  sidebar : Int64
  list : Int64
  text : Int64
  muted : Int64
  subtle : Int64
  line : Int64
  line_strong : Int64
  hover : Int64
  selected : Int64
  paper : Int64
  accent : Int64
  accent_text : Int64
  accent_bg : Int64
  green : Int64
  /// green and amber as words, dark enough to read on paper (Theme.kt greenInk, warnInk; the web's --green,
  /// --amber)
  green_ink : Int64
  warn_ink : Int64
  red : Int64
  red_bg : Int64
  /// placeholders' grey (waiting), a quiet pill's ground
  neutral_bg : Int64
  overlay : Int64
  shadow : Int64
  primary : Int64
  primary_hover : Int64
  on_primary : Int64
  /// a card's ground on the page
  card : Int64
  /// the narrow screen's quiet button
  chip : Int64
  /// links (--blue)
  blue : Int64
  /// inline code's words (--code-inline), a code block's ground (the text
  /// at 4% in the canvas)
  code_ink : Int64
  code_ground : Int64
}

///|
/// Six roles of type, each a size with its line, and the three weights
/// (400; 500 to stand out; 600 for titles).
pub(all) struct Type {
  caption : Double
  caption_line : Double
  meta : Double
  meta_line : Double
  ui : Double
  ui_line : Double
  body : Double
  body_line : Double
  title : Double
  title_line : Double
  heading : Double
  heading_line : Double
  display : Double
}

///|
pub(all) struct Theme {
  dark : Bool
  /// the narrow screen's (a phone's) ground and type
  narrow : Bool
  p : Palette
  t : Type
}

// ---------------------------------------------------------------------------
// Measures (docs/ui-panels.md; styles/align.ts, pages.css.ts)

///|
/// A small panel's padding: as far as what has a ground of its own (a row,
/// a button) stands from its edge.
pub let panel_pad : Double = 6.0

///|
/// Words stand in from a row's ground by this, so a panel's words and its
/// rows' words are on one line, panel_pad + text_in from its edge.
pub let text_in : Double = 10.0

///|
/// A small panel's buttons: pills this high (24), and its icon buttons
/// circles as wide.
pub let panel_pill : Double = 24.0

///|
/// A page card of words: this in from every side.
pub let card_pad : Double = 20.0

///|
/// A card's corner with nothing in its corners.
pub let card_corner : Double = 22.0

///|
/// A button's height (36), whose half a card's corner takes when one is in
/// its corner: card_pad + 18.
pub let button_h : Double = 36.0

///|
/// A card of pressable rows: the rows this far in, each with row_corner,
/// the card's corner theirs and this together.
pub let list_pad : Double = 8.0

///|
pub let row_corner : Double = 18.0

///|
/// Corners (--r-*): a field's, a card's, a dialog's, the nav's, a menu's,
/// an option's.
pub let r_field : Double = 12.0

///|
pub let r_card : Double = 20.0

///|
pub let r_dialog : Double = 32.0

///|
pub let r_menu : Double = 20.0

///|
pub let r_option : Double = 12.0

///|
/// --dur, for hovers and small changes.
pub let dur_ms : Double = 140.0

///|
/// Below this width the narrow screen's ground and type (the web's 700px).
pub let narrow_below : Double = 700.0

// ---------------------------------------------------------------------------

///|
let wide_light : Palette = {
  bg: 0xFFFFFFFFL,
  canvas: 0xFFFFFFFFL,
  raised: 0xE4E4E8FFL,
  sidebar: 0xF6F5F1FFL,
  list: 0xFBFAF9FFL,
  text: 0x24272BFFL,
  muted: 0x646970FFL,
  subtle: 0x73787DFFL,
  line: 0xE3E1DEFFL,
  line_strong: 0xC1C4C9FFL,
  hover: 0x26211711L,
  selected: 0xEBE7E1FFL,
  paper: 0xF6F2EAFFL,
  accent: 0xEF6A3CFFL,
  accent_text: 0xA23203FFL,
  accent_bg: 0xFFEFE6FFL,
  green: 0x006A3FFFL,
  green_ink: 0x006A3FFFL,
  warn_ink: 0x7F5306FFL,
  red: 0xA12F35FFL,
  red_bg: 0xFFF0EFFFL,
  neutral_bg: 0xEDEFF1FFL,
  overlay: 0x13161B33L,
  shadow: 0x13161B1AL,
  primary: 0x24272BFFL,
  primary_hover: 0x41464CFFL,
  on_primary: 0xFFFFFFFFL,
  // the text at 4% over the canvas (pages.css.ts cardGround)
  card: 0xF6F6F7FFL,
  chip: 0xEFECE6FFL,
  blue: 0x1559C4FFL,
  code_ink: 0x7C3FA0FFL,
  code_ground: 0xF5F5F5FFL,
}

///|
let wide_dark : Palette = {
  bg: 0x1F2023FFL,
  canvas: 0x1F2023FFL,
  raised: 0x2A2C31FFL,
  sidebar: 0x19191BFFL,
  list: 0x1C1D20FFL,
  text: 0xE9E9EAFFL,
  muted: 0xA3A5A9FFL,
  subtle: 0x8C8F94FFL,
  line: 0x2D2E32FFL,
  line_strong: 0x3D3F44FFL,
  hover: 0xFFFFFF0DL,
  selected: 0x323338FFL,
  paper: 0x26272BFFL,
  accent: 0xF57E4DFFL,
  accent_text: 0xFC9B6FFFL,
  accent_bg: 0x43251AFFL,
  green: 0x68C894FFL,
  green_ink: 0x68C894FFL,
  warn_ink: 0xE6B55DFFL,
  red: 0xF68482FFL,
  red_bg: 0x442322FFL,
  neutral_bg: 0x2A2B2FFFL,
  overlay: 0x00000080L,
  shadow: 0x00000073L,
  primary: 0xECEDEDFFL,
  primary_hover: 0xD3D4D6FFL,
  on_primary: 0x1F2023FFL,
  card: 0x28292CFFL,
  chip: 0x313237FFL,
  blue: 0x81AEFAFFL,
  code_ink: 0xC9A2E6FFL,
  code_ground: 0x26272AFFL,
}

///|
/// The narrow screen's (root.css.ts m): warm paper, its own greys; what the
/// wide screen's names mean there.
let narrow_light : Palette = {
  ..wide_light,
  bg: 0xF5F3EFFFL,
  canvas: 0xFFFFFFFFL,
  raised: 0xFFFFFFFFL,
  text: 0x24272BFFL,
  // the greys and the red Android's (Theme.kt Light), what the app on a phone matches, not the narrow web's
  muted: 0x626469FFL,
  subtle: 0x7C7E81FFL,
  line: 0xE7E3DCFFL,
  accent: 0xE5704AFFL,
  accent_text: 0xB9471FFFL,
  accent_bg: 0xFBE6DCFFL,
  green: 0x2F8F5BFFL,
  green_ink: 0x287A4DFFL,
  warn_ink: 0x98691EFFL,
  red: 0xBF3E2CFFL,
  // its placeholders in its bubbles' grey, a step darker than the page
  neutral_bg: 0xE8E4DCFFL,
  card: 0xFFFFFFFFL,
  // Android's C.chip (Theme.kt), what the app on a phone matches, not the narrow web's EFECE6
  chip: 0xE8E4DCFFL,
  hover: 0x24272B0FL,
}

///|
let narrow_dark : Palette = {
  ..wide_dark,
  bg: 0x1B1C1FFFL,
  canvas: 0x26272BFFL,
  raised: 0x2A2C31FFL,
  text: 0xECECEDFFL,
  muted: 0x9A9DA3FFL,
  // Android's (Theme.kt Dark)
  subtle: 0x84888FFFL,
  line: 0x34353AFFL,
  accent: 0xEF7A55FFL,
  accent_text: 0xF6A383FFL,
  accent_bg: 0x4A2F25FFL,
  green: 0x5CC08AFFL,
  green_ink: 0x5CC08AFFL,
  warn_ink: 0xD9962BFFL,
  red: 0xEB6B58FFL,
  neutral_bg: 0x313237FFL,
  card: 0x26272BFFL,
  chip: 0x313237FFL,
  hover: 0xECECED14L,
}

///|
let wide_type : Type = {
  caption: 11.0,
  caption_line: 16.0,
  meta: 12.0,
  meta_line: 18.0,
  ui: 13.0,
  ui_line: 20.0,
  body: 14.0,
  body_line: 22.0,
  title: 16.0,
  title_line: 24.0,
  heading: 22.0,
  heading_line: 30.0,
  display: 28.0,
}

///|
/// The phone's: a size up, as Android's.
let narrow_type : Type = {
  ..wide_type,
  caption: 12.0,
  meta: 13.0,
  meta_line: 18.0,
  ui: 15.0,
  ui_line: 22.0,
  body: 15.0,
  body_line: 22.0,
}

///|
let dark_set : Ref[Bool?] = { val: None }

///|
let current : Ref[Theme] = {
  val: { dark: false, narrow: false, p: wide_light, t: wide_type },
}

///|
/// Light or dark from now on (None: as the system, which hosts don't tell
/// yet: light).
pub fn set_dark(dark : Bool?) -> Unit {
  dark_set.val = dark
}

///|
/// The theme for this frame, from the window's width: call at the top of a
/// view.
pub fn begin(c : @ui.Ctx) -> Theme {
  let dark = dark_set.val.unwrap_or(false)
  let narrow = c.width < narrow_below
  let p = match (narrow, dark) {
    (false, false) => wide_light
    (false, true) => wide_dark
    (true, false) => narrow_light
    (true, true) => narrow_dark
  }
  current.val = { dark, narrow, p, t: if narrow { narrow_type } else { wide_type } }
  current.val
}

///|
/// A link's ink (Android's C.link, Theme.kt): the accent's darker ink on paper, the accent itself in the dark.
pub fn link_ink() -> Int64 {
  let t = theme()
  if t.dark {
    t.p.accent
  } else {
    t.p.accent_text
  }
}

///|
/// The theme `begin` picked.
pub fn theme() -> Theme {
  current.val
}

// ---------------------------------------------------------------------------
// Colours mixed as the web's color-mix does

///|
/// `top` laid over `base` (alpha compositing; base opaque or not).
pub fn over(base : Int64, top : Int64) -> Int64 {
  let ta = (top & 0xFFL).to_double() / 255.0
  let ba = (base & 0xFFL).to_double() / 255.0
  let oa = ta + ba * (1.0 - ta)
  if oa <= 0.0 {
    return 0L
  }
  let ch = fn(shift : Int) -> Int64 {
    let t = ((top >> shift) & 0xFFL).to_double()
    let b = ((base >> shift) & 0xFFL).to_double()
    let v = (t * ta + b * ba * (1.0 - ta)) / oa
    v.round().to_int64()
  }
  (ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | (oa * 255.0).round().to_int64()
}

///|
/// `c` at `share` of its opacity (color-mix with transparent).
pub fn alpha(c : Int64, share : Double) -> Int64 {
  let a = (c & 0xFFL).to_double() * share
  (c & 0xFFFFFF00L) | a.round().to_int64()
}

///|
/// `share` of `a` and the rest of `b` (color-mix in srgb).
pub fn mix(a : Int64, share : Double, b : Int64) -> Int64 {
  let ch = fn(shift : Int) -> Int64 {
    let x = ((a >> shift) & 0xFFL).to_double()
    let y = ((b >> shift) & 0xFFL).to_double()
    (x * share + y * (1.0 - share)).round().to_int64()
  }
  (ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)
}

// ---------------------------------------------------------------------------
// mbui's tokens (its docs/style.md): what still.fail's styles (styles.mbt) say by name. The numbers are here and
// nowhere else; a value off mbui's scale is one of the few `Exact`s below.

///|
/// still.fail's sizes of words on mbui's scale (Tailwind's names, still.fail's values), the eight the Android app
/// has, each with the line it has where a `Text` there says no `lineHeight` (ui/Theme.kt WebType: 1.4em, the web
/// phone's root.css.ts), and mbui's two under Xs (Xs3 10, Xs2 11) on the same rule: Xs 12 (120 places), Sm 13 (292), Base 14 (156), Lg 15 (206: the body), Xl 16 (a bar's
/// title, Parts.kt:527), Xl2 17 (back, Parts.kt:491), Xl3 22 (a title, bold: Security.kt:473, NewChat.kt:183,
/// Usage.kt:130, Workspaces.kt:191), Xl4 32 (a large title, Parts.kt:559).
pub let text_scale : @ui.TextScale = {
  xs3: (10.0, 14.0),
  xs2: (11.0, 15.4),
  xs: (12.0, 16.8),
  sm: (13.0, 18.2),
  base: (14.0, 19.6),
  lg: (15.0, 21.0),
  xl: (16.0, 22.4),
  xl2: (17.0, 23.8),
  xl3: (22.0, 30.8),
  xl4: (32.0, 44.8),
}

///|
/// The lines Android says (`lineHeight`), in place of the size's own (Leading): L4 16 (a row's small line in a list:
/// OpenJobs.kt:98, AgentSheet.kt:217, DriveScreen.kt:409, Attach.kt:197), L5 18 (a note, a meta line: Security.kt:110,
/// 485), L6 20 (a file's or a link's card's name: Composer.kt:781, 803; ChatFiles.kt:567; DriveScreen.kt:408), L7 22
/// (a lead, a paragraph: Security.kt:105, 106, 286; Composer.kt:562, 708).
pub let leading_scale : @ui.LeadingScale = {
  ..@ui.LeadingScale::tailwind(),
  l4: 16.0,
  l5: 18.0,
  l6: 20.0,
  l7: 22.0,
}

///|
/// still.fail's corners on mbui's scale (in order): Xl1_5 16 (Smooth(16.dp): a 32 high button or choice, 接管's),
/// Xl2 18 (what waits in the composer, where it is in none of the capsule's corners: Glass.kt InComposerFiles,
/// concentric(ComposerCorner 26, ComposerFilesIn 10), what Android gives Smooth), Xl3 22 (a settings page's card and
/// the waiting cards' shapes: Parts.kt CARD_CORNER, Waiting.kt:185), Xl4 24 (a capsule round a 40 button 4 in: the
/// remote screen's folded tools).
pub let radii : @ui.RadiusScale = {
  ..@ui.RadiusScale::tailwind(),
  xl1_5: 16.0,
  xl2: 18.0,
  xl3: card_corner,
  xl4: 24.0,
}

///|
/// A large title's letters drawn closer (Parts.kt:559, 562 LargeTitle: letterSpacing -0.6sp): off Tailwind's scale
/// (Tight is -0.8 at 32).
pub let large_title_tracking : @ui.Tracking = Exact(-0.6)

///|
/// A message's line (24.75: Chat.kt:1363, 1367, 1374), the one place Android says it.
pub let message_line : @ui.Leading = Exact(24.75)

///|
/// A card with a button (a capsule) in its corner: concentric with it, card_pad and the button's half (Parts.kt:607
/// Card foot: CARD_PAD + BUTTON_HEIGHT 38 / 2): worked out as Android does, no step of the scale.
pub let card_foot_radius : @ui.Radius = Exact(card_pad + 19.0)

///|
/// A list card's corner: concentric round its rows (row_corner, list_pad in), as Android works it out (Parts.kt:640
/// LIST_CARD_CORNER = concentricOut(LIST_ROW_CORNER 18, LIST_PAD 8)); its rows take theirs from it (radius=Inner).
pub let list_card_radius : @ui.Radius = Exact(concentric_out(row_corner, list_pad))

///|
/// A card with a Seg (rounded 10) in its top corners: concentric with it (Usage.kt:204 concentricOut(10, CARD_PAD)):
/// worked out as Android does, no step of the scale.
pub let seg_card_radius : @ui.Radius = Exact(concentric_out(10.0, card_pad))

///|
/// A small dot's side, how a thing stands (7: PageParts.kt:465 PresenceDot, Security.kt:101 Dot).
pub let dot_size : @ui.Len = Fixed(7.0)

///|
/// An option of a segmented choice in the wide frame, at its narrowest (the web's 105, controls.css.ts seg, less the
/// track's inset on both sides).
pub let seg_pill_min : @ui.Len = Fixed(101.0)

///|
/// A code's box's edge: the words' colour at 18%.
pub let code_edge : @ui.Color = A(Fg, Exact(0.18))

///|
/// A column a phone's width at most, in the middle (phone_column): its widest.
pub let phone_max : @ui.Len = Fixed(420.0)

///|
/// The theme as mbui's (its Theme's roles over this frame's palette: wide or narrow, light or dark), with
/// still.fail's sizes of words: what the styles' tokens are looked up in.
pub fn ui_theme() -> @ui.Theme {
  let t = current.val
  let base = match (t.narrow, t.dark) {
    (false, false) => @ui.Theme::light()
    (false, true) => @ui.Theme::dark()
    (true, false) => @ui.Theme::narrow_light()
    (true, true) => @ui.Theme::narrow_dark()
  }
  // a link's ink as Android's C.link (Theme.kt): the accent's darker ink on paper, the accent itself in the dark
  {
    ..base,
    text: text_scale,
    leading: leading_scale,
    radii,
    link: if t.dark { base.accent } else { base.accent_text },
    // a line of words that say none 1.4 of their size, as the web's root (`line-height: 1.4`) and Android's (Theme.kt
    // WebType: 1.4.em)
    text_line: 1.4,
  }
}

///|
/// The composer's files' row: the gap between what waits in it (Composer.kt: 6 and a remove button's reach past a
/// picture), and the room kept at its end for the last button's reach (Composer.kt `beyond + PictureRemoveOut`).
pub let files_gap : @ui.Space = Exact(11.0)

///|
pub let files_row_end : @ui.Space = Exact(7.0)

///|
/// A page's bar (Parts.kt NavBar): the title kept 84 clear of the bar's sides; the gap in the line under the title (5).
pub let nav_title_clear : @ui.Space = Exact(84.0)

///|
pub let nav_sub_gap : @ui.Space = space_5

///|
/// 5, off the scale's 4 and 6: the gap in the line under a bar's title (nav_sub_gap), a row's room above and under in
/// a sheet of chats (Composer.kt askToShare: padding(vertical = 5)).
pub let space_5 : @ui.Space = S1_25

///|
/// A tag's widest (PageParts.kt StationTag: widthIn(max = 104)).
pub let tag_max : @ui.Len = Fixed(104.0)

///|
/// A chat in the `@` menu at its lowest (Composer.kt ChatRefMenu: heightIn(min = 44)).
pub let ref_row_min_h : @ui.Len = Fixed(44.0)

///|
/// The search (Search.kt): its field 38 high (FIELD) on the ink at 6%; a row found 66 high (HitRow, ItemRow; 50 an item
/// with no line of words), its first line 22; what a row found says starts 22 in.
pub let search_field_h : @ui.Len = Fixed(38.0)

///|
pub let search_ground : @ui.Color = A(Fg, Exact(0.06))

///|
pub let found_row_h : @ui.Len = Fixed(66.0)

///|
pub let found_row_short_h : @ui.Len = Fixed(50.0)

///|
pub let found_line_h : @ui.Len = Fixed(22.0)

///|
pub let found_start : @ui.Space = Exact(22.0)

///|
/// What takes the room left in a row or a column (Compose's `weight(1f)`).
pub let grow : @ui.Len = Grow(1.0)

///|
/// Words on one line given the room left in their row, cut there with an ellipsis (Compose's Text with maxLines = 1
/// in a Row: measured in what is left).
pub let line_left : @ui.Size = Fill(1.0)

///|
/// A visualization in a message (Android ui/Viz.kt, chat/VizFiles.kt): its place while it comes (120 high), the ways
/// under it (22 boxes); a whole page's corners (Smooth 20, the web's card) on its paper (#F6F2EA, dark #26272B); the
/// full screen's name 18 in (Viz.kt VizFull).
pub let viz_wait_h : @ui.Len = Fixed(120.0)

///|
pub let viz_way_side : @ui.Len = Fixed(22.0)

///|
pub let viz_card_radius : @ui.Radius = Exact(20.0)

///|
pub let viz_paper : @ui.Color = Exact(0xF6F2EAFFL)

///|
pub let viz_paper_dark : @ui.Color = Exact(0x26272BFFL)

///|
pub let viz_full_in : @ui.Space = S4_5

///|
/// Marking a service's page (Preview.kt MarkMode, MarksOver, Note): its bar 30 high, 3 in at its end, 添加到对话's
/// icon and words 5 apart; the dot's ring 13; the edit key's ground the accent's 14%, the ring's 22%, an open mark's
/// 8%; what floats over the page frosted thick (the surface at 94%; dark, surface2's); a pin's number 11; what is said
/// of a mark 26 high.
pub let mark_bar_h : @ui.Len = Fixed(30.0)

///|
pub let mark_bar_end : @ui.Space = Exact(3.0)

///|
pub let mark_put_gap : @ui.Space = space_5

///|
pub let mark_ring : @ui.Len = Fixed(13.0)

///|
pub let mark_key_on : @ui.Color = A(Accent, Exact(0.14))

///|
pub let mark_ring_bg : @ui.Color = A(Accent, Exact(0.22))

///|
pub let mark_open_bg : @ui.Color = A(Accent, Exact(0.08))

///|
pub let mark_bubble : @ui.Color = A(Card, Exact(0.94))

///|
pub let mark_bubble_dark : @ui.Color = Exact(0x2C2D31F0L)

///|
pub let mark_pin_size : @ui.TextSize = Exact(11.0, 15.4)

///|
pub let mark_said_h : @ui.Len = Fixed(26.0)

///|
/// How much of a file has come (FilePreview.kt FileProgress): 220 wide.
pub let file_progress_w : @ui.Len = Fixed(220.0)

///|
/// A size typed (Preview.kt CustomSize): its fields 72 wide, 10 round.
pub let custom_field_w : @ui.Len = Fixed(72.0)

///|
pub let custom_field_r : @ui.Radius = Exact(10.0)

// ---------------------------------------------------------------------------
// A station's screen, seen and driven (Android app/remote/ScreenViewer.kt): its sizes off the steps, as Android says
// them.

///|
/// The side rail (60), a file's key (34), a progress track's height (3), the bounds of what floats over the frame
/// (接管 480, the rail's line 280, what an ended view says 320).
pub let rail_w : @ui.Len = Fixed(60.0)

///|
pub let row_key : @ui.Len = Fixed(34.0)

///|
pub let track_h : @ui.Len = Fixed(3.0)

///|
pub let take_over_max : @ui.Len = Fixed(480.0)

///|
pub let rail_say_max : @ui.Len = Fixed(280.0)

///|
pub let ended_max : @ui.Len = Fixed(320.0)

///|
/// A button's height on the phone (Controls.kt BUTTON_HEIGHT 38).
pub let button_38 : @ui.Len = Fixed(38.0)

///|
/// A link's card in a message (ScreenLinks.kt, AdbLinks.kt): 236 wide; a screen's with its preview over its words 280.
pub let link_card_w : @ui.Len = Fixed(236.0)

///|
pub let peek_card_px : Double = 280.0

///|
pub let peek_card_w : @ui.Len = Fixed(peek_card_px)

///|
/// A link's card's mark, 30 wide (36 high: S9), as the web's.
pub let link_mark_w : @ui.Len = Fixed(30.0)

///|
/// A quiet ground under what is grouped on a sheet (Publish.kt: the ink at 4%).
pub let faint_ground : @ui.Color = A(Fg, Exact(0.04))

///|
/// How wide a face's status at its row's end may be (Fonts.kt:142).
pub let face_status_most : @ui.Len = Fixed(140.0)

///|
/// A Slack app's icon as it is in its look (SlackApp.kt AppLook: 72 square), off the scale.
pub let app_icon_side : @ui.Len = Fixed(72.0)
