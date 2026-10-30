// 外观 › 字体's state: the three places, the one in view, a place's face chosen (kept as the device's: `prefs.set
// {fonts}`, fetched whole by the app: src/sfapp/faces.mbt). The page is sfdesk's (font_setting.mbt), one for every
// frame.

///|
// kept across runs: a table, never written
pub let font_places : Array[String] = ["ui", "text", "code"]

///|
/// The place in view on the fonts page (its switch).
pub let fonts_at : @signals.Signal[Int] = @signals.signal(0, same=fn(a, b) { a == b })

///|
/// A place's face chosen (None: back to the app's own), kept as the device's.
pub fn set_font(core : Core, place : String, id : String?) -> Unit {
  let v = match id {
    Some(s) => s.to_json()
    None => Json::null()
  }
  let fonts : Map[String, Json] = {}
  fonts[place] = v
  (core.call)("prefs.set", Json::object({ "fonts": Json::object(fonts) }), fn(_) {  })
}
