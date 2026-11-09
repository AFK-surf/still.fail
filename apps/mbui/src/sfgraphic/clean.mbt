// Individual editions of the share graphics: one actual app card on a neutral canvas.

///|
let clean_card_width : Double = 398.0

///|
let clean_canvas_width : Double = 480.0

///|
let clean_canvas_height : Double = 270.0

///|
fn clean_card(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.set_theme(@sf.ui_theme_now())
  @figure.canvas(c, clean_canvas_width, clean_canvas_height, paper, fn() {
    c.box(style=@ui.css("row w=Full h=Full align=ACenter justify=JCenter"), body) |> ignore
  })
}

///|
/// The narrow sign-in card, with either normal or reverse wrapping.
pub fn wrap_card_figure(c : @ui.Ctx, reverse : Bool) -> Unit {
  clean_card(c, fn() {
    sign_in_example(c, clean_card_width, reverse, "clean-wrap")
  })
}

///|
/// The quota card, with either button-edge or text alignment.
pub fn alignment_card_figure(c : @ui.Ctx, text_aligned : Bool) -> Unit {
  clean_card(c, fn() {
    alignment_example(c, clean_card_width, text_aligned, "clean-align")
  })
}
