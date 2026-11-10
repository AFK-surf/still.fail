// A place in a panel's foot that comes and goes (foot_place_node) beside the old foot drawing a button or not each frame:
// one button and two, at a sheet's foot with a finger and with a mouse and at a dialog's in the middle of a window, each
// where the old one's is and as wide; one going, the other's width at once.

///|
/// Where each of the foot's buttons stands (by its words), a panel opened by nothing on a window `at`, its foot holding 稍后
/// while `two` says so and 下载 always: the old foot's (`old`), else the node foot's (foot_place_node), at rest; then,
/// `two` turned, at that frame and at rest. Closed after, gone.
fn foot_place_stood(at : (Int, Double, Double), old : Bool) -> Array[String] raise {
  let two = @signals.signal(true)
  let open = fn(_from : Anchor) {
    if old {
      panel("一个", from=Unanchored, fn(c, _) { c.text("它说的话", style=secondary) |> ignore }, foot=fn(c, _) {
        if two.get() {
          button(c, "稍后", key="foot-place/later", tone=Ghost)
        }
        button(c, "下载", key="foot-place/go", tone=Primary)
      })
    } else {
      panel_nodes(
        "一个",
        from=Unanchored,
        fn(v, _) { words_node(v, fn() { "它说的话" }, fn() { secondary }) |> ignore },
        foot=fn(v, _) {
          foot_place_node(v, fn() { two.get() }, fn(p) { button_node(p, fn() { "稍后" }, fn() {  }, tone=Ghost) |> ignore })
          button_node(v, fn() { "下载" }, fn() {  }, tone=Primary) |> ignore
        },
      )
    }
  }
  presenters_reset()
  let (platform, w, h) = at
  let t = @ui.Tester::new(
    fn(c) { c.with_theme(ui_theme(), fn() { @ui.old_views_here(c) }) },
    tree=presented_tree(presenting_view(open)),
    w~,
    h~,
    platform~,
  )
  t.check_looks(false)
  t.draw()
  t.tap_text("打开")
  t.run_for(@ui.move_most_ms)
  t.leave()
  t.draw()
  let k = fn(v : Double) { (v * 1000.0).round() / 1000.0 }
  let stood : Array[String] = []
  let say = fn(when : String) {
    for label in ["稍后", "下载"] {
      let all = t.all(Button, label~)
      let r = if all.length() == 1 { "\{k(all[0].rect.0)},\{k(all[0].rect.1)} \{k(all[0].rect.2)}x\{k(all[0].rect.3)}" } else { "\{all.length()} of it" }
      stood.push("\{when}: \{label} \{r}")
    }
  }
  say("two")
  two.set(false)
  t.draw()
  say("one, at once")
  t.run_for(@ui.move_most_ms)
  say("one")
  two.set(true)
  t.draw()
  say("two again, at once")
  close_all_presented()
  t.run_for(@ui.move_most_ms)
  assert_false(presented_drawn(), msg="closed")
  stood
}

///|
test "a place in a panel's foot that comes and goes, where the old foot draws a button or not: a sheet's with a finger and with a mouse, a dialog's in the middle of a window" {
  for screen in [("sheet", phone), ("sheet, with a mouse", (0, 390.0, 844.0)), ("dialog", (0, 800.0, 600.0))] {
    let (about, at) = screen
    let old = foot_place_stood(at, true)
    let new = foot_place_stood(at, false)
    let differs : Array[String] = []
    for i, line in old {
      let n = new.get(i).unwrap_or("-")
      if n != line {
        differs.push("\{about}: old \{line} / new \{n}")
      }
    }
    if !differs.is_empty() || new.length() != old.length() {
      fail(differs.join(" | "))
    }
  }
}

///|
test "a place in a sheet's foot takes a button's share whatever it holds: words alone in it, the button beside it as wide as beside a button" {
  // (下载's place beside a place holding a button, then beside one holding words alone: the same)
  let stood = fn(words_only : Bool) -> String raise {
    let open = fn(_from : Anchor) {
      panel_nodes(
        "一个",
        from=Unanchored,
        fn(v, _) { words_node(v, fn() { "它说的话" }, fn() { secondary }) |> ignore },
        foot=fn(v, _) {
          foot_place_node(v, fn() { true }, fn(p) {
            if words_only {
              words_node(p, fn() { "稍后" }, fn() { secondary }) |> ignore
            } else {
              button_node(p, fn() { "稍后" }, fn() {  }, tone=Ghost) |> ignore
            }
          })
          button_node(v, fn() { "下载" }, fn() {  }, tone=Primary) |> ignore
        },
      )
    }
    presenters_reset()
    let t = @ui.Tester::new(
      fn(c) { c.with_theme(ui_theme(), fn() { @ui.old_views_here(c) }) },
      tree=presented_tree(presenting_view(open)),
      w=phone.1,
      h=phone.2,
      platform=phone.0,
    )
    t.check_looks(false)
    t.draw()
    t.tap_text("打开")
    t.run_for(@ui.move_most_ms)
    let all = t.all(Button, label="下载")
    assert_eq(all.length(), 1)
    let r = all[0].rect
    close_all_presented()
    t.run_for(@ui.move_most_ms)
    assert_false(presented_drawn(), msg="closed")
    "\{r.0},\{r.1} \{r.2}x\{r.3}"
  }
  assert_eq(stood(true), stood(false))
}
