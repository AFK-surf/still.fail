// Layout: a small flexbox. measure() gives a node's content size for a
// maximum width; place() gives every node its final rectangle.

///|
fn Ctx::editor_display(self : Ctx, n : Node) -> String {
  match self.editors.get(n.id) {
    Some(st) => st.display()
    None => ""
  }
}

///|
fn Ctx::measure(self : Ctx, i : Int, max_w : Double) -> (Double, Double) {
  let n = self.nodes[i]
  if n.m_key == max_w {
    return (n.m_w, n.m_h)
  }
  let pw = n.pad_l + n.pad_r
  let ph = n.pad_t + n.pad_b
  let avail = match n.w {
    Px(p) => p
    _ => max_w
  }
  let inner = dmax(avail - pw, 0.0)
  let (cw, ch) = if n.kind == kind_text {
    let tl = layout_text(n.text, n.font_size, n.weight, inner, n.wrap)
    (tl.w, tl.h)
  } else if n.kind == kind_editor {
    let s = self.editor_display(n)
    let tl = layout_text(s, n.font_size, n.weight, inner, true)
    (inner, tl.h)
  } else if n.kind == kind_list {
    (inner, 0.0)
  } else if n.dir == Column {
    let mut w = 0.0
    let mut h = 0.0
    let mut c = n.first
    let mut k = 0
    while c >= 0 {
      let (a, b) = self.child_size(c, inner, Column)
      w = dmax(w, a)
      h = h + b
      k = k + 1
      c = self.nodes[c].next
    }
    if k > 1 {
      h = h + n.gap * (k - 1).to_double()
    }
    (w, h)
  } else {
    let mut w = 0.0
    let mut h = 0.0
    let mut c = n.first
    let mut k = 0
    while c >= 0 {
      let (a, b) = self.child_size(c, dmax(inner - w, 0.0), Row)
      w = w + a
      h = dmax(h, b)
      k = k + 1
      c = self.nodes[c].next
    }
    if k > 1 {
      w = w + n.gap * (k - 1).to_double()
    }
    (w, h)
  }
  let fw = match n.w {
    Px(p) => p
    _ => cw + pw
  }
  let fh = match n.h {
    Px(p) => p
    _ => dclamp(ch + ph, n.min_h, n.max_h)
  }
  n.m_key = max_w
  n.m_w = fw
  n.m_h = fh
  (fw, fh)
}

///|
fn Ctx::child_size(
  self : Ctx,
  c : Int,
  avail : Double,
  _dir : Dir,
) -> (Double, Double) {
  let n = self.nodes[c]
  match n.w {
    Px(p) => {
      let (_, h) = self.measure(c, p)
      (p, h)
    }
    _ => self.measure(c, avail)
  }
}

///|
fn Ctx::place(
  self : Ctx,
  i : Int,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
) -> Unit {
  let n = self.nodes[i]
  n.x = x
  n.y = y
  n.fw = w
  n.fh = h
  let ix = x + n.pad_l
  let iy = y + n.pad_t
  let iw = dmax(w - n.pad_l - n.pad_r, 0.0)
  let ih = dmax(h - n.pad_t - n.pad_b, 0.0)
  if n.kind == kind_text {
    n.tl = Some(layout_text(n.text, n.font_size, n.weight, iw, n.wrap))
    return
  }
  if n.kind == kind_editor {
    match self.editors.get(n.id) {
      Some(st) => {
        st.tl = Some(layout_text(st.display(), n.font_size, n.weight, iw, true))
        st.ox = ix
        st.oy = iy
      }
      None => ()
    }
    return
  }
  if n.kind == kind_list {
    self.place_list(n, ix, iy, iw, ih)
    return
  }
  // collect children
  let kids = []
  let mut c = n.first
  while c >= 0 {
    kids.push(c)
    c = self.nodes[c].next
  }
  let k = kids.length()
  if k == 0 {
    return
  }
  let gaps = n.gap * (k - 1).to_double()
  let main_sz = Array::make(k, 0.0)
  let cross_sz = Array::make(k, 0.0)
  let mut fixed = gaps
  let mut flex = 0.0
  if n.dir == Column {
    for j in 0..<k {
      let ch = self.nodes[kids[j]]
      let cw = match ch.w {
        Px(p) => p
        Fill(_) => iw
        Auto =>
          if n.align == AStretch {
            iw
          } else {
            let (a, _) = self.measure(kids[j], iw)
            dmin(a, iw)
          }
      }
      cross_sz[j] = cw
      match ch.h {
        Px(p) => {
          main_sz[j] = p
          fixed = fixed + p
        }
        Fill(f) => flex = flex + f
        Auto => {
          let (_, b) = self.measure(kids[j], cw)
          main_sz[j] = b
          fixed = fixed + b
        }
      }
    }
  } else {
    // widths of fixed and content-sized children first
    let mut used = gaps
    for j in 0..<k {
      let ch = self.nodes[kids[j]]
      match ch.w {
        Px(p) => {
          main_sz[j] = p
          used = used + p
        }
        _ => ()
      }
    }
    for j in 0..<k {
      let ch = self.nodes[kids[j]]
      match ch.w {
        Fill(f) => flex = flex + f
        Auto => {
          let (a, _) = self.measure(kids[j], dmax(iw - used, 0.0))
          main_sz[j] = a
          used = used + a
        }
        _ => ()
      }
    }
    fixed = used
  }
  let free = (if n.dir == Column { ih } else { iw }) - fixed
  if flex > 0.0 {
    for j in 0..<k {
      let ch = self.nodes[kids[j]]
      let f = if n.dir == Column {
        match ch.h {
          Fill(f) => f
          _ => 0.0
        }
      } else {
        match ch.w {
          Fill(f) => f
          _ => 0.0
        }
      }
      if f > 0.0 {
        main_sz[j] = dmax(free, 0.0) * f / flex
      }
    }
  }
  if n.dir == Row {
    for j in 0..<k {
      let ch = self.nodes[kids[j]]
      cross_sz[j] = match ch.h {
        Px(p) => p
        Fill(_) => ih
        Auto =>
          if n.align == AStretch {
            ih
          } else {
            let (_, b) = self.measure(kids[j], main_sz[j])
            b
          }
      }
    }
  }
  let rest = if flex > 0.0 { 0.0 } else { dmax(free, 0.0) }
  let mut pos = match n.justify {
    JStart => 0.0
    JCenter => rest / 2.0
    JEnd => rest
    JBetween => 0.0
  }
  let step_gap = match n.justify {
    JBetween => if k > 1 { n.gap + rest / (k - 1).to_double() } else { n.gap }
    _ => n.gap
  }
  for j in 0..<k {
    let ch = self.nodes[kids[j]]
    let cross_total = if n.dir == Column { iw } else { ih }
    let off = match n.align {
      AStart | AStretch => 0.0
      ACenter => (cross_total - cross_sz[j]) / 2.0
      AEnd => cross_total - cross_sz[j]
    }
    if n.dir == Column {
      self.place(
        kids[j],
        ix + off + ch.tx,
        iy + pos + ch.ty,
        cross_sz[j],
        main_sz[j],
      )
    } else {
      self.place(
        kids[j],
        ix + pos + ch.tx,
        iy + off + ch.ty,
        main_sz[j],
        cross_sz[j],
      )
    }
    pos = pos + main_sz[j] + step_gap
  }
}
