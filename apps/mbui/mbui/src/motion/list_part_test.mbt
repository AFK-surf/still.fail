// A list told its rows (list_keys) in a part kept as its nodes (Ctx::kept_part: the chats' pane beside a chat that
// moves), as a host draws it: frames built for what changed beside it put its nodes back without building it, the list
// shown in them all the same; its rows changed after them move from where they were, not put in their new places at
// once as a list come back to is.

///|
/// How far across the list's part goes; the part beside it is past it.
let glide_list_w : Double = 280.0

///|
/// What the last frame drew of the list (Tester::drawn_text's instances left of the part beside it), a glyph's place
/// in the atlas left out.
fn glide_drawn(t : @ui.Tester) -> Array[String] {
  kept_drawn(t).filter(fn(line) {
    // ("inst", then its numbers in 1/64ths: its left the first)
    let f = line.split(" ").map(fn(v) { v.to_string() }).collect()
    f.length() > 1 && glide_number(f[1]) < (glide_list_w * 64.0).to_int()
  })
}

///|
/// A whole number as drawn_text writes it.
fn glide_number(s : String) -> Int {
  let mut n = 0
  let mut sign = 1
  for ch in s {
    if ch == '-' {
      sign = -1
    } else {
      n = n * 10 + (ch.to_int() - '0'.to_int())
    }
  }
  sign * n
}

///|
test "a list in a part kept while what is beside it is built moves its rows as they change" {
  let keys = @signals.signal(Array::makei(10, fn(i) { "r\{i}" }))
  let t = @ui.Tester::new(
    fn(c) {
      c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), fn() {
        c.box(w=Px(glide_list_w), h=Fill(1.0), fn() {
          c.kept_part(c.id("list"), "", fn() {
            let ks = keys.get()
            @motion.list_keys(c, "glide", ks) |> ignore
            c.list("glide", ks.length(), 40.0, fn(i) {
              let k = ks[i]
              let b = c.box(h=Px(40.0), padx=10.0, fn() { c.text(k, size=12.0) |> ignore })
              @motion.layout(c, b, "row/" + k)
            })
            |> ignore
          })
        })
        |> ignore
        // (a part built each frame: what it shows reads the clock)
        c.box(w=Fill(1.0), h=Fill(1.0), fn() {
          c.kept_part(c.id("beside"), "", fn() {
            c.text("\{(c.now() / kept_look_ms).floor()}", size=12.0) |> ignore
          })
        })
        |> ignore
      })
      |> ignore
    },
    w=360.0,
    h=480.0,
    platform=2,
  )
  t.check_looks(false)
  t.draw()
  // (a host's frames, each of the display's: those the test steps through without changing anything are built for
  // the part beside the list alone)
  t.set_frame_period(t.frame_period())
  for _ in 0..<5 {
    t.run_for(kept_look_ms)
  }
  // the first row gone below the fifth
  let now = keys.get().copy()
  let first = now.remove(0)
  now.insert(5, first)
  keys.set(now)
  let out = []
  for _ in 0..<12 {
    t.run_for(kept_look_ms)
    out.push(glide_drawn(t))
  }
  assert_true(out[0] != out[out.length() - 1], msg="the rows were in their new places at once")
}
