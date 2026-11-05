// A container owns the measurement and placement of its direct children. The
// result is a value consumed by layout, never a notification sent back to the
// component. Flex and a container's own arrangement share the same child
// measurement, caches and placement machinery.

///|
pub struct Layout {
  owner : Node
  w : Double
  h : Double
  aw : Double
  ah : Double
}

///|
pub struct Measured {
  owner : Node
  child : Node
  w : Double
  h : Double
  kw : Double
  kh : Double
  aw : Double
  ah : Double
  cbw : Double
  cbh : Double
  plan : Arranged?
}

///|
pub struct Placement {
  measured : Measured
  x : Double
  y : Double
}

///|
pub struct Arrangement {
  w : Double
  h : Double
  children : Array[Placement]
}

///|
pub type ArrangeFn = (Layout) -> Arrangement

///|
// Measurement produces a placement plan. Assigning that plan its own measured
// size does not ask the component to measure again with the answer as input:
// a clipped or folded container can occupy less room than its children.
struct Arranged {
  result : Arrangement
  w : Double
  h : Double
  x : Double
  y : Double
}

///|
// Returned beside out_h. Only a custom container produces a placement plan;
// each caller takes ownership of it before measuring another child.
let out_arranged : Ref[Arranged?] = Ref(None)

///|
/// The content size allocated by the parent, or None during intrinsic measure.
pub fn Layout::width(self : Layout) -> Double? {
  if known(self.w) { Some(self.w) } else { None }
}

///|
pub fn Layout::height(self : Layout) -> Double? {
  if known(self.h) { Some(self.h) } else { None }
}

///|
pub fn Layout::max_width(self : Layout) -> Double? {
  if known(self.aw) { Some(self.aw) } else { None }
}

///|
pub fn Layout::max_height(self : Layout) -> Double? {
  if known(self.ah) { Some(self.ah) } else { None }
}

///|
/// Measure a direct child without placing anything. A later child can be
/// allocated the space left by this answer in this same parent calculation.
pub fn Layout::measure(
  self : Layout,
  child : Node,
  width? : Double,
  height? : Double,
) -> Measured {
  guard self.owner.children.any(fn(n) { physical_equal(n, child) }) else {
    abort("a layout measures only its direct children")
  }
  let w = width.unwrap_or(undef)
  let h = height.unwrap_or(undef)
  let aw = width.unwrap_or(self.aw)
  let ah = height.unwrap_or(self.ah)
  let mw = size_node(child, w, h, aw, ah, self.w, self.h, false)
  let mh = out_h.val
  { owner: self.owner, child, w: mw, h: mh, kw: w, kh: h, aw, ah, cbw: self.w, cbh: self.h, plan: out_arranged.val }
}

///|
// A flex item's measurement, when it came from a custom container. The flex
// algorithm carries this value through allocation just as Layout::measure does.
fn measured_arrangement(
  owner : Node, child : Node, kw : Double, kh : Double,
  aw : Double, ah : Double, cbw : Double, cbh : Double,
) -> Measured? {
  out_arranged.val.map(fn(plan) {
    { owner, child, w: plan.w, h: plan.h, kw, kh, aw, ah, cbw, cbh, plan: Some(plan) }
  })
}

///|
pub fn Measured::size(self : Measured) -> (Double, Double) { (self.w, self.h) }

///|
pub fn Measured::at(self : Measured, x : Double, y : Double) -> Placement {
  { measured: self, x, y }
}

///|
/// Content size and positions, relative to this container's content origin.
pub fn arrangement(width : Double, height : Double, children : Array[Placement]) -> Arrangement {
  { w: width, h: height, children }
}

///|
fn arrange_node(
  node : Node,
  arrange : ArrangeFn,
  b : Box,
  w : Double,
  h : Double,
  aw : Double,
  ah : Double,
  perform : Bool,
) -> Double {
  let inner = fn(v : Double, padding : Double) {
    if known(v) { fmax(0.0, v - padding) } else { undef }
  }
  let available = fn(given : Double, offered : Double, low : Double, high : Double) {
    if known(given) { given } else if known(offered) { clamp_size(offered, low, high) } else { high }
  }
  let space : Layout = {
    owner: node,
    w: inner(w, b.pbw()), h: inner(h, b.pbh()),
    aw: inner(available(w, aw, b.min_w, b.max_w), b.pbw()),
    ah: inner(available(h, ah, b.min_h, b.max_h), b.pbh()),
  }
  let result = arrange(space)
  guard result.w >= 0.0 && !result.w.is_inf() && result.h >= 0.0 && !result.h.is_inf() else {
    abort("a layout returns finite nonnegative dimensions")
  }
  let fw = if known(w) { w } else { clamp_size(result.w + b.pbw(), b.min_w, b.max_w) }
  let fh = if known(h) { h } else { clamp_size(result.h + b.pbh(), b.min_h, b.max_h) }
  let plan = { result, w: fw, h: fh, x: b.bor_l + b.pad_l, y: b.bor_t + b.pad_t }
  if perform { place_arrangement(node, plan) }
  out_h.val = fh
  out_arranged.val = Some(plan)
  fw
}

///|
fn place_arrangement(node : Node, plan : Arranged) -> Unit {
  for child in node.children { child.line = -1 }
  for placed in plan.result.children {
    let m = placed.measured
    guard physical_equal(m.owner, node) else { abort("a measurement belongs to its parent layout") }
    let c = m.child
    guard c.line == -1 else { abort("a layout places each child once") }
    c.line = 0
    place_measured(m)
    c.left = on_grid(plan.x + placed.x)
    c.top = on_grid(plan.y + placed.y)
  }
}

///|
fn place_measured(m : Measured) -> Unit {
  let c = m.child
  match m.plan {
    Some(plan) => {
      touch(c)
      if reusing.val && c.p_ok && (c.p_arranged is Some(was) && physical_equal(was, plan)) {
        c.skip_gen = generation.val
        counters[1] = counters[1] + 1
      } else {
        place_arrangement(c, plan)
        c.p_ok = true
        c.p_kw = m.kw
        c.p_kh = m.kh
        c.p_aw = m.aw
        c.p_ah = m.ah
        c.p_cbw = m.cbw
        c.p_cbh = m.cbh
        c.p_w = m.w
        c.p_h = m.h
        c.p_arranged = Some(plan)
        c.laid_gen = generation.val
      }
      c.width = m.w
      c.height = m.h
    }
    None => {
      c.width = size_node(c, m.kw, m.kh, m.aw, m.ah, m.cbw, m.cbh, true)
      c.height = out_h.val
    }
  }
}
