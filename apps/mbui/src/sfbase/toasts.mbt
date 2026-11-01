// What a write said (toast_later, act.mbt), shown: mbui's toast (@kit.toaster) in the library's look (@sf.toast_look),
// one host for every frame, where the frame puts it (its `bottom`).

///|
/// What a write said, mbui's toast (@kit.toaster) in the library's look (@sf.toast_look: what an unconfirmed write did
/// said as not known), 2.6 s (paused while the pointer is on it), coming in and going out; one said again is a new
/// one; its action (an archive's 撤销) its button, pressed done and the toast gone. `bottom`: how far over the window's
/// foot, the frame's to say.
pub fn toasts(c : @ui.Ctx, bottom : Double) -> Unit {
  let said = app.toast.get()
  let action = if said.words != "" { said.action } else { "" }
  let duration = if action != "" { @sf.toast_action_ms } else { @sf.toast_ms }
  // its action's button the toaster's (the focus on it holds the toast)
  let action_id = c.id("toast/t\{said.n}/action")
  let shown = if said.words != "" { [@kit.toast("t\{said.n}", @sf.toast_said(said.words))] } else { [] }
  let mut pressed = false
  let r = @kit.toaster(c, "toast", shown, duration~, bottom~, look=fn(c, s, _action, _close) {
    let live = s.toast.id == "t\{said.n}"
    if @sf.toast_look(c, s, action=if live { action } else { "" }, action_id~) {
      pressed = true
    }
  })
  // pressed: done (what this saying's button does), and the toast goes
  // (gone: none said, which saying was last kept, the next a new one)
  if pressed {
    app.toast.set({ ..toast_none, n: said.n })
    (said.run)()
  } else if said.words != "" && r.open.is_empty() {
    app.toast.set({ ..toast_none, n: said.n })
  }
}

///|
/// What a write said as the window's tree's nodes (toasts's, made once: @kit.toaster_node in the library's look,
/// @sf.toast_look_node): the toast said now (toast_later), each saying its own toast (its id its saying's), what its
/// action does its own (run as its button is pressed, once, and the toast goes), gone by itself (its time out, swiped
/// away) only if it is still the one said; `bottom` over the window's foot, the frame's to say as it changes. The node.
pub fn toasts_node(parent : @view.View, bottom : () -> Double) -> @view.View {
  // (the saying a toast is of, by its id)
  let of = fn(id : String) -> ToastSaid? {
    let s = @signals.untracked(fn() { app.toast.get() })
    if s.words != "" && "t\{s.n}" == id {
      Some(s)
    } else {
      None
    }
  }
  @kit.toaster_node(
    parent,
    fn() {
      let s = app.toast.get()
      if s.words == "" {
        []
      } else {
        [@kit.toast("t\{s.n}", @sf.toast_said(s.words), action=s.action)]
      }
    },
    fn(to) { if to.action != "" { @sf.toast_action_ms } else { @sf.toast_ms } },
    bottom,
    fn(b, s) { @sf.toast_look_node(b, s) },
    fn(id) {
      // (pressed: what that saying's button does, once, and it goes; another said since not touched)
      match of(id) {
        Some(s) => {
          app.toast.set({ ..toast_none, n: s.n })
          (s.run)()
        }
        None => ()
      }
    },
    fn(id) {
      match of(id) {
        Some(s) => app.toast.set({ ..toast_none, n: s.n })
        None => ()
      }
    },
    w=@sf.toast_max,
  )
}
