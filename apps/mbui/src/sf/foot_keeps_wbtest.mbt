// A sheet's foot of two buttons, the old foot's (each Fill, kept: never narrower than what it holds) beside one of nodes
// (button_node there, in a foot_place_node or not): each its share while both fit; one whose words need more than its
// share as wide as they need, the other giving way, none of them cut; at the system's size of words and larger.

///|
/// Where each of a sheet's foot's two buttons stands, `first` and `second` their words (the second in a place that comes
/// and goes where `place`), on a phone with a finger, the system's size of words `fs`: the old foot's (`old`), else the
/// node foot's; and what is cut short or off (the node foot's: squeeze_faults). Closed after, gone.
fn foot_keeps_stood(
  old : Bool,
  first : String,
  second : String,
  fs : Double,
  place : Bool,
  at? : (Int, Double, Double) = phone,
  beside? : Bool = false,
) -> (Array[String], Array[String]) raise {
  let open = fn(opener : Anchor) {
    let from = if beside { opener } else { Unanchored }
    if old {
      panel("一个", from~, fn(c, _) { c.text("它说的话", style=secondary) |> ignore }, foot=fn(c, _) {
        button(c, first, key="foot-keeps/a", tone=Ghost)
        button(c, second, key="foot-keeps/b", tone=Primary)
      })
    } else {
      panel_nodes(
        "一个",
        from~,
        fn(v, _) { words_node(v, fn() { "它说的话" }, fn() { secondary }) |> ignore },
        foot=fn(v, _) {
          button_node(v, fn() { first }, fn() {  }, tone=Ghost) |> ignore
          if place {
            foot_place_node(v, fn() { true }, fn(p) { button_node(p, fn() { second }, fn() {  }, tone=Primary) |> ignore })
          } else {
            button_node(v, fn() { second }, fn() {  }, tone=Primary) |> ignore
          }
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
  if fs != 1.0 {
    t.set_font_scale(fs)
  }
  t.draw()
  t.tap_text("打开")
  t.run_for(@ui.move_most_ms)
  t.leave()
  t.draw()
  let k = fn(v : Double) { (v * 1000.0).round() / 1000.0 }
  let stood = [first, second].map(fn(label) {
    let all = t.all(Button, label~)
    if all.length() == 1 {
      let r = all[0].rect
      "\{label} \{k(r.0)},\{k(r.1)} \{k(r.2)}x\{k(r.3)}"
    } else {
      "\{label}: \{all.length()} of it"
    }
  })
  let cut = t.squeeze_faults()
  close_all_presented()
  t.run_for(@ui.move_most_ms)
  assert_false(presented_drawn(), msg="closed")
  (stood, cut)
}

///|
test "a sheet's foot of nodes: two buttons whose words fit, each its share, as the old foot's" {
  for place in [false, true] {
    for fs in [1.0, 1.3] {
      let at = "place \{place}, words \{fs}"
      let (old, _) = foot_keeps_stood(true, "取消", "下载", fs, place)
      let (new, cut) = foot_keeps_stood(false, "取消", "下载", fs, place)
      assert_eq(new, old, msg=at)
      assert_eq(cut, [], msg=at)
    }
  }
}

///|
test "a sheet's foot of nodes: one button's words more than its share, it as wide as they need and the other giving way, none cut, as the old foot's" {
  for place in [false, true] {
    for words in [("取消", "添加到此 workspace", 1.3), ("Cancel", "Add to this workspace", 1.3), ("取消", "添加到此 workspace，然后再看一看", 1.0)] {
      let (first, second, fs) = words
      let at = "place \{place}, \{second} at \{fs}"
      let (old, _) = foot_keeps_stood(true, first, second, fs, place)
      let (new, cut) = foot_keeps_stood(false, first, second, fs, place)
      assert_eq(new, old, msg=at)
      assert_eq(cut, [], msg=at)
    }
  }
}

///|
test "a sheet's foot of nodes: both buttons' words more than the foot has room for, laid out as the old foot's" {
  for place in [false, true] {
    let (first, second) = ("先取消这一次的添加然后", "添加到此 workspace，然后再看一看")
    let at = "place \{place}"
    let (old, old_cut) = foot_keeps_stood(true, first, second, 1.3, place)
    let (new, cut) = foot_keeps_stood(false, first, second, 1.3, place)
    assert_eq(new, old, msg="\{at}: old \{Repr(old)} cut \{Repr(old_cut)}; new \{Repr(new)} cut \{Repr(cut)}")
  }
}

///|
test "a dialog's foot in the middle of a window and a panel's beside what opened it: buttons whose words are long, as the old ones'" {
  for screen in [("dialog", false), ("beside", true)] {
    let (about, beside) = screen
    for place in [false, true] {
      for words in [("取消", "添加到此 workspace，然后再看一看"), ("先取消这一次的添加然后再说", "添加到此 workspace，然后再看一看，再看一看")] {
        let (first, second) = words
        let at = "\{about}, place \{place}, \{second}"
        let (old, old_cut) = foot_keeps_stood(true, first, second, 1.3, place, at=(0, 800.0, 600.0), beside~)
        let (new, cut) = foot_keeps_stood(false, first, second, 1.3, place, at=(0, 800.0, 600.0), beside~)
        assert_eq(new, old, msg="\{at}: old \{Repr(old)} cut \{Repr(old_cut)}; new \{Repr(new)} cut \{Repr(cut)}")
      }
    }
  }
}
