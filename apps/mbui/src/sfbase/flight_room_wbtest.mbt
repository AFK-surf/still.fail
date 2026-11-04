///|
test "a short fragment gives way when different line breaks make flying text cross" {
  let pieces : Array[FlightPiece] = [
    { a: 0, b: 10, from: (0.0, 0.0), at: (0.0, 0.0, 100.0, 20.0) },
    { a: 10, b: 11, from: (100.0, 0.0), at: (0.0, 20.0, 10.0, 20.0) },
    { a: 11, b: 19, from: (0.0, 20.0), at: (10.0, 20.0, 80.0, 20.0) },
  ]
  assert_eq(flight_piece_room(pieces, 1, 0.0, 0.0, 0.0, 0.0), (0.0, 10.0))
  let (left, right) = flight_piece_room(pieces, 1, 0.0, 0.0, 0.5, 0.5)
  assert_true(left >= right, msg="the short fragment yields where the lines cross")
  assert_eq(flight_piece_room(pieces, 2, 0.0, 0.0, 0.5, 0.5), (0.0, 80.0))
  assert_eq(flight_piece_room(pieces, 1, 0.0, 0.0, 1.0, 1.0), (0.0, 10.0))
}
