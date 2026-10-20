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

///|
/// A paragraph with a link after words that lead nowhere (as a chat's markdown has it), the link's right part under a
/// box that takes presses from `cover` on (none: at 1000, past it all).
fn link_after_words(went : Array[String], cover : Ref[Double]) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      c.box(w=Px(300.0), h=Px(20.0), fn() {
        c.rich(
          [@ui.plain("详见 "), @ui.link("example.com/e2e", "https://example.com/e2e")],
          size=10.0,
          wrap=false,
          on_link=fn(href) { went.push(href) },
        )
        |> ignore
        c.layer(fn() {
          c.row(fn() {
            c.box(w=Px(cover.val), h=Fill(1.0), fn() {  }) |> ignore
            c.drag_area(c.id("cover"), axis=Free, w=Fill(1.0), h=Fill(1.0), fn() {  }) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=100.0,
  )
}

///|
test "a link in a paragraph is tapped on the link, its own target, not on the words beside it" {
  let went = []
  let t = link_after_words(went, Ref::new(1000.0))
  let log = t.drive("timeout 300\ntap example.com/e2e\nexit")
  assert_eq(went, ["https://example.com/e2e"], msg=log.join("\n"))
}

///|
test "a link half under what takes presses is tapped on its part in sight, not on the words beside it" {
  let went = []
  let cover = Ref::new(1000.0)
  let t = link_after_words(went, cover)
  t.draw()
  let (x, _, w, _) = t.run_rects("example.com/e2e")[0]
  cover.val = x + w * 0.6
  t.draw()
  let log = t.drive("timeout 300\ntap example.com/e2e\nexit")
  assert_eq(went, ["https://example.com/e2e"], msg=log.join("\n"))
}
