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
/// The card's lines in each example, highlighted as selected words are: where a highlight starts is where a line's
/// first letter starts, so the lines that start together share one edge without a guide drawn over them.
let alignment_lines : Array[String] = [
  "Quota check failed", "Request timed out.", "Check your connection and try again.", "Try again",
]

///|
/// The selection's tint over each example's words, in the example's colour (drawn over the card, so it is see-through).
fn selection_tint(text_aligned : Bool) -> Int64 {
  ((if text_aligned { blue } else { red }) & 0xFFFFFF00L) | 0x5CL
}

///|
/// Highlight the card's lines where the previous frame drew their letters (`runs`, in the canvas's points).
fn alignment_selection(c : @ui.Ctx, runs : Array[@ui.TextRun]) -> Unit {
  for run in runs {
    if alignment_lines.contains(run.text) {
      let text_aligned = run.x0 > 480.0
      @figure.panel(c, run.x0 - 1.0, run.top, run.x1 - run.x0 + 2.0, run.bottom - run.top, selection_tint(text_aligned), 3.0, fn() {
      })
    }
  }
}

///|
fn alignment_panel(c : @ui.Ctx, x : Double, text_aligned : Bool) -> Unit {
  let w = 418.0
  let card_width = w - 2.0 * @sf.corner_inset
  let dot = @sf.capsule_in(@sf.pane_corner, 10.0)
  let mark = if text_aligned { blue } else { red }
  @figure.panel(c, x, 128.0, w, 282.0, white, @sf.pane_corner, fn() {
    @figure.panel(c, dot, dot, 10.0, 10.0, mark, 5.0, fn() { })
    @figure.words(c, dot + 20.0, dot - 5.625, if text_aligned { "Align the text" } else { "Align the edge" }, 17.0, ink, weight=650)
    c.box(style=@ui.style(w=Fixed(card_width)), left=@sf.corner_inset, top=54.0, fn() {
      alignment_example(c, card_width, text_aligned, if text_aligned { "words" } else { "edge" })
    })
    |> ignore
    @figure.words(c, @sf.corner_inset + @sf.card_pad, 210.0, if text_aligned { "Every line starts together." } else { "The button's edge lines up." }, 15.0, ink, weight=650)
    @figure.words(c, @sf.corner_inset + @sf.card_pad, 235.0, if text_aligned { "The button reaches into the margin." } else { "Its label starts further in." }, 12.0, muted)
  })
}

///|
/// A 960 × 540 comparison of aligning a button's edge or its words to the words above it. `runs` are the lines of
/// words a previous frame of it drew (Tester::text_runs): its card's lines are highlighted where they were drawn.
pub fn alignment_figure(c : @ui.Ctx, runs? : Array[@ui.TextRun] = []) -> Unit {
  c.set_theme(@sf.ui_theme_now())
  @figure.canvas(c, 960.0, 540.0, paper, fn() {
    @figure.words(c, 50.0, 19.0, "Same card. Different alignment.", 34.0, ink, weight=680)
    @figure.words(c, 50.0, 65.0, "Select the text and the difference shows.", 14.0, muted)
    @figure.panel(c, 826.0, 31.0, 10.0, 10.0, ink, 3.0, fn() { })
    @figure.words(c, 844.0, 24.0, "still.fail", 18.0, ink, weight=650)
    alignment_panel(c, 50.0, false)
    alignment_panel(c, 492.0, true)
    @figure.words(c, 50.0, 449.0, "Button padding makes the difference.", 20.0, ink, weight=650)
    @figure.words(c, 50.0, 480.0, "Align the words, and let the button follow the card's corner.", 14.0, muted)
    alignment_selection(c, runs)
  })
}
