// Where the host puts controls of its own over the window's tree (View::native_anchor: the system's glass buttons on
// iOS's sidebar), as drawn: each anchor is an instance of the frame, a rect of no opacity drawn as its node is, so it is
// copied, put back in a frame of the tree alone, shifted and raised wherever the layer that drew it is, by whatever way
// that is done. Its layer keeps where among its instances it is (SceneLayer's `anchors`), so the frame's end reads each
// straight from the frame's instances by its layer's first and its place, as many reads as there are anchors, never a
// walk of the frame (docs/retained.md rule 14). A layer not in the frame hands none of its anchors: the host hides
// those controls. Its rect is no part of what changed (@damage's reach of a rect that draws nothing). Its number is in
// it (slot 21, its notch's middle, read by no renderer while its notch's radius, 22, is 0): what a Tester's check finds
// walking the frame (anchors_checked), held to what the layers' places read.

///|
/// The anchors' names by their numbers, and their numbers by name: the same number for a name from frame to frame, so
/// a layer copied from the frame before reads as what it drew. Put back with each Tester (reset_globals).
let anchor_names : Array[String] = []

///|
let anchor_numbers : Map[String, Int] = {}

///|
/// The layers that drew anchors when last drawn, read as each frame ends (a layer gone, dropped as it is found so).
let anchored_layers : Map[@view.NodeId, Bool] = {}

///|
/// The anchors handed as the last frame ended: each one's name and where it was drawn, cut as it was (x, y, w, h).
let anchors_drawn : Array[(String, (Double, Double, Double, Double))] = []

///|
/// What hears the anchors as each frame ends (on_native_anchors), by the name each was said with.
let anchors_heard : Map[String, (Ctx, Array[(String, (Double, Double, Double, Double))]) -> Unit] = {}

///|
/// All of it put back, as a Tester begins (reset_globals).
fn anchors_reset() -> Unit {
  anchor_names.clear()
  anchor_numbers.clear()
  anchored_layers.clear()
  anchors_drawn.clear()
  anchors_heard.clear()
}

///|
/// Anchor `name`'s number.
fn native_anchor_number(name : String) -> Int {
  match anchor_numbers.get(name) {
    Some(n) => n
    None => {
      let n = anchor_names.length()
      anchor_names.push(name)
      anchor_numbers[name] = n
      n
    }
  }
}

///|
/// Anchor `name` drawn now, its instance the next the frame takes (`at`): kept by the layer being drawn. Its number.
fn scene_anchor_drawn(name : String, at : Int) -> Int {
  let n = native_anchor_number(name)
  match scene.drawing {
    Some(l) => l.anchors.push((n, at))
    None => ()
  }
  n
}

///|
/// Whether instance `k` of `a` is an anchor's (the number in it: slot 21 its number and one, 22 none): its number, -1
/// none.
fn anchor_of(a : FixedArray[Double], k : Int) -> Int {
  let b = k * inst_size
  if a[b + 5] == 0.0 && a[b + 11] == 0.0 && a[b + 22] == 0.0 && a[b + 21] > 0.0 {
    a[b + 21].to_int() - 1
  } else {
    -1
  }
}

///|
/// Layer `l` drawn: among the layers read for anchors as the frame ends while it has any.
fn anchors_layer_said(l : SceneLayer) -> Unit {
  if l.anchors.is_empty() {
    anchored_layers.remove(l.id)
  } else {
    anchored_layers[l.id] = true
  }
}

///|
/// The anchors as the frame `c` drew them: each of the layers that drew some and are in this frame, read by its first
/// instance and each anchor's place, cut by the clip it was drawn in; none that was cut out of sight.
fn Ctx::anchors_now(self : Ctx) -> Array[(String, (Double, Double, Double, Double))] {
  let out = []
  let gone = []
  for id, _ in anchored_layers {
    match scene.layers.get(id) {
      Some(l) if l.seen == scene.frame && l.start >= 0 =>
        for a in l.anchors {
          let k = l.start + a.1
          if k < self.ninst {
            match anchor_rect(self.inst, k) {
              Some(r) => out.push((anchor_names[a.0], r))
              None => ()
            }
          }
        }
      Some(_) => ()
      None => gone.push(id)
    }
  }
  for id in gone {
    anchored_layers.remove(id)
  }
  out
}

///|
/// Instance `k` of `a` as a rect cut by its clip (x, y, w, h): None where nothing of it is left.
fn anchor_rect(a : FixedArray[Double], k : Int) -> (Double, Double, Double, Double)? {
  let b = k * inst_size
  let x0 = dmax(a[b], a[b + 16])
  let y0 = dmax(a[b + 1], a[b + 17])
  let x1 = dmin(a[b] + a[b + 2], a[b + 18])
  let y1 = dmin(a[b + 1] + a[b + 3], a[b + 19])
  if x1 > x0 && y1 > y0 {
    Some((x0, y0, x1 - x0, y1 - y0))
  } else {
    None
  }
}

///|
/// As a frame's paint is over: its anchors read, and told what hears them.
fn Ctx::anchors_after_paint(self : Ctx) -> Unit {
  let now = self.anchors_now()
  anchors_drawn.clear()
  anchors_drawn.append(now)
  if frame_checked() {
    self.anchors_checked(now)
  }
  for _, f in anchors_heard {
    f(self, now)
  }
}

///|
/// What the last frame drew of the host's controls' anchors (View::native_anchor): each one's name and where it was
/// drawn, as big and as cut as it was (x, y, w, h); none of one not drawn.
pub fn native_anchors() -> Array[(String, (Double, Double, Double, Double))] {
  anchors_drawn.copy()
}

///|
/// Where the last frame drew anchor `name` (native_anchors'), None where it drew none.
pub fn native_anchor_drawn(name : String) -> (Double, Double, Double, Double)? {
  for a in anchors_drawn {
    if a.0 == name {
      return Some(a.1)
    }
  }
  None
}

///|
/// `f` told the anchors (native_anchors') as each frame's paint is over, from now on, said by `name` (said again by it,
/// the one said last: what installs it may as often as it is built): what hands them to the host (a bar's floating
/// controls) at the frame they were drawn in. Let go as a Tester starts.
pub fn on_native_anchors(name : String, f : (Ctx, Array[(String, (Double, Double, Double, Double))]) -> Unit) -> Unit {
  anchors_heard[name] = f
}

///|
/// A Tester's check of the anchors read by their layers' places (`now`): the frame walked, every anchor's instance in
/// it found by the number in it, cut as it was drawn, must be what they read, one for one. A place gone wrong (a layer
/// split or its instances moved and its places not with them) fails here, naming the anchors.
fn Ctx::anchors_checked(self : Ctx, now : Array[(String, (Double, Double, Double, Double))]) -> Unit {
  let found : Array[(String, (Double, Double, Double, Double))] = []
  for k in 0..<self.ninst {
    let n = anchor_of(self.inst, k)
    if n >= 0 && n < anchor_names.length() {
      match anchor_rect(self.inst, k) {
        Some(r) => found.push((anchor_names[n], r))
        None => ()
      }
    }
  }
  let read = now.copy()
  read.sort_by(fn(a, b) { anchor_order(a, b) })
  found.sort_by(fn(a, b) { anchor_order(a, b) })
  if read != found {
    let s = "the anchors read by their layers' places are not those drawn: read \{read}, drawn \{found}"
    println(s)
    abort(s)
  }
}

///|
/// Anchors in order: by name, then where.
fn anchor_order(a : (String, (Double, Double, Double, Double)), b : (String, (Double, Double, Double, Double))) -> Int {
  if a.0 != b.0 {
    a.0.compare(b.0)
  } else {
    a.1.compare(b.1)
  }
}
