// The phone's bottom bar as nodes of the window's tree (bar.mbt's model and ways; bar_drawn's look): laid out where
// it is told (bar_tell: BarLaid, the same its glass takes a finger by, bar_glass_node), each of its numbers read as
// each frame is painted at the frame's moment (Painted, View::drawn_at) while any of them goes, at rest once they all
// are (a moment of its own said at their end: View::at_moment), so a frame of the bar moving draws its own layer
// again and nothing of the pages under it.

///|
/// Said each time the bar is told what it goes by (bar_tell): its ways set out anew, what reads them read again.
let bar_said : @signals.Signal[Int] = @signals.signal(0, same=fn(a, b) { a == b })

///|
/// Said as all of the bar's ways have come to rest (the moment of their end, View::at_moment).
let bar_ways_rested : @signals.Signal[Int] = @signals.signal(0, same=fn(a, b) { a == b })

///|
fn bar_said_again() -> Unit {
  bar_said.set(@signals.untracked(fn() { bar_said.get() }) + 1)
}

///|
/// The moment the bar is painted at, as `n` paints in the frame `laid` is of: the frame's while any of its ways goes
/// (Laid::at: each frame painted again for it till they are all at rest), else the logic's (where they rest); read
/// again as it is told anew and as they come to rest.
fn bar_moment(laid : @view.Laid, n : @view.View) -> Double {
  bar_said.get() |> ignore
  bar_ways_rested.get() |> ignore
  let now = n.logic_at()
  if bar.rest() > now {
    laid.at()
  } else {
    now
  }
}

///|
/// A box `w` by `h` at (`x`, `y`) in `parent` (all of it: View::over), made by `f`; it.
fn bar_at(
  parent : @view.View,
  x : () -> Double,
  y : () -> Double,
  w : () -> Double,
  h : () -> Double,
  f : (@view.View) -> Unit,
) -> @view.View {
  let made : Ref[@view.View?] = Ref(None)
  parent.box(fn(o) {
    o.over(Is(true)) |> ignore
    made.val = Some(
      o.box(fn(b) {
        b
        .width(By(fn() { Some(w()) }))
        .height(By(fn() { Some(h()) }))
        .offset(By(fn() { (x(), y()) }))
        |> ignore
        f(b)
      }),
    )
  })
  |> ignore
  made.val.unwrap()
}

///|
/// The bottom bar drawn in `g`, its glass's node (bar_glass_node: where the bar is laid out, what takes a finger on it,
/// so what a press there goes to holds what it draws), as the old frame's bottom_bar drew it: its shadow, the action's
/// disc under the glass, the glass with its notch, the action in the notch, the ball, the places. `ws`: the workspace in
/// view.
fn bar_node(g : @view.View, src : Source, ws : () -> Workspace?) -> Unit {
  let told = fn() { bar_told_now.get() }
  let laid = fn() {
    match told() {
      Some(t) => Some(bar_laid(t))
      None => None
    }
  }
  g.box(fn(b) {
    b.over(Is(true)) |> ignore
    // (its ways said to have come to rest at their end: what reads them read again then, at rest)
    let due : Ref[() -> Unit] = Ref(fn() {  })
    b.reacts(fn() { bar_said.get() }, fn(_) {
      (due.val)()
      let end = bar.rest()
      due.val = if end > b.logic_at() {
        b.at_moment(end, fn() { bar_ways_rested.set(@signals.untracked(fn() { bar_ways_rested.get() }) + 1) })
      } else {
        fn() {  }
      }
    })
    b.owns(fn() { (due.val)() }) |> ignore
    // (shown; going, it takes nothing and says nothing, drawn as it goes down out of the way, and is gone once it has:
    // back while it goes, the same, come back)
    b.show(
      fn() {
        match told() {
          Some(t) => t.shown
          None => false
        }
      },
      fn(holder) { bar_holder_node(holder, src, ws, laid) },
      leave=bar_hide_ms,
    )
  })
  |> ignore
}

///|
/// The bar's panel (its glass, the panel's rows over it as it opens), `laid` where it is told: going down out of the
/// way and back up, drawn up out from under a finger that has it, drawn so, laid out where it rests.
fn bar_holder_node(holder : @view.View, src : Source, ws : () -> Workspace?, laid : () -> BarLaid?) -> Unit {
  let l = fn() { laid().unwrap_or(bar_laid({ shown: false, action: "", active: None, sets: [[]], cur: 0, width: 0.0 })) }
  let w = fn() { l().w }
  let panel = fn() { l().panel }
  let row_top = fn() { l().row_top }
  // (the glass's top laid out where the panel goes, drawn where it is as each frame is painted: `drift` off that)
  let clip_top = fn() {
    bar_said.get() |> ignore
    bar_glass_top(l().reach, bar.o.to)
  }
  let drift = fn(laid : @view.Laid, n : @view.View) {
    bar_glass_top(l().reach, bar.o.at(bar_moment(laid, n)).0) - clip_top()
  }
  holder.width(By(fn() { Some(w()) })).height(By(fn() { Some(panel()) })) |> ignore
  holder
  .alpha(Painted(fn(laid) { bar.vis.at(bar_moment(laid, holder)).0 }))
  .drawn_off(
    Painted(fn(laid) {
      let t = bar_moment(laid, holder)
      let v = bar.vis.at(t).0
      let foot = 22.0 + nav_foot()
      let raised = bar_raise(holder.window().1, foot, panel(), status_top()) * bar.up.value_at(t)
      (0.0, (1.0 - v) * bar_drop - raised)
    }),
  )
  |> ignore
  bar_shadow_node(holder, w, clip_top, panel, drift)
  // the action's disc under the glass (its warmth round the notch), and the glass with the notch cut into its top
  let disc_x = fn() { w() / 2.0 - drop / 2.0 }
  let disc_y = fn() { row_top() - lift - drop / 2.0 }
  let under = bar_at(holder, disc_x, disc_y, fn() { drop }, fn() { drop }, fn(d) {
    d
    .radius(Is(drop / 2.0))
    .ground(By(fn() {
      let t = @sf.theme()
      @sf.over(t.p.bg, @sf.alpha(t.p.accent, action_ink))
    }))
    |> ignore
  })
  bar_disc_look(under)
  bar_glass_capsule(holder, w, clip_top, panel, drift)
  // (the notch's key itself: pressed while the place has an action, taken only where the notch is drawn open at its
  // moment (closing, the panel up, what is under it the panel's); what it opens opened beside it)
  let disc = bar_at(holder, disc_x, disc_y, fn() { drop }, fn() { drop }, fn(d) {
    d
    .radius(Is(drop / 2.0))
    .glass(By(fn() { Some(@sf.glass_action().sharing()) }))
    .presses(By(fn() {
      match bar_told_now.get() {
        Some(t) => t.shown && t.action != ""
        None => false
      }
    }))
    .takes(fn(w, h, at) { if bar.drag < 0.0 && !bar.holds && bar.k_at(at) > 0.9 { [(0.0, 0.0, w, h)] } else { [] } })
    .on_press(fn() {
      match ws() {
        Some(w) =>
          bar_action_run(src, w, match @ui.tree_cause() {
            Some(at) => at
            None => @ui.current().moment()
          })
        None => ()
      }
    })
    |> ignore
    d.box(fn(c) {
      c.width(Is(Some(drop))).height(Is(Some(drop))).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
      // (the action's icon, made anew as the action is another: m_face, said as the bar is told)
      c.pick(
        fn() {
          bar_said.get() |> ignore
          m_face.val
        },
        fn(i, face) {
          if face != "" {
            @sf.icon_node(i, face, if face == "ling" { 40.0 } else { 30.0 }, Is(0xFFFFFFFFL)) |> ignore
          }
        },
      )
    })
    |> ignore
  })
  bar_disc_look(disc)
  // (what its action opens opened beside it: bar_action_run)
  bar_action_anchor.val = Some(disc)
  bar_ball_node(holder)
  bar_rows_node(holder, src, ws, w, clip_top, l)
  bar_places_node(holder, src, ws, w, row_top, l)
  bar_lens_node(holder)
  bar_swap_node(holder, src, ws, w, row_top, clip_top, panel)
}

///|
/// A disc in the notch (the action's, its ground under the glass): growing with the notch, fading while a finger has
/// the bar (disc_look's), as each frame is painted.
fn bar_disc_look(d : @view.View) -> Unit {
  let look = fn(laid : @view.Laid) {
    let t = bar_moment(laid, d)
    let k = bar.k_at(t)
    let up = bar.up.value_at(t)
    let visible = 1.0 - dclamp(up, 0.0, 1.0)
    if k <= 0.001 {
      (0.0, 1.0, 0.0)
    } else if k < 1.0 {
      (dmin(1.0, k * 3.0) * visible, dmax(0.001, k), lift * (1.0 - k))
    } else {
      (visible, 1.0, 0.0)
    }
  }
  d.alpha(Painted(fn(laid) { look(laid).0 })).scale(Painted(fn(laid) { look(laid).1 })).drawn_off(Painted(fn(laid) { (0.0, look(laid).2) }))
  |> ignore
}

///|
/// The bar's shadow (bar_shadow's): a blurred rounded rectangle 4 lower, outside the glass's outline only, none above
/// its top, coming in down its rounded ends in bands.
fn bar_shadow_node(
  holder : @view.View,
  w : () -> Double,
  top : () -> Double,
  bottom : () -> Double,
  drift : (@view.Laid, @view.View) -> Double,
) -> Unit {
  let h = fn() { bottom() - top() }
  let r = fn() { dmin(rad, h() / 2.0) }
  let room = 40.0
  let cast = fn(band : @view.View, from : () -> Double) {
    bar_at(band, fn() { room }, fn() { -from() }, w, h, fn(s) {
      s
      .radius(By(r))
      .shadow(By(fn() { (6.0, bar_shadow_y, @sf.alpha(0x000000FFL, if @sf.theme().dark { 0.45 } else { 0.16 })) }))
      .shadow_outside(Is(true))
      // (its band drawn with the glass's top: its foot where it is)
      .ground_drawn(
        Painted(fn(laid) {
          let d = drift(laid, s)
          (0.0, 0.0, 0.0, -d)
        }),
      )
      |> ignore
    })
    |> ignore
  }
  for k in 0..<bar_shadow_fade {
    let y0 = fn() { r() * k.to_double() / bar_shadow_fade.to_double() }
    let bh = fn() { r() / bar_shadow_fade.to_double() }
    bar_at(holder, fn() { -room }, fn() { top() + y0() }, fn() { w() + 2.0 * room }, bh, fn(band) {
      band
      .clips(Is(true))
      .alpha(Is((k.to_double() + 0.5) / bar_shadow_fade.to_double()))
      .offset(Painted(fn(laid) { (-room, top() + y0() + drift(laid, band)) }))
      |> ignore
      cast(band, y0)
    })
    |> ignore
  }
  // (down to the foot whatever the top: the glass's top drawn higher as the panel opens)
  bar_at(holder, fn() { -room }, fn() { top() + r() }, fn() { w() + 2.0 * room }, fn() { bottom() - r() + room }, fn(
    band
  ) {
    band.clips(Is(true)).offset(Painted(fn(laid) { (-room, top() + r() + drift(laid, band)) })) |> ignore
    cast(band, r)
  })
  |> ignore
}

///|
/// The glass (bar_glass's) from `top` to `bottom`, `w` wide, the notch cut into its top where the notch is as each
/// frame is painted, and the notch's own edge lit between its lips.
fn bar_glass_capsule(
  holder : @view.View,
  w : () -> Double,
  top : () -> Double,
  bottom : () -> Double,
  drift : (@view.Laid, @view.View) -> Double,
) -> Unit {
  let h = fn() { bottom() - top() }
  let corner = fn() { dmin(rad, h() / 2.0) }
  // (the notch where it is drawn, and where its lips are then: none while the circle is not through the edge)
  let notch = fn(laid : @view.Laid, n : @view.View) {
    let (cy, r) = notch_at(bar.k_at(bar_moment(laid, n)))
    (cy, r, notch_lips(w(), cy, r))
  }
  bar_at(holder, fn() { 0.0 }, top, w, h, fn(g) {
    g
    .radius(By(corner))
    .glass(By(fn() { Some(@sf.glass_bottom_bar()) }))
    // (its top where the panel has it as each frame is painted, its foot where it is)
    .ground_drawn(
      Painted(fn(laid) {
        let d = drift(laid, g)
        (0.0, d, 0.0, -d)
      }),
    )
    .notch(
      Painted(fn(laid) {
        match notch(laid, g) {
          (cy, r, Some(_)) => (cy, r, fillet)
          (_, _, None) => (0.0, 0.0, 0.0)
        }
      }),
    )
    |> ignore
  })
  |> ignore
  // the notch's outline alone, cut between its lips as it is painted
  bar_at(holder, fn() { 0.0 }, fn() { top() + 0.5 }, w, h, fn(lips) {
    lips
    .clips(Is(true))
    .drawn_off(Painted(fn(laid) { (0.0, drift(laid, lips)) }))
    .cut_across(
      Painted(fn(laid) {
        match notch(laid, lips).2 {
          Some((l, rr)) => Some((l, rr))
          None => Some((0.0, 0.0))
        }
      }),
    )
    |> ignore
    bar_at(lips, fn() { -0.5 }, fn() { -1.0 }, fn() { w() + 1.0 }, fn() { h() + 4.0 }, fn(edge) {
      edge
      .radius(By(fn() { corner() + 0.5 }))
      .edge(By(fn() { (1.0, @sf.alpha(0xFFFFFFFFL, if @sf.theme().dark { 0.22 } else { 0.7 })) }))
      .notch(
        Painted(fn(laid) {
          let (cy, r, _) = notch(laid, edge)
          (cy + 0.5, r - 0.5, fillet + 0.5)
        }),
      )
      .alpha(Painted(fn(laid) { if notch(laid, edge).2 is Some(_) { 1.0 } else { 0.0 } }))
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The ball (ball_at's) under the places: where it is, how big and how faint as each frame is painted, laid out round
/// where it goes.
fn bar_ball_node(holder : @view.View) -> Unit {
  let x0 = fn() {
    bar_said.get() |> ignore
    bar.ball_x.to
  }
  let y0 = fn() {
    bar_said.get() |> ignore
    bar.ball_y.to
  }
  bar_at(holder, fn() { x0() - ball_size / 2.0 }, fn() { y0() - ball_size / 2.0 }, fn() { ball_size }, fn() { ball_size }, fn(ball) {
    let at = fn(laid : @view.Laid) { bar_ball_at(bar_moment(laid, ball)) }
    ball
    .alpha(
      Painted(fn(laid) {
        let b = at(laid)
        let solid = @ui.current().glass_solid()
        let lensed = if solid { 0.0 } else { dmin(1.0, b.held) }
        b.alpha * (1.0 - lensed)
      }),
    )
    .scale(Painted(fn(laid) { at(laid).sw / ball_size }))
    .drawn_off(
      Painted(fn(laid) {
        let b = at(laid)
        (b.cx - @signals.untracked(x0), b.cy - @signals.untracked(y0))
      }),
    )
    |> ignore
    ball.box(fn(g) {
      g
      .width(Is(Some(ball_size)))
      .height(Is(Some(ball_size)))
      .radius(Is(ball_size / 2.0))
      .glass(By(fn() { Some(@sf.glass_bar_ball().sharing()) }))
      .shadow(By(fn() { (4.0, 1.0, if @sf.theme().dark { 0x00000059L } else { 0x37352D33L }) }))
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The ball at moment `t` (ball_at's, by the moment).
fn bar_ball_at(t : Double) -> BallAt {
  let m = bar
  let held = m.held.at(t).0
  let (x, xv) = m.ball_x.at(t)
  let y = m.ball_y.at(t).0
  let scale = (1.0 + 0.06 * held) * m.ball_scale.at(t).0
  let v = if (m.ball_x.to - x).abs() < 0.5 { 0.0 } else { xv / 60.0 }
  let (stretch, lower) = @kit.speed_stretch(v)
  let bw = ball_size + stretch
  let bh = ball_size - lower
  let left = x - ball_size / 2.0 - (if v < 0.0 { stretch } else { 0.0 })
  { cx: left + bw / 2.0, cy: y, sw: bw * scale, sh: bh * scale, alpha: m.ball_alpha.at(t).0, held }
}

///|
/// The bar's places over the ball (place_at's): each its slot 48 high round its middle, its face lit as far as it is
/// as each frame is painted, laid out where the notch is going and drawn where the notch has it.
fn bar_places_node(
  holder : @view.View,
  src : Source,
  ws : () -> Workspace?,
  w : () -> Double,
  row_top : () -> Double,
  l : () -> BarLaid,
) -> Unit {
  let items = fn() { l().items }
  let slot = fn() { (w() - 2.0 * c0) / 3.0 }
  let bar_mid = fn() { row_top() + bar_track / 2.0 }
  holder.box(fn(row) {
    row.over(Is(true)) |> ignore
    // (none while a bar chosen lands: bar_swap_node draws them coming down)
    row.alpha(Painted(fn(laid) { if bar.swap_at(bar_moment(laid, row)) is Some(_) { 0.0 } else { 1.0 } })) |> ignore
    row.each(items, fn(k) { k }, fn(p, key) {
      let key = @signals.untracked(fn() { key.get() })
      let j = fn() { items().search(key).unwrap_or(0) }
      let x_at = fn(k : Double) { bar_centres(w(), k, items().length())[j()] - slot() / 2.0 }
      bar_at(p, fn() { x_at(bar.k_end()) }, fn() { bar_mid() - 24.0 }, slot, fn() { 48.0 }, fn(at) {
        // (placed where the notch has it as each frame is painted: drawn, pressed and read out there; nothing laid out
        // for it)
        at.offset(Painted(fn(laid) { (x_at(bar.k_at(bar_moment(laid, at))), bar_mid() - 24.0) })) |> ignore
        bar_face_node(at, src, ws, key, fn(t) { bar_tint_at("bar:" + key, t) })
      })
      |> ignore
    })
  })
  |> ignore
}

///|
/// How lit the place of tint `id` is at moment `t` (its glide's, bar_tell's; none told yet: not).
fn bar_tint_at(id : String, t : Double) -> Double {
  match bar.tints.get(id) {
    Some(g) => g.at(t).0
    None => 0.0
  }
}

///|
/// A place's face (place_face's) in `at`: its icon in the idle ink, the lit one over it as far as `lit_at` has it at
/// the moment it is painted, its dot at the icon's top right; read out as its label.
fn bar_face_node(
  at : @view.View,
  src : Source,
  ws : () -> Workspace?,
  key : String,
  lit_at : (Double) -> Double,
) -> Unit {
  // (the stations at a glance, in words, and whether one is in trouble: bar_glance)
  let glance = fn() {
    match ws() {
      Some(w) => bar_glance(src, w.id)
      None => ({ online: 0, dim: 0, failing: 0, working: 0, asleep: false, connecting: 0 }, "", false)
    }
  }
  let idle = fn() { if @sf.theme().dark { 0xD1D5DBFFL } else { 0x6B7280FFL } }
  let lit = fn() { if @sf.theme().dark { 0xFFFFFFFFL } else { 0x111827FFL } }
  let lit_now = fn(laid : @view.Laid) { lit_at(bar_moment(laid, at)) }
  at
  .lines_up(Is(Some(Middle)))
  .lies_along(Is(Middle))
  .says(
    By(fn() {
      let said = if key == "stations" { glance().1 } else { "" }
      let label = if said != "" { said } else { place_label(key) }
      Some(@view.said(Tab, label~))
    }),
  )
  |> ignore
  let icon = fn(parent : @view.View, color : () -> Int64) {
    if key == "stations" {
      @sf.station_glyph_node(
        parent,
        fn() { glance().0 },
        28.0,
        color,
        fn() { @sf.theme().p.red },
      )
      |> ignore
    } else {
      @sf.icon_node(parent, place_icon(key), 28.0, By(color)) |> ignore
    }
  }
  at.box(fn(face) {
    face.over(Is(true)).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
    face.alpha(Painted(fn(laid) { if lit_now(laid) < 0.999 { 1.0 } else { 0.0 } })) |> ignore
    icon(face, idle)
  })
  |> ignore
  at.box(fn(over) {
    over.over(Is(true)).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
    over.alpha(
      Painted(fn(laid) {
        let v = lit_now(laid)
        if v > 0.001 {
          v
        } else {
          0.0
        }
      }),
    )
    |> ignore
    icon(over, lit)
  })
  |> ignore
  // its dot: a station in trouble (red)
  at.box(fn(d) {
    d.over(Is(true)).lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
    d.show(
      fn() {
        key == "stations" && glance().2
      },
      fn(dot) {
        dot
        .width(Is(Some(7.0)))
        .height(Is(Some(7.0)))
        .radius(Is(3.5))
        .ground(By(fn() { @sf.theme().p.red }))
        .offset(Is((13.5, -12.5)))
        |> ignore
      },
    )
  })
  |> ignore
}

///|
/// The other bars, above this one, as the panel opens (Bar.kt rowsAlpha, rowsShift): each its places at rest across
/// its row, as faint and as low as the panel has them as each frame is painted; none while it is closed, nor while a
/// bar chosen lands (bar_swap_node draws them going).
fn bar_rows_node(
  holder : @view.View,
  src : Source,
  ws : () -> Workspace?,
  w : () -> Double,
  clip_top : () -> Double,
  l : () -> BarLaid,
) -> Unit {
  ignore(clip_top)
  let slot = fn() { (w() - 2.0 * c0) / 3.0 }
  holder.box(fn(rows) {
    rows.over(Is(true)) |> ignore
    rows.show(
      fn() {
        bar_said.get() |> ignore
        bar_ways_rested.get() |> ignore
        bar.mode.get() || bar.o.to > 0.001 || bar.o.end() > rows.logic_at()
      },
      fn(open) {
        open.over(Is(true)) |> ignore
        let look = fn(laid : @view.Laid) {
          let t = bar_moment(laid, open)
          let o = bar.o.at(t).0
          (if bar.swap_at(t) is Some(_) { 0.0 } else { rows_alpha(o) }, rows_shift(o, l().reach))
        }
        open.alpha(Painted(fn(laid) { look(laid).0 })).drawn_off(Painted(fn(laid) { (0.0, look(laid).1) })) |> ignore
        // (each other bar by its place among the bars, at its row: n from the top)
        let others = fn() { l().others.mapi(fn(n, i) { (n, i) }) }
        open.each(others, fn(ni) { ni.1 }, fn(r, ni) {
          r.over(Is(true)) |> ignore
          let i = @signals.untracked(fn() { ni.get().1 })
          let n = fn() { ni.get().0 }
          let set = fn() { l().sets.get(i).unwrap_or([]) }
          r.each(set, fn(k) { k }, fn(p, key) {
            let key = @signals.untracked(fn() { key.get() })
            let x = fn() { bar_centres(w(), 0.0, set().length())[set().search(key).unwrap_or(0)] - slot() / 2.0 }
            let y = fn() { over + n().to_double() * bar_row + bar_row / 2.0 - 24.0 }
            bar_at(p, x, y, slot, fn() { 48.0 }, fn(at) {
              bar_face_node(at, src, ws, key, fn(t) { bar_tint_at("row:" + key, t) })
            })
            |> ignore
          })
        })
      },
    )
  })
  |> ignore
}

///|
/// The ball in the finger: a lens of liquid glass over the places as it is held (as it grows), what is under its rim
/// bent; gone as it is let go. Where glass is solid there is nothing to bend: the ball alone. Laid out as the ball is,
/// drawn as it is held as each frame is painted.
fn bar_lens_node(holder : @view.View) -> Unit {
  let x0 = fn() {
    bar_said.get() |> ignore
    bar.ball_x.to
  }
  let y0 = fn() {
    bar_said.get() |> ignore
    bar.ball_y.to
  }
  holder.box(fn(b) {
    b.over(Is(true)) |> ignore
    b.show(
      fn() { !@ui.current().glass_solid() },
      fn(on) {
        on.over(Is(true)) |> ignore
        bar_at(on, fn() { x0() - ball_size / 2.0 }, fn() { y0() - ball_size / 2.0 }, fn() { ball_size }, fn() { ball_size }, fn(
          lens
        ) {
          let at = fn(laid : @view.Laid) { bar_ball_at(bar_moment(laid, lens)) }
          let held = fn(laid : @view.Laid) {
            let b = at(laid)
            if b.held > 0.01 && b.alpha > 0.0 {
              Some(b)
            } else {
              None
            }
          }
          lens
          .alpha(
            Painted(fn(laid) {
              match held(laid) {
                Some(b) => dmin(1.0, b.held) * b.alpha
                None => 0.0
              }
            }),
          )
          .scale(
            Painted(fn(laid) {
              match held(laid) {
                Some(b) => b.sw * (1.0 + lens_grow * b.held) / ball_size
                None => 1.0
              }
            }),
          )
          .drawn_off(
            Painted(fn(laid) {
              let b = at(laid)
              (b.cx - @signals.untracked(x0), b.cy - @signals.untracked(y0))
            }),
          )
          |> ignore
          lens.box(fn(g) {
            g
            .width(Is(Some(ball_size)))
            .height(Is(Some(ball_size)))
            .radius(Is(ball_size / 2.0))
            .glass(Is(Some(@sf.glass_lens())))
            |> ignore
          })
          |> ignore
        })
        |> ignore
      },
    )
  })
  |> ignore
}

///|
/// A bar being chosen (Bar.kt pick): the stack of bars slides down inside the closing glass, the chosen one into the
/// bar's place, what is not chosen cut off by the glass's edge. It starts as the rows and the bar were drawn (the rows'
/// fade and offset, each place as lit as it was) and comes to the bar's look as it lands, each frame as it is painted.
fn bar_swap_node(
  holder : @view.View,
  src : Source,
  ws : () -> Workspace?,
  w : () -> Double,
  row_top : () -> Double,
  clip_top : () -> Double,
  panel : () -> Double,
) -> Unit {
  let slot = fn() { (w() - 2.0 * c0) / 3.0 }
  let bar_mid = fn() { row_top() + bar_track / 2.0 }
  holder.box(fn(b) {
    b.over(Is(true)) |> ignore
    b.show(
      fn() {
        bar_said.get() |> ignore
        bar_ways_rested.get() |> ignore
        bar.swap_at(b.logic_at()) is Some(_)
      },
      fn(on) {
        on.over(Is(true)) |> ignore
        let s = bar.swap.unwrap()
        let now = fn(laid : @view.Laid, n : @view.View) {
          let t = bar_moment(laid, n)
          let o = bar.o.at(t).0
          let st = s.t(o)
          let (xs, y) = swap_at(s, o, w(), bar.k_at(t), row_top())
          (t, st, xs, y - (over + s.n.to_double() * bar_row + bar_row / 2.0), s.drop * (1.0 - st), s.alpha + (1.0 - s.alpha) * st)
        }
        let was = fn(id : String) { s.lit.get(id).unwrap_or(0.0) }
        let window = fn(f : (@view.View) -> Unit) {
          bar_at(on, fn() { 0.0 }, clip_top, w, fn() { panel() - clip_top() }, fn(win) {
            win.clips(Is(true)) |> ignore
            f(win)
          })
          |> ignore
        }
        // the rest, leaving: the rows not chosen and the bar as it was, sliding down
        window(fn(win) {
          let laid_others : Array[Int] = []
          for i in 0..<s.sets.length() {
            if i != s.cur {
              laid_others.push(i)
            }
          }
          for n, i in laid_others {
            if i != s.i {
              let set = s.sets[i]
              for j, key in set {
                let x = fn() { bar_centres(w(), 0.0, set.length())[j] - slot() / 2.0 }
                let y = fn() { over + n.to_double() * bar_row + bar_row / 2.0 - clip_top() - 24.0 }
                bar_at(win, x, y, slot, fn() { 48.0 }, fn(at) {
                  at
                  .alpha(Painted(fn(laid) { now(laid, at).5 }))
                  .drawn_off(Painted(fn(laid) { let n = now(laid, at); (0.0, n.3 + n.4) }))
                  |> ignore
                  bar_face_node(at, src, ws, key, fn(_) { was("row:" + key) })
                })
                |> ignore
              }
            }
          }
          let laid_items = s.sets[s.cur]
          for j, key in laid_items {
            let x = fn() { bar_centres(w(), bar.k_end(), laid_items.length())[j] - slot() / 2.0 }
            let y = fn() { bar_mid() - clip_top() - 24.0 }
            bar_at(win, x, y, slot, fn() { 48.0 }, fn(at) {
              at.drawn_off(Painted(fn(laid) { (0.0, now(laid, at).3) })) |> ignore
              bar_face_node(at, src, ws, key, fn(_) { was("bar:" + key) })
            })
            |> ignore
          }
        })
        // the chosen bar, inside the closing glass too: landed, as the bar's places are drawn, lit as it comes when it
        // is the place shown
        window(fn(win) {
          let items = s.sets[s.i]
          let active = match bar.told {
            Some({ active: Some(a), .. }) => a
            _ => ""
          }
          for j, key in items {
            let x = fn() { bar_centres(w(), bar.k_end(), items.length())[j] - slot() / 2.0 }
            let y = fn() { bar_mid() - clip_top() - 24.0 }
            bar_at(win, x, y, slot, fn() { 48.0 }, fn(at) {
              at
              .alpha(Painted(fn(laid) { now(laid, at).5 }))
              .drawn_off(
                Painted(fn(laid) {
                  let n = now(laid, at)
                  let laid = bar_centres(w(), bar.k_end(), items.length())[j]
                  let dx = if j < n.2.length() { n.2[j] - laid } else { 0.0 }
                  (dx, n.3 + n.4 + over + s.n.to_double() * bar_row + bar_row / 2.0 - bar_mid())
                }),
              )
              |> ignore
              let end = if active == key { 1.0 } else { 0.0 }
              bar_face_node(at, src, ws, key, fn(t) {
                let st = s.t(bar.o.at(t).0)
                let from = was("row:" + key)
                if st >= 1.0 {
                  end
                } else if st <= 0.0 {
                  from
                } else {
                  from + (end - from) * st
                }
              })
            })
            |> ignore
          }
        })
      },
    )
  })
  |> ignore
}
