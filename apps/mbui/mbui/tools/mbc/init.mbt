// moonbit_init in its packages' pieces, and what a unit's functions need defined.

///|
priv struct Run {
  p : Bytes
  sts : Array[Bytes]
  locs : BSet
}

///|
fn subset(a : BSet, b : BSet) -> Bool {
  for k in a.t.keys {
    if !b.has(k) {
      return false
    }
  }
  true
}

///|
/// moonbit_init (moonc's names) in pieces, each a run of it that is one package's: [(package, declarations,
/// statements)], in its order, or None when it is not as this expects. A statement setting a global (moonc's
/// _M0F…, or its object's header) is the global's package's, with what came before it since the one before (its
/// temporaries); the locals moonc declares at the start go to the piece that uses them, and pieces between two that
/// share a local are one.
fn init_pieces(text : Bytes) -> Array[(Bytes, Bytes, Bytes)]? {
  let b = blank(text)
  let start = find_byte(b, b'{', 0)
  let end = rfind_byte(b, b'}')
  if start < 0 || end <= start {
    return None
  }
  let stmts : Array[Bytes] = []
  let mut depth = 0
  let mut paren = 0
  let mut s = start + 1
  let mut i = s
  while i < end {
    let c = b[i]
    if c == b'(' || c == b'[' {
      paren += 1
    } else if c == b')' || c == b']' {
      paren -= 1
    } else if c == b'{' {
      depth += 1
    } else if c == b'}' {
      depth -= 1
      if depth == 0 && paren == 0 {
        // (a block's end ends its statement, unless what follows goes on with it: else, a do's while, the ; of an
        // initialiser)
        let mut j = i + 1
        while j < end && is_space(b[j]) {
          j += 1
        }
        let mut w = j
        while w < imin(j + 8, b.length()) &&
          ((b[w] >= b'a' && b[w] <= b'z') ||
          (b[w] >= b'A' && b[w] <= b'Z') ||
          b[w] == b'_') {
          w += 1
        }
        let nxt = b[j:w]
        let go_on = b[j] == b';' ||
          b[j] == b',' ||
          b[j] == b')' ||
          nxt == b"else" ||
          (nxt == b"while" && starts(lstrip(sub(b, s, i)), b"do"))
        if !go_on {
          stmts.push(sub(text, s, i + 1))
          s = i + 1
        }
      }
    } else if c == b';' && depth == 0 && paren == 0 {
      stmts.push(sub(text, s, i + 1))
      s = i + 1
    }
    i += 1
  }
  if depth != 0 ||
    paren != 0 ||
    strip(sub(text, s, end)).length() > 0 ||
    stmts.length() == 0 {
    return None
  }
  // the locals moonc declares (no initial value), and the statements in runs by the package they set
  let floating : Map[Bytes, Bytes] = Map::new()
  let runs : Array[Run] = []
  let mut pending : Array[Bytes] = []
  let mut pending_locals = BSet::new()
  for st in stmts {
    let bst = blank(st)
    match init_decl(bst) {
      Some(m) if is_local(m) && !has_byte(bst, b'=') => {
        floating[m] = st
        continue
      }
      _ => ()
    }
    let loc = BSet::new()
    for n in idents(bst).items() {
      if is_local(n) {
        loc.add(n)
      }
    }
    let o = init_owner(bst)
    if o is None &&
      pending.length() == 0 &&
      runs.length() > 0 &&
      subset(loc, runs[runs.length() - 1].locs) {
      // (right after a global set, what lets its temporaries go or goes on with it: the global's too)
      runs[runs.length() - 1].sts.push(st)
      continue
    }
    pending.push(st)
    pending_locals.add_all(loc)
    match o {
      Some(name) => {
        let p = package_of(name)
        if runs.length() > 0 && runs[runs.length() - 1].p == p {
          let r = runs[runs.length() - 1]
          for x in pending {
            r.sts.push(x)
          }
          r.locs.add_all(pending_locals)
        } else {
          runs.push({ p, sts: pending, locs: pending_locals })
        }
        pending = []
        pending_locals = BSet::new()
      }
      None => ()
    }
  }
  if pending.length() > 0 {
    if runs.length() == 0 {
      runs.push({ p: b"", sts: [], locs: BSet::new() })
    }
    let r = runs[runs.length() - 1]
    for x in pending {
      r.sts.push(x)
    }
    r.locs.add_all(pending_locals)
  }
  // pieces sharing a local are one, and the pieces between them (the order kept)
  let last : Map[Bytes, Int] = Map::new()
  for k, r in runs {
    for n in r.locs.items() {
      last[n] = k
    }
  }
  let merged : Array[Run] = []
  let mut k = 0
  while k < runs.length() {
    let p = runs[k].p
    let sts = runs[k].sts.copy()
    let locs = runs[k].locs.copy()
    let mut reach = k
    for n in locs.items() {
      reach = imax(reach, last[n])
    }
    while k < reach {
      k += 1
      for x in runs[k].sts {
        sts.push(x)
      }
      locs.add_all(runs[k].locs)
      for n in runs[k].locs.items() {
        reach = imax(reach, last[n])
      }
    }
    if merged.length() > 0 && merged[merged.length() - 1].p == p {
      let m = merged[merged.length() - 1]
      for x in sts {
        m.sts.push(x)
      }
      m.locs.add_all(locs)
    } else {
      merged.push({ p, sts, locs })
    }
    k += 1
  }
  let out = []
  for m in merged {
    let decls = @buffer.new()
    for n, d in floating {
      if m.locs.has(n) {
        // (.strip('\n'))
        let mut a = 0
        let mut e = d.length()
        while a < e && d[a] == b'\n' {
          a += 1
        }
        while e > a && d[e - 1] == b'\n' {
          e -= 1
        }
        decls.write_bytesview(d[a:e])
        decls.write_byte(b'\n')
      }
    }
    out.push((m.p, decls.to_bytes(), cat(m.sts)))
  }
  Some(out)
}

///|
/// The struct types that functions' `texts` need defined, not only declared: by value (a local, a parameter, a
/// compound literal), sizeof, a member or an element through a variable declared as one or a pointer to one; None
/// when that cannot be told (a member through anything else). `globals`: {name: (type, pointers)} of the externs.
fn defined_needed(
  texts : Array[Bytes],
  globals : Map[Bytes, (Bytes, Int)],
  fields : Map[Bytes, Map[Bytes, (Bytes, Int)]],
) -> BSet? {
  let need = BSet::new()
  for t in texts {
    let b = drop_header_of(blank(t))
    // (a member through a cast: ((struct X*)v)->$0, an enum's case's)
    let (casts, rest) = cast_accesses(b)
    for c in casts {
      need.add(c)
    }
    if member_after_bracket(rest) {
      return None
    }
    for n in sizeof_all(b) {
      need.add(n)
    }
    for n in by_value_all(b) {
      if !(starts(n, b"enum") && boundary(n, 4)) {
        need.add(n)
      }
    }
    let local : Map[Bytes, (Bytes, Int)] = Map::new()
    for v in decl_vars(b) {
      local[v.0] = (v.1, v.2)
    }
    let type_of = fn(n : Bytes) -> (Bytes, Int)? {
      match local.get(n) {
        Some(v) => Some(v)
        None => globals.get(n)
      }
    }
    var_uses(b, fn(name, op) {
      match type_of(name) {
        Some(v) =>
          if v.1 == 0 || (v.1 == 1 && (op == b"->" || op == b"[")) {
            need.add(v.0)
          }
        None => ()
      }
    })
    // (a member's member: through the struct's definition, the member's type)
    accesses(b, fn(name, steps) {
      let mut v = type_of(name)
      for st in steps {
        let (op, member) = st
        match v {
          None => break
          Some(tv) => {
            if (op == b"->") != (tv.1 == 1) {
              break
            }
            need.add(tv.0)
            v = match fields.get(tv.0) {
              Some(f) => f.get(member)
              None => None
            }
          }
        }
      }
    })
  }
  Some(need)
}
