///|
/// A page with a button under where a layer opens, the layer (`modal` or not) holding a panel at (100, 200) with two
/// buttons, and what happened logged.
fn layer_page(open : Ref[Bool], log : Array[String], modal? : Bool = false) -> (Ctx) -> Unit {
  fn(c) {
    c.column(gap=4.0, fn() {
      let trigger = btn(c, "open")
      if trigger.clicked {
        log.push("open clicked")
        open.val = !open.val
      }
      if btn(c, "under").clicked {
        log.push("under")
      }
      if open.val {
        let o = c.overlay("layer", modal~, anchor=trigger.id, scrim=0x00000040L, fn() {
          c.box(tx=100.0, ty=200.0, pad=10.0, gap=4.0, bg=0xFFFFFFFFL, id=c.id("panel"), fn() {
            if btn(c, "inside").clicked {
              log.push("inside")
            }
            btn(c, "second") |> ignore
          })
          |> ignore
        })
        match o.dismissed {
          Some(d) => {
            log.push("dismissed \{d}")
            open.val = false
          }
          None => ()
        }
      }
      // built after the layer, over the whole page: the layer is still over it
      c.box(w=Fill(1.0), h=Px(600.0), id=c.id("late"), fn() {  }) |> ignore
    })
    |> ignore
  }
}

///|
test "a layer is drawn and tapped over what is built after it" {
  let open = Ref(true)
  let log = []
  let t = Tester::new(layer_page(open, log))
  t.click(Button, label="inside")
  assert_eq(log, ["inside"])
}

///|
test "a press outside a layer dismisses it and goes on to what is under it; on its anchor it does not dismiss" {
  let open = Ref(true)
  let log = []
  let t = Tester::new(layer_page(open, log))
  t.click(Button, label="under")
  assert_eq(log, ["under", "dismissed Outside"])
  assert_false(open.val)
  // opened, then its trigger pressed again: it closes by the trigger, not by the press outside
  t.click(Button, label="open")
  assert_true(open.val)
  t.click(Button, label="open")
  assert_eq(log, ["under", "dismissed Outside", "open clicked", "open clicked"])
}

///|
test "a modal layer: what is under it takes nothing, a press on its ground dismisses it, it hides the page" {
  let open = Ref(true)
  let log = []
  let t = Tester::new(layer_page(open, log, modal=true))
  // under it: not in the tree
  assert_true(t.query(Button, label="under") is None)
  assert_true(t.query(Button, label="inside") is Some(_))
  t.tap(5.0, 40.0)
  assert_eq(log, ["dismissed Outside"])
  assert_true(t.query(Button, label="under") is Some(_))
}

///|
test "Escape and back dismiss the topmost layer only" {
  let a = Ref(true)
  let b = Ref(true)
  let log : Array[String] = []
  let t = Tester::new(fn(c) {
    if a.val {
      let o = c.overlay("a", fn() {
        c.box(tx=10.0, ty=10.0, w=Px(100.0), h=Px(100.0), bg=0xEEEEEEFFL, id=c.id("pa"), fn() {
          if b.val {
            let ob = c.overlay("b", fn() {
              c.box(tx=50.0, ty=300.0, w=Px(100.0), h=Px(100.0), bg=0xDDDDDDFFL, id=c.id("pb"), fn() {  })
              |> ignore
            })
            if ob.dismissed is Some(d) {
              log.push("b \{d}")
              b.val = false
            }
          }
        })
        |> ignore
      })
      if o.dismissed is Some(d) {
        log.push("a \{d}")
        a.val = false
      }
    }
  })
  t.press("Escape")
  assert_eq(log, ["b Escape"])
  t.back()
  assert_eq(log, ["b Escape", "a Back"])
}

///|
test "a press in a layer dismisses the layers over it, not it" {
  let a = Ref(true)
  let b = Ref(true)
  let log : Array[String] = []
  let t = Tester::new(fn(c) {
    if a.val {
      let o = c.overlay("a", fn() {
        c.box(tx=10.0, ty=10.0, w=Px(200.0), h=Px(200.0), bg=0xEEEEEEFFL, id=c.id("pa"), fn() {
          if b.val {
            let ob = c.overlay("b", fn() {
              c.box(tx=50.0, ty=300.0, w=Px(100.0), h=Px(100.0), bg=0xDDDDDDFFL, id=c.id("pb"), fn() {  })
              |> ignore
            })
            if ob.dismissed is Some(d) {
              log.push("b \{d}")
              b.val = false
            }
          }
        })
        |> ignore
      })
      if o.dismissed is Some(d) {
        log.push("a \{d}")
        a.val = false
      }
    }
  })
  // in b: nothing
  t.tap(100.0, 350.0)
  assert_eq(log, [])
  // in a, outside b
  t.tap(20.0, 20.0)
  assert_eq(log, ["b Outside"])
  t.tap(300.0, 600.0)
  assert_eq(log, ["b Outside", "a Outside"])
}

///|
test "a modal layer traps Tab, takes the focus as it opens and gives it back as it goes" {
  let open = Ref(false)
  let log = []
  let t = Tester::new(layer_page(open, log, modal=true))
  t.tab()
  assert_eq(t.focused().unwrap().label, "open")
  t.press("Enter")
  assert_true(open.val)
  // into it: its first
  assert_eq(t.focused().unwrap().label, "inside")
  t.tab()
  assert_eq(t.focused().unwrap().label, "second")
  t.tab()
  assert_eq(t.focused().unwrap().label, "inside")
  t.press("Escape")
  assert_false(open.val)
  // back to what opened it
  assert_eq(t.focused().unwrap().label, "open")
}

///|
test "a modal layer stops the wheel over the page under it" {
  let open = Ref(true)
  let t = Tester::new(fn(c) {
    c.list("rows", 100, 40.0, fn(i) { c.text("row \{i}") |> ignore }) |> ignore
    if open.val {
      c.overlay("m", modal=true, fn() {
        c.box(tx=20.0, ty=20.0, w=Px(100.0), h=Px(100.0), bg=0xFFFFFFFFL, id=c.id("p"), fn() {  }) |> ignore
      })
      |> ignore
    }
  })
  t.wheel(200.0, 400.0, 300.0)
  assert_eq(t.list_offset(), 0.0)
  open.val = false
  t.frame()
  t.wheel(200.0, 400.0, 300.0)
  assert_true(t.list_offset() > 0.0)
}

///|
test "a layer leaving (inert) takes no press and gives the focus back" {
  let inert = Ref(false)
  let log = []
  let t = Tester::new(fn(c) {
    let trigger = btn(c, "trigger")
    c.overlay("l", modal=true, inert=inert.val, return_focus=trigger.id, fn() {
      c.box(tx=10.0, ty=100.0, id=c.id("p"), fn() {
        if btn(c, "in it").clicked {
          log.push("in it")
        }
      })
      |> ignore
    })
    |> ignore
  })
  assert_eq(t.focused().unwrap().label, "in it")
  let (x, y, w, h) = t.get(Button, label="in it").rect
  inert.val = true
  t.frame()
  assert_eq(t.focused().unwrap().label, "trigger")
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_eq(log, [])
  // hidden from the tree as it leaves
  assert_true(t.query(Button, label="in it") is None)
}

///|
test "place: below its anchor, flipped above when there is no room, kept in the window; right to left, from the right" {
  let out : Array[(Double, Double, Side)] = []
  let _t = Tester::new(fn(c) {
    out.clear()
    out.push(c.place((100.0, 100.0, 80.0, 30.0), 120.0, 60.0, along=Start))
    out.push(c.place((100.0, 800.0, 80.0, 30.0), 120.0, 60.0))
    out.push(c.place((330.0, 100.0, 50.0, 30.0), 120.0, 60.0, along=Start))
    c.with_direction(Rtl, fn() {
      out.push(c.place((100.0, 100.0, 80.0, 30.0), 60.0, 60.0, along=Start))
    })
  })
  assert_eq(out[0], (100.0, 134.0, Bottom))
  // flipped: 60 tall above the anchor, 4 off it
  assert_eq(out[1], (80.0, 736.0, Top))
  // moved left to stay 8 inside the window
  assert_eq(out[2], (390.0 - 8.0 - 120.0, 134.0, Bottom))
  // start is the right: their right edges line up
  assert_eq(out[3], (120.0, 134.0, Bottom))
}

///|
test "a layer dismissed as the view closed it its own way is not dismissed by that when it opens again" {
  let open = Ref(true)
  let log = []
  let t = Tester::new(fn(c) {
    c.column(gap=4.0, fn() {
      if btn(c, "open").clicked {
        open.val = true
      }
      // closes the layer itself (as a key of the view's own would), the press outside it dismissing it too
      if btn(c, "close").clicked {
        open.val = false
      }
      if open.val {
        let o = c.overlay("layer", fn() {
          c.box(tx=100.0, ty=200.0, pad=10.0, bg=0xFFFFFFFFL, fn() { btn(c, "inside") |> ignore }) |> ignore
        })
        if o.dismissed is Some(d) {
          log.push("dismissed \{d}")
          open.val = false
        }
      }
    })
    |> ignore
  })
  t.click(Button, label="close")
  assert_false(open.val)
  t.click(Button, label="open")
  t.frame()
  assert_true(open.val, msg="open again")
  assert_true(t.query(Button, label="inside") is Some(_))
  assert_eq(log, [])
}

///|
test "a layer opened by a list's row (built as the list is laid out) is laid out over the window as any other is" {
  let t = Tester::new(fn(c) {
    c.list("rows", 3, 40.0, fn(k) {
      c.text("row \{k}") |> ignore
      if k == 1 {
        c.overlay("row-layer", fn() {
          c.box(tx=100.0, ty=200.0, w=Px(80.0), pad=10.0, fn() { c.text("card") |> ignore }) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  let card = t.words().filter(fn(w) { w.0 == "card" })
  assert_eq(card.length(), 1)
  // where its box puts it, in what the box holds
  assert_eq((card[0].1, card[0].2), (110.0, 210.0))
  assert_true(card[0].3 > 0.0 && card[0].3 <= 60.0, msg="\{card[0].3} wide")
}

///|
test "an open layer the focus is in has the keys: the page under it reads none (Escape, a letter, its raw keys); the layer reads them" {
  let open = Ref(true)
  let log : Array[String] = []
  let t = Tester::new(fn(c) {
    // a page reading keys as a list's rows do (Ctx::keys) and as its shortcuts do (Ctx::key_pressed)
    for k in c.keys() {
      log.push("page key \{k.0}")
    }
    if c.key_pressed(key_escape) || c.key_pressed(key_escape, in_field=true) {
      log.push("page escape")
    }
    if open.val {
      // (as a menu opened is: the focus on its first)
      let o = c.overlay("menu", initial_focus=-1, fn() {
        if c.key_pressed(key_of_char('a')) {
          log.push("menu a")
        }
        btn(c, "inside") |> ignore
      })
      if o.dismissed is Some(d) {
        log.push("dismissed \{d}")
        open.val = false
      }
    }
  })
  t.draw()
  t.key(key_of_char('a'))
  t.frame()
  assert_eq(log, ["menu a"])
  t.key(key_escape)
  t.frame()
  assert_eq(log, ["menu a", "dismissed Escape"])
  assert_false(open.val)
  // closed: the page's again
  t.key(key_of_char('a'))
  t.frame()
  assert_eq(log, ["menu a", "dismissed Escape", "page key \{key_of_char('a')}"])
}
