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
