// A bottom sheet made in the window's retained tree. Its content is made once, its size is its layout's, and its
// presence, drag and scrim are each told at the moment that caused them.

///|
/// A bottom sheet in `parent` while `open` says so. `body` makes its contents once: a scrolling body should shrink in
/// the room between its fixed head and foot. `tall` is a share of the window to fill (0: as tall as its contents),
/// capped at 94%; `tall_now`, when supplied, follows a changing share without replacing the sheet. With `fit`, a
/// positive share is a limit rather than a fixed height. An optional `sticky` keeps a
/// natural-height sheet at the cap after its contents first exceed it, and can be kept across presentation changes.
/// `grows` allows the 55% and 94%
/// detents; a fitted sheet can use them when its contents come to the limit. The system's bottom inset is included.
///
/// The caller owns its place in the window's stack. `raised`, `sinks`, `dims` and `covered` are the stack's as they
/// change; `extent` receives a node whose laid-out height is the sheet's requested visible height. A stack reads it
/// in `Painted` through `Laid::size`, or at an input event through `View::laid_size`. `dismiss` is called by the hand, Escape
/// or back. `within` takes Escape/back first when it returns true. `shown` and `gone` are called as the layer is made
/// and let go; the latter includes its way out. `look` may set the sheet's surface, corners and shadow; its second
/// argument is the scrim's progress. `label` names it in the semantics tree. `initial_focus`, read after `body` is
/// made, may name a descendant to focus; otherwise existing input focus is left in place. Closing returns the focus.
pub fn sheet_node(
  parent : @view.View,
  open : () -> Bool,
  dismiss : () -> Unit,
  body : (@view.View) -> Unit,
  tall? : Double = 0.0,
  fit? : Bool = false,
  grows? : Bool = false,
  draggable? : Bool = true,
  raised? : () -> Double = fn() { 0.0 },
  raised_painted? : (@view.Laid) -> Double = fn(_) { raised() },
  sinks? : () -> Double = fn() { 0.0 },
  dims? : () -> Bool = fn() { true },
  covered? : () -> Double = fn() { 0.0 },
  scrim? : () -> Int64 = fn() { @ui.tree_theme().scrim },
  extent? : (@view.View) -> Unit = fn(_) {  },
  shown? : () -> Unit = fn() {  },
  gone? : () -> Unit = fn() {  },
  look? : (@view.View, () -> Double) -> Unit = sheet_node_look,
  label? : () -> String = fn() { "" },
  initial_focus? : () -> @view.View? = fn() { None },
  within? : () -> Bool = fn() { false },
  under? : Double = 0.0,
  sticky? : @view.LayoutCap,
  tall_now? : () -> Double = fn() { tall },
) -> Unit {
  let surface : Ref[@view.View?] = Ref(None)
  let close : Ref[(Double) -> Double] = Ref(fn(_) { 0.0 })
  parent.show(open, leave_by=fn(_) {
    let h = match surface.val {
      Some(s) => {
        let target : @view.View = s
        dmax(0.0, target.laid_size().1 - under)
      }
      None => 0.0
    }
    (close.val)(h)
  }, fn(layer) {
    shown()
    layer.owns(gone) |> ignore
    // An old island has no contents to retain until it has actually built. Do not build one only for this exit.
    @ui.old_defer_unbuilt_on_exit(layer) |> ignore
    // A page owning this presenter may itself leave as a layout removes it. Resolve that removal at the change
    // that caused it, even if no frame comes between that change and the sheet's exit.
    layer.laid_before_causes()
    let opened = layer.cause_at()
    let still = @ui.current().still()
    let slide = @motion.Way::new(0.0)
    let fade = @motion.Way::new(0.0)
    fade.go(1.0, @motion.tween(sheet_scrim_ms, ease=Out), at=opened)
    // 0: the initial way, whose distance is the size this frame lays out; 1: a way started by an event.
    let slide_mode = @signals.signal(0)
    let size_mode = @signals.signal(0)
    let held = @signals.signal(0.0)
    let size_way = @motion.Way::new(0.0)
    let size_done : Ref[() -> Unit] = Ref(fn() {  })
    let base_h = Ref(0.0)
    let hand_y = Ref(0.0)
    let dragged = Ref(false)
    let tracking = Ref(false)
    let current = fn(h : Double, at : Double) {
      if still {
        (0.0, 0.0)
      } else if @signals.untracked(fn() { slide_mode.get() }) == 0 {
        let duration = @ui.move_ms(h)
        let (x, v) = @ui.move_path(h, 0.0, at - opened, duration)
        (x, v * 1000.0)
      } else {
        slide.at(at)
      }
    }
    let fade_shown = fn() {
      fade.said()
      if fade.goes_at(layer.logic_at()) {
        fade.value_at(layer.drawn_at())
      } else {
        fade.target()
      }
    }
    close.val = fn(h) {
      let at = layer.cause_at()
      let (x, v) = current(h, at)
      (size_done.val)()
      held.set(h)
      size_mode.set(1)
      slide.put(x)
      let down = dmax(h + @signals.untracked(raised), @signals.untracked(sinks))
      slide.go(down, @motion.move(), at~, velocity=v)
      slide_mode.set(1)
      fade.go(0.0, @motion.tween(sheet_scrim_ms, ease=Out), at~)
      dmax(slide.end(), fade.end()) - at
    }
    let live = fn() { !layer.leaving() }
    layer
    .over(Is(true))
    .modal(By(live))
    .hides(By(fn() { !live() }))
    .held_back_goes_on()
    .focusable(Is(true), keys=0, tab=false)
    .ground(By(fn() { if dims() { @ui.alpha(scrim(), fade_shown()) } else { 0L } }))
    .presses(Is(true))
    .on_drag(fn(d) { if d.kind == Down && @signals.untracked(live) { dismiss() } })
    .on_key(fn(k) {
      if k.code == @ui.key_escape && @signals.untracked(live) {
        if !within() { dismiss() }
        true
      } else {
        false
      }
    })
    .takes_back(fn() { if @signals.untracked(live) && !within() { dismiss() } })
    |> ignore
    // On return while leaving, continue from where the closing way has got to, at that cause's moment.
    layer.reacts(fn() { layer.leaving() }, fn(leaving) {
      if !leaving && @signals.untracked(fn() { slide_mode.get() }) == 1 {
        let at = layer.cause_at()
        size_mode.set(0)
        slide.go(0.0, @motion.move(), at~)
        fade.go(1.0, @motion.tween(sheet_scrim_ms, ease=Out), at~)
      }
    })
    layer.reacts(sinks, fn(down) {
      if layer.leaving() && down > slide.target() {
        slide.go(down, @motion.move(), at=layer.cause_at())
        layer.leaves_no_earlier_than(slide.end()) |> ignore
      }
    })
    // The empty extent is laid out with the requested visible height, in the same layout as the surface. It is
    // neither drawn nor hit; the presenter may read its size while painting another layer or handling an event.
    let requested : @view.View = layer.box(fn(v) { v.presses(Is(false)) |> ignore })
    extent(requested)
    let surface_node = layer.box(fn(sheet : @view.View) {
      surface.val = Some(sheet)
      sheet
      .shrink(Is(1.0))
      .clips(Is(true))
      .presses(Is(true))
      .says(By(fn() { Some(@view.said(Dialog, label=label())) }))
      .offset(Painted(fn(laid) {
        let h = dmax(0.0, laid.size(sheet).map(fn(s) { s.1 }).unwrap_or(0.0) - under)
        let y = if slide_mode.get() == 0 {
          let duration = @ui.move_ms(h)
          if !still && sheet.logic_at() < opened + duration {
            @ui.move_path(h, 0.0, laid.at() - opened, duration).0
          } else {
            0.0
          }
        } else {
          slide.said()
          if slide.goes_at(sheet.logic_at()) { slide.value_at(laid.at()) } else { slide.target() }
        }
        (0.0, y + under - raised_painted(laid))
      }))
      |> ignore
      look(sheet, fade_shown)
      let settle = fn(h : Double, to : Double, at : Double, velocity : Double, detents : Bool) {
        (size_done.val)()
        size_way.put(h)
        size_way.go(to, @motion.move(), at~, velocity~)
        size_mode.set(2)
        size_done.val = sheet.at_moment(size_way.end(), fn() {
          if detents { held.set(to); size_mode.set(3) } else { size_mode.set(0) }
        })
      }
      // The head can still contain buttons: only a vertical hold past the slop is taken from them.
      sheet.claims(fn(dx, dy) { draggable && dy.abs() > @ui.touch_slop() && dy.abs() >= dx.abs() }, from=fn(_, y) { y < 64.0 }) |> ignore
      sheet.on_drag(fn(d) {
        match d.kind {
          Down => {
            tracking.val = draggable && d.y < 64.0 && @signals.untracked(raised) <= 0.0
            if tracking.val {
              (size_done.val)()
              base_h.val = dmax(0.0, d.h - under)
              hand_y.val = d.wy
              dragged.val = false
            }
          }
          Moved if tracking.val => {
            let delta = d.wy - hand_y.val
            if delta.abs() > @ui.touch_slop() { dragged.val = true }
            let total = @signals.untracked(fn() { sheet.window().1 })
            let normal = requested.laid_size().1
            let tall = @signals.untracked(tall_now)
            let detents = grows && (!(fit && tall > 0.0) || normal >= dmin(tall, 0.94) * total - 1.0)
            let top = if detents { total * 0.94 } else { base_h.val }
            let least = if detents { 120.0 } else { 0.0 }
            let from = if @signals.untracked(fn() { size_mode.get() }) == 1 {
              @signals.untracked(fn() { held.get() })
            } else { base_h.val }
            let to = dmax(base_h.val - delta, least)
            if from <= top && to > top && @ui.pointing() is Finger {
              @ui.haptic(TextHandleMove)
            }
            let h = stretched(to, top, total - top)
            held.set(h)
            size_mode.set(1)
          }
          Up if tracking.val => {
            tracking.val = false
            let total = @signals.untracked(fn() { sheet.window().1 })
            let h = if @signals.untracked(fn() { size_mode.get() }) == 1 { @signals.untracked(fn() { held.get() }) } else { base_h.val }
            let normal = requested.laid_size().1
            let tall = @signals.untracked(tall_now)
            let detents = grows && (!(fit && tall > 0.0) || normal >= dmin(tall, 0.94) * total - 1.0)
            if dragged.val && (if detents { h / total < 0.3 } else { base_h.val - h > 80.0 }) {
              dismiss()
            } else {
              let to = if detents {
                if !dragged.val && d.oy < 30.0 {
                  if h > total * (0.55 + 0.94) / 2.0 { total * 0.55 } else { total * 0.94 }
                } else if (h - total * 0.55).abs() <= (h - total * 0.94).abs() {
                  total * 0.55
                } else { total * 0.94 }
              } else if fit && tall > 0.0 { normal } else { base_h.val }
              settle(h, to, d.at, -d.vy * 1000.0, detents)
            }
          }
          Off if tracking.val => {
            tracking.val = false
            size_mode.set(0)
          }
          _ => ()
        }
      }) |> ignore
      // Empty parts of the surface consume a press without making the dialog itself an actionable control.
      sheet.box(fn(shield) { shield.over(Is(true)).on_press(fn() {  }) |> ignore }) |> ignore
      // A tap on the grabber toggles detents. It lies under the caller's content, so controls there keep their taps.
      if grows && draggable {
        sheet.box(fn(grip : @view.View) {
          grip.over(Is(true)).height(Is(Some(30.0))) |> ignore
          grip.on_press(fn() {
            let h = dmax(0.0, sheet.laid_size().1 - under)
            let total = @signals.untracked(fn() { sheet.window().1 })
            let normal = requested.laid_size().1
            let tall = @signals.untracked(tall_now)
            if !(fit && tall > 0.0) || normal >= dmin(tall, 0.94) * total - 1.0 {
              let to = if h > total * (0.55 + 0.94) / 2.0 { total * 0.55 } else { total * 0.94 }
              settle(h, to, sheet.cause_at(), 0.0, true)
            }
          }) |> ignore
        }) |> ignore
      }
      body(sheet)
      sheet.box(fn(inset) { inset.height(By(fn() { Some(@ui.system_bars().bottom + under) })) |> ignore }) |> ignore
      // The sheet under another is shaded by that sheet's receding amount.
      sheet.box(fn(veil) {
        veil.over(Is(true)).ground(By(fn() { @ui.alpha(scrim(), covered()) })).presses(Is(false)) |> ignore
      }) |> ignore
    })
    // Both the natural request and the current detent are resolved here, before either is painted. In particular a
    // fitted sheet whose contents become short no longer uses a detent. No measured size is fed back into a binding.
    layer.layout_box(By(fn() {
      let mode = size_mode.get()
      let current_h = if mode == 2 {
        size_way.said()
        if size_way.goes_at(layer.logic_at()) {
          layer.drawn_at() |> ignore
          size_way.value_at(layer.logic_at())
        } else { size_way.target() }
      } else { held.get() }
      (mode, current_h, layer.window().1, tall_now())
    }), fn(l, state) {
      let (mode, current_h, wh, tall) = state
      let cap = dmax(0.0, dmin(if fit && tall > 0.0 { tall } else { 0.94 }, 0.94) * wh)
      let wanted = dmax(0.0, l.measure(surface_node, l.width).1 - under)
      let normal = if tall > 0.0 && !fit {
        dmin(tall * wh, cap)
      } else if tall <= 0.0 {
        match sticky {
          Some(memory) => l.sticky_cap(memory, wanted, cap)
          None => dmin(wanted, cap)
        }
      } else { dmin(wanted, cap) }
      let eligible = grows && (!(fit && tall > 0.0) || normal >= cap - 1.0)
      let actual = if mode == 1 || ((mode == 2 || mode == 3) && eligible) { current_h } else { normal }
      l.measure(requested, 0.0, height=normal) |> ignore
      l.place(requested, 0.0, 0.0)
      l.measure(surface_node, l.width, height=dmax(0.0, actual) + under) |> ignore
      l.place(surface_node, 0.0, l.height - dmax(0.0, actual) - under)
    }) |> ignore
    match initial_focus() {
      Some(target) => layer.focus_opens(target) |> ignore
      None => layer.leaves_typing().focus_returns() |> ignore
    }
    layer.owns(fn() { (size_done.val)() }) |> ignore
  })
}

///|
/// The kit's default sheet surface; an app may supply its own look.
fn sheet_node_look(sheet : @view.View, _scrim : () -> Double) -> Unit {
  sheet
  .corners(Is(Some((26.0, 26.0, 0.0, 0.0))))
  .ground(By(fn() { @ui.tree_theme().surface }))
  .shadow(By(fn() { (24.0, 0.0, @ui.tree_theme().shadow) }))
  |> ignore
}
