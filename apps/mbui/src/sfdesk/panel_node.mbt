///|
fn side_beside_node(
  v : @view.View,
  key : String,
  open : () -> Bool,
  width : () -> Double,
  page : (@view.View, () -> Double) -> Unit,
  panel : (@view.View, () -> Bool) -> Unit,
) -> Unit {
  let whole = fn() {
    if width() < side_both_least { dmin(side_over_w, width()) } else { side_width(width()) }
  }
  let way = @motion.Way::new(1.0)
  let from = Ref(0.0)
  let was : Ref[Bool?] = Ref(None)
  let target = fn() { if open() { whole() } else { 0.0 } }
  let column = fn() {
    way.said()
    let k = if way.goes_at(v.logic_at()) { way.value_at(v.drawn_at()) } else { 1.0 }
    from.val + (target() - from.val) * k
  }
  v.reacts(open, fn(now) {
    let at = v.cause_at()
    if was.val is Some(old) && old != now && panel_own.asked.get() == key && !@ui.reduced_motion() {
      let old_target = if old { whole() } else { 0.0 }
      from.val = from.val + (old_target - from.val) * way.value_at(at)
      way.put(0.0)
      way.go(1.0, @motion.move(over=(target() - from.val).abs()), at~)
      panel_own.asked.set("")
    }
    was.val = Some(now)
    panel_own.was[key] = now
  })
  v.row(Is(true)).grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  let over = fn() { width() < side_both_least }
  v.box(fn(p) {
    let left = fn() { if over() { width() } else { width() - column() } }
    p.width(By(fn() { Some(left()) })).shrink(Is(0.0)) |> ignore
    page(p, left)
  }) |> ignore
  v.show(fn() { open() || column() > 0.0 }, fn(col) {
    col.width(By(fn() { Some(column()) })).shrink(Is(0.0))
    .over(By(over)).offset(By(fn() { (if over() { width() - column() } else { 0.0 }, 0.0) }))
    .clips(By(fn() { !over() && column() < whole() })) |> ignore
    col.box(fn(p) {
      p.width(By(fn() { Some(whole()) })).grow(Is(1.0)).shrink(Is(0.0)) |> ignore
      p.shadow(By(fn() { if over() { (25.0, 20.0, @sf.theme().p.shadow) } else { (0.0, 0.0, 0L) } })) |> ignore
      panel(p, over)
    }) |> ignore
    col.owns(fn() { if !open() { side_left(key) } }) |> ignore
  })
}
