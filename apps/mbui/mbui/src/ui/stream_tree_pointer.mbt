// One pointer shared by the full picture and any sharper pictures over it.

///|
priv struct StreamPointerImage {
  key : String
  png : Bytes
  w : Double
  h : Double
  hx : Double
  hy : Double
}

///|
priv struct StreamPointerPicture {
  mut epoch : Int64
  mut stream : Stream?
  mut direct : Bool
  mut rect : (Double, Double, Double, Double)
}

///|
/// A pointer shared by stream nodes showing one picture, including sharper parts of it. Its position is in the whole
/// picture's coordinates; its image stays the same size in window points as the picture is zoomed.
pub struct StreamPointer {
  priv pictures : Map[@view.NodeId, StreamPointerPicture]
  priv order : Array[@view.NodeId]
  priv mut image : StreamPointerImage?
  priv mut position : (Double, Double)?
  priv mut whole : (Double, Double, Double, Double)
  priv mut presented : Int64
  priv mut system : Bool
  priv native : Array[Stream]
  priv revision : @signals.Signal[Int64]
  priv mut next_revision : Int64
}

///|
// Kept by node until its owner lets it go. A full paint has an epoch of its own, including after an abandoned scene
// paint; entries not visited in that paint are outside the visible tree and must not affect the pointer's choice.
let stream_pointer_pictures : Map[@view.NodeId, StreamPointer] = {}

///|
let stream_pointer_overlays : Map[@view.NodeId, StreamPointer] = {}

///|
let stream_pointer_epoch : Ref[Int64] = Ref(0L)

///|
pub fn StreamPointer::new() -> StreamPointer {
  {
    pictures: {},
    order: [],
    image: None,
    position: None,
    whole: (0.0, 0.0, 0.0, 0.0),
    presented: -1L,
    system: false,
    native: [],
    revision: @signals.signal(0L),
    next_revision: 0L,
  }
}

///|
fn StreamPointer::changed(self : StreamPointer) -> Unit {
  self.next_revision += 1L
  self.revision.set(self.next_revision)
}

///|
/// The pointer's encoded image and hotspot in window points. A key identifies the bytes and is reused until it changes.
/// The image is prepared for the texture path as well, so switching away from a system layer does not wait to ask for it.
pub fn StreamPointer::image(
  self : StreamPointer,
  key : String,
  png : () -> Bytes,
  w : Double,
  h : Double,
  hx : Double,
  hy : Double,
) -> Unit {
  match self.image {
    Some(i) if i.key == key && i.w == w && i.h == h && i.hx == hx && i.hy == hy => return
    _ => ()
  }
  let data = png()
  self.image = Some({ key, png: data, w, h, hx, hy })
  add_image(key, data)
  let c = g()
  c.image_want(key, dmax(w, h) * c.scale)
  if self.system {
    self.tell_native()
  } else {
    self.changed()
  }
}

///|
/// Move the pointer in the whole picture (0..1; values outside it are allowed), or hide it. With only system layers
/// this tells their hosts directly; if any picture is drawn as a texture only the pointer's tree drawing is dirtied.
pub fn StreamPointer::at(self : StreamPointer, at : (Double, Double)?) -> Unit {
  if self.position == at {
    return
  }
  self.position = at
  if self.system {
    self.tell_native()
  } else {
    self.changed()
  }
}

///|
fn StreamPointer::hide_native(self : StreamPointer) -> Unit {
  for s in self.native {
    s.pointer_at(None)
  }
  self.native.clear()
}

///|
fn StreamPointer::tell_native(self : StreamPointer) -> Unit {
  let (wx, wy, ww, wh) = self.whole
  let place = self.position.map(fn(p) { (wx + p.0 * ww, wy + p.1 * wh) })
  for id in self.order {
    guard self.pictures.get(id) is Some(picture) else { continue }
    if picture.epoch != self.presented || !picture.direct {
      continue
    }
    guard picture.stream is Some(s) else { continue }
    let (x, y, w, h) = picture.rect
    if w <= 0.0 || h <= 0.0 {
      continue
    }
    match self.image {
      Some(i) => {
        s.pointer_image(i.key, fn() { i.png }, i.w, i.h, i.hx, i.hy)
        s.pointer_at(place.map(fn(p) { ((p.0 - x) / w, (p.1 - y) / h) }))
      }
      None => s.pointer_at(None)
    }
  }
}

///|
/// A pointer overlay for `pointer`, painted after the stream nodes sharing it. Give this node the whole picture's
/// place and size, outside any fade applied only to the video. Removing it hides system pointers but does not close streams.
pub fn stream_pointer_in(node : @view.View, pointer : StreamPointer) -> @view.View {
  let id = node.id()
  stream_pointer_overlays[id] = pointer
  node.host_drawing(By(fn() { Some(pointer.revision.get()) })) |> ignore
  node.owns(fn() {
    stream_pointer_overlays.remove(id)
    pointer.hide_native()
    pointer.system = false
  })
  node
}

///|
fn stream_pointer_picture(node : @view.View, pointer : StreamPointer) -> Unit {
  let id = node.id()
  stream_pointer_pictures[id] = pointer
  pointer.pictures[id] = { epoch: -1L, stream: None, direct: false, rect: (0.0, 0.0, 0.0, 0.0) }
  pointer.order.push(id)
  node.host_drawing(Is(Some(0L))) |> ignore
  node.owns(fn() {
    stream_pointer_pictures.remove(id)
    match pointer.pictures.get(id) {
      Some(p) => match p.stream { Some(s) => s.pointer_at(None); None => () }
      None => ()
    }
    pointer.pictures.remove(id)
    pointer.order.retain(fn(other) { other != id })
    pointer.system = false
    pointer.hide_native()
    pointer.changed()
  })
}

///|
fn stream_pointer_picture_drawn(
  id : @view.NodeId,
  stream : Stream?,
  direct : Bool,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
) -> Unit {
  guard stream_pointer_pictures.get(id) is Some(pointer) else { return }
  guard pointer.pictures.get(id) is Some(picture) else { return }
  picture.epoch = stream_pointer_epoch.val
  picture.stream = stream
  picture.direct = direct
  picture.rect = (x, y, w, h)
}

///|
/// Decide after the pictures before this overlay have painted. A mixture of layers and textures uses one opaque
/// canvas pointer over both; with only layers, put it on each layer so its own clipping and their stacking preserve it.
fn Ctx::paint_tree_stream_pointer(
  self : Ctx,
  pointer : StreamPointer,
  c : @view.Content,
  x : Double,
  y : Double,
  scale : Double,
  alpha : Double,
  may_layer : Bool,
) -> Unit {
  pointer.whole = (x, y, c.w * scale, c.h * scale)
  pointer.presented = stream_pointer_epoch.val
  let mut count = 0
  let mut all_direct = may_layer
  for id in pointer.order {
    guard pointer.pictures.get(id) is Some(picture) else { continue }
    if picture.epoch == pointer.presented && picture.stream is Some(_) {
      count += 1
      if !picture.direct {
        all_direct = false
      }
    }
  }
  if count > 0 && all_direct {
    let next : Array[Stream] = []
    for id in pointer.order {
      guard pointer.pictures.get(id) is Some(picture) else { continue }
      if picture.epoch == pointer.presented && picture.direct {
        match picture.stream {
          Some(s) => if !next.iter().any(fn(n) { physical_equal(n, s) }) { next.push(s) }
          None => ()
        }
      }
    }
    for s in pointer.native {
      if !next.iter().any(fn(n) { physical_equal(n, s) }) {
        s.pointer_at(None)
      }
    }
    pointer.native.clear()
    pointer.native.append(next)
    pointer.system = true
    pointer.tell_native()
  } else {
    pointer.hide_native()
    pointer.system = false
    match (pointer.image, pointer.position) {
      (Some(i), Some((px, py))) if count > 0 =>
        self.draw_image(i.key, x + px * c.w * scale - i.hx, y + py * c.h * scale - i.hy, i.w, i.h, FitFill, 0.0, alpha, fade=false)
      _ => ()
    }
  }
}
