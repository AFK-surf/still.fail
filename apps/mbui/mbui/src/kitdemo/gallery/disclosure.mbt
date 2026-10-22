// The last batch's page: an accordion with one part open, a collapsible, tabs, a scroll area, a form that was handed
// on with something wrong (each half its own).

///|
let folds : Array[Array[String]] = [["b"], ["b"]]

///|
let more : Array[Bool] = [false, false]

///|
let tab : Array[String] = ["account", "account"]

///|
let tried : Array[Bool] = [false, false]

///|
fn disclosure(c : @ui.Ctx) -> Unit {
  let t = c.theme()
  let h = if t.dark { 1 } else { 0 }
  c.box(dir=Row, gap=20.0, align=AStart, fn() {
    c.box(w=Fill(1.0), gap=18.0, fn() {
      section(c, "Accordion", fn() {
        folds[h] = @kit.accordion(
            c,
            "faq",
            [
              @kit.fold("a", "What is mbui?", fn() { c.text("A UI library", size=t.font, color=t.muted) |> ignore }),
              @kit.fold("b", "Is it fast?", fn() {
                c.text("Every frame is drawn anew, in well under a millisecond.", size=t.font, color=t.muted) |> ignore
              }),
              @kit.fold("c", "Who made it?", fn() { c.text("still.fail", size=t.font, color=t.muted) |> ignore }),
            ],
            folds[h],
          ).value
      })
      section(c, "Collapsible", fn() {
        more[h] = @kit.collapsible(c, "more", more[h], "3 more stations", fn() {
            c.text("mini1, studio, ccvm", size=t.font, color=t.muted) |> ignore
          }).value
      })
      section(c, "Scroll area", fn() {
        c.box(radius=t.radius, border=1.0, border_color=t.line, clip=true, fn() {
          @kit.scroll_area(c, "log", 96.0, fn() {
            c.box(pad=10.0, gap=4.0, fn() {
              for i in 0..<20 {
                c.text("line \{i}", size=t.font_sm, color=t.muted) |> ignore
              }
            })
            |> ignore
          })
        })
        |> ignore
      })
    })
    |> ignore
    c.box(w=Fill(1.0), gap=18.0, fn() {
      section(c, "Tabs", fn() {
        tab[h] = @kit.tabs(
            c,
            "tabs",
            [@kit.item("account", label="Account"), @kit.item("password", label="Password")],
            tab[h],
            fn(which) {
              c.text(if which == "account" { "Your name and picture." } else { "Change it here." }, size=t.font, color=t.muted)
              |> ignore
            },
          ).value
      })
      section(c, "Form", fn() {
        let r = @kit.form(c, "signup", [
          @kit.form_field("email", "Email", kind=Email, required=true, placeholder="you@example.com"),
          @kit.form_field("name", "Name", placeholder="Ada"),
        ])
        ignore(r)
        // as it shows once handed on empty
        if !tried[h] {
          tried[h] = true
          c.ask_action(c.id("signup/submit"), Activate)
        }
      })
    })
    |> ignore
  })
  |> ignore
}
