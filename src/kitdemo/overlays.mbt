// The overlays' page (Radix's second batch): each drawn by its look where it stands (a screenshot cannot open them
// over the window), then their triggers, live: a dialog, an alert dialog, a popover, a tooltip, toasts.

// what is open in each half (light, dark): each opens its own, in its theme

///|
let dialog_open : Array[Bool] = [false, false]

///|
let alert_open : Array[Bool] = [false, false]

///|
let pop_open : Array[Bool] = [false, false]

///|
let toasts : Array[Array[@kit.Toast]] = [[], []]

///|
let toasts_made : Ref[Int] = Ref(0)

///|
/// MBUI_OPEN (dialog, alert, popover, toast, menu: one of them) opens it in the light half as the page first shows, for a
/// screenshot of it in place.
let opened_env : Ref[Bool] = Ref(false)

///|
fn overlays(c : @ui.Ctx) -> Unit {
  let t = c.theme()
  let h = if t.dark { 1 } else { 0 }
  if !opened_env.val && h == 0 {
    opened_env.val = true
    match @ui.env("MBUI_OPEN") {
      "dialog" => dialog_open[0] = true
      "alert" => alert_open[0] = true
      "popover" => pop_open[0] = true
      "toast" =>
        toasts[0] = [
          @kit.toast("a", "Saved", description="Your profile is up to date"),
          @kit.toast("b", "Sent", description="To the team", action="Undo"),
        ]
      _ => ()
    }
  }
  let shown = 1.0
  section(c, "Dialog and alert dialog", fn() {
    c.box(dir=Row, gap=12.0, align=AStart, fn() {
      @kit.dialog_look(
        c,
        { title: "Edit profile", description: "How others see you.", t: shown, w: 200.0, closes: true },
        fn() {
          c.box(h=Px(t.control_h), radius=t.radius, border=1.0, border_color=t.border, padx=10.0, justify=JCenter, fn() {
            c.text("Ada Lovelace", size=t.font_sm, wrap=false) |> ignore
          })
          |> ignore
          c.box(dir=Row, justify=JEnd, pt=4.0, fn() { @kit.button(c, "Save", key="g-save") |> ignore }) |> ignore
          @kit.close_button(c, "g-close", "关闭") |> ignore
        },
      )
      @kit.dialog_look(
        c,
        { title: "Delete the chat?", description: "It cannot be undone.", t: shown, w: 200.0, closes: false },
        fn() {
          c.box(dir=Row, gap=8.0, justify=JEnd, pt=8.0, fn() {
            @kit.button(c, "Cancel", key="g-cancel", variant=Outline) |> ignore
            @kit.button(c, "Delete", key="g-delete", variant=Danger) |> ignore
          })
          |> ignore
        },
      )
    })
    |> ignore
  })
  section(c, "Popover, hover card and tooltip", fn() {
    c.box(dir=Row, gap=12.0, align=AStart, fn() {
      @kit.popover_look(c, { side: Bottom, t: shown }, fn() {
        c.text("Filters", size=t.font_sm, weight=600, wrap=false) |> ignore
        c.box(dir=Row, gap=8.0, align=ACenter, fn() {
          @kit.checkbox(c, "g-unread", On, label="Unread") |> ignore
          c.text("Unread only", size=t.font_sm, wrap=false) |> ignore
        })
        |> ignore
      })
      @kit.popover_look(c, { side: Bottom, t: shown }, fn() {
        c.box(dir=Row, gap=10.0, align=ACenter, fn() {
          @kit.avatar(c, "", "Ada Lovelace", size=36.0)
          c.box(gap=2.0, fn() {
            c.text("@ada", size=t.font_sm, weight=600, wrap=false) |> ignore
            c.text("Programmer", size=t.font_sm, color=t.muted, wrap=false) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      c.box(gap=6.0, align=ACenter, fn() {
        @kit.tooltip_look(c, { side: Top, t: shown }, "Bold (⌘B)")
        @kit.button(c, "B", key="g-bold", variant=Outline) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  section(c, "Toast", fn() {
    @kit.toast_look(
      c,
      { toast: @kit.toast("g", "Sent", description="To the team, 2 minutes ago", action="Undo"), t: shown, dx: 0.0, hovered: false },
      fn() {
        @kit.toast_button(c, "g-undo", "Undo", "Undo", false) |> ignore
        @kit.toast_button(c, "g-toast-close", "✕", "关闭", true) |> ignore
      },
    )
  })
  section(c, "Live", fn() {
    line(c, fn() {
      if @kit.button(c, "Dialog", key="open-dialog", variant=Soft).clicked {
        dialog_open[h] = true
      }
      if @kit.button(c, "Delete…", key="open-alert", variant=Soft).clicked {
        alert_open[h] = true
      }
      let p = @kit.button(c, "Popover", key="open-pop", variant=Soft)
      if p.clicked {
        pop_open[h] = !pop_open[h]
      }
      let tip = @kit.button(c, "Tooltip", key="tip", variant=Soft)
      @kit.tooltip(c, "tip", tip.id, "Words about it") |> ignore
      if @kit.button(c, "Toast", key="open-toast", variant=Soft).clicked {
        toasts_made.val += 1
        toasts[h] = toasts[h] + [@kit.toast("t\{toasts_made.val}", "Saved", description="Toast \{toasts_made.val}")]
      }
      dialog_open[h] = @kit.dialog(c, "dialog", dialog_open[h], "Edit profile", description="How others see you.", fn() {
          @kit.text_field(c, "name", placeholder="Name") |> ignore
        }).value
      alert_open[h] = @kit.alert_dialog(
          c,
          "alert",
          alert_open[h],
          "Delete the chat?",
          "Delete",
          description="It cannot be undone.",
          danger=true,
        ).open
      pop_open[h] = @kit.popover(c, "pop", pop_open[h], p.id, label="Filters", fn() {
          c.text("Filters", weight=600, wrap=false) |> ignore
          @kit.button(c, "Apply", key="apply") |> ignore
        }).value
      toasts[h] = @kit.toaster(c, "toasts", toasts[h]).open
    })
  })
}
