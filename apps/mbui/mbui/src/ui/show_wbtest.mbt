///|
/// Where row `label` (its words, a row 20 tall) shows in capped box `key` of `t` (laid out at its scroll): its top and
/// foot from the box's top.
fn shown_in_capped(t : Tester, key : String, label : String) -> (Double, Double) {
  let c = t.ctx()
  let (_, y, _, _) = t.rect_of(label).unwrap()
  let mut top = 0.0
  for i in 0..<c.count {
    if c.nodes[i].id == c.capped_id(key) {
      top = c.nodes[i].y
    }
  }
  (y - top, y - top + 20.0)
}

///|
test "the focus moved by the keys among what a box kept to a height holds is brought into view there" {
  let t = Tester::new(
    fn(c) {
      c.capped("menu", 100.0, fn() {
        c.roving("items", orientation=Vertical, fn() {
          c.column(fn() {
            for k in 0..<20 {
              let label = "item \{k}"
              let id = c.id(label)
              c.interact(id) |> ignore
              let i = c.box(h=Px(20.0), w=Fill(1.0), id~, fn() { c.text(label, wrap=false) |> ignore })
              c.semantics(i, Button, id~, actions=[Activate])
            }
          })
          |> ignore
        })
      })
      |> ignore
    },
    w=200.0,
    h=300.0,
  )
  t.tab()
  assert_eq(t.focused().unwrap().label, "item 0")
  // down past the box's foot: the one moved to stands at the foot, no further
  for _ in 0..<7 {
    t.press("Down")
  }
  assert_eq(t.focused().unwrap().label, "item 7")
  let (top, foot) = shown_in_capped(t, "menu", "item 7")
  assert_true(top >= 0.0 && foot <= 100.0, msg="\{(top, foot)}")
  assert_eq(foot, 100.0)
  // to the last and back to the first
  t.press("End")
  let (top, foot) = shown_in_capped(t, "menu", "item 19")
  assert_true(top >= 0.0 && foot <= 100.0, msg="\{(top, foot)}")
  t.press("Home")
  let (top, _) = shown_in_capped(t, "menu", "item 0")
  assert_eq(top, 0.0)
  // one already in view: nothing scrolls
  t.press("Down")
  let (top, _) = shown_in_capped(t, "menu", "item 0")
  assert_eq(top, 0.0)
}

///|
test "an option chosen by the keys while the focus stays in a field is brought into view as Ctx::show asks" {
  let chosen = Ref(0)
  let t = Tester::new(
    fn(c) {
      let mut keyed = false
      if c.key_pressed(key_code_down) && chosen.val < 19 {
        chosen.val += 1
        keyed = true
      }
      if c.key_pressed(key_code_up) && chosen.val > 0 {
        chosen.val -= 1
        keyed = true
      }
      c.capped("options", 100.0, fn() {
        c.column(fn() {
          for k in 0..<20 {
            let label = "option \{k}"
            let id = c.id(label)
            if keyed && k == chosen.val {
              c.show(id)
            }
            c.box(h=Px(20.0), w=Fill(1.0), id~, fn() { c.text(label, wrap=false) |> ignore }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=300.0,
  )
  for _ in 0..<12 {
    t.press("Down")
  }
  let (top, foot) = shown_in_capped(t, "options", "option 12")
  assert_eq(foot, 100.0, msg="\{(top, foot)}")
  // up within what shows: still; up past its top: it stands at the top
  for _ in 0..<4 {
    t.press("Up")
  }
  let (top, _) = shown_in_capped(t, "options", "option 8")
  assert_true(top >= 0.0, msg="\{top}")
  for _ in 0..<4 {
    t.press("Up")
  }
  let (top, _) = shown_in_capped(t, "options", "option 4")
  assert_eq(top, 0.0)
}
