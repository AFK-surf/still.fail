// A card's first action can align with its words without changing the room in a later button, an icon button, or a
// button at the other end of the card.

///|
test "card foot alignment leaves other buttons' room alone" {
  let t = @ui.Tester::new(
    wide_view(fn(c) {
      c.box(dir=Row, fn() { button(c, "普通按钮") |> ignore }) |> ignore
      page_card(c, footed=true, fn() {
        c.text("卡片的字") |> ignore
        card_foot(c, fn() {
          button(c, "图标按钮", icon="log-in") |> ignore
          button(c, "后续按钮") |> ignore
        })
      })
      page_card(c, footed=true, fn() {
        c.text("卡片的另一行字") |> ignore
        card_foot(c, at_end=true, fn() { button(c, "末尾按钮") |> ignore })
      })
      c.box(dir=Row, fn() { button(c, "另一按钮") |> ignore }) |> ignore
    }),
    w=800.0,
    h=600.0,
  )
  t.draw()
  let (ordinary_x, _, _, _) = t.rect_of("普通按钮").unwrap()
  let (later_x, _, _, _) = t.rect_of("后续按钮").unwrap()
  let (end_x, _, _, _) = t.rect_of("末尾按钮").unwrap()
  let (after_x, _, _, _) = t.rect_of("另一按钮").unwrap()
  let ordinary_in = ordinary_x - t.get(Button, label="普通按钮").rect.0
  let later_in = later_x - t.get(Button, label="后续按钮").rect.0
  let end_in = end_x - t.get(Button, label="末尾按钮").rect.0
  let after_in = after_x - t.get(Button, label="另一按钮").rect.0
  assert_true((later_in - ordinary_in).abs() < 0.01, msg="later \{later_in}, ordinary \{ordinary_in}")
  assert_true((end_in - ordinary_in).abs() < 0.01, msg="end \{end_in}, ordinary \{ordinary_in}")
  assert_true((after_in - ordinary_in).abs() < 0.01, msg="after \{after_in}, ordinary \{ordinary_in}")
}

///|
test "a wrapping card foot keeps its first action at the bottom left" {
  let t = @ui.Tester::new(
    wide_view(fn(c) {
      page_card(c, footed=true, fn() {
        c.text("卡片的字") |> ignore
        ask_buttons(c, fn() {
          button(c, "主要操作", tone=Primary) |> ignore
          button(c, "较长的次要操作一", tone=Ghost) |> ignore
          button(c, "较长的次要操作二", tone=Ghost) |> ignore
        })
      })
    }),
    w=220.0,
    h=400.0,
  )
  t.draw()
  let (title_x, _, _, _) = t.rect_of("卡片的字").unwrap()
  let (primary_x, primary_y, _, _) = t.rect_of("主要操作").unwrap()
  let (_, last_y, _, _) = t.rect_of("较长的次要操作二").unwrap()
  assert_true((primary_x - title_x).abs() < 0.01)
  assert_true(primary_y > last_y, msg="primary \{primary_y}, last \{last_y}")
}
