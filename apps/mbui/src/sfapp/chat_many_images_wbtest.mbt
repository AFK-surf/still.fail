// A chat of many pictures (chat-many-images: 30 messages at its end, each a picture of its own) on a phone, its frames
// as its host gets them (Tester::run_as_host, HostFrame), its pictures answered by the test one at a time in the order
// they are asked for: flung toward its start as they come one after another, and at rest as one comes. Asserted by
// counts, never by time (2026-11-06, the user on a phone: scrolling dropped frames, a chat was slow to come in, its
// pictures flickered as they came): no frame builds the old frame or is drawn over the whole window, the window's tree
// is laid out once at most in any frame, and a picture come at rest draws again only where it is.

///|
/// A phone's chat of many pictures, what it asked for kept to be answered (`answer_next`) in the order asked.
priv struct ManyPictures {
  t : @ui.Tester
  asked : Array[String]
  answers : Map[String, (Result[(Json, Bytes?), Json]) -> Unit]
  mut answered : Int
}

///|
fn many_pictures_open() -> ManyPictures {
  let answers : Map[String, (Result[(Json, Bytes?), Json]) -> Unit] = {}
  let asked : Array[String] = []
  let images = @sfbase.ChatImages::new()
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-many-images", w=390.0, h=844.0, platform=2, wrap=fn(base) {
    let base = core_lists(base)
    {
      ..base,
      images,
      file: fn(station, key, name) {
        images.get(station, @sfbase.file_image_id(station, key, name), "mem:many-test/" + name, fn(_heard, done) {
          asked.push(name)
          answers[name] = done
        })
      },
    }
  })
  t.set_frame_period(host_phone_period)
  t.run_for(@ui.move_most_ms)
  { t, asked, answers, answered: 0 }
}

///|
/// The first picture asked for and not answered yet, answered with its bytes; whether there was one.
fn ManyPictures::answer_next(self : ManyPictures) -> Bool {
  guard self.answered < self.asked.length() else { return false }
  let name = self.asked[self.answered]
  self.answered = self.answered + 1
  match self.answers.get(name) {
    Some(done) => done(Ok((Json::object({}), Some(fixture_file_png(name)))))
    None => ()
  }
  true
}

///|
/// The window's tree's computes of its layout so far (Tree::work's).
fn many_computes() -> Int {
  match @ui.view_tree() {
    Some(tree) => tree.work().computes
    None => 0
  }
}

///|
test "a chat of many pictures flung on a phone as its pictures come one after another: no frame builds the old frame or is drawn whole, and the window's tree is laid out once at most in any" {
  let m = many_pictures_open()
  let t = m.t
  // (those asked for as it opened, at its end, come first)
  while m.answer_next() {

  }
  t.run_as_host(@ui.move_most_ms)
  assert_true(m.asked.length() > 0, msg="the open chat asked for its pictures")
  t.record_host()
  let out : Array[String] = []
  // (a frame at a time: what the hand does in it told first, then one picture asked for come, then the frame)
  let frame = fn(what : String, hand : () -> Unit) {
    let before = many_computes()
    hand()
    m.answer_next() |> ignore
    t.run_as_host(host_phone_period)
    let n = many_computes() - before
    if n > 1 {
      out.push("\{what} at \{t.time()}: the tree laid out \{n} times")
    }
  }
  // (a finger's drag down the messages, toward their start, a move a frame, let go moving: a fling)
  let (lx, ly) = (195.0, 844.0 * 0.3)
  frame("down", fn() { t.touch_at(0, lx, ly, t.time()) })
  for i in 1..=12 {
    frame("dragged \{i}", fn() { t.touch_at(1, lx, ly + 15.0 * i.to_double(), t.time()) })
  }
  frame("let go", fn() { t.touch_at(2, lx, ly + 180.0, t.time()) })
  let end = t.time() + host_fling_ms
  let mut k = 0
  while t.time() < end {
    k = k + 1
    frame("flung \{k}", fn() {  })
  }
  assert_true(m.answered > 1, msg="pictures came as it was flung")
  for f in t.host_frames() {
    if f.old_built || f.damage_share >= 1.0 {
      out.push(host_said(f))
    }
  }
  assert_eq(out, [])
}

///|
test "a picture come in a chat of many at rest on a phone draws again only where it is" {
  let m = many_pictures_open()
  let t = m.t
  t.run_as_host(@ui.move_most_ms)
  // (all but the last asked for come, the chat at rest after them)
  guard m.asked.length() > 1 else { abort("the open chat asked for too few pictures: \{m.asked.length()}") }
  while m.answered < m.asked.length() - 1 {
    m.answer_next() |> ignore
  }
  t.run_as_host(@sfpages.reveal_ms + @ui.move_most_ms)
  let shown = t.drawn_images().length()
  t.record_host()
  m.answer_next() |> ignore
  t.run_as_host(@sfpages.reveal_ms + @ui.move_most_ms)
  assert_true(t.drawn_images().length() > shown, msg="the picture come is drawn")
  // (where pictures are drawn now: what a picture's coming may draw again, its own place, nothing else)
  let places = t.drawn_images().map(fn(a) { (a[0], a[1], a[0] + a[2], a[1] + a[3]) })
  let out : Array[String] = []
  for f in t.host_frames() {
    if f.old_built || f.parts_built > 0 || !f.damage.iter().all(fn(r) { places.iter().any(fn(p) { host_within(r, p) }) }) {
      out.push(host_said(f))
    }
  }
  assert_eq(out, [])
}
