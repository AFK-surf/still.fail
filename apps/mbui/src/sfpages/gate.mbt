// Signed out (the web's cloud/gate.tsx SignInPage; SignIn.kt SignInScreen), in the box the frame gives it (inside the
// system's bars): the illustration, what still.fail is for, and 登录或注册.

///|
/// The sign-in button's width at most on a desktop, as the desktop app's.
let sign_in_desk_w : Double = 300.0

///|
/// On a phone or a tablet: across a phone's page less its sides; no wider than this on a larger one.
let sign_in_touch_w : Double = 420.0

///|
/// The button: 50 high, a pill (SignIn.kt: height(50.dp), CircleShape).
let sign_in_button_h : Double = 50.0

///|
/// The picture: as wide as the button at most (SignIn.kt: widthIn(max = 300.dp)), never past the page's sides.
let sign_in_picture_w : Double = 300.0

///|
/// The page: its picture, words and button in a column in its middle, 28 in from its sides and 40 from its top and
/// foot, 12 apart (SignIn.kt: padding(horizontal = 30.dp, vertical = 40.dp), spacedBy(12.dp)).
// kept across runs: a value (no field of it changes)
let sign_in_box : @ui.Style = @ui.css("w=Full h=Full px=S7 py=S10 gap=S3 align=ACenter justify=JCenter")

///|
/// What the page leaves either side of the picture (its sides: sign_in_box's px).
let sign_in_side : Double = 28.0

///|
/// The title 10 under the picture, a large one, bold (SignIn.kt: 28.sp, Bold).
// kept across runs: a value (no field of it changes)
let sign_in_title_box : @ui.Style = @ui.css("pt=S2_5")

///|
// kept across runs: a value (no field of it changes)
let sign_in_title : @ui.TextStyle = @ui.text_style(size=Xl4, weight=Bold, color=Fg, wrap=false)

///|
/// What still.fail is for: the body's size, muted, centred (SignIn.kt: 15.sp, lineHeight 21.sp).
// kept across runs: a value (no field of it changes)
let sign_in_note : @ui.TextStyle = @ui.text_style(size=Lg, color=Muted, center=true, w=Full)

///|
/// 6 more over the button.
// kept across runs: a value (no field of it changes)
let sign_in_gap : @ui.Style = @ui.css("h=S1_5")

///|
/// The button: the ink's, a pill across the page, no wider than `most`; its words the page's ground, semibold.
fn sign_in_button(most : Double) -> @ui.Style {
  @ui.style(
    row=true,
    w=Full,
    max_w=Fixed(most),
    h=Fixed(sign_in_button_h),
    radius=Full,
    bg=Fg,
    align=ACenter,
    justify=JCenter,
  )
}

///|
// kept across runs: a value (no field of it changes)
let sign_in_button_desk : @ui.Style = sign_in_button(sign_in_desk_w)

///|
// kept across runs: a value (no field of it changes)
let sign_in_button_touch : @ui.Style = sign_in_button(sign_in_touch_w)

///|
// kept across runs: a value (no field of it changes)
let sign_in_words : @ui.TextStyle = @ui.text_style(size=Xl, weight=Semibold, color=Bg, wrap=false)

///|
/// 可同时登录多个账号: small, muted.
// kept across runs: a value (no field of it changes)
let sign_in_many : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// The page: the picture, the words (none on a desktop), the button.
pub fn sign_in_page(c : @ui.Ctx, src : Source) -> Unit {
  let t = @sf.theme()
  let busy = (src.signing_in)()
  // a desktop's (the screen's kind, never the hand): the picture and 登录或注册 alone, no words around them (asked
  // for, 2026-10-23)
  let bare = !@sf.touch_system()
  c.box(style=sign_in_box, fn() {
    @sf.drawable(
      c,
      if t.dark {
        "illus_sign_in_dark"
      } else {
        "illus_sign_in"
      },
      dmin(sign_in_picture_w, c.width - sign_in_side - sign_in_side),
    )
    |> ignore
    if !bare {
      c.box(style=sign_in_title_box, fn() {
        c.text(@sf.t("android-settings.signIn.title"), style=sign_in_title) |> ignore
      })
      |> ignore
      c.text(@sf.t("android-settings.signIn.note"), style=sign_in_note) |> ignore
    }
    c.box(style=sign_in_gap, fn() {  }) |> ignore
    let id = c.id("sign-in")
    if c.clicked(id) && !busy {
      (src.sign_in)()
    }
    // a desktop's no wider than the desktop app's (web cloud/gate.css.ts `ways`), a phone's across it
    c.box(style=if bare { sign_in_button_desk } else { sign_in_button_touch }, id~, fn() {
      c.text(
        if busy {
          @sf.t("common.opening")
        } else {
          @sf.t("android-settings.signIn.google")
        },
        style=sign_in_words,
      )
      |> ignore
      // SignIn.kt: clip(CircleShape).clickable
      if !busy {
        @motion.ripple(c, id, sign_in_button_h / 2.0)
      }
    })
    |> ignore
    if !bare {
      c.text(@sf.t("android-settings.signIn.many"), style=sign_in_many) |> ignore
    }
  })
  |> ignore
}
