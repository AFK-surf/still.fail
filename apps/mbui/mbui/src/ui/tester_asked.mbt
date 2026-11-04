// A host draws a frame only where the app asked for one (on_frame's end: h_request_frame, h_request_frame_on,
// h_wake_after); a Tester draws where the test says, and run_for draws at each motion's end whether it was asked
// for or not (next_due). What moves on a Tester while the app asks for no frame stands still on a device until
// something else asks: the picture a test sees is not the one a person sees.

///|
/// Every display frame for `ms` from now drawn, as a host whose display is always on draws them (Tester::run_as_host);
/// the moments where what is drawn changed though the frame before asked for no frame by then (none, a wake later, a
/// motion's end it never said): there a host shows the frame before, still, until something else asks for one.
pub fn Tester::unasked_changes(self : Tester, ms : Double) -> Array[Double] {
  let was = host_record.val
  self.record_host()
  self.run_as_host(ms)
  let frames = self.host_frames()
  host_record.val = was
  match was {
    Some(r) => r.append(frames)
    None => ()
  }
  frames.filter(fn(f) { !f.asked && f.changed }).map(fn(f) { f.at })
}
