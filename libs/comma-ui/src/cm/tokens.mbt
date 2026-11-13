// Comma's design system for mbui (AFK-surf/Cue clients/packages/ui, Figma "Comma Design System"): its tokens as the
// window's tree reads them. The numbers are tokens_made.mbt's, written by scripts/cm-tokens.mjs from Comma's own token
// modules, never by hand; this file says which of them a node reads now (light or dark) and what mbui's theme is in
// Comma's look, for what of mbui draws by the theme (a field's caret, the focus a Tester holds).
//
// Left out for now (the sample's): Comma's theme studio (the greys tinted by a hue the person picks, oklch), the
// shadows' every layer (one cast, the largest: tokens_made's), Central Icons.

///|
/// Light or dark as the app says (None: as mbui's window is, its theme's `dark`).
// kept across runs: said by the app as it starts and as the person changes it
let dark_said : @signals.Signal[Bool?] = @signals.signal(None)

///|
/// Light or dark from now on (None: as the window is).
pub fn set_dark(dark : Bool?) -> Unit {
  dark_said.set(dark)
}

///|
/// Whether what is drawn now is drawn dark: the app's say, else the window's.
pub fn is_dark() -> Bool {
  match dark_said.get() {
    Some(d) => d
    None => @ui.tree_theme().dark
  }
}

///|
/// Comma's colours as a node is drawn now (light or dark: is_dark), read where they are drawn so they follow.
pub fn colors() -> Colors {
  if is_dark() {
    dark
  } else {
    light
  }
}

///|
/// The focus ring's width and how far out of what it rings it lies (Comma's 4 px ring, round the box's own edge).
pub let ring_w : Double = focus_brand.0

///|
/// mbui's theme in Comma's look: what of mbui is drawn by the theme (a field's words and caret, the ring a Tester
/// looks for) drawn in Comma's colours, sizes and corners. Comma has no corner ladder: none held.
pub fn ui_theme() -> @ui.Theme {
  let d = is_dark()
  let c = if d { dark } else { light }
  let base = if d { @ui.Theme::dark() } else { @ui.Theme::light() }
  {
    ..base,
    bg: c.bg_primary,
    surface: c.bg_popup_primary,
    raised: c.bg_popup_primary,
    card: c.main_panel_item_bg,
    fg: c.text_primary,
    muted: c.text_tertiary,
    subtle: c.text_placeholder,
    faint: c.bg_secondary,
    border: c.border_primary,
    line: c.border_secondary,
    field_hover: c.border_menu_primary,
    accent: c.bg_brand_solid,
    accent_text: c.text_brand_secondary,
    accent_bg: c.bg_brand_primary,
    on_accent: c.fg_white,
    primary: c.button_primary_bg,
    on_primary: c.button_primary_fg,
    positive: c.fg_success_primary,
    danger: c.fg_error_primary,
    danger_bg: c.bg_error_primary,
    on_danger: c.fg_white,
    hover: c.bg_secondary_hover,
    selected: c.bg_active,
    focus: focus_brand.1,
    scrim: c.bg_overlay,
    shadow: (if d { shadow_dark_md } else { shadow_md }).2,
    thumb: c.fg_white,
    link: c.text_brand_secondary,
    sidebar: c.bg_window,
    list: c.bg_primary,
    radius: radius_md,
    radius_lg: radius_xl,
    radius_dialog: radius_2xl,
    font: type_small.size,
    font_sm: type_mini.size,
    font_title: type_large.size,
    font_heading: type_title2.size,
    control_h: 40.0,
    focus_w: ring_w,
    focus_gap: 0.0,
    corner_ladder: [],
    corner_fit: None,
    lit_apart: 0.0,
    lit_reach: 0.0,
  }
}

///|
/// Words in a role of Comma's type (`TypeRole`: its size, line and letters' spacing) at `weight` (Inter's: 450 its
/// regular, weight_regular), on one line unless `wrap`.
pub fn words_in(role : TypeRole, weight? : Int = weight_regular, wrap? : Bool = false) -> @view.WordsLook {
  {
    size: role.size,
    weight,
    line: role.line,
    wrap,
    tracking: Ems(role.tracking),
    balance: false,
    max_lines: 0,
  }
}

///|
/// A CSS easing of Comma's (tokens_made's `ease_*`) as a curve.
pub fn curve(e : (Double, Double, Double, Double)) -> (Double) -> Double {
  @motion.cubic_bezier(e.0, e.1, e.2, e.3)
}

///|
/// `c` at `share` of its opacity.
pub fn alpha(c : Int64, share : Double) -> Int64 {
  let a = (c & 0xFFL).to_double() * share
  (c & 0xFFFFFF00L) | a.round().to_int64()
}

///|
/// `share` of `a` and the rest of `b`, as each is seen over anything (their colours weighed by how opaque each is): a
/// ground going from a see-through colour to a solid one passes through no darker one.
pub fn mix(a : Int64, share : Double, b : Int64) -> Int64 {
  let aa = (a & 0xFFL).to_double() / 255.0
  let ba = (b & 0xFFL).to_double() / 255.0
  let opacity = aa * share + ba * (1.0 - share)
  if opacity <= 0.0 {
    return 0L
  }
  let ch = fn(shift : Int) -> Int64 {
    let x = ((a >> shift) & 0xFFL).to_double() * aa
    let y = ((b >> shift) & 0xFFL).to_double() * ba
    ((x * share + y * (1.0 - share)) / opacity).round().to_int64().max(0L).min(255L)
  }
  (ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | (opacity * 255.0).round().to_int64()
}
