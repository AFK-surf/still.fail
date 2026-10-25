// The Mac's text for still.fail's screens (screens/text-mac.textrec, scripts/screens.sh rec), embedded (moon.pkg's
// pre-build) for their tests (src/sfapp/screens_wbtest.mbt): a package of its own that only sfapp's wbtest imports, so
// an app's build neither embeds nor needs it.

///|
/// The Mac's text for the screens, a section a screen (scripts/screens.py)
pub fn text_mac() -> String {
  text_mac_kept
}
