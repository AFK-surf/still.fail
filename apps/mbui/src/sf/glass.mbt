// still.fail's glass (Android ui/Glass.kt over Haze, web mobile/styles/pages.css.ts and ui/styles/glass.ts), as
// @ui.Glass for a box's `glass=`. Haze's blur radius is cssBlur(px) = (px - 0.5) / 0.57735 dp, which RenderEffect
// takes as a deviation of px dp: CSS blur(px)'s, what @ui.Glass's blur is. Each has its solid ground for where the
// system asks for less transparency: what the glass would be with nothing under it (the page's paper under its tint).

///|
/// A bar at the top of a page over the list running under it (Glass.kt glass, TopGlassBar; mGlass): the page's paper
/// at 70% over a 24px blur, no line along its foot: the frost alone sets it off (2026-10-24, asked).
pub fn glass_bar() -> @ui.Glass {
  let t = theme()
  @ui.Glass::frosted(blur=24.0, tint=alpha(t.p.bg, 0.7), solid=t.p.bg)
}

///|
/// The same glass as a band along the page's foot (Glass.kt glassFoot: a new chat's choices and composer stand on
/// it), no line.
pub fn glass_foot() -> @ui.Glass {
  glass_bar()
}

///|
/// A capsule floating over the list (Glass.kt floating; mFloating, the composer's): `--raised` at 72% over a 20px
/// blur; `tint` for glass of another colour. Its breath of shadow is the box's (shadow 2, black at 30%, 0.5 down),
/// drawn outside it only.
pub fn glass_floating(tint? : Int64) -> @ui.Glass {
  let t = theme()
  let ground = alpha(tint.unwrap_or(t.p.raised), 0.72)
  @ui.Glass::frosted(blur=20.0, tint=ground, solid=over(t.p.bg, ground))
}

///|
/// The bottom bar's glass (Bar.kt: the floating capsule's, `raised` 72% over a 20px blur), its rim lit: a hairline
/// inside its edge, light along its top and left, less along its foot and right (white at 0.35 / 0.8 / 0.45; in the
/// dark 0.14 / 0.3 / 0.16).
pub fn glass_bottom_bar() -> @ui.Glass {
  let t = theme()
  let ground = alpha(t.p.raised, 0.72)
  let (e, l, b) = if t.dark { (0.14, 0.3, 0.16) } else { (0.35, 0.8, 0.45) }
  @ui.Glass::frosted(
    blur=20.0,
    tint=ground,
    solid=over(t.p.bg, ground),
    rim_edge=e,
    rim_lit=l,
    rim_back=b,
  )
}

///|
/// The bar's ball over the place in view (Bar.kt): the bar's glass with white over it (42%; 12% in the dark), a 24px
/// blur, its rim brighter (0.5 / 0.95 / 0.55; dark 0.22 / 0.45 / 0.25).
pub fn glass_bar_ball() -> @ui.Glass {
  let t = theme()
  let ground = over(
    alpha(t.p.raised, 0.72),
    alpha(0xFFFFFFFFL, if t.dark { 0.12 } else { 0.42 }),
  )
  let (e, l, b) = if t.dark { (0.22, 0.45, 0.25) } else { (0.5, 0.95, 0.55) }
  @ui.Glass::frosted(
    blur=24.0,
    tint=ground,
    solid=over(t.p.bg, ground),
    rim_edge=e,
    rim_lit=l,
    rim_back=b,
  )
}

///|
/// The bar's ball held (the lens over the places, iOS 26's tab bar's): liquid glass, nearly clear, its rim bending
/// the places under it; a touch of the page's paper so it reads as glass in both themes.
pub fn glass_lens() -> @ui.Glass {
  let t = theme()
  @ui.Glass::liquid(
    blur=0.0,
    tint=alpha(t.p.raised, if t.dark { 0.04 } else { 0.08 }),
    solid=over(t.p.bg, alpha(t.p.raised, 0.72)),
    bezel=16.0,
    refraction=12.0,
    chroma=0.08,
    adaptive=false,
  )
}

///|
/// A control's knob held (a switch's, a segmented choice's thumb: iOS 26's): the bar's lens, its rim narrower and
/// bending less, as small as it is.
pub fn glass_knob() -> @ui.Glass {
  { ..glass_lens(), bezel: 7.0, refraction: 5.0 }
}

///|
/// The page's primary action in the bar's notch (Bar.kt: 令, a "+"): the accent at 86% over a 20px blur, its rim
/// 0.4 / 0.75 / 0.4.
pub fn glass_action() -> @ui.Glass {
  let t = theme()
  let ground = alpha(t.p.accent, 0.86)
  @ui.Glass::frosted(
    blur=20.0,
    tint=ground,
    solid=over(t.p.bg, ground),
    rim_edge=0.4,
    rim_lit=0.75,
    rim_back=0.4,
  )
}

///|
/// A sheet over the page (Sheet.kt): the surface at 90% over a 28px blur (the scrim is drawn under it, so it is in
/// what the glass frosts, as on the web). 90%, not the 80% it was: what is written on a sheet keeps 4.5:1 whatever
/// lies under it (the accent's words, the weakest ink a sheet's words are in, over the page at its darkest, black: the
/// tint alone carries them), a sheet as tall as what it holds lying over any part of the page.
pub fn glass_sheet() -> @ui.Glass {
  let t = theme()
  @ui.Glass::frosted(blur=28.0, tint=alpha(t.p.canvas, sheet_tint), solid=t.p.bg)
}

///|
/// How much of a sheet's glass is its surface's colour (glass_sheet).
let sheet_tint : Double = 0.9

///|
/// How far a sheet reaches on under the window's foot (sheet_look: its foot's corners out of sight).
let sheet_under : Double = 26.0

///|
/// still.fail's sheet (Sheet.kt) as mbui's sheet draws it (@kit.sheet's look): the sheet's glass over the page, the
/// scrim's black as far as it shows (`s.t`) under it, its top corners 26 round (26 more of it under the window's
/// foot), a shadow; `ground` (not 0) a solid ground in the glass's place. What it holds starts with its grabber.
pub fn sheet_look(ground? : Int64 = 0L) -> (@ui.Ctx, @kit.SheetState, () -> Unit) -> Unit {
  fn(c, s, body) {
    let t = theme()
    c.box(
      w=Fill(1.0),
      h=Px(s.h + sheet_under),
      radius=26.0,
      bg=ground,
      glass?=if ground != 0L {
        None
      } else {
        Some({ ..glass_sheet(), solid: over(over(t.p.bg, alpha(0x000000FFL, 0.28 * s.t)), alpha(t.p.card, 0.8)) })
      },
      shadow=sheet_raised.sigma,
      shadow_y=sheet_raised.dy,
      shadow_color=sheet_raised.color,
      clip=true,
      pb=sheet_under,
      body,
    )
    |> ignore
  }
}

///|
/// The scrim under a sheet at its fullest: black at 28% (Sheet.kt).
pub let sheet_scrim : Int64 = 0x00000047L
