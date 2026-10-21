// Line break opportunities (UAX #14, rules LB1-LB31 with the default
// tailoring; LB1 resolves AI, SG and XX to AL, SA to CM or AL by general
// category, and CJ to NS). Offsets are UTF-16 code-unit offsets.

// Sets of classes: bit i of class_sets[k] says whether class k is in set i.

///|
const HARD = 1

///|
const NO_BASE = 2

///|
const LB13 = 4

///|
const LB15A_BEFORE = 8

///|
const LB15B_AFTER = 16

///|
const LB20A_BEFORE = 32

///|
const LB21 = 64

///|
const AL_HL = 128

///|
const AL_HL_NU = 256

///|
const HY_HH = 512

///|
const CL_CP = 1024

///|
const PR_PO = 2048

///|
const SY_IS = 4096

///|
const ID_EB_EM = 8192

///|
const JAMO = 16384

///|
fn make_class_sets() -> FixedArray[Int] {
  let m = FixedArray::make(64, 0)
  let sets = [
    (HARD, [BK, CR, LF, NL]),
    (NO_BASE, [BK, CR, LF, NL, SP, ZW]),
    (LB13, [CL, CP, EX, SY]),
    (LB15A_BEFORE, [BK, CR, LF, NL, OP, QU, GL, SP, ZW]),
    (LB15B_AFTER, [SP, GL, WJ, CL, QU, CP, EX, IS, SY, BK, CR, LF, NL, ZW]),
    (LB20A_BEFORE, [BK, CR, LF, NL, SP, ZW, CB, GL]),
    (LB21, [BA, HH, HY, NS]),
    (AL_HL, [AL, HL]),
    (AL_HL_NU, [AL, HL, NU]),
    (HY_HH, [HY, HH]),
    (CL_CP, [CL, CP]),
    (PR_PO, [PR, PO]),
    (SY_IS, [SY, IS]),
    (ID_EB_EM, [ID, EB, EM]),
    (JAMO, [JL, JV, JT, H2, H3]),
  ]
  for e in sets {
    let (bit, ks) = e
    for k in ks {
      m[k] = m[k] | bit
    }
  }
  m
}

///|
let class_sets : FixedArray[Int] = make_class_sets()

///|
fn has(set : Int, k : Int) -> Bool {
  k >= 0 && (class_sets[k] & set) != 0
}

///|
let u_ea = 1

///|
let u_xpcn = 2

///|
let u_pi = 4

///|
let u_pf = 8

///|
let u_dotted = 16

///|
let u_zwj_end = 32

///|
/// The text as LB9 sees it: a unit is a code point with the combining marks
/// and ZWJs that it absorbs (LB9), or a lone mark treated as AL (LB10).
priv struct Units {
  start : Array[Int]
  cls : Array[Int]
  flags : Array[Int]
  ri_run : Array[Int]
}

///|
fn Units::make(s : String) -> Units {
  let n = s.length()
  let u = { start: [], cls: [], flags: [], ri_run: [] }
  let mut i = 0
  while i < n {
    let c = code_point_at(s, i)
    let p = line_table.get(c)
    let k = p & 63
    let m = u.cls.length()
    if (k == CM || k == ZWJ) && m > 0 && !has(NO_BASE, u.cls[m - 1]) {
      // LB9: X (CM | ZWJ)* is X
      let f = (u.flags[m - 1] | u_zwj_end) ^ u_zwj_end
      u.flags[m - 1] = if k == ZWJ { f | u_zwj_end } else { f }
    } else {
      let (cls, flags) = if k == CM || k == ZWJ {
        (AL, 0) // LB10
      } else {
        (k, (p >> 6) | (if c == 0x25CC { u_dotted } else { 0 }))
      }
      u.start.push(i)
      u.cls.push(cls)
      u.flags.push(if k == ZWJ { flags | u_zwj_end } else { flags })
      u.ri_run.push(
        if cls != RI {
          0
        } else if m > 0 {
          u.ri_run[m - 1] + 1
        } else {
          1
        },
      )
    }
    i = i + cp_len(c)
  }
  u
}

///|
fn Units::flag(self : Units, k : Int, f : Int) -> Bool {
  k >= 0 && k < self.flags.length() && (self.flags[k] & f) != 0
}

///|
/// The class of unit k, or -1 before the start or after the end of text.
fn Units::at(self : Units, k : Int) -> Int {
  if k >= 0 && k < self.cls.length() {
    self.cls[k]
  } else {
    -1
  }
}

///|
/// The last unit at or before k that is not a space.
fn Units::skip_sp(self : Units, k : Int) -> Int {
  let mut j = k
  while j >= 0 && self.cls[j] == SP {
    j = j - 1
  }
  j
}

///|
fn Units::brahmic(self : Units, k : Int) -> Bool {
  let c = self.at(k)
  c == AK || c == AS || self.flag(k, u_dotted)
}

///|
/// Before unit u (0 < u < count): 0 no break, 1 break allowed, 2 mandatory.
fn Units::decide(self : Units, u : Int) -> Int {
  let a = self.cls[u - 1]
  let b = self.cls[u]
  let nb = self.at(u + 1)
  // LB4, LB5: hard line breaks
  if a == BK {
    return 2
  }
  if a == CR && b == LF {
    return 0
  }
  if a == CR || a == LF || a == NL {
    return 2
  }
  // LB6, LB7
  if has(HARD, b) || b == SP || b == ZW {
    return 0
  }
  // LB8: ZW SP* ÷
  if self.at(self.skip_sp(u - 1)) == ZW {
    return 1
  }
  // LB8a: ZWJ ×
  if self.flag(u - 1, u_zwj_end) {
    return 0
  }
  // LB11, LB12, LB12a
  if a == WJ || b == WJ || a == GL {
    return 0
  }
  if b == GL && a != SP && !has(HY_HH, a) {
    return 0
  }
  // LB13
  if has(LB13, b) {
    return 0
  }
  let before_sp = self.skip_sp(u - 1)
  let bs = self.at(before_sp)
  // LB14: OP SP* ×
  if bs == OP {
    return 0
  }
  // LB15a: (sot | BK | CR | LF | NL | OP | QU | GL | SP | ZW) [Pi&QU] SP* ×
  if bs == QU && self.flag(before_sp, u_pi) {
    let k = self.at(before_sp - 1)
    if k < 0 || has(LB15A_BEFORE, k) {
      return 0
    }
  }
  // LB15b: × [Pf&QU] (SP | GL | WJ | CL | QU | CP | EX | IS | SY | BK | CR
  //   | LF | NL | ZW | eot)
  if b == QU && self.flag(u, u_pf) && (nb < 0 || has(LB15B_AFTER, nb)) {
    return 0
  }
  // LB15c, LB15d
  if a == SP && b == IS && nb == NU {
    return 1
  }
  if b == IS {
    return 0
  }
  // LB16, LB17
  if has(CL_CP, bs) && b == NS {
    return 0
  }
  if bs == B2 && b == B2 {
    return 0
  }
  // LB18
  if a == SP {
    return 1
  }
  // LB19
  if b == QU && !self.flag(u, u_pi) {
    return 0
  }
  if a == QU && !self.flag(u - 1, u_pf) {
    return 0
  }
  // LB19a
  if b == QU && (!self.flag(u - 1, u_ea) || nb < 0 || !self.flag(u + 1, u_ea)) {
    return 0
  }
  if a == QU && (!self.flag(u, u_ea) || u < 2 || !self.flag(u - 2, u_ea)) {
    return 0
  }
  // LB20
  if a == CB || b == CB {
    return 1
  }
  // LB20a: (sot | BK | CR | LF | NL | SP | ZW | CB | GL) (HY | HH) × (AL | HL)
  if has(HY_HH, a) && has(AL_HL, b) {
    let k = self.at(u - 2)
    if k < 0 || has(LB20A_BEFORE, k) {
      return 0
    }
  }
  // LB21, LB21a, LB21b, LB22
  if has(LB21, b) || a == BB {
    return 0
  }
  if has(HY_HH, a) && self.at(u - 2) == HL && b != HL {
    return 0
  }
  if (a == SY && b == HL) || b == IN {
    return 0
  }
  // LB23, LB23a, LB24
  if (has(AL_HL, a) && b == NU) || (a == NU && has(AL_HL, b)) {
    return 0
  }
  if (a == PR && has(ID_EB_EM, b)) || (has(ID_EB_EM, a) && b == PO) {
    return 0
  }
  if (has(PR_PO, a) && has(AL_HL, b)) || (has(AL_HL, a) && has(PR_PO, b)) {
    return 0
  }
  // LB25: numbers
  if has(PR_PO, b) {
    let mut j = u - 1
    if has(CL_CP, self.cls[j]) {
      j = j - 1
    }
    while j >= 0 && has(SY_IS, self.cls[j]) {
      j = j - 1
    }
    if self.at(j) == NU {
      return 0
    }
  }
  if has(PR_PO, a) &&
    (b == NU || (b == OP && (nb == NU || (nb == IS && self.at(u + 2) == NU)))) {
    return 0
  }
  if (a == HY || a == IS) && b == NU {
    return 0
  }
  if b == NU {
    let mut j = u - 1
    while j >= 0 && has(SY_IS, self.cls[j]) {
      j = j - 1
    }
    if self.at(j) == NU {
      return 0
    }
  }
  // LB26, LB27: Korean syllable blocks
  if a == JL && (b == JL || b == JV || b == H2 || b == H3) {
    return 0
  }
  if (a == JV || a == H2) && (b == JV || b == JT) {
    return 0
  }
  if (a == JT || a == H3) && b == JT {
    return 0
  }
  if (has(JAMO, a) && b == PO) || (a == PR && has(JAMO, b)) {
    return 0
  }
  // LB28
  if has(AL_HL, a) && has(AL_HL, b) {
    return 0
  }
  // LB28a: Brahmic orthographic syllables
  if a == AP && self.brahmic(u) {
    return 0
  }
  if self.brahmic(u - 1) && (b == VF || b == VI) {
    return 0
  }
  if a == VI &&
    self.brahmic(u - 2) &&
    (b == AK || self.flag(u, u_dotted)) {
    return 0
  }
  if self.brahmic(u - 1) && self.brahmic(u) && nb == VF {
    return 0
  }
  // LB29, LB30
  if a == IS && has(AL_HL, b) {
    return 0
  }
  if has(AL_HL_NU, a) && b == OP && !self.flag(u, u_ea) {
    return 0
  }
  if a == CP && !self.flag(u - 1, u_ea) && has(AL_HL_NU, b) {
    return 0
  }
  // LB30a: regional indicator pairs
  if a == RI && b == RI && self.ri_run[u - 1] % 2 == 1 {
    return 0
  }
  // LB30b
  if b == EM && (a == EB || self.flag(u - 1, u_xpcn)) {
    return 0
  }
  // LB31
  1
}

///|
/// Line breaks before each offset of `s`: an array of length + 1 entries,
/// 0 where a line must not break, 1 where it may, 2 where it must (after a
/// hard line break, and at the end of text, LB3). Offsets inside a code
/// point or a combining sequence are 0.
pub fn line_breaks(s : String) -> FixedArray[Int] {
  let n = s.length()
  let out = FixedArray::make(n + 1, 0)
  if n == 0 {
    return out
  }
  let u = Units::make(s)
  for k in 1..<u.cls.length() {
    out[u.start[k]] = u.decide(k)
  }
  out[n] = 2
  out
}

///|
/// The line break opportunities of `s`: offsets where a line may end, each
/// with whether it must (a hard line break, or the end of text).
pub fn break_opportunities(s : String) -> Array[(Int, Bool)] {
  let b = line_breaks(s)
  let out = []
  for i in 1..<b.length() {
    if b[i] != 0 {
      out.push((i, b[i] == 2))
    }
  }
  out
}
