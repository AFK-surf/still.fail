// Property lookup: the generated tables (tables.mbt) are range lists packed
// into strings; they are decoded once into sorted starts and values and
// searched with a binary search, with a direct table for Latin-1.

///|
priv struct RangeTable {
  starts : FixedArray[Int]
  vals : FixedArray[Int]
  low : FixedArray[Int]
}

///|
/// Varint digits: '0'..'9', 'A'..'V' end a number (0..31); 'a'..'z' and
/// "!$%&*+" carry 5 bits and continue it.
fn digit(c : Int) -> Int {
  if c >= 48 && c <= 57 {
    c - 48
  } else if c >= 65 && c <= 86 {
    c - 55
  } else if c >= 97 && c <= 122 {
    32 + c - 97
  } else {
    match c {
      33 => 58
      36 => 59
      37 => 60
      38 => 61
      42 => 62
      43 => 63
      _ => -1
    }
  }
}

///|
fn RangeTable::decode(data : String) -> RangeTable {
  let starts = []
  let vals = []
  let n = data.length()
  let mut i = 0
  let mut start = 0
  let mut nums = 0
  let mut acc = 0
  let mut shift = 0
  while i < n {
    let d = digit(data.at(i).to_int())
    i = i + 1
    if d < 0 {
      continue
    }
    acc = acc | ((d & 31) << shift)
    shift = shift + 5
    if d < 32 {
      if nums % 2 == 0 {
        start = start + acc
        starts.push(start)
      } else {
        vals.push(acc)
      }
      nums = nums + 1
      acc = 0
      shift = 0
    }
  }
  let st = FixedArray::from_array(starts)
  let vs = FixedArray::from_array(vals)
  let t = { starts: st, vals: vs, low: FixedArray::make(256, 0) }
  for c in 0..<256 {
    t.low[c] = t.search(c)
  }
  t
}

///|
fn RangeTable::search(self : RangeTable, c : Int) -> Int {
  let starts = self.starts
  let mut lo = 0
  let mut hi = starts.length() - 1
  while lo < hi {
    let mid = (lo + hi + 1) / 2
    if starts[mid] <= c {
      lo = mid
    } else {
      hi = mid - 1
    }
  }
  self.vals[lo]
}

///|
fn RangeTable::get(self : RangeTable, c : Int) -> Int {
  if c < 256 {
    self.low[c]
  } else {
    self.search(c)
  }
}

///|
let grapheme_table : RangeTable = RangeTable::decode(grapheme_data)

///|
let line_table : RangeTable = RangeTable::decode(line_data)

///|
/// The code point starting at UTF-16 offset i (a lone surrogate stands for
/// itself).
fn code_point_at(s : String, i : Int) -> Int {
  let c = s.at(i).to_int()
  if c >= 0xD800 && c < 0xDC00 && i + 1 < s.length() {
    let d = s.at(i + 1).to_int()
    if d >= 0xDC00 && d < 0xE000 {
      return 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00)
    }
  }
  c
}

///|
fn cp_len(c : Int) -> Int {
  if c >= 0x10000 {
    2
  } else {
    1
  }
}

///|
/// The start of the code point that ends at offset i.
fn cp_before(s : String, i : Int) -> Int {
  if i >= 2 {
    let d = s.at(i - 1).to_int()
    if d >= 0xDC00 && d < 0xE000 {
      let c = s.at(i - 2).to_int()
      if c >= 0xD800 && c < 0xDC00 {
        return i - 2
      }
    }
  }
  i - 1
}
