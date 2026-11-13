// Comma's floating parts and the rest of its base parts as the hand, the keyboard and a screen reader meet them: a menu
// opened, walked by the arrow keys, done by Enter and shut by Escape; a dropdown's choice; a dialog over all, shut by
// Escape or its scrim; a tooltip by the keyboard's focus; a toast gone at its time; a slider stepped; a collapse opened;
// a button group's and a radio group's choice; and all of it open at once held to mbui's audit.

///|
/// A Tester of a 1000 × 700 window in Comma's theme, its layer made first, `make` making the page; drawn.
fn floating_case(make : (@view.View, Layer) -> Unit, dark? : Bool = false) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=1000.0, h=700.0, platform=0)
  set_dark(Some(dark))
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme)
    let layer = Layer::new()
    layer_node(root, layer)
    root.box(fn(w) {
      w.grow(Is(1.0)).ground(By(fn() { colors().bg_primary })) |> ignore
      w.box(fn(page) {
        page.grow(Is(1.0)).padding(Is((24.0, 24.0, 24.0, 24.0))).gap(Is(12.0)) |> ignore
        make(page, layer)
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// How long a floating part takes at most to come or go (the longest of Comma's enter and exit durations it uses).
let floating_ms : Double = 400.0

///|
test "a menu opens from its button, its rows walked by the arrow keys, Enter doing one and shutting it, Escape shutting it" {
  let open = @signals.signal(false)
  let done = Ref([])
  let t = floating_case(fn(p, layer) {
    let a = button_node(p, fn() { "Options" }, fn() { open.set(true) }, hierarchy=SecondaryGray)
    menu_node(layer, a, open, fn() {
      [menu_item("Profile", fn() { done.val.push("Profile") }), menu_item("Settings", fn() { done.val.push("Settings") })]
    })
  })
  t.act(Button, Activate, label="Options")
  t.run_for(floating_ms)
  let shown = t.all(Menu, label="Menu").length()
  t.key(@ui.key_code_down)
  t.key(@ui.key_code_down)
  t.key(@ui.key_code_enter)
  t.run_for(floating_ms)
  let after_enter = (open.get(), t.all(Menu, label="Menu").length())
  t.act(Button, Activate, label="Options")
  t.run_for(floating_ms)
  t.key(@ui.key_escape)
  t.run_for(floating_ms)
  assert_eq((shown, done.val, after_enter, open.get()), (1, ["Settings"], (false, 0), false))
}

///|
test "a dropdown's trigger opens its list; an option activated is chosen, read out as the trigger's value, and the list shut" {
  let chosen = @signals.signal(-1)
  let t = floating_case(fn(p, layer) {
    p.box(fn(b) {
      b.width(Is(Some(240.0))) |> ignore
      dropdown_node(b, layer, ["Light", "Dark", "System"], chosen, label="Appearance") |> ignore
    })
    |> ignore
  })
  let before = t.get(Combobox, label="Appearance").value
  t.act(Combobox, Activate, label="Appearance")
  t.run_for(floating_ms)
  t.act(MenuItem, Activate, label="Dark")
  t.run_for(floating_ms)
  assert_eq(
    (before, chosen.get(), t.get(Combobox, label="Appearance").value, t.all(Listbox, label="Appearance").length()),
    ("", 1, "Dark", 0),
  )
}

///|
test "a dialog takes all input over the page while it is open; Escape shuts it, and so does a press on its scrim" {
  let open = @signals.signal(false)
  let t = floating_case(fn(p, layer) {
    button_node(p, fn() { "Delete" }, fn() { open.set(true) }, hierarchy=Destructive) |> ignore
    dialog_node(layer, open, fn() { "Delete this project?" }, actions=fn(f) {
      button_node(f, fn() { "Cancel" }, fn() { open.set(false) }, hierarchy=SecondaryGray, size=Sm) |> ignore
    })
  })
  t.act(Button, Activate, label="Delete")
  t.run_for(floating_ms)
  let shown = t.all(Dialog, label="Delete this project?").length()
  t.key(@ui.key_escape)
  t.run_for(floating_ms)
  let escaped = (open.get(), t.all(Dialog, label="Delete this project?").length())
  t.act(Button, Activate, label="Delete")
  t.run_for(floating_ms)
  t.act(Button, Activate, label="Close dialog")
  t.run_for(floating_ms)
  assert_eq((shown, escaped, open.get()), (1, (false, 0), false))
}

///|
test "a tooltip shows as the keyboard's focus comes on its control, and goes as it leaves" {
  let t = floating_case(fn(p, layer) {
    let a = button_node(p, fn() { "Save" }, fn() {  })
    tooltip_node(layer, a, fn() { "Save the draft" })
    button_node(p, fn() { "Next" }, fn() {  }) |> ignore
  })
  t.tab()
  t.run_for(floating_ms)
  let shown = t.all(Tooltip, label="Save the draft").length()
  t.tab()
  t.run_for(floating_ms)
  assert_eq((shown, t.all(Tooltip, label="Save the draft").length()), (1, 0))
}

///|
test "a toast stays its time and is gone after it; its Dismiss takes it away before" {
  let toaster = Toaster::new()
  let t = floating_case(fn(p, layer) {
    button_node(p, fn() { "Save" }, fn() { toaster.show("Changes saved", intent=Success) }) |> ignore
    button_node(p, fn() { "Fail" }, fn() { toaster.show("Upload failed", intent=Error) }) |> ignore
    toaster_node(layer, toaster)
  })
  t.act(Button, Activate, label="Save")
  t.run_for(floating_ms)
  let shown = t.all(Status, label="Changes saved").length()
  t.run_for(toast_stays)
  let after = t.all(Status, label="Changes saved").length()
  t.act(Button, Activate, label="Fail")
  t.run_for(floating_ms)
  t.act(Button, Activate, label="Dismiss")
  t.run_for(floating_ms)
  assert_eq((shown, after, t.all(Status, label="Upload failed").length()), (1, 0, 0))
}

///|
test "a slider steps by a screen reader's Increment and Decrement and by the arrow keys, kept in its range" {
  let value = @signals.signal(98.0)
  let t = floating_case(fn(p, _) {
    p.box(fn(b) {
      b.width(Is(Some(320.0))) |> ignore
      slider_node(b, value, fn() { "Volume" }) |> ignore
    })
    |> ignore
  })
  t.act(Slider, Increment, label="Volume")
  t.act(Slider, Increment, label="Volume")
  t.act(Slider, Increment, label="Volume")
  let top = value.get()
  t.tab()
  t.key(@ui.key_code_left)
  t.key(@ui.key_code_home)
  t.key(@ui.key_code_right)
  assert_eq((top, value.get(), t.get(Slider, label="Volume").range), (100.0, 1.0, Some((0.0, 100.0, 1.0))))
}

///|
test "a collapse opens and shuts what it holds as its title is activated, read out expanded or not" {
  let open = @signals.signal(false)
  let t = floating_case(fn(p, _) {
    collapse_node(p, fn() { "Details" }, open, fn(b) {
      b.words(Is("Hidden words"), look=words_in(type_small)) |> ignore
    })
    |> ignore
  })
  let shut = (t.get(Button, label="Details").expanded, t.words().iter().any(fn(w) { w.0 == "Hidden words" }))
  t.act(Button, Activate, label="Details")
  t.run_for(floating_ms)
  assert_eq((shut, t.get(Button, label="Details").expanded, t.words().iter().any(fn(w) { w.0 == "Hidden words" })), ((Some(false), false), Some(true), true))
}

///|
test "a button group and a radio group choose as one of theirs is activated" {
  let (segment, plan) = (@signals.signal(0), @signals.signal(0))
  let t = floating_case(fn(p, _) {
    button_group_node(p, ["Day", "Week", "Month"], segment) |> ignore
    radio_group_node(p, [("Basic", ""), ("Business", "")], plan, label="Plan") |> ignore
  })
  t.act(Button, Activate, label="Month")
  t.act(Radio, Activate, label="Business")
  assert_eq(
    (segment.get(), t.get(Button, label="Month").pressed, plan.get(), t.get(Radio, label="Business").check),
    (2, Some(true), 1, Some(On)),
  )
}

///|
test "every one of these parts, its floating ones open, light and dark, holds to mbui's audit" {
  let faults = []
  for dark in [false, true] {
    let toaster = Toaster::new()
    let t = floating_case(dark~, fn(p, layer) {
      p.box(fn(r) {
        r.row(Is(true)).gap(Is(12.0)).lines_up(Is(Some(Start))) |> ignore
        let a = button_node(r, fn() { "Options" }, fn() {  }, hierarchy=SecondaryGray)
        menu_node(layer, a, @signals.signal(true), fn() { [menu_item("Profile", fn() {  }, checked=true), menu_item("Log out", fn() {  }, danger=true, divided=true)] })
        let b = button_node(r, fn() { "Help" }, fn() {  }, hierarchy=TertiaryGray)
        tooltip_node(layer, b, fn() { "Get help" }, shown=fn() { true })
        button_group_node(r, ["Day", "Week"], @signals.signal(0)) |> ignore
      })
      |> ignore
      p.box(fn(r) {
        r.row(Is(true)).gap(Is(24.0)).lines_up(Is(Some(Start))).margin(Is((0.0, 120.0, 0.0, 0.0))) |> ignore
        radio_group_node(r, [("Basic", "Up to 10 users.")], @signals.signal(0), label="Plan") |> ignore
        check_group_node(r, [("Email", "")], @signals.signal([true]), label="Notify") |> ignore
        r.box(fn(s) {
          s.width(Is(Some(200.0))) |> ignore
          slider_node(s, @signals.signal(40.0), fn() { "Volume" }, width=200.0) |> ignore
        })
        |> ignore
        indicator_node(r, Good, "Online") |> ignore
      })
      |> ignore
      collapse_node(p, fn() { "Details" }, @signals.signal(true), fn(b) {
        b.words(Is("More"), look=words_in(type_small)).ink(By(fn() { colors().text_tertiary })) |> ignore
      })
      |> ignore
      toaster_node(layer, toaster)
      toaster.show("Changes saved", intent=Success)
    })
    t.run_for(floating_ms)
    for f in t.audit() {
      faults.push((dark, f))
    }
  }
  assert_eq(faults, [])
}

///|
/// What of Comma's own design falls short of mbui's contrast rule (4.5:1 for words): a dialog's description, xs in the
/// quaternary's on popup-primary, 3.86:1 in the light (Cue's dialog/styles.ts). Drawn as Comma says; held here so it is
/// seen, not mended in this library alone.
let comma_contrast_known : Array[String] = ["\"It cannot be undone.\""]

///|
test "a dialog open, light and dark, holds to mbui's audit but for Comma's own description's contrast" {
  let (faults, known) = ([], [])
  for dark in [false, true] {
    let t = floating_case(dark~, fn(p, layer) {
      button_node(p, fn() { "Delete" }, fn() {  }, hierarchy=Destructive) |> ignore
      dialog_node(layer, @signals.signal(true), fn() { "Delete this project?" }, description=fn() { "It cannot be undone." }, actions=fn(f) {
        button_node(f, fn() { "Cancel" }, fn() {  }, hierarchy=SecondaryGray, size=Sm) |> ignore
        button_node(f, fn() { "Delete" }, fn() {  }, hierarchy=Destructive, size=Sm) |> ignore
      })
    })
    t.run_for(floating_ms)
    for f in t.audit() {
      if comma_contrast_known.iter().any(fn(k) { f.contains(k) && f.contains("under 4.5") }) {
        known.push(dark)
      } else {
        faults.push((dark, f))
      }
    }
  }
  assert_eq((faults, known), ([], [false]))
}
