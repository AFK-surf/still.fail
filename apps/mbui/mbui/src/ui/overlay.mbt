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
  // (said first as an Escape comes to it: whether it took it itself, within it, not dismissed)
  on_escape : (() -> Bool)?
  // (asked as the hand would dismiss it, Escape, back, a press outside: whether it stays open then, the Escape or back
  // taken all the same; Ctx::dismiss, its view's own, not asked)
  stays : (() -> Bool)?
  outside : Bool
  inert : Bool
  anchor : Int
  initial : Int
}

///|
/// The layers `body` builds (and those built in them: a menu a panel opens) at `stack` in the window's stack of layers,
/// the old frame's and the window's tree's alike (View::stacked): drawn, pressed, read out, gone to by Tab and given the
/// keys in that order, one over another, the topmost modal one holding all under it, whichever builds it; those of the
/// same place in the order they are built. Where none is said, as the old frame orders them among its own.
pub fn Ctx::stacked(self : Ctx, stack : Int, body : () -> Unit) -> Unit {
  let was = self.stack_cur
  self.stack_cur = stack
  body()
  self.stack_cur = was
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
/// (unless not `escape`; an Escape `on_escape` says it took, asked as it comes, within it, no dismissal: one step back
/// inside it), by a press outside (unless not `outside`); none of them while `stays` says it stays, asked as each
/// comes (what it is doing may not be left: an Escape or a back taken by it all the same, nothing under it told; its
/// view's own Ctx::dismiss not asked). A press on `anchor` (its trigger's id), or on what it holds, does not dismiss
/// it. As it opens the focus goes to `initial_focus` (-1: its first focusable; 0: nowhere, it stays; -2, by
/// default: the first focusable when it traps, else nowhere); as it goes, back to `return_focus` (0, by default: what
/// had it as it opened). `inert`: leaving (its exit drawn): it takes no press, focus or key, is not dismissed, is
/// hidden from the semantics tree, and the focus goes back as though it had gone; its scrim is still drawn (as it
/// fades), taking nothing.
pub fn Ctx::overlay(
  self : Ctx,
  key : String,
  modal? : Bool = false,
  trap? : Bool = modal,
  escape? : Bool = true,
  on_escape? : () -> Bool,
  stays? : () -> Bool,
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
  // (leaving, its exit drawn: the opening it was over, its back given up with it; open again, another; as the last
  // frame has it, taking nothing from here: Ctx::layer_takes)
  if inert {
    self.layers_gone.add(id)
    match self.layer_gen.get(id) {
      Some(g) => {
        self.layer_gen.remove(id)
        ignore(g)
        self.layer_retired.remove(id)
        self.layer_on_dismiss.remove(id)
      }
      None => ()
    }
  }
  // (an opening ended by what it is for (Ctx::layer_ended: given up, nothing dismissed) built open again: another, as
  // one dismissed is once read below, given the focus back from what has it now)
  if dismissed is None {
    match self.layer_gen.get(id) {
      Some(g) if self.layer_retired.get(id) == Some(g) => {
        self.layer_gen.remove(id)
        self.layer_retired.remove(id)
        self.layer_on_dismiss.remove(id)
        self.layer_return.remove(id)
      }
      _ => ()
    }
  }
  if dismissed is Some(_) {
    self.dismissals.remove(id)
    // (read: the opening it was over ends here; built open from here, by its view keeping it so, it is another, given
    // the focus back from what has it now)
    match self.layer_gen.get(id) {
      Some(g) if self.layer_retired.get(id) == Some(g) => {
        self.layer_gen.remove(id)
        self.layer_retired.remove(id)
        self.layer_on_dismiss.remove(id)
        self.layer_return.remove(id)
      }
      _ => ()
    }
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
  n.stack = self.stack_cur
  self.layers.push({
    id,
    node: i,
    parent: saved_layer,
    modal,
    trap: trap && !inert,
    escape,
    on_escape,
    stays,
    outside,
    inert,
    anchor,
    initial,
  })
  // this opening of it (layer_gen), while it is not leaving; what is told as it is dismissed, at that moment (Ctx::with_dismissed:
  // its own, the one built first in it)
  let gen = if inert {
    0
  } else {
    match self.layer_gen.get(id) {
      Some(g) => g
      None => {
        layer_opened.val = layer_opened.val + 1
        self.layer_gen[id] = layer_opened.val
        layer_opened.val
      }
    }
  }
  match self.layer_hook {
    Some(f) if gen != 0 => {
      self.layer_hook = None
      self.layer_on_dismiss[id] = (gen, f)
    }
    _ => ()
  }
  // the back to it, unless a layer built in it (over it) takes it after: what it is said over taking back once it took it
  // (Ctx::layer_back_taken)
  if escape && !inert {
    // (the system's back is an input: its frames are the framework's; said of this opening, at its place in the
    // window's stack of layers as the layers built are put in it: Ctx::back_says, raise_layers)
    self.back_layer_next = gen
    self.take_back(fn() { self.layer_back_taken(id, gen) })
    self.back_layer_next = 0
  }
  // (what is said in it, its: Ctx::back_within)
  let within_was = self.back_within
  self.back_within = gen
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
  self.back_within = within_was
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
    if l.trap && self.layer_takes(l) {
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
        if !self.layer_takes(x) {
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
    if l.modal && self.layer_takes(l) && l.node < self.count {
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
  self.keys_layer = self.layer_escape(desk.keys)
  match self.press_down {
    Some((x, y)) => {
      // (what took the press as it went down: the window's tree's, none of the old frame's)
      let target = if self.press_down_tree { 0 } else { hit_in(self.hit_ids, self.hit_rects, x, y) }
      let mut k = self.last_layers.length() - 1
      while k >= 0 {
        let l = self.last_layers[k]
        k = k - 1
        if !self.layer_takes(l) {
          continue
        }
        if self.in_layer(l, x, y) {
          break
        }
        if l.outside && (l.anchor == 0 || !self.on_anchor(l.anchor, target, x, y)) && !layer_stays(l) {
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
  self.press_down_tree = false
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
      match self.last_layers.iter().find_first(fn(l) { l.id == at && self.layer_takes(l) }) {
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
  // (each at its place in the window's stack of layers, those of the same place, and those said at none after the one
  // built before them, in the order they were opened: Ctx::stacked)
  let key = Map([])
  let mut at = -1
  for i in tops {
    if self.nodes[i].stack >= 0 {
      at = self.nodes[i].stack
    }
    key[i] = if self.nodes[i].stack >= 0 { self.nodes[i].stack } else { at }
  }
  let sorted = stack_sorted(tops, fn(i) { key.get(i).unwrap_or(-1) })
  root.first = -1
  root.last = -1
  for i in rest {
    self.link_last(0, i)
  }
  for i in sorted {
    self.link_last(0, i)
  }
  // (and the layers so: the topmost, what takes back, Escape and the keys, the last: Ctx::modal_node, keys_layer)
  let ordered = stack_sorted(self.layers, fn(l) {
    let mut r = l.node
    while r >= 0 && r < self.count && self.nodes[r].parent > 0 {
      r = self.nodes[r].parent
    }
    if r >= 0 && r < self.count { key.get(r).unwrap_or(-1) } else { -1 }
  })
  self.layers.clear()
  self.layers.append(ordered)
  // (what takes back, each layer's opening at its place as the layers are put (one said at none where the one built
  // before it is, kept or built anew) and where it is among them; the rest at the place said, under the layers there,
  // in the order said; what takes it now the topmost)
  let gens : Map[Int, (Int, Int)] = Map([])
  for rank, l in self.layers {
    match self.layer_gen.get(l.id) {
      Some(g) => {
        let mut r = l.node
        while r >= 0 && r < self.count && self.nodes[r].parent > 0 {
          r = self.nodes[r].parent
        }
        gens[g] = (key.get(r).unwrap_or(-1), rank)
      }
      None => ()
    }
  }
  let entries : Array[(BackEntry, Int, Int, Int)] = []
  let mut l = self.back_chain_next
  let mut said = 0
  while l is Said(e, rest) {
    // (a layer's close and what was said in it at that layer's place and rank, those said later over those before)
    let of = if e.layer != 0 { e.layer } else { e.within }
    match gens.get(of) {
      Some((at, rank)) if of != 0 => entries.push(({ ..e, stack: at }, at, rank, said))
      _ => entries.push((e, e.stack, -1, said))
    }
    said = said + 1
    l = rest
  }
  // (the topmost first: by place, a layer over what else is there, the later put layer over the earlier, else as said)
  let over = fn(a : (BackEntry, Int, Int, Int), b : (BackEntry, Int, Int, Int)) {
    if a.1 != b.1 {
      a.1 > b.1
    } else if a.2 != b.2 {
      a.2 > b.2
    } else {
      a.3 < b.3
    }
  }
  let sorted : Array[(BackEntry, Int, Int, Int)] = []
  for e in entries {
    let mut j = sorted.length()
    while j > 0 && over(e, sorted[j - 1]) {
      j = j - 1
    }
    sorted.insert(j, e)
  }
  let mut chain = Unsaid
  for i = sorted.length() - 1; i >= 0; i = i - 1 {
    chain = Said(sorted[i].0, chain)
  }
  self.back_chain_next = chain
  self.back_from_chain()
}

///|
/// `xs` by `key`, those of the same kept in their order.
fn[T] stack_sorted(xs : Array[T], key : (T) -> Int) -> Array[T] {
  let out : Array[T] = []
  for x in xs {
    let k = key(x)
    let mut i = out.length()
    while i > 0 && key(out[i - 1]) > k {
      i = i - 1
    }
    out.insert(i, x)
  }
  out
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
    self.focus_moved(target)
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
      self.focus_moved(back)
    }
  }
  // a field given the focus this frame under the topmost modal layer (a page's composer taking the cursor as its chat
  // is first drawn under a file over the window) does not keep it: hidden there, it would take what is typed over it
  // (Radix's FocusScope: nothing outside a trapped scope takes the focus); it goes back to what had it
  if self.focus != self.focus_before && self.editors.contains(self.focus) {
    let modal = self.layers.filter(fn(l) { l.modal && !l.inert }).last()
    match (modal, self.focusables.iter().find_first(fn(f) { f.id == self.focus })) {
      (Some(m), Some(f)) if !self.layer_built_in(f.layer, m.id) => self.focus_moved(self.focus_before)
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
    // (not built this frame: its opening over)
    if !self.layers.iter().any(fn(x) { x.id == l.id }) {
      self.layer_gen.remove(l.id)
      self.layer_retired.remove(l.id)
      self.layer_on_dismiss.remove(l.id)
      // (its openings' backs given up let go with it: no part kept says them again past here)
      let spent = layer_back_spent.iter().filter(fn(e) { e.1 == l.id }).map(fn(e) { e.0 }).collect()
      for g in spent {
        layer_back_spent.remove(g)
      }
    }
    if !l.inert && !self.layers.iter().any(fn(x) { x.id == l.id }) {
      self.layer_return.remove(l.id)
    }
  }
  let last = self.last_layers
  self.last_layers = self.layers
  last.clear()
  self.layers = last
  // (what was dismissed of the layers published before: as these say now)
  self.layers_gone.clear()
}

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
  // (one way of working it out: the window's tree's nodes said to go beside another go by it too, View::beside)
  @view.place_beside(
    anchor,
    w,
    h,
    self.width,
    self.height,
    side~,
    along~,
    offset~,
    along_offset~,
    padding~,
    flip~,
    rtl=self.direction == Rtl,
  )
}

///|
/// What takes back as one of the old views said it (Ctx's `back_next` and what goes with it), and the layer's opening it
/// is of (Ctx::overlay; 0: none's).
struct BackEntry {
  f : (Int, Double, Double, Double, Double) -> Unit
  node : Int
  edge : Double
  island : @view.NodeId?
  layer : Int
  /// where what said it is in the window's stack of layers (Ctx::stacked; -1 in none)
  stack : Int
  /// the layer's opening it was said in (Ctx::overlay's body; 0: none's): it stands with that layer, over what the
  /// layer said before it (its close), as it was said after it
  within : Int
}

///|
/// What takes back as the old views said it, the last said first (Ctx's `back_chain`): each what takes it once the one
/// over it, a layer's, took it.
enum BackList {
  Said(BackEntry, BackList)
  Unsaid
}

///|
/// What takes back said as it is now (Ctx's `back_next` and what goes with it) over what was said before it: where it
/// is in the window's stack of layers (Ctx::stacked) said with it, the chain put in that order once, as the layers are
/// (raise_layers).
fn Ctx::back_says(self : Ctx) -> Unit {
  match self.back_next {
    Some(f) =>
      self.back_chain_next = Said(
        {
          f,
          node: self.back_node_next,
          edge: self.back_edge_next,
          island: self.back_island_next,
          layer: self.back_layer_next,
          stack: self.back_stack_said(),
          within: self.back_within,
        },
        self.back_chain_next,
      )
    None => ()
  }
}

///|
/// Where what takes back said now stands in the window's stack of layers: a layer's (its close, what is said in it), at
/// the place said for it (Ctx::stacked); none's, at none (where its view is among the tree's, Ctx::back_taker), whatever
/// place it is built under.
fn Ctx::back_stack_said(self : Ctx) -> Int {
  if self.back_layer_next != 0 || self.back_within != 0 {
    self.stack_cur
  } else {
    -1
  }
}

///|
/// What takes back now said as the chain has it (Ctx's `back_chain_next`: its topmost, in the window's stack of layers).
fn Ctx::back_from_chain(self : Ctx) -> Unit {
  match self.back_chain_next {
    Said(top, _) => {
      self.back_next = Some(top.f)
      self.back_node_next = top.node
      self.back_edge_next = top.edge
      self.back_island_next = top.island
    }
    Unsaid => ()
  }
}

///|
/// What `top` says over what `under` does: the whole of it, in its order, then `under`'s.
fn back_list_over(top : BackList, under : BackList) -> BackList {
  match top {
    Unsaid => under
    Said(e, rest) => Said(e, back_list_over(rest, under))
  }
}

///|
/// The openings of layers so far (Ctx's `layer_gen`): each its own, a layer of the same key opened again another.
// kept across runs: only a count
let layer_opened : Ref[Int] = Ref(0)

///|
/// The layers' openings whose back was taken (Ctx::layer_back_taken), till they read it (Ctx::overlay: dismissed) or
/// close: what they said of back no more what takes it, said again as a part kept or not.
// kept across runs: put back by layer_back_forget
let layer_back_spent : Map[Int, Int] = Map::new()

///|
/// What the last frame drew of layers dismissed since (Ctx::layers_dismissed), by its ids: no input of theirs, pressed,
/// pointed at or scrolled (hit_at), till the next frame's targets are found.
// kept across runs: put back by layer_back_forget; let go as a frame's targets come (frame_paint)
let layer_retired_ids : Set[Int] = Set::new()

///|
fn layer_back_forget() -> Unit {
  layer_back_spent.clear()
  layer_retired_ids.clear()
}

///|
/// Back taken by layer `id` as its opening `gen` (Ctx::overlay's): where that is the one open now, it is dismissed (its
/// view closes it as it is built next), and what takes back from now (as of this moment: the next back) is what it was
/// said over, the host told so; a gesture held by an opening closed since, nothing.
fn Ctx::layer_back_taken(self : Ctx, id : Int, gen : Int) -> Unit {
  guard self.layer_gen.get(id) == Some(gen) && !self.layer_retired_now(id) else { return }
  // (staying open as it is taken: taken all the same, nothing done)
  if self.last_layers.iter().any(fn(l) { l.id == id && layer_stays(l) }) {
    return
  }
  self.dismissals[id] = Back
  self.layer_dismissed(id, Back)
}

///|
/// Layer `id` dismissed (`why`) at this moment, as its opening open now (Ctx::layers_dismissed's, alone).
fn Ctx::layer_dismissed(self : Ctx, id : Int, why : Dismiss) -> Unit {
  self.layers_dismissed([(id, why)])
}

///|
/// Layers dismissed at this moment (`gone`, the topmost first), each as its opening open now: all of them first given
/// up together (their openings over: one of the same key built again is another; their back given up, what was said
/// under them taking the next; taking no input from here, leaving as their views draw them going; the focus in one of
/// them back where it was as it opened, where that is still there), then each told so, in that order (Ctx::with_dismissed),
/// once (not `tell`: none, an opening ended by what it is for, Ctx::layer_ended), and the host told what takes back.
/// Their views read the dismissals as they are built next (Overlay's `dismissed`), as before.
fn Ctx::layers_dismissed(self : Ctx, gone : Array[(Int, Dismiss)], tell? : Bool = true) -> Unit {
  let told : Array[((Dismiss) -> Unit, Dismiss)] = []
  for d in gone {
    let (id, why) = d
    guard self.layer_gen.get(id) is Some(gen) && !self.layer_retired_now(id) else { continue }
    // (where the focus is, first: in it or on its own ground, as the last frame had it)
    let owned = self.focus == id || self.focus_in_layer(id)
    // (this opening takes no input from here: what it drew pressed or scrolled, its keys, a press held in it; the last
    // frame's facts of it kept as they are, its view drawing it going from the next)
    self.layer_retired[id] = gen
    self.layers_gone.add(id)
    layer_back_spent[gen] = id
    for i in 0..<self.count {
      let n = self.nodes[i]
      if n.id != 0 && self.layer_of(i) == id {
        layer_retired_ids.add(n.id)
      }
    }
    if self.down && layer_retired_ids.contains(self.active) {
      // (as the host calling it off: the rest of it nobody's)
      if view_held.val is Some(Old(_, _)) {
        view_held.val = Some(Nowhere)
      }
      self.press_called_off(self.px, self.py, view_moment())
    }
    // (the focus in it back where it was as it opened, where that may still take it; else nowhere)
    if owned {
      let back = self.layer_return.get(id).unwrap_or(0)
      // (a stop of the old views' that may take it, or a node of the tree's: its own, as focus_moved has it)
      let there = back != 0 &&
        (self.last_focusables.iter().any(fn(f) { f.id == back && !self.layer_inert(f.layer) }) ||
        tree_said_ids.contains(back))
      self.focus_moved(if there { back } else { 0 })
    }
    match self.layer_on_dismiss.get(id) {
      Some((g, f)) if g == gen => {
        self.layer_on_dismiss.remove(id)
        if tell {
          told.push((f, why))
        }
      }
      _ => ()
    }
  }
  self.back_layer_spent()
  @signals.start_batch()
  for t in told {
    @signals.untracked(fn() { (t.0)(t.1) })
  }
  @signals.end_batch()
  self.back_told_host()
}

///|
/// Layer `id`'s opening ended at this moment by what it is for (a choice made in it, its menu done with): as one
/// dismissed is (Ctx::layers_dismissed), its opening over, taking no input from here (its keys, presses, the back, the
/// focus in it given back), leaving as its view draws it going; but not dismissed, so nothing is told so
/// (Ctx::with_dismissed's `f` is for a dismissal). Its view closes it as it is built next.
pub fn Ctx::layer_ended(self : Ctx, id : Int) -> Unit {
  self.layers_dismissed([(id, Escape)], tell=false)
}

///|
/// Whether layer `l`, as the last frame built it, takes input now: not leaving, its opening not dismissed since (what
/// reads the last frame's layers for an input asks it: keys, the focus, Tab, presses and wheels over a modal one).
fn Ctx::layer_takes(self : Ctx, l : Layer) -> Bool {
  // (one dismissed since: none, though this frame's build has read its dismissal and let its opening go before the frame
  // publishes it inert or gone, layers_frame_end)
  !l.inert && !self.layer_retired_now(l.id) && !self.layers_gone.contains(l.id)
}

///|
/// Whether layer `id`'s opening as the last frame built it was dismissed since (Ctx::layers_dismissed): it takes no
/// input till its view builds it again.
fn Ctx::layer_retired_now(self : Ctx, id : Int) -> Bool {
  match (self.layer_retired.get(id), self.layer_gen.get(id)) {
    (Some(r), Some(g)) => r == g
    _ => false
  }
}

///|
/// The layer the keys go to as the last frame built them (Ctx::layer_escape's): the topmost open that is modal or has
/// the focus in it; 0 none (the window's, under every layer). `from`: of those at that place in the window's stack of
/// layers or over it alone (Ctx::keys_reach).
fn Ctx::keys_layer(self : Ctx, from? : Int = -3) -> Int {
  let open = self.last_layers.filter(fn(l) { self.layer_takes(l) && self.layer_stack(l) >= from }).rev()
  match open.iter().find_first(fn(l) { l.modal || self.focus_in_layer(l.id) }) {
    Some(l) => l.id
    None => 0
  }
}

///|
/// Whether the keys reach `id` (the focus) as the last frame built the layers: the layer they go to is the one it is in
/// (none, under every layer, where it is in none). Where it is in the window's tree (a node of it, or an old view's stop
/// or field hosted in one: focus_node_of), the old frame's layers under that in the window's stack of layers keep none
/// of them from it, as those over it do (view_key's rule for the keys it leaves the tree).
fn Ctx::keys_reach(self : Ctx, id : Int) -> Bool {
  let from = match (focus_node_of(id), view_app.val) {
    (Some(n), Some(t)) => t.stack_of(n)
    _ => -3
  }
  let layer = self.keys_layer(from~)
  if layer == 0 {
    !self.last_layers.iter().any(fn(l) { self.layer_takes(l) && self.layer_stack(l) >= from && self.focus_in_layer(l.id) })
  } else {
    self.focus_in_layer(layer) && self.focus == id
  }
}

///|
/// What a layer's input (Escape, a press outside it) dismisses, at the input's moment, as a frame would take it as it
/// begins (Ctx::layer_keys), from what the last frame built: an Escape come since to the topmost it dismisses, down to
/// where the keys go; the press outside each, from the top down; each dismissed so given up and told so then, the
/// topmost first (Ctx::layers_dismissed).
fn Ctx::layer_keys_now(self : Ctx) -> Unit {
  let before : Map[Int, Dismiss] = {}
  self.dismissals.each(fn(id, why) { before[id] = why })
  let open = self.last_layers.filter(fn(l) { self.layer_takes(l) }).rev()
  // (an Escape come since the frame began: in the keys the next frame takes, desk_frame_start; taken here, it is gone
  // for everything else as it is there)
  self.layer_escape(desk.mutable_keys) |> ignore
  self.layer_keys()
  let gone : Array[(Int, Dismiss)] = []
  for l in open {
    match self.dismissals.get(l.id) {
      Some(why) if before.get(l.id) != Some(why) => gone.push((l.id, why))
      _ => ()
    }
  }
  self.layers_dismissed(gone)
}

///|
/// `body` built, the first layer built in it (Ctx::overlay) telling `f` as it is dismissed, at that moment (back, Escape,
/// a press outside it: Ctx::layer_dismissed), once for each opening of it.
pub fn Ctx::with_dismissed(self : Ctx, f : (Dismiss) -> Unit, body : () -> Unit) -> Unit {
  let was = self.layer_hook
  self.layer_hook = Some(f)
  body()
  self.layer_hook = was
}

///|
/// What takes back as published (Ctx's `back`, `back_chain`), a layer's opening whose back was taken already on top:
/// what it was said over, and so on down, in its place.
fn Ctx::back_layer_spent(self : Ctx) -> Unit {
  let mut moved = false
  // (a layer's close, and what was said in it: the layer gone, none of it takes back)
  while self.back_chain is Said(e, under) &&
        ((e.layer != 0 && layer_back_spent.contains(e.layer)) || (e.within != 0 && layer_back_spent.contains(e.within))) {
    self.back_chain = under
    moved = true
  }
  if moved {
    match self.back_chain {
      Said(e, _) => {
        self.back = Some(e.f)
        self.back_node = e.node
        self.back_edge = e.edge
        self.back_island = e.island
        self.back_stack = e.stack
      }
      Unsaid => {
        self.back = None
        self.back_node = -1
        self.back_island = None
        self.back_stack = -3
      }
    }
  }
}

///|
/// Which layer the keys go to as the last frame built them (the topmost open that has them: a modal one, a menu, a
/// dialog, a sheet, a file over the window; one the focus is in. One over it that has none, a toast or a tip, leaves them
/// to it; one the focus stayed outside of, a field's suggestions or a menubar's menu opened by the pointer, leaves them
/// where the focus is); and an Escape in `keys` not taken yet dismissing the topmost layer it dismisses, down to there
/// (one that is not dismissed by it and has no keys leaves it to those under it; one that has the keys and is not, a
/// file over the window, to what it holds, its own Escape), taken and gone for everything else.
fn Ctx::layer_escape(self : Ctx, keys : Array[(Int, Int, Bool)]) -> Int {
  let open = self.last_layers.filter(fn(l) { self.layer_takes(l) }).rev()
  let keys_layer = self.keys_layer()
  for l in open {
    if l.escape {
      let mut took = false
      for k in 0..<keys.length() {
        let (code, mods, taken) = keys[k]
        if code == key_escape && !taken {
          // (one step back within it first, where it says it took it so: not dismissed)
          let within = layer_stays(l) ||
            (match l.on_escape {
              Some(f) => f()
              None => false
            })
          if !within {
            self.dismissals[l.id] = Escape
          }
          keys[k] = (code, mods, true)
          took = true
        }
      }
      // (an Escape that dismissed it is its, gone for everything else: not even what reads the keys a field took sees
      // it, a page's own Escape under it)
      if took {
        keys.retain(fn(k) { k.0 != key_escape })
      }
    }
    if l.id == keys_layer {
      break
    }
  }
  keys_layer
}

///|
/// Whether layer `l` says it stays open now, as something would dismiss it (Ctx::overlay's `stays`).
fn layer_stays(l : Layer) -> Bool {
  match l.stays {
    Some(f) => f()
    None => false
  }
}

///|
/// Whether a press at (x, y) of the window, `target` what takes it, is on `anchor` (a layer's trigger, Ctx::overlay's):
/// it, or what the last frame drew in it (its own targets: a rail's places; Ctx::holders, as Ctx::press_within has it:
/// not what only lies over it, nor where what holds it cuts it away).
fn Ctx::on_anchor(self : Ctx, anchor : Int, target : Int, x : Double, y : Double) -> Bool {
  if target == anchor {
    return true
  }
  let held : Array[Int] = []
  self.holders(self.hit_of(target, x, y), held)
  held.contains(anchor)
}
