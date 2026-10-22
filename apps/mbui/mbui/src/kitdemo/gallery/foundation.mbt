// The foundation's page: the theme's colours, a button in each look and state, a row in both directions, a layer
// put by its anchor.

///|
fn foundation(c : @ui.Ctx) -> Unit {
  let t = c.theme()
  section(c, "Theme", fn() {
    line(c, fn() {
      for sw in [
        ("bg", t.bg),
        ("surface", t.surface),
        ("fg", t.fg),
        ("muted", t.muted),
        ("faint", t.faint),
        ("line", t.line),
        ("border", t.border),
        ("primary", t.primary),
        ("accent", t.accent),
        ("danger", t.danger),
      ] {
        c.box(gap=4.0, align=ACenter, fn() {
          c.box(w=Px(28.0), h=Px(28.0), radius=8.0, bg=sw.1, border=1.0, border_color=t.border, fn() {  })
          |> ignore
          c.text(sw.0, size=10.0, color=t.muted, wrap=false) |> ignore
        })
        |> ignore
      }
    })
  })
  section(c, "Button", fn() {
    line(c, fn() {
      for v in [@kit.Solid, Soft, Outline, Ghost, Danger] {
        @kit.button(c, v.to_string(), variant=v) |> ignore
      }
    })
    line(c, fn() {
      let state = fn(label : String, hovered : Bool, pressed : Bool, focus : Bool, disabled : Bool) {
        c.box(fn() {
          @kit.button_look(c, {
            label,
            variant: Solid,
            hovered,
            pressed,
            focus_shown: focus,
            disabled,
            rect: (0.0, 0.0, if label == "Focused" { 88.0 } else { 0.0 }, t.control_h),
          })
        })
        |> ignore
      }
      state("Rest", false, false, false, false)
      state("Hovered", true, false, false, false)
      state("Pressed", true, true, false, false)
      state("Focused", false, false, true, false)
      state("Disabled", false, false, false, true)
    })
  })
  section(c, "Direction", fn() {
    for d in [@ui.Ltr, Rtl] {
      c.with_direction(d, fn() {
        c.box(dir=Row, gap=6.0, pl=12.0, bg=t.faint, radius=8.0, pady=6.0, fn() {
          c.text(d.to_string(), size=t.font_sm, weight=600, wrap=false) |> ignore
          for k in ["one", "two", "three"] {
            c.box(padx=8.0, pady=2.0, bg=t.surface, radius=6.0, fn() {
              c.text(k, size=t.font_sm, wrap=false) |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      })
    }
  })
  section(c, "Layer", fn() {
    let anchor = c.id("anchor")
    c.box(dir=Row, fn() {
      c.box(padx=12.0, pady=8.0, bg=t.faint, radius=t.radius, id=anchor, fn() {
        c.text("Anchor", size=t.font_sm, wrap=false) |> ignore
      })
      |> ignore
    })
    |> ignore
    // a layer put below it, kept in the window (by its size and its anchor's place as laid out)
    c.overlay("layer", anchor~, fn() {
      let body = c.id("layer-body")
      let i = c.box(
        pad=12.0,
        gap=4.0,
        bg=t.surface,
        radius=t.radius_lg,
        border=1.0,
        border_color=t.border,
        shadow=24.0,
        shadow_color=t.shadow,
        id=body,
        fn() {
          c.text("Over the page", weight=600, wrap=false) |> ignore
          c.text("Put by its anchor", size=t.font_sm, color=t.muted, wrap=false) |> ignore
        },
      )
      c.place_by_size(i, fn(w, h) {
        let r = c.laid_out(anchor).unwrap_or((0.0, 0.0, 0.0, 0.0))
        let (x, y, _) = c.place(r, w, h, along=Start)
        (x, y)
      })
    })
    |> ignore
  })
}
