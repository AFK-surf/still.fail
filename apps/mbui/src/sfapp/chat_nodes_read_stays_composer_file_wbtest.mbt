// A file and a quote added to the composer, on a chat's page made as nodes (chat_nodes_read_stays_composer_wbtest's
// steps and assertions, held here with those two): read up the message read stays where it is in every frame; at the
// end the last row goes up by just what the composer grew, the composer's ground never over it nor further from it.
// The first of them opens the composer's extras, its ground's way a Move as long as the furthest of what moves with
// it (350 ms on 小屏, 400 on 大屏; a line's 250): the room under the last row is as tall at each moment as that ground
// is drawn then (sfbase's foot_resizes, @motion.reshape_share), all of that way, one motion (until #6146's foot came
// at once there; given its way, it was cut at a Move's end by how far, 250 ms, the ground going on alone).

///|
/// Of what rs_composer found on screen `s` over a core `late` late, read up (else at the end), the file's and the quote's.
fn rsf_file(s : (String, Double, Double, Int), late : Double, at_end : Bool) -> Array[String] {
  rs_composer(s, late, at_end).filter(fn(said) { said.contains("a file added") || said.contains("a quote added") })
}

///|
test "a chat's page made as nodes, 小屏 and 大屏, the core 0, 120 and 400 ms late, read up and at the end: a file and a quote added to the composer; the message read stays, the last row up by what the composer grew, the composer never over it nor further from it" {
  let broken : Array[String] = []
  for s in long_screens {
    for late in [0.0, 120.0, 400.0] {
      for at_end in [false, true] {
        broken.append(rsf_file(s, late, at_end))
      }
    }
  }
  assert_eq(broken, [])
}
