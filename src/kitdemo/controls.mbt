// The simple controls' page (Radix's first batch): each live with its value kept here (both themes share it), beside
// its look drawn in the states a screenshot cannot reach (focused, disabled).

///|
let sw_on : Ref[Bool] = Ref(true)

///|
let cb : Ref[@ui.Check] = Ref(On)

///|
let size : Ref[String] = Ref("m")

///|
let bold : Ref[Bool] = Ref(true)

///|
let align : Ref[Array[String]] = Ref(["left"])

///|
let marks : Ref[Array[String]] = Ref(["b", "u"])

///|
let level : Ref[Double] = Ref(40.0)

///|
let shown : Ref[Bool] = Ref(false)

///|
fn controls(c : @ui.Ctx) -> Unit {
  let t = c.theme()
  let ring = fn(w : Double, h : Double) { (0.0, 0.0, w, h) }
  section(c, "Switch", fn() {
    line(c, fn() {
      sw_on.val = @kit.switch(c, "sw", sw_on.val, label="Wi-Fi").value
      @kit.switch(c, "sw-off", false, label="Off") |> ignore
      @kit.switch(c, "sw-dis", true, label="Disabled", disabled=true) |> ignore
      c.box(fn() {
        @kit.switch_look(c, {
          on: false,
          t: 0.0,
          hovered: false,
          pressed: false,
          focus_shown: true,
          disabled: false,
          rect: ring(36.0, 22.0),
        })
      })
      |> ignore
    })
  })
  section(c, "Checkbox and label", fn() {
    line(c, fn() {
      cb.val = @kit.checkbox(c, "terms", cb.val, label="Accept terms").value
      @kit.label(c, "Accept terms", for_id=c.id("terms")) |> ignore
      @kit.checkbox(c, "cb-mixed", Mixed, label="Some") |> ignore
      @kit.checkbox(c, "cb-off", Off, label="None") |> ignore
      @kit.checkbox(c, "cb-dis", On, label="Disabled", disabled=true) |> ignore
      c.box(fn() {
        @kit.checkbox_look(c, {
          check: Off,
          hovered: false,
          pressed: false,
          focus_shown: true,
          disabled: false,
          rect: ring(18.0, 18.0),
        })
      })
      |> ignore
    })
  })
  section(c, "Radio group", fn() {
    size.val = @kit.radio_group(
        c,
        "size",
        [@kit.item("s", label="Small"), @kit.item("m", label="Medium"), @kit.item("l", label="Large", disabled=true)],
        size.val,
        orientation=Horizontal,
        gap=16.0,
        label="Size",
      ).value
  })
  section(c, "Toggle and toggle group", fn() {
    line(c, fn() {
      bold.val = @kit.toggle(c, "Bold", bold.val, key="bold").value
      @kit.toggle(c, "Italic", false, key="italic") |> ignore
      align.val = @kit.toggle_group(
          c,
          "align",
          [@kit.item("left", label="Left"), @kit.item("center", label="Center"), @kit.item("right", label="Right")],
          align.val,
          label="Align",
        ).value
      marks.val = @kit.toggle_group(
          c,
          "marks",
          [@kit.item("b", label="B"), @kit.item("i", label="I"), @kit.item("u", label="U")],
          marks.val,
          multiple=true,
          label="Marks",
        ).value
    })
  })
  section(c, "Slider", fn() {
    line(c, fn() {
      level.val = @kit.slider(c, "level", level.val, w=180.0, label="Volume").value
      @kit.slider(c, "level-dis", 70.0, w=120.0, label="Disabled", disabled=true) |> ignore
      c.text("\{level.val.to_int()}", size=t.font_sm, color=t.muted, wrap=false) |> ignore
    })
  })
  section(c, "Progress and avatar", fn() {
    line(c, fn() {
      c.box(w=Px(140.0), gap=10.0, fn() {
        @kit.progress(c, Some(30.0), label="Upload")
        @kit.progress(c, None, label="Loading")
      })
      |> ignore
      @kit.avatar(c, "", "Ada Lovelace")
      @kit.avatar(c, "", "grace hopper", size=32.0)
      @kit.avatar(c, "", "Alan", size=32.0, radius=8.0)
    })
  })
  section(c, "Password field", fn() {
    c.box(w=Px(260.0), fn() {
      shown.val = @kit.password_field(c, "pw", shown.val, placeholder="Password").visible
    })
    |> ignore
  })
  section(c, "Separator, aspect ratio, accessible icon", fn() {
    line(c, fn() {
      c.box(w=Px(96.0), radius=8.0, clip=true, fn() {
        @kit.aspect_ratio(c, 16.0 / 9.0, fn() {
          c.box(w=Fill(1.0), h=Fill(1.0), bg=t.accent, align=ACenter, justify=JCenter, fn() {
            c.text("16:9", size=t.font_sm, color=t.on_accent, wrap=false) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
      c.box(w=Px(1.0), h=Px(40.0), fn() { @kit.separator(c, vertical=true) }) |> ignore
      c.box(w=Px(80.0), gap=6.0, fn() {
        c.text("Above", size=t.font_sm, wrap=false) |> ignore
        @kit.separator(c)
        c.text("Below", size=t.font_sm, wrap=false) |> ignore
      })
      |> ignore
      @kit.accessible_icon(c, "Favourite", fn() { c.text("★", size=20.0, color=t.accent, wrap=false) |> ignore })
    })
  })
}
