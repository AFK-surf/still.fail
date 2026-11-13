// What a Tester reads of the passage being picked now, whoever picks it: the window's tree's words or an old view's
// paragraphs picked with the pointer (tree_select.mbt, desktop.mbt: `picked`), or a passage an old view picks itself in
// its own words (kit's Pick: a message's in the old phone page), as the last frame painted it. While a finger or a
// mouse still drags it as well as once let go, so a test reads it widen as it is widened and its end follow a handle,
// the same on a page of either kind (the coordinator of the migration, 2026-11-13).

///|
/// The passage being picked as a Tester reads it (Tester::picking): its words; whether a finger picked it (held on its
/// words: its handles); where a finger takes each of its ends' handles (its start's, its end's) and that one alone, where
/// they show.
#derive(Eq, Debug)
pub struct Picking {
  text : String
  finger : Bool
  ends : Array[(Double, Double)?]
}

///|
/// What an old view's own passage (kit's Pick) the frame being painted painted: its words and its ends; the last
/// frame's (picking_painted_last), as it ends.
// kept across runs: painted each frame, let go as a run begins (picking_reset)
let picking_painting : Ref[Picking?] = Ref(None)

///|
// kept across runs: as the last frame painted it, let go as a run begins (picking_reset)
let picking_painted_last : Ref[Picking?] = Ref(None)

///|
/// As a run begins (a Tester's start): none painted.
fn picking_reset() -> Unit {
  picking_painting.val = None
  picking_painted_last.val = None
}

///|
/// As a frame ends: what it painted is what a Tester reads.
fn picking_frame_end() -> Unit {
  picking_painted_last.val = picking_painting.val
  picking_painting.val = None
}

///|
/// A passage an old view picks itself in its own words (kit's Pick), `text`, its ends where a finger takes them
/// (`start`, `end`: the middle of each end's line), painted in this frame: for a Tester to read (Tester::picking).
pub fn picking_painted(text : String, start : (Double, Double), end : (Double, Double)) -> Unit {
  picking_painting.val = Some({ text, finger: true, ends: [Some(start), Some(end)] })
}

///|
/// The passage being picked now, as the last frame painted it, while it is dragged or once let go: an old view's own
/// (picking_painted) where one painted one, else what is picked with the pointer (the window's tree's words, an old
/// view's paragraphs), its ends a finger's handles where it picked it. None where nothing is picked.
pub fn Tester::picking(self : Tester) -> Picking? {
  self.reads_own()
  match picking_painted_last.val {
    Some(p) => return Some(p)
    None => ()
  }
  let text = selected_words()
  if text == "" {
    return None
  }
  // (each handle where only it takes the finger: its knob's side of its line, over the start's, under the end's, as
  // the two of a short passage overlap along their lines)
  let ends = finger_ends.mapi(fn(k, e) {
    e.map(fn(h) { (h.ex, if k == 0 { h.y + finger_knob_room / 2.0 } else { h.y + h.h - finger_knob_room / 2.0 }) })
  })
  Some({ text, finger: picked.finger, ends: if picked.finger { ends } else { [] } })
}
