// Signed out (the web's cloud/gate.tsx SignInPage; SignIn.kt SignInScreen), in the box the frame gives it (inside the
// system's bars): the illustration, what still.fail is for, 登录或注册, that several can be signed in, and under the
// button where signing in stands: out in the browser, or why it failed.

///|
/// The page (the library's way in): the picture, what still.fail is for, 登录或注册, that several can be signed in; its
/// button saying what is under way (正在打开, 正在登录; 重新打开登录页 while the browser has the page: it may have been
/// closed) and the line under it what the browser is waiting for, or why the last sign-in failed (the core's words,
/// 登录失败 where it had none).
pub fn sign_in_page(c : @ui.Ctx, src : Source) -> Unit {
  let t = @sf.theme()
  let step = (src.sign_in_step)()
  let label = match step {
    Opening => @sf.t("common.opening")
    Verifying => @sf.t("android-settings.signIn.signingIn")
    InBrowser => @sf.t("android-settings.signIn.reopen")
    Idle | Failed(_) => @sf.t("android-settings.signIn.google")
  }
  let (said, bad) = match step {
    InBrowser => (@sf.t("android-settings.signIn.waiting"), false)
    Failed("") => (@sf.t("core-logic.accounts.login.failed"), true)
    Failed(why) => (why, true)
    Idle | Opening | Verifying => ("", false)
  }
  if @sf.way_in(
      c,
      if t.dark {
        "illus_sign_in_dark"
      } else {
        "illus_sign_in"
      },
      @sf.t("android-settings.signIn.title"),
      @sf.t("android-settings.signIn.note"),
      label,
      @sf.t("android-settings.signIn.many"),
      busy=step is (Opening | Verifying),
      said~,
      bad~,
    ) {
    (src.sign_in)()
  }
}

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
