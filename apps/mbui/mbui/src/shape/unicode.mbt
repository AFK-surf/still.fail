// harfrust's Unicode properties (unicode/mod.rs, the builtin tables): general category, combining class and
// HarfBuzz's modified one, mirroring, script, canonical composition and decomposition, emoji, default ignorables.

///|
pub const GC_CONTROL : Int = 0

///|
pub const GC_FORMAT : Int = 1

///|
pub const GC_UNASSIGNED : Int = 2

///|
pub const GC_PRIVATE_USE : Int = 3

///|
pub const GC_SURROGATE : Int = 4

///|
pub const GC_LOWERCASE_LETTER : Int = 5

///|
pub const GC_MODIFIER_LETTER : Int = 6

///|
pub const GC_OTHER_LETTER : Int = 7

///|
pub const GC_TITLECASE_LETTER : Int = 8

///|
pub const GC_UPPERCASE_LETTER : Int = 9

///|
pub const GC_SPACING_MARK : Int = 10

///|
pub const GC_ENCLOSING_MARK : Int = 11

///|
pub const GC_NON_SPACING_MARK : Int = 12

///|
pub const GC_DECIMAL_NUMBER : Int = 13

///|
pub const GC_LETTER_NUMBER : Int = 14

///|
pub const GC_OTHER_NUMBER : Int = 15

///|
pub const GC_CONNECT_PUNCTUATION : Int = 16

///|
pub const GC_DASH_PUNCTUATION : Int = 17

///|
pub const GC_CLOSE_PUNCTUATION : Int = 18

///|
pub const GC_FINAL_PUNCTUATION : Int = 19

///|
pub const GC_INITIAL_PUNCTUATION : Int = 20

///|
pub const GC_OTHER_PUNCTUATION : Int = 21

///|
pub const GC_OPEN_PUNCTUATION : Int = 22

///|
pub const GC_CURRENCY_SYMBOL : Int = 23

///|
pub const GC_MODIFIER_SYMBOL : Int = 24

///|
pub const GC_MATH_SYMBOL : Int = 25

///|
pub const GC_OTHER_SYMBOL : Int = 26

///|
pub const GC_LINE_SEPARATOR : Int = 27

///|
pub const GC_PARAGRAPH_SEPARATOR : Int = 28

///|
pub const GC_SPACE_SEPARATOR : Int = 29

///|
fn gc_is_mark(gc : Int) -> Bool {
  gc == GC_SPACING_MARK || gc == GC_ENCLOSING_MARK || gc == GC_NON_SPACING_MARK
}

///|
fn gc_flag(gc : Int) -> Int {
  if gc < 32 {
    1 << gc
  } else {
    0
  }
}

///|
fn ucd_b4(base : Int, i : Int) -> Int {
  (ucd_u8[base + (i >> 1)] >> ((i & 1) << 2)) & 15
}

///|
fn ucd_gc(u : Int) -> Int {
  if u < 1114110 && u >= 0 {
    ucd_u8[7944 +
    (
      (ucd_u8[2176 + (ucd_u16[(ucd_u8[u >> 1 >> 3 >> 5] << 5) + ((u >> 1 >> 3) & 31)] + ((u >> 1) & 7))] << 1) +
      (u & 1)
    )]
  } else {
    2
  }
}

///|
fn ucd_ccc(u : Int) -> Int {
  if u < 125259 && u >= 0 {
    ucd_u8[10432 +
    (
      (
        ucd_u8[9308 +
        (
          (ucd_u8[8577 + ((ucd_u8[8332 + (u >> 2 >> 3 >> 4)] << 4) + ((u >> 2 >> 3) & 15))] << 3) +
          ((u >> 2) & 7)
        )] <<
        2
      ) +
      (u & 3)
    )]
  } else {
    0
  }
}

///|
fn ucd_bmg(u : Int) -> Int {
  if u < 121617 && u >= 0 {
    ucd_palette[ucd_u8[11624 +
    (
      ucd_u8[11272 + ((ucd_u8[11071 + ((ucd_b4(10952, u >> 2 >> 3 >> 4) << 4) + ((u >> 2 >> 3) & 15))] << 3) + ((u >> 2) & 7))] +
      (u & 3)
    )]]
  } else {
    0
  }
}

///|
fn ucd_sc(u : Int) -> Int {
  if u < 918000 && u >= 0 {
    ucd_u8[12721 +
    (
      ucd_u16[4520 +
      (ucd_u16[3392 + ((ucd_u8[11824 + (u >> 3 >> 3 >> 4)] << 4) + ((u >> 3 >> 3) & 15))] + ((u >> 3) & 7))] +
      (u & 7)
    )]
  } else {
    2
  }
}

///|
fn ucd_dm(u : Int) -> Int {
  if u < 195102 && u >= 0 {
    ucd_u16[7816 + ((ucd_u8[19095 + ((ucd_u8[18713 + (u >> 4 >> 5)] << 5) + ((u >> 4) & 31))] << 4) + (u & 15))]
  } else {
    0
  }
}

///|
pub fn general_category(c : Int) -> Int {
  ucd_gc(c)
}

///|
pub fn combining_class(c : Int) -> Int {
  ucd_ccc(c)
}

///|
/// A character's script as an ISO 15924 tag in an Int ('Latn' as 0x4C61746E).
pub fn script_of(c : Int) -> Int {
  if c > 0x10FFFF {
    tag("Zzzz")
  } else {
    ucd_sc_map[ucd_sc(c)]
  }
}

///|
pub fn mirroring(c : Int) -> Int? {
  let d = ucd_bmg(c)
  if d == 0 {
    None
  } else {
    Some(c + d)
  }
}

///|
let modified_ccc : FixedArray[Int] = {
  let t = FixedArray::makei(256, fn(i) { i })
  let pairs = [
    (10, 22),
    (11, 15),
    (12, 16),
    (13, 17),
    (14, 23),
    (15, 18),
    (16, 19),
    (17, 20),
    (18, 21),
    (19, 14),
    (20, 24),
    (21, 12),
    (22, 25),
    (23, 13),
    (24, 10),
    (25, 11),
    (26, 26),
    (27, 28),
    (28, 29),
    (29, 30),
    (30, 31),
    (31, 32),
    (32, 33),
    (33, 27),
    (34, 34),
    (35, 35),
    (36, 36),
    (84, 4),
    (91, 5),
    (103, 3),
    (107, 107),
    (118, 118),
    (122, 122),
    (129, 129),
    (130, 132),
    (132, 131),
  ]
  for p in pairs {
    t[p.0] = p.1
  }
  t
}

///|
pub fn modified_combining_class(c : Int) -> Int {
  if c == 0x1A60 || c == 0x0FC6 {
    return 254
  }
  if c == 0x0F39 {
    return 127
  }
  modified_ccc[combining_class(c)]
}

///|
pub fn is_emoji_extended_pictographic(u : Int) -> Bool {
  if u < 0 || u >= 131070 {
    return false
  }
  let b4 = fn(i : Int) { (emoji_u8[i >> 1] >> ((i & 1) << 2)) & 15 }
  let i = (emoji_u8[64 + ((b4(u >> 6 >> 4) << 4) + ((u >> 6) & 15))] << 6) + (u & 63)
  ((emoji_u8[224 + (i >> 3)] >> (i & 7)) & 1) != 0
}

///|
pub fn is_default_ignorable(ch : Int) -> Bool {
  let plane = ch >> 16
  if plane == 0 {
    match ch >> 8 {
      0x00 => ch == 0x00AD
      0x03 => ch == 0x034F
      0x06 => ch == 0x061C
      0x17 => ch >= 0x17B4 && ch <= 0x17B5
      0x18 => ch >= 0x180B && ch <= 0x180F
      0x20 => (ch >= 0x200B && ch <= 0x200F) || (ch >= 0x202A && ch <= 0x202E) || (ch >= 0x2060 && ch <= 0x206F)
      0xFE => (ch >= 0xFE00 && ch <= 0xFE0F) || ch == 0xFEFF
      0xFF => ch >= 0xFFF0 && ch <= 0xFFF8
      _ => false
    }
  } else {
    match plane {
      0x01 => ch >= 0x1D173 && ch <= 0x1D17A
      0x0E => ch >= 0xE0000 && ch <= 0xE0FFF
      _ => false
    }
  }
}

///|
pub fn is_variation_selector(c : Int) -> Bool {
  (c >= 0xFE00 && c <= 0xFE0F) || (c >= 0xE0100 && c <= 0xE01EF)
}

///|
/// The space a character is when the font has no glyph for it (space_fallback::SpaceCode).
fn space_fallback(c : Int) -> Int {
  match c {
    0x0020 | 0x00A0 => 18
    0x2000 | 0x2002 => 2
    0x2001 | 0x2003 | 0x3000 => 1
    0x2004 => 3
    0x2005 => 4
    0x2006 => 6
    0x2007 => 19
    0x2008 => 20
    0x2009 => 5
    0x200A => 16
    0x202F => 21
    0x205F => 17
    _ => 0
  }
}

///|
fn hangul_compose(a : Int, b : Int) -> Int? {
  let s_base = 0xAC00
  let l_base = 0x1100
  let v_base = 0x1161
  let t_base = 0x11A7
  let t_count = 28
  let n_count = 21 * 28
  let s_count = 19 * n_count
  if l_base <= a && a < l_base + 19 && v_base <= b && b < v_base + 21 {
    Some(s_base + (a - l_base) * n_count + (b - v_base) * t_count)
  } else if s_base <= a && a <= s_base + s_count - t_count && t_base < b && b < t_base + t_count &&
    (a - s_base) % t_count == 0 {
    Some(a + (b - t_base))
  } else {
    None
  }
}

///|
fn hangul_decompose(ab : Int) -> (Int, Int)? {
  let s_base = 0xAC00
  let t_count = 28
  let n_count = 21 * 28
  let s_count = 19 * n_count
  let si = ab - s_base
  if si < 0 || si >= s_count {
    return None
  }
  if si % t_count != 0 {
    Some((s_base + si / t_count * t_count, 0x11A7 + si % t_count))
  } else {
    Some((0x1100 + si / n_count, 0x1161 + si % n_count / t_count))
  }
}

///|
pub fn compose(a : Int, b : Int) -> Int? {
  match hangul_compose(a, b) {
    Some(r) => return Some(r)
    None => ()
  }
  let u = if a >= 0 && a < 0x800 && b >= 0x300 && b < 0x380 {
    let k = (((a & 0x7FF).to_int64() << 21) | ((b & 0x7F).to_int64() << 14))
    let mask = (0x7FFL << 21) | (0x7FL << 14)
    let mut lo = 0
    let mut hi = ucd_dm2_u32_map.length() - 1
    let mut found = 0
    while lo <= hi {
      let mid = (lo + hi) / 2
      let key = ucd_dm2_u32_map[mid] & mask
      if key < k {
        lo = mid + 1
      } else if key > k {
        hi = mid - 1
      } else {
        found = (ucd_dm2_u32_map[mid] & 0x3FFFL).to_int()
        break
      }
    }
    found
  } else {
    let k = (a.to_int64() << 42) | (b.to_int64() << 21)
    let mask = (0x1FFFFFL << 42) | (0x1FFFFFL << 21)
    let mut lo = 0
    let mut hi = ucd_dm2_u64_map.length() - 1
    let mut found = 0
    while lo <= hi {
      let mid = (lo + hi) / 2
      let key = ucd_dm2_u64_map[mid] & mask
      if key < k {
        lo = mid + 1
      } else if key > k {
        hi = mid - 1
      } else {
        found = (ucd_dm2_u64_map[mid] & 0x1FFFFFL).to_int()
        break
      }
    }
    found
  }
  if u == 0 {
    None
  } else {
    Some(u)
  }
}

///|
/// A character's canonical decomposition: (a, 0) for a singleton, (a, b) for a pair.
pub fn decompose(ab : Int) -> (Int, Int)? {
  match hangul_decompose(ab) {
    Some(r) => return Some(r)
    None => ()
  }
  let mut i = ucd_dm(ab)
  if i == 0 {
    return None
  }
  i -= 1
  let p0 = ucd_dm1_p0_map.length()
  let p2 = ucd_dm1_p2_map.length()
  if i < p0 + p2 {
    let a = if i < p0 { ucd_dm1_p0_map[i] } else { 0x20000 | ucd_dm1_p2_map[i - p0] }
    return Some((a, 0))
  }
  i -= p0 + p2
  if i < ucd_dm2_u32_map.length() {
    let v = ucd_dm2_u32_map[i]
    return Some(((v >> 21).to_int(), (((v >> 14) & 0x7FL) | 0x300L).to_int()))
  }
  i -= ucd_dm2_u32_map.length()
  let v = ucd_dm2_u64_map[i]
  Some(((v >> 42).to_int(), ((v >> 21) & 0x1FFFFFL).to_int()))
}

///|
/// A four-letter tag as an Int.
pub fn tag(s : String) -> Int {
  let mut v = 0
  for i in 0..<4 {
    let c = if i < s.length() { s.code_unit_at(i).to_int() } else { 0x20 }
    v = (v << 8) | (c & 0xFF)
  }
  v
}
