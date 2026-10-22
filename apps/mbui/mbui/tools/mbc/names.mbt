// The stable split's names: moonc numbers what it makes up across the whole program (locals, labels, anonymous
// functions and their types, constructors' objects); the stable split names them by what they are instead.

///|
/// The part of a name that says what it names (a string literal's, a layout's): 64 bits of its content's SHA-1.
fn content_hash(t : BytesView) -> Bytes {
  if same_hash.val {
    return b"0"
  }
  sha1_hex(t, 16)
}

///|
/// (a test's: every content the same hash, to see them named apart)
let same_hash : Ref[Bool] = { val: false }

///|
/// {content: name}, each named by its content_hash; contents whose hashes are the same numbered apart in the order
/// of their text.
fn by_content(contents : Array[Bytes], prefix : Bytes) -> Map[Bytes, Bytes] {
  let groups : Map[Bytes, Array[Bytes]] = Map::new()
  let seen = BSet::new()
  for c in contents {
    if seen.has(c) {
      continue
    }
    seen.add(c)
    let h = content_hash(c)
    match groups.get(h) {
      Some(a) => a.push(c)
      None => groups[h] = [c]
    }
  }
  let out = Map::new()
  for h, cs in groups {
    for k, c in sort_bytes(cs) {
      out[c] = cat([prefix, h, if k > 0 { cat([b"_", bint(k)]) } else { b"" }])
    }
  }
  out
}

///|
fn fn_type_key(
  n : Bytes,
  defs : Map[Bytes, Bytes],
  keys : Map[Bytes, Bytes],
  stack : Array[Bytes],
) -> Bytes {
  match keys.get(n) {
    Some(k) => return k
    None => ()
  }
  if stack.contains(n) {
    return b"cycle"
  }
  stack.push(n)
  let t = fn_type_sub(defs[n], fn(m) {
    if m == n {
      b"self"
    } else if defs.contains(m) {
      fn_type_key(m, defs, keys, stack)
    } else {
      m
    }
  })
  let _ = stack.pop()
  let k = content_hash(t)
  keys[n] = k
  k
}

///|
/// {name: its stable name} for moonc's function types (struct _M0TW…), by their definitions (in moonc's order).
fn fn_type_names(defs : Map[Bytes, Bytes]) -> Map[Bytes, Bytes] {
  let keys : Map[Bytes, Bytes] = Map::new()
  for n, _ in defs {
    let _ = fn_type_key(n, defs, keys, [])
  }
  let ns = []
  for n, _ in defs {
    ns.push(n)
  }
  let named = by_content(sort_bytes(ns).map(fn(n) { keys[n] }), b"_Mw")
  let order = stable_sort(ns, fn(a, b) {
    let c = bcmp(keys[a], keys[b])
    if c != 0 {
      c
    } else {
      bcmp(a, b)
    }
  })
  let out = Map::new()
  let seen : Map[Bytes, Int] = Map::new()
  for n in order {
    let w = named[keys[n]]
    let c = seen.get_or_default(w, 0) + 1
    seen[w] = c
    out[n] = if c == 1 { w } else { cat([w, b"_x", bint(c)]) }
  }
  out
}

///|
/// A name's numbers: re.sub(r'\d+', '#', name), and the numbers
fn digits_stem(name : Bytes) -> (Bytes, Array[Bytes]) {
  let buf = @buffer.new()
  let nums = []
  let n = name.length()
  let mut i = 0
  while i < n {
    if is_digit(name[i]) {
      let s = i
      while i < n && is_digit(name[i]) {
        i += 1
      }
      nums.push(sub(name, s, i))
      buf.write_byte(b'#')
    } else {
      buf.write_byte(name[i])
      i += 1
    }
  }
  (buf.to_bytes(), nums)
}

///|
/// Two numbers written in digits, as ints
fn num_cmp(a : Bytes, b : Bytes) -> Int {
  let mut i = 0
  while i < a.length() - 1 && a[i] == b'0' {
    i += 1
  }
  let mut j = 0
  while j < b.length() - 1 && b[j] == b'0' {
    j += 1
  }
  let la = a.length() - i
  let lb = b.length() - j
  if la != lb {
    return la - lb
  }
  bcmp(a[i:], b[j:])
}

///|
/// {name: its stable name} for moonc's globals `names` (in moonc's order): those whose names differ only in their
/// numbers in one group, numbered in the order of their numbers; a string literal by its content.
fn stable_names(
  names : Array[Bytes],
  data_text : Map[Bytes, Bytes],
  fn_defs : Map[Bytes, Bytes],
) -> Map[Bytes, Bytes] {
  let groups : Map[Bytes, Array[(Bytes, Array[Bytes])]] = Map::new()
  let out : Map[Bytes, Bytes] = Map::new()
  let literals : Array[(Bytes, Bytes)] = []
  for name in names {
    if starts(name, b"moonbit_string_literal_") && data_text.contains(name) {
      literals.push((name, replace_all(data_text[name], name, b"")))
      continue
    }
    let (stem, nums) = digits_stem(name)
    match groups.get(stem) {
      Some(a) => a.push((name, nums))
      None => groups[stem] = [(name, nums)]
    }
  }
  for stem, members in groups {
    let sorted = stable_sort(members, fn(x, y) {
      let (_, a) = x
      let (_, b) = y
      for i in 0..<imin(a.length(), b.length()) {
        let c = num_cmp(a[i], b[i])
        if c != 0 {
          return c
        }
      }
      a.length() - b.length()
    })
    let flat = replace_all(stem, b"#", b"0")
    for k, m in sorted {
      out[m.0] = cat([b"_Mz", bint(k), b"_", flat])
    }
  }
  // (moonc's function types by their definitions)
  let defs : Map[Bytes, Bytes] = Map::new()
  for n, d in fn_defs {
    if out.contains(n) {
      defs[n] = d
    }
  }
  if fn_defs.length() > 0 {
    for n, w in fn_type_names(defs) {
      out[n] = w
    }
  }
  // a string literal by its content (two the same, which moonc does not make: numbered apart, in its order)
  let named = by_content(literals.map(fn(x) { x.1 }), b"_Ms")
  let seen : Map[Bytes, Int] = Map::new()
  for x in literals {
    let n = named[x.1]
    let c = seen.get_or_default(n, 0) + 1
    seen[n] = c
    out[x.0] = if c == 1 { n } else { cat([n, b"_x", bint(c)]) }
  }
  out
}
