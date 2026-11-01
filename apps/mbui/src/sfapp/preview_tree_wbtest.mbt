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
test "viewer on the tree: pinched, the picture drawn bigger by its node" {
  // (a phone's: its fingers the hand all along)
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
  let main = "mem:preview/" + viewer.get().unwrap().id()
  let w0 = nodes_of(main).map(fn(r) { r.2 })
  assert_eq(w0.length(), 1, msg="lying flat, its node's")
  // the one beside it decoded, out of sight (the frame after its word, as the display draws it, nothing else said)
  // (frames drawn as the display draws them, at moments said: none of the test's own stepping, run_for's, which builds
  // every part anew)
  t.finish_all()
  display_frame(t)
  t.frame_at(t.time() + @ui.image_fade_ms)
  // pinched: drawn bigger by its node as it goes
  let t0 = t.time()
  told_by(t, t0, [(0, 0, 150.0, 422.0, 10.0), (0, 1, 240.0, 422.0, 20.0), (1, 1, 300.0, 422.0, 40.0), (1, 1, 330.0, 422.0, 60.0), (2, 0, 150.0, 422.0, 80.0), (2, 1, 330.0, 422.0, 90.0)], At([30.0, 50.0, 70.0]))
  t.frame_at(t0 + 90.0 + @ui.move_most_ms)
  let w1 = nodes_of(main).map(fn(r) { r.2 })
  assert_true(w1.length() == 1 && w1[0] > w0[0], msg="drawn bigger by its node: \{w0} \{w1}")
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
  (v.lift.starts_at() - (t0 + 30.0), v.lift.target(), should, v.marks_rect(t0 + 200.0))
}

///|
test "viewer on the tree, marking: the keyboard up as words are written on a gliding picture: lifted from the keyboard's moment, as far as keeps them clear of it where the picture is then, a finger placed by the same lift, whatever frame came last or was drawn ahead" {
  let at = lifted_for_words(-1.0, 0.0)
  assert_eq(lifted_for_words(20.0, 0.0), at)
  assert_eq(lifted_for_words(-1.0, 40.0), at)
  assert_eq(lifted_for_words(20.0, 40.0), at)
  // (set out at the keyboard's moment)
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

///|
/// A picture opened in a wide window (a mouse), marking: its top bar's 取消 clicked (`frames`: the frame after drawn
/// before what is looked at; else none): whether marking is still on as the click is let go, and after.
fn wide_marking_cancel(frames : Bool) -> (Bool, Bool) raise {
  let t = preview_tester("image", w=1280.0, platform=0)
  t.host_says_finger(Some(false))
  let click = fn(label : String) raise {
    let (x, y, w, h) = t.get(Button, label~).rect
    t.touch(0, x + w / 2.0, y + h / 2.0)
    t.touch(2, x + w / 2.0, y + h / 2.0)
  }
  click(@sf.t("web-main.annotate.image"))
  t.draw()
  assert_true(marking.on, msg="marking")
  click(pv("common.cancel"))
  let let_go = marking.on
  if frames {
    t.draw()
  }
  (let_go, marking.on)
}

///|
test "viewer on the tree, a wide window, marking: its top bar the tree's; 取消 leaves marking as its click is let go, the frames drawn after or none" {
  for frames in [true, false] {
    let (let_go, after) = wide_marking_cancel(frames)
    assert_true(!let_go, msg="frames \{frames}: marking left as the click is let go")
    assert_true(!after, msg="frames \{frames}: left")
  }
  let t = preview_tester("image", w=1280.0, platform=0)
  t.host_says_finger(Some(false))
  let v = viewer.get().unwrap()
  let (x, y, w, h) = t.get(Button, label=@sf.t("web-main.annotate.image")).rect
  t.touch(0, x + w / 2.0, y + h / 2.0)
  t.touch(2, x + w / 2.0, y + h / 2.0)
  t.draw()
  assert_true(@sfbase.bar_as_nodes(v, 1280.0), msg="marking: the bar across the top its nodes")
  // (nothing drawn: 下载 unable; a box drawn, able)
  let download = pv("android-chat.marks.downloadMarked")
  assert_true(t.get(Button, label=download).disabled, msg="nothing drawn: 下载 unable")
  let (rx, ry, rw, rh) = v.zoom.rect().unwrap()
  let (px, py) = (rx + rw / 3.0, ry + rh / 3.0)
  t.touch(0, px, py)
  t.touch(1, px + 60.0, py + 40.0)
  t.touch(2, px + 60.0, py + 40.0)
  t.draw()
  let (dx, dy, dw, dh) = t.get(Button, label=pv("android-chat.annotate.done")).rect
  t.touch(0, dx + dw / 2.0, dy + dh / 2.0)
  t.touch(2, dx + dw / 2.0, dy + dh / 2.0)
  t.draw()
  assert_true(!t.get(Button, label=download).disabled, msg="a box drawn: 下载 able")
}

///|
/// A picture opened in a wide window (a mouse), marking: the tester, the viewer, and a click at a labelled button's
/// middle (pressed and let go, no frame after).
fn wide_marking() -> (@ui.Tester, Viewer, (String) -> Unit raise) raise {
  let t = preview_tester("image", w=1280.0, platform=0)
  t.host_says_finger(Some(false))
  let click = fn(label : String) raise {
    let (x, y, w, h) = t.get(Button, label~).rect
    t.touch(0, x + w / 2.0, y + h / 2.0)
    t.touch(2, x + w / 2.0, y + h / 2.0)
  }
  click(@sf.t("web-main.annotate.image"))
  t.draw()
  assert_true(marking.on, msg="marking")
  (t, viewer.get().unwrap(), click)
}

///|
test "viewer on the tree, a wide window, marking's 下载: nothing drawn, nothing made; a box drawn, clicked twice with no frame between, the marked picture asked for once, being made from the first" {
  let (t, v, click) = wide_marking()
  let download = pv("android-chat.marks.downloadMarked")
  click(download)
  t.draw()
  assert_eq(t.marks_drawn().length(), 0, msg="nothing drawn: nothing made")
  assert_true(!marking.busy, msg="nothing drawn: not making")
  let (rx, ry, rw, rh) = v.zoom.rect().unwrap()
  let (px, py) = (rx + rw / 3.0, ry + rh / 3.0)
  t.touch(0, px, py)
  t.touch(1, px + 60.0, py + 40.0)
  t.touch(2, px + 60.0, py + 40.0)
  t.draw()
  click(pv("android-chat.annotate.done"))
  t.draw()
  click(download)
  assert_true(marking.busy, msg="let go: being made at once")
  click(download)
  t.draw()
  let drawn = t.marks_drawn()
  assert_eq(drawn.length(), 1, msg="twice, no frame between: asked for once")
  assert_eq(items(Some(@json.parse(drawn[0])), "marks").length(), 1, msg="the box")
}

///|
test "viewer on the tree, a wide window, marking's 下载 with words being written: able as words come to be and unable as they go, told with no frame between; the words put down first, the marked picture made with them, once" {
  let (t, v, click) = wide_marking()
  click(pv("android-chat.marks.tool.text"))
  t.draw()
  let (rx, ry, rw, rh) = v.zoom.rect().unwrap()
  t.touch(0, rx + rw / 3.0, ry + rh / 3.0)
  t.touch(2, rx + rw / 3.0, ry + rh / 3.0)
  t.draw()
  assert_true(marking.writing is Some(_), msg="writing")
  let download = pv("android-chat.marks.downloadMarked")
  // (a word typed and taken out again, told with no frame between: nothing to keep, nothing made)
  t.text_told("看", t.time())
  t.key_told(@ui.key_code_backspace, 0, t.time())
  click(download)
  assert_eq(t.marks_drawn().length(), 0, msg="typed and taken out, no frame between: nothing made")
  assert_true(!marking.busy, msg="typed and taken out: not making")
  // (words typed, no frame between: made with them, once)
  t.text_told("看这里", t.time())
  click(download)
  assert_true(marking.busy, msg="words typed, no frame between: being made as the click is let go")
  click(pv("android-chat.marks.downloadMarked"))
  t.draw()
  let drawn = t.marks_drawn()
  assert_eq(drawn.length(), 1, msg="made once: \{drawn}")
  assert_true(drawn[0].contains("看这里"), msg="with the words: \{drawn[0]}")
  assert_true(marking.writing is None, msg="the words put down")
}

///|
test "viewer on the tree, a wide window, a picture of a chat's marked: 添加到对话 clicked twice with no frame between, the marked picture asked for once, being made from the first; made, put in that chat's draft once, the viewer closed back to it" {
  let t = preview_tester("step", w=1280.0, platform=0)
  t.host_says_finger(Some(false))
  let (a, _) = preview_files().iter().find_first(fn(f) { f.0.name == "界面草图.png" }).unwrap()
  open_preview("ws1/st1", "s-c1", a, steps=InChat(Some(1.0), "s-c1"))
  t.run_for(@ui.move_most_ms)
  let click = fn(label : String) raise {
    let (x, y, w, h) = t.get(Button, label~).rect
    t.touch(0, x + w / 2.0, y + h / 2.0)
    t.touch(2, x + w / 2.0, y + h / 2.0)
  }
  click(@sf.t("web-main.annotate.image"))
  t.draw()
  let v = viewer.get().unwrap()
  assert_true(marking.on && v.draft_key() == "ws1/st1:s-c1", msg="marking, a draft to put it in: \{v.draft_key()}")
  let (rx, ry, rw, rh) = v.zoom.rect().unwrap()
  let (px, py) = (rx + rw / 3.0, ry + rh / 3.0)
  t.touch(0, px, py)
  t.touch(1, px + 60.0, py + 40.0)
  t.touch(2, px + 60.0, py + 40.0)
  t.draw()
  click(pv("android-chat.annotate.done"))
  t.draw()
  let put = pv("android-chat.preview.put")
  let quoted = fn() { @sfbase.writings.get("ws1/st1:s-c1").map(fn(w) { w.quotes.length() }).unwrap_or(0) }
  let before = quoted()
  click(put)
  assert_true(marking.busy && marking.to_draft, msg="let go: being made for the draft at once")
  click(pv("android-chat.marks.making"))
  t.run_for(@ui.move_most_ms)
  assert_eq(t.marks_drawn().length(), 1, msg="twice, no frame between: asked for once")
  assert_true(viewer.get() is None, msg="made: the viewer closed back to the chat")
  assert_eq(quoted() - before, 1, msg="put in the chat's draft once")
}

///|
/// Marking on a wide window, a box drawn: its note asked for at once, what is said of it written (no frame between):
/// the tester, the viewer, the clicker, the box's id.
fn wide_box_noted(said : String) -> (@ui.Tester, Viewer, (String) -> Unit raise, Int) raise {
  let (t, v, click) = wide_marking()
  let (rx, ry, rw, rh) = v.zoom.rect().unwrap()
  let (px, py) = (rx + rw / 3.0, ry + rh / 3.0)
  t.touch(0, px, py)
  t.touch(1, px + 60.0, py + 40.0)
  t.touch(2, px + 60.0, py + 40.0)
  t.draw()
  assert_true(marking.note >= 0, msg="its note asked for")
  let id = marking.note
  if said != "" {
    t.text_told(said, t.time())
  }
  (t, v, click, id)
}

///|
test "viewer on the tree, a wide window, marking: a box's note written and its 完成 clicked: what is said of it kept and the note closed as the click is let go, before any frame; closed after a frame" {
  let (t, _, click, id) = wide_box_noted("这里对齐")
  click(pv("android-chat.annotate.done"))
  assert_eq(marking.comments.get(id), Some("这里对齐"), msg="let go: what is said of it kept")
  assert_true(marking.note < 0, msg="let go: the note closed")
  t.draw()
  assert_true(marking.note < 0, msg="a frame after: closed")
  assert_eq(marking.comments.get(id), Some("这里对齐"), msg="a frame after: kept")
}

///|
/// Marking on a wide window, a box drawn (its note asked for), then the clock on `ms`: in one frame, or a frame each
/// drag_step_ms: the frame then.
fn wide_note_at(ms : Double, frames : Bool) -> Int64 raise {
  let (t, _, _, _) = wide_box_noted("")
  let end = t.time() + ms
  if frames {
    while t.time() + @ui.drag_step_ms < end {
      t.frame_at(t.time() + @ui.drag_step_ms)
    }
  }
  t.frame_at(end)
  t.frame_hash()
}

///|
test "viewer on the tree, a wide window, marking: a note asked for comes in the same at a moment whatever frames came between; come in, nothing of it reads the clock; let go, nothing of it left" {
  assert_eq(wide_note_at(note_pop_ms / 2.0, true), wide_note_at(note_pop_ms / 2.0, false), msg="half way in: the same")
  let (t, _, click, _) = wide_box_noted("")
  t.frame_at(t.time() + note_pop_ms)
  t.draw()
  assert_false(@ui.view_tree().unwrap().clock_read(), msg="come in: nothing reads the clock")
  click(pv("android-chat.annotate.done"))
  t.draw()
  assert_true(marking.note < 0, msg="done: let go")
  assert_false(@ui.view_tree().unwrap().clock_read(), msg="let go: nothing of it reads the clock")
}

///|
test "viewer on the tree, a wide window, marking: a note's words written and more being composed, its 完成 clicked with no frame between: all it shows kept as the click is let go; opened again, all of it" {
  let (t, _, click, id) = wide_box_noted("这里")
  t.compose("对齐")
  click(pv("android-chat.annotate.done"))
  assert_eq(marking.comments.get(id), Some("这里对齐"), msg="let go: what was composed kept too")
  t.draw()
  @sfbase.marks_open_note(t.ctx(), id)
  t.draw()
  assert_eq(marking.note_field.text(), "这里对齐", msg="opened again: all of it")
}

///|
/// Marking on a wide window, a box drawn (its note asked for as the finger lifts), the first frame `late` after that
/// moment: how opaque the note's card is drawn (the window's tree's) half its coming in after that moment, and once it
/// has come in.
fn wide_note_first(late : Double) -> (Double, Double) raise {
  let (t, v, _) = wide_marking()
  let (rx, ry, rw, rh) = v.zoom.rect().unwrap()
  let (px, py) = (rx + rw / 3.0, ry + rh / 3.0)
  t.touch(0, px, py)
  t.touch(1, px + 60.0, py + 40.0)
  t.touch(2, px + 60.0, py + 40.0)
  let at = t.time()
  let card = fn() {
    match @ui.view_tree().unwrap().drawn().iter().find_first(fn(d) { d.ground == @sfbase.note_ground }) {
      Some(d) => d.alpha
      None => -1.0
    }
  }
  t.frame_at(at + late)
  t.frame_at(at + note_pop_ms / 2.0)
  let half = card()
  t.frame_at(at + note_pop_ms + 20.0)
  (half, card())
}

///|
test "viewer on the tree, a wide window, marking: a note asked for comes in from the moment it was, its first frame on time or late: half way in as opaque either way, coming in still, all of it once in" {
  let (half, whole) = wide_note_first(0.0)
  let (late_half, late_whole) = wide_note_first(40.0)
  assert_true(half > 0.0 && half < 1.0, msg="half way: coming in: \{half}")
  assert_eq(late_half, half, msg="its first frame late: as far in at that moment")
  assert_eq((whole, late_whole), (1.0, 1.0), msg="come in: all of it")
}

///|
test "viewer on the tree, a wide window, marking: a second box's note written, its 删除批注 pressed: nothing gone as it goes down; let go, that box gone and its note closed before any frame, the first box kept" {
  let (t, v, click, first) = wide_box_noted("第一个")
  click(pv("android-chat.annotate.done"))
  t.draw()
  // (a second box, lower down)
  let (rx, ry, rw, rh) = v.zoom.rect().unwrap()
  let (px, py) = (rx + rw / 2.0, ry + rh * 2.0 / 3.0)
  t.touch(0, px, py)
  t.touch(1, px + 60.0, py + 40.0)
  t.touch(2, px + 60.0, py + 40.0)
  t.draw()
  let second = marking.note
  assert_true(second >= 0 && second != first, msg="the second box's note asked for")
  t.text_told("第二个", t.time())
  t.run_for(note_pop_ms)
  let (x, y, w, h) = t.get(Button, label=pv("android-chat.annotate.remove")).rect
  t.touch(0, x + w / 2.0, y + h / 2.0)
  assert_eq((marking.note, marking.shapes.length()), (second, 2), msg="pressed: nothing gone")
  t.touch(2, x + w / 2.0, y + h / 2.0)
  assert_eq(
    (marking.note, marking.shapes.map(fn(s) { s.id })),
    (-1, [first]),
    msg="let go: the second box gone, its note closed, the first kept",
  )
  t.draw()
  assert_eq(marking.comments.get(first), Some("第一个"), msg="a frame after: the first's note as it was")
}

///|
test "viewer on the tree, a wide window, marking: a note asked for, come in: its 完成 and 删除批注 found by what they are called, where a finger reaches them, as a test finds a box by its label" {
  let (t, _, _, _) = wide_box_noted("")
  t.run_for(note_pop_ms)
  for name in [pv("android-chat.annotate.done"), pv("android-chat.annotate.remove")] {
    assert_eq(t.locate("=" + name).length(), 1, msg="\{name}: seen")
    assert_eq(t.reachable("=" + name).length(), 1, msg="\{name}: where a finger reaches it")
  }
}
///|
test "viewer on the tree, a wide window, marking: a note done (its card drawn), its card clicked: the note open again as the click is let go, before any frame" {
  let (t, _, click, id) = wide_box_noted("")
  click(pv("android-chat.annotate.done"))
  t.draw()
  t.draw()
  assert_true(marking.note < 0, msg="done: closed, its card drawn")
  let (cx, cy) = t.find(pv("android-chat.annotate.quoteOnly")).unwrap()
  t.touch(0, cx, cy)
  t.touch(2, cx, cy)
  assert_eq(marking.note, id, msg="its card: its note open again as the click is let go")
}


///|
/// Marking on a wide window `w` across, `k` boxes drawn one after another on the picture, each note done with nothing
/// said: the tester, its clicker, the marks' ids in their order.
fn wide_notes(k : Int, w? : Double = 1280.0) -> (@ui.Tester, (String) -> Unit raise, Array[Int]) raise {
  let (t, v, click) = wide_marking()
  if w != 1280.0 {
    t.resize(w, 844.0)
  }
  let ids = []
  for i in 0..<k {
    let (rx, ry, rw, rh) = v.zoom.rect().unwrap()
    let (px, py) = (rx + rw * (0.05 + 0.1 * i.to_double()), ry + rh * (0.1 + 0.08 * i.to_double()))
    t.touch(0, px, py)
    t.touch(1, px + 30.0, py + 20.0)
    t.touch(2, px + 30.0, py + 20.0)
    t.draw()
    ids.push(marking.note)
    click(pv("android-chat.annotate.done"))
    t.draw()
  }
  t.run_for(note_pop_ms)
  (t, click, ids)
}

///|
/// The notes' cards read out (their labels, in order), and what the +N card says ("" none read out).
fn cards_read(t : @ui.Tester) -> (Array[String], String) {
  let cards = []
  let mut more = ""
  for s in t.semantics() {
    if s.role == Button && s.label.has_prefix("+") {
      more = s.label
    } else if s.role == Button && card_label(s.label) {
      cards.push(s.label)
    }
  }
  (cards, more)
}

///|
test "viewer on the tree, marking: more notes than the foot holds cards for: the last left out first, +N saying how many as they leave, in the first frame so laid out; the window wider again, the same cards back, +N gone; narrow again, its menu listing them in order, one picked opening its note" {
  // (eight cards 160 wide, 8 between, 16 in at either side: 1368; a window 1600 wide holds them, one 1000 wide not, a
  // large screen's both: its frame the same, laid out narrower)
  let (t, click, ids) = wide_notes(8)
  t.resize(1600.0, 844.0)
  let (all, more) = cards_read(t)
  assert_eq((all.length(), more), (8, ""), msg="1600 wide: all eight, no +N: \{all} \{more}")
  let card_ids = card_nodes()
  t.resize(1000.0, 844.0)
  let (shown, more) = cards_read(t)
  let left = 8 - shown.length()
  assert_true(left > 0 && shown.length() > 0, msg="1000 wide: some left out: \{shown}")
  assert_eq(more, "+\{left}", msg="+N says how many, the first frame so laid out")
  // (+N as tall as its one line, at the row's top as the cards are: marks_notes_row's)
  let (_, my, _, mh) = t.get(Button, label=more).rect
  let (_, cy, _, ch) = t.get(Button, label=shown[0]).rect
  assert_true(my == cy && mh < ch, msg="+N at the cards' top, as tall as its one line: \{(my, mh)} \{(cy, ch)}")
  for i in 0..<shown.length() {
    assert_true(shown[i].has_prefix("\{i + 1}  "), msg="the first kept, in order: \{shown}")
  }
  t.resize(1600.0, 844.0)
  let (back, more) = cards_read(t)
  assert_eq((back.length(), more), (8, ""), msg="wider again: all back, +N gone")
  assert_eq(card_nodes(), card_ids, msg="wider again: the same cards' nodes")
  // (narrow again: what +N's menu holds, one picked)
  t.resize(1000.0, 844.0)
  let (shown, more) = cards_read(t)
  click(more)
  t.draw()
  for i in shown.length()..<8 {
    assert_true(t.find("\{i + 1}  " + pv("android-chat.annotate.quoteOnly")) is Some(_), msg="its menu: note \{i + 1}")
  }
  t.tap_text("8  " + pv("android-chat.annotate.quoteOnly"))
  t.draw()
  assert_eq(marking.note, ids[7], msg="picked in its menu: its note open")
}

///|
/// The notes' cards' nodes as the window's tree reads them out, in order.
fn card_nodes() -> Array[@view.NodeId] {
  @ui.view_tree().unwrap().said_order().filter(fn(s) {
    match s.said {
      Some(said) => said.role == Button && card_label(said.label)
      None => false
    }
  }).map(fn(s) { s.id })
}

///|
test "viewer on the tree, marking: a note's card left out of the foot as the window narrows: not read out, no press there its; one held as it is left out, let go: its note not opened" {
  let (t, _, ids) = wide_notes(8)
  t.resize(1600.0, 844.0)
  // (the last card held)
  let (x, y, w, h) = t.get(Button, label="8  " + pv("android-chat.annotate.quoteOnly")).rect
  t.touch(0, x + w / 2.0, y + h / 2.0)
  t.resize(1000.0, 844.0)
  let (shown, _) = cards_read(t)
  assert_false(shown.iter().any(fn(s) { s.has_prefix("8  ") }), msg="left out: not read out")
  t.touch(2, x + w / 2.0, y + h / 2.0)
  t.draw()
  assert_true(marking.note < 0, msg="held as it left, let go: its note not opened")
  ignore(ids)
}

///|
/// Whether `label` is a note's card's: its number, two spaces, what is said of it.
fn card_label(label : String) -> Bool {
  match label.find("  ") {
    Some(i) if i > 0 => {
      for ch in label.unsafe_substring(start=0, end=i) {
        if ch < '0' || ch > '9' {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// A picture opened on a phone (a finger's), marking: its floating bar's 取消 tapped (`frames`: the frame after drawn
/// before what is looked at; else none): whether marking is still on as the finger lifts, and after; how many of the
/// window's tree's own buttons said 取消 there were while it marked.
fn narrow_marking_cancel(frames : Bool) -> (Bool, Bool, Int) raise {
  let t = preview_tester("image", w=390.0, platform=2)
  let tap = fn(label : String) raise {
    let (x, y, w, h) = t.get(Button, label~).rect
    t.touch(0, x + w / 2.0, y + h / 2.0)
    t.touch(2, x + w / 2.0, y + h / 2.0)
  }
  tap(@sf.t("web-main.annotate.image"))
  t.draw()
  assert_true(marking.on, msg="marking")
  let cancel = pv("common.cancel")
  let nodes = @ui.view_tree().unwrap().said_order().filter(fn(s) {
    match s.said {
      Some(said) => said.role == Button && said.label == cancel
      None => false
    }
  })
  tap(cancel)
  let let_go = marking.on
  if frames {
    t.draw()
  }
  (let_go, marking.on, nodes.length())
}

///|
test "viewer on the tree, a phone, marking: its floating bar the tree's; 取消 leaves marking as the finger lifts, the frames drawn after or none" {
  for frames in [true, false] {
    let (let_go, after, nodes) = narrow_marking_cancel(frames)
    assert_true(!let_go, msg="frames \{frames}: marking left as the finger lifts")
    assert_true(!after, msg="frames \{frames}: left")
    assert_eq(nodes, 1, msg="frames \{frames}: 取消 a button of the tree's own")
  }
}

///|
test "viewer on the tree, a phone, marking: its floating bar never narrower, marking's actions in its tools' place and back: as wide after 取消 as while it marked" {
  let t = preview_tester("image", w=390.0, platform=2)
  let tap = fn(label : String) raise {
    let (x, y, w, h) = t.get(Button, label~).rect
    t.touch(0, x + w / 2.0, y + h / 2.0)
    t.touch(2, x + w / 2.0, y + h / 2.0)
  }
  let close = fn() raise { t.get(Button, label=@sf.t("web-main.preview.closeKey")).rect.0 }
  let plain = close()
  tap(@sf.t("web-main.annotate.image"))
  t.draw()
  let marked = close()
  tap(pv("common.cancel"))
  t.draw()
  assert_true(!marking.on, msg="left")
  assert_true(marked >= plain, msg="as wide marking at least: \{plain} \{marked}")
  assert_eq(close(), marked, msg="× where it was while it marked")
}

///|
/// How far in the floating bar is drawn (its glass, 44 high along the top; 0: none).
fn head_drawn() -> Double {
  let mut most = 0.0
  for d in @ui.view_tree().unwrap().drawn() {
    if d.glass is Some(_) && d.h == @ui.Space::px(S11) && d.y < 120.0 && d.alpha > most {
      most = d.alpha
    }
  }
  most
}

///|
test "viewer on a phone's width, a mouse: its bars hidden by a click, shown by the pointer along the top, marking begun there, the pointer back on the picture; Escape leaves marking: the floating bar goes as hidden bars do" {
  let t = preview_tester("image", w=390.0, platform=0)
  let v = viewer.get().unwrap()
  let (rx, ry, rw, rh) = v.zoom.rect().unwrap()
  let (px, py) = (rx + rw / 2.0, ry + rh / 2.0)
  t.touch(0, px, py)
  t.touch(2, px, py)
  t.run_for(@sf.sleep_ms * 2.0)
  assert_true(!v.bars_shown(), msg="hidden by a click")
  assert_eq(head_drawn(), 0.0, msg="hidden: gone")
  // (the pointer along the top: shown, its 标注图片 pressed there)
  let (x, y, w, h) = t.get(Button, label=@sf.t("web-main.annotate.image")).rect
  t.move(x + w / 2.0, y + h / 2.0)
  t.run_for(@sf.wake_ms * 2.0)
  assert_true(v.near_bar, msg="the pointer along the top")
  assert_eq(head_drawn(), 1.0, msg="the pointer along the top: shown")
  t.touch(0, x + w / 2.0, y + h / 2.0)
  t.touch(2, x + w / 2.0, y + h / 2.0)
  t.draw()
  assert_true(marking.on, msg="marking")
  // (the pointer back on the picture: still shown, marking)
  t.move(px, py)
  t.run_for(@sf.sleep_ms * 2.0)
  assert_true(!v.near_bar && !v.awake, msg="the pointer off the top, the bars asleep")
  assert_eq(head_drawn(), 1.0, msg="marking: shown")
  t.key(@ui.key_escape)
  assert_true(!marking.on, msg="Escape: marking left")
  t.run_for(@sf.sleep_ms * 2.0)
  assert_true(!v.near_bar, msg="the pointer not back along the top")
  assert_eq(head_drawn(), 0.0, msg="marking left, the bars asleep: gone")
}

///|
test "viewer on the tree, a phone, marking: its floating bar wider as what marking says asks it (why making it failed), as wide once that is gone" {
  let t = preview_tester("image", w=390.0, platform=2)
  let (x, y, w, h) = t.get(Button, label=@sf.t("web-main.annotate.image")).rect
  t.touch(0, x + w / 2.0, y + h / 2.0)
  t.touch(2, x + w / 2.0, y + h / 2.0)
  t.draw()
  let close = fn() raise { t.get(Button, label=@sf.t("web-main.preview.closeKey")).rect.0 }
  let marked = close()
  marking.error = pv("android-chat.file.drawFailed")
  @sfbase.marks_changed()
  t.draw()
  let failed = close()
  assert_true(failed > marked, msg="why it failed: wider: \{marked} \{failed}")
  marking.error = ""
  @sfbase.marks_changed()
  t.draw()
  assert_eq(close(), failed, msg="gone: as wide: \{marked} \{failed}")
  marks_leave()
}

///|
test "viewer on the tree, a phone: its floating bar's tools and × as far apart as keys are (keys_apart), each from the one before it" {
  let t = preview_tester("image", w=390.0, platform=2)
  // (its tools and × by what they say: 标注图片, 复制, 下载, 关闭)
  let keys = [
    @sf.t("web-main.annotate.image"),
    @sf.t("common.copy"),
    @sf.t("web-main.preview.download"),
    @sf.t("web-main.preview.closeKey"),
  ].map(fn(label) { t.get(Button, label~).rect })
  keys.sort_by(fn(a, b) { a.0.compare(b.0) })
  assert_true(keys.length() >= 3, msg="its tools and ×: \{keys}")
  for i in 1..<keys.length() {
    let (px, _, pw, _) = keys[i - 1]
    assert_eq(keys[i].0 - (px + pw), @sf.keys_apart(), msg="\{i}: \{keys}")
  }
}

///|
test "viewer on the tree, a phone, marking a picture of a long name: 添加到对话 a button of its own on the floating bar, its words 12 inside it, it before ×" {
  let t = preview_tester("step", w=390.0, platform=0)
  let (a, _) = preview_files().iter().find_first(fn(f) { f.0.name == "界面草图.png" }).unwrap()
  open_preview("ws1/st1", "s-c1", { ..a, name: "web-open-2-folded-preview-of-the-chat.png" }, steps=InChat(Some(1.0), "s-c1"))
  t.run_for(@ui.move_most_ms)
  marks_start()
  t.draw()
  let put = pv("android-chat.preview.put")
  let pills = t.semantics().filter(fn(s) { s.role == Button && s.label == put })
  assert_eq(pills.length(), 1, msg="添加到对话 a button of its own, one")
  let (bx, _, bw, _) = pills[0].rect
  let words = @ui.view_tree().unwrap().drawn().filter(fn(d) { d.words == put && d.alpha > 0.0 })
  assert_eq(words.length(), 1, msg="its words drawn, once")
  let (xx, _, _, _) = t.get(Button, label=@sf.t("web-main.preview.closeKey")).rect
  assert_true(words[0].x + words[0].w <= bx + bw - 12.0 + 0.5, msg="its words 12 inside it")
  assert_true(words[0].x >= bx + 12.0 - 0.5, msg="its words 12 inside it, from its start")
  assert_true(bx + bw <= xx + 0.5, msg="before ×")
  marks_leave()
}

///|
/// A picture opened on a phone (a finger's), marking: a box drawn from (100, 100) to (300, 200) in its pixels, its
/// note done (完成); the tester and the box's mark.
fn pinned() -> (@ui.Tester, Int) raise {
  let t = preview_tester("image", w=390.0, platform=2)
  marks_start()
  t.draw()
  let v = viewer.get().unwrap()
  let (x, y, w, _) = v.zoom.rect().unwrap()
  let k = w / v.zoom.nw
  marking.tool = Rect
  t.drag(x + 100.0 * k, y + 100.0 * k, x + 300.0 * k, y + 200.0 * k)
  t.run_for(note_pop_ms)
  let tick = t.reachable("icon:check")
  assert_eq(tick.length(), 1, msg="完成 where a finger reaches it")
  t.tap(tick[0].0, tick[0].1)
  t.draw()
  assert_eq(marking.note, -1, msg="its note done")
  (t, marking.shapes[0].id)
}

///|
test "viewer on the tree, marking: a mark's pin drawn by the window's tree, its 24 round ground one" {
  let (_, _) = pinned()
  assert_eq(pin_grounds(), 1, msg="its pin's 24 round ground drawn, one")
  marks_leave()
}

///|
/// How many pins' own grounds are drawn (24 round, 12 its corners: a note card's 16 pin is not one).
fn pin_grounds() -> Int {
  @ui.view_tree().unwrap().drawn().filter(fn(d) { d.w == 24.0 && d.h == 24.0 && d.radius == 12.0 }).length()
}

///|
/// How far into the zoom's glide a pin is looked at (well before its end), and long enough for it to be done.
let pin_glide_mid_ms : Double = 60.0

///|
let pin_glide_done_ms : Double = 2000.0

///|
/// Mark 1's pin pressed in `t` where it is at the tester's moment (its press and its let go, no frame between): its
/// rect then.
fn pin_pressed(t : @ui.Tester) -> (Double, Double, Double, Double) raise {
  let label = pv_fill("android-chat.marks.pin", [("n", "1")])
  let (x, y, w, h) = t.get(Button, label~).rect
  t.touch(0, x + w / 2.0, y + h / 2.0)
  t.touch(2, x + w / 2.0, y + h / 2.0)
  (x, y, w, h)
}

///|
test "viewer on the tree, marking: a mark's pin pressed opens its note as the finger lifts, again closes it, the frames drawn after or none; the pin a button of the tree's own" {
  for frames in [true, false] {
    let (t, id) = pinned()
    pin_pressed(t) |> ignore
    assert_eq(marking.note, id, msg="frames \{frames}: pressed, its note open as the finger lifts")
    if frames {
      t.draw()
    }
    t.run_for(note_pop_ms)
    pin_pressed(t) |> ignore
    assert_eq(marking.note, -1, msg="frames \{frames}: pressed again, closed as the finger lifts")
    if frames {
      t.draw()
    }
    let label = pv_fill("android-chat.marks.pin", [("n", "1")])
    let pins = @ui.view_tree().unwrap().said_order().filter(fn(s) {
      match s.said {
        Some(said) => said.role == Button && said.label == label
        None => false
      }
    })
    assert_eq(pins.length(), 1, msg="frames \{frames}: a button of the tree's own")
    marks_leave()
  }
}

///|
test "viewer on the tree, marking: a mark's pin where the picture is as it is drawn while the zoom glides and where the glide leaves it; pressed between two frames, where it is at that moment, its note opened" {
  let (t, id) = pinned()
  let v = viewer.get().unwrap()
  let label = pv_fill("android-chat.marks.pin", [("n", "1")])
  // (where its point is: the box's corner, as the picture is at the tester's moment)
  let expected = fn() {
    let (rx, ry, rw, _) = v.marks_rect(t.time()).unwrap()
    let k = rw / v.zoom.nw
    (rx + 100.0 * k, ry + 100.0 * k)
  }
  // (its point as it is drawn: 2 in and 22 down of its 24, as big as its note being open says)
  let point = fn() raise {
    let (x, y, w, h) = t.get(Button, label~).rect
    let k = if marking.note == id { @sfbase.pin_open_scale } else { 1.0 }
    assert_true((w - 24.0 * k).abs() < 0.01 && (h - 24.0 * k).abs() < 0.01, msg="as big as \{k}: \{(w, h)}")
    (x + 2.0 * k, y + 22.0 * k)
  }
  let near = fn(a : (Double, Double), b : (Double, Double)) { (a.0 - b.0).abs() < 0.01 && (a.1 - b.1).abs() < 0.01 }
  let (bw, bh) = (v.zoom.bw, v.zoom.bh)
  v.zoom.zoom_to(v.zoom.fit() * 2.0, bw / 2.0, bh / 2.0, true, at=t.time())
  t.run_for(pin_glide_mid_ms)
  assert_true(v.zoom.goes_at(t.time()), msg="the glide under way")
  let p = point()
  assert_true(near(p, expected()), msg="gliding: \{p} where the picture has it, \{expected()}")
  // (the clock on, no frame drawn: pressed where the pin is at that moment)
  t.advance(pin_glide_mid_ms / 2.0)
  assert_true(v.zoom.goes_at(t.time()), msg="the glide under way still")
  // (its middle: 10 right of its point and 10 up)
  let (ex, ey) = expected()
  t.touch(0, ex + 10.0, ey - 10.0)
  t.touch(2, ex + 10.0, ey - 10.0)
  assert_eq(marking.note, id, msg="pressed where it is between two frames: its note open")
  t.run_for(pin_glide_done_ms)
  assert_true(!v.zoom.goes_at(t.time()), msg="the glide done")
  let p = point()
  assert_true(near(p, expected()), msg="glided: \{p} where the picture has it, \{expected()}")
  marks_leave()
}

///|
test "viewer on the tree, marking: words being written over a mark's pin over it, as before: a press there theirs, the note not opened" {
  let (t, _) = pinned()
  let v = viewer.get().unwrap()
  let (rx, ry, rw, _) = v.marks_rect(t.time()).unwrap()
  let k = rw / v.zoom.nw
  // (the box's corner, its pin up and right of it; words begun 30 left of it and 5 up: their field over the pin)
  let (cx, cy) = (rx + 100.0 * k, ry + 100.0 * k)
  marking.tool = Words
  t.touch(0, cx - 30.0, cy - 5.0)
  t.touch(2, cx - 30.0, cy - 5.0)
  t.draw()
  assert_true(marking.writing is Some(_), msg="words begun")
  t.touch(0, cx + 10.0, cy - 10.0)
  t.touch(2, cx + 10.0, cy - 10.0)
  t.draw()
  assert_eq(marking.note, -1, msg="the words' field over the pin: the press theirs, no note")
  assert_true(marking.writing is Some(_), msg="still written")
  marks_leave()
}

///|
test "viewer on the tree, marking a picture that could not be decoded: as what draws it draws none of its marks, no pin drawn, read out or pressed, no words being written drawn" {
  let t = preview_tester("image", w=390.0, platform=2, finish=false)
  let v = viewer.get().unwrap()
  // (each picture asked for could not be decoded, as the host says)
  for _ in 0..<3 {
    for p in t.pending() {
      t.finish(p.0, p.1, ok=p.0 != 1)
    }
    t.draw()
  }
  assert_eq(@ui.image_state("mem:preview/" + v.id()), -1, msg="its picture not decoded")
  // (where it is known all the same: where its pin would be)
  let (rx, ry, rw, _) = v.marks_rect(t.time()).unwrap()
  let k = rw / v.zoom.nw
  marks_start()
  // (a box from (100, 100) to (300, 200) in its pixels, numbered 1; words being written at (50, 50))
  marking.shapes.push({ id: marking.next_id, kind: "box", color: marking.color, w: 4.0, pts: [100.0, 100.0, 300.0, 200.0], text: "" })
  marking.next_id += 1
  marking.writing = Some((-1, 50.0, 50.0, 16.0, marking.color))
  @sfbase.marks_changed()
  t.draw()
  let label = pv_fill("android-chat.marks.pin", [("n", "1")])
  let pins = @ui.view_tree().unwrap().said_order().filter(fn(s) {
    match s.said {
      Some(said) => said.label == label
      None => false
    }
  })
  assert_eq(pins.length(), 0, msg="no pin of the tree's")
  assert_true(t.semantics().iter().all(fn(s) { s.label != label }), msg="no pin read out")
  assert_eq(pin_grounds(), 0, msg="no pin drawn")
  // (where its pin would be, picking: nothing of a pin's there to press)
  marking.tool = Select
  t.touch(0, rx + 100.0 * k + 10.0, ry + 100.0 * k - 10.0)
  t.touch(2, rx + 100.0 * k + 10.0, ry + 100.0 * k - 10.0)
  assert_eq(marking.note, -1, msg="no note opened")
  assert_true(t.find(pv("android-chat.marks.write")) is None, msg="no words being written drawn")
  marks_leave()
}

///|
test "viewer on the tree, marking a picture whose size is not known yet (none said, nothing decoded): as what draws it draws none of its marks, no pin drawn, read out or pressed, no words being written drawn" {
  let t = preview_tester("step", w=390.0, platform=2, finish=false)
  // (the same picture under no size of its own, nothing standing in for it)
  let (a, _) = preview_files().iter().find_first(fn(f) { f.0.name == "界面草图.png" }).unwrap()
  open_preview("ws1/st1", "s-c1", { ..a, width: 0.0, height: 0.0, thumbhash: "" }, steps=InChat(Some(1.0), "s-c1"))
  t.run_for(@ui.move_most_ms)
  let v = viewer.get().unwrap()
  assert_true(v.zoom.rect() is None, msg="where it is not known")
  marks_start()
  marking.shapes.push({ id: marking.next_id, kind: "box", color: marking.color, w: 4.0, pts: [100.0, 100.0, 300.0, 200.0], text: "" })
  marking.next_id += 1
  marking.writing = Some((-1, 50.0, 50.0, 16.0, marking.color))
  @sfbase.marks_changed()
  t.draw()
  let label = pv_fill("android-chat.marks.pin", [("n", "1")])
  assert_true(t.semantics().iter().all(fn(s) { s.label != label }), msg="no pin read out")
  assert_eq(pin_grounds(), 0, msg="no pin drawn")
  // (where a pin with no place would be put: nothing of a pin's there to press)
  marking.tool = Select
  t.touch(0, 12.0, 12.0)
  t.touch(2, 12.0, 12.0)
  assert_eq(marking.note, -1, msg="no note opened")
  assert_true(t.find(pv("android-chat.marks.write")) is None, msg="no words being written drawn")
  marks_leave()
}

///|
/// A picture opened on a phone (a finger's), marking: a box from (100, 100) to (300, 200) in its pixels, its note done;
/// an arrow from (350, 250) to (500, 300); a line drawn by hand from (60, 320) to (200, 360); words 「对齐」 at (380,
/// 60). The tester.
fn shaped() -> @ui.Tester raise {
  let (t, _) = pinned()
  let v = viewer.get().unwrap()
  let (x, y, w, _) = v.zoom.rect().unwrap()
  let k = w / v.zoom.nw
  marking.tool = Arrow
  t.drag(x + 350.0 * k, y + 250.0 * k, x + 500.0 * k, y + 300.0 * k)
  // (the arrow's note, asked for as it is drawn, done)
  t.run_for(note_pop_ms)
  let tick = t.reachable("icon:check")
  assert_eq(tick.length(), 1, msg="the arrow's note's 完成, one")
  t.tap(tick[0].0, tick[0].1)
  t.draw()
  assert_eq(marking.note, -1, msg="the arrow's note done")
  marking.tool = Pen
  t.drag(x + 60.0 * k, y + 320.0 * k, x + 200.0 * k, y + 360.0 * k)
  marking.shapes.push({ id: marking.next_id, kind: "words", color: marking.color, w: 18.0 / k, pts: [380.0, 60.0], text: "对齐" })
  marking.next_id += 1
  @sfbase.marks_changed()
  t.draw()
  // (the four, each there, nothing being written or noted)
  for kind in ["box", "arrow", "pen", "words"] {
    assert_true(marking.shapes.iter().any(fn(m) { m.kind == kind }), msg="a \{kind}")
  }
  assert_true(marking.writing is None && marking.note == -1, msg="nothing being written or noted")
  t
}

///|
/// The lines the window's tree draws over the picture (marks_shapes_node's), and the words drawn there with their place
/// (the words and their edges, in the order drawn).
fn shapes_drawn() -> (Array[@ui.Line], Array[(String, Double, Double, Int64)]) {
  let lines = []
  let words = []
  for d in @ui.view_tree().unwrap().drawn() {
    lines.append(d.lines)
    if d.words == "对齐" {
      words.push((d.words, d.x, d.y, d.ink))
    }
  }
  (lines, words)
}

///|
test "viewer on the tree, marking: a box, an arrow, a line drawn by hand and words drawn by the window's tree, as marks_lines works them out where the picture is; the words edged in their halo, eight under the words themselves" {
  let t = shaped()
  let v = viewer.get().unwrap()
  let (lines, words) = shapes_drawn()
  let (want, _) = @sfbase.marks_lines(v.marks_rect(t.time()).unwrap(), v.zoom.nw)
  assert_eq(lines.length(), want.length(), msg="as many lines")
  assert_true(lines == want, msg="the lines as marks_lines has them")
  assert_eq(words.length(), 9, msg="the words and their eight edges")
  assert_eq(words[8].3, marking.color, msg="the words themselves last, in their colour")
  marks_leave()
}

///|
test "viewer on the tree, marking: the marks drawn where the picture is as each frame draws it while the zoom glides, and where the glide leaves it" {
  let t = shaped()
  let v = viewer.get().unwrap()
  v.zoom.zoom_to(v.zoom.fit() * 2.0, v.zoom.bw / 2.0, v.zoom.bh / 2.0, true, at=t.time())
  t.run_for(pin_glide_mid_ms)
  assert_true(v.zoom.goes_at(t.time()), msg="the glide under way")
  assert_true(shapes_drawn().0 == @sfbase.marks_lines(v.marks_rect(t.time()).unwrap(), v.zoom.nw).0, msg="gliding")
  t.run_for(pin_glide_done_ms)
  assert_true(!v.zoom.goes_at(t.time()), msg="the glide done")
  assert_true(shapes_drawn().0 == @sfbase.marks_lines(v.marks_rect(t.time()).unwrap(), v.zoom.nw).0, msg="glided")
  marks_leave()
}

///|
test "viewer on the tree, marking: the box picked, its dashed frame and handles drawn in the frame it is picked; its colour changed, drawn so in the next; marking left, none of it drawn" {
  let t = shaped()
  let v = viewer.get().unwrap()
  let id = marking.shapes[0].id
  marking.tool = Select
  marking.picked = id
  @sfbase.marks_changed()
  t.draw()
  let (lines, _) = shapes_drawn()
  let (want, handles) = @sfbase.marks_lines(v.marks_rect(t.time()).unwrap(), v.zoom.nw)
  assert_true(lines == want, msg="its frame with them")
  let rings = @ui.view_tree().unwrap().drawn().filter(fn(d) { d.w == 12.0 && d.h == 12.0 && d.radius == 6.0 })
  assert_eq(rings.length(), handles.length(), msg="a handle each")
  // (its colour changed)
  let i = marking.shapes.search_by(fn(s) { s.id == id }).unwrap()
  marking.shapes[i] = { ..marking.shapes[i], color: 0x2E8B57FFL }
  @sfbase.marks_changed()
  t.draw()
  assert_true(shapes_drawn().0.iter().any(fn(l) { l.color == 0x2E8B57FFL }), msg="in its colour now")
  marks_leave()
  t.draw()
  assert_eq(shapes_drawn().0.length(), 0, msg="marking left: no lines")
  assert_eq(shapes_drawn().1.length(), 0, msg="marking left: no words")
}

///|
test "viewer on the tree, marking: the marks drawn where the picture is as each frame draws it while the keyboard lifts it (words being written low on it), and where the lift leaves it" {
  let t = shaped()
  let v = viewer.get().unwrap()
  // (words begun low on the picture, the keyboard up, the window laid out above it, as a host does)
  marking.tool = Words
  let (x, y, w, h) = v.zoom.rect().unwrap()
  t.touch(0, x + w / 2.0, y + h * 0.9)
  t.touch(2, x + w / 2.0, y + h * 0.9)
  assert_true(marking.writing is Some(_), msg="words begun")
  t.set_ime_inset(300.0)
  t.resize_next(390.0, 844.0 - 300.0)
  t.draw()
  t.run_for(pin_glide_mid_ms)
  assert_true(v.lift.goes_at(t.time()), msg="the lift under way")
  assert_true(shapes_drawn().0 == @sfbase.marks_lines(v.marks_rect(t.time()).unwrap(), v.zoom.nw).0, msg="lifting")
  t.run_for(pin_glide_done_ms)
  assert_true(!v.lift.goes_at(t.time()) && v.lift.target() > 0.0, msg="lifted")
  assert_true(shapes_drawn().0 == @sfbase.marks_lines(v.marks_rect(t.time()).unwrap(), v.zoom.nw).0, msg="lifted, the lines")
  marks_leave()
}

///|
test "viewer on the tree, marking: words written again and set otherwise (another colour, another size) drawn so in the next frame, by the nodes that drew them" {
  let t = shaped()
  let tree = @ui.view_tree().unwrap()
  let ids = fn() { tree.drawn().filter(fn(d) { d.words.has_prefix("对齐") }).map(fn(d) { (d.id.at, d.id.gen) }) }
  let before = ids()
  assert_eq(before.length(), 9, msg="the words and their edges")
  let i = marking.shapes.search_by(fn(s) { s.kind == "words" }).unwrap()
  let m = marking.shapes[i]
  marking.shapes[i] = { ..m, text: "对齐了", color: 0x2E8B57FFL, w: m.w * 1.5 }
  @sfbase.marks_changed()
  t.draw()
  let now = tree.drawn().filter(fn(d) { d.words == "对齐了" })
  assert_eq(now.length(), 9, msg="written again, in the next frame")
  assert_eq(now[8].ink, 0x2E8B57FFL, msg="in its new colour")
  let v = viewer.get().unwrap()
  let (_, _, rw, _) = v.marks_rect(t.time()).unwrap()
  assert_eq(now[8].words_look.size, m.w * 1.5 * rw / v.zoom.nw, msg="at its new size")
  assert_eq(now.map(fn(d) { (d.id.at, d.id.gen) }), before, msg="by the same nodes")
  marks_leave()
}

///|
/// What the window's tree's node draws of the open viewer's picture (View::image, its whole picture's name): its source,
/// else none.
fn picture_node() -> String? {
  let main = match viewer.get() {
    Some(v) => "mem:preview/" + v.id()
    None => return None
  }
  for d in @ui.view_tree().unwrap().drawn() {
    match d.image {
      Some((src, _, _)) if src == main => return Some(src)
      _ => ()
    }
  }
  None
}

///|
/// The window's tree's nodes drawing `src` (View::image), each where it is drawn (x, y, w, h).
fn nodes_of(src : String) -> Array[(Double, Double, Double, Double)] {
  @ui.view_tree().unwrap().drawn().filter_map(fn(d) {
    match d.image {
      Some((s, _, _)) if s == src => Some((d.x, d.y, d.w, d.h))
      _ => None
    }
  })
}

///|
/// The pictures drawn now from a decode of `src` (each instance's decode, image.mbt's draw_image), where each is.
fn drawn_of(t : @ui.Tester, src : String) -> Array[(Double, Double, Double, Double)] {
  t.drawn_instances().filter_map(fn(i) {
    if i[5] == 4.0 && t.image_src(i[20].to_int()).has_prefix(src) {
      Some((i[0], i[1], i[2], i[3]))
    } else {
      None
    }
  })
}

///|
/// Whether `r` is at (x, y, w, h), to half a point.
fn at_rect(r : (Double, Double, Double, Double), x : Double, y : Double, w : Double, h : Double) -> Bool {
  (r.0 - x).abs() < 0.5 && (r.1 - y).abs() < 0.5 && (r.2 - w).abs() < 0.5 && (r.3 - h).abs() < 0.5
}

///|
test "viewer on the tree: the picture lying flat drawn by its node, its stand-in as it comes, then the picture itself as the host says it is decoded; drawn once" {
  let t = preview_tester("image", finish=false)
  let v = viewer.get().unwrap()
  let main = "mem:preview/" + v.id()
  // (each decode but the picture's own done: its stand-in ready)
  for _ in 0..<3 {
    for p in t.pending() {
      if p.0 != 1 || !t.image_src(p.1).has_prefix(main) {
        t.finish(p.0, p.1)
      }
    }
    t.draw()
  }
  t.run_for(@ui.move_most_ms)
  // (what it shows where it lies: the source of the decode drawn there)
  let shown = fn() {
    let (x, y, w, h) = v.zoom.rect().unwrap()
    t.drawn_instances().filter(fn(i) { i[5] == 4.0 && (i[0] - x).abs() < 0.5 && (i[1] - y).abs() < 0.5 && (i[2] - w).abs() < 0.5 && (i[3] - h).abs() < 0.5 }).map(fn(i) { t.image_src(i[20].to_int()) })
  }
  assert_true(picture_node() is Some(_), msg="the node's")
  let before = shown()
  assert_true(before.length() == 1 && before[0] != "mem:preview/" + v.id(), msg="its stand-in first: \{before}")
  for p in t.pending() {
    t.finish(p.0, p.1)
  }
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(shown(), ["mem:preview/" + v.id()], msg="the picture itself once decoded")
  // (drawn once: by its node alone, what draws the picture leaving it)
  let (x, y, w, h) = v.zoom.rect().unwrap()
  let at = drawn_pictures(t).filter(fn(d) { (d.0 - x).abs() < 0.5 && (d.1 - y).abs() < 0.5 && (d.2 - w).abs() < 0.5 && (d.3 - h).abs() < 0.5 })
  assert_eq(at.length(), 1, msg="drawn once where it lies: \{drawn_pictures(t)}")
}

///|
test "viewer on the tree: the strip put aside and still (no way going): the picture moved with it, drawn by its node, once; the one beside it brought in drawn by a node of its own where the stage's width and the gap put it, once; at rest, it alone" {
  let t = preview_tester("step")
  let v = viewer.get().unwrap()
  t.run_for(@ui.move_most_ms)
  let main = "mem:preview/" + v.id()
  assert_true(picture_node() is Some(_), msg="flat: the node's")
  // (the one after it, 第二版.png, read ahead)
  let n = pv_strip.near.values().to_array()
  assert_eq(n.length(), 1, msg="one beside it")
  let next = "mem:preview/" + n[0].id()
  // (put aside -50, still, toward it: as a film's fixture holds it)
  pv_strip.way.put(-50.0)
  t.draw()
  assert_true(!pv_strip.way.goes_at(t.time()), msg="no way going")
  let (x, y, w, h) = v.zoom.rect().unwrap()
  assert_true(nodes_of(main).length() == 1 && at_rect(nodes_of(main)[0], x - 50.0, y, w, h), msg="put aside: the node's, 50 aside: \{nodes_of(main)}")
  let shown = drawn_of(t, main)
  assert_true(shown.length() == 1 && at_rect(shown[0], x - 50.0, y, w, h), msg="drawn 50 aside, once: \{shown}")
  // (the one after: fitted to the stage, 390 + 24 to the right of it, 50 aside)
  let (nx, ny, nw, nh) = @sfbase.fitted_rect(400.0, 560.0, 390.0, 844.0).unwrap()
  let nx = nx - 50.0 + 390.0 + @sfbase.slide_gap
  assert_true(nodes_of(next).length() == 1 && at_rect(nodes_of(next)[0], nx, ny, nw, nh), msg="the one beside it a node's: \{nodes_of(next)}")
  let beside = drawn_of(t, next)
  assert_true(beside.length() == 1 && at_rect(beside[0], nx, ny, nw, nh), msg="the one beside it drawn once: \{beside}")
  // (back at rest: it alone, the one beside it out of the scene)
  pv_strip.way.put(0.0)
  t.draw()
  assert_true(drawn_of(t, main).length() == 1 && at_rect(drawn_of(t, main)[0], x, y, w, h), msg="at rest, drawn once where it lies")
  assert_eq(nodes_of(next).length() + drawn_of(t, next).length(), 0, msg="at rest, the one beside it nowhere")
}

///|
/// Stepped from `from` (a picture of the chat's, InChat) to the one after it by a swipe, the strip going: in a frame on
/// the way, the one before it ends, and the one it ends in, the one going drawn by a node from where it lay, the stage's
/// width and the gap out to its side, the one come in by its own node, each from its own decode, once; at the end, the
/// one come in alone.
fn stepped_through(from : String) -> Unit raise {
  let t = preview_tester("step")
  if from != "界面草图.png" {
    let (a, _) = preview_files().iter().find_first(fn(f) { f.0.name == from }).unwrap()
    open_preview("ws1/st1", "s-c1", a, steps=InChat(Some(1.0), "s-c1"))
    t.run_for(@ui.move_most_ms)
  }
  let v = viewer.get().unwrap()
  assert_eq(v.file.name, from, msg="open")
  t.run_for(@ui.move_most_ms)
  let gone = "mem:preview/" + v.id()
  let (gx, gy, gw, gh) = v.zoom.rect().unwrap()
  assert_true(drawn_of(t, gone).length() == 1, msg="\{from}: drawn, once")
  t.drag(300.0, 422.0, 100.0, 422.0)
  let w2 = viewer.get().unwrap()
  assert_true(!physical_equal(w2, v), msg="\{from}: stepped")
  let come = "mem:preview/" + w2.id()
  assert_true(come != gone, msg="another picture")
  let end = pv_strip.way.end()
  assert_true(end > t.time() + 2.0 * @ui.frame_period_default, msg="a way of some frames")
  let l = pv_strip.leaving.unwrap()
  assert_true(l.picture.has_prefix(gone) && at_rect((l.x, l.y, l.w, l.h), gx, gy, gw, gh), msg="it goes from where it lay, as it showed")
  for at in [t.time() + @ui.frame_period_default, (t.time() + end) / 2.0, end - @ui.frame_period_default] {
    t.frame_at(at)
    let sx = pv_strip.way.value_at(t.time())
    assert_true(sx != 0.0 && pv_strip.way.goes_at(t.time()), msg="\{from} \{at}: going, \{sx}")
    let lx = l.x + sx - l.dir.to_double() * l.width
    let going = nodes_of(l.picture)
    assert_true(going.length() == 1 && at_rect(going[0], lx, l.y, l.w, l.h), msg="\{from} \{at}: the one going a node's: \{going}")
    let drawn = drawn_of(t, gone)
    assert_true(drawn.length() == 1 && at_rect(drawn[0], lx, l.y, l.w, l.h), msg="\{from} \{at}: the one going drawn once: \{drawn}")
    let (x, y, w, h) = w2.zoom.rect().unwrap()
    assert_true(picture_node() == Some(come), msg="\{from} \{at}: the one come in its node's")
    let shown = drawn_of(t, come)
    assert_true(shown.length() == 1 && at_rect(shown[0], x + sx, y, w, h), msg="\{from} \{at}: the one come in drawn once, \{sx} aside: \{shown}")
  }
  t.frame_at(end)
  let (x, y, w, h) = w2.zoom.rect().unwrap()
  let shown = drawn_of(t, come)
  assert_true(shown.length() == 1 && at_rect(shown[0], x, y, w, h), msg="\{from}: at its end, the one come in drawn once: \{shown}")
  assert_eq(nodes_of(l.picture).length() + drawn_of(t, gone).length(), 0, msg="\{from}: at its end, the one gone nowhere")
}

///|
test "viewer on the tree: stepped to the one after, the strip going: the one going drawn by a node from where it lay, the stage's width and the gap out to the side, the one come in by its own node, each once in each frame; at its end, the one come in alone" {
  stepped_through("界面草图.png")
}

///|
test "viewer on the tree: stepped to the one after as big as it (对照草图.png to 界面草图.png): each told by its own picture, the one going and the one come in each where it is, once; at its end, the one come in alone" {
  // (as big as each other, other pictures: decoded, as wide and as tall, their pixels not the same)
  let bytes = fn(name : String) { (preview_files().iter().find_first(fn(f) { f.0.name == name }).unwrap().1)() }
  let (aw, ah, a) = @pixels.decode_png(bytes("对照草图.png")).unwrap()
  let (bw, bh, b) = @pixels.decode_png(bytes("界面草图.png")).unwrap()
  assert_eq((aw, ah), (bw, bh), msg="as big")
  assert_true(a.length() == b.length() && (0).until(a.length()).any(fn(i) { a[i] != b[i] }), msg="other pictures")
  stepped_through("对照草图.png")
}

///|
test "viewer on the tree: its picture said not to decode with the strip put aside: its words alone, nothing of it or of the one beside it drawn, as before" {
  let t = preview_tester("step", finish=false)
  let v = viewer.get().unwrap()
  let main = "mem:preview/" + v.id()
  // (its own decode said not to be; every other done)
  for _ in 0..<3 {
    for p in t.pending() {
      t.finish(p.0, p.1, ok=!(p.0 == 1 && t.image_src(p.1).has_prefix(main)))
    }
    t.draw()
  }
  assert_eq(@ui.image_state(main), -1, msg="not to be decoded")
  let n = pv_strip.near.values().to_array()
  assert_eq(n.length(), 1, msg="one beside it")
  let next = "mem:preview/" + n[0].id()
  pv_strip.way.put(-50.0)
  t.draw()
  let said = pv("android-chat.file.image.failed")
  assert_eq(t.words().filter(fn(w) { w.0 == said }).length(), 1, msg="said once")
  assert_eq(nodes_of(main).length() + drawn_of(t, main).length(), 0, msg="nothing of it drawn")
  assert_eq(nodes_of(next).length() + drawn_of(t, next).length(), 0, msg="nothing beside it drawn while it failed: \{nodes_of(next)}")
  // (one said to be going from where it lay, the strip on its way back: none of it drawn either)
  pv_strip.leaving = Some({ picture: next, x: 20.0, y: 300.0, w: 350.0, h: 240.0, dir: 1, width: 390.0 + @sfbase.slide_gap })
  pv_strip.way.go(0.0, @motion.sheet_spring, at=t.time())
  t.frame_at(t.time() + @ui.frame_period_default)
  assert_true(pv_strip.way.goes_at(t.time()), msg="going")
  assert_eq(t.words().filter(fn(w) { w.0 == said }).length(), 1, msg="going: said once")
  assert_eq(nodes_of(next).length() + drawn_of(t, next).length(), 0, msg="nothing going drawn while it failed: \{nodes_of(next)}")
  pv_strip.leaving = None
}

///|
/// The pictures drawn now where viewer `v`'s lies, `dx` aside.
fn main_pictures(t : @ui.Tester, v : Viewer, dx : Double) -> Int {
  let (x, y, w, h) = v.zoom.rect().unwrap()
  drawn_pictures(t).filter(fn(d) { (d.0 - (x + dx)).abs() < 0.5 && (d.1 - y).abs() < 0.5 && (d.2 - w).abs() < 0.5 && (d.3 - h).abs() < 0.5 }).length()
}

///|
test "viewer on the tree: the strip going back to rest, nothing else of it changing: the picture drawn once in each frame by its node, where the way has it as the frame is drawn" {
  let t = preview_tester("step")
  let v = viewer.get().unwrap()
  t.run_for(@ui.move_most_ms)
  pv_strip.way.put(50.0)
  t.draw()
  pv_strip.way.go(0.0, @motion.animate_spring, at=t.time())
  let end = pv_strip.way.end()
  assert_true(end > t.time() + 2.0 * @ui.frame_period_default, msg="a way of some frames")
  // (a frame on the way and the one before it ends: still aside, the node's)
  for at in [(t.time() + end) / 2.0, end - @ui.frame_period_default] {
    t.frame_at(at)
    let aside = pv_strip.way.value_at(t.time())
    assert_true(aside != 0.0 && picture_node() is Some(_), msg="\{at}: aside \{aside}, the node's")
    assert_eq(main_pictures(t, v, aside), 1, msg="\{at}: drawn once")
  }
  // (the frame it ends in, and the one after)
  t.frame_at(end)
  assert_true(picture_node() is Some(_), msg="at its end: the node's")
  assert_eq(main_pictures(t, v, 0.0), 1, msg="at its end: drawn once")
  t.frame_at(end + @ui.frame_period_default)
  assert_eq(main_pictures(t, v, 0.0), 1, msg="after: drawn once")
}

///|
test "viewer on the tree: its stand-in decoded and shown, then the picture itself said not to decode: its words saying so alone, no picture where it lay, neither the stand-in nor it" {
  let t = preview_tester("image", finish=false)
  let v = viewer.get().unwrap()
  let main = "mem:preview/" + v.id()
  // (each decode but the picture's own done)
  for _ in 0..<3 {
    for p in t.pending() {
      if p.0 != 1 || !t.image_src(p.1).has_prefix(main) {
        t.finish(p.0, p.1)
      }
    }
    t.draw()
  }
  t.run_for(@ui.move_most_ms)
  assert_true(picture_node() is Some(_), msg="the node's")
  let (x, y, w, h) = v.zoom.rect().unwrap()
  let shown = t.drawn_instances().filter(fn(i) { i[5] == 4.0 && (i[0] - x).abs() < 0.5 && (i[1] - y).abs() < 0.5 && (i[2] - w).abs() < 0.5 && (i[3] - h).abs() < 0.5 }).map(fn(i) { t.image_src(i[20].to_int()) })
  assert_true(shown.length() == 1 && shown[0] != main, msg="its stand-in shown: \{shown}")
  assert_eq(main_pictures(t, v, 0.0), 1, msg="drawn where it lies")
  // (the picture's own decode said not to be)
  let own = t.pending().filter(fn(p) { p.0 == 1 && t.image_src(p.1).has_prefix(main) })
  assert_eq(own.length(), 1, msg="its own decode asked for, one")
  t.finish(1, own[0].1, ok=false)
  t.draw()
  assert_eq(@ui.image_state(main), -1, msg="not to be decoded")
  assert_true(t.find(pv("android-chat.file.image.failed")) is Some(_), msg="said so")
  assert_eq(picture_node(), None, msg="none of the node's")
  assert_eq(main_pictures(t, v, 0.0), 0, msg="nothing where it lay")
}

///|
/// The window's tree's nodes drawing `src` as small decodes asked for out of sight (Viewer::size_unknown's): 1 by 1,
/// drawn at none.
fn size_asks(src : String) -> Array[@view.Drawn] {
  @ui.view_tree().unwrap().drawn().filter(fn(d) {
    match d.image {
      Some((s, _, _)) => s == src && d.w == 1.0 && d.h == 1.0
      None => false
    }
  })
}

///|
test "viewer on the tree: its picture said not to decode: why, in words of the window's tree's node alone, none of the old view's, in the middle of the stage, muted; nothing of its picture asked for or drawn there" {
  let t = preview_tester("image", w=390.0, platform=2, finish=false)
  let v = viewer.get().unwrap()
  // (each picture asked for could not be decoded, as the host says)
  for _ in 0..<3 {
    for p in t.pending() {
      t.finish(p.0, p.1, ok=p.0 != 1)
    }
    t.draw()
  }
  let main = "mem:preview/" + v.id()
  assert_eq(@ui.image_state(main), -1, msg="its picture not decoded")
  let said = pv("android-chat.file.image.failed")
  let all = t.words().filter(fn(w) { w.0 == said })
  let nodes = @ui.view_tree().unwrap().drawn().filter(fn(d) { d.words == said })
  assert_eq(nodes.length(), 1, msg="said by the tree's node: \{all}")
  assert_eq(all.length(), 1, msg="said once: \{all}")
  let d = nodes[0]
  assert_eq(d.ink, @sf.theme().p.muted, msg="in the theme's muted ink, as the viewer's other words on its canvas")
  assert_eq(d.words_look.size, @sf.theme().t.body, msg="the body's size")
  assert_eq((d.x + d.w / 2.0, d.y + d.h / 2.0), (195.0, 422.0), msg="in the middle: \{all}")
  assert_eq(size_asks(main).length(), 0, msg="its size asked for no more")
  assert_eq(picture_node(), None, msg="no picture drawn by the tree")
}

///|
test "viewer on the tree: a picture whose size is not known yet (none said, nothing standing in): a small decode of it asked for by the window's tree's node, drawing none of it, none of the old view's; decoded, it lies where its size says, asked for no more" {
  let t = preview_tester("step", w=390.0, platform=2, finish=false)
  let (a, _) = preview_files().iter().find_first(fn(f) { f.0.name == "界面草图.png" }).unwrap()
  open_preview("ws1/st1", "s-c1", { ..a, width: 0.0, height: 0.0, thumbhash: "" }, steps=InChat(Some(1.0), "s-c1"))
  t.run_for(@ui.move_most_ms)
  let v = viewer.get().unwrap()
  assert_true(v.zoom.rect() is None, msg="where it is not known")
  let main = "mem:preview/" + v.id()
  let asks = size_asks(main)
  assert_eq(asks.length(), 1, msg="asked by the tree's node")
  assert_eq(asks[0].alpha, 0.0, msg="drawn at none")
  // (nothing of it drawn: the old view's 1 by 1 at 0.01 none)
  let small = t.drawn_instances().filter(fn(i) { i[5] == 4.0 && t.image_src(i[20].to_int()).has_prefix(main) })
  assert_eq(small.length(), 0, msg="none drawn: \{small}")
  // (nor asked for by the old view: no picture of it built there, drawn or not)
  let built = t.image_nodes().filter(fn(n) { n.0 == main })
  assert_eq(built.length(), 0, msg="none of the old view's: \{built}")
  // (asked for small: the host's decode of it, at the 1 drawn at the window's pixels)
  let own = t.pending().filter(fn(p) { p.0 == 1 && t.image_src(p.1).has_prefix(main) })
  assert_eq(own.length(), 1, msg="its decode asked for, one")
  for p in t.pending() {
    t.finish(p.0, p.1)
  }
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(v.zoom.rect() is Some(_), msg="where it lies, known")
  // (its whole decode, asked for as it is drawn where it lies, done)
  for p in t.pending() {
    t.finish(p.0, p.1)
  }
  t.draw()
  let (x, y, w, h) = v.zoom.rect().unwrap()
  let lying = t.drawn_instances().filter(fn(i) { i[5] == 4.0 && t.image_src(i[20].to_int()).has_prefix(main) && (i[0] - x).abs() < 0.5 && (i[1] - y).abs() < 0.5 && (i[2] - w).abs() < 0.5 && (i[3] - h).abs() < 0.5 })
  assert_eq(lying.length(), 1, msg="the picture itself drawn where it lies, once: \{lying.length()}")
  assert_eq(size_asks(main).length(), 0, msg="asked for no more")
}

///|
test "viewer on the tree: a picture whose size is not known yet (none said, nothing standing in) said not to decode: why, in words of the window's tree's node; its size asked for no more" {
  let t = preview_tester("step", w=390.0, platform=2, finish=false)
  let (a, _) = preview_files().iter().find_first(fn(f) { f.0.name == "界面草图.png" }).unwrap()
  open_preview("ws1/st1", "s-c1", { ..a, width: 0.0, height: 0.0, thumbhash: "" }, steps=InChat(Some(1.0), "s-c1"))
  t.run_for(@ui.move_most_ms)
  let v = viewer.get().unwrap()
  let main = "mem:preview/" + v.id()
  assert_true(v.zoom.rect() is None, msg="its size not known")
  assert_eq(size_asks(main).length(), 1, msg="its size asked for")
  // (each picture asked for said not to decode, as the host says: its own, and what would stand in for it, the
  // station's thumbnail, so no size is known of either)
  for p in t.pending() {
    t.finish(p.0, p.1, ok=p.0 != 1)
  }
  t.draw()
  assert_eq(@ui.image_state(main), -1, msg="not to be decoded")
  assert_true(v.zoom.rect() is None, msg="its size still not known: \{v.zoom.nw} x \{v.zoom.nh}")
  let said = pv("android-chat.file.image.failed")
  assert_eq(@ui.view_tree().unwrap().drawn().filter(fn(d) { d.words == said }).length(), 1, msg="said by the tree's node, unknown")
  assert_eq(size_asks(main).length(), 0, msg="its size asked for no more once it failed")
}

///|
/// A picture of the chat opened by its thumbnail tapped (preview_wbtest's flight back: chat-preview-named, the chat at
/// rest, a row put up at a time till compare.png shows), its flight set out, nothing run yet: the tester (`finish`: what
/// it asks the host done as it asks it, else what it asked before it opened done, what it asks from then on when the
/// test says).
fn opening(finish? : Bool = true) -> @ui.Tester raise {
  new_run()
  let src = fixture("chat-preview-named")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, finish~)
  nav_rested(t)
  let mut tries = 0
  while t.locate("img:compare.png").length() == 0 && tries < 12 {
    let (first, _) = t.visible()
    t.scroll_to(if first > 0 { first - 1 } else { 0 })
    t.draw()
    tries += 1
  }
  let at = t.locate("img:compare.png")
  assert_true(at.length() > 0, msg="its thumbnail")
  // (what was asked before it opens done, the chat's thumbnail among it)
  if !finish {
    for p in t.pending() {
      t.finish(p.0, p.1)
    }
    t.draw()
  }
  t.tap(at[0].0, at[0].1)
  t
}

///|
/// The pictures drawn now at least half as wide as viewer `v`'s where it lies.
fn big_pictures(t : @ui.Tester, v : Viewer) -> Int {
  let (_, _, w, _) = v.zoom.rect().unwrap()
  drawn_pictures(t).filter(fn(d) { d.2 >= w / 2.0 }).length()
}

///|
/// The window's tree's node drawing viewer `v`'s picture as it flies (its whole picture or what stands in for it), where
/// it is drawn: none, else one.
fn flight_nodes(v : Viewer, src : Source) -> Array[(Double, Double, Double, Double)] {
  let shown = ["mem:preview/" + v.id(), v.stand_in(src)].filter(fn(s) { s != "" })
  @ui.view_tree().unwrap().drawn().filter_map(fn(d) {
    match d.image {
      Some((s, _, _)) if shown.contains(s) => Some((d.x, d.y, d.w, d.h))
      _ => None
    }
  })
}

///|
test "viewer on the tree: its picture flying in drawn by its nodes, once, in each frame from the first to the one before it lands, cut and round as its flight has it; landed, by the node it lies in, once; the same with no frame drawn between" {
  for between in [true, false] {
    let t = opening()
    let src = preview_src.val.unwrap_or(fixture("chat-preview-named"))
    let v = viewer.get().unwrap()
    assert_true(v.flies && !v.fly_back && v.fly.goes_at(t.time()), msg="flying in")
    let end = v.fly.end()
    if between {
      for at in [t.time() + @ui.frame_period_default, (t.time() + end) / 2.0, end - @ui.frame_period_default] {
        t.frame_at(at)
        let nodes = flight_nodes(v, src)
        assert_eq(nodes.length(), 1, msg="\{at}: flying, its node's: \{nodes}")
        let (x, y, w, h) = nodes[0]
        let at_it = drawn_pictures(t).filter(fn(d) { (d.0 - x).abs() < 0.5 && (d.1 - y).abs() < 0.5 && (d.2 - w).abs() < 0.5 && (d.3 - h).abs() < 0.5 })
        assert_eq(at_it.length(), 1, msg="\{at}: flying, drawn once there: \{drawn_pictures(t)}")
      }
    }
    t.frame_at(end)
    assert_true(!v.flies, msg="landed")
    assert_true(picture_node() is Some(_), msg="\{between}: landed, the node's")
    assert_eq(main_pictures(t, v, 0.0), 1, msg="\{between}: landed, drawn once")
    t.frame_at(end + @ui.frame_period_default)
    assert_eq(main_pictures(t, v, 0.0), 1, msg="\{between}: after, drawn once")
  }
}

///|
/// The decode each picture drawn now at least `w` wide is drawn from (its instance's id, image.mbt's draw_image).
fn decodes_drawn(t : @ui.Tester, w : Double) -> Array[Int] {
  t.drawn_instances().filter(fn(i) { i[5] == 4.0 && i[2] >= w }).map(fn(i) { i[20].to_int() })
}

///|
test "viewer on the tree: its picture zoomed in at once, a sharper decode asked for, bigger; drawn from the one before till it is done, from it in the frame after the host says so" {
  let t = preview_tester("image", finish=false)
  let v = viewer.get().unwrap()
  for p in t.pending() {
    t.finish(p.0, p.1)
  }
  t.draw()
  t.run_for(@ui.move_most_ms)
  let main = "mem:preview/" + v.id()
  assert_eq(picture_node(), Some(main), msg="the picture itself")
  let before = decodes_drawn(t, 300.0)
  assert_eq(before.length(), 1, msg="drawn, from one decode")
  let asked = fn() { t.image_loads().filter(fn(l) { l.0.has_prefix("bytes:") }).map(fn(l) { l.1 }) }
  let sizes = asked()
  // (four times as big, at once)
  v.zoom.zoom_to(v.zoom.fit() * 4.0, v.zoom.bw / 2.0, v.zoom.bh / 2.0, false, at=t.time())
  t.draw()
  let sharper = t.pending().filter(fn(p) { p.0 == 1 && t.image_src(p.1) == main })
  assert_eq(sharper.length(), 1, msg="a sharper decode asked for, one")
  let now = asked()
  assert_true(now.length() == sizes.length() + 1 && now[now.length() - 1] > sizes[sizes.length() - 1], msg="asked bigger: \{sizes} then \{now}")
  assert_eq(decodes_drawn(t, 300.0), before, msg="drawn from the one before while it decodes")
  t.finish(1, sharper[0].1)
  t.draw()
  assert_eq(decodes_drawn(t, 300.0), [sharper[0].1], msg="drawn from the sharper one in the frame after")
}

///|
/// Where the picture flying from thumbnail `from` (gone out from under the bar `lifted` of the way) to `to` is drawn,
/// `p` of the way there: from where it lies in the thumbnail's box (covering it, or fitted inside it; at its top where
/// it is cropped so) to its place.
fn flight_picture_at(
  from : @sfbase.Thumb,
  lifted : Double,
  to : (Double, Double, Double, Double),
  p : Double,
) -> (Double, Double, Double, Double) {
  let fy = from.y + @sfbase.lift_of(from) * lifted
  let (tx, ty, tw, th) = to
  let k = if from.letterbox { dmin(from.w / tw, from.h / th) } else { dmax(from.w / tw, from.h / th) }
  let (pw0, ph0) = (tw * k, th * k)
  let px0 = from.x + (from.w - pw0) / 2.0
  let py0 = fy + (if from.top_crop { 0.0 } else { (from.h - ph0) / 2.0 })
  let along = fn(a : Double, b : Double) { a + (b - a) * p }
  (along(px0, tx), along(py0, ty), along(pw0, tw), along(ph0, th))
}

///|
test "viewer on the tree: closed, the chat moved under it on the way back, then its thumbnail off the screen: the picture flies from where the thumbnail is in the frame drawn, then on to where it was last, once in each frame, and is let go as it lands" {
  let t = opening()
  let v = viewer.get().unwrap()
  t.run_for(@ui.move_most_ms)
  let id = v.id()
  let main = "mem:preview/" + id
  t.back()
  assert_true(v.flies && v.fly_back, msg="flying back")
  let end = v.fly.end()
  t.frame_at(t.time() + (end - t.time()) / 3.0)
  let was = thumb_of(t.ctx(), id).unwrap()
  // (the chat moved under it: a row along)
  let (first, _) = t.visible()
  t.scroll_to(if first > 0 { first - 1 } else { first + 1 })
  t.frame_at(t.time() + @ui.frame_period_default)
  let moved = thumb_of(t.ctx(), id).unwrap()
  assert_true((moved.y - was.y).abs() > 1.0, msg="moved: \{was.y} to \{moved.y}")
  // (kept as where it flies from in the frame it moved: where it is now, not where it was)
  let kept = v.fly_from.map(fn(f) { (f.x, f.y, f.w, f.h) })
  assert_eq(kept, Some((moved.x, moved.y, moved.w, moved.h)), msg="kept where it is now, in the frame it moved")
  let to = v.zoom.rect().unwrap()
  let (x, y, w, h) = flight_picture_at(moved, v.lifted(), to, v.flying())
  let shown = drawn_of(t, main)
  assert_true(shown.length() == 1 && at_rect(shown[0], x, y, w, h), msg="from where it is now, once: \{shown}, \{(x, y, w, h)}")
  // (its thumbnail off the screen: the chat scrolled far)
  let mut tries = 0
  let mut last = moved
  while thumb_of(t.ctx(), id) is Some(_) && tries < 6 {
    last = thumb_of(t.ctx(), id).unwrap()
    t.scroll_to(if tries % 2 == 0 { 0 } else { 1000 })
    t.frame_at(t.time() + @ui.frame_period_default)
    match thumb_of(t.ctx(), id) {
      Some(now) => last = now
      None => ()
    }
    tries += 1
  }
  assert_true(thumb_of(t.ctx(), id) is None, msg="off the screen")
  for at in [t.time() + @ui.frame_period_default, end - @ui.frame_period_default] {
    t.frame_at(at)
    assert_eq(v.fly_from.map(fn(f) { (f.x, f.y, f.w, f.h) }), Some((last.x, last.y, last.w, last.h)), msg="\{at}: where it was last seen")
    let (x, y, w, h) = flight_picture_at(last, v.lifted(), to, v.flying())
    let shown = drawn_of(t, main)
    assert_true(shown.length() == 1 && at_rect(shown[0], x, y, w, h), msg="\{at}: on to where it was last, once: \{shown}, \{(x, y, w, h)}")
  }
  t.frame_at(end + @ui.frame_period_default)
  assert_true(viewer.get() is None && @sfbase.pv_leaving.get() is None, msg="let go as it lands")
}

///|
/// The index in the frame's draw order of the viewer's own bar's frosted glass: the window's tree's node of glass that
/// holds its title's words `s` (the closest round them), drawn where that node is.
fn viewer_glass(t : @ui.Tester, s : String) -> Int {
  let drawn = @ui.view_tree().unwrap().drawn()
  let title = match drawn.iter().find_first(fn(d) { d.words == s }) {
    Some(d) => d
    None => return -1
  }
  let mut best : @view.Drawn? = None
  for d in drawn {
    if d.glass is Some(_) && d.x <= title.x && d.y <= title.y && d.x + d.w >= title.x + title.w && d.y + d.h >= title.y + title.h {
      match best {
        Some(b) if b.w * b.h <= d.w * d.h => ()
        _ => best = Some(d)
      }
    }
  }
  let g = match best {
    Some(g) => g
    None => return -1
  }
  let mut at = -1
  for k, i in t.drawn_instances() {
    if at < 0 && i[5] == 5.0 && (i[0] - g.x).abs() < 0.5 && (i[1] - g.y).abs() < 0.5 && (i[2] - g.w).abs() < 0.5 && (i[3] - g.h).abs() < 0.5 {
      at = k
    }
  }
  at
}

///|
/// The index in the frame's draw order of the chat's bar's frosted glass: across the whole window's top.
fn chat_glass(t : @ui.Tester) -> Int {
  let mut at = -1
  for k, i in t.drawn_instances() {
    if at < 0 && i[5] == 5.0 && i[0] <= 0.0 && i[1] <= 0.0 && i[2] >= 390.0 {
      at = k
    }
  }
  at
}

///|
test "viewer on the tree: its picture flying in, as it grows: over the viewer's ground coming in, under the viewer's own bar; the chat's bar under that ground" {
  let t = opening()
  let v = viewer.get().unwrap()
  let main = "mem:preview/" + v.id()
  let start = t.time()
  let end = v.fly.end()
  for share in [0.4, 0.6] {
    t.frame_at(start + (end - start) * share)
    let p = v.flying()
    assert_true(p > 0.0 && p < 1.0, msg="\{share}: growing, \{p}")
    let thumb = v.fly_from.map(fn(f) { f.picture }).unwrap_or("")
    let mut pic = -1
    let mut ground = -1
    for k, i in t.drawn_instances() {
      let s = if i[5] == 4.0 { t.image_src(i[20].to_int()) } else { "" }
      if i[5] == 4.0 && (s.has_prefix(main) || (thumb != "" && s.has_prefix(thumb))) {
        pic = k
      }
      // (the viewer's ground, as far in as the flight has brought it: the whole window, neither none nor all of it)
      if i[5] == 0.0 && i[0] <= 0.0 && i[1] <= 0.0 && i[2] >= 390.0 && i[3] >= 844.0 && i[11] > 0.01 && i[11] < 0.99 {
        ground = k
      }
    }
    let head = viewer_glass(t, "compare.png")
    let chat = chat_glass(t)
    assert_true(pic >= 0 && ground >= 0 && head >= 0 && chat >= 0, msg="\{share}: found: picture \{pic}, ground \{ground}, its bar \{head}, the chat's \{chat}")
    assert_true(ground < pic, msg="\{share}: over the ground: \{ground} \{pic}")
    let titles = t.words().filter(fn(w) { w.0 == "compare.png" })
    let glass = t.drawn_instances().mapi(fn(k, i) { (k, i) }).filter(fn(e) { e.1[5] == 5.0 }).map(fn(e) { (e.0, e.1[0].round(), e.1[1].round(), e.1[2].round(), e.1[3].round()) })
    assert_true(pic < head, msg="\{share}: under its bar: \{pic} \{head}; titles \{titles}; glass \{glass}")
    assert_true(chat < ground, msg="\{share}: the chat's bar under the ground: \{chat} \{ground}")
  }
}

///|
test "viewer on the tree: its picture said not to decode as it flies in, its stand-in ready: its words alone, once; nothing of it flying, drawn or a node's" {
  let t = opening(finish=false)
  let v = viewer.get().unwrap()
  let main = "mem:preview/" + v.id()
  let thumb = v.fly_from.map(fn(f) { f.picture }).unwrap_or("")
  assert_true(thumb != "" && @ui.image_state(thumb) == 1, msg="its stand-in ready: \{thumb}")
  let end = v.fly.end()
  // (its own decode said not to be; every other done)
  for _ in 0..<3 {
    for p in t.pending() {
      t.finish(p.0, p.1, ok=!(p.0 == 1 && t.image_src(p.1).has_prefix(main)))
    }
    t.frame_at(t.time() + @ui.frame_period_default)
  }
  assert_eq(@ui.image_state(main), -1, msg="not to be decoded")
  t.frame_at((t.time() + end) / 2.0)
  assert_true(v.flies, msg="flying")
  let said = pv("android-chat.file.image.failed")
  assert_eq(t.words().filter(fn(w) { w.0 == said }).length(), 1, msg="said once")
  let flying = drawn_of(t, main).length() + drawn_of(t, thumb).length() + nodes_of(main).length() + nodes_of(thumb).length()
  assert_eq(flying, 0, msg="no flight while it failed: \{drawn_of(t, thumb)} \{nodes_of(thumb)}")
}

///|
test "viewer on the tree: its picture flying in, a frame drawn for a moment later than the logic is at (as a host times one for its vsync): drawn where its flight has it at that moment, once; the next frame on from there" {
  let t = opening()
  let v = viewer.get().unwrap()
  let id = v.id()
  let main = "mem:preview/" + id
  let thumb = v.fly_from.map(fn(f) { f.picture }).unwrap_or("")
  let end = v.fly.end()
  let now = t.time() + (end - t.time()) / 3.0
  let shown = now + 2.0 * @ui.frame_period_default
  // (where its flight has it at `at`: Viewer::flying's, lifted's)
  let at_moment = fn(at : Double) {
    let e = v.fly.value_at(at)
    let lift = v.fly_lift
    let p = if e <= lift { 0.0 } else { (e - lift) / (1.0 - lift) }
    let lifted = if lift <= 0.0 { 1.0 } else { dmin(e / lift, 1.0) }
    flight_picture_at(thumb_of(t.ctx(), id).unwrap(), lifted, v.zoom.rect().unwrap(), p)
  }
  let flying = fn() {
    t.drawn_instances().filter(fn(i) { i[5] == 4.0 && (t.image_src(i[20].to_int()).has_prefix(main) || (thumb != "" && t.image_src(i[20].to_int()).has_prefix(thumb))) }).map(fn(i) { (i[0], i[1], i[2], i[3]) })
  }
  t.frame_shown_at(now, shown)
  let (x, y, w, h) = at_moment(shown)
  let drawn = flying()
  assert_true(drawn.length() == 1 && at_rect(drawn[0], x, y, w, h), msg="drawn where it is at the moment shown: \{drawn}, \{(x, y, w, h)}")
  let next = shown + @ui.frame_period_default
  t.frame_shown_at(next, next)
  let (x, y, w, h) = at_moment(next)
  let drawn = flying()
  assert_true(drawn.length() == 1 && at_rect(drawn[0], x, y, w, h), msg="the next frame on from there: \{drawn}, \{(x, y, w, h)}")
}

///|
test "viewer on the tree: its picture flying in cut to the thumbnail's own corners, each as its container resolves it, as round as the flight leaves them: the box its node's, the picture cut so" {
  let t = opening()
  let v = viewer.get().unwrap()
  let id = v.id()
  let main = "mem:preview/" + v.id()
  let thumb = v.fly_from.map(fn(f) { f.picture }).unwrap_or("")
  let end = v.fly.end()
  t.frame_at(t.time() + (end - t.time()) / 4.0)
  let (tl, tr, br, bl) = thumb_of(t.ctx(), id).unwrap().corners.each()
  let k = 1.0 - v.flying()
  let want = (tl * k, tr * k, br * k, bl * k)
  let boxes = @ui.view_tree().unwrap().drawn().filter(fn(d) { d.corners is Some(_) })
  assert_eq(boxes.map(fn(d) { d.corners }), [Some(want)], msg="its box's corners")
  let cut = t.drawn_instances().filter(fn(i) { i[5] == 4.0 && (t.image_src(i[20].to_int()).has_prefix(main) || (thumb != "" && t.image_src(i[20].to_int()).has_prefix(thumb))) }).map(fn(i) { (i[24], i[25], i[26], i[27]) })
  assert_eq(cut.length(), 1, msg="drawn once")
  let (a, b, c, d) = cut[0]
  let near = fn(x : Double, y : Double) { (x - y).abs() < 0.01 }
  assert_true(near(a, want.0) && near(b, want.1) && near(c, want.2) && near(d, want.3), msg="cut so: \{cut[0]}, \{want}")
}

///|
/// The coverage at corners of picture instances `pics` (landing, then landed) against `before` (the thumbnail as it lay
/// before it was opened), 40 by 40 at each of its corners on the device's pixels (`scale` a point): the pixels whose
/// cover differs by more than half.
fn corners_changed(before : Array[Double], pics : Array[Array[Double]], scale : Double) -> Int {
  let (x, y, w, h) = (before[0], before[1], before[2], before[3])
  let n = (40.0 * scale).ceil().to_int()
  let mut bad = 0
  for origin in [(x, y), (x + w - 40.0, y), (x + w - 40.0, y + h - 40.0), (x, y + h - 40.0)] {
    for ix in 0..<n {
      for iy in 0..<n {
        let px = origin.0 + (ix.to_double() + 0.5) / scale
        let py = origin.1 + (iy.to_double() + 0.5) / scale
        let want = corner_cover(before, px, py, scale)
        for p in pics {
          if (corner_cover(p, px, py, scale) - want).abs() > 0.5 {
            bad += 1
          }
        }
      }
    }
  }
  bad
}

///|
test "viewer on the tree: closed back into its thumbnail: the frame drawn for a moment past the flight's end, its logic just before it, and the frame after cover the thumbnail's corners as it lay before it opened, on the device's pixels" {
  let t = opening()
  let v = viewer.get().unwrap()
  t.run_for(@ui.move_most_ms)
  let thumb = v.fly_from.map(fn(f) { f.picture }).unwrap_or("")
  let main = "mem:preview/" + v.id()
  let pictures = fn() {
    t.drawn_instances().filter(fn(i) { i[5] == 4.0 && i[11] > 0.5 && i[2] > 40.0 && (t.image_src(i[20].to_int()).has_prefix(main) || (thumb != "" && t.image_src(i[20].to_int()).has_prefix(thumb))) })
  }
  // (closed once, at rest: the thumbnail as it lies, then opened and closed again)
  t.back()
  t.run_for(@ui.move_most_ms)
  let before = pictures()
  assert_eq(before.length(), 1, msg="the thumbnail at rest")
  let at = t.locate("img:compare.png")
  t.tap(at[0].0, at[0].1)
  t.run_for(@ui.move_most_ms)
  t.back()
  // (the one closed: going, its flight back said)
  let v2 = @sfbase.pv_leaving.get().unwrap()
  let end = v2.fly.end()
  t.frame_shown_at(end - 0.01, end + 0.01)
  let landing = pictures()
  assert_eq(landing.length(), 1, msg="landing, once")
  t.frame_at(end + @ui.frame_period_default)
  let after = pictures()
  assert_eq(after.length(), 1, msg="landed, the thumbnail")
  assert_eq(corners_changed(before[0], [landing[0], after[0]], t.ctx().scale), 0, msg="pixels changing at a corner")
}

///|
/// The flight photo's picture in a card 300 by 225 its corners each as `corners` says (top left, then round it), shown
/// while `shown` says, an old view's in a window of the tree's, beside the viewer as the shells have it
/// (sfbase's viewer_node, its stage the window), on `scale` pixels a point; seen once its picture is decoded: the
/// tester, and what the picture's file is known by.
fn cornered_card(
  corners : @signals.Signal[(Double, Double, Double, Double)],
  shown : @signals.Signal[Bool],
  scale : Double,
) -> (@ui.Tester, Source) {
  new_run()
  let a = flight_photo()
  @sfbase.sent_pictures[@sfbase.sent_key("ws1/st1", a.path)] = "sent-key"
  let src = fixture("chat")
  let t = @ui.Tester::new(
    // (the old views the tree hosts built where the frame builds them, as the app's view has it)
    fn(c) { @ui.old_views_here(c) },
    tree=fn(root) {
      root.box(fn(v) {
        v.grow(Is(1.0)) |> ignore
        @ui.old(v, fn(c) {
          let (tl, tr, br, bl) = corners.get()
          if shown.get() {
            let radius = @ui.Radius::Corners(tl, tr, br, bl)
            c.box(style=@ui.style(w=Fixed(300.0), h=Fixed(225.0), radius~, clip=true), fn() { chat_file(c, src, a) })
            |> ignore
          }
        })
        .over(Is(true))
        |> ignore
        @sfbase.viewer_node(v, src, fn() { v.window() })
      })
      |> ignore
    },
    w=390.0,
    h=844.0,
    scale~,
    images=[("sent-key", 1200, 900), ("mem:preview/ws1/st1/s-c1/uploads/fx/photo.jpg", 1200, 900)],
  )
  t.draw()
  t.run_for(@ui.image_fade_ms)
  (t, src)
}

///|
test "viewer on the tree, from a card its corners each unlike: closed back into it, the frame drawn for a moment past the flight's end and the frame after cover its corners as it lay before it opened, on the device's pixels" {
  let scale = 3.25
  let corners = @signals.signal((40.0, 10.0, 30.0, 20.0), same=fn(a, b) { a == b })
  let (t, _) = cornered_card(corners, @signals.signal(true), scale)
  let pictures = fn() { t.drawn_instances().filter(fn(p) { p[5] == 4.0 && p[2] > 40.0 && p[11] > 0.5 }) }
  let before = pictures()
  assert_eq(before.length(), 1, msg="the thumbnail: \{t.image_nodes()} \{@ui.view_tree().unwrap().drawn().filter(fn(d) { d.hosted }).map(fn(d) { (d.x, d.y, d.w, d.h) })}")
  // (its corners unlike, its own or its card's that cut it: scene.mbt's 36-39, 24-27)
  let own = [before[0][36], before[0][37], before[0][38], before[0][39]]
  let cut = [before[0][24], before[0][25], before[0][26], before[0][27]]
  let unlike = fn(a : Array[Double]) { a.iter().any(fn(r) { r != a[0] }) }
  assert_true(unlike(own) || unlike(cut), msg="its corners unlike: \{own} \{cut}")
  let at = t.locate("img:sent-key")
  assert_eq(at.length(), 1, msg="the card's picture: \{t.image_nodes()} \{@ui.view_tree().unwrap().drawn().filter(fn(d) { d.hosted }).map(fn(d) { (d.x, d.y, d.w, d.h) })}")
  t.tap(at[0].0, at[0].1)
  assert_true(viewer.get() is Some(_), msg="opened")
  let v = viewer.get().unwrap()
  assert_true(v.in_tree, msg="the window's tree's viewer")
  t.run_for(@ui.move_most_ms)
  t.back()
  let end = v.fly.end()
  t.frame_shown_at(end - 0.01, end + 0.01)
  let landing = pictures()
  assert_eq(landing.length(), 1, msg="landing")
  t.frame_at(end + @ui.frame_period_default)
  let after = pictures()
  assert_eq(after.length(), 1, msg="landed")
  assert_eq(corners_changed(before[0], [landing[0], after[0]], scale), 0, msg="pixels changing at a corner")
}

///|
test "viewer on the tree, from a card: its corners changed as the picture flies back, nothing else of it: kept as they are now in the frame they change; the card gone, kept as they were last" {
  let corners = @signals.signal((40.0, 10.0, 30.0, 20.0), same=fn(a, b) { a == b })
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let (t, src) = cornered_card(corners, shown, 2.0)
  let at = t.locate("img:sent-key")
  assert_eq(at.length(), 1, msg="the card's picture: \{t.image_nodes()} \{@ui.view_tree().unwrap().drawn().filter(fn(d) { d.hosted }).map(fn(d) { (d.x, d.y, d.w, d.h) })}")
  t.tap(at[0].0, at[0].1)
  assert_true(viewer.get() is Some(_), msg="opened")
  let v = viewer.get().unwrap()
  assert_true(v.in_tree, msg="the window's tree's viewer")
  t.run_for(@ui.move_most_ms)
  let id = v.id()
  t.back()
  let end = v.fly.end()
  t.frame_at(t.time() + (end - t.time()) / 3.0)
  assert_eq(flight_nodes(v, src).length(), 1, msg="flying back, its node's")
  let was = thumb_of(t.ctx(), id).unwrap()
  assert_eq(v.fly_from.map(fn(f) { f.corners.each() }), Some((40.0, 10.0, 30.0, 20.0)), msg="kept as they are")
  // (its corners changed, nothing else of it)
  corners.set((5.0, 25.0, 15.0, 35.0))
  t.frame_at(t.time() + @ui.frame_period_default)
  let now = thumb_of(t.ctx(), id).unwrap()
  assert_eq((now.x, now.y, now.w, now.h), (was.x, was.y, was.w, was.h), msg="where it was, as big")
  assert_eq(now.corners.each(), (5.0, 25.0, 15.0, 35.0), msg="its corners as they are now")
  assert_eq(v.fly_from.map(fn(f) { f.corners.each() }), Some((5.0, 25.0, 15.0, 35.0)), msg="kept as they are now, in the frame they change")
  // (the card gone)
  shown.set(false)
  // (its measure the frame it was last laid out in's till a frame has passed without it: measured_rect)
  let mut frames = 0
  while thumb_of(t.ctx(), id) is Some(_) && frames < 3 {
    t.frame_at(t.time() + @ui.frame_period_default)
    frames += 1
  }
  assert_true(thumb_of(t.ctx(), id) is None, msg="gone, \{frames} frames on")
  t.frame_at(t.time() + @ui.frame_period_default)
  assert_eq(v.fly_from.map(fn(f) { f.corners.each() }), Some((5.0, 25.0, 15.0, 35.0)), msg="kept as they were last")
  let k = 1.0 - v.flying()
  let boxes = @ui.view_tree().unwrap().drawn().filter(fn(d) { d.corners is Some(_) }).map(fn(d) { d.corners })
  assert_eq(boxes, [Some((5.0 * k, 25.0 * k, 15.0 * k, 35.0 * k))], msg="its box round as they were last")
}

///|
test "viewer on the tree: what its canvas holds of an old view's, not marking: the words being written's alone (no old view drawing the picture)" {
  let t = preview_tester("image")
  t.run_for(@ui.move_most_ms)
  let v = viewer.get().unwrap()
  let main = "mem:preview/" + v.id()
  let held = @ui.view_tree().unwrap().drawn_held()
  let at = held.search_by(fn(e) {
    match e.0.image {
      Some((s, _, _)) => s == main
      None => false
    }
  })
  assert_true(at is Some(_), msg="its picture lying flat, a node's")
  // (what holds the picture: the canvas; of what it holds, those an old view draws)
  let canvas = held[at.unwrap()].1
  let hosted = held.filter(fn(e) { e.1 == canvas && e.0.hosted })
  assert_eq(hosted.length(), 1, msg="an old view's: the words being written's alone: \{hosted.length()}")
}

///|
test "viewer on the tree: what it adds of an old view's to the window, open, not marking: the words being written's alone (none drawing its bars)" {
  let t = preview_tester("image")
  t.run_for(@ui.move_most_ms)
  let hosted = fn() { @ui.view_tree().unwrap().drawn().filter(fn(d) { d.hosted }).length() }
  let open = hosted()
  assert_true(viewer.get() is Some(_), msg="open")
  t.back()
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is None && @sfbase.pv_leaving.get() is None, msg="gone")
  assert_eq(open - hosted(), 1, msg="of an old view's, open: the words being written's alone")
}
