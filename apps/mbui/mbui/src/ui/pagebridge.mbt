// A page's view and the app, under a Tester (native.mbt: NativeView::page's and ::site's `said`, ::script, ::touch):
// what a page's host says to the app put in its queue by the test (Tester::view_says, site_no_answer, site_too_slow),
// the scripts the app had the page run (Tester::view_scripts), and a test's fingers taken as a host takes them: a
// finger that goes down on a page's view (shown, where it was last placed) is the page's (the view's line "finger ID
// down X Y" in Tester::views, the canvas sees none of it), unless the view says otherwise (NativeView::touch:
// `Through`, the canvas's; `VerticalOut`, the canvas's from where it went down once it has gone further up or down
// than across past the slop, unless it went sideways past it first; `PinchOut`, once a second finger comes down, the
// first given where it is now before it: the page told "finger ID cancel").

///|
/// What a page's host says (view_site_next's JSON) put in view `id`'s queue (a view the fake host has not opened: the
/// queue every view takes from).
fn fake_site_push(f : FakeHost, id : Int, event : String) -> Unit {
  if f.view_kinds.contains(id) {
    match f.site_of.get(id) {
      Some(q) => q.push(event)
      None => f.site_of[id] = [event]
    }
  } else {
    f.site.push(event)
  }
  f.wants = true
}

///|
/// View `id`'s page says `text` to the app (its scripts' `mbuiHost.post(text)`): `said` hears it as the next frame
/// begins, after what was said before it.
pub fn Tester::view_says(self : Tester, id : Int, text : String) -> Unit {
  fake_site_push(self.fake, id, Json::object({ "said": Json::string(text) }).stringify())
  g().wants_frame = true
}

///|
/// Site view `id`'s request `req` has had no head of its answer in `site_head_wait_ms` (as its host says, `{"late":N}`).
pub fn Tester::site_no_answer(self : Tester, id : Int, req : Int) -> Unit {
  fake_site_push(self.fake, id, "{\"late\":\{req}}")
  g().wants_frame = true
}

///|
/// Site view `id`'s request `req` is read by its page so slowly that more than `site_backlog_max` of it waits (as its
/// host says, `{"slow":N}`).
pub fn Tester::site_too_slow(self : Tester, id : Int, req : Int) -> Unit {
  fake_site_push(self.fake, id, "{\"slow\":\{req}}")
  g().wants_frame = true
}

///|
/// The scripts view `id`'s page has run (NativeView::script: once the page was there), oldest first.
pub fn Tester::view_scripts(self : Tester, id : Int) -> Array[String] {
  self.fake.scripts_run.get(id).unwrap_or([])
}

///|
/// The page's view a point is on (shown, the last placed of those it is on, not where a press of the app's is drawn
/// over it), with who takes a finger on it; 0 none.
fn fake_view_under(f : FakeHost, x : Double, y : Double) -> (Int, String, Double) {
  let mut out = (0, "", 0.0)
  for id, at in f.view_at {
    let (x0, y0, x1, y1, shown) = at
    let kind = f.view_kinds.get(id).unwrap_or(0)
    if shown &&
      (kind == 2 || kind == 3) &&
      x >= x0 &&
      x < x1 &&
      y >= y0 &&
      y < y1 &&
      id > out.0 &&
      !fake_covered(f, id, x, y) {
      let (mode, slop) = f.view_touch.get(id).unwrap_or(("all", 0.0))
      out = (id, mode, slop)
    }
  }
  out
}

///|
/// Whether a press of the app's is drawn over view `id` at the point (view_tell 4).
fn fake_covered(f : FakeHost, id : Int, x : Double, y : Double) -> Bool {
  let r = f.view_covers.get(id).unwrap_or([])
  for j = 0; j + 3 < r.length(); j = j + 4 {
    if x >= r[j] && x < r[j + 2] && y >= r[j + 1] && y < r[j + 3] {
      return true
    }
  }
  false
}

///|
/// A test's finger (kinds as on_pointer's: 0 down, 1 moved, 2 up, 3 called off; 4, 5, 6 a second finger; 8 the first
/// let go, the second the first from here), taken as a host takes it where a page's view is.
fn finger(kind : Int, x : Double, y : Double) -> Unit {
  let f = match fake.val {
    Some(f) => f
    None => return on_pointer(kind, x, y, 0)
  }
  if kind == 0 {
    let (id, mode, _) = fake_view_under(f, x, y)
    if id > 0 && mode != "through" {
      f.touch_view = id
      f.touch_down = (x, y)
      f.touch_at = (x, y)
      f.touch_sideways = false
      f.views.push("finger \{id} down \{x} \{y}")
      return
    }
    f.touch_view = 0
    return on_pointer(kind, x, y, 0)
  }
  let id = f.touch_view
  if id == 0 {
    return on_pointer(kind, x, y, 0)
  }
  let (mode, slop) = f.view_touch.get(id).unwrap_or(("all", 0.0))
  let (dx0, dy0) = f.touch_down
  let taken = match kind {
    1 =>
      mode == "vertical" &&
      !f.touch_sideways &&
      (y - dy0).abs() > slop &&
      (y - dy0).abs() > (x - dx0).abs()
    4 => mode == "pinch"
    _ => false
  }
  if taken {
    // the page's no more: called off there, the canvas's from where it went down (a pinch's first finger then where it
    // is now, before the second comes down)
    f.views.push("finger \{id} cancel")
    f.touch_view = 0
    on_pointer(0, dx0, dy0, 0)
    if kind == 4 {
      on_pointer(1, f.touch_at.0, f.touch_at.1, 0)
    }
    on_pointer(kind, x, y, 0)
    return
  }
  if kind == 1 {
    f.touch_at = (x, y)
    // sideways first: the page's to the end of the touch
    if mode == "vertical" && (x - dx0).abs() > slop {
      f.touch_sideways = true
    }
  }
  let name = match kind {
    1 => "move"
    2 => "up"
    3 => "cancel"
    4 => "second down"
    5 => "second move"
    _ => "second up"
  }
  f.views.push("finger \{id} \{name} \{x} \{y}")
  if kind == 2 || kind == 3 {
    f.touch_view = 0
  }
}

///|
/// A test's wheel, taken as a host takes it over a page's view: the page's (All, PinchOut), the canvas's (Through,
/// VerticalOut: its upright scroll).
fn finger_wheel(x : Double, y : Double, dx : Double, dy : Double, phase : Int) -> Unit {
  match fake.val {
    Some(f) => {
      let (id, mode, _) = fake_view_under(f, x, y)
      if id > 0 && (mode == "all" || mode == "pinch") {
        f.views.push("wheel \{id} \{dx} \{dy}")
        return
      }
    }
    None => ()
  }
  on_wheel(x, y, dx, dy, phase)
}
