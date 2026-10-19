// What lies over the page (Radix's Portal, DismissableLayer and FocusScope in one): a layer built where the view
// asks for it, among what it belongs to, but laid over the whole window and drawn and tapped over everything built
// outside a layer, layers opened later over those opened before. A layer is dismissed (Overlay::dismissed, the view
// closes it: it is the view's to keep open or not) by Escape and by the system's back when it is the topmost, and by
// a press outside what it holds (outside each layer over it too: a press in a dialog dismisses the menu open over
// it, not the dialog), unless the press is on its anchor (the button that toggles it). A modal layer covers the page
// with a ground of its own (a scrim) that takes every press and wheel the layer does not, and hides the page from the
// semantics tree; one that traps the focus keeps Tab among what it holds. As it opens, the focus goes into it (its
// first focusable, or what it says); as it goes (no longer built, or inert: leaving, its exit drawn), the focus goes
// back where it was when it opened (its anchor), unless it went elsewhere meanwhile.
//
// Where a layer's content goes, by an anchor (a popover by its button), is Ctx::place's (Radix's Popper): on a side
// of it, along it, flipped to the other side and moved along to stay in the window.

///|
/// Why a layer was dismissed.
pub(all) enum Dismiss {
  Escape
  Outside
  Back
} derive(Eq, Show, Debug)

///|
/// A layer as built (Ctx::overlay): its id, node, the layer it was built in (0 the page), how it behaves.
struct Layer {
  id : Int
  node : Int
  parent : Int
  modal : Bool
  trap : Bool
  escape : Bool
  outside : Bool
  inert : Bool
  anchor : Int
  initial : Int
}

///|
/// What a layer reports: whether it was dismissed since the last frame (and why); its node.
pub(all) struct Overlay {
  id : Int
  node : Int
  dismissed : Dismiss?
}

///|
/// A layer over the page (see the file's head), `key` its id's, built by `body`. `modal`: a ground (`scrim`, its
/// colour; clear by default) under what it holds takes the presses and wheels it does not, and the page is hidden
/// from the semantics tree; `trap` (with `modal` by default) keeps Tab in it. Dismissed by Escape and the back
/// (unless not `escape`), by a press outside (unless not `outside`); a press on `anchor` (its trigger's id) does not
/// dismiss it. As it opens the focus goes to `initial_focus` (-1: its first focusable; 0: nowhere, it stays; -2, by
/// default: the first focusable when it traps, else nowhere); as it goes, back to `return_focus` (0, by default:
/// what had it as it opened). `inert`: leaving (its exit drawn): it takes no press, focus or key, is not dismissed,
/// is hidden from the semantics tree, and the focus goes back as though it had gone.
pub fn Ctx::overlay(
  self : Ctx,
  key : String,
  modal? : Bool = false,
  trap? : Bool = modal,
  escape? : Bool = true,
  outside? : Bool = true,
  scrim? : Int64 = 0L,
  anchor? : Int = 0,
  initial_focus? : Int = -2,
  return_focus? : Int = 0,
  inert? : Bool = false,
  body : () -> Unit,
) -> Overlay {
  let id = self.id(key)
  let dismissed = self.dismissals.get(id)
  if dismissed is Some(_) {
    self.dismissals.remove(id)
    // the view closes it as it reads this: a frame again to draw it closed
    self.wants_frame = true
  }
  let initial = if initial_focus == -2 {
    if trap {
      -1
    } else {
      0
    }
  } else {
    initial_focus
  }
  // what to give the focus back to, as it opened
  if !self.layer_return.contains(id) {
    self.layer_return[id] = if return_focus != 0 { return_focus } else { self.focus }
  } else if return_focus != 0 {
    self.layer_return[id] = return_focus
  }
  let saved_cur = self.cur
  let saved_layer = self.layer_cur
  let saved_group = self.group_cur
  self.cur = 0
  self.layer_cur = id
  self.group_cur = 0
  let i = self.box(align=AStart, fn() {  })
  let n = self.nodes[i]
  n.layer = true
  n.portal = true
  self.layers.push({
    id,
    node: i,
    parent: saved_layer,
    modal,
    trap: trap && !inert,
    escape,
    outside,
    inert,
    anchor,
    initial,
  })
  // the back to it, unless a layer built in it (over it) takes it after
  if escape && !inert {
    self.take_back(fn() {
      self.dismissals[id] = Back
      self.wants_frame = true
    })
  }
  self.with_parent(i, fn() {
    if modal && !inert {
      // the ground that takes what the layer does not
      let b = self.box(w=Fill(1.0), h=Fill(1.0), bg=scrim, id~, fn() {  })
      self.nodes[b].layer = true
      self.nodes[b].blocks = true
    }
    if inert {
      // leaving: drawn, never tapped (draw.mbt)
      self.draw_only(i)
      self.hidden_from_semantics(body)
    } else {
      body()
    }
  })
  self.cur = saved_cur
  self.layer_cur = saved_layer
  self.group_cur = saved_group
  { id, node: i, dismissed }
}

///|
/// The layer `id` dismissed (as though by `why`) for the next frame: a view's own close button for a layer it
/// closes the same way.
pub fn Ctx::dismiss(self : Ctx, id : Int, why? : Dismiss = Escape) -> Unit {
  self.dismissals[id] = why
  self.wants_frame = true
}

///|
/// The last frame's layer `id`, if built.
fn Ctx::last_layer(self : Ctx, id : Int) -> Layer? {
  for l in self.last_layers {
    if l.id == id {
      return Some(l)
    }
  }
  None
}

///|
/// The topmost layer of the last frame that traps the focus (0 none).
fn Ctx::trapping_layer(self : Ctx) -> Int {
  let mut k = self.last_layers.length() - 1
  while k >= 0 {
    let l = self.last_layers[k]
    if l.trap && !l.inert {
      return l.id
    }
    k = k - 1
  }
  0
}

///|
/// Whether layer `l` is `outer` or was built in it (0: the page holds every layer).
fn Ctx::layer_within(self : Ctx, l : Int, outer : Int) -> Bool {
  if outer == 0 {
    return true
  }
  let mut at = l
  let mut steps = 0
  while at != 0 && steps < 64 {
    if at == outer {
      return true
    }
    at = match self.last_layer(at) {
      Some(x) => x.parent
      None => 0
    }
    steps = steps + 1
  }
  false
}

///|
/// Whether layer `l` (or one it was built in) was leaving the last frame.
fn Ctx::layer_inert(self : Ctx, l : Int) -> Bool {
  let mut at = l
  let mut steps = 0
  while at != 0 && steps < 64 {
    match self.last_layer(at) {
      Some(x) => {
        if x.inert {
          return true
        }
        at = x.parent
      }
      None => return false
    }
    steps = steps + 1
  }
  false
}

///|
/// The node of the topmost modal layer the last frame built (-1 none): what is outside it is hidden.
fn Ctx::modal_node(self : Ctx) -> Int {
  let mut k = self.last_layers.length() - 1
  while k >= 0 {
    let l = self.last_layers[k]
    if l.modal && !l.inert && l.node < self.count {
      return l.node
    }
    k = k - 1
  }
  -1
}

///|
/// Whether (x, y) is on what layer `l` holds (its children, its modal ground left out), as last laid out.
fn Ctx::in_layer(self : Ctx, l : Layer, x : Double, y : Double) -> Bool {
  if l.node >= self.count {
    return false
  }
  let mut ch = self.nodes[l.node].first
  while ch >= 0 {
    let n = self.nodes[ch]
    if !n.blocks && x >= n.x && x < n.x + n.fw && y >= n.y && y < n.y + n.fh {
      return true
    }
    ch = n.next
  }
  false
}

///|
/// As the frame starts: Escape to the topmost layer; a press since the last frame dismisses the layers it was outside
/// of, from the top down to the first it was in (or a modal one: what is under that never saw it).
fn Ctx::layer_keys(self : Ctx) -> Unit {
  let top = self.top_layer()
  match top {
    Some(l) =>
      for k in 0..<desk.keys.length() {
        let (code, mods, taken) = desk.keys[k]
        if code == key_escape && !taken {
          if l.escape {
            self.dismissals[l.id] = Escape
          }
          desk.keys[k] = (code, mods, true)
        }
      }
    None => ()
  }
  match self.press_down {
    Some((x, y)) => {
      let target = hit_in(self.hit_ids, self.hit_rects, x, y)
      let mut k = self.last_layers.length() - 1
      while k >= 0 {
        let l = self.last_layers[k]
        k = k - 1
        if l.inert {
          continue
        }
        if self.in_layer(l, x, y) {
          break
        }
        if l.outside && (l.anchor == 0 || target != l.anchor) {
          self.dismissals[l.id] = Outside
        }
        if l.modal {
          break
        }
      }
    }
    None => ()
  }
  self.press_down = None
}

///|
/// The topmost layer of the last frame that is not leaving.
fn Ctx::top_layer(self : Ctx) -> Layer? {
  let mut k = self.last_layers.length() - 1
  while k >= 0 {
    let l = self.last_layers[k]
    if !l.inert {
      return Some(l)
    }
    k = k - 1
  }
  None
}

///|
/// Once built: the layers to the end of the window's children (over everything else, in the order they were opened).
fn Ctx::raise_layers(self : Ctx) -> Unit {
  if self.layers.is_empty() || self.count == 0 {
    return
  }
  let root = self.nodes[0]
  let rest : Array[Int] = []
  let tops : Array[Int] = []
  let mut ch = root.first
  while ch >= 0 {
    if self.nodes[ch].portal {
      tops.push(ch)
    } else {
      rest.push(ch)
    }
    ch = self.nodes[ch].next
  }
  root.first = -1
  root.last = -1
  for i in rest {
    self.link_last(0, i)
  }
  for i in tops {
    self.link_last(0, i)
  }
}

///|
fn Ctx::link_last(self : Ctx, p : Int, i : Int) -> Unit {
  let pn = self.nodes[p]
  self.nodes[i].next = -1
  if pn.last >= 0 {
    self.nodes[pn.last].next = i
  } else {
    pn.first = i
  }
  pn.last = i
}

///|
/// As the frame ends: the focus into the layers that opened (as they say), back from those that went; this frame's
/// layers the last frame's for the next.
fn Ctx::layers_frame_end(self : Ctx) -> Unit {
  // opened: not there (or leaving) the last frame
  for l in self.layers {
    if l.inert || l.initial == 0 {
      continue
    }
    let was = match self.last_layer(l.id) {
      Some(x) => !x.inert
      None => false
    }
    if was {
      continue
    }
    let target = if l.initial > 0 {
      l.initial
    } else {
      let mut first = 0
      for f in self.focusables {
        if first == 0 && f.layer == l.id {
          first = f.id
        }
      }
      // none in it: its own ground (the layer itself holds the focus: Tab stays, Escape is its)
      if first == 0 {
        l.id
      } else {
        first
      }
    }
    self.focus = target
    self.wants_frame = true
  }
  // gone, or leaving: the focus back, when it was in it or is nowhere
  for l in self.last_layers {
    if l.inert {
      continue
    }
    let still = self.layers.iter().any(fn(x) { x.id == l.id && !x.inert })
    if still {
      continue
    }
    let back = self.layer_return.get(l.id).unwrap_or(0)
    let inside = self.focus == 0 ||
      self.focus == l.id ||
      self.last_focusables.iter().any(fn(f) {
        f.id == self.focus && self.layer_within(f.layer, l.id)
      })
    if back != 0 && inside {
      self.focus = back
      self.wants_frame = true
    }
    if !self.layers.iter().any(fn(x) { x.id == l.id }) {
      self.layer_return.remove(l.id)
    }
  }
  let last = self.last_layers
  self.last_layers = self.layers
  last.clear()
  self.layers = last
}

///|
/// Which side of its anchor a layer's content goes.
pub(all) enum Side {
  Top
  Right
  Bottom
  Left
} derive(Eq, Show, Debug)

///|
/// Where along the side it lines up with the anchor: their starts (the left, right to left the right), their middles,
/// their ends.
pub(all) enum Along {
  Start
  Middle
  End
} derive(Eq, Show, Debug)

///|
/// Where content `w` by `h` goes by an anchor (x, y, w, h, in the window), Radix's Popper: on `side`, `offset` away,
/// lined up `along` it (moved `along_offset` further), kept `padding` inside the window (`flip`: to the other side when
/// it does not fit on its own and fits better there; moved along the side to stay in). Its top left, and the side it
/// went on.
pub fn Ctx::place(
  self : Ctx,
  anchor : (Double, Double, Double, Double),
  w : Double,
  h : Double,
  side? : Side = Bottom,
  along? : Along = Middle,
  offset? : Double = 4.0,
  along_offset? : Double = 0.0,
  padding? : Double = 8.0,
  flip? : Bool = true,
) -> (Double, Double, Side) {
  let (ax, ay, aw, ah) = anchor
  let vw = self.width
  let vh = self.height
  // the room on each side
  let room = fn(s : Side) {
    match s {
      Top => ay - offset - padding
      Bottom => vh - (ay + ah) - offset - padding
      Left => ax - offset - padding
      Right => vw - (ax + aw) - offset - padding
    }
  }
  let opposite = fn(s : Side) {
    match s {
      Top => Bottom
      Bottom => Top
      Left => Right
      Right => Left
    }
  }
  let need = fn(s : Side) {
    match s {
      Top | Bottom => h
      Left | Right => w
    }
  }
  let side = if flip && room(side) < need(side) && room(opposite(side)) > room(side) {
    opposite(side)
  } else {
    side
  }
  // right to left, a start is the right
  let along = if self.direction == Rtl && (side == Top || side == Bottom) {
    match along {
      Start => End
      End => Start
      Middle => Middle
    }
  } else {
    along
  }
  let sign = if self.direction == Rtl && (side == Top || side == Bottom) {
    -1.0
  } else {
    1.0
  }
  let line = fn(a0 : Double, alen : Double, len : Double) {
    match along {
      Start => a0
      Middle => a0 + (alen - len) / 2.0
      End => a0 + alen - len
    }
  }
  let (x, y) = match side {
    Top => (line(ax, aw, w) + along_offset * sign, ay - offset - h)
    Bottom => (line(ax, aw, w) + along_offset * sign, ay + ah + offset)
    Left => (ax - offset - w, line(ay, ah, h) + along_offset)
    Right => (ax + aw + offset, line(ay, ah, h) + along_offset)
  }
  // moved along to stay in the window (never past its start)
  let keep = fn(v : Double, len : Double, max : Double) {
    dmax(padding, dmin(v, max - padding - len))
  }
  let (x, y) = match side {
    Top | Bottom => (keep(x, w, vw), y)
    Left | Right => (x, keep(y, h, vh))
  }
  (x, y, side)
}
