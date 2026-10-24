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
  /// the grounds of a pill in a tone (parts.css.ts pill: --green-bg, --blue-bg, --amber-bg; the amber's ink is
  /// warn_ink)
  green_bg : Int64
  blue_bg : Int64
  amber_bg : Int64
  /// a station online (--online: a status dot, parts.css.ts statusDot)
  online : Int64
  /// placeholders' grey (waiting), a quiet pill's ground
  neutral_bg : Int64
  overlay : Int64
  shadow : Int64
  primary : Int64
  primary_hover : Int64
  on_primary : Int64
  /// a card's ground on the page
  card : Int64
  /// what sits a step apart on a card: a command's box (Theme.kt surface2, root.css.ts --m-surface2)
  card2 : Int64
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

// (a small panel's padding, its words' room and its pills: align.mbt panel_pad, text_in, panel_pill)

///|
/// The corner ladder (docs/ui-panels.md「圆角阶梯」): the few corners nested things are round by, outermost first, each
/// the one before it concentric `corner_inset` in (smooth.mbt concentric: that over 1.25 less): a pane of the frame
/// (the tape's panels laid out Medium, a dialog), a card (a page's card, a sheet, the composer), a row or a block on a
/// card, a small block on a row. What has a ground and lies in a container's corner stands `corner_inset` in from both
/// its edges and is round by the next step (mbui works its corner out: corners.mbt), or is a capsule or a circle `its
/// half less than the container's corner` in. The theme's (Theme::corner_ladder): screen tests hold every corner with
/// something in it, and what is there, to these.
pub let pane_corner : Double = 34.0

///|
pub let corner_inset : Double = 10.0

///|
pub let card_corner : Double = @ui.concentric(pane_corner, corner_inset)

///|
pub let row_corner : Double = @ui.concentric(card_corner, corner_inset)

///|
pub let small_corner : Double = @ui.concentric(row_corner, corner_inset)

///|
// kept across runs: a value (no field of it changes)
pub let corner_ladder : Array[Double] = [pane_corner, card_corner, row_corner, small_corner]

///|
/// The corner of the panel of its own the view is built in (the tape's, laid out Medium: pane_corner), None in a
/// window's whole: what a page stands in that panel's foot or top corners stands where it is concentric with it
/// (`foot_in`).
// kept across runs: said by the frame round each panel of its own it builds
pub let pane_round : Ref[Double?] = Ref(None)

///|
/// Whether the page being built is in a panel of its own (pane_round): what stands in its corners stands concentric
/// with the panel's.
pub fn in_pane() -> Bool {
  pane_round.val is Some(_)
}

///|
/// How far in from its panel's sides and foot a capsule `height` high stands at a page's foot: concentric with the
/// panel's corner in a panel of its own (pane_round), else `alone`.
pub fn foot_in(height : Double, alone : Double) -> Double {
  match pane_round.val {
    Some(r) => capsule_in(r, height)
    None => alone
  }
}

///|
/// How far in from a corner of the ladder's `corner` a capsule or a circle `height` high stands, concentric with it
/// (ui-panels.md: 外圆角 = 距离 + 半高).
pub fn capsule_in(corner : Double, height : Double) -> Double {
  corner - height / 2.0
}

///|
/// How far in a capsule `height` high stands from a card's sides and foot where it is in the card's foot corners (a
/// button, a field there: concentric with the card's corner), and its ground reaching past the card's words (card_pad
/// in) to there: across the card, or at its start with its words where they were (`words_in`: its own padding).
pub fn card_foot_in(height : Double) -> Double {
  capsule_in(card_corner, height)
}

///|
pub fn foot_across(height : Double) -> @ui.Style {
  @ui.style(mx=room(card_foot_in(height) - card_pad))
}

///|
pub fn foot_start(height : Double, words_in : Double) -> @ui.Style {
  @ui.style(ml=room(card_foot_in(height) - card_pad), pl=room(words_in + card_pad - card_foot_in(height)))
}

///|
/// A card's rows `row_h` high, each with something `end_h` high in its middle at its end (a key's button): reaching into
/// the card's padding over the first and under the last by as much as that stands in from a row's top and foot, so the
/// first's and the last's stand in the card's corners as far from both its edges (round by the ladder's there: mbui
/// works it out).
pub fn card_rows_reach(row_h : Double, end_h : Double) -> @ui.Style {
  @ui.style(my=room((end_h - row_h) / 2.0))
}

///|
/// A block (a command's box, a table) across a card's foot, its ground reaching past the card's words to the
/// ladder's inset: round by the ladder's next step there.
pub let block_across : @ui.Style = @ui.style(mx=room(corner_inset - card_pad))

///|
/// A card's foot with a capsule `height` high in its corners: as far in as makes it concentric (card_foot_in).
pub fn foot_pad(height : Double) -> @ui.Style {
  @ui.style(pb=room(card_foot_in(height)))
}

///|
/// The ladder's steps and inset as a style's: a card's corner, a row's or a block's, a small block's; the inset;
/// what a card's words stand in from a list's rows (card_pad less the inset); what a card's corner keeps clear past
/// its words (its corner less card_pad).
pub let card_radius : @ui.Radius = rounded(card_corner)

///|
pub let row_radius : @ui.Radius = rounded(row_corner)

///|
pub let small_radius : @ui.Radius = rounded(small_corner)

///|
pub let inset_room : @ui.Space = room(corner_inset)

///|
pub let list_words_room : @ui.Space = room(card_pad - corner_inset)

///|
pub let corner_clear_room : @ui.Space = room(card_corner - card_pad)

///|
/// How far in from a corner of `corner` a capsule `height` high stands concentric with it (capsule_in), as a style's
/// room; `less`, less what already stands between (a row's own inset, a line over it).
pub fn capsule_room(corner : Double, height : Double, less? : Double = 0.0) -> @ui.Space {
  room(capsule_in(corner, height) - less)
}

///|
/// How far in from a capsule's ends (`outer` high) one `height` high stands in it, concentric with them (a dot, a
/// button in a capsule's end), as a style's room.
pub fn capsule_end_room(outer : Double, height : Double) -> @ui.Space {
  room(capsule_in(outer / 2.0, height))
}

///|
/// `more` under the system's bar at the window's top (a phone's status bar; 0 where the host lays the app out under it):
/// where what floats at the top of a layer over the whole window stands.
pub fn system_top_room(more : Double) -> @ui.Space {
  room(more + @ui.system_bars().top)
}

///|
/// How far under a page's bar what is drawn from the page's top stands (the bar 45, in a panel of its own as much taller
/// as puts its buttons in the panel's corner concentric with it: tape_bar_over).
pub fn under_bar_room() -> @ui.Space {
  room(wide_bar_h + (if in_pane() { tape_bar_over } else { 0.0 }))
}

///|
/// Where a page's capsule `height` high stands at its foot (foot_in): in from its panel's sides by as much more than
/// the page's own `side` room as makes it concentric there (a margin, `side` less that), and over its foot.
pub fn foot_corner(height : Double, side : Double, foot : Double) -> @ui.Style {
  @ui.style(mx=room(foot_in(height, side) - side), pb=room(foot_in(height, foot)))
}

///|
/// A page card of words: this in from every side.
pub let card_pad : Double = 20.0

///|
/// A command's box's corner: a block's on a card, its copy button corner_inset in from its corner.
pub let command_box_corner : Double = row_corner

///|
/// A button's height (36): a capsule, capsule_in(card_corner, 36) in from a card's corner where it stands in one.
pub let button_h : Double = 36.0

///|
/// A card of pressable rows: the rows this far in (the ladder's inset), each round by row_corner.
pub let list_pad : Double = corner_inset

///|
/// A settings row's icon, before its name (SettingParts.kt ROW_ICON).
pub let row_icon : Double = 22.0

///|
/// A finger's list row in from its box's left (SidebarList.css.ts phone: a chat row's 22).
pub let phone_row_in : @ui.Space = room(22.0)

///|
/// An empty list's illustration and words in from its sides (Home.kt Empty: 30).
pub let empty_in : @ui.Space = room(30.0)

///|
/// The account's picture and the workspace's mark, each on its card atop settings (SettingsHome.kt): 46.
pub let identity_mark : Double = 46.0

///|
/// The workspace's mark's square (SettingsHome.kt WorkspaceTile): the account's picture's size beside it, card_pad from
/// its card's edges, so in its corners: concentric with the card's (22, 20 in: 6, Md), what it holds in its middle.
pub let workspace_tile : @ui.Style = @ui.style(
  w=Fixed(identity_mark),
  h=Fixed(identity_mark),
  radius=Md,
  align=ACenter,
  justify=JCenter,
  clip=true,
)

///|
/// A mark of the workspace's own (one of still.fail's icons, an emoji) in its square: 26.
pub let workspace_tile_mark : Double = 26.0

///|
/// A workspace's first letter in its square, where it has no mark: 22 on a line of 22 (Xl3, L7: SettingsHome.kt's
/// lineHeight, near the account's initial beside it, half its picture), semibold, muted (Rail.css.ts workspaceItem).
pub let workspace_letter : @ui.TextStyle = @ui.text_style(size=Xl3, leading=L7, weight=Semibold, color=Muted, wrap=false)

///|
/// A chip whose ground fills from the left (an allowance's, a machine's load, a download's: Parts.kt FILL_CHIP_CORNER):
/// round by the ladder's small corner (a small one's 16 a capsule); in a card's or a row's corner concentric with it
/// (mbui works it out).
pub let fill_chip_corner : Double = small_corner

///|
/// Corners (--r-*): a field's, a card's, a dialog's, the nav's, a menu's,
/// an option's.
pub let r_field : Double = 12.0

///|
pub let r_card : Double = 20.0

///|
pub let r_dialog : Double = 32.0

///|
/// (a small panel's: a menu, a popover, a hover's card: a card of the ladder's, its rows its inset in, round by the
/// next step)
pub let r_menu : Double = card_corner

///|
pub let r_option : Double = 12.0

///|
/// --dur, for hovers and small changes.
pub let dur_ms : Double = 140.0

///|
/// Where a desktop's window, which no system classes, goes from one layout to the next (layout): the widths at which
/// Android's WindowSizeClass goes from compact to medium and from medium to expanded, so a window as wide is laid out
/// alike whatever the system.
pub let medium_from : Double = 600.0

///|
pub let large_from : Double = 840.0

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
  green_bg: 0xE7F6EDFFL,
  blue_bg: 0xEAF2FFFFL,
  amber_bg: 0xFEF4E0FFL,
  online: 0x45B164FFL,
  neutral_bg: 0xEDEFF1FFL,
  overlay: 0x13161B33L,
  shadow: 0x13161B1AL,
  primary: 0x24272BFFL,
  primary_hover: 0x41464CFFL,
  on_primary: 0xFFFFFFFFL,
  // the text at 4% over the canvas (pages.css.ts cardGround)
  card: 0xF6F6F7FFL,
  card2: 0xFBFAF7FFL,
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
  green_bg: 0x1B3426FFL,
  blue_bg: 0x1F2E47FFL,
  amber_bg: 0x403012FFL,
  online: 0x45B164FFL,
  neutral_bg: 0x2A2B2FFFL,
  overlay: 0x00000080L,
  shadow: 0x00000073L,
  primary: 0xECEDEDFFL,
  primary_hover: 0xD3D4D6FFL,
  on_primary: 0x1F2023FFL,
  card: 0x28292CFFL,
  card2: 0x2C2D31FFL,
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
  // the sidebar beside the page (a tablet's Medium and Large): a step under the page's ground as the web's is under
  // its canvas (FFFFFF → F6F5F1), the panes told apart by their grounds; what is chosen in it a step under that, as
  // the web's (F6F5F1 → EBE7E1). The web's own, over this page's beige, were the page's colour
  sidebar: 0xECE9E1FFL,
  selected: 0xE1DBD1FFL,
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
  // the sidebar a step under the page's ground, as the web's dark one under its canvas (1F2023 → 19191B)
  sidebar: 0x151517FFL,
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
/// Whether the system is a phone's or a tablet's (iOS, Android): its own theme at any size, its window's layout by the
/// system's size classes (layout). How things answer the hand is not this: @ui.pointing.
pub fn touch_system() -> Bool {
  let p = @ui.platform()
  p == 1 || p == 2
}

///|
/// How the app's panes are laid out, by the screen alone: how much room its window has and what kind of screen it is.
/// Never by what it is pointed with (@ui.pointing): each is pointed at with a mouse or a finger alike.
pub(all) enum Layout {
  /// one page at a time, the whole window (a phone held upright, a narrow window)
  Small
  /// the panes side by side as on a large screen, more of them than the window shows: the one in use whole, those
  /// beside it showing past its edges, one tapped coming over before what it holds answers (sfdesk's frame.mbt)
  Medium
  /// the panes side by side, all of them shown: the rail and the sidebar, the page, the page's side panel
  Large
} derive(Eq, Show, Debug)

///|
/// The layout of a window `width` wide, in points, on every screen alike (medium_from, large_from): neither which way up
/// it is held, nor its height, nor how large it is says how many panes there are (the user, 2026-10-25); the height
/// only how much of them shows. One thing else: a fold half open on its back half is Small (a chat across the window,
/// its composer under the fold: sfapp's tabletop.mbt). While
/// the app has the device turned sideways itself (a film, a station's screen over all of it: @hostapi.sideways), the
/// one it had as it turned: the screen is the same, only what is over all of it turned.
pub fn layout(width : Double) -> Layout {
  let now = screen_layout(width)
  if !@hostapi.sideways() {
    layout_held.val = None
    return now
  }
  match layout_held.val {
    Some(held) => held
    None => {
      layout_held.val = Some(now)
      now
    }
  }
}

///|
/// The layout as the app turned the device sideways (layout), while it has it so.
// kept across runs: let go as the device is upright again
let layout_held : Ref[Layout?] = Ref(None)

///|
/// The layout by the screen alone (layout).
fn screen_layout(width : Double) -> Layout {
  // a fold half open, its crease across: a chat over the crease, whatever its width (the one thing other than the width)
  if touch_system() && @ui.system_tabletop() is Some(_) {
    return Small
  }
  if width < medium_from {
    Small
  } else if width < large_from {
    Medium
  } else {
    Large
  }
}

///|
/// The theme for this frame, by the screen (docs/architecture.md: the layout follows the screen, never the hand): on a
/// touch device the phone's (its palette, its type a finger's size: Android's app, a tablet's too), on a computer the
/// web's. Laid out Small the phone's on a computer too, as its pages are the phone's, which carry its palette in places
/// (sfapp messages.mbt `ink`) until they and the web's are one (the way there 4): call at the top of a view.
pub fn begin(c : @ui.Ctx) -> Theme {
  let dark = dark_set.val.unwrap_or(false)
  let narrow = touch_system() || layout(c.width) is Small
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
/// A list card's corner: concentric round its rows (row_corner, list_pad in), as Android works it out (Parts.kt:640
/// LIST_CARD_CORNER = concentricOut(LIST_ROW_CORNER 18, LIST_PAD 8)); its rows take theirs from it (radius=Inner).
pub let list_card_radius : @ui.Radius = surface(list_pad, row_corner).radius()

///|
/// A drive's card (its corner 16, DriveScreen.kt) and a row's ground at its ends: concentric in it, list_pad in.
pub let drive_card_corner : Double = card_corner

///|
pub let drive_row_end_radius : @ui.Radius = rounded(inner_corner(drive_card_corner, list_pad))

///|
/// A card with a Seg (rounded 10) in its top corners: concentric with it (Usage.kt:204 concentricOut(10, CARD_PAD)):
/// worked out as Android does, no step of the scale.
pub let seg_card_radius : @ui.Radius = surface(card_pad, 10.0).radius()

///|
/// The usage page's days (Usage.kt Days): the plot 150 high (PLOT), a bar 16 wide at most (BAR), how far a line of the
/// scale's words stand over it (their line, Xs3's 14, and 2), and a part's corner (4; 2 with many days: Base, Sm).
pub let usage_plot : Double = 150.0

///|
pub let usage_plot_h : @ui.Len = Fixed(usage_plot)

///|
pub let usage_bar_max : @ui.Len = Fixed(16.0)

///|
pub let usage_tick_rise : Double = 16.0

///|
pub let usage_part_r : Double = 4.0

///|
pub let usage_part_r_many : Double = 2.0

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
/// A bar's round button (Parts.kt NavButton): 34 across.
pub let nav_button_side : @ui.Len = Fixed(34.0)

///|
/// A hairline across (0.5: a panel's rule over its foot).
pub let hairline : @ui.Len = Fixed(0.5)

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
    // on a phone the greys Android's (Theme.kt C.muted, C.subtle: the narrow palette's), not mbui's own narrow theme's
    // lighter ones: what a style's Muted and Subtle say there
    muted: if t.narrow { t.p.muted } else { base.muted },
    subtle: if t.narrow { t.p.subtle } else { base.subtle },
    // the panes' grounds the palette's (a touch device's sidebar a step under its beige page, what is chosen a step
    // under that): what a style's Sidebar and Selected say, not mbui's narrow theme's, which has the web's
    sidebar: t.p.sidebar,
    selected: t.p.selected,
    // a line of words that say none 1.4 of their size, as the web's root (`line-height: 1.4`) and Android's (Theme.kt
    // WebType: 1.4.em)
    text_line: 1.4,
    corner_ladder,
    // the app's own words with digits all one width, as the web's root (`font-variant-numeric: tabular-nums`): a
    // percentage, a time running, a count keep their width as they change; what people wrote keeps the font's own
    tabular: true,
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
/// The sign-in page's (SignIn.kt): its title 28, bold, on the font's own line (28.sp), off the scale between Xl3's
/// 22 and Xl4's 32; its sides 30 (padding(horizontal = 30.dp)), between S7's 28 and S8's 32.
pub let sign_in_title_size : @ui.TextSize = Exact(28.0, 39.2)

///|
pub let sign_in_side : @ui.Space = Exact(30.0)

///|
/// A picking row's line under its words (Controls.kt PickRow: 12.sp on 17.sp), between L4's 16 and L5's 18.
pub let pick_sub_line : @ui.Leading = Exact(17.0)

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
/// Marking a service's page (Preview.kt MarkMode, MarksOver, Note): its bar 30 high (a capsule), 添加到对话 (24 high)
/// and the dot's ring (13) in its ends where they are concentric with them (capsule_end_room: 3 in at its end, 8.5 at
/// its start), 添加到对话's icon and words 5 apart; the edit key's ground the accent's 14%, the ring's 22%, an open
/// mark's 8%; what floats over the page frosted thick (the surface at 94%; dark, surface2's); a pin's number 11; what is
/// said of a mark 26 high.
pub let mark_bar_h : @ui.Len = Fixed(mark_bar_side)

///|
let mark_bar_side : Double = 30.0

///|
pub let mark_bar_end : @ui.Space = capsule_end_room(mark_bar_side, mark_put_side)

///|
let mark_put_side : Double = 24.0

///|
pub let mark_bar_start : @ui.Space = capsule_end_room(mark_bar_side, mark_ring_side)

///|
pub let mark_put_gap : @ui.Space = space_5

///|
pub let mark_ring : @ui.Len = Fixed(mark_ring_side)

///|
let mark_ring_side : Double = 13.0

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
/// A sidebar's row, every sidebar's (Sidebar.css.ts navRow, navSession; SidebarList.css.ts item): the ladder's row
/// (row_corner), as a list card's rows and a menu's are. The web's nav corner (12, as a field's and an option's) is a
/// row's; on the ladder a row is 18, so a one-line row (32) is round at its ends as a menu's row is, and a chat's (54)
/// as a list card's.
pub let side_row_radius : @ui.Radius = row_radius

///|
/// A chat's row in the wide frame's sidebar (Sidebar.css.ts navSession: two lines, 20 and 18, 2 apart, 7 above and
/// under).
pub let side_row_h : @ui.Len = Fixed(54.0)

///|
/// A person's picture after the first at a sidebar row's end (RowPicture.css.ts: 16 across, 3 over the one before):
/// the room it takes.
pub let side_face_step : @ui.Len = Fixed(13.0)

///|
/// The same at a finger's row's end (mobile/Home.tsx RowAside size 18): 15 the room after the first, the starter's ring
/// 22 across (2 past the face's ground).
pub let touch_face_step : @ui.Len = Fixed(15.0)

///|
pub let touch_face_ring : @ui.Len = Fixed(22.0)

///|
/// The dot before a chat that wants the viewer in 待处理's panel (Attention.css.ts dot): 7 across.
pub let attention_dot : @ui.Len = Fixed(7.0)

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

///|
/// A choice's line on a card (Parts.kt PickLine): 11 over and under (as files_gap), rounded 10 (as custom_field_r),
/// its check in a room 18 wide at its end.
pub let pick_line_y : @ui.Space = files_gap

///|
pub let pick_line_r : @ui.Radius = custom_field_r

///|
pub let check_room_w : @ui.Len = Fixed(18.0)

///|
/// A person's initial on their colour (Parts.kt Avatar: Color.White), on every theme.
pub let face_ink : Int64 = 0xFFFFFFFFL

///|
/// A sheet's grabber (Sheet.kt SheetGrab): 38 × 5, round at its ends (its 3 capped at half its height, as every
/// renderer draws it; its colour the palette's line, said where it is drawn).
// kept across runs: a value (no field of it changes)
pub let sheet_grabber : @ui.Style = @ui.css("w=Fixed(38.0) h=Fixed(5.0) radius=Full")

///|
/// A tip's widest (the web's parts.css.ts tooltip: 300).
pub let tip_max : @ui.Len = Fixed(300.0)

///|
/// A login card's on a desktop's width (the web's MachineLogins.css.ts card): 360 at least where there is the room
/// (min(100%, 360px)), and its corner its padding and its × pill's half (8 + 12: the web's card's 20, as a
/// visualization's).
pub let login_card_least : Double = 360.0

///|
pub let login_card_corner : @ui.Radius = rounded(card_corner)

///|
/// A file's card in a message on a desktop's width (the web's Chat.css.ts fileCard): its sheet (30 by 36) 7 in from its
/// side, as the sheet's own 9.75 less the 2.75 it is drawn in (FILE_CARD_PAD); its corner the sheet's room and its own
/// 3.25 (MESSAGE_FILE_CORNER, 13), a message's pictures' too.
pub let file_sheet_in : @ui.Space = files_row_end

///|
pub let file_sheet_w : @ui.Len = Fixed(30.0)

///|
pub let file_sheet_h : @ui.Len = Fixed(36.0)

///|
/// A file card's own button (Chat.css.ts fileCardRemove: 22 round).
pub let file_card_button : @ui.Len = Fixed(22.0)

///|
/// A name over a message at its widest (Chat.css.ts msgHead msgName: 240).
pub let name_max : @ui.Len = Fixed(240.0)

///|
/// A small square button beside a line (the web's activityStop, a file card's remove: 22).
pub let small_button : @ui.Len = Fixed(22.0)

///|
/// The pill offering to quote what is picked (the web's Chat.css.ts quotePop: 26 high).
pub let quote_pop_h : @ui.Len = Fixed(26.0)

///|
/// A page's bar in the wide frame (the web's sidebar.css.ts pageBar: 45 high).
pub let wide_bar_h_size : @ui.Len = Fixed(wide_bar_h)

///|
pub let wide_bar_h : Double = 45.0

///|
/// A page's bar in a panel of the tape (laid out Medium, round by the ladder's pane corner): what stands in the
/// panel's top corners (its buttons, 32 across, capsules and circles) as far from its top and side as makes them
/// concentric with it; its bar as much taller over them (`tape_bar_over`), as much in at its end (`tape_bar_end`).
pub let tape_bar_end : Double = capsule_in(pane_corner, 32.0)

///|
pub let tape_bar_over : Double = tape_bar_end - (wide_bar_h - hairline_h - 32.0) / 2.0

///|
pub let tape_bar_over_room : @ui.Space = room(tape_bar_over)

///|
/// A bar's line under it (its pb: SPx).
let hairline_h : Double = 1.0

///|
/// A card over what the pointer rests on (the web's Hover.css.ts card: 320 wide; a tile's 220 at least), and an
/// agent's in it (AgentCard.css.ts: 288).
pub let hover_card_w : @ui.Len = Fixed(320.0)

///|
pub let hover_tile_least : @ui.Len = Fixed(220.0)

///|
pub let agent_card_w : @ui.Len = Fixed(288.0)

///|
/// parts.tsx's measures off the scale (parts.css.ts, own.css.ts, styles/spinner.css.ts): a switch (36 by 22, its thumb
/// 2 in; small 26 by 16), a pill (22 high, 9 in), a status dot's ring (1.5), a section's note (3 under its title, 52em
/// of its 12 at most), the first one (480 at most, its line 34em of its 13), a spinner (14; in a line of small text 12).
pub let switch_w : Double = 36.0

///|
pub let switch_h : Double = 22.0

///|
pub let switch_small_w : Double = 26.0

///|
pub let switch_small_h : Double = 16.0

///|
pub let switch_in : Double = 2.0

///|
pub let pill_h : Double = 22.0

///|
pub let pill_in : Double = 9.0

///|
pub let status_ring : Double = 1.5

///|
pub let section_note_gap : Double = 3.0

///|
pub let section_note_most : @ui.Len = Fixed(624.0)

///|
pub let first_most : @ui.Len = Fixed(480.0)

///|
pub let first_lead_most : @ui.Len = Fixed(442.0)

///|
pub let spinner_size : Double = 14.0

///|
pub let spinner_inline : Double = 12.0

///|
/// A dialog's widths (parts.css.ts dialog 520, dialogWide 640), how far short of the window's it stays at most (32),
/// and its close button (32 round).
pub let dialog_w : Double = 520.0

///|
pub let dialog_wide_w : Double = 640.0

///|
pub let dialog_margin : Double = 32.0

///|
pub let dialog_close : Double = 32.0

///|
/// A dialog's corner (DIALOG_PAD 24 and a pill's half height 18) and shadow (0 24px 64px: a blur's deviation half its
/// CSS radius).
pub let dialog_r : Double = pane_corner

///|
pub let dialog_shadow : Double = 32.0

///|
pub let dialog_shadow_y : Double = 24.0

///|
/// A select (parts.css.ts select: 200 wide by default; its chevron 14), choices 8 apart; a confirm (dialogAlert, 420
/// wide); a small panel's icon button's icon (16); a chooser's chevron (12); a copy's check (1.6 s).
pub let select_w : Double = 200.0

///|
pub let select_chevron : Double = 14.0

///|
pub let choice_gap : Double = 8.0

///|
pub let confirm_w : Double = 420.0

///|
pub let panel_icon_size : Double = 16.0

///|
pub let chooser_chevron : Double = 12.0

///|
pub let command_copied_ms : Double = 1600.0

///|
/// A menu's item at least (controls.css.ts menuItem: 34 high): 32, a capsule its panel's padding in from its corner,
/// concentric with it (capsule_in(r_menu, 32) = panel_pad).
pub let menu_row_min : Double = 32.0

///|
/// Over and under a menu's item's line of words (20): as high as menu_row_min.
pub let menu_row_over : Double = 6.0

///|
/// Nothing under it, no ring round it.
pub let no_ground : Int64 = 0L

///|
pub let no_ring : Double = 0.0

///|
/// A length off the scale, as a style's room (padding, margins: below 0 for a margin): align.mbt's.
fn room(x : Double) -> @ui.Space {
  Exact(x)
}

///|
/// A corner off the scale, as a style's: align.mbt's.
fn rounded(x : Double) -> @ui.Radius {
  Exact(x)
}

///|
/// The waiting shapes (waiting.css.ts): a row 66 high, 22 in at its start, its title 13 and line 10 high 10 apart, its
/// picture 22; dense 10 in, the bars 0.6 as long, 10 and 8 high, 7 apart; a message's bubble 18 round, 70% of the
/// width at most.
pub let wait_row_h : Double = 66.0

///|
pub let wait_row_in : Double = 22.0

///|
pub let wait_row_gap : Double = 10.0

///|
pub let wait_title_h : Double = 13.0

///|
pub let wait_line_h : Double = 10.0

///|
pub let wait_picture : Double = 22.0

///|
pub let wait_dense_in : Double = 10.0

///|
pub let wait_dense_share : Double = 0.6

///|
pub let wait_title_dense : Double = 10.0

///|
pub let wait_line_dense : Double = 8.0

///|
pub let wait_dense_gap : Double = 7.0

///|
pub let wait_bubble_r : Double = 18.0

///|
pub let wait_bubble_share : Double = 0.7

///|
/// A toast (toast.css.ts): 9 in over and under its words, 20 round, 560 wide at most, 24 over the window's foot, a
/// floating shadow (0 8px 24px), coming in from 8 below.
pub let toast_py : Double = 9.0

///|
pub let toast_r : Double = 20.0

///|
pub let toast_max : Double = 560.0

///|
pub let toast_bottom : Double = 24.0

///|
pub let toast_shadow : Double = 12.0

///|
pub let toast_shadow_y : Double = 8.0

///|
pub let toast_rise : Double = 8.0


///|
/// A column's edge (parts.css.ts resizeHandle, own.css.ts): a strip 7 wide, 4 of it past the column's edge; its bar 5
/// wide, 24 high and 48 on the strip; its line 8 short of the strip's ends, in 40 steps of its fade; dragged once 3
/// from where it went down.
pub let handle_w : Double = 7.0

///|
pub let handle_out : Double = 4.0

///|
pub let edge_bar_w : Double = 5.0

///|
pub let edge_line_steps : Int = 40

///|
pub let handle_slop : Double = 3.0

///|
/// A tip that follows the pointer along an edge (usePointerTip): 300 ms after the pointer comes, 14 beside it.
pub let edge_tip_ms : Double = 300.0

///|
pub let edge_tip_gap : Double = 14.0

// ---------------------------------------------------------------------------
// The desktop's sidebar and rail (sfdesk: ember web/src/Rail.css.ts, ChatMark.css.ts, styles/shell.css.ts)

///|
/// A chat's marks' colours, bright in both themes (ChatMark.css.ts: #3b82f6 done and waiting on the viewer, #e5484d to
/// be seen now and its halo at 25%, #f2b01e at work).
pub let mark_blue : @ui.Color = Exact(0x3B82F6FFL)

///|
pub let mark_red : @ui.Color = Exact(0xE5484DFFL)

///|
pub let mark_halo : @ui.Color = A(mark_red, O25)

///|
pub let mark_yellow : Int64 = 0xF2B01EFFL

///|
/// The rail's places 9 from its edges open, in its 56's middle (Rail.css.ts rail: 9 under the last, its 38s 9 in).
pub let rail_in : @ui.Space = room(9.0)

///|
/// The same as a panel of the tape (laid out Medium, round by the ladder's pane corner): the places in its corners (a
/// 38 to press, its ground 30 round in its middle) as far in as makes their grounds concentric with it.
pub let rail_in_tape : Double = capsule_in(pane_corner, rail_ground_side) - (38.0 - rail_ground_side) / 2.0

///|
pub let rail_in_tape_room : @ui.Space = room(rail_in_tape)

///|
/// The composer's padding as a style's (composer_pad).
pub let composer_pad_room : @ui.Space = room(composer_pad)

///|
/// Where a dialog's buttons stand in its foot corner (the theme's button: a capsule): as far from its foot and its side
/// as makes the last concentric with its corner (dialog_r), the row reaching past its sides' room `pad` to there.
pub fn dialog_corner_foot(pad : Double) -> @ui.Style {
  let at = capsule_in(dialog_r, button_height())
  @ui.style(pb=room(at), mr=room(at - pad))
}

///|
/// A place's ground in the rail (a place's, a workspace's): 30 round, so where it stands in a panel's corner it is
/// concentric with it (Rail.css.ts item, workspaceItem: 9 round, the web's).
pub let rail_ground_side : Double = 30.0

///|
pub let rail_corner : @ui.Radius = Full

///|
/// What sits in a small panel's corner (--panel-in: a menu's rows, a popover's), concentric with the panel's.
pub let panel_in : @ui.Radius = rounded(small_panel_inner(r_menu))

///|
/// The `@` menu over the desktop's composer (ChatRef.css.ts refMenu: a small panel, padded panel_pad) and its rows'
/// corner (refItem: concentric with it), its rows at their lowest (38: round by the ladder's next step, not capsules).
pub let ref_menu_corner : @ui.Radius = rounded(r_menu)

///|
pub let ref_item_corner : @ui.Radius = panel_in

///|
pub let ref_item_min_h : @ui.Len = Fixed(38.0)


///|
/// The closed bar's corner: round with the places' grounds 6 in (around: a capsule as wide as it).
pub let closed_bar_corner : @ui.Radius = rounded(around(6.0, rail_ground_side / 2.0))

///|
/// The corner of the tape's panels (laid out Medium: the sidebar's, the page's, the side panel's, all alike): the
/// frame's own. What stands in a panel's corner follows it (`InnerOr`: the composer's capsule at the page's foot, and
/// its buttons in its corners, concentric), so it is chosen for the panels alone and changes without them.
pub let page_panel_corner : @ui.Radius = rounded(pane_corner)


///|
/// The sidebar's edge's look 3 in its strip (Rail.css.ts edge: its line 6 in, its bar 4 in, the library's 7 wide).
pub let edge_in : @ui.Space = room(3.0)

///|
/// A chat's row in the sidebar 7 in from its top and foot (Sidebar.css.ts navSession: padding 7 10).
pub let row_in : @ui.Space = room(7.0)

///|
/// An agent's mark (the web's ui.css.ts agentMark): its corner .3 of its side, a 28 one's 8.4 (an agent's card).
pub let agent_mark_28_corner : @ui.Radius = rounded(28.0 * 0.3)


///|
/// (a 16 one's, 4.8: a line of an agent's history's details)
pub let agent_mark_16_corner : @ui.Radius = rounded(16.0 * 0.3)

///|
/// A chat's jobs (the web's Jobs.css.ts): a job's action 26 high, the popover's foot's rows 38.
pub let job_action_h : @ui.Len = Fixed(26.0)

///|
pub let jobs_row_h : @ui.Len = Fixed(38.0)


///|
/// A tab of a chat's side panel (the web's ChatPage.css.ts sideTab: 30 high).
pub let side_tab_h : @ui.Len = Fixed(side_tab_side)

///|
pub let side_tab_side : Double = 30.0

///|
/// A device's code read aloud, large (Security.css.ts bigCode): the web's display size, 28, its line 1.3 of it, off
/// the scale; its letters 6 apart.
pub let code_big_size : @ui.TextSize = Exact(28.0, 36.4)

///|
pub let code_big_tracking : @ui.Tracking = Exact(6.0)

///|
/// A chat's bar (the web's ChatPage.css.ts): its station's tag 160 wide at most, 7 in; an agent's station's part 140 at
/// most, in by .19 of its 20 tile and 1.
pub let chat_station_most : @ui.Len = Fixed(160.0)

///|
pub let chat_station_in : @ui.Space = room(7.0)

///|
pub let agent_station_most : @ui.Len = Fixed(140.0)

///|
pub let agent_station_in : @ui.Space = room(20.0 * 0.19 + 1.0)

///|
/// A person in a chat's stack of people (the web's later.css.ts peopleStack): 16 ringed 1.5.
pub let person_ringed : @ui.Len = Fixed(19.0)

///|
/// The people a day's usage is split by, in the order the core's usage view ranks them (the web's Usage.css.ts, the
/// phone's Usage.kt): four of their own in light and in dark, the first still.fail's accent.
// kept across runs: a table, never written
let usage_light : Array[Int64] = [0xEF6A3CFFL, 0x2A78D6FFL, 0x1BAF7AFFL, 0x4A3AA7FFL]

///|
// kept across runs: a table, never written
let usage_dark : Array[Int64] = [0xE0602FFFL, 0x3987E5FFL, 0x199E70FFL, 0x9085E9FFL]

///|
/// The `i`th person's colour in the theme shown.
pub fn usage_series(i : Int) -> Int64 {
  (if theme().dark { usage_dark } else { usage_light })[i % 4]
}

///|
/// An agent's history's steps (the web's History.css.ts, ToolStep.css.ts): the turn's rail 9.5 in, how much of a wait
/// has gone a bar 3 high; a diff's line 22 in, its mark 9.
pub let history_rail_in : @ui.Space = room(9.5)

///|
pub let wait_bar_h : @ui.Len = Fixed(3.0)

///|
pub let diff_line_in : @ui.Space = room(22.0)

///|
pub let diff_mark_in : @ui.Space = room(9.0)

///|
/// A message's picture out in the margin before its words (align.ts columns.avatar: 29), 3 down (Chat.css.ts msgRow >
/// msgAvatar).
pub let message_avatar_out : @ui.Space = room(-29.0)

///|
pub let message_avatar_down : @ui.Space = room(3.0)

///|
/// A message's head in past its picture where the picture is over its start (Chat.css.ts inlineHeads: 25).
pub let message_head_in : @ui.Space = room(25.0)

///|
/// An agent's activity line out in the margin with the messages' pictures (align.ts columns.activity: its 24 picture
/// and the 11 beside it, 35 before the words).
pub let activity_out : @ui.Space = room(-35.0)

///|
/// Narrow (columns.activityNarrow): 9 out into the list's 16.
pub let activity_out_narrow : @ui.Space = room(-9.0)

///|
/// What says a chat is archived or its station down, over its composer (Chat.css.ts offlineNotice: 760 at most, 64
/// less than the pane).
pub let notice_w : @ui.Len = Fixed(760.0)

///|
/// 奏 with none left: its column (DecisionsIdle.css.ts column: 560 at most); a card's way to its chat (Decisions.css.ts
/// elsewhere: 38 high).
pub let idle_column_w : @ui.Len = Fixed(560.0)

///|
pub let elsewhere_h : @ui.Len = Fixed(38.0)

///|
/// A service's address in its bar beside the chat (Preview.css.ts previewAddress: 30 high).
pub let preview_address_h : @ui.Len = Fixed(30.0)

///|
/// A message's video (Chat.css.ts msgVideo, msgVideoPlay, msgVideoName): black under its still, black at 65% under its
/// play mark and its name, which are white.
pub let video_ground : @ui.Color = Data(0x000000FFL)

///|
pub let video_shade : @ui.Color = Data(0x000000A6L)

///|
pub let white_ink : @ui.Color = Data(0xFFFFFFFFL)

///|
pub let white : Int64 = 0xFFFFFFFFL
