// Rule 4 of the spacing rules (gaps.mbt) in a capsule holding a mark concentric with one end and lines of words at the
// other (a file's card): the mark stands so, the lines' box as clear of the curve at its end as of the capsule's top
// and foot.

///|
/// A capsule 52 high: a mark (24, drawn) concentric with one end, 14 in, then words 8 after it, their end `words_end`
/// from the other end: two lines one under the other (14 and 11 on the Tester's font, 20 and 16 high as a file's card's
/// on a desktop), or the first alone (`lines` 1); the mark at its left end, or (`mark_left` false) at its right; as
/// wide as what it holds (in a row, as a message lays its files' cards out). Rule 4's faults in it.
fn capsule_words_faults(words_end : Double, lines? : Int = 2, mark_left? : Bool = true) -> Array[String] {
  let t = Tester::new(
    fn(c) {
      let (pl, pr) = if mark_left { (14.0, words_end) } else { (words_end, 14.0) }
      c.row(align=AStart, fn() {
        c.box(dir=Row, h=Px(52.0), pl~, pr~, gap=8.0, radius=26.0, bg=0xE4E4E4FFL, align=ACenter, fn() {
          let mark = fn() {
            c.box(w=Px(24.0), h=Px(24.0), fn() {
              let sheet = shape_of([([5.0, 3.0, 19.0, 3.0, 19.0, 21.0, 5.0, 21.0], true)], fill=0x24272BFFL)
              c.shapes([sheet], w=Px(24.0), h=Px(24.0)) |> ignore
            })
            |> ignore
          }
          let words = fn() {
            c.box(fn() {
              c.text("signals-progress.md", size=14.0) |> ignore
              if lines > 1 {
                c.text("14 KB", size=11.0) |> ignore
              }
            })
            |> ignore
          }
          if mark_left {
            mark()
            words()
          } else {
            words()
            mark()
          }
        })
        |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=200.0,
    corners_held=false,
  )
  t.draw()
  t.gap_faults().filter(fn(f) { f.has_prefix("rule 4") })
}

///|
test "rule 4: two lines of words at a capsule's end with a mark concentric with its other end, 14 in as the mark is (their corners 4.4 from the curve, 8 from its top) found, 24 in not; at either end" {
  assert_true(capsule_words_faults(14.0).length() > 0, msg="14 in, after the mark")
  assert_eq(capsule_words_faults(24.0), [])
  assert_true(capsule_words_faults(14.0, mark_left=false).length() > 0, msg="14 in, before the mark")
  assert_eq(capsule_words_faults(24.0, mark_left=false), [])
}

///|
test "rule 4: one line of words at a capsule's end with a mark concentric with its other end stands by its box, as far in as the mark's" {
  assert_eq(capsule_words_faults(14.0, lines=1), [])
  assert_true(capsule_words_faults(24.0, lines=1).length() > 0, msg="24 in beside the mark's 14")
}
