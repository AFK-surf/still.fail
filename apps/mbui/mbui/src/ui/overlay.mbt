// What lies over the page (Radix's Portal, DismissableLayer and FocusScope in one): a layer built where the view
// asks for it, among what it belongs to, but laid over the whole window and drawn and tapped over everything built
// outside a layer, layers opened later over those opened before. A layer is dismissed (Overlay::dismissed, the view
// closes it: it is the view's to keep open or not) by Escape when it is the topmost Escape dismisses (one that it does
// not, over it, without the keys, passed: a toast), by the system's back when it is the topmost, and by a press
// outside what it holds (outside each layer over it too: a press in a dialog dismisses the menu open over it, not the
// dialog), unless the press is on its anchor (the button that toggles it). A modal layer covers the page with a
// ground of its own (a scrim) that takes every press and wheel the layer does not, hides the page from the semantics
// tree, and has the keys (what is built under it reads none, a field there given the focus does not keep it); one
// that traps the focus keeps Tab among what it holds. As it opens, the focus goes into it (its first focusable, or
// what it says); as it goes (no longer built, or inert: leaving, its exit drawn), the focus goes back where it was
// when it opened (its anchor), unless it went elsewhere meanwhile.
//
// Where a layer's content goes, by an anchor (a popover by its button), is Ctx::place's (Radix's Popper): on a side
// of it, along it, flipped to the other side and moved to stay in the window (over the anchor where neither side has
// the room); only what is taller than the window is made shorter (Ctx::place_most).

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
/// is hidden from the semantics tree, and the focus goes back as though it had gone; its scrim is still drawn (as it
/// fades), taking nothing.
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
    // the view closes it as it reads this: built again, closed
    self.read_changed("a layer dismissed")
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
  n.portal_id = id
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
    // (the system's back is an input: its frames are the framework's)
    self.take_back(fn() { self.dismissals[id] = Back })
  }
  self.with_parent(i, fn() {
    if modal && (!inert || scrim != 0L) {
      // the ground that takes what the layer does not; leaving, its scrim still fading with it, taking nothing
      let b = self.box(w=Fill(1.0), h=Fill(1.0), bg=scrim, id=if inert { 0 } else { id }, fn() {  })
      self.nodes[b].layer = true
      self.nodes[b].blocks = !inert
      // (what is put over it, a menu's thing held, painted once it is: Ctx::paint_raised)
      if scrim != 0L {
        dr.scrims.push(b)
      }
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
/// Box `i` (one with an id) stops the wheel: one turned over it scrolls nothing laid under it (the page under a
/// popover's panel that is not modal), only what scrolls in it. A modal layer's ground does so all over the window.
pub fn Ctx::stop_wheel(self : Ctx, i : Int) -> Unit {
  self.nodes[i].stops_wheel = true
}

///|
/// The pointer goes through box `i` and what it holds to what lies under it (a tooltip, which explains what it is
/// over and takes nothing): never on top there for the pointer (Ctx::hovered), a press or the wheel, though drawn and
/// found where it is (Ctx::rect_of). What is not so takes the pointer wherever it lies over something: what is under a
/// dialog's ground, a panel's, is not pointed at.
pub fn Ctx::passes(self : Ctx, i : Int) -> Unit {
  self.nodes[i].passes = true
}

///|
/// The layer `id` dismissed (as though by `why`): a view's own close button for a layer it closes the same way. Told
/// as the frame is built, it is built again with it.
pub fn Ctx::dismiss(self : Ctx, id : Int, why? : Dismiss = Escape) -> Unit {
  self.dismissals[id] = why
  self.read_changed("a layer dismissed")
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
  // (the keys and the focus, read so: hand.mbt)
  hand_presses_read()
  hand.focus_id.get() |> ignore
  // a dismissal of a layer the last frame did not build (the view closed it its own way meanwhile) is let go: opened
  // again, the layer is not dismissed by it
  let stale : Array[Int] = []
  self.dismissals.each(fn(id, _) {
    if !self.last_layers.iter().any(fn(l) { l.id == id }) {
      stale.push(id)
    }
  })
  for id in stale {
    self.dismissals.remove(id)
  }
  // the keys this frame the topmost open layer's that has them: a modal one (a menu, a dialog, a sheet, a file over
  // the window), one the focus is in — not the page's under it, as a modal layer takes its presses. One over it that
  // has none (a toast, a tip) leaves them to it; one the focus stayed outside of (a field's suggestions, a menubar's
  // menu opened by the pointer: the field, the bar, move in it) leaves them where the focus is.
  let open = self.last_layers.filter(fn(l) { !l.inert }).rev()
  self.keys_layer = match open.iter().find_first(fn(l) { l.modal || self.focus_in_layer(l.id) }) {
    Some(l) => l.id
    None => 0
  }
  // Escape the topmost's it dismisses, down to where the keys go: one that is not dismissed by it and has no keys (a
  // toast) leaves it to those under it; one that has the keys and is not (a file over the window) to what it holds,
  // its own Escape (what it shows closed first)
  for l in open {
    if l.escape {
      for k in 0..<desk.keys.length() {
        let (code, mods, taken) = desk.keys[k]
        if code == key_escape && !taken {
          self.dismissals[l.id] = Escape
          desk.keys[k] = (code, mods, true)
        }
      }
      // (an Escape that dismissed it is its, gone for everything else: not even what reads the keys a field took
      // sees it, a page's own Escape under it)
      if self.dismissals.get(l.id) == Some(Escape) {
        desk.keys.retain(fn(k) { k.0 != key_escape })
      }
      break
    }
    if l.id == self.keys_layer {
      break
    }
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
/// Whether the focus is in layer `id` (or one built in it), as the frame before built them.
fn Ctx::focus_in_layer(self : Ctx, id : Int) -> Bool {
  if self.focus == 0 {
    return false
  }
  match self.last_focusables.iter().find_first(fn(f) { f.id == self.focus }) {
    Some(f) => {
      let mut at = f.layer
      for _ in 0..<64 {
        if at == id {
          return true
        }
        match self.last_layers.iter().find_first(fn(l) { l.id == at }) {
          Some(l) if at != 0 => at = l.parent
          _ => return false
        }
      }
      false
    }
    None => false
  }
}

///|
/// Whether keyboard focus is in an overlay or a nested overlay it owns.
pub fn Ctx::keyboard_in_overlay(self : Ctx, id : Int) -> Bool {
  self.focus_visible && self.focus_in_layer(id)
}

///|
/// Whether the pointer is inside an overlay or a nested overlay it owns.
pub fn Ctx::pointer_in_overlay(self : Ctx, id : Int) -> Bool {
  let (px, py, _) = self.pointer()
  for f in self.last_focusables {
    guard self.rect_of(f.id) is Some((x, y, w, h)) else { continue }
    if px < x || px >= x + w || py < y || py >= y + h { continue }
    let mut at = f.layer
    for _ in 0..<64 {
      if at == id { return true }
      match self.last_layers.iter().find_first(fn(l) { l.id == at && !l.inert }) {
        Some(l) if at != 0 => at = l.parent
        _ => break
      }
    }
  }
  false
}

///|
/// Whether what is being built now reads the keys: it is in the layer they go to (or one built in it), or none takes
/// them.
fn Ctx::keys_here(self : Ctx) -> Bool {
  // (an old view under the window's tree's topmost modal layer, not in it: none (view_host.mbt's island_allows); what
  // it opens over everything (a menu, a sheet: its layers) over that layer too, and theirs)
  if self.layer_cur == 0 && !island_allows(island_building.val) {
    return false
  }
  if self.keys_layer == 0 {
    return true
  }
  let mut at = self.layer_cur
  // (up the layers it was built in, as this frame and the one before built them)
  for _ in 0..<64 {
    if at == self.keys_layer {
      return true
    }
    if at == 0 {
      return false
    }
    let parent = match self.layers.iter().find_first(fn(l) { l.id == at }) {
      Some(l) => Some(l.parent)
      None =>
        match self.last_layers.iter().find_first(fn(l) { l.id == at }) {
          Some(l) => Some(l.parent)
          None => None
        }
    }
    match parent {
      Some(p) => at = p
      None => return false
    }
  }
  false
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
/// As the frame is laid out: the focus into the layers that opened (as they say), back from those that went; given
/// there, the view that read it is built again in this frame (Ctx::read_changed).
fn Ctx::layers_focus(self : Ctx) -> Unit {
  hand.focus_id.get() |> ignore
  let had = self.focus
  // opened: not there (or leaving) the last frame
  for l in self.layers {
    if l.inert || l.initial == 0 || self.layers_opened.contains(l.id) {
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
    self.layers_opened.push(l.id)
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
    }
  }
  // a field given the focus this frame under the topmost modal layer (a page's composer taking the cursor as its chat
  // is first drawn under a file over the window) does not keep it: hidden there, it would take what is typed over it
  // (Radix's FocusScope: nothing outside a trapped scope takes the focus); it goes back to what had it
  if self.focus != self.focus_before && self.editors.contains(self.focus) {
    let modal = self.layers.filter(fn(l) { l.modal && !l.inert }).last()
    match (modal, self.focusables.iter().find_first(fn(f) { f.id == self.focus })) {
      (Some(m), Some(f)) if !self.layer_built_in(f.layer, m.id) => self.focus = self.focus_before
      _ => ()
    }
  }
  if self.focus != had {
    self.read_changed("the focus, into a layer or back from one")
  }
}

///|
/// Whether layer `l` is `outer` or was built in it, as this frame built them (as the last did, for one not built yet).
fn Ctx::layer_built_in(self : Ctx, l : Int, outer : Int) -> Bool {
  let mut at = l
  for _ in 0..<64 {
    if at == outer {
      return true
    }
    if at == 0 {
      return false
    }
    at = match self.layers.iter().find_first(fn(x) { x.id == at }) {
      Some(x) => x.parent
      None =>
        match self.last_layer(at) {
          Some(x) => x.parent
          None => 0
        }
    }
  }
  false
}

///|
/// As the frame ends: this frame's layers the last frame's for the next.
fn Ctx::layers_frame_end(self : Ctx) -> Unit {
  for l in self.last_layers {
    if !l.inert && !self.layers.iter().any(fn(x) { x.id == l.id }) {
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
/// Node `i` (built this frame) offset by what `at` makes of the size it is laid out at, as it is laid out, in place of
/// its tx and ty: what goes where its own size says (a menu by its trigger, a dialog in the middle of the window) is
/// there in the first frame it is drawn, and follows its size as that changes, in the same frame. `at` runs in the
/// direction where it was said (Ctx::place's start and end).
pub fn Ctx::place_by_size(self : Ctx, i : Int, at : (Double, Double) -> (Double, Double)) -> Unit {
  let dir = self.direction
  self.nodes[i].place = Some(fn(w, h) {
    let was = self.direction
    self.direction = dir
    let r = at(w, h)
    self.direction = was
    r
  })
}

///|
/// Where the thing with `id` is laid out this frame (x, y, w, h), asked while a frame is laid out (in what
/// Ctx::place_by_size is given): what was laid out before it (the page, under a layer over it), else None.
pub fn Ctx::laid_out(self : Ctx, id : Int) -> (Double, Double, Double, Double)? {
  for k in 0..<self.count {
    let n = self.nodes[k]
    if n.id == id {
      return Some((n.x, n.y, n.fw, n.fh))
    }
  }
  None
}

///|
/// How tall what Ctx::place puts by an anchor can be, kept `padding` inside the window: the window's height less that
/// at each end. What has not the room on its side goes to the other where that has more; what has it on neither is
/// moved to stay in the window, over its anchor; only what is taller than this is to be made shorter, what it holds
/// scrolling (Radix's Popper: flip, then shift, then size). Never under 0.
pub fn Ctx::place_most(self : Ctx, padding? : Double = 8.0) -> Double {
  dmax(self.height - 2.0 * padding, 0.0)
}

///|
/// Where content `w` by `h` goes by an anchor (x, y, w, h, in the window), Radix's Popper: on `side`, `offset` away,
/// lined up `along` it (moved `along_offset` further), kept `padding` inside the window (`flip`: to the other side when
/// it does not fit on its own and fits better there; moved along the side to stay in, and over the anchor where it
/// fits on neither: Radix's shift on both axes). Its top left, and the side it went on.
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
  // moved along to stay in the window, and across where neither side has the room for it: over its anchor rather
  // than out of the window (never past its start)
  let keep = fn(v : Double, len : Double, max : Double) {
    dmax(padding, dmin(v, max - padding - len))
  }
  let (x, y) = (keep(x, w, vw), keep(y, h, vh))
  (x, y, side)
}
