// The image viewer as nodes of the window's tree (sfbase's viewer_tree.mbt): what a finger does on it decided at each
// event's own moment, whatever frames were drawn between (each, a few, none, or drawn ahead of events told late);
// laid out in the room the shell gives it; closed, a finger on it called off; gone, nothing of it left.

///|
/// How the frames come as a host's events are told (told_by): drawn at each of the moments given (from `t0`), the
/// events told at their own moments between; a frame drawn `late` past each event's moment before it is told (the
/// host on to then, the event come late, its own time said with it); a frame drawn for `ahead` past each event's
/// moment as the host is at it (its logic there, what it draws sampled ahead, as a frame timed for its vsync is), the
/// event told then.
enum Frames {
  At(Array[Double])
  Late(Double)
  Ahead(Double)
}

///|
/// What a host tells, at its own moment from `t0`: a finger's event (`phase` 0 down, 1 moved, 2 up, 3 called off, of
/// finger `id` at (`x`, `y`)), or (phase -1) its word that the pictures it was decoding are done.
fn told_by(t : @ui.Tester, t0 : Double, said : Array[(Int, Int, Double, Double, Double)], frames : Frames) -> Unit {
  let at_frames = match frames {
    At(f) => f
    _ => []
  }
  let mut f = 0
  for e in said {
    let (phase, id, x, y, at) = e
    while f < at_frames.length() && at_frames[f] <= at {
      t.frame_at(t0 + at_frames[f])
      f = f + 1
    }
    match frames {
      Late(late) if phase >= 0 && t0 + at + late > t.time() => t.frame_at(t0 + at + late)
      Ahead(ahead) if t0 + at >= t.time() => t.frame_shown_at(t0 + at, t0 + at + ahead)
      _ => ()
    }
    if t.time() < t0 + at {
      t.advance(t0 + at - t.time())
    }
    if phase < 0 {
      t.finish_all()
    } else {
      t.touch_raw(phase, id, x, y, t0 + at)
    }
  }
  while f < at_frames.length() {
    t.frame_at(t0 + at_frames[f])
    f = f + 1
  }
}

///|
/// Every 8 ms to `to` from the start.
fn every_8(to : Double) -> Array[Double] {
  Array::makei((to / 8.0).to_int(), fn(i) { 8.0 * (i + 1).to_double() })
}

///|
/// The pictures drawn now, where (x, y, w, h), left to right, as one value.
fn pictures_now(t : @ui.Tester) -> Array[(Double, Double, Double, Double)] {
  drawn_pictures(t)
}

///|
/// The two pictures of the step fixture open on the first, its pictures decoded only as the host says (at 5 from `t0`),
/// a host's fingers each at its own time: two pinch it bigger (down at 10 and 20, the second out 90 by 120, up at 130
/// and 140), then one drags it left quickly (down at 400, 60 in 30 ms, up at 450: a fling). Read at 1200: where the
/// picture is, when its fling ends, the strip, which one shows, whether its bars do, and the pictures drawn.
fn image_chain(frames : Frames) -> ((Double, Double, Double, Double)?, Double, Double, String, Bool, Array[(Double, Double, Double, Double)]) {
  let t = preview_tester("step", finish=false)
  let v = viewer.get().unwrap()
  let t0 = t.time()
  let said = [(-1, 0, 0.0, 0.0, 5.0), (0, 0, 150.0, 422.0, 10.0), (0, 1, 240.0, 422.0, 20.0)]
  for i in 1..=10 {
    said.push((1, 1, 240.0 + 9.0 * i.to_double(), 422.0, 20.0 + 10.0 * i.to_double()))
  }
  said.push((2, 0, 150.0, 422.0, 130.0))
  said.push((2, 1, 330.0, 422.0, 140.0))
  said.push((0, 2, 250.0, 422.0, 400.0))
  for i in 1..=3 {
    said.push((1, 2, 250.0 - 20.0 * i.to_double(), 422.0, 400.0 + 10.0 * i.to_double()))
  }
  said.push((2, 2, 190.0, 422.0, 450.0))
  told_by(t, t0, said, frames)
  t.frame_at(t0 + 1200.0)
  let z = v.zoom
  (
    z.rect_at(t0 + 1200.0),
    z.fling_ends() - t0,
    pv_strip.way.value_at(t0 + 1200.0),
    viewer.get().unwrap().file.name,
    v.awake,
    pictures_now(t),
  )
}

///|
test "viewer on the tree: its picture decoded, pinched, dragged and flung, each at the host's moment: the same whichever frames came between, none, told late or drawn ahead" {
  let none = image_chain(At([]))
  let each = image_chain(At(every_8(1192.0)))
  let few = image_chain(At([65.0, 445.0, 700.0]))
  let late = image_chain(Late(40.0))
  let ahead = image_chain(Ahead(40.0))
  assert_eq(each, none)
  assert_eq(few, none)
  assert_eq(late, none)
  assert_eq(ahead, none)
  // (pinched twice as big, flung left: zoomed and gone that way, the same picture, its bars as they were, drawn)
  let (r, _, s, name, awake, drawn) = none
  assert_true(r.unwrap().2 > 600.0, msg="\{none}")
  assert_eq((s, name, awake), (0.0, "界面草图.png", true))
  assert_true(drawn.length() > 0)
}

///|
/// The step fixture's first picture swiped quickly to the next (down at 10 from `t0`, 200 left by 60, let go at 70),
/// then caught as it slides at 200 and pushed quickly back right (60 in 30 ms, let go at 240): which one shows, the
/// strip, and the pictures drawn at 800 and at 1500.
fn strip_chain(frames : Frames) -> (String, Double, Array[(Double, Double, Double, Double)], Array[(Double, Double, Double, Double)]) {
  let t = preview_tester("step", finish=false)
  let t0 = t.time()
  let said = [(-1, 0, 0.0, 0.0, 5.0), (0, 0, 300.0, 422.0, 10.0)]
  for i in 1..=5 {
    said.push((1, 0, 300.0 - 40.0 * i.to_double(), 422.0, 10.0 + 10.0 * i.to_double()))
  }
  said.push((2, 0, 100.0, 422.0, 70.0))
  said.push((0, 1, 195.0, 422.0, 200.0))
  for i in 1..=3 {
    said.push((1, 1, 195.0 + 20.0 * i.to_double(), 422.0, 200.0 + 10.0 * i.to_double()))
  }
  said.push((2, 1, 255.0, 422.0, 240.0))
  told_by(t, t0, said, frames)
  t.frame_at(t0 + 800.0)
  let mid = pictures_now(t)
  t.frame_at(t0 + 1500.0)
  (viewer.get().unwrap().file.name, pv_strip.way.value_at(t0 + 1500.0), mid, pictures_now(t))
}

///|
test "viewer on the tree: swiped to the next, caught as it slides and pushed back: the same pictures drawn whichever frames came, told late, or drawn ahead past the slide's end before the finger came" {
  let none = strip_chain(At([]))
  let each = strip_chain(At(every_8(792.0)))
  let few = strip_chain(At([30.0, 150.0, 500.0]))
  let late = strip_chain(Late(30.0))
  // (a frame drawn for 450 past each event: past where the first slide ends, before the finger catches it)
  let ahead = strip_chain(Ahead(450.0))
  assert_eq(each, none)
  assert_eq(few, none)
  assert_eq(late, none)
  assert_eq(ahead, none)
  assert_eq(none.1, 0.0)
}

///|
/// The image zoomed in (a double tap in its middle), then a host's finger from `t0`: down at 10, a quick 60 left in 30
/// ms, held still there till `up`, let go there. Where the picture is at 1200, and when its fling ends (none: before
/// the up).
fn let_go_after(up : Double, frames : Frames) -> ((Double, Double, Double, Double)?, Bool) raise {
  let t = preview_tester("image")
  let z = zoom_in_middle(t)
  let t0 = t.time()
  let said = [(0, 0, 250.0, 422.0, 10.0)]
  for i in 1..=3 {
    said.push((1, 0, 250.0 - 20.0 * i.to_double(), 422.0, 10.0 + 10.0 * i.to_double()))
  }
  said.push((2, 0, 190.0, 422.0, up))
  told_by(t, t0, said, frames)
  t.frame_at(t0 + 1200.0)
  (z.rect_at(t0 + 1200.0), z.fling_ends() > t0 + up)
}

///|
test "viewer on the tree: zoomed, a quick move then held still before it is let go: no fling (how fast it went as of the let go), whichever frames came" {
  let still = let_go_after(200.0, At([]))
  assert_eq(let_go_after(200.0, At(every_8(400.0))), still)
  assert_true(!still.1, msg="\{still}")
  // let go moving: on it goes
  let moving = let_go_after(50.0, At([]))
  assert_true(moving.1)
  assert_eq(let_go_after(50.0, At(every_8(400.0))), moving)
}

///|
/// The image zoomed in, then a host's finger down at 10 from `t0` and let go 100 left of it at 40, no move between:
/// where the picture is at 40 and at 1200, and whether the bars changed.
fn down_then_far(frames : Frames) -> (Double, Double, Bool) raise {
  let t = preview_tester("image")
  let v = viewer.get().unwrap()
  let z = zoom_in_middle(t)
  let awake = v.awake
  let t0 = t.time()
  let x0 = z.rect_at(t0).unwrap().0
  told_by(t, t0, [(0, 0, 250.0, 422.0, 10.0), (2, 0, 150.0, 422.0, 40.0)], frames)
  t.frame_at(t0 + 1200.0)
  (z.rect_at(t0 + 40.0).unwrap().0 - x0, z.rect_at(t0 + 1200.0).unwrap().0 - x0, v.awake != awake)
}

///|
test "viewer on the tree: zoomed, a finger down and let go far from there with no move between: a drag (moved there, flung on), no tap" {
  let none = down_then_far(At([]))
  assert_eq(down_then_far(At([20.0, 30.0])), none)
  assert_eq(none.0, -100.0)
  assert_true(none.1 < -100.0 && !none.2, msg="\{none}")
}

///|
/// The image open in a window 466 wide (a phone on its side, its system's bars at the left `left` wide): the stage the
/// picture is fitted to, and the share across the picture under a double tap 20 right of the stage's middle, before
/// and after its glide.
fn tapped_beside(left : Int) -> (Double, Double, Double) {
  let t = preview_tester("image", w=466.0, platform=1)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":20,\"left\":\{left},\"right\":0}}")
  t.run_for(@ui.move_most_ms)
  let z = viewer.get().unwrap().zoom
  let lx = z.bw / 2.0 + 20.0
  let ly = z.bh / 2.0
  let share = fn() {
    let (rx, _, rw, _) = z.rect_at(t.time()).unwrap()
    (lx - rx) / rw
  }
  let before = share()
  t.tap(left.to_double() + lx, ly)
  t.advance(double_tap_ms / 2.0)
  t.tap(left.to_double() + lx, ly)
  t.run_for(@ui.move_most_ms)
  (z.bw, before, share())
}

///|
test "viewer on the tree: fitted to the room beside the system's bars, as they come and go; a double tap zooms round the point under the finger there" {
  let beside = tapped_beside(84)
  let none = tapped_beside(0)
  assert_eq((beside.0, none.0), (466.0 - 84.0, 466.0))
  // the point of the picture under the finger stays under it, the bars beside or not
  assert_true((beside.2 - beside.1).abs() < 0.0001, msg="\{beside}")
  assert_true((none.2 - none.1).abs() < 0.0001, msg="\{none}")
}

///|
/// The image open, closed by back at 10 from `t0`; `held`, a finger down on it at 0 and moved and let go after it
/// closed (at 30 and 60): how its way out goes (when it ends, read at 100) and whether its bars changed.
fn closed_held(held : Bool) -> (Double, Double, Double, Bool) {
  let t = preview_tester("image", platform=1)
  let v = viewer.get().unwrap()
  let awake = v.awake
  let t0 = t.time()
  if held {
    t.touch_raw(0, 0, 195.0, 422.0, t0)
  }
  t.advance(t0 + back_at_ms - t.time())
  t.back()
  if held {
    t.advance(t0 + moved_at_ms - t.time())
    t.touch_raw(1, 0, 120.0, 300.0, t0 + moved_at_ms)
    t.advance(t0 + up_at_ms - t.time())
    t.touch_raw(2, 0, 120.0, 300.0, t0 + up_at_ms)
  }
  t.frame_at(t0 + 100.0)
  (v.fade.ends_at() - t0, v.fly.ends_at() - t0, v.zoom.rect_at(t0 + 100.0).unwrap().0, v.awake != awake)
}

///|
test "viewer on the tree: a finger held on it as it closes is called off then: what it does after changes nothing of its way out, and taps nothing" {
  let free = closed_held(false)
  let held = closed_held(true)
  assert_eq(held, free)
  assert_true(!free.3)
}

///|
/// What of the window's tree is held now: its nodes, its bindings, what is due on its timeline, and whether its clock is
/// read (a frame asked for each moment).
fn tree_held() -> (Int, Int, Int, Bool) {
  let tree = @ui.view_tree().unwrap()
  (tree.alive(), tree.bindings_held(), tree.due_count(), tree.clock_read())
}

///|
test "viewer on the tree: opened from the chat, zoomed, closed back into its thumbnail: nothing of it left; opened again, the same way in" {
  new_run()
  let src = fixture("chat-preview-named")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0)
  nav_rested(t)
  let mut tries = 0
  while t.locate("img:compare.png").length() == 0 && tries < 12 {
    let (first, _) = t.visible()
    t.scroll_to(if first > 0 { first - 1 } else { 0 })
    t.draw()
    tries += 1
  }
  t.run_for(@sfpages.reveal_ms)
  let (x, y) = t.locate("img:compare.png")[0]
  // (the pointer over the window, what is under it followed as long as it is: the window's, not the viewer's)
  t.move(x, y)
  let before = tree_held()
  let first = opened_closed(t, x, y, before)
  let again = opened_closed(t, x, y, before)
  assert_eq(again, first)
  assert_true(first.1)
  t.assert_idle()
}

///|
/// The chat's picture at (`x`, `y`) tapped open, zoomed in, closed: its way in (when it ends from the tap, and whether
/// it flies), checked still once in and gone to `before` once out.
fn opened_closed(t : @ui.Tester, x : Double, y : Double, before : (Int, Int, Int, Bool)) -> (Double, Bool) raise {
  t.tap(x, y)
  let v = viewer.get().unwrap()
  let t0 = t.time()
  let way = (v.fly.ends_at() - t0, v.flies)
  t.run_for(@ui.move_most_ms)
  // in and still: its clock read no more
  assert_true(!@ui.view_tree().unwrap().clock_read(), msg="\{tree_held()}")
  // zoomed in, then closed: back into its thumbnail
  t.tap(195.0, 422.0)
  t.advance(double_tap_ms / 2.0)
  t.tap(195.0, 422.0)
  t.run_for(@ui.move_most_ms)
  t.back()
  t.run_for(@ui.move_most_ms)
  t.run_for(@sfpages.reveal_ms)
  assert_true(viewer.get() is None && pv_leaving.get() is None)
  assert_eq(tree_held(), before)
  way
}

///|
/// A frame drawn as the display's next would be, nothing more said (none of Tester::draw's: what the test changed told
/// as from outside): what was told meanwhile shows only where what reads it followed it.
fn display_frame(t : @ui.Tester) -> Unit {
  t.frame_at(t.time() + between_frames_ms)
}

///|
/// A host's finger tapping the control said `label` (`role`), where it is drawn, then the frames the app asks for after
/// it (the one that takes it, the one after: what the input changed), nothing more.
fn pressed(t : @ui.Tester, role : @ui.Role, label : String) -> Unit raise {
  let (x, y, w, h) = t.get(role, label~).rect
  let at = t.time() + tap_step_ms
  t.advance(tap_step_ms)
  t.touch_raw(0, 9, x + w / 2.0, y + h / 2.0, at)
  t.advance(tap_step_ms)
  t.touch_raw(2, 9, x + w / 2.0, y + h / 2.0, at + tap_step_ms)
  t.frames_owed()
}

///|
/// Marking with the pen, a stroke drawn by a host's finger from `t0` (down at 10 on the picture, 4 moves 30 across,
/// let go at 60), no frame between, then the display's next frame; `off`, called off at 60 instead.
fn pen_stroke(t : @ui.Tester, off : Bool) -> Unit {
  let (x, y, _, _) = viewer.get().unwrap().zoom.rect().unwrap()
  let t0 = t.time()
  let said = [(0, 0, x + 40.0, y + 40.0, 10.0)]
  for i in 1..=4 {
    said.push((1, 0, x + 40.0 + 30.0 * i.to_double(), y + 40.0 + 10.0 * i.to_double(), 10.0 + 10.0 * i.to_double()))
  }
  said.push((if off { 3 } else { 2 }, 0, x + 160.0, y + 80.0, 60.0))
  told_by(t, t0, said, At([]))
  display_frame(t)
}

///|
/// The image open, marking it begun from the bar's 标注图片 and the pen taken up from its tools, each by a finger.
fn pen_marking() -> @ui.Tester raise {
  let t = preview_tester("image", platform=1)
  pressed(t, Button, @sf.t("web-main.annotate.image"))
  assert_true(marking.on)
  pressed(t, Button, pv("android-chat.marks.tool.pen"))
  assert_true(marking.tool == Pen)
  t
}

///|
/// The lines drawn in the marking's colour.
fn marked_lines(t : @ui.Tester) -> Int {
  t.drawn_lines().filter(fn(l) { l.5 == marking.color }).length()
}

///|
test "viewer on the tree, marking: a stroke drawn by a finger on the picture: the bar's undo at once; undone from the bar: gone from the picture at once" {
  let t = pen_marking()
  let undo = pv("android-chat.marks.undo")
  assert_true(t.get(Button, label=undo).disabled)
  pen_stroke(t, false)
  assert_eq(marking.shapes.length(), 1)
  assert_true(marked_lines(t) > 0)
  // the bar, built on its own, followed the picture's
  assert_true(!t.get(Button, label=undo).disabled)
  // undone from the bar: the picture's drawing, built on its own, follows it
  pressed(t, Button, undo)
  assert_eq(marking.shapes.length(), 0)
  assert_eq(marked_lines(t), 0)
  assert_true(t.get(Button, label=undo).disabled)
  // a stroke again, then marking left from the bar (取消): nothing of it drawn on the picture
  pen_stroke(t, false)
  assert_true(marked_lines(t) > 0)
  pressed(t, Button, pv("common.cancel"))
  assert_true(!marking.on)
  assert_eq(marked_lines(t), 0)
}

///|
test "viewer on the tree, marking: a stroke called off: nothing drawn, nothing to undo" {
  let t = pen_marking()
  pen_stroke(t, true)
  assert_eq(marking.shapes.length(), 0)
  assert_eq(marked_lines(t), 0)
  assert_true(t.get(Button, label=pv("android-chat.marks.undo")).disabled)
  marks_leave()
}

///|
test "viewer on the tree, marking: a mark moved and called off: back where it was, nothing more to undo" {
  let t = pen_marking()
  pen_stroke(t, false)
  let was = marking.shapes[0].pts.copy()
  let past = marking.past.length()
  pressed(t, Button, pv("android-chat.marks.tool.select"))
  let (x, y, _, _) = viewer.get().unwrap().zoom.rect().unwrap()
  let t0 = t.time()
  told_by(t, t0, [(0, 0, x + 100.0, y + 60.0, 10.0), (1, 0, x + 140.0, y + 60.0, 20.0), (1, 0, x + 180.0, y + 60.0, 30.0), (3, 0, x + 180.0, y + 60.0, 40.0)], At([]))
  display_frame(t)
  assert_eq(marking.shapes[0].pts, was)
  assert_eq(marking.past.length(), past)
  marks_leave()
}

///|
test "viewer on the tree, marking: a box's corner handle taken: the box stretched from the corner across, not moved; undone back" {
  let t = preview_tester("image", platform=1)
  pressed(t, Button, @sf.t("web-main.annotate.image"))
  assert_true(marking.tool == Rect)
  let z = viewer.get().unwrap().zoom
  let (x, y, w, _) = z.rect().unwrap()
  let k = w / z.nw
  // a box drawn from 40, 40 to 160, 100 on the picture, its note left unsaid (a tap beside it closes it)
  told_by(t, t.time(), [(0, 0, x + 40.0, y + 40.0, 10.0), (1, 0, x + 100.0, y + 70.0, 20.0), (2, 0, x + 160.0, y + 100.0, 30.0)], At([]))
  display_frame(t)
  assert_eq(marking.shapes.length(), 1)
  told_by(t, t.time(), [(0, 0, x + 20.0, y + 20.0, 10.0), (2, 0, x + 20.0, y + 20.0, 20.0)], At([]))
  display_frame(t)
  assert_eq(marking.note, -1)
  // picked by its left edge (a tap: nothing to undo), then its foot right handle (drawn half a reach out of the
  // corner) taken 40, 30 further
  pressed(t, Button, pv("android-chat.marks.tool.select"))
  let past = marking.past.length()
  told_by(t, t.time(), [(0, 0, x + 40.0, y + 70.0, 10.0), (2, 0, x + 40.0, y + 70.0, 20.0)], At([]))
  display_frame(t)
  assert_eq(marking.picked, marking.shapes[0].id)
  assert_eq(marking.past.length(), past)
  let hx = x + 160.0 + @sfbase.mark_reach / 2.0
  let hy = y + 100.0 + @sfbase.mark_reach / 2.0
  told_by(t, t.time(), [(0, 0, hx, hy, 10.0), (1, 0, hx + 20.0, hy + 15.0, 20.0), (2, 0, hx + 40.0, hy + 30.0, 30.0)], At([]))
  display_frame(t)
  let (bx, by, bw, bh) = marking.shapes[0].bounds()
  let near = fn(a : Double, b : Double) { (a - b).abs() < 0.01 }
  assert_true(near(bx * k, 40.0) && near(by * k, 40.0), msg="its top left stays: \{(bx * k, by * k)}")
  assert_true(near(bw * k, 160.0) && near(bh * k, 90.0), msg="stretched as far as the finger went: \{(bw * k, bh * k)}")
  assert_eq(marking.past.length(), past + 1)
  marks_undo()
  let (_, _, uw, uh) = marking.shapes[0].bounds()
  assert_true(near(uw * k, 120.0) && near(uh * k, 60.0))
  marks_leave()
}

///|
test "viewer on the tree, marking: a second finger as a stroke is drawn: the stroke dropped, the two a pinch" {
  let t = pen_marking()
  let (x, y, _, _) = viewer.get().unwrap().zoom.rect().unwrap()
  let t0 = t.time()
  told_by(
    t,
    t0,
    [
      (0, 0, x + 40.0, y + 40.0, 10.0),
      (1, 0, x + 80.0, y + 60.0, 20.0),
      (0, 1, x + 200.0, y + 100.0, 30.0),
      (1, 1, x + 230.0, y + 110.0, 40.0),
      (2, 1, x + 230.0, y + 110.0, 50.0),
      (2, 0, x + 80.0, y + 60.0, 60.0),
    ],
    At([]),
  )
  display_frame(t)
  assert_eq(marking.shapes.length(), 0)
  assert_true(marking.drag is None)
  assert_eq(marked_lines(t), 0)
  marks_leave()
}

///|
test "viewer on the tree: pinched, the bars over it not built again; the picture beside it decoded, its drawing not built again" {
  // (a phone's: its fingers the hand all along, the bars not built again for the hand changing as the first finger
  // comes, which they follow)
  let t = preview_tester("step", finish=false, platform=2)
  // (parts kept between frames as a host keeps them; no frame built again whole to check it, which would count as a
  // build of each)
  t.drawn_again(true)
  t.check_looks(false)
  // all it asked for decoded (its picture, its stand-in), then the strip drawn aside a little (the next drawn beside it,
  // its decode asked for) and let go, back where it was
  t.finish_all()
  t.run_for(@ui.move_most_ms)
  t.hold_drag(300.0, 422.0, 280.0, 422.0)
  t.release(280.0, 422.0)
  t.draw()
  t.run_for(strip_rest(t) + @ui.image_fade_ms)
  let beside = t.pending()
  assert_true(beside.length() > 0, msg="\{t.awaited()}")
  let (bars, drawing) = (viewer_built.bars, viewer_built.drawing)
  // the one beside it decoded, out of sight: nothing of this one's built again (the frame after its word, as the
  // display draws it, nothing else said)
  // (frames drawn as the display draws them, at moments said: none of the test's own stepping, run_for's, which builds
  // every part anew)
  t.finish_all()
  display_frame(t)
  t.frame_at(t.time() + @ui.image_fade_ms)
  assert_eq(viewer_built.drawing, drawing, msg="\{beside}")
  // pinched: its drawing built again as it goes, its bars not
  let t0 = t.time()
  told_by(t, t0, [(0, 0, 150.0, 422.0, 10.0), (0, 1, 240.0, 422.0, 20.0), (1, 1, 300.0, 422.0, 40.0), (1, 1, 330.0, 422.0, 60.0), (2, 0, 150.0, 422.0, 80.0), (2, 1, 330.0, 422.0, 90.0)], At([30.0, 50.0, 70.0]))
  t.frame_at(t0 + 90.0 + @ui.move_most_ms)
  assert_true(viewer_built.drawing > drawing)
  assert_eq(viewer_built.bars, bars)
}

///|
test "viewer on the tree: closed as it slides to the next, and another picture opened before that slide would have ended: it comes in still, where it is fitted, nothing of the slide before" {
  let t = preview_tester("step")
  t.drag(300.0, 422.0, 100.0, 422.0)
  assert_eq(viewer.get().unwrap().file.name, "第二版.png")
  assert_true(pv_strip.way.goes_at(t.time()))
  let slide_ends = pv_strip.way.end()
  t.back()
  display_frame(t)
  // opened anew as the slide was to go on
  let (a, _) = preview_files().iter().find_first(fn(f) { f.0.name == "界面草图.png" }).unwrap()
  open_preview("ws1/st1", "s-c1", a)
  assert_true(t.time() < slide_ends)
  display_frame(t)
  assert_eq(pv_strip.way.value_at(t.time()), 0.0)
  assert_true(!pv_strip.way.goes_at(t.time()))
  t.run_for(slide_ends - t.time())
  assert_eq(pv_strip.way.value_at(t.time()), 0.0)
}

///|
test "viewer on the tree: the strip let go as the app begins anew, wherever it was" {
  let t = preview_tester("step")
  t.hold_drag(300.0, 422.0, 250.0, 422.0)
  assert_true(pv_strip.way.value_at(t.time()) != 0.0)
  new_run()
  assert_eq(pv_strip.way.value_at(t.time()), 0.0)
  assert_true(!pv_strip.way.goes_at(t.time()))
}

///|
/// Marking with the words tool, the picture gliding in (a double tap's, set off at the start), words begun low on it by
/// a finger at 10, a frame drawn at `seen` (none: -1: the logic left where the finger was), then the keyboard up (300,
/// the window laid out above it) as the frame at 30 takes it, that frame drawn `ahead` past its moment (0: at it): when
/// the lift set out (from the ms 30 falls in), where it goes, where it should go (what is written kept 24 clear of the
/// keyboard, the picture where its glide has it at 30), and where a finger at 200 is on the picture as lifted.
fn lifted_for_words(seen : Double, ahead : Double) -> (Double, Double, Double, (Double, Double, Double, Double)?) raise {
  let t = preview_tester("image", platform=1)
  pressed(t, Button, @sf.t("web-main.annotate.image"))
  pressed(t, Button, pv("android-chat.marks.tool.text"))
  let v = viewer.get().unwrap()
  let z = v.zoom
  let t0 = t.time()
  z.double_tap(195.0, 422.0, at=t0)
  let (x, y, w, h) = z.rect_at(t0).unwrap()
  told_by(t, t0, [(0, 0, x + w / 2.0, y + h * 0.9, 10.0), (2, 0, x + w / 2.0, y + h * 0.9, 15.0)], At([]))
  assert_true(marking.writing is Some(_))
  if seen >= 0.0 {
    t.frame_at(t0 + seen)
  }
  // (the keyboard up, the app laid out above it, as a host does)
  t.set_ime_inset(300.0)
  t.resize_next(390.0, 844.0 - 300.0)
  if ahead > 0.0 {
    t.frame_shown_at(t0 + 30.0, t0 + 30.0 + ahead)
  } else {
    t.frame_at(t0 + 30.0)
  }
  let should = @sfbase.marks_writing_bottom_in(z, z.rect_at(t0 + 30.0)).unwrap() +
    @sfbase.marks_keyboard_gap -
    t.size().1
  (v.lift.starts_at() - @ui.whole_ms(t0 + 30.0), v.lift.target(), should, v.marks_rect(t0 + 200.0))
}

///|
test "viewer on the tree, marking: the keyboard up as words are written on a gliding picture: lifted from the keyboard's moment, as far as keeps them clear of it where the picture is then, a finger placed by the same lift, whatever frame came last or was drawn ahead" {
  let at = lifted_for_words(-1.0, 0.0)
  assert_eq(lifted_for_words(20.0, 0.0), at)
  assert_eq(lifted_for_words(-1.0, 40.0), at)
  assert_eq(lifted_for_words(20.0, 40.0), at)
  // (set out at the keyboard's moment, on the ms it falls in)
  assert_eq(at.0, 0.0)
  assert_true(at.1 > 0.0, msg="\{at}")
  assert_eq(at.1, at.2)
}

///|
test "viewer on the tree, narrow, a mouse: the secondary button on the picture opens its own menu (复制图片), never the chat's under it; off the picture none; the primary held still opens none" {
  let t = preview_tester("image", platform=0)
  assert_true(@ui.pointing() is Mouse)
  let (x, y, w, h) = viewer.get().unwrap().zoom.rect().unwrap()
  // held still with the primary button: a mouse's, no menu of it
  t.touch(0, x + w / 2.0, y + h / 2.0)
  t.draw()
  t.run_for(@ui.long_press_ms * 2.0)
  assert_true(!@sf.presenting())
  t.touch(2, x + w / 2.0, y + h / 2.0)
  t.draw()
  // off the picture, on the canvas: none
  t.right_click(x + w / 2.0, y + h + 40.0)
  assert_true(!@sf.presenting())
  assert_eq(t.reachable("引用").length(), 0)
  // on it: its own, opened once as it is pressed, nothing of the chat's under it; reached where its way in ends
  let before = @sf.last_presented()
  t.right_click(x + w / 2.0, y + h / 2.0)
  assert_eq(@sf.last_presented() - before, 1)
  assert_true(t.find("复制图片") is Some(_))
  assert_eq(t.reachable("引用").length(), 0)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(t.reachable("复制图片").length() > 0)
  assert_eq(t.reachable("引用").length(), 0)
}

///|
/// A picture of the chat tapped open, its whole answered 30 ms after it is asked for, as the core's answers come
/// (between frames, outside any event: the fixture's due work, fix_later), or failing then: how many times its whole was
/// asked for, and whether it came (or its failure was said).
fn whole_answered_later(fails : Bool) -> (Int, Bool, Bool) {
  new_run()
  let base = fixture("chat-preview-named")
  let asked = Ref(0)
  let src : Source = {
    ..base,
    read_going: fn(name, params, on_value, done) {
      if name == "station.file" {
        asked.val = asked.val + 1
        @sffixture.fix_later(30.0, fn() {
          if fails {
            done(Err({ "code": "gone", "message": "没了" }))
          } else {
            (base.read_going)(name, params, on_value, done)
          }
        })
      } else {
        (base.read_going)(name, params, on_value, done)
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0)
  nav_rested(t)
  let mut tries = 0
  while t.locate("img:compare.png").length() == 0 && tries < 12 {
    let (first, _) = t.visible()
    t.scroll_to(if first > 0 { first - 1 } else { 0 })
    t.draw()
    tries += 1
  }
  let (x, y) = t.locate("img:compare.png")[0]
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  let v = viewer.get().unwrap()
  (asked.val, v.bytes.get() is Some(_), v.error.get() is Some(_))
}

///|
test "viewer on the tree: its whole answered later, between frames, as the core answers: asked for once; what came (or that it failed) said with its no longer being asked" {
  assert_eq(whole_answered_later(false), (1, true, false))
  assert_eq(whole_answered_later(true), (1, false, true))
}

///|
test "viewer on the tree: the one beside it read ahead, stepped to before its answer came: read once, shown whole as it comes" {
  new_run()
  let base = fixture("chat-preview-step")
  let asked : Map[String, Int] = {}
  let later = 2000.0
  let src : Source = {
    ..base,
    read_going: fn(name, params, on_value, done) {
      let file = text(Some(params), "name")
      if name == "station.file" {
        asked[file] = asked.get(file).unwrap_or(0) + 1
      }
      if name == "station.file" && file == "第二版.png" {
        @sffixture.fix_later(later, fn() { (base.read_going)(name, params, on_value, done) })
      } else {
        (base.read_going)(name, params, on_value, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.draw()
  t.run_for(@ui.move_most_ms)
  // (read ahead, its answer still to come)
  assert_eq(asked.get("第二版.png"), Some(1))
  t.drag(300.0, 422.0, 100.0, 422.0)
  let v = viewer.get().unwrap()
  assert_eq(v.file.name, "第二版.png")
  assert_true(v.bytes.get() is None)
  t.run_for(later)
  assert_eq(asked.get("第二版.png"), Some(1))
  assert_true(v.bytes.get() is Some(_))
}

///|
/// The image open, held still on its picture by what the host says each press comes from, `hands` in turn (true a
/// finger, false a mouse): for each, whether its menu opened.
fn held_by(hands : Array[Bool]) -> Array[Bool] {
  let t = preview_tester("image", platform=2)
  let (x, y, w, h) = viewer.get().unwrap().zoom.rect().unwrap()
  let out = []
  for finger in hands {
    t.host_says_finger(Some(finger))
    let before = @sf.last_presented()
    t.press_at(x + w / 2.0, y + h / 2.0)
    t.run_for(@ui.long_press_ms * 2.0)
    out.push(@sf.last_presented() > before)
    t.release(x + w / 2.0, y + h / 2.0)
    t.draw()
    if @sf.presenting() {
      t.key(@ui.key_escape)
      t.draw()
    }
    t.run_for(@kit.sheet_rest("sf-present") - t.time())
  }
  out
}

///|
test "viewer on the tree: held still, a menu by a finger, none by a mouse, the hand of each press its own as it comes (from a mouse to a finger and back)" {
  assert_eq(held_by([false, true, false]), [false, true, false])
  assert_eq(held_by([true, false, true]), [true, false, true])
}

///|
/// The step fixture's chat laid out, its first picture opened (as a tap opens it, between frames), `frames` drawn or
/// none before a host's finger swipes to the next, no frame between: the wholes asked for in order as of the open and
/// in all, which one shows and whether it is whole.
fn read_ahead_by(frames : Bool) -> (Array[String], Array[String], String, Bool) raise {
  new_run()
  let base = fixture("chat-preview-step")
  // (the fixture's own opening of its first picture ended before the window is made: nothing of it read or read ahead,
  // the chat alone laid out)
  let opened = viewer.get().unwrap()
  let (steps, a) = (opened.steps, opened.file)
  @sfbase.close_now()
  let asked : Array[String] = []
  let src : Source = {
    ..base,
    read_going: fn(name, params, on_value, done) {
      if name == "station.file" {
        asked.push(text(Some(params), "name"))
      }
      (base.read_going)(name, params, on_value, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(asked.is_empty(), msg="\{asked}")
  // opened between frames, at t0: what is beside it read ahead as it opens
  let t0 = t.time()
  open_preview("ws1/st1", "s-c1", a, steps~)
  let at_open = asked.copy()
  if frames {
    t.frame_at(t0 + 16.0)
    t.frame_at(t0 + 32.0)
  }
  let said = [(0, 0, 300.0, 422.0, 40.0)]
  for i in 1..=5 {
    said.push((1, 0, 300.0 - 40.0 * i.to_double(), 422.0, 40.0 + 10.0 * i.to_double()))
  }
  said.push((2, 0, 100.0, 422.0, 100.0))
  told_by(t, t0, said, At([]))
  t.frame_at(t0 + 1000.0)
  let shown = viewer.get().unwrap()
  (at_open, asked.copy(), shown.file.name, shown.bytes.get() is Some(_))
}

///|
test "viewer on the tree: what is beside a picture read ahead as it opens, before any frame; frames drawn or not, the same reads, the same step" {
  let none = read_ahead_by(false)
  let drawn = read_ahead_by(true)
  assert_eq(drawn, none)
  assert_true(none.0.contains("第二版.png"), msg="\{none}")
  assert_eq((none.2, none.3), ("第二版.png", true))
}

///|
/// closed_held's moments from its finger down: back at 10, the finger moved at 30 and let go at 60.
let back_at_ms : Double = 10.0

///|
let moved_at_ms : Double = 30.0

///|
let up_at_ms : Double = 60.0

///|
/// A host's tap's own moments (pressed): down a step after the moment it is asked at, up a step after.
let tap_step_ms : Double = 5.0

///|
/// A made-up source whose whole files read through it (as they come: read_going) are counted in `asked`.
fn counted(base : Source, asked : Ref[Int]) -> Source {
  {
    ..base,
    read_going: fn(name, params, on_value, done) {
      if name == "station.file" {
        asked.val = asked.val + 1
      }
      (base.read_going)(name, params, on_value, done)
    },
  }
}

///|
test "a run begun before its Tester: the window's tree of the run before follows nothing the next one opens; what it reads, the new run's alone" {
  // the run before: its chat laid out, its window's tree made and following the app's state
  new_run()
  let before = Ref(0)
  let old_src = counted(fixture("chat-preview-named"), before)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let old_t = @ui.Tester::new(fn(c) { view(c, old_src) }, tree=app_tree(old_src), w=390.0, h=844.0)
  old_t.draw()
  // the next begun: its made-up core opening a picture before its Tester is made
  new_run()
  let base = fixture("chat-preview-image")
  let opened = viewer.get().unwrap()
  assert_eq(before.val, 0)
  assert_true(!opened.started && !opened.in_tree)
  // its Tester: the picture set out and read through this run's source alone
  let now = Ref(0)
  let src = counted(base, now)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(before.val, 0)
  assert_true(now.val > 0 && opened.started && opened.in_tree, msg="\{now.val}")
}

///|
/// The image zoomed in by a double tap (its glide set off at g0), frames drawn by `frames` (none, every 8 ms, or one
/// drawn ahead of the logic) till `at` from g0, then ⌘ and the wheel turned once at the moment `at` is: how big it is
/// shown then and after the wheel, and how big the wheel took it to be.
fn wheeled_after_glide(at : Double, frames : Int) -> (Double, Double) {
  let t = preview_tester("image", platform=0)
  let z = viewer.get().unwrap().zoom
  t.tap(195.0, 422.0)
  t.advance(double_tap_ms / 2.0)
  t.tap(195.0, 422.0)
  let g0 = t.time()
  match frames {
    1 =>
      for i in 1..=(at / 8.0).to_int() {
        t.frame_at(g0 + 8.0 * i.to_double())
      }
    2 => t.frame_shown_at(g0 + at / 2.0, g0 + at + 40.0)
    _ => ()
  }
  t.advance(g0 + at - t.time())
  let before = z.scale_at(t.time())
  t.wheel_with(195.0, 422.0, 0.0, -wheel_notch, @ui.wheel_mod_cmd)
  (before, z.scale_at(t.time()) / before)
}

///|
/// One notch of a wheel (its delta as a mouse's says it).
let wheel_notch : Double = 100.0

///|
test "viewer on the tree: zoomed in by a double tap, ⌘ and the wheel as it glides or after: on from how big it is shown then, whatever frames came" {
  for at in [@ui.move_most_ms / 2.0, @ui.move_most_ms + 50.0] {
    let none = wheeled_after_glide(at, 0)
    assert_eq(wheeled_after_glide(at, 1), none)
    assert_eq(wheeled_after_glide(at, 2), none)
    // (the wheel's step on from what shows: as many times bigger as a notch makes it, from fitted or from zoomed)
    assert_true((none.1 - @dmath.exp(wheel_notch * @sfbase.desk_wheel_rate)).abs() < 0.000001, msg="\{at}: \{none}")
  }
}

///|
test "viewer on the tree: a wheel over the picture is the picture's, never the chat's under it" {
  let t = preview_tester("image", platform=0)
  let z = viewer.get().unwrap().zoom
  let before = z.scale_at(t.time())
  let chat_at = (t.visible(), t.list_offset())
  // (a plain wheel, which would scroll the chat: over the picture, fitted, it moves nothing)
  t.wheel_with(195.0, 422.0, 0.0, wheel_notch, 0)
  assert_eq((t.visible(), t.list_offset()), chat_at)
  t.wheel_with(195.0, 422.0, 0.0, -wheel_notch, @ui.wheel_mod_cmd)
  assert_true(z.scale_at(t.time()) > before)
  assert_eq((t.visible(), t.list_offset()), chat_at)
}

///|
test "viewer on the tree: its picture's menu open over it, a wheel over the menu: not the picture's; the chat under it never scrolled" {
  let t = preview_tester("image", platform=0)
  let z = viewer.get().unwrap().zoom
  let (x, y, w, h) = z.rect().unwrap()
  let chat_at = (t.visible(), t.list_offset())
  // a wheel over the picture: the picture's, nothing of the chat's moved
  let before = z.scale_at(t.time())
  t.wheel_with(x + w / 2.0, y + h / 2.0, 0.0, -wheel_notch, @ui.wheel_mod_cmd)
  assert_true(z.scale_at(t.time()) > before)
  assert_eq((t.visible(), t.list_offset()), chat_at)
  // its menu opened over it, where its way in ends: a wheel over the menu the menu's, the picture as it was
  t.right_click(x + w / 2.0, y + h / 2.0)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  let (mx, my) = t.find("复制图片").unwrap()
  let shown = z.scale_at(t.time())
  t.wheel_with(mx, my, 0.0, -wheel_notch, @ui.wheel_mod_cmd)
  assert_eq(z.scale_at(t.time()), shown)
  assert_eq((t.visible(), t.list_offset()), chat_at)
}

///|
test "viewer on the tree, over the pages as a modal layer: a wheel over its bar's buttons scrolls nothing under it" {
  let t = preview_tester("image", platform=0)
  let chat_at = (t.visible(), t.list_offset())
  let (x, y, w, h) = t.get(Button, label=@sf.t("common.copy")).rect
  t.wheel_with(x + w / 2.0, y + h / 2.0, 0.0, wheel_notch, 0)
  t.wheel_with(x + w / 2.0, y + h / 2.0, 0.0, -wheel_notch, 0)
  assert_eq((t.visible(), t.list_offset()), chat_at)
}

///|
test "viewer on the tree, over the pages as a modal layer: the app's keys under it (⌘N a new chat) do nothing while it shows" {
  let t = preview_tester("image", platform=0)
  let depth = app.nav.depth()
  t.key(@ui.key_of_char('n'), mods=@ui.mod_cmd)
  t.draw()
  assert_eq(app.nav.depth(), depth)
  assert_true(viewer.get() is Some(_))
}

///|
/// The picture open, a key (`code`) said to have come at 20 ms past now: `how` 0 told at its moment (the host's clock
/// there), 1 told late (the host's clock at 80 by then), 2 a frame drawn at 10 before it, told at its moment. Whether
/// it is closing, when its way out ends (from now), and how far it is zoomed at 60.
fn keyed(code : Int, how : Int) -> (Bool, Double, Double) {
  let t = preview_tester("image", platform=0)
  let v = viewer.get().unwrap()
  let t0 = t.time()
  if how == 2 {
    t.frame_at(t0 + 10.0)
  }
  t.advance(t0 + (if how == 1 { 80.0 } else { 20.0 }) - t.time())
  t.key_told(code, 0, t0 + 20.0)
  let ends = if v.flies { v.fly.ends_at() } else { v.fade.ends_at() }
  (v.closing, ends - t0, v.zoom.scale_at(t0 + 60.0))
}

///|
test "viewer on the tree: Esc closes it and + zooms it at the key's own moment, told then, late or after a frame: the same; a menu over it, Esc closes the menu, it stays, the next Esc closes it" {
  for code in [@ui.key_escape, @ui.key_of_char('+')] {
    let on_time = keyed(code, 0)
    assert_eq(keyed(code, 1), on_time, msg="\{code} late")
    assert_eq(keyed(code, 2), on_time, msg="\{code} after a frame")
  }
  assert_true(keyed(@ui.key_escape, 0).0)
  // (+ zoomed in from how it showed then; a key it takes not, nothing)
  assert_true(keyed(@ui.key_of_char('+'), 0).2 > keyed(@ui.key_of_char('q'), 0).2)
  assert_true(!keyed(@ui.key_of_char('q'), 0).0)
  // its picture's menu open over it: Esc the menu's, then the next its
  let t = preview_tester("image", platform=0)
  let v = viewer.get().unwrap()
  let (x, y, w, h) = v.zoom.rect().unwrap()
  t.right_click(x + w / 2.0, y + h / 2.0)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(@sf.presenting())
  t.key(@ui.key_escape)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(!@sf.presenting() && !v.closing && viewer.get() is Some(_))
  t.key(@ui.key_escape)
  assert_true(v.closing)
}

///|
test "viewer on the tree: back its layer's; a menu over it, back the menu's, it stays, the next back closes it" {
  let t = preview_tester("image", platform=0)
  let v = viewer.get().unwrap()
  let (x, y, w, h) = v.zoom.rect().unwrap()
  t.right_click(x + w / 2.0, y + h / 2.0)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(@sf.presenting())
  t.back()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(!@sf.presenting() && !v.closing && viewer.get() is Some(_))
  t.back()
  assert_true(v.closing)
}

///|
/// The image fixture's viewer (fading in: no thumbnail to grow from), the window's tree drawing it: how opaque each of
/// its pictures is drawn at `at` from where it set out (and, `closing`, at `at` from where it is closed once in), and
/// how far its fade had come then.
fn fading(at : Double, closing~ : Bool = false) -> (Array[Double], Double) {
  new_run()
  let src = fixture("chat-preview-image")
  preview_src.val = Some(src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  // (its first frame: set out as its node is made, then)
  t.draw()
  let v = viewer.get().unwrap()
  if closing {
    t.run_for(@ui.move_most_ms)
    t.back()
  }
  let t0 = v.fade.starts_at()
  if at > 0.0 {
    t.frame_at(t0 + at)
  }
  // (the viewer's: as wide as its stage less its sides, the chat's thumbnails under it far narrower)
  let mine = t.drawn_images().filter(fn(i) { i[2] > 300.0 })
  (mine.map(fn(i) { i[8] }), v.fade.value_at(t0 + at))
}

///|
test "viewer on the tree: fading in and out, its picture as far in as its ground, never whole over a page still seen" {
  for c in [(0.0, false), (@sfbase.pv_fade_ms / 2.0, false), (@sfbase.pv_fade_ms + 50.0, false), (@sfbase.pv_fade_ms / 2.0, true)] {
    let (at, closing) = c
    let (shown, fade) = fading(at, closing~)
    // (none drawn where it is not in at all)
    assert_true(shown.length() > 0 || fade < 0.01, msg="at \{at} (closing \{closing}) no picture drawn, its fade \{fade}")
    if at < @sfbase.pv_fade_ms {
      assert_true(fade < 0.99 && fade > -0.01, msg="at \{at} (closing \{closing}) its fade is not on its way: \{fade}")
    }
    for o in shown {
      assert_true((o - fade).abs() < 0.01, msg="at \{at} (closing \{closing}) a picture drawn \{o} opaque, its fade \{fade}: \{shown}")
    }
  }
}

///|
test "viewer on the tree, a wide window: a picture as it comes says how much has come in its bar, 正在打开 before the core has said" {
  new_run()
  let base = fixture("chat-preview-step")
  // (each picture's whole held, how much of it has come told by the test)
  let said : Map[String, (Json) -> Unit] = {}
  let src : Source = {
    ..base,
    read_going: fn(name, params, on_value, done) {
      if name == "station.file" {
        said[text(Some(params), "name")] = on_value
      } else {
        (base.read_going)(name, params, on_value, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.draw()
  t.run_for(@ui.move_most_ms)
  let v = viewer.get().unwrap()
  assert_true(v.coming())
  assert_true(t.find("正在打开") is Some(_))
  (said.get(v.file.name).unwrap())({ "loaded": 1024.0, "total": 4096.0 })
  t.draw()
  assert_true(t.find("正在打开") is None)
  assert_true(t.find("正在读取 1 KB / 4 KB") is Some(_))
}

///|
test "viewer on the tree, a phone's screen: a picture as it comes, its floating bar its nodes: its name and ×, nothing of how much before the core has said; then a card saying how much in words and a bar at that share, read again as more comes; whole, the card gone and its tools there; nothing of it reading the clock once it is gone" {
  new_run()
  let base = fixture("chat-preview-step")
  // (its whole held: how much of it has come told by the test, then the whole given)
  let said : Map[String, (Json) -> Unit] = {}
  let held : Map[String, () -> Unit] = {}
  let src : Source = {
    ..base,
    read_going: fn(name, params, on_value, done) {
      if name == "station.file" {
        let file = text(Some(params), "name")
        said[file] = on_value
        held[file] = fn() { (base.read_going)(name, params, on_value, done) }
      } else {
        (base.read_going)(name, params, on_value, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=1)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.draw()
  t.run_for(@ui.move_most_ms)
  let v = viewer.get().unwrap()
  assert_true(v.coming() && v.in_tree, msg="coming, the tree's viewer")
  let close = @sf.t("web-main.preview.closeKey")
  assert_eq(t.all(Button, label=close).length(), 1, msg="its ×, once: the old bar's not drawn as well")
  assert_true(t.locate("icon:close").length() == 1, msg="its × the node's")
  assert_eq(t.all(ProgressBar).length(), 0, msg="nothing of how much before the core has said")
  assert_true(t.find("正在读取") is None)
  assert_eq(t.all(Button, label=@sf.t("common.copy")).length(), 0, msg="no tools while it comes")
  assert_eq(t.all(Button, label=@sf.t("web-main.preview.download")).length(), 0, msg="no download while it comes")
  (said.get(v.file.name).unwrap())({ "loaded": 1024.0, "total": 4096.0 })
  // (said as the core says it, no frame drawn for it)
  let now = t.all(ProgressBar)
  assert_eq(now.length(), 1, msg="its bar read out at once")
  assert_eq((now[0].value, now[0].range), ("25%", Some((0.0, 25.0, 100.0))), msg="at once")
  t.draw()
  assert_true(t.find("正在读取 1 KB / 4 KB") is Some(_), msg="how much, in words")
  let bars = t.all(ProgressBar)
  assert_eq(bars.length(), 1, msg="one bar")
  assert_eq(bars[0].value, "25%")
  assert_eq(bars[0].range, Some((0.0, 25.0, 100.0)), msg="its least, where it is, its most")
  (said.get(v.file.name).unwrap())({ "loaded": 3072.0, "total": 4096.0 })
  assert_eq((t.all(ProgressBar)[0].value, t.all(ProgressBar)[0].range), ("75%", Some((0.0, 75.0, 100.0))), msg="more come: said at once, no frame drawn")
  t.draw()
  assert_true(t.find("正在读取 3 KB / 4 KB") is Some(_), msg="more come: its words again")
  assert_eq(t.all(ProgressBar)[0].value, "75%", msg="and its bar")
  assert_eq(t.all(ProgressBar)[0].range, Some((0.0, 75.0, 100.0)), msg="its range at once")
  // (whole: the card gone, its tools there)
  (held.get(v.file.name).unwrap())()
  t.draw()
  t.run_for(@kit.progress_known_ms)
  assert_true(!v.coming(), msg="whole")
  assert_eq(t.all(ProgressBar).length(), 0, msg="its card gone")
  assert_true(t.find("正在读取") is None)
  for l in [@sf.t("web-main.annotate.image"), @sf.t("common.copy"), @sf.t("web-main.preview.download"), close] {
    assert_eq(t.all(Button, label=l).length(), 1, msg="\{l}: \{t.all(Button, label=l).length()}")
  }
  assert_true(!@ui.view_tree().unwrap().cycle_read(), msg="no wait drawn by the clock once whole")
}

///|
test "viewer on the tree, a phone's screen: a picture coming, its card shown: at rest between what the core says; closed as it comes, nothing of it reading the clock once it is gone" {
  new_run()
  let base = fixture("chat-preview-step")
  let said : Map[String, (Json) -> Unit] = {}
  let src : Source = {
    ..base,
    read_going: fn(name, params, on_value, done) {
      if name == "station.file" {
        said[text(Some(params), "name")] = on_value
      } else {
        (base.read_going)(name, params, on_value, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=1)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.draw()
  t.run_for(@ui.move_most_ms)
  let v = viewer.get().unwrap()
  (said.get(v.file.name).unwrap())({ "loaded": 1024.0 })
  t.draw()
  assert_eq(t.all(ProgressBar).length(), 1, msg="a bar")
  let tree = @ui.view_tree().unwrap()
  assert_true(t.find("正在读取") is Some(_))
  t.run_for(@kit.progress_known_ms)
  t.assert_idle()
  pressed(t, Button, @sf.t("web-main.preview.closeKey"))
  t.run_for(@ui.move_most_ms)
  t.run_for(@sfpages.reveal_ms)
  assert_true(viewer.get() is None && pv_leaving.get() is None, msg="closed")
  assert_true(!tree.cycle_read() && !tree.clock_read(), msg="nothing of it reading the clock once it is gone")
}

///|
test "viewer on the tree, a phone's screen: its floating bar its nodes, one of each tool (标注, 复制, 下载, ×), none of the old bar's; copied, a check for copied_ms from the press, frames drawn only as the app asks the host for them; × closes it" {
  let t = preview_tester("image", platform=1)
  let told = @sf.words_told_count()
  let labels = [
    @sf.t("web-main.annotate.image"),
    @sf.t("common.copy"),
    @sf.t("web-main.preview.download"),
    @sf.t("web-main.preview.closeKey"),
  ]
  for l in labels {
    // (one of each: the old bar's not drawn as well)
    assert_eq(t.all(Button, label=l).length(), 1, msg="\{l}: \{t.all(Button, label=l).length()}")
  }
  assert_true(viewer.get().unwrap().in_tree, msg="the tree's viewer")
  pressed(t, Button, @sf.t("common.copy"))
  assert_eq(t.all(Button, label=@sf.t("common.copied")).length(), 1, msg="copied: its check")
  let pressed_at = t.time()
  woken_till(t, pressed_at + @sf.copied_ms / 2.0)
  assert_eq(t.all(Button, label=@sf.t("common.copied")).length(), 1, msg="half its time: still")
  woken_till(t, pressed_at + @sf.copied_ms * 1.5)
  assert_eq(t.all(Button, label=@sf.t("common.copy")).length(), 1, msg="past its time: copy again")
  assert_eq(@sf.words_told_count(), told, msg="the words told once")
  pressed(t, Button, @sf.t("web-main.preview.closeKey"))
  t.run_for(@ui.move_most_ms)
  t.run_for(@sfpages.reveal_ms)
  assert_true(viewer.get() is None && pv_leaving.get() is None, msg="closed by its ×")
}

///|
/// Frames drawn till `end` only as the app asks its host for them (Tester::wanted_after: a frame now, a wake at a
/// moment, none), each at the display's next frame or at the moment it woke for.
fn woken_till(t : @ui.Tester, end : Double) -> Unit {
  let mut n = 0
  while t.time() < end && n < 400 {
    n += 1
    let w = t.wanted_after()
    if w == 0.0 {
      t.frame_at(t.time() + between_frames_ms)
    } else if w <= end {
      t.frame_at(w)
    } else {
      t.advance(end - t.time())
    }
  }
}

///|
test "viewer on the tree, a phone's screen: its floating bar's words as the core's language says them, said again as that changes, its nodes made once" {
  new_run()
  let base = fixture("chat-preview-image")
  let lang : @signals.Signal[String] = @signals.signal("zh", same=fn(a, b) { a == b })
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let got = (base.topic)(name, params)
      match (name, got.value) {
        ("prefs", Some(Object(m))) => {
          let o = m.copy()
          o["lang"] = Json::string(lang.get())
          { ..got, value: Some(Json::object(o)) }
        }
        ("prefs", None) => { ..got, value: Some(Json::object({ "lang": Json::string(lang.get()) })) }
        _ => got
      }
    },
  }
  preview_src.val = Some(src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=1)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.draw()
  t.run_for(@ui.move_most_ms)
  let zh = @sf.t("common.copy")
  assert_eq(t.all(Button, label=zh).length(), 1, msg="in Chinese: \{zh}")
  let copy = t.get(Button, label=zh)
  lang.set("en")
  t.draw()
  let en = @sf.t("common.copy")
  assert_true(en != zh, msg="the words in English: \{en}")
  assert_eq(t.all(Button, label=en).length(), 1, msg="said again in English: \{en}")
  assert_eq(t.get(Button, label=en).id, copy.id, msg="the same node, said again")
}

///|
/// Whether the tip of the floating bar's 复制 is read out shown now.
fn copy_tip_shown(t : @ui.Tester) -> Bool {
  t.semantics().any(fn(s) { s.role == Tooltip && s.label == @sf.t("common.copy") && !s.hidden })
}

///|
test "viewer on the tree, a phone's screen: its bar's tip a finger held open takes the first Escape, the viewer the next; no frame between a key and what it did" {
  let t = preview_tester("image", platform=1)
  let b = t.get(Button, label=@sf.t("common.copy"))
  let (cx, cy) = (b.rect.0 + b.rect.2 / 2.0, b.rect.1 + b.rect.3 / 2.0)
  t.touch(0, cx, cy)
  t.run_for(@ui.long_press_ms + 50.0)
  t.touch(2, cx, cy)
  t.run_for(a_moment_ms)
  assert_true(copy_tip_shown(t), msg="held open")
  t.key_told(@ui.key_escape, 0, t.time())
  assert_true(viewer.get() is Some(v) && !v.closing, msg="the first Escape the tip's: the viewer open still")
  t.run_for(@kit.pop_out_ms * 2.0)
  assert_true(!copy_tip_shown(t), msg="the tip gone")
  t.key_told(@ui.key_escape, 0, t.time())
  assert_true(viewer.get() is None || viewer.get().unwrap().closing, msg="the next Escape the viewer's")
}

///|
test "viewer on the tree, a mouse: its bar's tip shown by the keyboard's focus, the picture's menu opened over it: Escape the menu's first, then the tip's, then the viewer's" {
  let t = preview_tester("image", platform=0)
  // (the keyboard's focus to 复制, its tip shown)
  let mut tabs = 0
  while !copy_tip_shown(t) && tabs < 8 {
    t.key(@ui.key_tab)
    t.draw()
    tabs += 1
  }
  assert_true(copy_tip_shown(t), msg="the focus on 复制, its tip shown (\{tabs} tabs)")
  let (x, y, w, h) = viewer.get().unwrap().zoom.rect().unwrap()
  t.right_click(x + w / 2.0, y + h / 2.0)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(@sf.presenting(), msg="the picture's menu open")
  t.key(@ui.key_escape)
  t.run_for(@kit.sheet_rest("sf-present") - t.time() + 50.0)
  assert_true(!@sf.presenting(), msg="the first Escape the menu's")
  assert_true(viewer.get() is Some(v) && !v.closing, msg="the viewer open still")
  assert_true(copy_tip_shown(t), msg="the tip still shown")
  t.key_told(@ui.key_escape, 0, t.time())
  assert_true(viewer.get() is Some(v) && !v.closing, msg="the next Escape the tip's: the viewer open still")
  t.run_for(@kit.pop_out_ms * 2.0)
  assert_true(!copy_tip_shown(t), msg="the tip gone")
  t.key_told(@ui.key_escape, 0, t.time())
  assert_true(viewer.get() is None || viewer.get().unwrap().closing, msg="then the viewer's")
}

///|
/// The floating bar's name as the window's tree draws it now: its size and its ink.
fn head_name_drawn() -> (Double, Int64)? {
  let name = viewer.get().unwrap().file.name
  @ui.view_tree().unwrap().drawn().iter().find_first(fn(d) { d.words == name }).map(fn(d) { (d.words_look.size, d.ink) })
}

///|
test "viewer on the tree: its floating bar's words in still.fail's theme as its old views are, a touch screen's sizes from its first frame; light or dark as chosen, a frame owed at once and drawn so the frame after; a window made narrower, its first frame the same" {
  for platform in [1, 0] {
    let look : @signals.Signal[String] = @signals.signal("light", same=fn(a, b) { a == b })
    let t = looked_preview(look, platform)
    let theme = @sf.ui_theme()
    let body = theme.text_size(Body).0
    assert_eq(head_name_drawn().map(fn(n) { n.0 }), Some(body), msg="platform \{platform}: its name as still.fail's Body")
    // (dark chosen, as the core's prefs say it: their appearance)
    look.set("dark")
    assert_eq(t.wanted_after(), 0.0, msg="platform \{platform}: dark as chosen, a frame owed at once")
    t.draw()
    let dark = @sf.ui_theme()
    assert_true(dark.dark, msg="dark as set")
    assert_eq(head_name_drawn().map(fn(n) { n.1 }), Some(dark.color(Fg)), msg="platform \{platform}: its name in the dark's ink, the frame after")
    t.resize(360.0, 844.0)
    t.draw()
    assert_eq(head_name_drawn().map(fn(n) { n.0 }), Some(dark.text_size(Body).0), msg="platform \{platform}: narrower, the same size")
  }
}

///|
/// A moment after an input (a finger let go): less than any of the motions it sets off.
let a_moment_ms : Double = 50.0

///|
/// How many of what was kept since `before` are `png`.
fn kept_as(t : @ui.Tester, before : Int, png : Bytes) -> Int {
  t.kept()[before:].to_array().filter(fn(k) { k.2 == png }).length()
}

///|
/// Marking the image open (pen_marking, a stroke), the host's drawings answered as the test says, then
/// 下载标注后的图片 pressed by a finger: the host asked to draw the marks onto it, its picture to come as `png`.
fn marks_asked(png : Bytes) -> @ui.Tester raise {
  let t = pen_marking()
  t.marks_by_hand()
  pen_stroke(t, false)
  t.marks_make(png)
  pressed(t, Button, pv("android-chat.marks.downloadMarked"))
  t
}

///|
test "viewer on the tree, marking: the marked picture kept once at the host's word, no frame drawn for it; not before, not again with the frames after; another drawing with the same picture kept once more" {
  let png = b"\x89PNG-marked"
  let t = marks_asked(png)
  let before = t.kept().length()
  t.run_for(@ui.move_most_ms)
  assert_eq(kept_as(t, before, png), 0, msg="before the host's word: none")
  t.marks_answer(1)
  assert_eq(kept_as(t, before, png), 1, msg="at its word, no frame drawn: once")
  t.run_for(@ui.move_most_ms)
  t.marks_answer(1)
  t.run_for(@ui.move_most_ms)
  assert_eq(kept_as(t, before, png), 1, msg="frames after, its word again: not again")
  // (marking on, another stroke, the same picture drawn by another drawing)
  pen_stroke(t, false)
  t.marks_make(png)
  pressed(t, Button, pv("android-chat.marks.downloadMarked"))
  t.marks_answer(2)
  assert_eq(kept_as(t, before, png), 2, msg="another drawing, the same picture: once more")
}

///|
test "viewer on the tree, marking: its viewer closed before the host's word, the picture kept by none, another viewer opened after taking none of it" {
  let png = b"\x89PNG-marked"
  let t = marks_asked(png)
  let before = t.kept().length()
  let name = viewer.get().unwrap().file.name
  viewer.get().unwrap().shut(t.ctx())
  t.run_for(@ui.move_most_ms)
  t.run_for(@sfpages.reveal_ms)
  assert_true(viewer.get() is None, msg="closed")
  // (another viewer opened on the same picture, from the chat)
  // (another viewer opened on the same file, as the app opens one: open_preview, the fixture's own file)
  let file = preview_files().iter().find_first(fn(f) { f.0.name == name }).unwrap().0
  open_preview("ws1/st1", "s-c1", file)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is Some(_), msg="another viewer open")
  t.marks_answer(1)
  t.run_for(@ui.move_most_ms)
  assert_eq(kept_as(t, before, png), 0, msg="kept by none")
}

///|
/// The image open (preview_tester's), the core's prefs saying the appearance `look` says as it changes.
fn looked_preview(look : @signals.Signal[String], platform : Int) -> @ui.Tester {
  new_run()
  let base = fixture("chat-preview-image")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let got = (base.topic)(name, params)
      match (name, got.value) {
        ("prefs", Some(Object(m))) => {
          let o = m.copy()
          o["appearance"] = Json::string(look.get())
          { ..got, value: Some(Json::object(o)) }
        }
        ("prefs", None) => { ..got, value: Some(Json::object({ "appearance": Json::string(look.get()) })) }
        _ => got
      }
    },
  }
  preview_src.val = Some(src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// A picture opened on a fold half open (its crease across, so a small screen however wide: tabletop.mbt), `w` wide,
/// its whole held by the test while `hold` (how much has come told by it: `said`, the whole given: `given`).
fn folded_preview(
  w : Double,
  hold : Bool,
  said : Map[String, (Json) -> Unit],
  given : Map[String, () -> Unit],
) -> @ui.Tester {
  new_run()
  let base = fixture("chat-preview-image")
  let src : Source = {
    ..base,
    read_going: fn(name, params, on_value, done) {
      if hold && name == "station.file" {
        let file = text(Some(params), "name")
        said[file] = on_value
        given[file] = fn() { (base.read_going)(name, params, on_value, done) }
      } else {
        (base.read_going)(name, params, on_value, done)
      }
    },
  }
  preview_src.val = Some(src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=626.0, platform=1)
  t.post(@hostapi.system_channel, "{\"fold\":{\"hinge\":\"half\",\"divisions\":[{\"x\":0,\"y\":300,\"w\":\{w},\"h\":30}]}}")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "viewer on the tree, a fold half open wider than a phone: its floating bar its nodes, its kind and size after its name with its tools, none of the old bar's and no zoom's tools (zoomed by the hand and the keys); made narrower than a phone, the kind and size gone, the bar the same nodes" {
  let said : Map[String, (Json) -> Unit] = {}
  let given : Map[String, () -> Unit] = {}
  let t = folded_preview(890.0, true, said, given)
  assert_true(@sf.layout(890.0) is Small, msg="a small screen however wide")
  let v = viewer.get().unwrap()
  assert_true(v.coming() && v.in_tree, msg="coming, the tree's viewer")
  let zoom = [
    @sf.t("web-main.preview.zoomOutKey"),
    @sf.t("web-main.preview.fitKey"),
    @sf.t("web-main.preview.zoomInKey"),
    @sf.t("web-main.preview.actualKey"),
  ]
  (given.get(v.file.name).unwrap())()
  t.draw()
  t.run_for(@kit.progress_known_ms)
  assert_true(!v.coming(), msg="whole")
  for l in [@sf.t("web-main.annotate.image"), @sf.t("common.copy"), @sf.t("web-main.preview.download"), @sf.t("web-main.preview.closeKey")] {
    assert_eq(t.all(Button, label=l).length(), 1, msg="\{l}: one, the node's: \{t.all(Button, label=l).length()}")
  }
  for l in zoom {
    assert_eq(t.all(Button, label=l).length(), 0, msg="whole: no zoom's tool: \{l}")
  }
  let meta = @sfbase.vf_meta(v, preview_src.val.unwrap())
  assert_true(meta != "" && t.find(meta) is Some(_), msg="its kind and size after its name: \{meta}")
  // (zoomed by the keys: = (+), a quarter more)
  let z = v.zoom
  let fitted = z.scale_at(t.time())
  t.key(@ui.key_of_char('='))
  t.run_for(@ui.move_most_ms)
  let now = z.scale_at(t.time())
  assert_true((now - fitted * @sf.viewer_zoom_step).abs() < 0.0001, msg="+: a quarter more, \{fitted} then \{now}")
  // (narrower than a phone, the same pose: the kind and size gone, the rest the same nodes)
  t.resize(600.0, 626.0)
  t.post(@hostapi.system_channel, "{\"fold\":{\"hinge\":\"half\",\"divisions\":[{\"x\":0,\"y\":300,\"w\":600,\"h\":30}]}}")
  t.draw()
  assert_true(t.find(meta) is None, msg="narrow: no kind and size")
  assert_eq(t.all(Button, label=@sf.t("common.copy")).length(), 1, msg="narrow: its tools still")
  assert_true(viewer.get().unwrap().in_tree, msg="the same viewer")
  // (wide again: its kind and size back, still none of the old bar's)
  t.resize(890.0, 626.0)
  t.post(@hostapi.system_channel, "{\"fold\":{\"hinge\":\"half\",\"divisions\":[{\"x\":0,\"y\":300,\"w\":890,\"h\":30}]}}")
  t.draw()
  for l in [@sf.t("common.copy"), @sf.t("web-main.preview.closeKey")] {
    assert_eq(t.all(Button, label=l).length(), 1, msg="wide again: \{l} one: \{t.all(Button, label=l).length()}")
  }
  for l in zoom {
    assert_eq(t.all(Button, label=l).length(), 0, msg="wide again: no zoom's tool: \{l}")
  }
  assert_true(t.find(meta) is Some(_), msg="wide again: its kind and size")
  assert_true(viewer.get().unwrap().in_tree, msg="the same viewer")
}

///|
/// A picture opened in a wide window (1280 wide, a mouse: the wide frame, its viewer the tree's), whole.
fn wide_preview() -> @ui.Tester {
  let t = preview_tester("image", w=1280.0, platform=0)
  t
}

///|
test "viewer on the tree, a wide window, a mouse: the secondary button on the picture opens its own menu (复制图片) over it, reached there; Escape the menu's first, then the viewer's" {
  let t = wide_preview()
  let v = viewer.get().unwrap()
  assert_true(v.in_tree)
  let (x, y, w, h) = v.zoom.rect().unwrap()
  let before = @sf.last_presented()
  t.right_click(x + w / 2.0, y + h / 2.0)
  assert_eq(@sf.last_presented() - before, 1, msg="its own menu, once")
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(t.reachable("复制图片").length() > 0, msg="over it, reached")
  assert_eq(t.reachable("引用").length(), 0, msg="nothing of the chat's")
  t.key_told(@ui.key_escape, 0, t.time())
  // (as the key is told, no frame drawn: the menu's, the viewer staying)
  assert_true(!@sf.presenting(), msg="Escape: the menu closed at once")
  assert_true(viewer.get() is Some(_), msg="the viewer stays")
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is Some(_), msg="the viewer stays as the menu goes")
  t.key_told(@ui.key_escape, 0, t.time())
  t.run_for(@ui.move_most_ms)
  t.run_for(@sfpages.reveal_ms)
  assert_true(viewer.get() is None && pv_leaving.get() is None, msg="the next Escape: the viewer closed")
}

///|
test "viewer on the tree, its window made narrow then wide again (Large, Small, Medium, Large): the same viewer, as zoomed as it was, flying in no more, one bar of it drawn, closed by Escape" {
  let t = wide_preview()
  let v = viewer.get().unwrap()
  v.zoom.zoom_to(v.zoom.fit() * 2.0, v.zoom.bw / 2.0, v.zoom.bh / 2.0, false, at=t.time())
  t.draw()
  let zoomed = v.zoom.scale_at(t.time())
  for size in [(390.0, 844.0), (700.0, 800.0), (1280.0, 800.0)] {
    t.resize(size.0, size.1)
    t.draw()
    // (each tier's shell: Small the narrow one's, Medium the tape's, Large the panes')
    let tier = @sf.layout(size.0)
    assert_eq(tier, if size.0 < 600.0 { @sf.Small } else if size.0 < 840.0 { @sf.Medium } else { @sf.Large }, msg="\{size}")
    let now = viewer.get().unwrap()
    assert_true(physical_equal(now, v), msg="\{size}: the same viewer")
    assert_true(now.in_tree, msg="\{size}: the tree's")
    assert_true(!now.flies || now.fly_back, msg="\{size}: flying in no more")
    assert_eq(now.zoom.scale_at(t.time()), zoomed, msg="\{size}: as zoomed")
    // (one bar drawn: the floating one's × on a small screen, none across the top's, whose way back closes it)
    let closes = t.all(Button, label=@sf.t("web-main.preview.closeKey")).length()
    assert_eq(closes, if size.0 < 600.0 { 1 } else { 0 }, msg="\{size}: one bar's")
  }
  t.key_told(@ui.key_escape, 0, t.time())
  t.run_for(@ui.move_most_ms)
  t.run_for(@sfpages.reveal_ms)
  assert_true(viewer.get() is None && pv_leaving.get() is None, msg="closed by Escape")
}

///|
/// A picture opened in a wide window (a mouse), zoomed in by ⌘ and the wheel at the stage's middle till it is larger
/// than the stage both ways (4 times: 2400 by 1600 in 1280 by 844); the pointer put at (100, 700); then ⌘ and the
/// wheel turned at (400, 300), off the middle, told with no frame drawn, and (`moved_after`) the pointer moved to
/// (1200, 100) before any frame: where in the picture the point under (400, 300) was, and where it is after (as shares
/// of the picture's width and height), and the picture's place after (none of it kept from where the wheel puts it:
/// larger than the stage, away from its edges).
fn wheel_centre(moved_after : Bool) -> ((Double, Double), (Double, Double), (Double, Double, Double, Double)) raise {
  let t = wide_preview()
  let z = viewer.get().unwrap().zoom
  // (4 times: e^(693 × 0.002), at the stage's middle (the window's: 1280 by 844), the pointer there too: round the
  // middle whichever way the wheel is read)
  let (mx, my) = (z.bw / 2.0, z.bh / 2.0)
  t.move(mx, my)
  t.wheel_with(mx, my, 0.0, -693.0, @ui.wheel_mod_cmd)
  t.draw()
  let (rx, ry, rw, rh) = z.rect_at(t.time()).unwrap()
  assert_true(rw > z.bw * 1.5 && rh > z.bh * 1.5, msg="larger than the stage both ways: \{rw} by \{rh}")
  assert_true(
    (rx + rw / 2.0 - z.bw / 2.0).abs() < 0.001 && (ry + rh / 2.0 - z.bh / 2.0).abs() < 0.001,
    msg="its middle the stage's: \{(rx, ry, rw, rh)}",
  )
  t.move(100.0, 700.0)
  let (bx, by) = (400.0, 300.0)
  let before = ((bx - rx) / rw, (by - ry) / rh)
  t.wheel_told(bx, by, 0.0, -200.0, @ui.wheel_mod_cmd, t.time())
  if moved_after {
    t.touch(1, 1200.0, 100.0)
  }
  t.draw()
  let (sx, sy, sw, sh) = z.rect_at(t.time()).unwrap()
  assert_true(sw > rw * 1.4, msg="zoomed in a half more")
  (before, ((bx - sx) / sw, (by - sy) / sh), (sx, sy, sw, sh))
}

///|
test "viewer on the tree, a wide window, a mouse: ⌘ and the wheel zoom round where the wheel turned, not where the pointer was before it nor where it went after it with no frame between" {
  for moved_after in [false, true] {
    let (before, after, (sx, sy, sw, sh)) = wheel_centre(moved_after)
    // (away from the stage's edges: nothing of where the wheel put it kept in)
    let z = viewer.get().unwrap().zoom
    assert_true(sx < -1.0 && sy < -1.0 && sx + sw > z.bw + 1.0 && sy + sh > z.bh + 1.0, msg="clear of the stage's edges: \{(sx, sy, sw, sh)}")
    assert_true(
      (after.0 - before.0).abs() < 0.000001 && (after.1 - before.1).abs() < 0.000001,
      msg="moved after \{moved_after}: the point under the wheel stays under it: \{before} then \{after}",
    )
  }
}

///|
test "viewer on the tree, a wide window: a toast said as it shows (a call's answer, between frames) over it, its button reached there; pressed, done, the viewer staying" {
  let t = wide_preview()
  assert_true(viewer.get().unwrap().in_tree)
  let done = Ref(0)
  toast_later("已移到回收站", action="撤销", run=fn() { done.val += 1 })
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.reachable("撤销").length() > 0, msg="its button over the viewer, reached")
  t.tap_text("撤销")
  t.draw()
  assert_eq(done.val, 1, msg="pressed: done")
  assert_true(viewer.get() is Some(_), msg="the viewer stays")
}

///|
/// The bar across the top of a wide window as it is drawn: its glass's top (the glass as wide as the window, at its
/// top: the window's tree's, else an old view's), None where none is drawn.
fn wide_bar_top(t : @ui.Tester) -> Double? {
  for d in @ui.view_tree().unwrap().drawn() {
    if d.glass is Some(_) && d.w == 1280.0 && d.y <= 0.0 {
      return Some(d.y)
    }
  }
  let mut out = None
  for g in t.drawn_glass() {
    if g.2 == 1280.0 && g.1 <= 0.0 {
      out = Some(g.1)
    }
  }
  out
}

///|
/// A picture opened in a wide window, clicked on (the bars hidden by it, at the click's moment), and `after` ms later
/// drawn (`frames`: the frames between at the display's pace; else none between): where the bar across the top is
/// drawn then.
fn wide_bar_after_click(frames : Bool, after : Double) -> Double? raise {
  let t = wide_preview()
  let v = viewer.get().unwrap()
  assert_true(v.in_tree, msg="the tree's viewer")
  assert_eq(wide_bar_top(t), Some(0.0), msg="the bar across the top, there as it opens")
  let (x, y, w, h) = v.zoom.rect().unwrap()
  t.touch(0, x + w / 2.0, y + h / 2.0)
  t.touch(2, x + w / 2.0, y + h / 2.0)
  assert_true(!v.bars_shown(), msg="clicked: its bars hidden")
  if frames {
    t.run_for(after)
  } else {
    t.advance(after)
    t.draw()
  }
  wide_bar_top(t)
}

///|
test "viewer on the tree, a wide window, a mouse: a click on the picture hides the bar across the top from the click's moment, going up as far by a moment the frames drawn between or none" {
  // (half its way: as far as the bar's own way has gone by then)
  let half = @sf.viewer_bar_ms / 2.0
  let drawn = wide_bar_after_click(true, half)
  let none = wide_bar_after_click(false, half)
  match drawn {
    Some(y) => assert_true(y < -1.0 && y > -@sf.viewer_bar_h, msg="under way: \{y}")
    None => fail("frames: the bar gone half its way")
  }
  assert_eq(none, drawn, msg="no frame between: as far up as with them")
}

///|
/// A picture opened in a wide window (1280 by 844, a mouse's), held coming till the test gives it (`given`), how much
/// of it has come said as the test says it (`said`: the core's progress, as it calls it).
fn held_wide_preview(
  given : Map[String, () -> Unit],
  platform? : Int = 0,
  corner? : Double = 0.0,
  w? : Double = 1280.0,
  said? : Map[String, (Json) -> Unit] = {},
) -> @ui.Tester {
  new_run()
  let base = fixture("chat-preview-image")
  let src : Source = {
    ..base,
    read_going: fn(name, params, on_value, done) {
      if name == "station.file" {
        said[text(Some(params), "name")] = on_value
        given[text(Some(params), "name")] = fn() { (base.read_going)(name, params, on_value, done) }
      } else {
        (base.read_going)(name, params, on_value, done)
      }
    },
  }
  preview_src.val = Some(src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=844.0, platform~, window_corner=corner)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The bar across the top of a wide window, the window told it has none of the system's title bar or has (`inset`),
/// a frame drawn: where its way back starts (-1: none), whether a press on its blank (between the way back and the name) moved
/// the window, whether the bars still show after it, the viewer open; how far in from the window's side its last tool (download) ends,
/// where it has one (-1 none: a picture coming has none).
fn wide_bar_inset(t : @ui.Tester, v : Viewer, inset : Bool) -> ((Double, Bool, Bool), Double) raise {
  t.set_window_inset(inset)
  t.draw()
  // (none: -1, the bar gone)
  let back = match t.all(Button, label=v.desk_back(preview_src.val.unwrap())) {
    [b, ..] => b.rect
    [] => (-1.0, -1.0, 0.0, 0.0)
  }
  let last = match t.all(Button, label=@sf.t("web-main.preview.download")) {
    [d, ..] => 1280.0 - (d.rect.0 + d.rect.2)
    [] => -1.0
  }
  let before = t.window_drags()
  let (x, y) = (dmax(back.0, 0.0) + back.2 + 100.0, @sf.viewer_bar_h / 2.0)
  t.touch(0, x, y)
  t.touch(2, x, y)
  t.draw()
  // (and whether the viewer is still open: a press passed under the bar, round the picture, would close it)
  ((back.0, t.window_drags() > before, v.bars_shown() && viewer.get() is Some(_)), last)
}

///|
test "viewer on the tree, a wide window, the bar across the top the same coming and whole, the window gone full screen and back (its title bar the system's, then the app's again), the same viewer, on a Mac and on Windows: clear of the window's buttons at its left (a Mac's) while they are in it, its last tool clear of them at its right (Windows', the app's own) while they are, else at the window's corner; a press on its blank moving the window then, nothing under it taking the press" {
  for platform in [0, 3] {
    let given : Map[String, () -> Unit] = {}
    let t = held_wide_preview(given, platform~)
    let v = viewer.get().unwrap()
    assert_true(v.coming() && v.in_tree, msg="\{platform}: coming, the tree's viewer")
    // (while it comes: the bar across the top as it is then, the same bar's as once it is whole)
    let old = []
    for inset in [true, false, true] {
      old.push(wide_bar_inset(t, v, inset).0)
    }
    (given.get(v.file.name).unwrap())()
    t.draw()
    t.run_for(@kit.progress_known_ms)
    assert_true(!v.coming(), msg="\{platform}: whole")
    assert_true(@sfbase.bar_as_nodes(v, 1280.0), msg="\{platform}: whole, the bar its nodes")
    let node = []
    let last = []
    for inset in [true, false, true] {
      let (n, l) = wide_bar_inset(t, v, inset)
      node.push(n)
      last.push(l)
      // (where a page's bar's last stands, the window so: clear of its own buttons where they are the app's, else at
      // its corner)
      let want = if @ui.window_keys_own() {
        @sf.window_keys_room_at(1280.0) + @sf.viewer_bar_in
      } else {
        @sf.window_end_in(@sf.viewer_bar_in)
      }
      assert_true((l - want).abs() < 0.001, msg="\{platform}, inset \{inset}: its last tool \{l} in, as a page's bar's last: \{want}")
    }
    assert_true(viewer.get().map(fn(now) { physical_equal(now, v) }).unwrap_or(false), msg="\{platform}: the same viewer")
    assert_eq(node, old, msg="\{platform}: whole as while it came: \{node} and \{old}")
    assert_true(old[0].1 && !old[1].1 && old[2].1 && old[0].2 && old[1].2, msg="\{platform}: moved while inset: \{old}")
    if platform == 0 {
      assert_true(old[0].0 > old[1].0, msg="a Mac's: clear of its buttons at the left while inset: \{old}")
    } else {
      assert_true(last[0] > last[1] && last[2] == last[0], msg="Windows': clear of its buttons at the right while inset: \{last}")
    }
  }
}

///|
/// Whether the bar across the top is drawn out of the way (none of it drawn, or all of it up past the window's top).
fn wide_bar_out(t : @ui.Tester) -> Bool {
  match wide_bar_top(t) {
    None => true
    Some(y) => y <= -@sf.viewer_bar_h
  }
}

///|
test "viewer on the tree, a wide window, a mouse, motion reduced: a click on the picture hides the bar across the top at once, the next shows it at once, the first frame after each where it goes; nothing read of the clock after" {
  let t = wide_preview()
  // (as the settings set it: this device's motion reduced, read by the app each frame)
  (preview_src.val.unwrap().call)("prefs.set", { "motion": "reduce" }, fn(_) {  })
  t.draw()
  assert_true(@ui.current().still(), msg="motion reduced")
  let v = viewer.get().unwrap()
  assert_eq(wide_bar_top(t), Some(0.0), msg="there")
  let (x, y, w, h) = v.zoom.rect().unwrap()
  let click = fn() {
    t.touch(0, x + w / 2.0, y + h / 2.0)
    t.touch(2, x + w / 2.0, y + h / 2.0)
    t.draw()
  }
  click()
  let out = wide_bar_out(t)
  let ticking_out = @ui.view_tree().unwrap().clock_read()
  // (the next click no second of a double one)
  t.advance(double_tap_ms * 2.0)
  click()
  let back = wide_bar_top(t)
  let ticking_back = @ui.view_tree().unwrap().clock_read()
  (preview_src.val.unwrap().call)("prefs.set", { "motion": Json::null() }, fn(_) {  })
  t.draw()
  assert_true(out, msg="hidden: out of the way in the first frame")
  assert_eq(back, Some(0.0), msg="shown again: there in the first frame")
  assert_true(!ticking_out && !ticking_back, msg="nothing read of the clock after: \{ticking_out} \{ticking_back}")
}

///|
/// Where the middle of the file's name is drawn across the window: the window's tree's words, else the old bar's.
fn wide_name_middle(t : @ui.Tester, name : String) -> Double {
  for d in @ui.view_tree().unwrap().drawn() {
    if d.words == name && d.alpha > 0.0 {
      return d.x + d.w / 2.0
    }
  }
  for w in t.words() {
    if w.0 == name && w.5 > 0.0 {
      return w.1 + w.3 / 2.0
    }
  }
  -1.0
}

///|
test "viewer on the tree, a wide window, the bar across the top: its file's name in the window's middle, coming and whole, however wide the way back and the tools are" {
  let given : Map[String, () -> Unit] = {}
  let t = held_wide_preview(given)
  let v = viewer.get().unwrap()
  assert_true(v.coming(), msg="coming")
  let old = wide_name_middle(t, v.file.name)
  (given.get(v.file.name).unwrap())()
  t.draw()
  t.run_for(@kit.progress_known_ms)
  assert_true(@sfbase.bar_as_nodes(v, 1280.0), msg="whole: the bar its nodes")
  let node = wide_name_middle(t, v.file.name)
  assert_true(old > 0.0 && (old - 640.0).abs() < 1.0, msg="coming: in the middle: \{old}")
  assert_true((node - old).abs() < 0.5, msg="whole: where it was while it came: \{node} and \{old}")
}

///|
test "viewer on the tree, a wide window, the bar across the top: its last tool as far in from the window's side as a page's bar's last, on a Mac (its window's corner 16, followed), on Windows 11 (8, too square to follow) and on an Android tablet (none), 1280 wide and 840" {
  for (platform, corner, w) in [(0, 16.0, 1280.0), (3, 8.0, 1280.0), (2, 0.0, 1280.0), (2, 0.0, 840.0)] {
    let given : Map[String, () -> Unit] = {}
    let t = held_wide_preview(given, platform~, corner~, w~)
    let v = viewer.get().unwrap()
    (given.get(v.file.name).unwrap())()
    t.draw()
    t.run_for(@kit.progress_known_ms)
    assert_true(@sfbase.bar_as_nodes(v, w), msg="\{platform} \{w}: whole, the bar its nodes")
    let last = match t.all(Button, label=@sf.t("web-main.preview.download")) {
      [d, ..] => w - (d.rect.0 + d.rect.2)
      [] => -1.0
    }
    // (a page's bar's last, as the old views have it: the window's corner and the theme's ranges as they ask them)
    let want = @sf.window_end_in(@sf.viewer_bar_in)
    assert_true(
      (last - want).abs() < 0.001,
      msg="\{platform} \{w}: its last tool \{last} in, a page's bar's \{want}; roots \{@ui.tree_corner_roots_now()} and \{@ui.corner_roots()}",
    )
  }
}

///|
test "viewer on the tree, a window 600 wide (a Mac's, not a small screen), the bar across the top: its tools, no zoom's tools (zoomed by the hand and the keys)" {
  let t = preview_tester("image", w=600.0, platform=0)
  let v = viewer.get().unwrap()
  assert_true(@sfbase.bar_as_nodes(v, 600.0), msg="whole: the bar its nodes")
  for l in [@sf.t("web-main.preview.zoomOutKey"), @sf.t("web-main.preview.fitKey"), @sf.t("web-main.preview.zoomInKey"), @sf.t("web-main.preview.actualKey")] {
    assert_eq(t.all(Button, label=l).length(), 0, msg="no \{l}")
  }
  for l in [@sf.t("web-main.annotate.image"), @sf.t("common.copy"), @sf.t("web-main.preview.download")] {
    assert_eq(t.all(Button, label=l).length(), 1, msg="\{l}")
  }
}

///|
test "viewer on the tree, an Android tablet 840 wide, a picture whose name is far longer than the bar's middle: the bar's tools whole, its last as far in as a page's bar's last; the way back clear of them" {
  let t = preview_tester("long", w=840.0, platform=2)
  let v = viewer.get().unwrap()
  assert_true(@sfbase.bar_as_nodes(v, 840.0), msg="whole: the bar its nodes")
  let rect = fn(l : String) {
    match t.all(Button, label=l) {
      [d, ..] => d.rect
      [] => (-1.0, -1.0, -1.0, -1.0)
    }
  }
  let first = rect(@sf.t("web-main.annotate.image"))
  let last = rect(@sf.t("web-main.preview.download"))
  let back = rect(v.desk_back(preview_src.val.unwrap()))
  // (what is beside the name, the row's own room and its gaps out, halved: what each side would have alike)
  let mut middle = 0.0
  for d in @ui.view_tree().unwrap().drawn() {
    if d.words == v.file.name || d.words == @sfbase.vf_meta(v, preview_src.val.unwrap()) {
      middle = dmax(middle, d.w)
    }
  }
  // (the middle no wider than the bar lets it be: the window's width less 320)
  let middle = dmin(middle, 840.0 - 320.0)
  let end_in = @sf.window_end_in(@sf.viewer_bar_in)
  let half = (840.0 - @sf.viewer_bar_in - end_in - 2.0 * 16.0 - middle) / 2.0
  let tools = last.0 + last.2 - first.0
  assert_true(tools > 0.0 && tools <= half, msg="the tools whole, within what is beside the name: \{tools} and \{half}")
  assert_true((840.0 - (last.0 + last.2) - end_in).abs() < 0.001, msg="its last tool \{840.0 - (last.0 + last.2)} in, a page's bar's \{end_in}")
  assert_true(back.0 + back.2 <= first.0, msg="the way back clear of the tools: \{back} and \{first}")
}

///|
/// A picture `what` (the fixture's chat-preview-…) opened in a wide window `w` wide on `platform` (0 a Mac, 3 Windows),
/// the window's buttons in the app's top row (inset), the system's words `fs`; held coming while `hold` (how much has
/// come said once: 1 KB of 4 KB); else whole. Where the bar across the top has its way back, each of its tools, its
/// progress bar and the words beside it (each x, w; none: (-1, 0)), and whether it is as `hold` says and the bar its
/// nodes ("nodes" 1, else 0).
fn wide_bar_room(what : String, w : Double, platform : Int, fs : Double, hold : Bool) -> Map[String, (Double, Double)] raise {
  new_run()
  let base = fixture("chat-preview-" + what)
  let said : Map[String, (Json) -> Unit] = {}
  let src : Source = {
    ..base,
    read_going: fn(name, params, on_value, done) {
      if hold && name == "station.file" {
        said[text(Some(params), "name")] = on_value
      } else {
        (base.read_going)(name, params, on_value, done)
      }
    },
  }
  preview_src.val = Some(src)
  // (opened 1280 wide, then the window made `w` wide: the chat under it opening the picture at 840 on a Mac, its
  // buttons in it, draws a message over the field's hint for a frame (words_over), as on main: no part of the bar's)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=844.0, platform~, window_corner=if platform == 0 { 16.0 } else { 8.0 })
  t.set_window_inset(true)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.resize(w, 844.0)
  t.draw()
  // (the system's words said once it is open: the bar measured again by them, nothing under it moving meanwhile)
  t.set_font_scale(fs)
  t.draw()
  let v = viewer.get().unwrap()
  if hold {
    (said.get(v.file.name).unwrap())({ "loaded": 1024.0, "total": 4096.0 })
    t.draw()
  }
  t.run_for(@kit.progress_known_ms)
  let out : Map[String, (Double, Double)] = {}
  // (coming and the bar its nodes: 1; else 0)
  out["nodes"] = (if v.coming() == hold && @sfbase.bar_as_nodes(v, w) { 1.0 } else { 0.0 }, 0.0)
  let at = fn(k : String, l : String) {
    out[k] = match t.all(Button, label=l) {
      [b, ..] => (b.rect.0, b.rect.2)
      [] => (-1.0, 0.0)
    }
  }
  at("back", v.desk_back(src))
  at("mark", @sf.t("web-main.annotate.image"))
  at("copy", @sf.t("common.copy"))
  at("download", @sf.t("web-main.preview.download"))
  out["bar"] = match t.all(ProgressBar) {
    [b, ..] => (b.rect.0, b.rect.2)
    [] => (-1.0, 0.0)
  }
  out["words"] = (-1.0, 0.0)
  for d in @ui.view_tree().unwrap().drawn() {
    if d.words.has_prefix("正在读取") && d.alpha > 0.0 {
      out["words"] = (d.x, d.w)
    }
  }
  out
}

///|
test "viewer on the tree, the bar across the top, a name far longer than its middle, on a Mac and on Windows with the window's buttons in it, the system's words 1 and 1.3, 700, 840 and 1280 wide: whole, its tools whole and its last where a page's bar's last is, the way back clear of them and where it is with a short name; coming, how much has come in words and its bar as whole as with a short name, clear of the window's buttons" {
  let seen = []
  for platform in [0, 3] {
    for fs in [1.0, 1.3] {
      for w in [700.0, 840.0, 1280.0] {
        for hold in [false, true] {
          let short = wide_bar_room("image", w, platform, fs, hold)
          let long = wide_bar_room("long", w, platform, fs, hold)
          let end_in = if platform == 3 {
            @sf.window_keys_room_at(w) + @sf.viewer_bar_in
          } else {
            @sf.window_end_in(@sf.viewer_bar_in)
          }
          let at = "platform \{platform}, words \{fs}, \{w} wide, \{if hold { "coming" } else { "whole" }}"
          let get = fn(m : Map[String, (Double, Double)], k : String) { m.get(k).unwrap_or((-1.0, 0.0)) }
          if get(short, "nodes").0 != 1.0 || get(long, "nodes").0 != 1.0 {
            fail("\{at}: the bar not its nodes")
          }
          if hold {
            let (sbx, sbw) = get(short, "bar")
            let (_, sww) = get(short, "words")
            if sbx < 0.0 || sbw != 120.0 || sww <= 0.0 {
              fail("\{at}: the short name's words and bar not there to measure by: \{get(short, "bar")} \{get(short, "words")}")
            }
            let (bx, bw) = get(long, "bar")
            let (wx, ww) = get(long, "words")
            seen.push(
              "\{at}: bar \{(bx, bw)} (short \{get(short, "bar")}), words \{(wx, ww)} (short \{get(short, "words")}), ends \{w - (bx + bw)} in, want ≥ \{end_in}; back \{get(long, "back")}",
            )
            if bw != get(short, "bar").1 || ww != get(short, "words").1 || ww <= 0.0 {
              fail("\{at}: the words or the bar cut: \{seen.last()}")
            }
            if w - (bx + bw) < end_in - 0.001 {
              fail("\{at}: over the window's buttons: \{seen.last()}")
            }
          } else {
            let (mx, mw) = get(long, "mark")
            let (dx, dw) = get(long, "download")
            let (cx, cw) = get(long, "copy")
            let (kx, kw) = get(long, "back")
            seen.push("\{at}: mark \{(mx, mw)}, copy \{(cx, cw)}, download \{(dx, dw)}, ends \{w - (dx + dw)} in, want \{end_in}; back \{(kx, kw)} (short \{get(short, "back")})")
            if mw != @sf.tool_side || cw != @sf.tool_side || dw != @sf.tool_side {
              fail("\{at}: a tool cut: \{seen.last()}")
            }
            if (w - (dx + dw) - end_in).abs() > 0.001 {
              fail("\{at}: its last not where a page's bar's last is: \{seen.last()}")
            }
            if kx + kw > mx + 0.001 || kx != get(short, "back").0 {
              fail("\{at}: the way back over the tools or moved: \{seen.last()}")
            }
          }
        }
      }
    }
  }
  ignore(seen)
}

///|
/// A picture beside others opened in a wide window (a mouse's), its way to the one after (the disc at its right)
/// clicked, then `after` ms later drawn (`frames`: the frames between at the display's pace; else none between): which
/// picture shows, and where the strip is then.
fn wide_step_after_click(frames : Bool, after : Double) -> (String, Double) raise {
  let t = preview_tester("step", w=1280.0, platform=0)
  assert_true(viewer.get().unwrap().in_tree, msg="the tree's viewer")
  let (x, y, w, h) = t.get(Button, label=@sf.t("web-main.preview.nextKey")).rect
  t.touch(0, x + w / 2.0, y + h / 2.0)
  t.touch(2, x + w / 2.0, y + h / 2.0)
  let clicked = t.time()
  // (as it is let go, no frame drawn: the one after the one shown)
  assert_true(viewer.get().unwrap().file.name != "界面草图.png", msg="let go: on to the one after at once")
  if frames {
    t.run_for(after)
  } else {
    t.advance(after)
    t.draw()
  }
  (viewer.get().unwrap().file.name, pv_strip.way.value_at(clicked + after))
}

///|
test "viewer on the tree, a wide window, a mouse: its way to the picture after clicked, the next one sliding in from the click's moment, as far by a moment the frames drawn between or none" {
  let half = @ui.move_most_ms / 2.0
  let drawn = wide_step_after_click(true, half)
  let none = wide_step_after_click(false, half)
  assert_true(drawn.0 != "界面草图.png", msg="frames: on to the one after: \{drawn}")
  assert_true(drawn.1 > 1.0, msg="frames: still sliding in: \{drawn}")
  assert_eq(none, drawn, msg="no frame between: the same one, as far in")
}

///|
/// The way to the picture after (the disc at the right of a wide window) as it is drawn: how far in (its alpha, its
/// ancestors' with it), None where none is drawn (the window's tree's node; else the old view's, by its key,
/// Tester::look_of).
fn after_disc(t : @ui.Tester) -> Double? {
  for d in @ui.view_tree().unwrap().drawn() {
    if d.glass is Some(_) && d.w == @ui.Space::px(S10) && d.x > 640.0 {
      return Some(d.alpha)
    }
  }
  t.look_of("preview/go/1").map(fn(l) { l.2 })
}

///|
/// The way to the picture after's ground as it is drawn (0: none): the node's, else the old view's box there.
fn after_disc_ground(t : @ui.Tester) -> Int64 {
  for d in @ui.view_tree().unwrap().drawn() {
    if d.glass is Some(_) && d.w == @ui.Space::px(S10) && d.x > 640.0 {
      return d.ground
    }
  }
  let mut out = 0L
  for r in t.drawn_rects() {
    if r.2 == @ui.Space::px(S10) && r.0 > 640.0 {
      out = r.4
    }
  }
  out
}

///|
test "viewer on the tree, a wide window, a mouse: its bars hidden, the way to the one after kept by the pointer over it; held down and moved off it past its going, still there and the press its; back on it and let go, one step" {
  let t = preview_tester("step", w=1280.0, platform=0)
  let v = viewer.get().unwrap()
  let (x, y, w, h) = t.get(Button, label=@sf.t("web-main.preview.nextKey")).rect
  let (dx, dy) = (x + w / 2.0, y + h / 2.0)
  // (the bars hidden by a click on the picture, the pointer on the disc as it goes: kept)
  let (rx, ry, rw, rh) = v.zoom.rect().unwrap()
  t.touch(0, rx + rw / 2.0, ry + rh / 2.0)
  t.touch(2, rx + rw / 2.0, ry + rh / 2.0)
  t.draw()
  assert_true(!v.bars_shown(), msg="its bars hidden")
  t.move(dx, dy)
  t.run_for(@sf.sleep_ms + @sf.wake_ms)
  assert_eq(after_disc(t), Some(1.0), msg="the pointer over it: there")
  // (held down on it, moved off it, past its going)
  t.touch(0, dx, dy)
  assert_true(@ui.pointing() is Mouse, msg="a mouse's")
  t.touch(1, dx - 300.0, dy)
  t.run_for(@sf.sleep_ms * 2.0)
  assert_eq(after_disc(t), Some(1.0), msg="held, moved off it: still there")
  assert_eq(after_disc_ground(t), 0L, msg="held, moved off it: no hover ground (the pointer not on it)")
  // (back on it, let go: one step)
  t.touch(1, dx, dy)
  t.touch(2, dx, dy)
  let name = viewer.get().unwrap().file.name
  assert_true(name != "界面草图.png", msg="let go on it: on to the one after")
  t.run_for(@ui.move_most_ms)
  assert_eq(viewer.get().unwrap().file.name, name, msg="one step")
}

///|
test "viewer on the tree, a wide window, a mouse: the way to the one after gone whole (its bars hidden, the pointer away), a click where it was steps nowhere" {
  let t = preview_tester("step", w=1280.0, platform=0)
  let v = viewer.get().unwrap()
  let (x, y, w, h) = t.get(Button, label=@sf.t("web-main.preview.nextKey")).rect
  let (rx, ry, rw, rh) = v.zoom.rect().unwrap()
  t.touch(0, rx + rw / 2.0, ry + rh / 2.0)
  t.touch(2, rx + rw / 2.0, ry + rh / 2.0)
  t.run_for(@sf.sleep_ms * 2.0)
  assert_eq(after_disc(t).unwrap_or(0.0), 0.0, msg="gone whole")
  t.touch(0, x + w / 2.0, y + h / 2.0)
  t.touch(2, x + w / 2.0, y + h / 2.0)
  t.draw()
  assert_true(viewer.get().map(fn(n) { n.file.name == "界面草图.png" }).unwrap_or(true), msg="no step")
}

///|
test "viewer on the tree, a wide window, motion reduced: its bars hidden by a click, the way to the one after gone in the first frame; the viewer closed as it would go, nothing read of the clock after" {
  let t = preview_tester("step", w=1280.0, platform=0)
  (preview_src.val.unwrap().call)("prefs.set", { "motion": "reduce" }, fn(_) {  })
  t.draw()
  let v = viewer.get().unwrap()
  let (rx, ry, rw, rh) = v.zoom.rect().unwrap()
  t.touch(0, rx + rw / 2.0, ry + rh / 2.0)
  t.touch(2, rx + rw / 2.0, ry + rh / 2.0)
  t.draw()
  let gone = after_disc(t)
  (preview_src.val.unwrap().call)("prefs.set", { "motion": Json::null() }, fn(_) {  })
  t.draw()
  assert_eq(gone.unwrap_or(0.0), 0.0, msg="gone in the first frame")
  // (its bars shown again, going in; closed by Escape meanwhile: nothing owed once it has gone)
  t.touch(0, rx + rw / 2.0, ry + rh / 2.0)
  t.touch(2, rx + rw / 2.0, ry + rh / 2.0)
  t.advance(@sf.wake_ms / 2.0)
  t.key_told(@ui.key_escape, 0, t.time())
  t.run_for(@ui.move_most_ms)
  t.run_for(@sfpages.reveal_ms)
  assert_true(viewer.get() is None && pv_leaving.get() is None, msg="closed")
  t.draw()
  assert_true(!@ui.view_tree().unwrap().clock_read(), msg="nothing read of the clock after")
}

///|
test "viewer on the tree, a wide window: the way to the picture after drawn with its shadow under its frosted glass (Base, outside it), as the old one is" {
  let t = preview_tester("step", w=1280.0, platform=0)
  let (blur, _) = @ui.Shadow::blur_y(Base)
  let disc = @ui.Space::px(S10)
  let cast = t.drawn_shadows().filter(fn(s) { s.2 == disc && s.0 > 640.0 })
  assert_eq(cast.length(), 1, msg="its shadow: \{t.drawn_shadows()}")
  assert_eq(cast[0].5, blur, msg="Base's blur")
}

///|
test "viewer on the tree, a wide window, transparency reduced: the way to the picture after on its glass's solid ground, no glass, its shadow under it (Base, one), as the old one is; back again, its glass" {
  let t = preview_tester("step", w=1280.0, platform=0)
  let disc = @ui.Space::px(S10)
  let (blur, _) = @ui.Shadow::blur_y(Base)
  let glass_there = fn() { t.drawn_glass().filter(fn(g) { g.2 == disc && g.0 > 640.0 }).length() }
  let solid_there = fn() {
    t.drawn_rects().filter(fn(r) { r.2 == disc && r.0 > 640.0 }).length()
  }
  let shadows = fn() { t.drawn_shadows().filter(fn(s) { s.2 == disc && s.0 > 640.0 }) }
  t.set_reduce_transparency(true)
  t.draw()
  let reduced = (glass_there(), solid_there(), shadows().map(fn(s) { s.5 }))
  t.set_reduce_transparency(false)
  t.draw()
  let back = (glass_there(), shadows().length())
  assert_eq(reduced, (0, 1, [blur]), msg="reduced: no glass, its solid ground, its shadow")
  assert_eq(back, (1, 1), msg="back: its glass, its shadow")
}

///|
test "viewer on the tree, a wide window, its picture coming: the bar across the top's way back clicked, the viewer closing as it is let go, no frame drawn after it" {
  let given : Map[String, () -> Unit] = {}
  let t = held_wide_preview(given)
  let v = viewer.get().unwrap()
  assert_true(v.coming() && v.in_tree, msg="coming, the tree's viewer")
  let (x, y, w, h) = t.get(Button, label=v.desk_back(preview_src.val.unwrap())).rect
  t.touch(0, x + w / 2.0, y + h / 2.0)
  t.touch(2, x + w / 2.0, y + h / 2.0)
  assert_true(v.closing, msg="let go: closing at once")
}

///|
test "viewer on the tree, a wide window, its picture coming as the core says it: not known, then known, then more, then whole; each as it is said (its bar read out), drawn so; whole, its bar gone and its tools there; closed while it comes, nothing read of the clock after" {
  let given : Map[String, () -> Unit] = {}
  let said : Map[String, (Json) -> Unit] = {}
  let t = held_wide_preview(given, said~)
  let v = viewer.get().unwrap()
  assert_true(v.coming() && @sfbase.bar_as_nodes(v, 1280.0), msg="coming: the bar its nodes")
  let bar = fn() {
    match t.all(ProgressBar) {
      [b] => Some((b.value, b.range))
      _ => None
    }
  }
  assert_eq(bar(), Some(("", None)), msg="not known: a bar that sweeps")
  assert_true(t.find(@sf.t("common.opening")) is Some(_), msg="not known: 正在打开")
  (said.get(v.file.name).unwrap())({ "loaded": 1024.0, "total": 4096.0 })
  assert_eq(bar(), Some(("25%", Some((0.0, 25.0, 100.0)))), msg="known: said at once")
  t.draw()
  assert_true(t.find("正在读取 1 KB / 4 KB") is Some(_), msg="known: in words")
  (said.get(v.file.name).unwrap())({ "loaded": 3072.0, "total": 4096.0 })
  assert_eq(bar(), Some(("75%", Some((0.0, 75.0, 100.0)))), msg="more: said at once")
  t.draw()
  assert_true(t.find("正在读取 3 KB / 4 KB") is Some(_), msg="more: in words")
  assert_eq(t.all(Button, label=@sf.t("common.copy")).length(), 0, msg="coming: no copy")
  (given.get(v.file.name).unwrap())()
  t.draw()
  t.run_for(@kit.progress_known_ms)
  assert_true(!v.coming(), msg="whole")
  assert_eq(bar(), None, msg="whole: its bar gone")
  assert_true(t.find("正在读取") is None, msg="whole: its words gone")
  assert_eq(t.all(Button, label=@sf.t("common.copy")).length(), 1, msg="whole: its copy")
  // (another, closed while it comes)
  let given2 : Map[String, () -> Unit] = {}
  let t2 = held_wide_preview(given2)
  let v2 = viewer.get().unwrap()
  assert_true(v2.coming(), msg="coming again")
  t2.key_told(@ui.key_escape, 0, t2.time())
  t2.run_for(@ui.move_most_ms)
  t2.run_for(@sfpages.reveal_ms)
  assert_true(viewer.get() is None && pv_leaving.get() is None, msg="closed while it comes")
  t2.draw()
  let tree = @ui.view_tree().unwrap()
  assert_true(!tree.clock_read() && !tree.cycle_read(), msg="nothing read of the clock after")
}

///|
/// A picture opened in a wide window (a mouse's, said so by the host), marking begun from its bar (标注图片), then the
/// pen taken up from the marking's tools by a click: the tool as that click is let go (no frame drawn); a stroke drawn
/// across the picture by the mouse straight after (`frames`: a frame drawn between the click and the stroke; else
/// none): the kinds of the marks made, and how many undos they are.
fn wide_pen_then_stroke(frames : Bool) -> (@sfbase.MarkTool, Array[String], Int) raise {
  let t = preview_tester("image", w=1280.0, platform=0)
  t.host_says_finger(Some(false))
  let v = viewer.get().unwrap()
  assert_true(v.in_tree, msg="the tree's viewer")
  let click = fn(label : String) raise {
    let (x, y, w, h) = t.get(Button, label~).rect
    t.touch(0, x + w / 2.0, y + h / 2.0)
    assert_true(@ui.pointing() is Mouse, msg="a mouse's")
    t.touch(2, x + w / 2.0, y + h / 2.0)
  }
  click(@sf.t("web-main.annotate.image"))
  t.draw()
  assert_true(marking.on, msg="marking")
  let past = marking.past.length()
  click(pv("android-chat.marks.tool.pen"))
  let taken = marking.tool
  if frames {
    t.draw()
  }
  let (rx, ry, rw, rh) = v.zoom.rect().unwrap()
  let (x, y) = (rx + rw / 3.0, ry + rh / 3.0)
  t.touch(0, x, y)
  for i in 1..=4 {
    t.touch(1, x + 20.0 * i.to_double(), y + 10.0 * i.to_double())
  }
  t.touch(2, x + 80.0, y + 40.0)
  t.draw()
  (taken, marking.shapes.map(fn(s) { s.kind }), marking.past.length() - past)
}

///|
test "viewer on the tree, a wide window, marking: the pen taken up as its click is let go, a stroke drawn straight after it the pen's, one undo of it; the frames drawn between or none" {
  for frames in [true, false] {
    let (taken, kinds, undos) = wide_pen_then_stroke(frames)
    assert_true(taken == Pen, msg="frames \{frames}: the pen as the click is let go")
    assert_eq(kinds, ["pen"], msg="frames \{frames}: the pen's mark")
    assert_eq(undos, 1, msg="frames \{frames}: one undo")
  }
}

///|
test "viewer on the tree, a wide window, marking: a tool held down and not let go, or its press called off, takes nothing up; let go on it, taken up once" {
  let t = preview_tester("image", w=1280.0, platform=0)
  t.host_says_finger(Some(false))
  let (ax, ay, aw, ah) = t.get(Button, label=@sf.t("web-main.annotate.image")).rect
  t.touch(0, ax + aw / 2.0, ay + ah / 2.0)
  t.touch(2, ax + aw / 2.0, ay + ah / 2.0)
  t.draw()
  let (x, y, w, h) = t.get(Button, label=pv("android-chat.marks.tool.pen")).rect
  let (cx, cy) = (x + w / 2.0, y + h / 2.0)
  t.touch(0, cx, cy)
  assert_true(marking.tool == Rect, msg="down, not let go: as it was")
  t.touch(3, cx, cy)
  t.draw()
  assert_true(marking.tool == Rect, msg="called off: as it was")
  let past = marking.past.length()
  t.touch(0, cx, cy)
  t.touch(2, cx, cy)
  assert_true(marking.tool == Pen, msg="let go on it: the pen")
  assert_eq(marking.past.length(), past, msg="nothing to undo for it")
  t.draw()
  assert_true(marking.tool == Pen, msg="the frame after: still the pen")
}

///|
test "viewer on the tree, a wide window, marking: a box drawn, what to say of it asked at once in the tools' place; said done, its note's card shown over the tools in the frame after; undone from the tools, the card gone in the frame after; redone and undone with no input at all, the card back and gone in the frame after" {
  let t = preview_tester("image", w=1280.0, platform=0)
  t.host_says_finger(Some(false))
  let v = viewer.get().unwrap()
  let (ax, ay, aw, ah) = t.get(Button, label=@sf.t("web-main.annotate.image")).rect
  t.touch(0, ax + aw / 2.0, ay + ah / 2.0)
  t.touch(2, ax + aw / 2.0, ay + ah / 2.0)
  t.draw()
  assert_true(marking.on && marking.tool == Rect, msg="marking, the box")
  let card = pv("android-chat.annotate.quoteOnly")
  assert_true(t.find(card) is None, msg="no card yet")
  let (rx, ry, rw, rh) = v.zoom.rect().unwrap()
  let (x, y) = (rx + rw / 3.0, ry + rh / 3.0)
  t.touch(0, x, y)
  t.touch(1, x + 60.0, y + 40.0)
  t.touch(2, x + 60.0, y + 40.0)
  t.draw()
  assert_eq(marking.shapes.map(fn(s) { s.kind }), ["box"], msg="a box")
  let undo = pv("android-chat.marks.undo")
  assert_true(t.find(card) is None && t.all(Button, label=undo).length() == 0, msg="its note asked: no card, no tools")
  let (dx, dy, dw, dh) = t.get(Button, label=pv("android-chat.annotate.done")).rect
  t.touch(0, dx + dw / 2.0, dy + dh / 2.0)
  t.touch(2, dx + dw / 2.0, dy + dh / 2.0)
  t.draw()
  assert_true(marking.note < 0, msg="said done")
  assert_true(t.find(card) is Some(_), msg="its card shown")
  let (ux, uy, uw, uh) = t.get(Button, label=undo).rect
  t.touch(0, ux + uw / 2.0, uy + uh / 2.0)
  t.touch(2, ux + uw / 2.0, uy + uh / 2.0)
  t.draw()
  assert_eq(marking.shapes.length(), 0, msg="undone")
  assert_true(t.find(card) is None, msg="its card gone")
  // (marking changed with no input at all, the frame after drawn as the host draws it, no step of the test's: the
  // notes follow marking itself, not what an input builds again; a host's frame first, nothing changed: parts kept on it
  // (the frame's, not the notes' alone: the notes' own kept is what the whole-build check holds the next frame to))
  t.frame_at(t.time() + t.frame_period())
  assert_true(t.parts_kept() > 0, msg="a host's frame, nothing changed: its parts kept (\{t.parts_kept()}), built \{t.built_why()}")
  @sfbase.marks_redo()
  t.frame_at(t.time() + t.frame_period())
  assert_eq(marking.shapes.length(), 1, msg="redone, no input")
  assert_true(t.find(card) is Some(_), msg="redone, no input: its card back in the frame after")
  @sfbase.marks_undo()
  t.frame_at(t.time() + t.frame_period())
  assert_true(t.find(card) is None, msg="undone, no input: its card gone in the frame after")
}
