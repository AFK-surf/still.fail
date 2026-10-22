// The system's bars over the app's view (the status bar, the navigation bar, a cutout), as the host says them on
// @hostapi.system_channel (`bars`: over another app, or edge to edge): kept here as each message comes, before the
// app's own handler of the channel is given it, so a view pads by them (system_bars) without reading the message
// itself. 0 where the host lays the view out inside them, and in a Tester until a test posts them.

///|
/// How far the system bars reach in over the view from each edge, in points.
pub(all) struct SystemBars {
  top : Double
  bottom : Double
  left : Double
  right : Double
} derive(Eq, Show)

///|
/// The bars as the host last said them (none: all 0). Put back by each Tester (messages_reset).
let system_bars_now : Ref[SystemBars] = Ref::new({ top: 0.0, bottom: 0.0, left: 0.0, right: 0.0 })

///|
/// How far the system bars reach in over the view now (`top`: the status bar's, `bottom`: the navigation bar's, or
/// the keyboard's top under it), as the host last said them.
pub fn system_bars() -> SystemBars {
  system_bars_now.val
}

///|
/// A message on the system's channel, as it comes: the bars it says kept.
fn system_took(json : String) -> Unit {
  for said in @hostapi.system_said(json) {
    match said {
      Bars(top~, bottom~, left~, right~) => system_bars_now.val = { top, bottom, left, right }
      _ => ()
    }
  }
}
