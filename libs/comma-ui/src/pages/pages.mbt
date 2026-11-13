// The gallery's pages (src/gallery shows them in a window, src/shots draws them offscreen): `page` the one asked for.

///|
/// The gallery in the window's `root` (its layer made in it first): its first page (Comma's base parts), or with
/// `more` its second (the floating parts and the rest), with `open` the floating part to open as it starts (tooltip,
/// menu, dropdown, popup, dialog or toast; "" none).
pub fn page(root : @view.View, more? : Bool = false, open? : String = "") -> Unit {
  @ui.set_tree_theme(@cm.ui_theme)
  let layer = @cm.Layer::new()
  @cm.layer_node(root, layer)
  root.box(fn(w) {
    w.grow(Is(1.0)) |> ignore
    if more {
      more_page(w, layer, open)
    } else {
      base(w)
    }
  })
  |> ignore
}

///|
/// The page: a column of sections on the window's ground.
fn base(root : @view.View) -> Unit {
  root.box(fn(page) {
    page
    .grow(Is(1.0))
    .ground(By(fn() { @cm.colors().bg_primary }))
    .padding(Is((@cm.space_4xl, @cm.space_3xl, @cm.space_4xl, @cm.space_3xl)))
    .gap(Is(@cm.space_2xl))
    |> ignore
    section(page, "Type", fn(s) {
      row(s, fn(r) {
        for w in [400, @cm.weight_regular, @cm.weight_medium, @cm.weight_semibold, @cm.weight_bold] {
          r.box(fn(b) {
            b.words(Is("Inter \{w}"), look=@cm.words_in(@cm.type_large, weight=w)).ink(By(fn() { @cm.colors().text_primary }))
            |> ignore
          })
          |> ignore
        }
      })
    })
    section(page, "Button", fn(s) {
      row(s, fn(r) {
        for h in [
          @cm.Primary,
          SecondaryColor,
          SecondaryGray,
          TertiaryColor,
          TertiaryGray,
          LinkColor,
          LinkGray,
          Destructive,
        ] {
          @cm.button_node(r, fn() { "Button" }, fn() {  }, hierarchy=h) |> ignore
        }
      })
      row(s, fn(r) {
        for size in [@cm.Xs, Sm, Md, Lg] {
          @cm.button_node(r, fn() { "Button" }, fn() {  }, size~) |> ignore
        }
        @cm.button_node(r, fn() { "Online" }, fn() {  }, hierarchy=SecondaryGray, dot=true) |> ignore
      })
      row(s, fn(r) {
        for h in [@cm.Primary, SecondaryGray, TertiaryGray, Destructive] {
          @cm.button_node(r, fn() { "Disabled" }, fn() {  }, hierarchy=h, disabled=fn() { true }) |> ignore
        }
      })
    })
    section(page, "Badge", fn(s) {
      for kind in [@cm.PillColor, PillOutline, BadgeColor, BadgeModern] {
        row(s, fn(r) {
          for tone in [@cm.Gray, Brand, Error, Warning, Success, Blue, Indigo, Purple, Pink, Orange] {
            @cm.badge_node(r, fn() { "Label" }, tone~, kind~) |> ignore
          }
        })
      }
      row(s, fn(r) {
        for size in [@cm.BadgeSm, BadgeMd, BadgeLg] {
          @cm.badge_node(r, fn() { "Label" }, tone=Brand, size~, dot=true) |> ignore
        }
      })
    })
    section(page, "Tag", fn(s) {
      row(s, fn(r) {
        for tone in [@cm.Gray, Brand, Error, Warning, Success] {
          @cm.tag_node(r, fn() { "Label" }, tone~, remove=fn() {  }) |> ignore
        }
        for size in [@cm.BadgeSm, BadgeMd, BadgeLg] {
          @cm.tag_node(r, fn() { "Label" }, size~) |> ignore
        }
      })
    })
    section(page, "Checkbox · Toggle", fn(s) {
      row(s, fn(r) {
        for size in [@cm.ControlSm, ControlMd] {
          for start in [false, true] {
            let on = @signals.signal(start)
            @cm.check_node(r, fn() { on.get() }, fn(v) { on.set(v) }, fn() { "Checkbox" }, size~) |> ignore
          }
          @cm.check_node(r, fn() { true }, fn(_) {  }, fn() { "Disabled" }, size~, disabled=fn() { true }) |> ignore
        }
        for size in [@cm.ControlSm, ControlMd] {
          for start in [false, true] {
            let on = @signals.signal(start)
            @cm.toggle_node(r, fn() { on.get() }, fn(v) { on.set(v) }, fn() { "Toggle" }, size~) |> ignore
          }
          @cm.toggle_node(r, fn() { true }, fn(_) {  }, fn() { "Disabled" }, size~, disabled=fn() { true }) |> ignore
        }
      })
    })
    section(page, "Input", fn(s) {
      row(s, fn(r) {
        let fields = [
          (@ui.Field::new(), false, false),
          (@ui.Field::new(text="olivia@untitledui.com"), false, false),
          (@ui.Field::new(text="olivia@"), true, false),
          (@ui.Field::new(text="Disabled"), false, true),
        ]
        for f in fields {
          let (field, wrong, off) = f
          r.box(fn(b) {
            b.width(Is(Some(240.0))) |> ignore
            @cm.input_node(
              b,
              field,
              placeholder="olivia@untitledui.com",
              label="Email",
              invalid=fn() { wrong },
              disabled=fn() { off },
            )
            |> ignore
          })
          |> ignore
        }
      })
    })
    section(page, "Avatar", fn(s) {
      row(s, fn(r) {
        for size in [@cm.AvatarXs, AvatarSm, AvatarMd, AvatarLg, AvatarXl, Avatar2xl] {
          @cm.avatar_node(r, fn() { "Olivia Rhye" }, size~, online=fn() { Some(true) }) |> ignore
        }
        @cm.avatar_node(r, fn() { "Phoenix Baker" }, online=fn() { Some(false) }) |> ignore
      })
    })
  })
  |> ignore
}

///|
/// A section of the page: its name, then what `body` makes under it.
fn section(page : @view.View, name : String, body : (@view.View) -> Unit) -> Unit {
  page.box(fn(s) {
    s.gap(Is(@cm.space_lg)) |> ignore
    s.box(fn(t) {
      t.words(Is(name), look=@cm.words_in(@cm.type_regular, weight=@cm.weight_semibold)).ink(By(fn() { @cm.colors().text_primary }))
      |> ignore
    })
    |> ignore
    body(s)
  })
  |> ignore
}

///|
/// A row of parts, their middles lined up, a step apart, wrapping where the window is narrower.
fn row(s : @view.View, body : (@view.View) -> Unit) -> Unit {
  s.box(fn(r) {
    r.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(@cm.space_lg)).wraps(Is(Some(@cm.space_lg))) |> ignore
    body(r)
  })
  |> ignore
}
