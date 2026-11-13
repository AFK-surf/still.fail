// Bidirectional text, UAX #9: each character's embedding level (P2–P3, X1–X10, W1–W7, N0–N2, I1–I2), a line's
// levels with L1, the visual order of a line's pieces (L2) and the mirrored characters (L4). Explicit embeddings,
// overrides and isolates are followed; BidiCharacterTest.txt's cases pass (bidi_conformance_test.mbt, a sample).

///|
let bidi_table : RangeTable = RangeTable::decode(bidi_data)

///|
/// The Bidi_Class of a code point (B_L, B_R, …).
fn bidi_class(c : Int) -> Int {
  bidi_table.get(c)
}

///|
/// A bracket's pair and kind (1 opening, 2 closing), or (0, 0).
fn bracket_of(c : Int) -> (Int, Int) {
  let n = bidi_brackets.length() / 3
  let mut lo = 0
  let mut hi = n - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let v = bidi_brackets[mid * 3]
    if v == c {
      return (bidi_brackets[mid * 3 + 1], bidi_brackets[mid * 3 + 2])
    } else if v < c {
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  (0, 0)
}

///|
/// L4: the character drawn for `c` where it reads right to left (its Bidi_Mirroring_Glyph: "(" for ")"), or `c`.
pub fn mirror(c : Int) -> Int {
  let n = bidi_mirrors.length() / 2
  let mut lo = 0
  let mut hi = n - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let v = bidi_mirrors[mid * 2]
    if v == c {
      return bidi_mirrors[mid * 2 + 1]
    } else if v < c {
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  c
}

///|
/// The two angle brackets with canonical equivalents (BD16 matches them as one).
fn bracket_norm(c : Int) -> Int {
  if c == 0x2329 {
    0x3008
  } else if c == 0x232A {
    0x3009
  } else {
    c
  }
}

///|
fn is_isolate_initiator(t : Int) -> Bool {
  t == B_LRI || t == B_RLI || t == B_FSI
}

///|
fn is_removed_class(t : Int) -> Bool {
  t == B_LRE || t == B_LRO || t == B_RLE || t == B_RLO || t == B_PDF || t == B_BN
}

///|
/// The levels of a text's characters. `levels` and `classes` hold one entry per UTF-16 code unit (a surrogate pair
/// both halves alike); a character X9 removes (embedding controls, BN) takes the level of what is before it.
pub struct Bidi {
  levels : FixedArray[Int]
  classes : FixedArray[Int]
  para : FixedArray[Int]
  /// any level odd, or above 0
  mixed : Bool
}

///|
/// Strong direction for N0 and N1: 0 L, 1 R (EN and AN count as R), -1 neither.
fn strong_dir(t : Int) -> Int {
  if t == B_L {
    0
  } else if t == B_R || t == B_AL || t == B_EN || t == B_AN {
    1
  } else {
    -1
  }
}

///|
/// P2: the first strong character's direction in [a, b), skipping what isolates hold; -1 none.
fn first_strong(cls : FixedArray[Int], a : Int, b : Int) -> Int {
  let mut depth = 0
  for k in a..<b {
    let t = cls[k]
    if is_isolate_initiator(t) {
      depth = depth + 1
    } else if t == B_PDI {
      if depth > 0 {
        depth = depth - 1
      }
    } else if depth == 0 {
      if t == B_L {
        return 0
      }
      if t == B_R || t == B_AL {
        return 1
      }
    }
  }
  -1
}

///|
/// The levels of `s`, a paragraph at each paragraph separator (B). `dir`: 0 left to right, 1 right to left, -1 each
/// paragraph's own first strong character's (P2, P3).
pub fn Bidi::new(s : String, dir? : Int = -1) -> Bidi {
  let n = s.length()
  let cps = []
  let at = []
  let mut i = 0
  let mut complex = dir == 1
  while i < n {
    let c = code_point_at(s, i)
    cps.push(c)
    at.push(i)
    i = i + cp_len(c)
  }
  let m = cps.length()
  let cls = FixedArray::make(m, 0)
  for k in 0..<m {
    let t = bidi_class(cps[k])
    cls[k] = t
    if t == B_R ||
      t == B_AL ||
      t == B_AN ||
      (t >= B_LRE && t <= B_PDF) ||
      t == B_LRI ||
      t == B_RLI ||
      t == B_FSI {
      complex = true
    }
  }
  let levels = FixedArray::make(n, 0)
  let classes = FixedArray::make(n, 0)
  let para = FixedArray::make(n, 0)
  for k in 0..<m {
    classes[at[k]] = cls[k]
    if cps[k] >= 0x10000 {
      classes[at[k] + 1] = cls[k]
    }
  }
  if !complex {
    // no right-to-left character, nothing to embed: all level 0 (EN after L is L, W7)
    return { levels, classes, para, mixed: false }
  }
  let lv = FixedArray::make(m, 0)
  let pl = FixedArray::make(m, 0)
  let mut a = 0
  while a < m {
    let mut b = a
    while b < m && cls[b] != B_B {
      b = b + 1
    }
    if b < m {
      b = b + 1
    }
    resolve_paragraph(cps, cls, a, b, dir, lv, pl)
    a = b
  }
  let mut mixed = false
  for k in 0..<m {
    let o = at[k]
    levels[o] = lv[k]
    para[o] = pl[k]
    if cps[k] >= 0x10000 {
      levels[o + 1] = lv[k]
      para[o + 1] = pl[k]
    }
    if lv[k] > 0 {
      mixed = true
    }
  }
  { levels, classes, para, mixed }
}

///|
/// One paragraph [a, b) of code points: their levels into `lv`, the paragraph's into `pl`.
fn resolve_paragraph(
  cps : Array[Int],
  cls : FixedArray[Int],
  a : Int,
  b : Int,
  dir : Int,
  lv : FixedArray[Int],
  pl : FixedArray[Int],
) -> Unit {
  let len = b - a
  // BD9: each isolate initiator's matching PDI (b: none), and each PDI's initiator (-1: none)
  let match_pdi = FixedArray::make(len, b)
  let pdi_of = FixedArray::make(len, -1)
  let open = []
  for k in a..<b {
    let t = cls[k]
    if is_isolate_initiator(t) {
      open.push(k)
    } else if t == B_PDI && open.length() > 0 {
      let o = open.pop().unwrap()
      match_pdi[o - a] = k
      pdi_of[k - a] = o
    }
  }
  // P2, P3
  let para_level = if dir == 0 {
    0
  } else if dir == 1 {
    1
  } else if first_strong(cls, a, b) == 1 {
    1
  } else {
    0
  }
  for k in a..<b {
    pl[k] = para_level
  }
  // X1–X8
  let types = FixedArray::make(len, 0)
  let removed = FixedArray::make(len, false)
  let st_level = [para_level]
  let st_override = [0]
  let st_isolate = [false]
  let mut overflow_isolate = 0
  let mut overflow_embedding = 0
  let mut valid_isolate = 0
  fn top() {
    st_level.length() - 1
  }

  fn pop() {
    st_level.pop() |> ignore
    st_override.pop() |> ignore
    st_isolate.pop() |> ignore
  }

  fn next_odd(l : Int) {
    (l + 1) | 1
  }

  fn next_even(l : Int) {
    (l + 2) & -2
  }

  fn overridden(k : Int, t : Int) {
    let o = st_override[top()]
    types[k - a] = if o == 1 { B_L } else if o == 2 { B_R } else { t }
  }

  for k in a..<b {
    let t = cls[k]
    let j = k - a
    if t == B_RLE || t == B_LRE || t == B_RLO || t == B_LRO {
      let cur = st_level[top()]
      let nl = if t == B_RLE || t == B_RLO { next_odd(cur) } else { next_even(cur) }
      lv[k] = cur
      if nl <= 125 && overflow_isolate == 0 && overflow_embedding == 0 {
        st_level.push(nl)
        st_override.push(if t == B_RLO { 2 } else if t == B_LRO { 1 } else { 0 })
        st_isolate.push(false)
      } else if overflow_isolate == 0 {
        overflow_embedding = overflow_embedding + 1
      }
      removed[j] = true
      types[j] = t
    } else if is_isolate_initiator(t) {
      let cur = st_level[top()]
      lv[k] = cur
      overridden(k, t)
      let rtl = t == B_RLI ||
        (t == B_FSI && first_strong(cls, k + 1, match_pdi[j]) == 1)
      let nl = if rtl { next_odd(cur) } else { next_even(cur) }
      if nl <= 125 && overflow_isolate == 0 && overflow_embedding == 0 {
        valid_isolate = valid_isolate + 1
        st_level.push(nl)
        st_override.push(0)
        st_isolate.push(true)
      } else {
        overflow_isolate = overflow_isolate + 1
      }
    } else if t == B_PDI {
      if overflow_isolate > 0 {
        overflow_isolate = overflow_isolate - 1
      } else if valid_isolate > 0 {
        overflow_embedding = 0
        while !st_isolate[top()] {
          pop()
        }
        pop()
        valid_isolate = valid_isolate - 1
      }
      lv[k] = st_level[top()]
      overridden(k, t)
    } else if t == B_PDF {
      if overflow_isolate > 0 {
        ()
      } else if overflow_embedding > 0 {
        overflow_embedding = overflow_embedding - 1
      } else if !st_isolate[top()] && st_level.length() >= 2 {
        pop()
      }
      lv[k] = st_level[top()]
      removed[j] = true
      types[j] = t
    } else if t == B_B {
      lv[k] = para_level
      types[j] = t
    } else if t == B_BN {
      lv[k] = st_level[top()]
      removed[j] = true
      types[j] = t
    } else {
      lv[k] = st_level[top()]
      overridden(k, t)
    }
  }
  // X10: level runs, chained into isolating run sequences across matched isolates
  let seqs : Array[Array[Int]] = []
  let seq_of_initiator = FixedArray::make(len, -1)
  let run : Array[Int] = []
  fn close_run() {
    if run.length() == 0 {
      return
    }
    let first = run[0]
    let o = pdi_of[first - a]
    let id = if cls[first] == B_PDI && o >= 0 && seq_of_initiator[o - a] >= 0 {
      let s = seq_of_initiator[o - a]
      for x in run {
        seqs[s].push(x)
      }
      s
    } else {
      seqs.push(run.copy())
      seqs.length() - 1
    }
    let last = run[run.length() - 1]
    if is_isolate_initiator(cls[last]) && match_pdi[last - a] < b {
      seq_of_initiator[last - a] = id
    }
    run.clear()
  }

  for k in a..<b {
    if removed[k - a] {
      continue
    }
    if run.length() > 0 && lv[run[run.length() - 1]] != lv[k] {
      close_run()
    }
    run.push(k)
  }
  close_run()
  // the embedding levels, as X1–X8 left them (sos and eos are found from them, not from what I1–I2 make)
  let emb = FixedArray::make(len, 0)
  for k in a..<b {
    emb[k - a] = lv[k]
  }
  for seq in seqs {
    resolve_sequence(cps, cls, types, removed, emb, lv, a, b, para_level, match_pdi, seq)
  }
  // what X9 removed: the level of what is before it (else after it), so it stays beside it in any order
  for k in a..<b {
    if removed[k - a] {
      let mut p = k - 1
      while p >= a && removed[p - a] {
        p = p - 1
      }
      if p >= a {
        lv[k] = lv[p]
      } else {
        let mut q = k + 1
        while q < b && removed[q - a] {
          q = q + 1
        }
        lv[k] = if q < b { lv[q] } else { para_level }
      }
    }
  }
}

///|
/// W1–W7, N0–N2, I1–I2 over one isolating run sequence (code point indices, in order).
fn resolve_sequence(
  cps : Array[Int],
  cls : FixedArray[Int],
  types : FixedArray[Int],
  removed : FixedArray[Bool],
  emb : FixedArray[Int],
  lv : FixedArray[Int],
  a : Int,
  b : Int,
  para_level : Int,
  match_pdi : FixedArray[Int],
  seq : Array[Int],
) -> Unit {
  let n = seq.length()
  let level = emb[seq[0] - a]
  // sos, eos
  let mut p = seq[0] - 1
  while p >= a && removed[p - a] {
    p = p - 1
  }
  let before = if p >= a { emb[p - a] } else { para_level }
  let last = seq[n - 1]
  let after = if is_isolate_initiator(cls[last]) && match_pdi[last - a] >= b {
    para_level
  } else {
    let mut q = last + 1
    while q < b && removed[q - a] {
      q = q + 1
    }
    if q < b && !is_isolate_initiator(cls[last]) {
      emb[q - a]
    } else {
      para_level
    }
  }
  let sos = if (if before > level { before } else { level }) % 2 == 1 {
    B_R
  } else {
    B_L
  }
  let eos = if (if after > level { after } else { level }) % 2 == 1 {
    B_R
  } else {
    B_L
  }
  let t = FixedArray::make(n, 0)
  for j in 0..<n {
    t[j] = types[seq[j] - a]
  }
  // W1
  for j in 0..<n {
    if t[j] == B_NSM {
      t[j] = if j == 0 {
        sos
      } else if is_isolate_initiator(t[j - 1]) || t[j - 1] == B_PDI {
        B_ON
      } else {
        t[j - 1]
      }
    }
  }
  // W2, W3
  let mut strong = sos
  for j in 0..<n {
    let x = t[j]
    if x == B_L || x == B_R || x == B_AL {
      strong = x
    } else if x == B_EN && strong == B_AL {
      t[j] = B_AN
    }
  }
  for j in 0..<n {
    if t[j] == B_AL {
      t[j] = B_R
    }
  }
  // W4
  for j in 1..<(n - 1) {
    let x = t[j]
    if x == B_ES && t[j - 1] == B_EN && t[j + 1] == B_EN {
      t[j] = B_EN
    } else if x == B_CS && t[j - 1] == B_EN && t[j + 1] == B_EN {
      t[j] = B_EN
    } else if x == B_CS && t[j - 1] == B_AN && t[j + 1] == B_AN {
      t[j] = B_AN
    }
  }
  // W5
  let mut j = 0
  while j < n {
    if t[j] != B_ET {
      j = j + 1
      continue
    }
    let s = j
    while j < n && t[j] == B_ET {
      j = j + 1
    }
    if (s > 0 && t[s - 1] == B_EN) || (j < n && t[j] == B_EN) {
      for k in s..<j {
        t[k] = B_EN
      }
    }
  }
  // W6
  for k in 0..<n {
    let x = t[k]
    if x == B_ES || x == B_ET || x == B_CS {
      t[k] = B_ON
    }
  }
  // W7
  strong = sos
  for k in 0..<n {
    let x = t[k]
    if x == B_L || x == B_R {
      strong = x
    } else if x == B_EN && strong == B_L {
      t[k] = B_L
    }
  }
  let e = if level % 2 == 1 { B_R } else { B_L }
  let e_dir = if e == B_R { 1 } else { 0 }
  // N0: paired brackets (BD16), in the order of their opening ones
  let pairs : Array[(Int, Int)] = []
  let stack_pair = []
  let stack_at = []
  let mut overflow = false
  for k in 0..<n {
    if overflow || t[k] != B_ON {
      continue
    }
    let c = cps[seq[k]]
    let (pair, kind) = bracket_of(c)
    if kind == 1 {
      if stack_pair.length() == 63 {
        overflow = true
        continue
      }
      stack_pair.push(bracket_norm(pair))
      stack_at.push(k)
    } else if kind == 2 {
      let want = bracket_norm(c)
      let mut d = stack_pair.length() - 1
      while d >= 0 && stack_pair[d] != want {
        d = d - 1
      }
      if d >= 0 {
        pairs.push((stack_at[d], k))
        while stack_pair.length() > d {
          stack_pair.pop() |> ignore
          stack_at.pop() |> ignore
        }
      }
    }
  }
  pairs.sort_by(fn(x, y) { x.0 - y.0 })
  for pr in pairs {
    let (o, c) = pr
    let mut found_e = false
    let mut found_other = false
    for k in (o + 1)..<c {
      let d = strong_dir(t[k])
      if d == e_dir {
        found_e = true
      } else if d >= 0 {
        found_other = true
      }
    }
    let to = if found_e {
      e
    } else if found_other {
      let mut ctx = if sos == B_R { 1 } else { 0 }
      let mut k = o - 1
      while k >= 0 {
        let d = strong_dir(t[k])
        if d >= 0 {
          ctx = d
          break
        }
        k = k - 1
      }
      if ctx != e_dir {
        if ctx == 1 {
          B_R
        } else {
          B_L
        }
      } else {
        e
      }
    } else {
      -1
    }
    if to >= 0 {
      t[o] = to
      t[c] = to
      // the marks that followed each bracket (NSM before W1) go with it
      for bk in [o, c] {
        let mut k = bk + 1
        while k < n && cls[seq[k]] == B_NSM {
          t[k] = to
          k = k + 1
        }
      }
    }
  }
  // N1, N2
  fn neutral(x : Int) {
    x == B_B ||
    x == B_S ||
    x == B_WS ||
    x == B_ON ||
    is_isolate_initiator(x) ||
    x == B_PDI
  }

  j = 0
  while j < n {
    if !neutral(t[j]) {
      j = j + 1
      continue
    }
    let s = j
    while j < n && neutral(t[j]) {
      j = j + 1
    }
    let lead = if s == 0 { strong_dir(sos) } else { strong_dir(t[s - 1]) }
    let trail = if j >= n { strong_dir(eos) } else { strong_dir(t[j]) }
    let to = if lead == trail && lead >= 0 {
      if lead == 1 {
        B_R
      } else {
        B_L
      }
    } else {
      e
    }
    for k in s..<j {
      t[k] = to
    }
  }
  // I1, I2
  for k in 0..<n {
    let x = t[k]
    let l = level
    lv[seq[k]] = if l % 2 == 0 {
      if x == B_R {
        l + 1
      } else if x == B_AN || x == B_EN {
        l + 2
      } else {
        l
      }
    } else if x == B_L || x == B_EN || x == B_AN {
      l + 1
    } else {
      l
    }
  }
}

///|
/// The levels of a line, code units [start, end), with L1: separators, and the spaces (and isolate controls) before
/// them or at the line's end, at the paragraph's level.
pub fn Bidi::line_levels(self : Bidi, start : Int, end : Int) -> FixedArray[Int] {
  let n = end - start
  let out = FixedArray::make(n, 0)
  if !self.mixed {
    return out
  }
  for k in 0..<n {
    out[k] = self.levels[start + k]
  }
  fn ws(t : Int) {
    t == B_WS || is_isolate_initiator(t) || t == B_PDI || is_removed_class(t)
  }

  let mut trailing = true
  let mut k = n - 1
  while k >= 0 {
    let t = self.classes[start + k]
    if t == B_S || t == B_B {
      out[k] = self.para[start + k]
      trailing = true
    } else if trailing && ws(t) {
      out[k] = self.para[start + k]
    } else {
      trailing = false
    }
    k = k - 1
  }
  out
}

///|
/// Whether any level is above 0 (else every line reads left to right, in logical order).
pub fn Bidi::is_mixed(self : Bidi) -> Bool {
  self.mixed
}

///|
/// The level of the paragraph holding code unit `i`.
pub fn Bidi::paragraph_level(self : Bidi, i : Int) -> Int {
  if i < self.para.length() {
    self.para[i]
  } else {
    0
  }
}

///|
/// L2: the visual order, left to right, of a line's pieces at these levels (indices into `levels`).
pub fn visual_order(levels : ArrayView[Int]) -> Array[Int] {
  let n = levels.length()
  let order = Array::makei(n, fn(i) { i })
  let mut hi = 0
  let mut lo_odd = 1000
  for l in levels {
    if l > hi {
      hi = l
    }
    if l % 2 == 1 && l < lo_odd {
      lo_odd = l
    }
  }
  let mut l = hi
  while l >= lo_odd && l > 0 {
    let mut i = 0
    while i < n {
      if levels[order[i]] < l {
        i = i + 1
        continue
      }
      let s = i
      while i < n && levels[order[i]] >= l {
        i = i + 1
      }
      // reverse order[s..i)
      let mut x = s
      let mut y = i - 1
      while x < y {
        let tmp = order[x]
        order[x] = order[y]
        order[y] = tmp
        x = x + 1
        y = y - 1
      }
    }
    l = l - 1
  }
  order
}
