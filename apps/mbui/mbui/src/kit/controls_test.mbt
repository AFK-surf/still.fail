// Batch 1's controls driven as a person and a screen reader drive them, the values kept by the test (the view's),
// read back through the semantics tree.

///|
test "switch: a tap turns it, the view keeps it; Activate too; disabled, nothing does" {
  let on = Ref(false)
  let off = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    c.column(gap=8.0, fn() {
      on.val = switch(c, "wifi", on.val, label="Wi-Fi").value
      ignore(switch(c, "air", off.val, label="Airplane", disabled=true))
    })
    |> ignore
  })
  t.click(@ui.Role::Switch, label="Wi-Fi")
  assert_true(on.val)
  assert_eq(t.get(@ui.Role::Switch, label="Wi-Fi").check, Some(@ui.Check::On))
  t.act(@ui.Role::Switch, @ui.Action::Activate, label="Wi-Fi")
  assert_false(on.val)
  t.click(@ui.Role::Switch, label="Airplane")
  assert_false(off.val)
}

///|
test "checkbox: a click checks it; Space with the focus unchecks it; neither (mixed) goes to checked" {
  let v : Ref[@ui.Check] = Ref(@ui.Check::Off)
  let t = @ui.Tester::new(fn(c) { v.val = checkbox(c, "terms", v.val, label="Terms").value })
  t.click(@ui.Role::Checkbox, label="Terms")
  assert_eq(v.val, @ui.Check::On)
  t.key(@ui.key_tab)
  t.key(@ui.key_space)
  assert_eq(v.val, @ui.Check::Off)
  v.val = @ui.Check::Mixed
  t.frame()
  t.click(@ui.Role::Checkbox, label="Terms")
  assert_eq(v.val, @ui.Check::On)
}

///|
test "radio group: a tap checks one; the arrows move the focus along it and check what they reach, wrapping" {
  let v = Ref("a")
  let t = @ui.Tester::new(fn(c) {
    v.val = radio_group(c, "size", [item("a", label="Small"), item("b", label="Medium"), item("c", label="Large")], v.val, label="Size").value
  })
  t.click(@ui.Role::Radio, label="Large")
  assert_eq(v.val, "c")
  // Tab lands on the checked one; Down from the last wraps to the first
  t.key(@ui.key_tab)
  t.key(@ui.key_code_down)
  assert_eq(v.val, "a")
  t.key(@ui.key_code_down)
  assert_eq(v.val, "b")
  assert_eq(t.get(@ui.Role::Radio, label="Medium").check, Some(@ui.Check::On))
  assert_eq(t.get(@ui.Role::Radio, label="Small").check, Some(@ui.Check::Off))
}

///|
test "toggle group: single, a tap picks one and a second tap lets it go; multiple, each on its own" {
  let one : Ref[Array[String]] = Ref([])
  let many : Ref[Array[String]] = Ref([])
  let t = @ui.Tester::new(fn(c) {
    c.column(gap=8.0, fn() {
      one.val = toggle_group(c, "align", [item("l", label="Left"), item("r", label="Right")], one.val, label="Align").value
      many.val = toggle_group(
        c,
        "fmt",
        [item("b", label="Bold"), item("i", label="Italic")],
        many.val,
        multiple=true,
        label="Format",
      ).value
    })
    |> ignore
  })
  t.click(@ui.Role::Radio, label="Left")
  assert_eq(one.val, ["l"])
  t.click(@ui.Role::Radio, label="Right")
  assert_eq(one.val, ["r"])
  t.click(@ui.Role::Radio, label="Right")
  assert_eq(one.val, [])
  t.click(@ui.Role::Button, label="Bold")
  t.click(@ui.Role::Button, label="Italic")
  assert_eq(many.val, ["b", "i"])
}

///|
test "toggle group that slides: its thumb behind the pressed item, getting there on a spring" {
  let v : Ref[Array[String]] = Ref(["l"])
  let t = @ui.Tester::new(fn(c) {
    c.box(pad=20.0, fn() {
      v.val = toggle_group(
        c,
        "seg",
        [item("l", label="Left"), item("m", label="Middle"), item("r", label="Right")],
        v.val,
        slide=true,
        thumb=fn(c, w, h) { c.box(w=Px(w), h=Px(h), bg=0x123456FFL, fn() {  }) |> ignore },
        label="Seg",
      ).value
    })
    |> ignore
  })
  // (the thumb is placed over its item once the items are laid out: a layout read back, drawn now)
  t.draw()
  let thumb = fn() {
    t.drawn_rects().filter(fn(r) { r.4 == 0x123456FFL }).map(fn(r) { (r.0.round(), r.1.round(), r.2.round(), r.3.round()) })
  }
  let under = fn(s : String) {
    let (x, y, w, h) = t.rect_of(s).unwrap()
    match thumb() {
      [(tx, ty, tw, th)] => tx <= x && x + w <= tx + tw && ty <= y && y + h <= ty + th
      _ => false
    }
  }
  assert_true(under("Left"))
  t.click(@ui.Role::Radio, label="Right")
  assert_eq(v.val, ["r"])
  // the thumb on its spring, set out from rest as the click was taken: there once its slide is over
  t.run_for(@ui.cover_slide_ms)
  assert_true(under("Right"))
  assert_false(under("Left"))
  // the view's choice: on its way a tenth of its slide's time, not yet under the words it goes to
  v.val = ["m"]
  t.draw()
  let part_way = @ui.cover_slide_ms / 10.0
  t.run_for(part_way)
  assert_false(under("Middle"))
  t.run_for(@ui.cover_slide_ms - part_way)
  assert_true(under("Middle"))
  t.assert_idle()
}

///|
/// A sliding group (its thumb drawn 0x123456) in a box that cuts what is outside it, moved `x` sideways; what is
/// pressed in `v`, the last item's words in `last`.
fn slid_group(x : Ref[Double], v : Ref[Array[String]], last? : Ref[String] = Ref("Right")) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), h=Fill(1.0), clip=true, fn() {
        c.box(tx=x.val, fn() {
          v.val = toggle_group(
            c,
            "seg",
            [item("l", label="Left"), item("m", label="Middle"), item("r", label=last.val)],
            v.val,
            slide=true,
            thumb=fn(c, w, h) { c.box(w=Px(w), h=Px(h), bg=0x123456FFL, fn() {  }) |> ignore },
            label="Seg",
          ).value
        })
        |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=200.0,
  )
}

///|
/// The thumb's box (x, y, w, h), drawn once.
fn thumb_of(t : @ui.Tester) -> (Double, Double, Double, Double) {
  let rs = t.drawn_rects().filter(fn(r) { r.4 == 0x123456FFL })
  if rs.length() != 1 {
    abort("the thumb drawn \{rs.length()} times")
  }
  (rs[0].0, rs[0].1, rs[0].2, rs[0].3)
}

///|
/// Whether the thumb is where the words `s` are, to a hundredth of a point either way.
fn thumb_on(t : @ui.Tester, s : String) -> Bool {
  let (x, _, w, _) = thumb_of(t)
  let (ix, _, iw, _) = t.rect_of(s).unwrap()
  x <= ix + 0.01 && ix + iw <= x + w + 0.01
}

///|
test "a sliding group coming in past an edge that cuts it: its thumb whole from the first, nothing to grow on after" {
  // (a page sliding in: the group's last item cut at the edge from the first frame, halfway across it)
  let (rx, rw, full) = {
    let at_rest = slid_group(Ref(0.0), Ref(["r"]))
    at_rest.draw()
    let (rx, _, rw, _) = at_rest.rect_of("Right").unwrap()
    (rx, rw, thumb_of(at_rest).2)
  }
  let x = Ref(300.0 - rx - rw / 2.0)
  let v = Ref(["r"])
  let t = slid_group(x, v)
  t.draw()
  let (_, _, w0, _) = thumb_of(t)
  assert_eq(w0, full)
  x.val = 0.0
  t.draw()
  let (_, _, w1, _) = thumb_of(t)
  assert_eq(w0, w1)
  assert_true(thumb_on(t, "Right"))
  t.assert_idle()
}

///|
test "the pressed item laid out anew (its words longer): its thumb on it in the same frame, no motion" {
  let last = Ref("Right")
  let t = slid_group(Ref(0.0), Ref(["r"]), last~)
  t.draw()
  last.val = "Right of it"
  t.draw()
  assert_true(thumb_on(t, "Right of it"))
  t.assert_idle()
}

///|
test "another item pressed: the thumb on its way between the two, and another chosen mid-way it goes on from there" {
  // a moment on its way
  let mid_way = 60.0
  let on_its_way = fn(v : Ref[Array[String]]) -> @ui.Tester raise {
    let t = slid_group(Ref(0.0), v)
    t.draw()
    t.click(@ui.Role::Radio, label="Right")
    assert_eq(v.val, ["r"])
    t.run_for(mid_way)
    assert_false(thumb_on(t, "Left"))
    assert_false(thumb_on(t, "Right"))
    t
  }
  // where it is the frame after, nothing else chosen: still on its way to Right
  let going_on = {
    let t = on_its_way(Ref(["l"]))
    t.draw()
    thumb_of(t)
  }
  let v = Ref(["l"])
  let t = on_its_way(v)
  let before = thumb_of(t)
  // another chosen (the view's choice), the frame that takes it: from where it is in that frame, not from an item; the
  // same frame as going on would have shown, not a jump
  v.val = ["m"]
  t.draw()
  let after = thumb_of(t)
  assert_true((after.0 - going_on.0).abs() < 0.000001 && (after.2 - going_on.2).abs() < 0.000001)
  assert_true(after != before)
  t.run_for(@ui.cover_slide_ms)
  assert_true(thumb_on(t, "Middle"))
  t.assert_idle()
}

///|
test "slider: the arrows a step, Page keys ten, Home and End the ends; Increment and Decrement; held in range" {
  let v = Ref(50.0)
  let t = @ui.Tester::new(fn(c) {
    v.val = slider(c, "vol", v.val, min=0.0, max=100.0, step=5.0, label="Volume").value
  })
  t.key(@ui.key_tab)
  t.key(@ui.key_code_right)
  assert_eq(v.val, 55.0)
  t.key(@ui.key_code_down)
  assert_eq(v.val, 50.0)
  t.key(@ui.key_code_page_up)
  assert_eq(v.val, 100.0)
  t.key(@ui.key_code_right)
  assert_eq(v.val, 100.0)
  t.key(@ui.key_code_home)
  assert_eq(v.val, 0.0)
  t.act(@ui.Role::Slider, @ui.Action::Increment, label="Volume")
  assert_eq(v.val, 5.0)
  t.act(@ui.Role::Slider, @ui.Action::Decrement, label="Volume")
  t.act(@ui.Role::Slider, @ui.Action::Decrement, label="Volume")
  assert_eq(v.val, 0.0)
  let s = t.get(@ui.Role::Slider, label="Volume")
  assert_eq(s.value, "0")
  assert_eq(s.range, Some((0.0, 0.0, 100.0)), msg="its least, where it is, its most")
  let told = t.ctx().a11y_lines().split("\n").filter(fn(l) { l.contains("Slider") }).to_array()
  let f = told[0].split("\u{1F}").map(fn(v) { v.to_string() }).to_array()
  assert_eq([f[12], f[13], f[14]], [(0.0).to_string(), (0.0).to_string(), (100.0).to_string()], msg="told the host so")
}

///|
test "slider: a tap on its track sets the value even when no frame is drawn while pressed" {
  let v = Ref(20.0)
  let t = @ui.Tester::new(fn(c) {
    v.val = slider(c, "s", v.val, w=Px(240.0), label="Volume").value
  }, platform=2)
  let (x, y, w, h) = t.get(@ui.Role::Slider, label="Volume").rect
  t.tap(x + w * 0.75, y + h / 2.0)
  assert_true(v.val > 20.0, msg="a tap sets the slider")
}

///|
test "slider: a drag between frames sets the value where it ends" {
  let v = Ref(20.0)
  let t = @ui.Tester::new(fn(c) {
    v.val = slider(c, "s", v.val, w=Px(240.0), label="Volume").value
  }, platform=2)
  let (x, y, w, h) = t.get(@ui.Role::Slider, label="Volume").rect
  t.touch(0, x + w * 0.2, y + h / 2.0)
  t.touch(1, x + w * 0.75, y + h / 2.0)
  t.touch(2, x + w * 0.75, y + h / 2.0)
  t.draw()
  assert_true(v.val > 60.0, msg="a drag sets the slider where it ends")
}

///|
test "slider: dragged along its track, it follows the pointer to the nearest step; right to left, mirrored" {
  let v = Ref(0.0)
  let t = @ui.Tester::new(fn(c) {
    v.val = slider(c, "s", v.val, min=0.0, max=10.0, step=1.0, w=Px(200.0), label="S").value
  })
  let (x, y, w, h) = t.get(@ui.Role::Slider, label="S").rect
  t.drag(x + 1.0, y + h / 2.0, x + w * 0.7, y + h / 2.0)
  assert_eq(v.val, 7.0)
  t.drag(x + w * 0.7, y + h / 2.0, x + w * 0.2, y + h / 2.0)
  assert_eq(v.val, 2.0)
}

///|
test "snap: in range, on the step from min" {
  assert_eq(snap(7.4, 0.0, 10.0, 1.0), 7.0)
  assert_eq(snap(-3.0, 0.0, 10.0, 1.0), 0.0)
  assert_eq(snap(12.0, 0.0, 10.0, 1.0), 10.0)
  assert_eq(snap(0.26, 0.0, 1.0, 0.25), 0.25)
  assert_eq(snap(3.3, 1.0, 10.0, 2.0), 3.0)
}

///|
test "progress: its value as a percentage and its range; not known, neither, and its band a cycle said (a frame each frame while shown)" {
  let v : Ref[Double?] = Ref(Some(30.0))
  let t = @ui.Tester::new(fn(c) { progress(c, "upload", v.val, max=60.0, label="Upload") })
  let p = t.get(@ui.Role::ProgressBar, label="Upload")
  assert_eq(p.value, "50%")
  assert_eq(p.range, Some((0.0, 30.0, 60.0)), msg="its least, where it is, its most")
  v.val = None
  t.draw()
  assert_eq(t.get(@ui.Role::ProgressBar, label="Upload").range, None)
  // (what was come drawn back out into the band running along it: progress_known_ms)
  t.run_for(progress_known_ms)
  // a wait: a frame asked for each frame while it shows (Ctx::cycle), said as a cycle: what never ends does not keep a
  // test from idle
  assert_true(t.ctx().wants_frame)
  assert_eq(t.cycles().length(), 1)
  t.assert_idle()
}

///|
test "progress: told a value anew, it goes there over progress_ms from where it showed (there at once the first time); its value said at once" {
  let v : Ref[Double?] = Ref(Some(30.0))
  let shown : Ref[Double?] = Ref(None)
  let t = @ui.Tester::new(fn(c) {
    progress(c, "upload", v.val, max=60.0, label="Upload", look=fn(_, s) { shown.val = s.t })
  })
  assert_eq(shown.val, Some(0.5))
  v.val = Some(60.0)
  t.draw()
  assert_eq(t.get(@ui.Role::ProgressBar, label="Upload").value, "100%")
  t.run_for(progress_ms / 2.0)
  let half = shown.val.unwrap()
  assert_true(half > 0.5 && half < 1.0, msg="\{half}")
  t.run_for(progress_ms)
  assert_eq(shown.val, Some(1.0))
}

///|
test "avatar: named by its person, their initials while it has no picture" {
  assert_eq(initials("Ada Lovelace"), "AL")
  assert_eq(initials("ada"), "A")
  assert_eq(initials("林 子 健"), "林子")
  let t = @ui.Tester::new(fn(c) { avatar(c, "", "Ada Lovelace") })
  ignore(t.get(@ui.Role::Image, label="Ada Lovelace"))
  assert_true(t.find("AL") is Some(_))
}

///|
test "password field: hidden, its words are not read out; the button shows them, named for what it does next" {
  let shown = Ref(false)
  let words = Ref("")
  let t = @ui.Tester::new(fn(c) {
    let p = password_field(c, "pw", shown.val, placeholder="Password")
    shown.val = p.visible
    words.val = p.text
  })
  t.tap_text("Password")
  t.type_text("hunter2")
  assert_eq(words.val, "hunter2")
  assert_eq(t.get(@ui.Role::TextField).value, "")
  t.click(@ui.Role::Button, label="显示")
  assert_true(shown.val)
  assert_eq(t.get(@ui.Role::TextField).value, "hunter2")
  assert_eq(t.get(@ui.Role::Button, label="隐藏").pressed, Some(true))
  t.click(@ui.Role::Button, label="隐藏")
  assert_false(shown.val)
  assert_eq(t.get(@ui.Role::TextField).value, "")
}

///|
test "toggle: a tap presses it, Activate lets it go; said pressed or not" {
  let on = Ref(false)
  let t = @ui.Tester::new(fn(c) { on.val = toggle(c, "Bold", on.val).value })
  t.click(@ui.Role::Button, label="Bold")
  assert_true(on.val)
  assert_eq(t.get(@ui.Role::Button, label="Bold").pressed, Some(true))
  t.act(@ui.Role::Button, @ui.Action::Activate, label="Bold")
  assert_false(on.val)
  assert_eq(t.get(@ui.Role::Button, label="Bold").pressed, Some(false))
}

///|
test "label: a tap on it turns its control, or gives its field the focus" {
  let v : Ref[@ui.Check] = Ref(@ui.Check::Off)
  let t = @ui.Tester::new(fn(c) {
    c.column(gap=8.0, fn() {
      c.row(gap=8.0, fn() {
        v.val = checkbox(c, "terms", v.val, label="Terms").value
        label(c, "Accept the terms", for_id=c.id("terms")) |> ignore
      })
      |> ignore
      label(c, "Name", for_id=c.id("name"), field=true) |> ignore
      c.editor("name", placeholder="Your name") |> ignore
    })
    |> ignore
  })
  t.tap_text("Accept the terms")
  assert_eq(v.val, @ui.Check::On)
  t.tap_text("Name")
  assert_true(t.get(@ui.Role::TextField, label="Your name").focused)
  t.type_text("Ada")
  assert_eq(t.get(@ui.Role::TextField, label="Your name").value, "Ada")
}

///|
test "separator, aspect ratio, accessible icon, visually hidden: what the tree says, and the shape kept" {
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      separator(c)
      separator(c, decorative=true)
      c.box(w=Px(160.0), fn() {
        let i = aspect_ratio(c, 16.0 / 9.0, fn() {  })
        c.semantics(i, Group, label="Picture")
      })
      |> ignore
      accessible_icon(c, "Favourite", fn() { c.text("★") |> ignore })
      visually_hidden(c, "3 unread")
    })
    |> ignore
  })
  inspect(
    t.semantics_dump(),
    content=(
      #|Separator value="horizontal"
      #|Group "Picture"
      #|Image "Favourite"
      #|Text "3 unread"
      #|
    ),
  )
  let (_, _, w, h) = t.get(@ui.Role::Group, label="Picture").rect
  assert_eq(w, 160.0)
  assert_eq(h, 90.0)
}

///|
test "text field: typed in, its words the view's to read; Enter hands them on" {
  let got = Ref("")
  let sent = Ref(0)
  let t = @ui.Tester::new(fn(c) {
    let f = text_field(c, "name", placeholder="Name")
    got.val = f.text
    if f.submitted {
      sent.val += 1
    }
  })
  t.tap_text("Name")
  t.type_text("Ada")
  assert_eq(got.val, "Ada")
  assert_eq(t.get(@ui.Role::TextField, label="Name").value, "Ada")
  t.enter()
  assert_eq(sent.val, 1)
}

///|
test "text field in a look of the view's: its frame round the editor, told when it is written in; Enter not handed on" {
  let focused = Ref(false)
  let got = Ref("")
  let t = @ui.Tester::new(fn(c) {
    let f = text_field(c, "code", placeholder="Code", enter_sends=false, size=15.0, line=21.0, look=fn(c, s, editor) {
      focused.val = s.focused
      c.box(id=s.id, w=s.w, pad=10.0, radius=12.0, border=1.0, editor) |> ignore
    })
    got.val = f.text
  })
  assert_true(!focused.val)
  t.tap_text("Code")
  t.type_text("42")
  t.draw()
  assert_true(focused.val)
  assert_eq(got.val, "42")
}

///|
test "toggle group that grows: as wide as where it is, its items equal shares" {
  let v : Ref[Array[String]] = Ref(["a"])
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Px(300.0), fn() {
        v.val = toggle_group(
          c,
          "g",
          [item("a", label="A"), item("b", label="Bbbbbb")],
          v.val,
          grow=true,
          label="G",
          ground=fn(c, _, items) { c.box(dir=Row, w=Fill(1.0), items) |> ignore },
        ).value
      })
      |> ignore
    },
    w=400.0,
    h=200.0,
  )
  let (_, _, gw, _) = t.get(@ui.Role::Group, label="G").rect
  assert_eq(gw, 300.0)
  let (_, _, aw, _) = t.get(@ui.Role::Radio, label="A").rect
  let (_, _, bw, _) = t.get(@ui.Role::Radio, label="Bbbbbb").rect
  assert_eq(aw, bw)
}

///|
test "toggle group that grows, short of room for equal shares: an item as wide as its words need, the other the rest" {
  let v : Ref[Array[String]] = Ref(["a"])
  let long = "Bbbbbbbbbbbbbbbb"
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Px(200.0), fn() {
        v.val = toggle_group(
          c,
          "g",
          [item("a", label="A"), item("b", label=long)],
          v.val,
          grow=true,
          label="G",
          ground=fn(c, _, items) { c.box(dir=Row, w=Fill(1.0), items) |> ignore },
        ).value
      })
      |> ignore
    },
    w=400.0,
    h=200.0,
  )
  // its words whole, not cut to the half it would share
  assert_eq(t.lines_of(long), [long])
  let (ax, _, aw, _) = t.get(@ui.Role::Radio, label="A").rect
  let (bx, _, bw, _) = t.get(@ui.Role::Radio, label=long).rect
  assert_true(bw > 100.0)
  assert_true(bx >= ax + aw - 0.5)
  assert_true((ax + aw + bw - 200.0).abs() < 0.5)
}

///|
test "switch: its knob slides to the side it was turned to by a rest of its own (switch_rest)" {
  let on = Ref(false)
  let t = @ui.Tester::new(fn(c) { on.val = switch(c, "wifi", on.val, label="Wi-Fi").value })
  t.click(@ui.Role::Switch, label="Wi-Fi")
  let rest = switch_rest("wifi")
  assert_true(rest > t.time())
  t.run_for(rest - t.time())
  assert_eq(switch_rest("wifi"), -1.0)
  t.assert_idle()
}

///|
test "progress: from not known to known, the band running along it is drawn into the part come over progress_known_ms, not changed in a frame" {
  let v : Ref[Double?] = Ref(None)
  let seen : Ref[ProgressState] = Ref({ t: None, known: 0.0 })
  let t = @ui.Tester::new(fn(c) { progress(c, "upload", v.val, max=100.0, look=fn(_, s) { seen.val = s }) })
  assert_eq(seen.val.known, 0.0)
  v.val = Some(40.0)
  t.draw()
  t.run_for(progress_known_ms / 2.0)
  let half = seen.val.known
  assert_true(half > 0.0 && half < 1.0, msg="\{half}")
  t.run_for(progress_known_ms)
  assert_eq(seen.val.known, 1.0)
  assert_eq(seen.val.t, Some(0.4))
}
