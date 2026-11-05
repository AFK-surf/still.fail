// The composer's two round controls, with their old size, inks and response to readiness and the pointer.

///|
pub fn composer_send_node(parent : @view.View, ready : () -> Bool, starting : () -> Bool, send : () -> Unit, tips? : TipLayer) -> @view.View {
  parent.box(fn(v) {
    let hot = fn() { ready() && (v.pointed() || v.pressed()) }
    let able = EdgeWay::new(if @signals.untracked(ready) { 1.0 } else { 0.0 })
    let lit = EdgeWay::new(0.0)
    v.reacts(ready, fn(on) { able.go(v, if on { 1.0 } else { 0.0 }, dur_ms) })
    v.reacts(hot, fn(on) { lit.go(v, if on { 1.0 } else { 0.0 }, dur_ms) })
    v.width(By(fn() { Some(theme().round.side) })).height(By(fn() { Some(theme().round.side) }))
    .radius(By(fn() { theme().round.side / 2.0 })).lines_up(Is(Some(Middle))).lies_along(Is(Middle))
    .turned_off(By(fn() { !ready() })).focusable(By(ready))
    .says(By(fn() { Some(@view.said(Button, label=t("web-main.composer.send"))) }))
    .on_press(fn() { if ready() { send() } })
    .ground(By(fn() {
      let p = theme().p
      let on = mix(mix(p.text, 0.82, p.canvas), lit.shown(v), p.text)
      mix(on, able.shown(v), over(p.raised, alpha(p.text, 0.18)))
    })) |> ignore
    v.pick(starting, fn(p, busy) {
      if busy { spinner_node(p, size=theme().round.glyph) |> ignore } else {
        icon_node(p, "arrow-up", theme().round.glyph,
          By(fn() { mix(theme().p.canvas, able.shown(v), theme().p.raised) })) |> ignore
      }
    })
    match tips {
      Some(layer) => tip_node(layer, v, fn() { t("web-main.composer.send") }) |> ignore
      None => ()
    }
  })
}

///|
pub fn composer_attach_node(parent : @view.View, disabled : () -> Bool, open : (@view.View) -> Unit, tips? : TipLayer) -> @view.View {
  parent.box(fn(v) {
    let hot = fn() { !disabled() && (v.pointed() || v.pressed()) }
    v.width(By(fn() { Some(theme().round.side) })).height(By(fn() { Some(theme().round.side) }))
    .radius(By(fn() { theme().round.side / 2.0 })).lines_up(Is(Some(Middle))).lies_along(Is(Middle))
    .presses(By(fn() { !disabled() })).focusable(By(fn() { !disabled() }))
    .ground(By(fn() { if hot() { theme().p.hover } else { 0L } }))
    .says(By(fn() { Some(@view.said(Button, label=t("web-main.composer.attach"))) }))
    .on_press(fn() { if !disabled() { open(v) } }) |> ignore
    icon_node(v, "plus", 18.0, By(fn() {
      if disabled() { alpha(theme().p.text, 0.4) } else if hot() { theme().p.text } else { theme().p.muted }
    })) |> ignore
    match tips {
      Some(layer) => tip_node(layer, v, fn() { if disabled() { "" } else { t("web-main.composer.attach") } }) |> ignore
      None => ()
    }
  })
}
