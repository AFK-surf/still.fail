// Extended grapheme clusters (UAX #29, section 3), rules GB1-GB999
// including GB9c (Indic conjuncts) and GB11 (emoji zwj sequences).
// Offsets are UTF-16 code-unit offsets.

///|
const G_CR = 1

///|
const G_LF = 2

///|
const G_CONTROL = 3

///|
const G_EXTEND = 4

///|
const G_ZWJ = 5

///|
const G_RI = 6

///|
const G_PREPEND = 7

///|
const G_SPACING_MARK = 8

///|
const G_L = 9

///|
const G_V = 10

///|
const G_T = 11

///|
const G_LV = 12

///|
const G_LVT = 13

///|
const INCB_LINKER = 1

///|
const INCB_CONSONANT = 2

///|
const INCB_EXTEND = 3

///|
fn gcb(p : Int) -> Int {
  p & 15
}

///|
fn is_xpict(p : Int) -> Bool {
  (p & 16) != 0
}

///|
fn incb(p : Int) -> Int {
  (p >> 5) & 3
}

///|
fn is_ctl(g : Int) -> Bool {
  g == G_CONTROL || g == G_CR || g == G_LF
}

///|
/// GB3-GB9b: the decision from the two code points alone. true: break.
fn pair_breaks(a : Int, b : Int) -> Bool {
  if a == G_CR && b == G_LF {
    false
  } else if is_ctl(a) || is_ctl(b) {
    true
  } else if a == G_L && (b == G_L || b == G_V || b == G_LV || b == G_LVT) {
    false
  } else if (a == G_LV || a == G_V) && (b == G_V || b == G_T) {
    false
  } else if (a == G_LVT || a == G_T) && b == G_T {
    false
  } else if b == G_EXTEND || b == G_ZWJ || b == G_SPACING_MARK {
    false
  } else {
    a != G_PREPEND
  }
}

///|
/// The grapheme cluster boundary after offset `i`, which must be a boundary
/// itself (0 or a value returned by this function or `prev_grapheme`).
pub fn next_grapheme(s : String, i : Int) -> Int {
  let n = s.length()
  if i >= n {
    return n
  }
  let i = if i < 0 { 0 } else { i }
  let c0 = code_point_at(s, i)
  let mut p = grapheme_table.get(c0)
  let mut j = i + cp_len(c0)
  // context for GB12/13 (regional indicators so far, odd or even), GB11
  // (0: none, 1: ExtPict Extend*, 2: ExtPict Extend* ZWJ) and GB9c
  // (Linker InCB_Extend* just before)
  let mut ri = gcb(p) == G_RI
  let mut emoji = if is_xpict(p) { 1 } else { 0 }
  let mut linker = incb(p) == INCB_LINKER
  while j < n {
    let c = code_point_at(s, j)
    let q = grapheme_table.get(c)
    let a = gcb(p)
    let b = gcb(q)
    let brk = if pair_breaks(a, b) {
      if linker && incb(q) == INCB_CONSONANT && !is_ctl(a) {
        false
      } else if emoji == 2 && is_xpict(q) && a == G_ZWJ {
        false
      } else {
        !(ri && a == G_RI && b == G_RI)
      }
    } else {
      false
    }
    if brk {
      return j
    }
    ri = b == G_RI && !(ri && a == G_RI)
    emoji = if is_xpict(q) {
      1
    } else if emoji == 1 && b == G_EXTEND {
      1
    } else if emoji == 1 && b == G_ZWJ {
      2
    } else {
      0
    }
    linker = incb(q) == INCB_LINKER || (linker && incb(q) == INCB_EXTEND)
    p = q
    j = j + cp_len(c)
  }
  n
}

///|
/// Whether offset `i` (0 < i < length) is a boundary whatever comes before
/// the code point preceding it.
fn certain_boundary(s : String, i : Int) -> Bool {
  let a = grapheme_table.get(code_point_at(s, cp_before(s, i)))
  let b = grapheme_table.get(code_point_at(s, i))
  if !pair_breaks(gcb(a), gcb(b)) {
    return false
  }
  // the rules that look further back could still join them
  !(
    (gcb(a) == G_RI && gcb(b) == G_RI) ||
    (gcb(a) == G_ZWJ && is_xpict(b)) ||
    (incb(b) == INCB_CONSONANT && incb(a) != 0)
  )
}

///|
/// The last grapheme cluster boundary before offset `i`.
pub fn prev_grapheme(s : String, i : Int) -> Int {
  let n = s.length()
  let i = if i > n { n } else { i }
  if i <= 0 {
    return 0
  }
  let mut p = cp_before(s, i)
  while p > 0 && !certain_boundary(s, p) {
    p = cp_before(s, p)
  }
  let mut b = p
  while true {
    let q = next_grapheme(s, b)
    if q >= i {
      break
    }
    b = q
  }
  b
}

///|
/// All grapheme cluster boundaries of `s`, from 0 to its length (none for
/// an empty string).
pub fn graphemes(s : String) -> Array[Int] {
  let n = s.length()
  let out = []
  if n == 0 {
    return out
  }
  let mut i = 0
  out.push(0)
  while i < n {
    i = next_grapheme(s, i)
    out.push(i)
  }
  out
}
