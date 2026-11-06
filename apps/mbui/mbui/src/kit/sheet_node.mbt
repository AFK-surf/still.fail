// A bottom sheet made in the window's retained tree. Its content is made once, its size is its layout's, and its
// presence, drag and scrim are each told at the moment that caused them.

///|
/// A bottom sheet in `parent` while `open` says so. `body` makes its contents once: a scrolling body should shrink in
/// the room between its fixed head and foot. `tall` is a share of the window to fill (0: as tall as its contents),
/// capped at 94%; `grows` allows the 55% and 94% detents. The system's bottom inset is included in its height.
///
/// The caller owns its place in the window's stack. `raised`, `sinks`, `dims` and `covered` are the stack's as they
/// change; `height` is told the laid-out height for an older sheet below it. `dismiss` is called by the hand, Escape
/// or back. `within` takes Escape/back first when it returns true. `shown` and `gone` are called as the layer is made
/// and let go; the latter includes its way out. `look` may set the sheet's surface, corners and shadow; its second
/// argument is the scrim's progress. `label` names it in the semantics tree.
pub fn sheet_node(
  parent : @view.View,
  open : () -> Bool,
  dismiss : () -> Unit,
  body : (@view.View) -> Unit,
  tall? : Double = 0.0,
  grows? : Bool = false,
  draggable? : Bool = true,
  raised? : () -> Double = fn() { 0.0 },
  sinks? : () -> Double = fn() { 0.0 },
  dims? : () -> Bool = fn() { true },
  covered? : () -> Double = fn() { 0.0 },
  scrim? : () -> Int64 = fn() { @ui.tree_theme().scrim },
  height? : (Double) -> Unit = fn(_) {  },
  shown? : () -> Unit = fn() {  },
  gone? : () -> Unit = fn() {  },
  look? : (@view.View, () -> Double) -> Unit = sheet_node_look,
  label? : () -> String = fn() { "" },
  within? : () -> Bool = fn() { false },
  under? : Double = 0.0,
) -> Unit {
  let close : Ref[(@view.View) -> Double] = Ref(fn(_) { 0.0 })
  parent.show(open, leave_by=fn(layer) { (close.val)(layer) }, fn(layer) {
    shown()
    layer.owns(gone) |> ignore
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
    let normal_h = Ref(0.0)
    let reported_h = Ref(-1.0)
    let hand_y = Ref(0.0)
    let dragged = Ref(false)
    let tracking = Ref(false)
    let surface : Ref[@view.View?] = Ref(None)
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
    close.val = fn(_) {
      let at = layer.cause_at()
      let h = match surface.val {
        Some(s) => dmax(0.0, s.laid_size().1 - under)
        None => 0.0
      }
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
    .focus_opens(layer)
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
    layer.box(fn(spacer) { spacer.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore }) |> ignore
    layer.box(fn(sheet) {
      surface.val = Some(sheet)
      let max_h = fn() { dmax(0.0, sheet.window().1 * 0.94) }
      sheet
      // Content is capped at the top detent. While held or returning, allow its rubber-band extension above it.
      .max_height(By(fn() { Some((if size_mode.get() == 0 { max_h() } else { sheet.window().1 }) + under) }))
      .height(By(fn() {
        match size_mode.get() {
          1 => Some(held.get() + under)
          2 => {
            size_way.said()
            if size_way.goes_at(sheet.logic_at()) {
              sheet.drawn_at() |> ignore
              Some(size_way.value_at(sheet.logic_at()) + under)
            } else {
              Some(size_way.target() + under)
            }
          }
          _ => if tall > 0.0 { Some(dmin(max_h(), sheet.window().1 * tall) + under) } else { None }
        }
      }))
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
        (0.0, y + under - raised())
      }))
      |> ignore
      look(sheet, fade_shown)
      sheet.reacts(fn() { (size_mode.get(), sheet.laid_size_told(), sheet.window().1) }, fn(state) {
        let (mode, size, wh) = state
        if tall > 0.0 {
          normal_h.val = dmin(wh * 0.94, wh * tall)
        } else if mode == 0 {
          match size { Some((_, h)) => normal_h.val = dmax(0.0, h - under); None => () }
        }
        if normal_h.val != reported_h.val && size is Some(_) {
          reported_h.val = normal_h.val
          height(normal_h.val)
        }
      })
      let settle = fn(h : Double, to : Double, at : Double, velocity : Double) {
        (size_done.val)()
        size_way.put(h)
        size_way.go(to, @motion.move(), at~, velocity~)
        size_mode.set(2)
        size_done.val = sheet.at_moment(size_way.end(), fn() {
          if grows { held.set(to); size_mode.set(1) } else { size_mode.set(0) }
        })
      }
      // The head can still contain buttons: only a vertical hold past the slop is taken from them.
      sheet.claims(fn(dx, dy) { draggable && dy.abs() > @ui.touch_slop() && dy.abs() >= dx.abs() }, from=fn(_, y) { y < 64.0 })
      .on_drag(fn(d) {
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
            let top = if grows { total * 0.94 } else { base_h.val }
            let least = if grows { 120.0 } else { 0.0 }
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
            if dragged.val && (if grows { h / total < 0.3 } else { base_h.val - h > 80.0 }) {
              dismiss()
            } else {
              let to = if grows {
                if !dragged.val && d.oy < 30.0 {
                  if h > total * (0.55 + 0.94) / 2.0 { total * 0.55 } else { total * 0.94 }
                } else if (h - total * 0.55).abs() <= (h - total * 0.94).abs() {
                  total * 0.55
                } else { total * 0.94 }
              } else { base_h.val }
              settle(h, to, d.at, -d.vy * 1000.0)
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
        sheet.box(fn(grip) {
          grip.over(Is(true)).height(Is(Some(30.0))).on_press(fn() {
            let h = dmax(0.0, sheet.laid_size().1 - under)
            let total = @signals.untracked(fn() { sheet.window().1 })
            let to = if h > total * (0.55 + 0.94) / 2.0 { total * 0.55 } else { total * 0.94 }
            settle(h, to, sheet.cause_at(), 0.0)
          }) |> ignore
        }) |> ignore
      }
      body(sheet)
      sheet.box(fn(inset) { inset.height(By(fn() { Some(@ui.system_bars().bottom + under) })) |> ignore }) |> ignore
      // The sheet under another is shaded by that sheet's receding amount.
      sheet.box(fn(veil) {
        veil.over(Is(true)).ground(By(fn() { @ui.alpha(scrim(), covered()) })).presses(Is(false)) |> ignore
      }) |> ignore
    }) |> ignore
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
