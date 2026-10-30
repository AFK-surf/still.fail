// Glass, as it is said (what is drawn of it, its capture and its run, is the host's: ui's glass.mbt).


///|
/// How a glass box looks. `blur` is CSS blur()'s deviation, in logical px;
/// `tint` is laid over the frost (its alpha how much); `saturation` as CSS
/// saturate(); `solid` is the ground drawn instead where the system asks for
/// less transparency (or MBUI_GLASS=solid).
pub(all) struct Glass {
  blur : Double
  tint : Int64
  saturation : Double
  solid : Int64
  // the rim, frosted: a hairline inside the edge, light along the top and
  // left, less along the foot and right (white's alpha each; Bar.kt rim)
  rim_edge : Double
  rim_lit : Double
  rim_back : Double
  // liquid
  liquid : Bool
  rim : Double
  bezel : Double
  refraction : Double
  chroma : Double
  merge : Double
  adaptive : Bool
  // frosted: frosts what the glass before it frosts (its capture), not what
  // has been drawn since
  shares_capture : Bool
} derive(Eq, Show, Debug)

///|
/// Frosted glass: what is under it blurred by `blur` (CSS px), `tint` over it.
pub fn Glass::frosted(
  blur~ : Double,
  tint~ : Int64,
  solid~ : Int64,
  saturation? : Double = 1.0,
  rim_edge? : Double = 0.0,
  rim_lit? : Double = 0.0,
  rim_back? : Double = 0.0,
  shares_capture? : Bool = false,
) -> Glass {
  {
    blur,
    tint,
    saturation,
    solid,
    rim_edge,
    rim_lit,
    rim_back,
    liquid: false,
    rim: 0.0,
    bezel: 0.0,
    refraction: 0.0,
    chroma: 0.0,
    merge: 0.0,
    adaptive: false,
    shares_capture,
  }
}

///|
/// The same glass frosting what the glass painted before it in this frame frosts (its capture, at that glass's
/// blur), whatever has been drawn since, over that glass too: a ball over a bar, both of the page under them.
pub fn Glass::sharing(self : Glass) -> Glass {
  { ..self, shares_capture: true }
}

///|
/// Liquid glass: nearly clear, what is under it bent along its rim (a bezel
/// `bezel` wide moving it by up to `refraction` px, the colours split by
/// `chroma`), a light rim, text in it inked by what is under it
/// (`adaptive`); shapes of one `glass_group` within `merge` of each other
/// flow into one.
pub fn Glass::liquid(
  blur? : Double = 1.0,
  tint? : Int64 = 0xFFFFFF1AL,
  solid? : Int64 = 0xECECF0FFL,
  saturation? : Double = 1.3,
  rim? : Double = 0.55,
  bezel? : Double = 14.0,
  refraction? : Double = 9.0,
  chroma? : Double = 0.18,
  merge? : Double = 16.0,
  adaptive? : Bool = true,
) -> Glass {
  {
    blur,
    tint,
    saturation,
    solid,
    rim_edge: 0.0,
    rim_lit: 0.0,
    rim_back: 0.0,
    liquid: true,
    rim,
    bezel,
    refraction,
    chroma,
    merge,
    adaptive,
    shares_capture: false,
  }
}

