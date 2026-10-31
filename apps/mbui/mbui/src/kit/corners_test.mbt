// still.fail's corner rule (ui/corners.mbt) over the components drawn open: what lies in a rounded thing's corner is
// as far from both its edges, and concentric.

///|
test "corners: a dialog, an alert dialog" {
  let t = @ui.Tester::new(fn(c) {
    dialog(c, "d", true, "Edit profile", description="How others see you.", fn() {
      text_field(c, "name", placeholder="Name") |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_eq(t.corner_faults(), [])
  let t = @ui.Tester::new(fn(c) {
    alert_dialog(c, "a", true, "Delete the chat?", "Delete", description="It cannot be undone.", danger=true) |> ignore
  })
  t.draw()
  assert_eq(t.corner_faults(), [])
}

///|
test "corners: a menu, a select's list, a popover, a tooltip" {
  let t = @ui.Tester::new(fn(c) {
    c.column(gap=8.0, pad=20.0, fn() {
      let tr = button(c, "File", key="file")
      dropdown_menu(c, "m", true, tr.id, [
        menu_label("File"),
        menu_item("new", label="New tab", shortcut="⌘T"),
        menu_separator(),
        menu_check("bar", true, label="Show bookmarks"),
      ])
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.press("Down")
  assert_eq(t.corner_faults(), [])
  let t = @ui.Tester::new(fn(c) {
    c.column(pad=20.0, fn() {
      let tr = button(c, "Filters", key="f")
      popover(c, "p", true, tr.id, fn() { c.text("Filters") |> ignore }) |> ignore
      tooltip(c, "tip", tr.id, "Words") |> ignore
    })
    |> ignore
  })
  t.draw()
  t.tab()
  t.draw()
  assert_eq(t.corner_faults(), [])
}

///|
test "corners: toasts, fields, segmented choices, a toolbar" {
  let t = @ui.Tester::new(fn(c) {
    c.column(gap=12.0, pad=20.0, fn() {
      password_field(c, "pw", false, placeholder="Password") |> ignore
      toggle_group(c, "g", [item("a", label="Left"), item("b", label="Right")], ["a"]) |> ignore
      toggle_group(c, "s", [item("a", label="Day"), item("b", label="Week")], ["b"], slide=true) |> ignore
      toolbar(c, "tb", fn() {
        toggle(c, "B", true, key="b") |> ignore
        toggle(c, "I", false, key="i") |> ignore
      })
      tabs(c, "tabs", [item("x", label="One"), item("y", label="Two")], "x", fn(_) {  }) |> ignore
    })
    |> ignore
    toaster(c, "toasts", [toast("a", "Saved"), toast("b", "Sent", description="To the team", action="Undo")]) |> ignore
  })
  t.draw()
  // pointed at: the password's button shows its ground
  let (x, y, w, h) = t.get(@ui.Role::Button, label="显示").rect
  t.move(x + w / 2.0, y + h / 2.0)
  assert_eq(t.corner_faults(), [])
}

///|
test "corners: a fault names what breaks the rule by its words and place" {
  // (4 from its side and 10 from its top: its corner worked out cannot be concentric with both)
  let t = @ui.Tester::new(fn(c) {
    c.column(pad=20.0, fn() {
      c.box(w=Px(200.0), h=Px(80.0), padx=4.0, pady=10.0, bg=0xEEEEEEFFL, radius=16.0, fn() {
        c.box(pad=8.0, bg=0x3366FFFFL, radius=6.0, fn() { c.text("Send", size=13.0) |> ignore })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let faults = t.corner_faults()
  assert_true(faults.length() > 0)
  assert_true(faults[0].contains("「Send」"))
}

///|
test "corners: a circle or a capsule in a corner: as far from both edges, the container's corner following it" {
  // a circle of 11, 15 from both edges, in a corner that reads to it as 26 (15 + 11: @ui.round_like): no fault
  let t = @ui.Tester::new(fn(c) {
    c.column(pad=20.0, fn() {
      c.box(w=Px(200.0), h=Px(80.0), pad=15.0, bg=0xEEEEEEFFL, radius=@ui.round_like_out(26.0), fn() {
        c.box(w=Px(22.0), h=Px(22.0), bg=0x3366FFFFL, radius=11.0, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_eq(t.corner_faults(), [])
  // a capsule 24 high, 12 from both edges, in a corner that reads to it as 24: no fault
  let t = @ui.Tester::new(fn(c) {
    c.column(pad=20.0, fn() {
      c.box(w=Px(200.0), h=Px(80.0), pad=12.0, bg=0xEEEEEEFFL, radius=@ui.round_like_out(24.0), fn() {
        c.box(w=Px(60.0), h=Px(24.0), bg=0x3366FFFFL, radius=12.0, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_eq(t.corner_faults(), [])
  // the same circle in a corner of 24: the container's fault, it wants one that reads to it as 26 (27.18)
  let t = @ui.Tester::new(fn(c) {
    c.column(pad=20.0, fn() {
      c.box(w=Px(200.0), h=Px(80.0), pad=15.0, bg=0xEEEEEEFFL, radius=24.0, fn() {
        c.box(w=Px(22.0), h=Px(22.0), bg=0x3366FFFFL, radius=11.0, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let faults = t.corner_faults()
  assert_eq(faults.length(), 1)
  assert_true(faults[0].contains("wants corner 27.18"))
  // a circle nearer one edge than the other: its own fault
  let t = @ui.Tester::new(fn(c) {
    c.column(pad=20.0, fn() {
      c.box(w=Px(200.0), h=Px(80.0), pl=16.0, pt=12.0, bg=0xEEEEEEFFL, radius=24.0, fn() {
        c.box(w=Px(22.0), h=Px(22.0), bg=0x3366FFFFL, radius=11.0, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let faults = t.corner_faults()
  assert_eq(faults.length(), 1)
  assert_true(faults[0].contains("16 and 12 from its edges"))
}

///|
test "corners: a mark hung past the corner of a card in a container's corner is the card's, not the container's" {
  // a composer (26 round, 10 in) with a card's room 200 wide and its remove button's reach (6.5) at its end; the button
  // (20 round) over the card's top right corner, lifted past its top by its reach, 3.5 from the composer's top and 23
  // from its right: no fault
  let card = fn(lift : Double) {
    @ui.Tester::new(fn(c) {
      c.column(pad=20.0, fn() {
        c.box(w=Px(239.5), h=Px(90.0), pad=10.0, bg=0xEEEEEEFFL, radius=26.0, fn() {
          c.box(w=Px(206.5), fn() {
            c.box(w=Px(200.0), h=Px(56.0), fn() {  }) |> ignore
            c.layer(align=AEnd, fn() {
              c.box(w=Px(20.0), h=Px(20.0), bg=0x222222FFL, radius=10.0, ty=-lift, fn() {  }) |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
  }
  let t = card(6.5)
  t.draw()
  assert_eq(t.corner_faults(), [])
  // the same button not lifted, within what it is laid over: set in the composer's corner, 10 from its top and 23 from
  // its right, the rule's
  let t = card(0.0)
  t.draw()
  assert_eq(t.corner_faults().length(), 1)
}

///|
test "corners: a box in a container's corner is measured without the corner a mark is hung on" {
  // a quote waiting in a composer (26 round, 10 in): its corner its container's inner, the room for its remove
  // button's reach (5) after it, so 10 from the composer's left and top and 15 from its right; the button over its top
  // right corner, lifted past its top: that corner the button's, the quote measured by its top left: no fault
  let quote = fn(mark : Bool) {
    @ui.Tester::new(fn(c) {
      c.column(pad=20.0, fn() {
        c.box(w=Px(300.0), h=Px(120.0), pad=10.0, bg=0xEEEEEEFFL, radius=26.0, fn() {
          c.box(dir=Row, w=Fill(1.0), fn() {
            c.box(style=@ui.style(w=Grow(1.0), h=Fixed(60.0), bg=Exact(0xFFFFFFFFL), radius=InnerOr(Exact(18.0))), fn() {  })
            |> ignore
            c.box(w=Px(5.0), fn() {  }) |> ignore
            if mark {
              c.layer(align=AEnd, fn() {
                c.box(w=Px(20.0), h=Px(20.0), bg=0x222222FFL, radius=10.0, ty=-5.0, fn() {  }) |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
  }
  let t = quote(true)
  t.draw()
  assert_eq(t.corner_faults(), [])
  // no mark on it: 10, 10 and 15 from the edges, a fault
  let t = quote(false)
  t.draw()
  assert_true(t.corner_faults().length() > 0)
}

///|
test "corners: a round thing centred in its container is not set in a corner" {
  // a card's trailing ×, centred up and down in a row: near the top right corner, but not in it
  let t = @ui.Tester::new(fn(c) {
    c.column(pad=20.0, fn() {
      c.box(dir=Row, w=Px(236.0), h=Px(52.0), pl=12.0, pr=10.0, align=ACenter, bg=0xEEEEEEFFL, radius=16.0, fn() {
        c.box(w=Fill(1.0), fn() { c.text("build.log", size=13.0) |> ignore }) |> ignore
        c.box(w=Px(22.0), h=Px(22.0), bg=0x3366FFFFL, radius=11.0, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_eq(t.corner_faults(), [])
  // the same × put at the top right by the layout (the row's items at its start, 10 from the top and the right): the
  // corner rule holds, and the card's corner of 16 is not the 21 it wants
  let t = @ui.Tester::new(fn(c) {
    c.column(pad=20.0, fn() {
      c.box(dir=Row, w=Px(236.0), h=Px(52.0), pl=12.0, pr=10.0, pt=10.0, align=AStart, bg=0xEEEEEEFFL, radius=16.0, fn() {
        c.box(w=Fill(1.0), fn() { c.text("build.log", size=13.0) |> ignore }) |> ignore
        c.box(w=Px(22.0), h=Px(22.0), bg=0x3366FFFFL, radius=11.0, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let faults = t.corner_faults()
  assert_eq(faults.length(), 1)
  assert_true(faults[0].contains("wants corner 21"))
}

///|
test "corners: a container whose ground is a layer of its size: what is in its corner as far from both edges" {
  // a composer: its glass a layer under it, the attachment's tile 10 from the left and 14 from the top: a fault
  let composer = fn(c : @ui.Ctx, top : Double) {
    c.column(pad=20.0, fn() {
      c.box(w=Px(370.0), h=Px(160.0), fn() {
        c.layer(fn() { c.box(w=Fill(1.0), h=Fill(1.0), bg=0xEEEEEEFFL, radius=26.0, fn() {  }) |> ignore })
        |> ignore
        c.box(pl=10.0, pt=top, fn() {
          c.box(w=Px(56.0), h=Px(56.0), bg=0x3366FFFFL, radius=18.0, fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }
  let t = @ui.Tester::new(fn(c) { composer(c, 14.0) })
  t.draw()
  let faults = t.corner_faults()
  assert_eq(faults.length(), 1)
  assert_true(faults[0].contains("10 and 14 from its edges"))
  // 10 from both, its corner concentric with 26's (26 less 10 over 1.25: 18, still.fail's attachment): no fault
  let t = @ui.Tester::new(fn(c) { composer(c, 10.0) })
  t.draw()
  assert_eq(t.corner_faults(), [])
}

///|
test "corners: the container's own fill drawn on over its corner is its shape, not a thing in its corner" {
  // a grouped row: its rounded ground, a square patch of the same fill over its bottom corners: no fault
  let row = fn(c : @ui.Ctx, patch : Int64) {
    c.column(pad=20.0, fn() {
      c.box(w=Px(366.0), h=Px(58.0), bg=0xEEEEEEFFL, radius=16.0, fn() {
        c.box(h=Px(42.0), fn() {  }) |> ignore
        c.box(w=Fill(1.0), h=Px(16.0), bg=patch, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  }
  let t = @ui.Tester::new(fn(c) { row(c, 0xEEEEEEFFL) })
  t.draw()
  assert_eq(t.corner_faults(), [])
  // a band of another fill there (a table's foot): its square corners show past the card's: both corners fault
  let t = @ui.Tester::new(fn(c) { row(c, 0x3366FFFFL) })
  t.draw()
  assert_eq(t.corner_faults().length(), 2)
}

///|
test "corners: a round thing centred in a capsule sits in its round end" {
  // a switch's knob centred up and down in its track (44×26, corner 13), 5 from the left, 3 from top and bottom: a
  // fault, centred or not
  let knob = fn(c : @ui.Ctx, side : Double, pad : Double) {
    c.column(pad=20.0, fn() {
      c.box(dir=Row, w=Px(44.0), h=Px(26.0), pl=pad, align=ACenter, bg=0xDDDDDDFFL, radius=13.0, fn() {
        c.box(w=Px(side), h=Px(side), bg=0xFFFFFFFFL, radius=side / 2.0, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  }
  let t = @ui.Tester::new(fn(c) { knob(c, 20.0, 5.0) })
  t.draw()
  assert_eq(t.corner_faults().length(), 2)
  // a knob of 22, 2 from every edge: concentric with the track's end, no fault
  let t = @ui.Tester::new(fn(c) { knob(c, 22.0, 2.0) })
  t.draw()
  assert_eq(t.corner_faults(), [])
}

///|
test "corners: flush in the corner of what cuts with a rounded corner shows the cut's corner" {
  // a diff row's ground flush at the bottom of a card that cuts what it holds (clip, corner 12): drawn round by the
  // cut, no fault
  let card = fn(c : @ui.Ctx, clip : Bool) {
    c.column(pad=20.0, fn() {
      c.box(w=Px(300.0), h=Px(80.0), bg=0xEEEEEEFFL, radius=12.0, clip~, fn() {
        c.box(h=Px(56.0), fn() {  }) |> ignore
        c.box(w=Fill(1.0), h=Px(24.0), bg=0xDDF4DDFFL, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  }
  let t = @ui.Tester::new(fn(c) { card(c, true) })
  t.draw()
  assert_eq(t.corner_faults(), [])
  // the same card not cutting: the row's square corners show past the card's, both corners fault
  let t = @ui.Tester::new(fn(c) { card(c, false) })
  t.draw()
  assert_eq(t.corner_faults().length(), 2)
  // flush in a cut with no corner (a square clip inside the card): a square cut, the row's corners still square
  let t = @ui.Tester::new(fn(c) {
    c.column(pad=20.0, fn() {
      c.box(w=Px(300.0), h=Px(80.0), bg=0xEEEEEEFFL, radius=12.0, fn() {
        c.box(w=Fill(1.0), h=Fill(1.0), clip=true, fn() {
          c.box(h=Px(56.0), fn() {  }) |> ignore
          c.box(w=Fill(1.0), h=Px(24.0), bg=0xDDF4DDFFL, fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_eq(t.corner_faults().length(), 2)
}
