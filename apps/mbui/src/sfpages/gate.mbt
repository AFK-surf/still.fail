// Signed out (the web's cloud/gate.tsx SignInPage), in the box the frame gives it (inside the
// system's bars): the illustration, what still.fail is for, 登录或注册, that several can be signed in, and under the
// button where signing in stands: out in the browser, or why it failed.

///|
/// The page as nodes of the window's tree in `parent` (sign_in_page's, made once): the way in's (@sf.way_in_node), its
/// button's words, whether it is at work and what is said under it as the core's sign-in step says them as it changes.
/// The node.
pub fn sign_in_node(parent : @view.View, src : Source) -> @view.View {
  let step = fn() { (src.sign_in_step)() }
  @sf.way_in_node(
    parent,
    fn() { if @sf.theme().dark { "illus_sign_in_dark" } else { "illus_sign_in" } },
    fn() { @sf.t("android-settings.signIn.title") },
    fn() { @sf.t("android-settings.signIn.note") },
    fn() {
      match step() {
        Opening => @sf.t("common.opening")
        Verifying => @sf.t("android-settings.signIn.signingIn")
        InBrowser => @sf.t("android-settings.signIn.reopen")
        Idle | Failed(_) => @sf.t("android-settings.signIn.google")
      }
    },
    fn() { @sf.t("android-settings.signIn.many") },
    fn() { (src.sign_in)() },
    busy=fn() { step() is (Opening | Verifying) },
    said=fn() {
      match step() {
        InBrowser => (@sf.t("android-settings.signIn.waiting"), false)
        Failed("") => (@sf.t("core-logic.accounts.login.failed"), true)
        Failed(why) => (why, true)
        Idle | Opening | Verifying => ("", false)
      }
    },
  )
}
