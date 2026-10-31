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
  mut key : String
  mut at : (Double, Double)?
}

///|
let pointers_told : Map[Int, PointerTold] = Map([])

///|
/// Whether its picture is shown by its system video layer (a stream made with `layer`, the host's own layer open for it,
/// an H.264 frame of it shown): what `Ctx::stream` with `layer` shows there, a pointer told it drawn over it.
pub fn Stream::layered(self : Stream) -> Bool {
  match self.view {
    Some(v) => !v.closed && self.h264 && !self.closed && self.at is Some(_)
    None => false
  }
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
  let key_at_zoom = key + "/" + z.to_string()
  if told.key == key_at_zoom {
    return
  }
  told.key = key_at_zoom
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
      let t = { key: "", at: None }
      pointers_told[id] = t
      t
    }
  }
}
