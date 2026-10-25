// Signed out (the web's cloud/gate.tsx SignInPage; SignIn.kt SignInScreen), in the box the frame gives it (inside the
// system's bars): the illustration, what still.fail is for, and 登录或注册.

///|
/// The page (the library's way in): the picture, what still.fail is for, 登录或注册, that several can be signed in.
pub fn sign_in_page(c : @ui.Ctx, src : Source) -> Unit {
  let t = @sf.theme()
  let busy = (src.signing_in)()
  if @sf.way_in(
      c,
      if t.dark {
        "illus_sign_in_dark"
      } else {
        "illus_sign_in"
      },
      @sf.t("android-settings.signIn.title"),
      @sf.t("android-settings.signIn.note"),
      if busy {
        @sf.t("common.opening")
      } else {
        @sf.t("android-settings.signIn.google")
      },
      @sf.t("android-settings.signIn.many"),
      busy~,
    ) {
    (src.sign_in)()
  }
}
