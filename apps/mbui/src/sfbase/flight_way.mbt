// A send has one declared path, shared by old rows and retained nodes. Sampling it does not advance it: a node
// draws from its own frame's moment, and a legacy caller from the host's, on the same way and the same curves.

///|
pub struct FlightWay {
  priv way : @motion.Way
}

///|
pub fn FlightWay::new(value? : Double = 0.0) -> FlightWay {
  { way: @motion.Way::new(value) }
}

///|
pub fn FlightWay::animate(self : FlightWay, to : Double, spec : @motion.Spec, start_at? : Double) -> Unit {
  self.way.go(to, spec, at=start_at.unwrap_or_else(fn() { @ui.current().moment() }))
}

///|
pub fn FlightWay::get(self : FlightWay) -> Double {
  self.way.get()
}

///|
pub fn FlightWay::ends(self : FlightWay) -> Double {
  self.way.said()
  self.way.end()
}

///|
pub fn FlightWay::over(self : FlightWay) -> Bool {
  self.way.said()
  let c = @ui.current()
  let done = !self.way.goes_at(c.moment())
  if !done { c.shows_until(self.way.end()) }
  done
}

///|
/// The same flight at the moment node `v` is drawn, following the way and the clock only until it lands.
pub fn FlightWay::shown(self : FlightWay, v : @view.View) -> Double {
  self.way.said()
  if v.drawn_past(self.way.end()) {
    self.way.value_at(self.way.end())
  } else {
    self.way.value_at(v.drawn_at())
  }
}

///|
/// When this draft's words have left the field far enough for its hint and caret to come back. A negative moment
/// means their row has not been placed yet. The deadline follows the same declared path as the flight, not frames.
pub fn flight_hint_due(draft : String) -> Double? {
  guard flight_of(draft) is Some(f) &&
    (f.text != "" || f.files.iter().any(fn(ff) { ff.key.has_prefix(quote_prefix) })) else { return None }
  let end = f.way.ends()
  guard f.placed else { return Some(-1.0) }
  let mut low = f.set_out
  let mut high = end
  // Invert the shared monotonic flight curve once when its path is declared. No second set of easing constants.
  for _ in 0..<40 {
    let mid = (low + high) / 2.0
    if flight_up(f.way.way.value_at(mid), f.desk || f.carried) < 0.5 { low = mid } else { high = mid }
  }
  Some(high)
}
