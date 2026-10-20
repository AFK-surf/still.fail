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
  muted: 0x7A7D83FFL,
  subtle: 0xA6A8ACFFL,
  line: 0xE7E3DCFFL,
  accent: 0xE5704AFFL,
  accent_text: 0xB9471FFFL,
  accent_bg: 0xFBE6DCFFL,
  green: 0x2F8F5BFFL,
  red: 0xC9412EFFL,
  // its placeholders in its bubbles' grey, a step darker than the page
  neutral_bg: 0xE8E4DCFFL,
  card: 0xFFFFFFFFL,
  chip: 0xEFECE6FFL,
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
  subtle: 0x6E7177FFL,
  line: 0x34353AFFL,
  accent: 0xEF7A55FFL,
  accent_text: 0xF6A383FFL,
  accent_bg: 0x4A2F25FFL,
  green: 0x5CC08AFFL,
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
/// still.fail's sizes of words on mbui's scale (Tailwind's names), as the Android app has them: where a `Text` there
/// says no `lineHeight`, its line is the theme's (ui/Theme.kt WebType: 1.4em, the web phone's root.css.ts). Xs a
/// note in lines (12/18, Security.kt:110), Sm the meta line (13/18), Base the body (15/21: 15sp with no line, 206
/// places), Xl2 a title (22/30.8: 22sp bold with no line, Security.kt:473, NewChat.kt:183, Usage.kt:130,
/// Workspaces.kt:191). The other sizes Android has for their own roles: below.
pub let text_scale : @ui.TextScale = {
  ..@ui.TextScale::tailwind(),
  xs: (12.0, 18.0),
  sm: (13.0, 18.0),
  base: (15.0, 21.0),
  xl2: (22.0, 30.8),
}

///|
/// A page's lead, a security page's account of itself (15/22: Security.kt:105, 106, 286; a quote's comment,
/// Composer.kt:562, 708).
pub let lead_size : @ui.TextSize = Exact(15.0, 22.0)

///|
/// A file's or a link's card's name (15/20: Composer.kt:781, 803; ChatFiles.kt:567; DriveScreen.kt:408).
pub let card_title_size : @ui.TextSize = Exact(15.0, 20.0)

///|
/// A message's words (15/24.75: Chat.kt:1363, 1367, 1374).
pub let message_size : @ui.TextSize = Exact(15.0, 24.75)

///|
/// Small words with no line said (12/16.8: 12sp with no line, 120 places).
pub let caption_size : @ui.TextSize = Exact(12.0, 16.8)

///|
/// What says more about something, a row's second line, a page's account of itself (13/18.2: 13sp with no line, 292
/// places: Settings.kt:163, 191, 258).
pub let secondary_size : @ui.TextSize = Exact(13.0, 18.2)

///|
/// A row's value at its end (14/19.6: 14sp with no line, 156 places: SettingParts.kt:258, Settings.kt:176).
pub let value_size : @ui.TextSize = Exact(14.0, 19.6)

///|
/// A row's line of small words under its title, in a list (12/16: OpenJobs.kt:98, AgentSheet.kt:217,
/// DriveScreen.kt:409, Attach.kt:197).
pub let row_caption_size : @ui.TextSize = Exact(12.0, 16.0)

///|
/// The code face's size in a line of its own, its line the font's own (mono).
pub let code_size : @ui.TextSize = Exact(13.0, 0.0)

///|
/// Back in a bar, the word for where it goes (17/23.8: 17sp with no line, Parts.kt:491 NavBack).
pub let back_size : @ui.TextSize = Exact(17.0, 23.8)

///|
/// A compact bar's title (16/22.4: 16sp with no line, Parts.kt:527 NavBar).
pub let bar_title_size : @ui.TextSize = Exact(16.0, 22.4)

///|
/// A page's large title, its big word (32/44.8: 32sp with no line, Parts.kt:559, 562 LargeTitle).
pub let large_title_size : @ui.TextSize = Exact(32.0, 44.8)

///|
/// A settings page's card's corner, and the shapes of cards to come (20, r_card).
pub let card_radius : @ui.Radius = Exact(20.0)

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
  { ..base, text: text_scale }
}

///|
/// The composer's files' row: the gap between what waits in it (Composer.kt: 6 and a remove button's reach past a
/// picture), and the room kept at its end for the last button's reach (Composer.kt `beyond + PictureRemoveOut`).
pub let files_gap : @ui.Space = Exact(11.0)

///|
pub let files_row_end : @ui.Space = Exact(7.0)

///|
/// What waits in the composer, its corner where it is in none of the capsule's (Glass.kt InComposerFiles:
/// concentric(ComposerCorner 26, ComposerFilesIn 10), what Android gives Smooth).
pub let files_corner : @ui.Radius = Exact(18.0)

///|
/// A page's bar (Parts.kt NavBar): back's word (17) and the title (16), each on the font's own line; the title kept
/// 84 clear of the bar's sides; the gap in the line under the title (5).
pub let nav_back_size : @ui.TextSize = Exact(17.0, 0.0)

///|
pub let nav_title_size : @ui.TextSize = Exact(16.0, 0.0)

///|
pub let nav_title_clear : @ui.Space = Exact(84.0)

///|
pub let nav_sub_gap : @ui.Space = Exact(5.0)
