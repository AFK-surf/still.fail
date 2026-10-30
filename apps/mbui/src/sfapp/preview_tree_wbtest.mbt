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
    read_bytes: fn(name, params, done) {
      if name == "station.file" {
        asked.val = asked.val + 1
        @sffixture.fix_later(30.0, fn() {
          if fails {
            done(Err({ "code": "gone", "message": "没了" }))
          } else {
            (base.read_bytes)(name, params, done)
          }
        })
      } else {
        (base.read_bytes)(name, params, done)
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
    read_bytes: fn(name, params, done) {
      let file = text(Some(params), "name")
      if name == "station.file" {
        asked[file] = asked.get(file).unwrap_or(0) + 1
      }
      if name == "station.file" && file == "第二版.png" {
        @sffixture.fix_later(later, fn() { (base.read_bytes)(name, params, done) })
      } else {
        (base.read_bytes)(name, params, done)
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
    read_bytes: fn(name, params, done) {
      if name == "station.file" {
        asked.push(text(Some(params), "name"))
      }
      (base.read_bytes)(name, params, done)
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
/// A made-up source whose whole files read through it are counted in `asked`.
fn counted(base : Source, asked : Ref[Int]) -> Source {
  {
    ..base,
    read_bytes: fn(name, params, done) {
      if name == "station.file" {
        asked.val = asked.val + 1
      }
      (base.read_bytes)(name, params, done)
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
  t.wheel_with(195.0, 422.0, 0.0, -wheel_notch, @ui.wheel_mod_cmd)
  assert_true(z.scale_at(t.time()) > before)
}
