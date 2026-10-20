// The system's settings the app is drawn by, kept with its frames as its input is (MBUI_DRAW_LOG=1, a Tester's tape):
// motion reduced, transparency reduced, the system dark, the window's buttons in the app's top row. Read as each frame
// begins; an ENV line before the first frame's DRAWHASH, and again before the frame where one of them changed. A
// Tester made with the run (Tester::new's `run`) draws its first frame by those it began with; its `replay_frames`
// sets the later ones again at their place (its fake host's: Tester::set_reduce_motion,
// set_reduce_transparency, set_dark, set_window_inset), so a run is drawn again by the settings it was drawn by.
//
//   ENV {"motion":0|1,"glass":0|1,"dark":0|1,"inset":0|1}    motion reduced, transparency reduced (glass solid), dark,
//                                                            the window's inset

///|
/// The settings last kept on the tape ("" none yet).
let env_kept : Ref[String] = Ref::new("")

///|
/// The system's settings as this frame begins, kept on the tape when they are not as last kept.
fn env_at_frame() -> Unit {
  if !taping() {
    return
  }
  let m : Map[String, Json] = {
    "motion": Json::number(if reduced_motion() { 1.0 } else { 0.0 }),
    "glass": Json::number(if h_reduce_transparency() { 1.0 } else { 0.0 }),
    "dark": Json::number(if system_dark() { 1.0 } else { 0.0 }),
    "inset": Json::number(if window_inset() { 1.0 } else { 0.0 }),
  }
  let line = "ENV " + Json::object(m).stringify()
  if line != env_kept.val {
    env_kept.val = line
    tape_line(line)
  }
}

///|
/// One ENV line set again on the fake host (Tester::replay_frames).
fn replay_env(f : FakeHost, line : String) -> Unit {
  guard line.find("ENV ") is Some(i) else { return }
  let j = @json.parse(line.view(start_offset=i + 4).to_owned()) catch { _ => return }
  guard j is Object(m) else { return }
  let on = fn(k : String, was : Bool) -> Bool {
    match m.get(k) {
      Some(Number(d, ..)) => d != 0.0
      _ => was
    }
  }
  f.reduce_motion = on("motion", f.reduce_motion)
  f.reduce_transparency = on("glass", f.reduce_transparency)
  f.dark = on("dark", f.dark)
  f.inset = on("inset", f.inset)
  f.wants = true
}

///|
/// The settings a run began with (its ENV lines before its first DRAWHASH) set on the fake host before a Tester draws
/// its first frame (Tester::new's `run`), so the frames replayed are the run's, one for one.
fn env_before_frames(f : FakeHost, run : String) -> Unit {
  for v in run.split("\n") {
    let line = v.to_owned()
    if line.find("DRAWHASH ") is Some(_) {
      return
    }
    if line.find("ENV ") is Some(_) {
      replay_env(f, line)
    }
  }
}

///|
/// Motion reduced or not, as the person's setting, from the next frame on.
pub fn Tester::set_reduce_motion(self : Tester, on : Bool) -> Unit {
  self.fake.reduce_motion = on
  self.fake.wants = true
}
