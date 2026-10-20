// What takes the presses on a box that takes none itself (Ctx::presses_to), and where a scripted run's tap lands on
// words partly under what lies over them (drive.mbt reach_point).

///|
/// Two places on a bar whose glass takes the presses and reads where they land (as still.fail's bar does), each said
/// to be pressed through it, or not.
fn glass_bar(said : Bool, picked : Ref[String]) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      let glass = c.id("glass")
      match c.drag_of(glass) {
        Some(d) => if d.take_tap() { picked.val = if d.x < 100.0 { "files" } else { "settings" } }
        None => ()
      }
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.box(h=Px(100.0), fn() {  }) |> ignore
        c.box(w=Fill(1.0), h=Px(60.0), fn() {
          c.drag_area(glass, axis=Free, w=Fill(1.0), h=Fill(1.0), fn() {  }) |> ignore
          c.layer(fn() {
            c.row(fn() {
              c.box(w=Px(100.0), h=Px(60.0), fn() {
                if said {
                  c.presses_to(glass)
                }
                c.text("文件", wrap=false) |> ignore
              })
              |> ignore
              c.box(w=Px(100.0), h=Px(60.0), fn() {
                if said {
                  c.presses_to(glass)
                }
                c.text("设置", wrap=false) |> ignore
              })
              |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=200.0,
  )
}

///|
test "places on a glass that takes their presses: tapped through it once each says so, else under it, said what" {
  let picked = Ref::new("")
  let t = glass_bar(true, picked)
  let log = t.drive("timeout 300\ntap 设置\nexit")
  assert_eq(picked.val, "settings", msg=log.join("\n"))
  // not said: the glass is another's to press, and the failure says what it is
  let picked2 = Ref::new("")
  let u = glass_bar(false, picked2)
  let log2 = u.drive("timeout 300\ntap 设置\nexit")
  assert_eq(picked2.val, "")
  assert_true(
    log2.iter().any(fn(l) { l.contains("under something else to press") && l.contains("a drag area 0,100 200x60") }),
    msg=log2.join("\n"),
  )
}

///|
test "panic presses said to be an area's that is drawn nowhere fail, saying where" {
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Px(50.0), h=Px(50.0), fn() {
        c.presses_to(c.id("no such area"))
        c.text("x", wrap=false) |> ignore
      })
      |> ignore
    },
    w=100.0,
    h=100.0,
  )
  t.draw()
}

///|
test "words partly under what lies over them: tapped at the point of them in sight nearest their middle, each run" {
  let tapped = Ref::new(0)
  let t = @ui.Tester::new(
    fn(c) {
      let row = c.id("row")
      if c.clicked(row) {
        tapped.val += 1
      }
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.box(h=Px(80.0), fn() {  }) |> ignore
        c.box(id=row, h=Px(20.0), fn() { c.text("忽略这一行", wrap=false) |> ignore }) |> ignore
        // a bar over the row's upper half
        c.layer(fn() {
          c.box(h=Px(60.0), fn() {  }) |> ignore
          c.box(id=c.id("bar"), w=Fill(1.0), h=Px(30.0), bg=0xFFFFFFFFL, fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=200.0,
  )
  let log = t.drive("timeout 300\ntap 忽略这一行\nexit")
  assert_eq(tapped.val, 1, msg=log.join("\n"))
  let tap = log.filter(fn(l) { l.has_prefix("DRIVE tap 忽略这一行 at") })
  // (where: below the bar, the same each run)
  let again = t.drive("timeout 300\ntap 忽略这一行\nexit").filter(fn(l) { l.has_prefix("DRIVE tap 忽略这一行 at") })
  assert_eq(again, tap)
  assert_eq(tap.length(), 1)
}

///|
test "the next wake the app waits on: when, and who said it; none once it has come" {
  let armed = Ref::new(false)
  // how long the app waits
  let wait_ms = 300.0
  let t = @ui.Tester::new(fn(c) {
      if !armed.val {
        armed.val = true
        c.wake_in(wait_ms)
      }
      c.text("x", wrap=false) |> ignore
    }, w=100.0, h=100.0)
  match t.next_wake() {
    Some((at, by)) => {
      assert_true(at > t.time())
      assert_true(by.contains("presses_test.mbt"), msg=by)
      t.run_for(at - t.time())
    }
    None => fail("a wake waited on")
  }
  t.draw()
  assert_eq(t.next_wake(), None)
}
