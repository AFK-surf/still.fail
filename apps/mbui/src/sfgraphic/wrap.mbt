// A shareable comparison built from the same card, buttons, chooser and flex layout as the app. Only the normal-wrap
// example changes the direction of the card foot; the wide and reverse examples use the app's own ask_buttons.

///|
let paper : Int64 = 0xEDEDF0FFL
///|
let ink : Int64 = 0x1D1D1FFFL
///|
let muted : Int64 = 0x6E6E73FFL
///|
let faint : Int64 = 0x85858CFFL
///|
let white : Int64 = 0xFFFFFFFFL
///|
let red : Int64 = 0xF0502CFFL
///|
let blue : Int64 = 0x2863E9FFL

///|
/// The sign-in card's own controls. Each example has its own keys because all three belong to the same drawing.
fn sign_in_actions(c : @ui.Ctx, key : String) -> Unit {
  ignore(@sf.button(c, "Use password manager", key=key + "/primary", tone=Primary))
  ignore(@sf.button(c, "Sign in here", key=key + "/screen", tone=Ghost))
  ignore(@sf.chooser(
    c,
    key + "/vault",
    "Save to vault",
    [],
    fn() { false },
    fn(_) { },
    as_button=true,
  ))
}

///|
/// A real sign-in card's components at one width. `reverse` is the only difference in its foot's layout.
pub fn sign_in_example(c : @ui.Ctx, width : Double, reverse : Bool, key : String) -> Unit {
  c.box(style=@ui.style(w=Fixed(width)), fn() {
    @sf.card(c, fill=true, fn() {
      @sf.ask_words(c, "Sign in to github.com", "View Actions logs for PR #512")
      let actions = fn() { sign_in_actions(c, key) }
      if reverse {
        @sf.ask_buttons(c, actions)
      } else {
        c.box(style=@sf.ask_foot.then(@sf.foot_reach(@sf.button_height())), flow=true, line_gap=@sf.ask_foot_lines(), fn() {
          @sf.card_foot_words(actions)
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
fn card_at(c : @ui.Ctx, x : Double, y : Double, width : Double, reverse : Bool, key : String) -> Unit {
  c.box(style=@ui.style(w=Fixed(width)), left=x, top=y, fn() { sign_in_example(c, width, reverse, key) }) |> ignore
}

///|
fn comparison_panel(c : @ui.Ctx, x : Double, reverse : Bool) -> Unit {
  let w = 418.0
  let dot = @sf.capsule_in(@sf.pane_corner, 10.0)
  @figure.panel(c, x, 244.0, w, 280.0, white, @sf.pane_corner, fn() {
    @figure.panel(c, dot, dot, 10.0, 10.0, if reverse { blue } else { red }, 5.0, fn() { })
    @figure.words(c, dot + 20.0, dot - 5.625, if reverse { "Narrow · reverse wrap" } else { "Narrow · normal wrap" }, 17.0, ink, weight=650)
    @figure.words(c, if reverse { 296.0 } else { 348.0 }, dot - 2.625, if reverse { "wrap-reverse ↑" } else { "wrap ↓" }, 11.0, faint)
    card_at(c, @sf.corner_inset, 54.0, w - 2.0 * @sf.corner_inset, reverse, if reverse { "reverse" } else { "normal" })
    @figure.words(c, @sf.corner_inset + @sf.card_pad, 220.0, if reverse { "The last action wraps up." } else { "The last action wraps down." }, 15.0, ink, weight=650)
    @figure.words(
      c,
      @sf.corner_inset + @sf.card_pad,
      244.0,
      if reverse { "The primary action stays in the bottom-left corner." } else { "The primary action is no longer at the bottom." },
      12.0,
      muted,
    )
  })
}

///|
/// The 960 × 540 wrapping figure, intended to be drawn at 2.5× for a 2400 × 1350 PNG.
pub fn wrap_figure(c : @ui.Ctx) -> Unit {
  c.set_theme(@sf.ui_theme_now())
  let wide_panel_w = 860.0
  let wide_card_x = 164.0
  let wide_card_w = wide_panel_w - wide_card_x - @sf.corner_inset
  @figure.canvas(c, 960.0, 540.0, paper, fn() {
    @figure.words(c, 50.0, 19.0, "Same buttons. Different wrap.", 34.0, ink, weight=680)
    @figure.words(c, 50.0, 65.0, "Three actions fit on a wide row. When space runs out, the wrap direction matters.", 14.0, muted)
    @figure.panel(c, 826.0, 31.0, 10.0, 10.0, ink, 3.0, fn() { })
    @figure.words(c, 844.0, 24.0, "still.fail", 18.0, ink, weight=650)
    @figure.auto_panel(c, 50.0, 96.0, wide_panel_w, white, @sf.pane_corner, fn() {
      @figure.words(c, @sf.card_pad, 25.0, "Wide layout", 18.0, ink, weight=650)
      @figure.words(c, @sf.card_pad, 59.0, "All three actions\nfit on one line.", 14.0, muted, width=135.0, line=20.0)
      c.box(style=@ui.style(w=Fixed(wide_card_w), ml=@sf.room_of(wide_card_x), my=@sf.inset_room), fn() {
        sign_in_example(c, wide_card_w, true, "wide")
      })
      |> ignore
    })
    comparison_panel(c, 50.0, false)
    comparison_panel(c, 492.0, true)
  })
}
