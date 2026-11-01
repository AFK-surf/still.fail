// A quota card drawn twice: the first aligns the button's edge to the card's words; the second uses the real card foot
// so the button's words align instead, while the button itself follows the card's corner.

///|
/// The edge-aligned example deliberately leaves the button off the card's bottom-left corner. No other faults belong
/// in the picture, including on the surrounding white panels or on the text-aligned example.
pub fn alignment_corner_faults_ok(faults : Array[String]) -> Bool {
  faults.length() == 1 &&
  faults[0].contains("「Try again」") &&
  faults[0].contains("bottom left") &&
  faults[0].contains("Quota check failed")
}

///|
fn alignment_example(c : @ui.Ctx, width : Double, text_aligned : Bool, key : String) -> Unit {
  c.box(style=@ui.style(w=Fixed(width)), fn() {
    @sf.layers(c, fn() {
      @sf.page_card(c, footed=true, fn() {
        @sf.card_lines(c, "Quota check failed", words="Request timed out.", note="Check your connection and try again.")
        let action = fn() { ignore(@sf.button(c, "Try again", key~, tone=Primary)) }
        if text_aligned {
          @sf.card_foot(c, action)
        } else {
          c.box(style=@sf.ask_foot, action) |> ignore
        }
      })
    })
  })
  |> ignore
}

///|
fn alignment_panel(c : @ui.Ctx, x : Double, text_aligned : Bool) -> Unit {
  let w = 418.0
  let card_width = w - 2.0 * @sf.corner_inset
  let dot = @sf.capsule_in(@sf.pane_corner, 10.0)
  let mark = if text_aligned { blue } else { red }
  @figure.panel(c, x, 128.0, w, 282.0, white, @sf.pane_corner, fn() {
    @figure.panel(c, dot, dot, 10.0, 10.0, mark, 5.0, fn() { })
    @figure.words(c, dot + 20.0, dot - 5.625, if text_aligned { "Text aligned" } else { "Edge aligned" }, 17.0, ink, weight=650)
    c.box(style=@ui.style(w=Fixed(card_width)), left=@sf.corner_inset, top=54.0, fn() {
      alignment_example(c, card_width, text_aligned, if text_aligned { "words" } else { "edge" })
    })
    |> ignore
    // A dotted rail in the margin links two short ticks: the first points to the card's words, the second to the
    // button's edge or its label. The ticks meet the actual starting x without covering the text.
    let rail_x = @sf.corner_inset + @sf.card_pad - 6.0
    for i in 0..<15 {
      @figure.panel(c, rail_x, 84.0 + i.to_double() * 6.0, 1.5, 2.5, mark, 0.0, fn() { })
    }
    @figure.panel(c, rail_x, 83.5, 6.0, 1.5, mark, 0.0, fn() { })
    @figure.panel(c, rail_x, 168.5, 6.0, 1.5, mark, 0.0, fn() { })
    @figure.words(c, @sf.corner_inset + @sf.card_pad, 210.0, if text_aligned { "Text start = button label" } else { "Text start = button edge" }, 15.0, ink, weight=650)
    @figure.words(c, @sf.corner_inset + @sf.card_pad, 235.0, if text_aligned { "The button reaches into the margin." } else { "The label sits further right." }, 12.0, muted)
  })
}

///|
/// A 960 × 540 comparison of aligning a button's edge or its words to the words above it.
pub fn alignment_figure(c : @ui.Ctx) -> Unit {
  c.set_theme(@sf.ui_theme_now())
  @figure.canvas(c, 960.0, 540.0, paper, fn() {
    @figure.words(c, 50.0, 19.0, "Same card. Different alignment.", 34.0, ink, weight=680)
    @figure.words(c, 50.0, 65.0, "The button's shape and its label don't start in the same place.", 14.0, muted)
    @figure.panel(c, 826.0, 31.0, 10.0, 10.0, ink, 3.0, fn() { })
    @figure.words(c, 844.0, 24.0, "still.fail", 18.0, ink, weight=650)
    alignment_panel(c, 50.0, false)
    alignment_panel(c, 492.0, true)
    @figure.words(c, 50.0, 449.0, "Button padding makes the difference.", 20.0, ink, weight=650)
    @figure.words(c, 50.0, 480.0, "Align the words while the button follows the card's corner.", 14.0, muted)
  })
}
