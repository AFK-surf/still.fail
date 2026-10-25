// Shadows as Core Animation draws them (mbui's: a box's shape blurred, `shadow` its sigma, as CALayer's shadowRadius;
// `shadow_y` its offset down; `shadow_color` its colour and opacity).
//
// The original (still.fail's Android app) says most of its shadows as Compose's `shadow(elevation, ambientColor,
// spotColor)`. Said here as such a shadow, once each, from the light the platform casts them in (an ambient light of
// 3.9%, a key light of 19%, 500 over the window's top: the system's own values): a blur of 0.8 elevation, 0.6 of it
// down, black as strong as both lights together at its edge. What the original draws as a blur of its own (a bar's
// glass: a BlurMaskFilter of a CSS deviation) is said with that deviation as it is.

///|
/// A shadow: its blur (sigma), how far down, its colour.
pub(all) struct Raised {
  sigma : Double
  dy : Double
  color : Int64
}

///|
/// The original's `shadow(elevation)` (dp), its ambient and spot colours black at `ambient`, `spot` (1: Compose's
/// default, black).
pub fn raised(elevation : Double, ambient? : Double = 1.0, spot? : Double = 1.0) -> Raised {
  // at its edge: the ambient light's whole, half the key light's (its penumbra's middle); a blur's edge is half its
  // opacity
  let a = dmin(1.0, 2.0 * (ambient_light * ambient + key_light / 2.0 * spot))
  { sigma: blur_per_elevation * elevation, dy: fall_per_elevation * elevation, color: alpha(0x000000FFL, a) }
}

///|
/// The platform's lights (Android's ambient_shadow_alpha, spot_shadow_alpha), and how a shadow's blur and fall go with
/// its elevation.
let ambient_light : Double = 0.039

///|
let key_light : Double = 0.19

///|
let blur_per_elevation : Double = 0.8

///|
let fall_per_elevation : Double = 0.6

///|
/// A capsule floating over a page (Glass.kt floating, floatingStill: shadow(1, black at 30% both)).
pub let floating : Raised = raised(1.0, ambient=0.3, spot=0.3)

///|
/// A sheet's (Sheet.kt: shadow(24)), a menu's (Sheet.kt: shadow(18)).
pub let sheet_raised : Raised = raised(24.0)

///|
pub let menu_raised : Raised = raised(18.0)

///|
/// A bar of choices over what was picked (MessagePick.kt: shadow(8)); a capsule of a service's page (Preview.kt: 8).
pub let pick_raised : Raised = raised(8.0)

///|
/// A mark's pin (ImageMarks.kt, Preview.kt: shadow(3)).
pub let pin_raised : Raised = raised(3.0)

///|
/// A round button over a picture (FilePreview.kt: shadow(1)).
pub let button_raised : Raised = raised(1.0)

///|
/// A document's page in the viewer (FilePreview.kt: shadow(2)).
pub let page_raised : Raised = raised(2.0)

///|
/// The viewer's bars over a page (FilePreview.kt pageGlass: shadow(6), black at 12% both).
pub let viewer_bar_raised : Raised = raised(6.0, ambient=0.12, spot=0.12)

///|
/// A note said over a service's page (Preview.kt: shadow(6)), its strip (shadow(4), black at 12% both).
pub let bubble_raised : Raised = raised(6.0)

///|
pub let strip_raised : Raised = raised(4.0, ambient=0.12, spot=0.12)

///|
/// A station's update card (StationUpdate.kt: shadow(12), black at 8% both).
pub let update_raised : Raised = raised(12.0, ambient=0.08, spot=0.08)

///|
/// A shadow as a style says it (@ui.style's `shadow`).
pub fn Raised::cast(self : Raised) -> @ui.Shadow {
  Cast(self.sigma, self.dy, self.color)
}

///|
/// What a finger holds and moves along its row (a place on a bottom bar's card): lifted 6, black at 14% both.
pub let held_raised : Raised = raised(6.0, ambient=0.14, spot=0.14)
