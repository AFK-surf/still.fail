// A scripted run as a film (Tester::film): the film's frames at its own rate from the Tester's first frame on, each
// the picture of the last frame the run drew by its moment. Whoever films draws the pictures (mbui/src/film: a host's
// renderer offscreen, over a Tester whose text and pictures are that host's, Tester::new's `live`); here only which
// picture each of the film's frames is, so that a film of a run is the run's frames, nothing waited for and nothing
// left out.

///|
/// `script` run over the view (Tester::drive: a frame at each of the display's frames, until it ends or `max` frames)
/// and filmed at `fps` frames a second from the Tester's first frame on: `draw` told of each frame drawn (the
/// Tester's first, then each the run draws), `put(k)` that the picture drawn last is the film's frame k, for every k
/// from 0 to the last in order, each once: the last drawn by a frame's moment is that frame's picture. What the Tester
/// logged on the way: its first frame's, then the run's (Tester::drive).
pub fn Tester::film(
  self : Tester,
  script : String,
  fps? : Double = 60.0,
  max? : Int = 3000,
  draw~ : (Tester) -> Unit,
  put~ : (Int) -> Unit,
) -> Array[String] {
  let t0 = self.fake.time
  let first = self.fake.logs.copy()
  // the film's frame the picture drawn last is
  let shown = Ref::new(0)
  draw(self)
  let logs = self.drive(script, max~, each=fn(t) {
    let k = ((t.fake.time - t0) * fps / 1000.0).round().to_int()
    while shown.val < k {
      put(shown.val)
      shown.val = shown.val + 1
    }
    draw(t)
  })
  put(shown.val)
  first + logs
}

///|
/// What the last frame presented, as a host's renderer is given it (@hostapi.present): its instances (scene.mbt's,
/// `inst_size` numbers each: the Tester's own, read, not changed), how many, and what is under them (red, green,
/// blue, 0-1).
pub fn Tester::presented(self : Tester) -> (FixedArray[Double], Int, (Double, Double, Double)) {
  ignore(self)
  let c = g()
  (c.inst, c.ninst, c.clear)
}

///|
/// The live host's picture for the Tester's image `id` (Tester::new's `live`), what that host's renderer draws an
/// instance of it by; None for one it has not (a stream's frame, a picture a test made up, one that did not decode).
pub fn Tester::live_image(self : Tester, id : Int) -> Int? {
  self.fake.live_images.get(id)
}
