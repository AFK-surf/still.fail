// What the connects' pages and a run's page share of the settings: a value by the first of its names the core gives,
// and borrowing what a run uses asked first (`pick.borrow`). The connects' pages, a new one's dialog and a connect's
// Slack app are src/sfdesk's (connects.mbt, connect.mbt, new_connect.mbt, slack_app.mbt), one each in every frame.

///|
/// The first of `keys` that `v` has, else `or_else`.
pub fn first_text(v : Json?, keys : Array[String], or_else : String) -> String {
  for k in keys {
    match opt_text(v, k) {
      Some(x) => return x
      None => ()
    }
  }
  or_else
}

///|
/// What a run uses borrowed from another's (the core's `borrow`: its title, its lines, its action), asked first.
pub fn confirm_borrow(core : Core, station : String, of : String, b : Json?) -> Unit {
  confirm(text(b, "title"), join(strings(b, "lines"), "\n\n"), text(b, "action"), fn() {
    act(core, text(b, "action"), "pick.borrow", obj([("station", str(station)), ("of", str(of))]), done=tr("android-chat.run.borrowed"))
  })
}
