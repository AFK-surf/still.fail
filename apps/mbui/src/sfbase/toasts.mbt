// What a write said (toast_later, act.mbt), shown: mbui's toast (@kit.toaster) in the library's look (@sf.toast_look),
// one host for every frame, where the frame puts it (its `bottom`).

///|
/// What a write said, mbui's toast (@kit.toaster) in the library's look (@sf.toast_look: what an unconfirmed write did
/// said as not known), 2.6 s (paused while the pointer is on it), coming in and going out; one said again is a new
/// one; its action (an archive's 撤销) its button, pressed done and the toast gone. `bottom`: how far over the window's
/// foot, the frame's to say.
pub fn toasts(c : @ui.Ctx, bottom : Double) -> Unit {
  let action = if app.toast.get() != "" { app.toast_action.get() } else { "" }
  let duration = if action != "" { @sf.toast_action_ms } else { @sf.toast_ms }
  // its action's button the toaster's (the focus on it holds the toast)
  let action_id = c.id("toast/t\{app.toast_n.get()}/action")
  let said = if app.toast.get() != "" { [@kit.toast("t\{app.toast_n.get()}", @sf.toast_said(app.toast.get()))] } else { [] }
  let mut pressed = false
  let r = @kit.toaster(c, "toast", said, duration~, bottom~, look=fn(c, s, _action, _close) {
    let live = s.toast.id == "t\{app.toast_n.get()}"
    if @sf.toast_look(c, s, action=if live { action } else { "" }, action_id~) {
      pressed = true
    }
  })
  // pressed: done, and the toast goes
  if pressed {
    let run = app.toast_run
    app.toast.set("")
    app.toast_action.set("")
    app.toast_run = fn() {  }
    run()
  } else if app.toast.get() != "" && r.open.is_empty() {
    app.toast.set("")
  }
}
