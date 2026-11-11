// What the window's tree did in each frame a Tester drew, as a test asks it (Tester::tree_frames_from_now): its Work's
// counts since the frame before (nodes made, let go, laid out, words measured: what the journal's FrameDone says of a
// frame a device draws). For a test to hold what a part promises of what it makes (a page's list: each block made
// only while it shows), counted, never timed.

///|
/// What the window's tree did in one frame a Tester drew (Tester::tree_frames).
#derive(Eq, Debug)
pub(all) struct TreeFrame {
  made : Int
  let_go : Int
  laid : Int
  measured : Int
}

///|
// kept across runs: written by each frame a Tester draws while a test asked for them, put back as a Tester is made
let tree_frames_kept : Array[TreeFrame] = []

///|
/// The tree's counts as the last frame was kept, while they are (None: not asked).
// kept across runs: said by Tester::tree_frames_from_now, put back as a Tester is made
let tree_frames_was : Ref[(Int, Int, Int, Int)?] = Ref(None)

///|
/// What the frame just drawn did, kept where a test asked for it.
fn tree_frame_kept() -> Unit {
  guard tree_frames_was.val is Some(was) && view_app.val is Some(tree) else { return }
  let w = tree.work()
  tree_frames_was.val = Some((w.made, w.let_go, w.laid, w.measured))
  tree_frames_kept.push({
    made: journal_since(w.made, was.0),
    let_go: journal_since(w.let_go, was.1),
    laid: journal_since(w.laid, was.2),
    measured: journal_since(w.measured, was.3),
  })
}

///|
fn tree_frames_reset() -> Unit {
  tree_frames_kept.clear()
  tree_frames_was.val = None
}

///|
/// From now on, what the window's tree does in each frame drawn is kept (Tester::tree_frames), those kept before let
/// go.
pub fn Tester::tree_frames_from_now(self : Tester) -> Unit {
  ignore(self)
  tree_frames_kept.clear()
  tree_frames_was.val = match view_app.val {
    Some(tree) => {
      let w = tree.work()
      Some((w.made, w.let_go, w.laid, w.measured))
    }
    None => Some((0, 0, 0, 0))
  }
}

///|
/// What the window's tree did in each frame drawn since Tester::tree_frames_from_now, in order.
pub fn Tester::tree_frames(self : Tester) -> Array[TreeFrame] {
  self.reads_own()
  ignore(self)
  tree_frames_kept.copy()
}
