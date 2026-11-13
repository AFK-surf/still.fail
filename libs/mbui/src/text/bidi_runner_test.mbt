// Runs the sample of BidiCharacterTest.txt (bidi_conformance_test.mbt, made by scripts/gen_bidi.py): each case's
// paragraph level, its characters' levels after L1 (x: removed by X9, not compared) and their visual order.

///|
fn hex_cp(s : String) -> Int {
  let mut v = 0
  for c in s {
    let d = c.to_int()
    v = v * 16 +
      (if d >= 48 && d <= 57 {
        d - 48
      } else if d >= 65 && d <= 70 {
        d - 55
      } else {
        d - 87
      })
  }
  v
}

///|
fn dec(s : String) -> Int {
  let mut v = 0
  for c in s {
    v = v * 10 + (c.to_int() - 48)
  }
  v
}

///|
fn ints(s : String) -> Array[String] {
  if s == "" {
    []
  } else {
    s.split(",").map(fn(x) { x.to_owned() }).to_array()
  }
}

///|
fn run_bidi_conformance(chunks : Array[String]) -> Unit raise {
  let mut total = 0
  let mut fails = 0
  for chunk in chunks {
    for line in chunk.split("\n") {
      let line = line.to_owned()
      if line.length() == 0 {
        continue
      }
      total = total + 1
      let f = line.split(";").map(fn(x) { x.to_owned() }).to_array()
      let cps = ints(f[0]).map(hex_cp)
      let pdir = dec(f[1])
      let plevel = dec(f[2])
      let want = ints(f[3])
      let order = ints(f[4]).map(dec)
      let sb = StringBuilder()
      let at = []
      let mut off = 0
      for c in cps {
        at.push(off)
        sb.write_char(c.unsafe_to_char())
        off = off + (if c >= 0x10000 { 2 } else { 1 })
      }
      let s = sb.to_string()
      let b = @text.Bidi::new(s, dir=if pdir == 2 { -1 } else { pdir })
      let lv = b.line_levels(0, s.length())
      let mut ok = cps.length() == 0 || b.paragraph_level(0) == plevel
      let kept = []
      let kept_lv = []
      for i, w in want {
        if w == "x" {
          continue
        }
        let l = lv[at[i]]
        if w != l.to_string() {
          ok = false
        }
        kept.push(i)
        kept_lv.push(l)
      }
      let vis = @text.visual_order(kept_lv[:]).map(fn(k) { kept[k] })
      if vis != order {
        ok = false
      }
      if !ok {
        fails = fails + 1
        if fails <= 20 {
          let got = at.map(fn(o) { lv[o].to_string() }).join(",")
          println(
            "bidi case \{total}: \{f[0]} dir \{pdir}: levels want \{f[3]} got \{got} (para \{b.paragraph_level(0)} want \{plevel}); order want \{f[4]} got \{vis.map(fn(x) { x.to_string() }).join(",")}",
          )
        }
      }
    }
  }
  println("bidi conformance (Unicode \{@text.unicode_version}): \{total - fails}/\{total} pass")
  assert_eq(fails, 0)
}

///|
test "bidi API" {
  // all left to right: no levels to speak of
  let b = @text.Bidi::new("Hello, world 123")
  assert_eq(b.is_mixed(), false)
  // Arabic with digits in a left-to-right paragraph: the Arabic word and the number after it read right to left
  let s = "abc \u{645}\u{631}\u{62D}\u{628}\u{627} 123 def"
  let m = @text.Bidi::new(s)
  assert_eq(m.is_mixed(), true)
  assert_eq(m.paragraph_level(0), 0)
  let lv = m.line_levels(0, s.length())
  assert_eq(lv[0], 0)
  assert_eq(lv[4], 1)
  assert_eq(lv[10], 2)
  assert_eq(lv[13], 0)
  // a right-to-left paragraph: its first strong character is Hebrew
  let h = @text.Bidi::new("\u{5E9}\u{5DC}\u{5D5}\u{5DD} world")
  assert_eq(h.paragraph_level(0), 1)
  assert_eq(@text.visual_order([1, 1, 1, 0, 0][:]), [2, 1, 0, 3, 4])
  assert_eq(@text.visual_order([0, 1, 1, 2, 2, 1, 0][:]), [0, 5, 3, 4, 2, 1, 6])
}
