// What a real host gave the app between its frames, kept with them (MBUI_DRAW_LOG=1, frames.mbt): each input as
// the host handed it (a pointer's, a wheel's, a key's, the input method's, the system's back, the app shown or
// hidden), with the host's own time for it, as an INPUT line between the DRAWHASH lines of the frames around it. A
// Tester's `replay_frames` hands each on again at its place, at its time: the run's whole input, seen again frame by
// frame.
//
//   INPUT {"k":"pointer","t":T,"a":[kind,x,y,button,mods]} (mods: the keys held as it went down; none before them)   "wheel" [x,y,dx,dy,phase]   "key" [code,mods]
//   INPUT {"k":"text","t":T,"a":[kind,a,b],"s":TEXT}    "back" [kind,x,progress,edge]   "app" [state]

///|
fn draw_logging() -> Bool {
  if draw_log.val < 0 {
    draw_log.val = if @hostapi.env("MBUI_DRAW_LOG") == "1" { 1 } else { 0 }
  }
  draw_log.val == 1 && fake.val is None
}

///|
/// An input came between two frames (any of the host's: a pointer's, a key's…): the next frame is the framework's to
/// draw, and the one after it, for what was changed by what read the input late in a frame (a list's rows are built
/// after the rest). Kept on the log when it is (MBUI_DRAW_LOG).
let inputs_since : Ref[Bool] = Ref::new(false)

///|
/// An input came between two frames that what is built takes (a press, a key, words typed, a drag, a wheel): the
/// frame after the next is built, for what it changed late in it that is no signal yet (what the build itself keeps of
/// a press: a pager turned, a menu shut). Not a pointer moved with nothing down: what changes of where it is, what
/// reads it reads (hand.mbt).
let inputs_taken : Ref[Bool] = Ref::new(false)

///|
fn took_input(kind : String, t : Double, args : Array[Double], text? : String) -> Unit {
  input_came()
  // (a pointer moved, gone out of the window, a wheel turned: the hand on mbui's own, what it is over; else the app's
  // to take, an event from outside: kept_part.mbt)
  // (and the system's back gesture going on: where it is, Nav's `finger`, on_back)
  let moved = (kind == "pointer" && (args[0] == 1.0 || args[0] == 7.0)) || (kind == "back" && args[0] == 1.0)
  // (a wheel: what it turned says whether it is taken, on_wheel; a list's place a signal of its own)
  let wheel = kind == "wheel"
  if !moved && !wheel {
    inputs_taken.val = true
  }
  if !(moved || wheel) {
    outside_came()
  }
  input_taped(kind, t, args, text?)
}

///|
/// An input written on the tape being made (taping), nothing else: one the old view takes none of (a press on the tree
/// made once, view_host.mbt) is replayed all the same.
fn input_taped(kind : String, t : Double, args : Array[Double], text? : String) -> Unit {
  if taping() {
    let m : Map[String, Json] = {
      "k": Json::string(kind),
      "t": Json::number(t),
      "a": Json::array(args.map(Json::number(_))),
    }
    match text {
      Some(s) => m["s"] = Json::string(s)
      None => ()
    }
    tape_line("INPUT " + Json::object(m).stringify())
  }
}

///|
/// One INPUT line handed on again (Tester::replay_frames), the fake host's clock at its time while it is.
fn replay_input(f : FakeHost, line : String) -> Unit {
  guard line.find("INPUT ") is Some(i) else { return }
  let j = @json.parse(line.view(start_offset=i + 6).to_owned()) catch { _ => return }
  guard j is Object(m) else { return }
  let a : Array[Double] = match m.get("a") {
    Some(Array(xs)) =>
      xs.map(fn(x) {
        match x {
          Number(d, ..) => d
          _ => 0.0
        }
      })
    _ => []
  }
  let n = fn(k : Int) -> Double { if k < a.length() { a[k] } else { 0.0 } }
  let t = match m.get("t") {
    Some(Number(d, ..)) => d
    _ => f.time
  }
  let frame_time = f.time
  f.time = t
  match m.get("k") {
    Some(String("pointer")) => {
      let by = if a.length() > 5 { n(5).to_int() } else { -1 }
      pointer_in(n(0).to_int(), n(1), n(2), n(3).to_int(), n(4).to_int(), by~)
    }
    Some(String("wheel")) => on_wheel(n(0), n(1), n(2), n(3), n(4).to_int())
    Some(String("key")) => on_key(n(0).to_int(), n(1).to_int())
    Some(String("text")) => {
      let s = match m.get("s") {
        Some(String(s)) => s
        _ => ""
      }
      on_text(n(0).to_int(), s, n(1).to_int(), n(2).to_int())
    }
    Some(String("back")) => on_back(n(0).to_int(), n(1), n(2), n(3).to_int())
    Some(String("app")) => on_app_state(n(0).to_int())
    _ => ()
  }
  f.time = frame_time
}
