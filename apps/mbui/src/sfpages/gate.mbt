// Signed out (the web's cloud/gate.tsx SignInPage; SignIn.kt SignInScreen), in the box the frame gives it (inside the
// system's bars): the illustration, what still.fail is for, and 登录或注册.

///|
/// The sign-in button's width at most on a desktop, as the desktop app's.
let sign_in_desk_w : Double = 300.0

///|
/// On a phone or a tablet: across a phone's page less its sides; no wider than this on a larger one.
let sign_in_touch_w : Double = 420.0

///|
/// The page: the picture, the words (none on a desktop), the button.
pub fn sign_in_page(c : @ui.Ctx, src : Source) -> Unit {
  let t = @sf.theme()
  let busy = (src.signing_in)()
  // a desktop's (the screen's kind, never the hand): the picture and 登录或注册 alone, no words around them (asked
  // for, 2026-10-23)
  let bare = !@sf.touch_system()
  c.box(
    w=Fill(1.0),
    h=Fill(1.0),
    padx=30.0,
    pady=40.0,
    gap=12.0,
    align=ACenter,
    justify=JCenter,
    fn() {
      @sf.drawable(
        c,
        if t.dark {
          "illus_sign_in_dark"
        } else {
          "illus_sign_in"
        },
        dmin(300.0, c.width - 60.0),
      )
      |> ignore
      if !bare {
        c.box(pt=10.0, fn() {
          c.text(
            @sf.t("android-settings.signIn.title"),
            size=28.0,
            weight=700,
            color=t.p.text,
            wrap=false,
          )
          |> ignore
        })
        |> ignore
        c.text(
          @sf.t("android-settings.signIn.note"),
          size=15.0,
          color=t.p.muted,
          center=true,
          w=Fill(1.0),
          line=21.0,
        )
        |> ignore
      }
      c.box(h=Px(6.0), fn() {  }) |> ignore
      let id = c.id("sign-in")
      if c.clicked(id) && !busy {
        (src.sign_in)()
      }
      c.box(
        dir=Row,
        w=Fill(1.0),
        // a desktop's no wider than the desktop app's (web cloud/gate.css.ts `ways`), a phone's across it
        max_w=if bare { sign_in_desk_w } else { sign_in_touch_w },
        h=Px(50.0),
        radius=25.0,
        bg=t.p.text,
        align=ACenter,
        justify=JCenter,
        id~,
        fn() {
          c.text(
            if busy {
              @sf.t("common.opening")
            } else {
              @sf.t("android-settings.signIn.google")
            },
            size=16.0,
            weight=600,
            color=t.p.bg,
            wrap=false,
          )
          |> ignore
          // SignIn.kt: clip(CircleShape).clickable
          if !busy {
            @motion.ripple(c, id, 25.0)
          }
        },
      )
      |> ignore
      if !bare {
        c.text(
          @sf.t("android-settings.signIn.many"),
          size=12.0,
          color=t.p.muted,
          wrap=false,
        )
        |> ignore
      }
    },
  )
  |> ignore
}
