// A hover card hosted by a retained control. Its content remains the independent card it was; its trigger,
// delay, entrance and lifetime belong to that control, not to a rebuilt page.

///|
/// A card under `trigger`, with hover's timing and layout. Returns what opens it from a finger's hold (or tap,
/// for a control with no other action). Its body may open another panel and keep this card while that is drawn.
pub fn hover_node(trigger : @view.View, key : String, body : (@ui.Ctx) -> Unit,
  tile? : Bool = false, padded? : Bool = true) -> () -> Unit {
  trigger.points(Is(true)) |> ignore
  let open = @signals.signal(false, same=fn(a, b) { a == b })
  let held = @signals.signal(false, same=fn(a, b) { a == b })
  let card_on : Ref[@view.View?] = Ref(None)
  let due : Ref[() -> Unit] = Ref(fn() { })
  let close = fn() { (due.val)(); held.set(false); open.set(false) }
  trigger.reacts(fn() {
    @sf.pointer_rests() && !@ui.pointer_pressed() &&
      (trigger.pointed() || card_on.val.map(fn(card) {
        pointer_over(card) || @ui.old_overlay_in_use(card)
      }).unwrap_or(false) || hover_held(key))
  }, fn(on) {
    (due.val)()
    guard !@signals.untracked(fn() { held.get() }) else { return }
    guard on || @signals.untracked(fn() { open.get() }) else { return }
    due.val = trigger.at_moment(trigger.cause_at() + (if on { hover_open_ms } else { hover_close_ms }),
      fn() { open.set(on) })
  })
  trigger.owns(fn() { (due.val)() }) |> ignore
  // (the window's layer made as it first opens, not for each that could: popup_root_when)
  @sf.popup_root_when(trigger, fn() { open.get() }, fn(root) {
  root.show(fn() { open.get() }, fn(layer) {
    let look = @motion.presence_node(layer, initial=false, enter=hover_in, exit=hover_out)
    let live = fn() { !layer.leaving() }
    layer.over(Is(true)).hides(By(fn() { layer.leaving() }))
    .modal(By(fn() { held.get() && live() })).presses(By(live))
    .takes(fn(w, h, _) { if held.get() { [(0.0, 0.0, w, h)] } else { [] } })
    .on_drag(fn(d) { if d.kind == Down && @signals.untracked(fn() { held.get() && live() }) { close() } })
    .on_key(fn(k) { if k.code == @ui.key_escape && @signals.untracked(live) { close(); true } else { false } })
    .takes_back(close).held_back_goes_on() |> ignore
    layer.box(fn(card) {
      let card_width : @signals.Signal[Double?] = @signals.signal(None, same=fn(a, b) { a == b })
      card.beside(trigger.id(), side=Bottom, along=Start, offset=hover_offset, padding=8.0)
      .alpha(By(fn() { look().alpha })).scale(By(fn() { look().sx }), about=FromBeside).presses(By(live)) |> ignore
      @ui.old(card, natural=true, fits?=if tile { Some((agent_card_most, card_width)) } else { None }, fn(c) {
        let b = c.box(id=c.id(key + "/panel"), style=if tile { hover_tile } else { hover_card }, fn() {
          @sf.small_panel(c, w=Fill(1.0), fn() {
            c.box(style=if padded { hover_inner } else { hover_bare }, fn() {
              let before = hover_now.val
              hover_now.val = Some((key, c.id(key + "/panel")))
              body(c)
              hover_now.val = before
            }) |> ignore
          }) |> ignore
        })
        c.look_by(b, fn() {
          { alpha: 1.0, dx: 0.0, dy: 0.0, sx: 1.0, sy: 1.0, ox: 0.5, oy: 0.5,
            rot: 0.0, circle: 0.0, words: look().words }
        })
      })
      .width(if tile { By(fn() { card_width.get() }) } else { Is(Some(320.0)) })
      |> fn(island) { card_on.val = Some(island) }
      card.owns(fn() { card_on.val = None }) |> ignore
    }) |> ignore
    layer.focus_returns() |> ignore
  }, leave=hover_out_ms)
  })
  fn() { (due.val)(); held.set(true); open.set(true) }
}
