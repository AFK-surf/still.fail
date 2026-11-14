// The corner rule under a scale (View::scale: a thing lifted as a finger holds it, @sf's lift): a container and what
// lies in its corner drawn under one scale are held to the ladder as said, the drawn divided by it; one scaled and the
// other not, or each its own, as drawn; at rest, as ever.

///|
/// The ladder these tests hold corners to (still.fail's, a panel's 42 down to a small block's 10).
let scaled_ladder : Array[Double] = [42.0, 26.0, 24.0, 18.0, 10.0]

///|
/// How much a lift draws a thing bigger, all the way up.
let scaled_lift : Double = 1.04

///|
/// How far in from the card's edges what lies in its top left corner stands.
let scaled_in : Double = 8.0

///|
/// What the corner rule says of a card 200×120, `card_r` round, drawn `card_scale` as big about its middle, 40 in from
/// the window's top left (all of it in the window, drawn bigger too), holding in its top left corner, `scaled_in` in, a
/// block 60×40, `block_r` round, drawn `block_scale` as big again as the card is, about its top left.
fn scaled_card_faults(card_r : Double, block_r : Double, card_scale? : Double = 1.0, block_scale? : Double = 1.0) -> Array[String] {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0, corners_held=false)
  set_view_app(fn(root) {
    root.box(fn(room) {
      room.pad(Is(40.0)) |> ignore
      room.box(fn(card) {
        card
        .width(Is(Some(200.0)))
        .height(Is(Some(120.0)))
        .pad(Is(scaled_in))
        .ground(Is(0x333333FFL))
        .radius(Is(card_r))
        .scale(Is(card_scale))
        |> ignore
        card.box(fn(b) {
          b
          .width(Is(Some(60.0)))
          .height(Is(Some(40.0)))
          .ground(Is(0xEEEEEEFFL))
          .radius(Is(block_r))
          .scale(Is(block_scale), about=@view.At(0.0, 0.0))
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  g().corner_ladder = scaled_ladder
  t.corner_faults()
}

///|
test "corners under a scale: a card 26 round and a block 18 round concentric in its corner, both drawn 1.04 as big (27.04, 18.72): nothing said, as at rest" {
  let block_r = concentric(26.0, scaled_in)
  let rest = scaled_card_faults(26.0, block_r)
  let lifted = scaled_card_faults(26.0, block_r, card_scale=scaled_lift)
  assert_eq((rest, lifted), ([], []), msg=lifted.join("\n"))
}

///|
test "corners under a scale: the card drawn 1.04 as big and the block in its corner not, drawn as the lifted one is (18.72 round, 8.32 in): each its own scale, as drawn, the card's 27.04 said off the ladder" {
  let block_r = concentric(26.0, scaled_in) * scaled_lift
  let faults = scaled_card_faults(26.0, block_r, card_scale=scaled_lift, block_scale=1.0 / scaled_lift)
  assert_true(
    faults
    .iter()
    .any(fn(f) {
      f.contains("(corner 27.04") &&
      !f.contains("as said") &&
      f.contains("something lies in its top left, and its corner is not one of the ladder's")
    }),
    msg=faults.join("\n"),
  )
}

///|
test "corners under a scale: a card 27 round at rest, a block concentric in its corner: said off the ladder, as ever" {
  let faults = scaled_card_faults(27.0, concentric(27.0, scaled_in))
  assert_true(
    faults.iter().any(fn(f) { f.contains("(corner 27): something lies in its top left, and its corner is not one of the ladder's") }),
    msg=faults.join("\n"),
  )
}
