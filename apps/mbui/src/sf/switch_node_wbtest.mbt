// A switch's row as nodes (switch_row_node, its switch switch_node's) beside the old view's (switch_row), with keyboard
// and mouse and with a finger: Tab takes the focus to the switch, read out a switch by its name, on or off; Space and
// Enter turn it; a screen reader finds one switch, the press's room the same; the ring of the keys' focus round its
// track; while it takes no press, Tab passes it over and the keys turn nothing.

///|
/// A row with a switch named 性能记录 alone in a window 390 by 300 with input `platform`, as nodes (`node`) or as the old
/// view's, `on` as it is, turned as it is pressed, taking none while `disabled`.
fn switch_tester(node : Bool, platform : Int, on : @signals.Signal[Bool], disabled : Bool) -> @ui.Tester {
  let t = if node {
    @ui.Tester::new(fn(_c) {  }, w=390.0, h=300.0, platform~)
  } else {
    @ui.Tester::new(
      fn(c) {
        c.box(style=@ui.css("w=Full"), fn() {
          let now = switch_row(c, "p", "性能记录", on.get(), note="保存在本机", disabled~)
          if now != on.get() {
            on.set(now)
          }
        })
        |> ignore
      },
      w=390.0,
      h=300.0,
      platform~,
    )
  }
  if node {
    @ui.set_view_app(fn(root) {
      root.box(fn(b) {
        switch_row_node(b, fn() { "性能记录" }, fn() { on.get() }, fn(to) { on.set(to) }, note=fn() { "保存在本机" }, disabled=fn() {
          disabled
        })
      })
      |> ignore
    })
  }
  t.draw()
  t
}

///|
/// What a switch's row answers the keys and a screen reader with: the switches read out (each its name, whether on,
/// whether it takes none, its size), what Tab reads out (where it is said off the switch's place), the focus ring's
/// place and size off the switch's, whether a press's room is the switch's own, and whether it is on after Space, then
/// after Enter.
fn switch_said(node : Bool, platform : Int, disabled : Bool) -> Array[String] {
  let on = @signals.signal(false)
  let t = switch_tester(node, platform, on, disabled)
  let out = []
  let switches = t.semantics().filter(fn(n) { n.role == Switch && !n.hidden })
  for n in switches {
    out.push("switch \{n.label} \{@ui.some_text(n.check)} disabled \{n.disabled} \{n.rect.2}x\{n.rect.3}")
  }
  guard switches.length() == 1 else { return out }
  let (sx, sy, sw, sh) = switches[0].rect
  t.key(@ui.key_tab)
  t.frame()
  out.push("tab: " + t.focused().map(fn(n) { "\{n.role} \{n.label} \{@ui.some_text(n.check)} at \{n.rect.0 - sx},\{n.rect.1 - sy}" }).unwrap_or("none"))
  for b in t.boxes_held() {
    if b.border_w > 0.0 {
      out.push("ring at \{b.x - sx},\{b.y - sy} \{b.w}x\{b.h} round \{b.radius} line \{b.border_w}")
    }
    if b.hit {
      out.push("pressed at \{b.x - sx},\{b.y - sy} \{b.w}x\{b.h} of the switch's \{sw}x\{sh}")
    }
  }
  t.key(@ui.key_space)
  t.frame()
  out.push("space: on \{on.get()}")
  t.enter()
  t.frame()
  out.push("enter: on \{on.get()}")
  out
}

///|
test "a switch's row as nodes, with keyboard and mouse and with a finger: Tab to it reads out a switch by its name, off; Space turns it on, Enter off; one switch to a screen reader, as big as its press's room; the ring round its track; as the old view's" {
  for platform in [0, 2] {
    let made = switch_said(true, platform, false)
    let old = switch_said(false, platform, false)
    assert_eq(made, old, msg="platform \{platform}: as nodes \{Repr(made)}, as the old view's \{Repr(old)}")
    assert_true(made.contains("tab: Switch 性能记录 Some(Off) at 0,0"), msg="platform \{platform}: \{Repr(made)}")
    assert_true(made.contains("space: on true") && made.contains("enter: on false"), msg="platform \{platform}: \{Repr(made)}")
  }
}

///|
test "a switch's row as nodes taking no press: read out disabled, Tab passing it over, Space and Enter turning nothing, as the old view's" {
  for platform in [0, 2] {
    let made = switch_said(true, platform, true)
    let old = switch_said(false, platform, true)
    assert_eq(made, old, msg="platform \{platform}: as nodes \{Repr(made)}, as the old view's \{Repr(old)}")
    assert_true(made.contains("tab: none") && made.contains("space: on false"), msg="platform \{platform}: \{Repr(made)}")
  }
}
