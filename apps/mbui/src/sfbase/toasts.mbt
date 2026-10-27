// What a write said (toast_later, act.mbt), shown: mbui's toast (@kit.toaster) in the library's look (@sf.toast_look),
// one host for every frame, where the frame puts it (its `bottom`).

///|
/// What a write said, mbui's toast (@kit.toaster) in the library's look (@sf.toast_look: what an unconfirmed write did
/// said as not known), 2.6 s (paused while the pointer is on it), coming in and going out; one said again is a new
/// one; its action (an archive's 撤销) its button, pressed done and the toast gone. `bottom`: how far over the window's
/// foot, the frame's to say; or `top` (0 or more), how far under its top, dropping in from over it (@sf.toast_look).
pub fn toasts(c : @ui.Ctx, bottom : Double, top? : Double = -1.0) -> Unit {
  let action = if app.toast != "" { app.toast_action } else { "" }
  let duration = if action != "" { @sf.toast_action_ms } else { @sf.toast_ms }
  // its action's button the toaster's (the focus on it holds the toast)
  let action_id = c.id("toast/t\{app.toast_n}/action")
  let said = if app.toast != "" { [@kit.toast("t\{app.toast_n}", @sf.toast_said(app.toast))] } else { [] }
  let mut pressed = false
  let enter = if top >= 0.0 { @sf.toast_drop_spring } else { @motion.tween(@kit.presence_in_ms, ease=Out) }
  let r = @kit.toaster(c, "toast", said, duration~, bottom~, top~, enter~, look=fn(c, s, _action, _close) {
    let live = s.toast.id == "t\{app.toast_n}"
    if @sf.toast_look(c, s, action=if live { action } else { "" }, action_id~) {
      pressed = true
    }
  })
  // pressed: done, and the toast goes
  if pressed {
    let run = app.toast_run
    app.toast = ""
    app.toast_action = ""
    app.toast_run = fn() {  }
    run()
  } else if app.toast != "" && r.open.is_empty() {
    app.toast = ""
  }
}
