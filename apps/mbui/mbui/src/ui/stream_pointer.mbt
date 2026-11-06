// A pointer over a stream's picture drawn by its host on the stream's system video layer (@hostapi.stream_pointer), as
// a remote screen's pointer over its picture: composited by the system with the picture, it goes where the layer goes
// (zoomed, panned) by itself, and moves as it is told (Stream::pointer_at), between frames too, nothing of the app's
// built or painted for it. Only while the stream shows itself there (Stream::layered); elsewhere the app draws its own.
//
// Under a Tester, what the host is told shows in Tester::stream_fed: "pointer KEY WxH hot=HX,HY" its picture,
// "pointer at X Y" where it points, "pointer none" hidden.

///|
/// What each stream's host was last told of its pointer (by the stream's id): its picture's key, and where it points
/// (None hidden).
priv struct PointerTold {
  mut image : (String, Double, Double, Double, Double, Double)?
  mut at : (Double, Double)?
}

///|
let pointers_told : Map[Int, PointerTold] = Map([])

///|
/// Whether its decoded picture can be shown by its system video layer (one was opened and an H.264 frame decoded).
/// This does not say whether a node is showing that layer: `layer_visible` reports the last painted frame's placement.
pub fn Stream::layered(self : Stream) -> Bool {
  match self.view {
    Some(v) => !v.closed && self.h264 && !self.closed && self.at is Some(_)
    None => false
  }
}

///|
/// Whether its system layer was actually shown in the last painted frame. Tracked: readers are told after a frame
/// places or hides it. A pointer formerly on the layer is hidden when that layer leaves.
pub fn Stream::layer_visible(self : Stream) -> Bool {
  self.layer_visible.get()
}

///|
fn Stream::layer_visibility_said(self : Stream) -> Unit {
  let visible = match self.view {
    Some(v) => !self.closed && !v.closed && v.told_shown && self.h264 && self.at is Some(_)
    None => false
  }
  if !visible {
    self.pointer_at(None)
  }
  if visible == self.layer_visible_now {
    return
  }
  self.layer_visible_now = visible
  self.layer_visible.set(visible)
}

///|
/// The pointer its host draws over its picture on its layer: `key` names its picture (told the host only as it changes:
/// `png` asked for then), `w` × `h` points at any zoom, its hot spot `hx`, `hy` points in from its top left.
pub fn Stream::pointer_image(
  self : Stream,
  key : String,
  png : () -> Bytes,
  w : Double,
  h : Double,
  hx : Double,
  hy : Double,
) -> Unit {
  if self.closed || self.id == 0 {
    return
  }
  let told = pointer_told(self.id)
  let z = window_zoom_drawn.val
  let image = (key, w, h, hx, hy, z)
  if told.image == Some(image) {
    return
  }
  told.image = Some(image)
  match fake.val {
    Some(f) => fake_fed(f, self.id, "pointer \{key} \{w}x\{h} hot=\{hx},\{hy}")
    None => @hostapi.stream_pointer(self.id, png(), w * z, h * z, hx * z, hy * z)
  }
}

///|
/// Where its pointer points: (x, y) of the rect its picture is drawn at (0..1, outside it too), None none. Told the host
/// as it changes, at once, in a frame or between frames: nothing built or painted for it.
pub fn Stream::pointer_at(self : Stream, at : (Double, Double)?) -> Unit {
  if self.closed || self.id == 0 {
    return
  }
  let told = pointer_told(self.id)
  if told.at == at {
    return
  }
  told.at = at
  match fake.val {
    Some(f) =>
      fake_fed(f, self.id, match at {
        Some((x, y)) => "pointer at \{x} \{y}"
        None => "pointer none"
      })
    None =>
      match at {
        Some((x, y)) => @hostapi.stream_pointer_at(self.id, x, y, true)
        None => @hostapi.stream_pointer_at(self.id, 0.0, 0.0, false)
      }
  }
}

///|
fn pointer_told(id : Int) -> PointerTold {
  match pointers_told.get(id) {
    Some(t) => t
    None => {
      let t = { image: None, at: None }
      pointers_told[id] = t
      t
    }
  }
}
