// The gallery's second page (MBUI_CM_PAGE=more): Comma's floating parts (Tooltip, Menu, Dropdown, Popup, Dialog, Toast)
// and the rest of its base parts (Button group, Radio and Checkbox groups, Slider, Collapse, Indicator, ScrollArea),
// in two columns. MBUI_CM_OPEN names a floating part to open as the page starts, for its picture: tooltip, menu,
// dropdown, popup, dialog or toast.

///|
fn more(root : @view.View, layer : @cm.Layer, open : String) -> Unit {
  let toaster = @cm.Toaster::new()
  root.box(fn(page) {
    page
    .grow(Is(1.0))
    .row(Is(true))
    .lines_up(Is(Some(Start)))
    .ground(By(fn() { @cm.colors().bg_primary }))
    .padding(Is((@cm.space_4xl, @cm.space_3xl, @cm.space_4xl, @cm.space_3xl)))
    .gap(Is(@cm.space_6xl))
    |> ignore
    page.box(fn(left) {
      left.grow(Is(1.0)).basis(Is(Some(0.0))).gap(Is(@cm.space_2xl)) |> ignore
      section(left, "Tooltip", fn(s) {
        row(s, fn(r) {
          let a = @cm.button_node(r, fn() { "Hover me" }, fn() {  }, hierarchy=SecondaryGray)
          @cm.tooltip_node(layer, a, fn() { "This is a tooltip" }, shown=fn() { open == "tooltip" })
          let b = @cm.button_node(r, fn() { "Below" }, fn() {  }, hierarchy=SecondaryGray)
          @cm.tooltip_node(layer, b, fn() { "Shown under it" }, side=Bottom)
        })
      })
      section(left, "Menu", fn(s) {
        row(s, fn(r) {
          let shown = @signals.signal(open == "menu")
          let a = @cm.button_node(r, fn() { "Options" }, fn() { shown.set(!shown.untracked()) }, hierarchy=SecondaryGray)
          @cm.menu_node(layer, a, shown, fn() {
            [
              @cm.menu_item("View profile", fn() {  }),
              @cm.menu_item("Settings", fn() {  }, checked=true),
              @cm.menu_item("Keyboard shortcuts", fn() {  }),
              @cm.menu_item("Log out", fn() {  }, danger=true, divided=true),
            ]
          })
        })
      })
      section(left, "Dropdown", fn(s) {
        row(s, fn(r) {
          r.box(fn(b) {
            b.width(Is(Some(240.0))) |> ignore
            let chosen = @signals.signal(1)
            @cm.dropdown_node(
              b,
              layer,
              ["Light", "Dark", "System"],
              chosen,
              label="Appearance",
              open=@signals.signal(open == "dropdown"),
            )
            |> ignore
          })
          |> ignore
          r.box(fn(b) {
            b.width(Is(Some(240.0))) |> ignore
            @cm.dropdown_node(b, layer, ["English", "简体中文"], @signals.signal(-1), label="Language", placeholder="Select a language")
            |> ignore
          })
          |> ignore
        })
      })
      section(left, "Popup", fn(s) {
        row(s, fn(r) {
          let shown = @signals.signal(open == "popup")
          let a = @cm.button_node(r, fn() { "Share" }, fn() { shown.set(!shown.untracked()) }, hierarchy=SecondaryGray)
          @cm.popup_node(layer, a, shown, fn(p) {
            p.gap(Is(@cm.space_lg)) |> ignore
            p.box(fn(w) {
              w
              .words(Is("Share this workspace"), look=@cm.words_in(@cm.type_regular, weight=@cm.weight_semibold))
              .ink(By(fn() { @cm.colors().text_primary }))
              |> ignore
            })
            |> ignore
            p.box(fn(w) {
              w
              .words(Is("Anyone with the link can view it."), look=@cm.words_in(@cm.type_small, wrap=true))
              .ink(By(fn() { @cm.colors().text_tertiary }))
              |> ignore
            })
            |> ignore
            @cm.input_node(p, @ui.Field::new(text="comma.surf/w/design"), label="Link") |> ignore
          })
        })
      })
      section(left, "Dialog", fn(s) {
        row(s, fn(r) {
          let shown = @signals.signal(open == "dialog")
          @cm.button_node(r, fn() { "Delete project" }, fn() { shown.set(true) }, hierarchy=Destructive) |> ignore
          @cm.dialog_node(
            layer,
            shown,
            fn() { "Delete this project?" },
            description=fn() { "Its tasks and files go with it. This cannot be undone." },
            actions=fn(f) {
              @cm.button_node(f, fn() { "Cancel" }, fn() { shown.set(false) }, hierarchy=SecondaryGray, size=Sm) |> ignore
              @cm.button_node(f, fn() { "Delete" }, fn() { shown.set(false) }, hierarchy=Destructive, size=Sm) |> ignore
            },
          )
        })
      })
      section(left, "Toast", fn(s) {
        row(s, fn(r) {
          @cm.button_node(r, fn() { "Saved" }, fn() { toaster.show("Changes saved", intent=Success) }, hierarchy=SecondaryGray)
          |> ignore
          @cm.button_node(
            r,
            fn() { "Failed" },
            fn() { toaster.show("Upload failed", description="design.fig is larger than 100 MB.", intent=Error) },
            hierarchy=SecondaryGray,
          )
          |> ignore
        })
      })
    })
    |> ignore
    page.box(fn(right) {
      right.grow(Is(1.0)).basis(Is(Some(0.0))).gap(Is(@cm.space_2xl)) |> ignore
      section(right, "Button group", fn(s) {
        @cm.button_group_node(s, ["Leading", "Text", "Text", "Trailing"], @signals.signal(0)) |> ignore
        @cm.button_group_node(s, ["Online", "Away", "Busy"], @signals.signal(1), dot=0) |> ignore
      })
      section(right, "Radio group · Checkbox group", fn(s) {
        row(s, fn(r) {
          r.box(fn(b) {
            b.width(Is(Some(220.0))) |> ignore
            @cm.radio_group_node(
              b,
              [("Basic plan", "Up to 10 users."), ("Business plan", "Up to 20 users."), ("Enterprise", "Unlimited.")],
              @signals.signal(1),
              label="Plan",
            )
            |> ignore
          })
          |> ignore
          r.box(fn(b) {
            b.width(Is(Some(220.0))) |> ignore
            @cm.check_group_node(
              b,
              [("Email", "Weekly digest."), ("Push", "Mentions only."), ("SMS", "")],
              @signals.signal([true, false, true]),
              label="Notifications",
            )
            |> ignore
          })
          |> ignore
        })
      })
      section(right, "Slider", fn(s) {
        s.box(fn(b) {
          b.width(Is(Some(320.0))).gap(Is(@cm.space_3xl)) |> ignore
          @cm.slider_node(b, @signals.signal(40.0), fn() { "Volume" }) |> ignore
          @cm.slider_node(b, @signals.signal(75.0), fn() { "Disabled" }, disabled=fn() { true }) |> ignore
        })
        |> ignore
      })
      section(right, "Collapse", fn(s) {
        s.box(fn(b) {
          b.width(Is(Some(360.0))).gap(Is(@cm.space_md)) |> ignore
          for i, t in ["What is Comma?", "How are tasks shared?"] {
            @cm.collapse_node(b, fn() { t }, @signals.signal(i == 0), fn(body) {
              body.box(fn(w) {
                w
                .words(Is("Comma runs agents for your team in one place, each with its own workspace."), look=@cm.words_in(@cm.type_small, wrap=true))
                .ink(By(fn() { @cm.colors().text_tertiary }))
                |> ignore
              })
              |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      })
      section(right, "Indicator", fn(s) {
        row(s, fn(r) {
          for size in [0, 1, 2] {
            for sig in [@cm.Idle, Info, Good, Caution, Bad] {
              @cm.indicator_node(r, sig, "Status", size~) |> ignore
            }
          }
        })
      })
      section(right, "ScrollArea", fn(s) {
        s.box(fn(b) {
          b
          .width(Is(Some(320.0)))
          .radius(Is(@cm.radius_md))
          .edge(By(fn() { (1.0, @cm.colors().border_secondary) }))
          |> ignore
          @cm.scroll_area_node(b, 160.0, label="Releases", fn(list) {
            list.padding(Is((@cm.space_lg, @cm.space_md, @cm.space_lg, @cm.space_md))).gap(Is(@cm.space_md)) |> ignore
            for i in 1..=12 {
              list.box(fn(w) {
                w.words(Is("Release 0.\{i}.0"), look=@cm.words_in(@cm.type_small)).ink(By(fn() { @cm.colors().text_secondary }))
                |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      })
    })
    |> ignore
  })
  |> ignore
  @cm.toaster_node(layer, toaster)
  if open == "toast" {
    toaster.show("Changes saved", intent=Success)
    toaster.show("Upload failed", description="design.fig is larger than 100 MB.", intent=Error)
  }
}
