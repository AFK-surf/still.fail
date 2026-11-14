// What a write said (toast_later, act.mbt), shown: mbui's toast as the window's tree's nodes (@kit.toaster_node) in the
// library's look (@sf.toast_look_node), one host for every frame, where the frame puts it (its `bottom`).

///|
/// What a write said as the window's tree's nodes (made once: @kit.toaster_node in the library's look,
/// @sf.toast_look_node): the toast said now (toast_later), each saying its own toast (its id its saying's), what its
/// action does its own (run as its button is pressed, once, and the toast goes), gone by itself (its time out, swiped
/// away) only if it is still the one said; `bottom` over what the system's bars leave of the window's foot, the frame's to say as it changes. The node.
pub fn toasts_node(parent : @view.View, bottom : () -> Double) -> @view.View {
  // (the saying a toast is of, by its id)
  let of = fn(id : String) -> ToastSaid? {
    let s = app.toast.untracked()
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
