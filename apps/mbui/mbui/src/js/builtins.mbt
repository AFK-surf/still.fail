// The builtins a widget's script reaches for: Object, Function, Array, String, Number, Boolean, Math, JSON, the errors,
// Date (its time what the host says it is), Map and Set, Promise (settled as their work is done, callbacks as
// microtasks the host drains), timers (setTimeout, setInterval, requestAnimationFrame: run by the host at the
// moments they are due), console. What is not here is a ReferenceError, and the widget falls back to a browser.

///|
fn arg(args : Array[Value], i : Int) -> Value {
  args.get(i).unwrap_or(Undefined)
}

///|
fn Realm::ctor(self : Realm, name : String, proto : Obj, f : NativeFn, arity? : Int = 0) -> Obj {
  let v = self.native(name, f, arity~)
  match v {
    O(o) => {
      o.props["prototype"] = Data(O(proto))
      o.hidden["prototype"] = true
      proto.props["constructor"] = Data(v)
      proto.hidden["constructor"] = true
      self.define_global(name, v)
      o
    }
    _ => abort("a native function is an object")
  }
}

///|
fn Realm::this_items(self : Realm, this : Value) -> Array[Value] raise Throw {
  match this {
    O({ kind: Arr(items), .. }) => items
    O(o) => {
      // an array-like: its length and indexes
      let n = self.to_number(self.get(this, "length"))
      let out = []
      if !n.is_nan() {
        for i in 0..<n.to_int() {
          out.push(self.get(O(o), i.to_string()))
        }
      }
      out
    }
    _ => raise self.error("TypeError", "not an array")
  }
}

///|
fn Realm::callback(self : Realm, f : Value) -> Value raise Throw {
  if !f.is_callable() {
    raise self.error("TypeError", "\{self.to_display(f)} is not a function")
  }
  f
}

///|
fn rel_index(v : Double, len : Int) -> Int {
  if v.is_nan() {
    return 0
  }
  let i = if v < 0.0 { len.to_double() + v.floor() } else { v.floor() }
  if i < 0.0 {
    0
  } else if i > len.to_double() {
    len
  } else {
    i.to_int()
  }
}

///|
fn Realm::stable_sort(self : Realm, items : Array[Value], less : (Value, Value) -> Bool raise Throw) -> Array[Value] raise Throw {
  if items.length() <= 1 {
    return items.copy()
  }
  let mid = items.length() / 2
  let a = self.stable_sort(items[0:mid].to_array(), less)
  let b = self.stable_sort(items[mid:].to_array(), less)
  let out = []
  let mut i = 0
  let mut j = 0
  while i < a.length() && j < b.length() {
    if less(b[j], a[i]) {
      out.push(b[j])
      j += 1
    } else {
      out.push(a[i])
      i += 1
    }
  }
  while i < a.length() {
    out.push(a[i])
    i += 1
  }
  while j < b.length() {
    out.push(b[j])
    j += 1
  }
  out
}

///|
fn install_builtins(r : Realm) -> Unit {
  r.define_global("globalThis", O(r.global_obj))
  r.define_global("window", O(r.global_obj))
  r.define_global("self", O(r.global_obj))
  r.define_global("NaN", N(0.0 / 0.0))
  r.define_global("Infinity", N(1.0 / 0.0))
  install_object(r)
  install_function(r)
  install_array(r)
  install_string(r)
  install_number(r)
  install_math(r)
  install_json(r)
  install_errors(r)
  install_date(r)
  install_collections(r)
  install_timers(r)
  install_console(r)
}

// ── Object ───────────────────────────────────────────────────────────

///|
fn install_object(r : Realm) -> Unit {
  let o = r.ctor("Object", r.object_proto, fn(_, args, r) {
    match arg(args, 0) {
      O(x) => O(x)
      Undefined | Null => O(r.new_obj())
      v => O(r.to_object(v))
    }
  })
  let keys_of = fn(r : Realm, v : Value) raise Throw {
    match v {
      O(x) => r.own_keys(x)
      S(s) => Array::makei(s.length(), fn(i) { i.to_string() })
      Undefined | Null => raise r.error("TypeError", "Cannot convert undefined or null to object")
      _ => []
    }
  }
  r.method(o, "keys", fn(_, args, r) { r.array(keys_of(r, arg(args, 0)).map(fn(k) { S(k) })) })
  r.method(o, "values", fn(_, args, r) {
    let v = arg(args, 0)
    let out = []
    for k in keys_of(r, v) {
      out.push(r.get(v, k))
    }
    r.array(out)
  })
  r.method(o, "entries", fn(_, args, r) {
    let v = arg(args, 0)
    let out = []
    for k in keys_of(r, v) {
      out.push(r.array([S(k), r.get(v, k)]))
    }
    r.array(out)
  })
  r.method(o, "assign", fn(_, args, r) {
    let target = arg(args, 0)
    for i in 1..<args.length() {
      match args[i] {
        O(src) => for k in r.own_keys(src) { r.set(target, k, r.get(args[i], k)) }
        _ => ()
      }
    }
    target
  })
  r.method(o, "fromEntries", fn(_, args, r) {
    let out = r.new_obj()
    for e in r.iterate(arg(args, 0)) {
      out.props[r.key_of(r.get(e, "0"))] = Data(r.get(e, "1"))
    }
    O(out)
  })
  r.method(o, "create", fn(_, args, r) {
    match arg(args, 0) {
      O(p) => O(r.new_obj(proto=Some(p)))
      _ => O(r.new_obj(proto=None))
    }
  })
  r.method(o, "getPrototypeOf", fn(_, args, r) {
    match arg(args, 0) {
      O(x) =>
        match x.proto {
          Some(p) => O(p)
          None => Null
        }
      S(_) => O(r.string_proto)
      N(_) => O(r.number_proto)
      _ => Null
    }
  })
  r.method(o, "setPrototypeOf", fn(_, args, _) {
    match (arg(args, 0), arg(args, 1)) {
      (O(x), O(p)) => x.proto = Some(p)
      (O(x), Null) => x.proto = None
      _ => ()
    }
    arg(args, 0)
  })
  r.method(o, "freeze", fn(_, args, _) { arg(args, 0) })
  r.method(o, "seal", fn(_, args, _) { arg(args, 0) })
  r.method(o, "isFrozen", fn(_, _, _) { B(false) })
  r.method(o, "is", fn(_, args, _) {
    match (arg(args, 0), arg(args, 1)) {
      (N(a), N(b)) => B((a == b && (a != 0.0 || 1.0 / a == 1.0 / b)) || (a.is_nan() && b.is_nan()))
      (a, b) => B(strict_equal(a, b))
    }
  })
  r.method(o, "defineProperty", fn(_, args, r) {
    match arg(args, 0) {
      O(x) => {
        let key = r.key_of(arg(args, 1))
        let d = arg(args, 2)
        let g = r.get(d, "get")
        let s = r.get(d, "set")
        if g.is_callable() || s.is_callable() {
          x.props[key] = Accessor(g, s)
        } else {
          x.props[key] = Data(r.get(d, "value"))
        }
        if !r.get(d, "enumerable").truthy() {
          x.hidden[key] = true
        }
      }
      _ => ()
    }
    arg(args, 0)
  })
  r.method(o, "getOwnPropertyNames", fn(_, args, r) {
    match arg(args, 0) {
      O(x) => {
        let out = []
        x.props.each(fn(k, _) { out.push(S(k)) })
        r.array(out)
      }
      _ => r.array([])
    }
  })
  let p = r.object_proto
  r.method(p, "hasOwnProperty", fn(this, args, r) {
    match this {
      O(x) => {
        let k = r.key_of(arg(args, 0))
        B(x.props.contains(k) || (x.kind is Arr(items) && index_of_key(k).map(fn(i) { i < items.length() }).unwrap_or(false)))
      }
      _ => B(false)
    }
  })
  r.method(p, "toString", fn(this, _, _) {
    match this {
      O({ kind: Arr(_), .. }) => S("[object Array]")
      Null => S("[object Null]")
      Undefined => S("[object Undefined]")
      _ => S("[object Object]")
    }
  })
  r.method(p, "toLocaleString", fn(this, _, r) { S(r.to_string(this)) })
  r.method(p, "valueOf", fn(this, _, _) { this })
  r.method(p, "isPrototypeOf", fn(this, args, _) {
    match (this, arg(args, 0)) {
      (O(a), O(b)) => {
        let mut cur = b.proto
        while cur is Some(c) {
          if c.id == a.id {
            return B(true)
          }
          cur = c.proto
        }
        B(false)
      }
      _ => B(false)
    }
  })
  r.method(r.global_obj, "hasOwnProperty", fn(_, args, r) { B(r.global_obj.props.contains(r.key_of(arg(args, 0)))) })
}

// ── Function ─────────────────────────────────────────────────────────

///|
fn install_function(r : Realm) -> Unit {
  let f = r.ctor("Function", r.function_proto, fn(_, _, r) { raise r.error("EvalError", "Function() is not allowed") })
  ignore(f)
  let p = r.function_proto
  r.method(p, "call", fn(this, args, r) { r.call(this, arg(args, 0), if args.length() > 1 { args[1:].to_array() } else { [] }) })
  r.method(p, "apply", fn(this, args, r) {
    let list = match arg(args, 1) {
      Undefined | Null => []
      v => r.iterate(v)
    }
    r.call(this, arg(args, 0), list)
  })
  r.method(p, "bind", fn(this, args, r) {
    O(r.new_obj(proto=Some(r.function_proto), kind=Bound(this, arg(args, 0), if args.length() > 1 { args[1:].to_array() } else { [] })))
  })
  r.method(p, "toString", fn(_, _, _) { S("function () { [native code] }") })
}

// ── Array ────────────────────────────────────────────────────────────

///|
fn install_array(r : Realm) -> Unit {
  let a = r.ctor("Array", r.array_proto, fn(_, args, r) {
    match args {
      [N(n)] => r.array(Array::make(n.to_int(), Undefined))
      _ => r.array(args.copy())
    }
  })
  r.method(a, "isArray", fn(_, args, _) { B(arg(args, 0) is O({ kind: Arr(_), .. })) })
  r.method(a, "of", fn(_, args, r) { r.array(args.copy()) })
  r.method(a, "from", fn(_, args, r) {
    let src = arg(args, 0)
    let items = match src {
      O({ kind: Arr(_), .. }) | S(_) => r.iterate(src)
      O(_) =>
        if r.get(src, "@@iterator").is_callable() || r.get(src, "@@items") is O(_) {
          r.iterate(src)
        } else {
          r.this_items(src)
        }
      _ => []
    }
    let f = arg(args, 1)
    if f.is_callable() {
      r.array(items.mapi(fn(i, x) { r.call(f, Undefined, [x, N(i.to_double())]) }))
    } else {
      r.array(items)
    }
  })
  let p = r.array_proto
  r.method(p, "push", fn(this, args, r) {
    let items = r.this_items(this)
    for x in args {
      items.push(x)
    }
    N(items.length().to_double())
  })
  r.method(p, "pop", fn(this, _, r) { r.this_items(this).pop().unwrap_or(Undefined) })
  r.method(p, "shift", fn(this, _, r) {
    let items = r.this_items(this)
    if items.is_empty() {
      Undefined
    } else {
      items.remove(0)
    }
  })
  r.method(p, "unshift", fn(this, args, r) {
    let items = r.this_items(this)
    for i, x in args {
      items.insert(i, x)
    }
    N(items.length().to_double())
  })
  r.method(p, "slice", fn(this, args, r) {
    let items = r.this_items(this)
    let n = items.length()
    let s = rel_index(if arg(args, 0) is Undefined { 0.0 } else { r.to_number(arg(args, 0)) }, n)
    let e = rel_index(if arg(args, 1) is Undefined { n.to_double() } else { r.to_number(arg(args, 1)) }, n)
    r.array(if s < e { items[s:e].to_array() } else { [] })
  })
  r.method(p, "splice", fn(this, args, r) {
    let items = r.this_items(this)
    let n = items.length()
    let s = rel_index(r.to_number(arg(args, 0)), n)
    let count = if args.length() < 2 {
      n - s
    } else {
      let c = r.to_number(args[1]).to_int()
      if c < 0 {
        0
      } else if c > n - s {
        n - s
      } else {
        c
      }
    }
    let removed = []
    for _ in 0..<count {
      removed.push(items.remove(s))
    }
    for i in 2..<args.length() {
      items.insert(s + i - 2, args[i])
    }
    r.array(removed)
  })
  r.method(p, "concat", fn(this, args, r) {
    let out = r.this_items(this).copy()
    for x in args {
      match x {
        O({ kind: Arr(more), .. }) => for y in more { out.push(y) }
        _ => out.push(x)
      }
    }
    r.array(out)
  })
  r.method(p, "join", fn(this, args, r) {
    let sep = if arg(args, 0) is Undefined { "," } else { r.to_string(arg(args, 0)) }
    let parts = []
    for x in r.this_items(this) {
      parts.push(if x is Undefined || x is Null { "" } else { r.to_string(x) })
    }
    S(parts.join(sep))
  })
  r.method(p, "toString", fn(this, _, r) {
    let parts = []
    for x in r.this_items(this) {
      parts.push(if x is Undefined || x is Null { "" } else { r.to_string(x) })
    }
    S(parts.join(","))
  })
  r.method(p, "reverse", fn(this, _, r) {
    r.this_items(this).rev_in_place()
    this
  })
  r.method(p, "sort", fn(this, args, r) {
    let items = r.this_items(this)
    let f = arg(args, 0)
    let sorted = r.stable_sort(items, fn(x, y) raise Throw {
      if x is Undefined {
        return false
      }
      if y is Undefined {
        return true
      }
      if f.is_callable() {
        r.to_number(r.call(f, Undefined, [x, y])) < 0.0
      } else {
        r.to_string(x) < r.to_string(y)
      }
    })
    for i, x in sorted {
      items[i] = x
    }
    this
  })
  let finder = fn(name : String, from_end : Bool, want_index : Bool) {
    r.method(p, name, fn(this, args, r) {
      let items = r.this_items(this)
      let f = r.callback(arg(args, 0))
      let n = items.length()
      for k in 0..<n {
        let i = if from_end { n - 1 - k } else { k }
        if r.call(f, arg(args, 1), [items[i], N(i.to_double()), this]).truthy() {
          return if want_index { N(i.to_double()) } else { items[i] }
        }
      }
      if want_index {
        N(-1.0)
      } else {
        Undefined
      }
    })
  }
  finder("find", false, false)
  finder("findIndex", false, true)
  finder("findLast", true, false)
  finder("findLastIndex", true, true)
  r.method(p, "indexOf", fn(this, args, r) {
    let items = r.this_items(this)
    let from = rel_index(r.to_number(arg(args, 1)), items.length())
    for i in from..<items.length() {
      if strict_equal(items[i], arg(args, 0)) {
        return N(i.to_double())
      }
    }
    N(-1.0)
  })
  r.method(p, "lastIndexOf", fn(this, args, r) {
    let items = r.this_items(this)
    for k = items.length() - 1; k >= 0; k = k - 1 {
      if strict_equal(items[k], arg(args, 0)) {
        return N(k.to_double())
      }
    }
    N(-1.0)
  })
  r.method(p, "includes", fn(this, args, r) { B(r.this_items(this).iter().any(fn(x) { same_value_zero(x, arg(args, 0)) })) })
  r.method(p, "at", fn(this, args, r) {
    let items = r.this_items(this)
    let i = r.to_number(arg(args, 0)).to_int()
    let k = if i < 0 { items.length() + i } else { i }
    items.get(k).unwrap_or(Undefined)
  })
  r.method(p, "forEach", fn(this, args, r) {
    let f = r.callback(arg(args, 0))
    let items = r.this_items(this)
    let mut i = 0
    while i < items.length() {
      r.call(f, arg(args, 1), [items[i], N(i.to_double()), this]) |> ignore
      i += 1
    }
    Undefined
  })
  r.method(p, "map", fn(this, args, r) {
    let f = r.callback(arg(args, 0))
    let out = []
    for i, x in r.this_items(this).copy() {
      out.push(r.call(f, arg(args, 1), [x, N(i.to_double()), this]))
    }
    r.array(out)
  })
  r.method(p, "filter", fn(this, args, r) {
    let f = r.callback(arg(args, 0))
    let out = []
    for i, x in r.this_items(this).copy() {
      if r.call(f, arg(args, 1), [x, N(i.to_double()), this]).truthy() {
        out.push(x)
      }
    }
    r.array(out)
  })
  r.method(p, "some", fn(this, args, r) {
    let f = r.callback(arg(args, 0))
    for i, x in r.this_items(this).copy() {
      if r.call(f, arg(args, 1), [x, N(i.to_double()), this]).truthy() {
        return B(true)
      }
    }
    B(false)
  })
  r.method(p, "every", fn(this, args, r) {
    let f = r.callback(arg(args, 0))
    for i, x in r.this_items(this).copy() {
      if !r.call(f, arg(args, 1), [x, N(i.to_double()), this]).truthy() {
        return B(false)
      }
    }
    B(true)
  })
  let reducer = fn(name : String, from_end : Bool) {
    r.method(p, name, fn(this, args, r) {
      let f = r.callback(arg(args, 0))
      let items = r.this_items(this).copy()
      let order = if from_end { items.copy().rev() } else { items }
      let idx = fn(k : Int) { if from_end { items.length() - 1 - k } else { k } }
      let mut start = 0
      let mut acc = if args.length() >= 2 {
        args[1]
      } else {
        if order.is_empty() {
          raise r.error("TypeError", "Reduce of empty array rep no initial value")
        }
        start = 1
        order[0]
      }
      for k in start..<order.length() {
        acc = r.call(f, Undefined, [acc, order[k], N(idx(k).to_double()), this])
      }
      acc
    })
  }
  reducer("reduce", false)
  reducer("reduceRight", true)
  r.method(p, "flat", fn(this, args, r) {
    let depth = if arg(args, 0) is Undefined { 1 } else { r.to_number(arg(args, 0)).to_int() }
    let out = []
    fn go(items : Array[Value], d : Int) {
      for x in items {
        match x {
          O({ kind: Arr(more), .. }) if d > 0 => go(more, d - 1)
          _ => out.push(x)
        }
      }
    }

    go(r.this_items(this), depth)
    r.array(out)
  })
  r.method(p, "flatMap", fn(this, args, r) {
    let f = r.callback(arg(args, 0))
    let out = []
    for i, x in r.this_items(this).copy() {
      match r.call(f, arg(args, 1), [x, N(i.to_double()), this]) {
        O({ kind: Arr(more), .. }) => for y in more { out.push(y) }
        y => out.push(y)
      }
    }
    r.array(out)
  })
  r.method(p, "fill", fn(this, args, r) {
    let items = r.this_items(this)
    let n = items.length()
    let s = rel_index(if arg(args, 1) is Undefined { 0.0 } else { r.to_number(arg(args, 1)) }, n)
    let e = rel_index(if arg(args, 2) is Undefined { n.to_double() } else { r.to_number(arg(args, 2)) }, n)
    for i in s..<e {
      items[i] = arg(args, 0)
    }
    this
  })
  r.method(p, "keys", fn(this, _, r) { r.array(r.this_items(this).mapi(fn(i, _) { N(i.to_double()) })) })
  r.method(p, "values", fn(this, _, r) { r.array(r.this_items(this).copy()) })
  r.method(p, "entries", fn(this, _, r) { r.array(r.this_items(this).mapi(fn(i, x) { r.array([N(i.to_double()), x]) })) })
  r.method(p, "toSorted", fn(this, args, r) {
    let copy = r.array(r.this_items(this).copy())
    r.call(r.get(copy, "sort"), copy, args)
  })
  r.method(p, "toReversed", fn(this, _, r) { r.array(r.this_items(this).copy().rev()) })
}

// ── String ───────────────────────────────────────────────────────────

///|
fn Realm::this_string(self : Realm, this : Value) -> String raise Throw {
  match this {
    S(s) => s
    O({ kind: Boxed(S(s)), .. }) => s
    _ => self.to_string(this)
  }
}

///|
fn install_string(r : Realm) -> Unit {
  let s = r.ctor("String", r.string_proto, fn(_, args, r) { S(if args.is_empty() { "" } else { r.to_string(args[0]) }) })
  r.method(s, "fromCharCode", fn(_, args, r) {
    let b = StringBuilder()
    for a in args {
      b.write_char(Int::unsafe_to_char(r.to_number(a).to_int() & 0xFFFF))
    }
    S(b.to_string())
  })
  r.method(s, "fromCodePoint", fn(_, args, r) {
    let b = StringBuilder()
    for a in args {
      b.write_char(Int::unsafe_to_char(r.to_number(a).to_int()))
    }
    S(b.to_string())
  })
  let p = r.string_proto
  r.method(p, "toString", fn(this, _, r) { S(r.this_string(this)) })
  r.method(p, "valueOf", fn(this, _, r) { S(r.this_string(this)) })
  r.method(p, "charAt", fn(this, args, r) {
    let t = r.this_string(this)
    let i = r.to_number(arg(args, 0)).to_int()
    S(if i >= 0 && i < t.length() { t.view(start_offset=i, end_offset=i + 1).to_owned() } else { "" })
  })
  r.method(p, "charCodeAt", fn(this, args, r) {
    let t = r.this_string(this)
    let i = if arg(args, 0) is Undefined { 0 } else { r.to_number(arg(args, 0)).to_int() }
    N(if i >= 0 && i < t.length() { t.code_unit_at(i).to_int().to_double() } else { 0.0 / 0.0 })
  })
  r.method(p, "codePointAt", fn(this, args, r) {
    let t = r.this_string(this)
    let i = if arg(args, 0) is Undefined { 0 } else { r.to_number(arg(args, 0)).to_int() }
    if i < 0 || i >= t.length() {
      return Undefined
    }
    let c = t.code_unit_at(i).to_int()
    if c >= 0xD800 && c <= 0xDBFF && i + 1 < t.length() {
      let d = t.code_unit_at(i + 1).to_int()
      N(((c - 0xD800) * 0x400 + (d - 0xDC00) + 0x10000).to_double())
    } else {
      N(c.to_double())
    }
  })
  r.method(p, "at", fn(this, args, r) {
    let t = r.this_string(this)
    let i = r.to_number(arg(args, 0)).to_int()
    let k = if i < 0 { t.length() + i } else { i }
    if k >= 0 && k < t.length() {
      S(t.view(start_offset=k, end_offset=k + 1).to_owned())
    } else {
      Undefined
    }
  })
  r.method(p, "indexOf", fn(this, args, r) {
    let t = r.this_string(this)
    let needle = r.to_string(arg(args, 0))
    let from = rel_index(r.to_number(arg(args, 1)), t.length())
    match t.view(start_offset=from).find(needle) {
      Some(i) => N((i + from).to_double())
      None => N(-1.0)
    }
  })
  r.method(p, "lastIndexOf", fn(this, args, r) {
    let t = r.this_string(this)
    match t.rev_find(r.to_string(arg(args, 0))) {
      Some(i) => N(i.to_double())
      None => N(-1.0)
    }
  })
  r.method(p, "includes", fn(this, args, r) { B(r.this_string(this).contains(r.to_string(arg(args, 0)))) })
  r.method(p, "startsWith", fn(this, args, r) {
    let t = r.this_string(this)
    let from = rel_index(r.to_number(arg(args, 1)), t.length())
    B(t.view(start_offset=from).has_prefix(r.to_string(arg(args, 0))))
  })
  r.method(p, "endsWith", fn(this, args, r) {
    let t = r.this_string(this)
    let end = if arg(args, 1) is Undefined { t.length() } else { rel_index(r.to_number(arg(args, 1)), t.length()) }
    B(t.view(end_offset=end).has_suffix(r.to_string(arg(args, 0))))
  })
  r.method(p, "slice", fn(this, args, r) {
    let t = r.this_string(this)
    let n = t.length()
    let a = rel_index(if arg(args, 0) is Undefined { 0.0 } else { r.to_number(arg(args, 0)) }, n)
    let b = rel_index(if arg(args, 1) is Undefined { n.to_double() } else { r.to_number(arg(args, 1)) }, n)
    S(if a < b { t.view(start_offset=a, end_offset=b).to_owned() } else { "" })
  })
  r.method(p, "substring", fn(this, args, r) {
    let t = r.this_string(this)
    let n = t.length()
    let clamp = fn(v : Double) {
      if v.is_nan() || v < 0.0 {
        0
      } else if v > n.to_double() {
        n
      } else {
        v.to_int()
      }
    }
    let a = clamp(r.to_number(arg(args, 0)))
    let b = if arg(args, 1) is Undefined { n } else { clamp(r.to_number(arg(args, 1))) }
    let (lo, hi) = if a < b { (a, b) } else { (b, a) }
    S(t.view(start_offset=lo, end_offset=hi).to_owned())
  })
  r.method(p, "substr", fn(this, args, r) {
    let t = r.this_string(this)
    let n = t.length()
    let a = rel_index(r.to_number(arg(args, 0)), n)
    let len = if arg(args, 1) is Undefined { n - a } else { r.to_number(arg(args, 1)).to_int() }
    let b = if a + len > n { n } else if len < 0 { a } else { a + len }
    S(t.view(start_offset=a, end_offset=b).to_owned())
  })
  r.method(p, "toUpperCase", fn(this, _, r) { S(r.this_string(this).to_upper()) })
  r.method(p, "toLowerCase", fn(this, _, r) { S(r.this_string(this).to_lower()) })
  r.method(p, "toLocaleUpperCase", fn(this, _, r) { S(r.this_string(this).to_upper()) })
  r.method(p, "toLocaleLowerCase", fn(this, _, r) { S(r.this_string(this).to_lower()) })
  let ws = " \t\n\r\u{b}\u{c}\u{a0}\u{feff}\u{2028}\u{2029}"
  r.method(p, "trim", fn(this, _, r) { S(r.this_string(this).trim(chars=ws).to_string()) })
  r.method(p, "trimStart", fn(this, _, r) { S(r.this_string(this).trim_start(chars=ws).to_string()) })
  r.method(p, "trimEnd", fn(this, _, r) { S(r.this_string(this).trim_end(chars=ws).to_string()) })
  let pad = fn(start : Bool) -> NativeFn {
    fn(this, args, r) {
      let t = r.this_string(this)
      let want = r.to_number(arg(args, 0)).to_int()
      let fill = if arg(args, 1) is Undefined { " " } else { r.to_string(arg(args, 1)) }
      if want <= t.length() || fill == "" {
        return S(t)
      }
      let b = StringBuilder()
      while b.to_string().length() < want - t.length() {
        b.write_string(fill)
      }
      let padding = b.to_string().view(end_offset=want - t.length()).to_owned()
      S(if start { padding + t } else { t + padding })
    }
  }
  r.method(p, "padStart", pad(true))
  r.method(p, "padEnd", pad(false))
  r.method(p, "repeat", fn(this, args, r) {
    let n = r.to_number(arg(args, 0))
    if n < 0.0 || n.is_inf() {
      raise r.error("RangeError", "Invalid count value")
    }
    S(r.this_string(this).repeat(n.to_int()))
  })
  r.method(p, "concat", fn(this, args, r) {
    let b = StringBuilder()
    b.write_string(r.this_string(this))
    for a in args {
      b.write_string(r.to_string(a))
    }
    S(b.to_string())
  })
  r.method(p, "localeCompare", fn(this, args, r) {
    let a = r.this_string(this)
    let b = r.to_string(arg(args, 0))
    N(if a < b { -1.0 } else if a > b { 1.0 } else { 0.0 })
  })
  r.method(p, "normalize", fn(this, _, r) { S(r.this_string(this)) })
  r.method(p, "split", fn(this, args, r) {
    let t = r.this_string(this)
    let limit = if arg(args, 1) is Undefined { 1 << 30 } else { r.to_number(arg(args, 1)).to_int() }
    let out = match arg(args, 0) {
      Undefined => [S(t)]
      O({ kind: RegExp(_, _), .. }) as re => r.regex_split(t, re)
      sep => {
        let s = r.to_string(sep)
        if s == "" {
          let all = []
          for i in 0..<t.length() {
            all.push(S(t.view(start_offset=i, end_offset=i + 1).to_owned()))
          }
          all
        } else {
          t.split(s).map(fn(x) { S(x.to_string()) }).collect()
        }
      }
    }
    r.array(if out.length() > limit { out[0:limit].to_array() } else { out })
  })
  r.method(p, "replace", fn(this, args, r) { r.replace(r.this_string(this), arg(args, 0), arg(args, 1), false) })
  r.method(p, "replaceAll", fn(this, args, r) { r.replace(r.this_string(this), arg(args, 0), arg(args, 1), true) })
  r.method(p, "match", fn(this, args, r) { r.regex_match(r.this_string(this), arg(args, 0)) })
  r.method(p, "matchAll", fn(this, args, r) { r.regex_match_all(r.this_string(this), arg(args, 0)) })
  r.method(p, "search", fn(this, args, r) { r.regex_search(r.this_string(this), arg(args, 0)) })
  r.method(p, "@@iterator", fn(this, _, r) {
    let it = r.iterate(S(r.this_string(this)))
    r.list_iterator(it)
  })
  let b = r.ctor("Boolean", r.boolean_proto, fn(_, args, _) { B(arg(args, 0).truthy()) })
  ignore(b)
  r.method(r.boolean_proto, "toString", fn(this, _, _) {
    match this {
      B(x) | O({ kind: Boxed(B(x)), .. }) => S(if x { "true" } else { "false" })
      _ => S("false")
    }
  })
  r.method(r.boolean_proto, "valueOf", fn(this, _, _) {
    match this {
      O({ kind: Boxed(v), .. }) => v
      v => v
    }
  })
}

///|
/// String.prototype.replace / replaceAll: a string's first (or every) match of `pat` (a string or a RegExp) put in place
/// by `rep` (a string rep its $ patterns, or a function's answer).
fn Realm::replace(self : Realm, t : String, pat : Value, rep : Value, all : Bool) -> Value raise Throw {
  match pat {
    O({ kind: RegExp(_, _), .. }) => return self.regex_replace(t, pat, rep, all)
    _ => ()
  }
  let needle = self.to_string(pat)
  let b = StringBuilder()
  let mut from = 0
  let mut done = false
  while !done {
    match t.view(start_offset=from).find(needle) {
      Some(i) => {
        let at = from + i
        b.write_string(t.view(start_offset=from, end_offset=at).to_owned())
        let put = if rep.is_callable() {
          self.to_string(self.call(rep, Undefined, [S(needle), N(at.to_double()), S(t)]))
        } else {
          expand_dollars(self.to_string(rep), needle, [], t, at)
        }
        b.write_string(put)
        from = at + needle.length()
        if needle == "" {
          if from < t.length() {
            b.write_string(t.view(start_offset=from, end_offset=from + 1).to_owned())
          }
          from += 1
        }
        if !all || from > t.length() {
          done = true
        }
      }
      None => done = true
    }
  }
  if from < t.length() {
    b.write_string(t.view(start_offset=from).to_owned())
  }
  S(b.to_string())
}

///|
/// A replacement's $& $1.. $$ $` $' put in.
fn expand_dollars(rep : String, matched : String, groups : Array[String?], t : String, at : Int) -> String {
  if !rep.contains("$") {
    return rep
  }
  let b = StringBuilder()
  let mut i = 0
  while i < rep.length() {
    let c = rep.code_unit_at(i).to_int()
    if c == '$'.to_int() && i + 1 < rep.length() {
      let d = rep.code_unit_at(i + 1).to_int()
      if d == '$'.to_int() {
        b.write_char('$')
        i += 2
        continue
      }
      if d == '&'.to_int() {
        b.write_string(matched)
        i += 2
        continue
      }
      if d == '`'.to_int() {
        b.write_string(t.view(end_offset=at).to_owned())
        i += 2
        continue
      }
      if d == '\''.to_int() {
        b.write_string(t.view(start_offset=at + matched.length()).to_owned())
        i += 2
        continue
      }
      if d >= '1'.to_int() && d <= '9'.to_int() {
        let k = d - '0'.to_int()
        if k <= groups.length() {
          b.write_string(groups[k - 1].unwrap_or(""))
          i += 2
          continue
        }
      }
    }
    b.write_char(Int::unsafe_to_char(c))
    i += 1
  }
  b.to_string()
}

// ── Number ───────────────────────────────────────────────────────────

///|
fn Realm::this_number(self : Realm, this : Value) -> Double raise Throw {
  match this {
    N(n) => n
    O({ kind: Boxed(N(n)), .. }) => n
    _ => self.to_number(this)
  }
}

///|
/// `n` rep `digits` after the point (toFixed), rounded half away from zero as written in decimal.
pub fn fixed(n : Double, digits : Int) -> String {
  if n.is_nan() {
    return "NaN"
  }
  if n.abs() >= 1.0e21 {
    return number_to_string(n)
  }
  let neg = n < 0.0
  let scale = @dmath.pow(10.0, digits.to_double())
  let v = (n.abs() * scale + 0.5 + 1.0e-9 * n.abs() * scale / 1.0e15).floor()
  let whole = (v / scale).floor()
  let frac = v - whole * scale
  let ws = whole.to_int64().to_string()
  let s = if digits > 0 {
    let f = frac.to_int64().to_string()
    ws + "." + "0".repeat(digits - f.length()) + f
  } else {
    ws
  }
  if neg && v != 0.0 {
    "-" + s
  } else {
    s
  }
}

///|
/// toLocaleString in English: grouped by thousands, between `min` and `max` digits after the point.
pub fn locale_number(n : Double, min : Int, max : Int, group : Bool) -> String {
  if n.is_nan() {
    return "NaN"
  }
  if n.is_inf() {
    return if n > 0.0 { "∞" } else { "-∞" }
  }
  let s = fixed(n, max)
  let neg = s.has_prefix("-")
  let body = if neg { s.view(start_offset=1).to_owned() } else { s }
  let (int_part, frac0) = match body.find(".") {
    Some(at) => (body.view(end_offset=at).to_owned(), body.view(start_offset=at + 1).to_owned())
    None => (body, "")
  }
  let mut frac = frac0
  while frac.length() > min && frac.has_suffix("0") {
    frac = frac.view(end_offset=frac.length() - 1).to_owned()
  }
  let b = StringBuilder()
  let len = int_part.length()
  for i in 0..<len {
    if group && i > 0 && (len - i) % 3 == 0 {
      b.write_char(',')
    }
    b.write_char(Int::unsafe_to_char(int_part.code_unit_at(i).to_int()))
  }
  let out = if frac == "" { b.to_string() } else { b.to_string() + "." + frac }
  if neg {
    "-" + out
  } else {
    out
  }
}

///|
fn install_number(r : Realm) -> Unit {
  let n = r.ctor("Number", r.number_proto, fn(_, args, r) { N(if args.is_empty() { 0.0 } else { r.to_number(args[0]) }) })
  n.props["MAX_SAFE_INTEGER"] = Data(N(9007199254740991.0))
  n.props["MIN_SAFE_INTEGER"] = Data(N(-9007199254740991.0))
  n.props["EPSILON"] = Data(N(2.220446049250313e-16))
  n.props["MAX_VALUE"] = Data(N(1.7976931348623157e308))
  n.props["MIN_VALUE"] = Data(N(4.9406564584124654e-324))
  n.props["POSITIVE_INFINITY"] = Data(N(1.0 / 0.0))
  n.props["NEGATIVE_INFINITY"] = Data(N(-1.0 / 0.0))
  n.props["NaN"] = Data(N(0.0 / 0.0))
  r.method(n, "isInteger", fn(_, args, _) {
    match arg(args, 0) {
      N(x) => B(!x.is_nan() && !x.is_inf() && x == x.floor())
      _ => B(false)
    }
  })
  r.method(n, "isSafeInteger", fn(_, args, _) {
    match arg(args, 0) {
      N(x) => B(!x.is_nan() && !x.is_inf() && x == x.floor() && x.abs() <= 9007199254740991.0)
      _ => B(false)
    }
  })
  r.method(n, "isFinite", fn(_, args, _) {
    match arg(args, 0) {
      N(x) => B(!x.is_nan() && !x.is_inf())
      _ => B(false)
    }
  })
  r.method(n, "isNaN", fn(_, args, _) {
    match arg(args, 0) {
      N(x) => B(x.is_nan())
      _ => B(false)
    }
  })
  let parse_float : NativeFn = fn(_, args, r) {
    let t = r.to_string(arg(args, 0)).trim_start(chars=" \t\n\r").to_string()
    // the longest prefix that reads as a number
    let mut end = 0
    let mut best = 0.0 / 0.0
    if t.has_prefix("Infinity") || t.has_prefix("+Infinity") {
      return N(1.0 / 0.0)
    }
    if t.has_prefix("-Infinity") {
      return N(-1.0 / 0.0)
    }
    while end < t.length() && end < 400 {
      end += 1
      match parse_number_text(t.view(end_offset=end).to_owned()) {
        Some(v) => best = v
        None => {
          let c = t.code_unit_at(end - 1).to_int()
          if !(c == '.'.to_int() || c == 'e'.to_int() || c == 'E'.to_int() || c == '-'.to_int() || c == '+'.to_int()) {
            break
          }
        }
      }
    }
    N(best)
  }
  let parse_int : NativeFn = fn(_, args, r) {
    let t = r.to_string(arg(args, 0)).trim(chars=" \t\n\r").to_string()
    let mut radix = if arg(args, 1) is Undefined { 0 } else { r.to_number(arg(args, 1)).to_int() }
    let mut i = 0
    let mut neg = false
    if t.has_prefix("-") || t.has_prefix("+") {
      neg = t.has_prefix("-")
      i = 1
    }
    if (radix == 0 || radix == 16) && (t.view(start_offset=i).has_prefix("0x") || t.view(start_offset=i).has_prefix("0X")) {
      radix = 16
      i += 2
    }
    if radix == 0 {
      radix = 10
    }
    let mut v = 0.0
    let start = i
    while i < t.length() {
      let d = digit_value(t.code_unit_at(i).to_int())
      if d < 0 || d >= radix {
        break
      }
      v = v * radix.to_double() + d.to_double()
      i += 1
    }
    if i == start {
      return N(0.0 / 0.0)
    }
    N(if neg { -v } else { v })
  }
  r.method(n, "parseFloat", parse_float)
  r.method(n, "parseInt", parse_int)
  r.define_global("parseFloat", r.native("parseFloat", parse_float))
  r.define_global("parseInt", r.native("parseInt", parse_int))
  r.define_global("isNaN", r.native("isNaN", fn(_, args, r) { B(r.to_number(arg(args, 0)).is_nan()) }))
  r.define_global("isFinite", r.native("isFinite", fn(_, args, r) {
    let x = r.to_number(arg(args, 0))
    B(!x.is_nan() && !x.is_inf())
  }))
  let p = r.number_proto
  r.method(p, "toFixed", fn(this, args, r) { S(fixed(r.this_number(this), r.to_number(arg(args, 0)).to_int())) })
  r.method(p, "toString", fn(this, args, r) {
    let x = r.this_number(this)
    let radix = if arg(args, 0) is Undefined { 10 } else { r.to_number(arg(args, 0)).to_int() }
    if radix == 10 || x != x.floor() || x.is_nan() || x.is_inf() {
      return S(number_to_string(x))
    }
    let digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    let mut v = x.abs().to_int64()
    if v == 0L {
      return S("0")
    }
    let b = []
    while v > 0L {
      b.push(digits.view(start_offset=(v % radix.to_int64()).to_int(), end_offset=(v % radix.to_int64()).to_int() + 1).to_owned())
      v = v / radix.to_int64()
    }
    S((if x < 0.0 { "-" } else { "" }) + b.rev().join(""))
  })
  r.method(p, "toPrecision", fn(this, args, r) {
    let x = r.this_number(this)
    if arg(args, 0) is Undefined {
      return S(number_to_string(x))
    }
    let pdigits = r.to_number(arg(args, 0)).to_int()
    if x == 0.0 {
      return S(fixed(0.0, pdigits - 1))
    }
    let e = @dmath.log10(x.abs()).floor().to_int()
    if e < -6 || e >= pdigits {
      let m = x / @dmath.pow(10.0, e.to_double())
      S(fixed(m, pdigits - 1) + "e" + (if e >= 0 { "+" } else { "-" }) + e.abs().to_string())
    } else {
      S(fixed(x, pdigits - 1 - e))
    }
  })
  r.method(p, "toLocaleString", fn(this, args, r) {
    let x = r.this_number(this)
    let opts = arg(args, 1)
    let style = match opts {
      O(_) => r.get(opts, "style")
      _ => Undefined
    }
    let num_opt = fn(name : String, d : Int) raise Throw {
      match opts {
        O(_) =>
          match r.get(opts, name) {
            Undefined => d
            v => r.to_number(v).to_int()
          }
        _ => d
      }
    }
    let group = match opts {
      O(_) => !(r.get(opts, "useGrouping") is B(false))
      _ => true
    }
    let pct = style is S("percent")
    let v = if pct { x * 100.0 } else { x }
    let min = num_opt("minimumFractionDigits", 0)
    let maxd = num_opt("maximumFractionDigits", if pct { 0 } else if style is S("currency") { 2 } else { 3 })
    let max = if maxd < min { min } else { maxd }
    let body = locale_number(v, if style is S("currency") && min == 0 { 2 } else { min }, max, group)
    if pct {
      S(body + "%")
    } else if style is S("currency") {
      let cur = r.to_string(r.get(opts, "currency"))
      let sym = match cur {
        "USD" => "$"
        "EUR" => "€"
        "GBP" => "£"
        "JPY" | "CNY" => "¥"
        _ => cur + " "
      }
      S(if body.has_prefix("-") { "-" + sym + body.view(start_offset=1).to_owned() } else { sym + body })
    } else {
      S(body)
    }
  })
  r.method(p, "valueOf", fn(this, _, r) { N(r.this_number(this)) })
}

// ── Math ─────────────────────────────────────────────────────────────

///|
fn install_math(r : Realm) -> Unit {
  let m = r.new_obj()
  r.define_global("Math", O(m))
  m.props["PI"] = Data(N(3.141592653589793))
  m.props["E"] = Data(N(2.718281828459045))
  m.props["LN2"] = Data(N(0.6931471805599453))
  m.props["LN10"] = Data(N(2.302585092994046))
  m.props["LOG2E"] = Data(N(1.4426950408889634))
  m.props["LOG10E"] = Data(N(0.4342944819032518))
  m.props["SQRT2"] = Data(N(1.4142135623730951))
  m.props["SQRT1_2"] = Data(N(0.7071067811865476))
  let one = fn(name : String, f : (Double) -> Double) {
    r.method(m, name, fn(_, args, r) { N(f(r.to_number(arg(args, 0)))) })
  }
  one("abs", fn(x) { x.abs() })
  one("floor", fn(x) { x.floor() })
  one("ceil", fn(x) { x.ceil() })
  one("round", fn(x) { (x + 0.5).floor() })
  one("trunc", fn(x) { if x < 0.0 { x.ceil() } else { x.floor() } })
  one("sign", fn(x) { if x > 0.0 { 1.0 } else if x < 0.0 { -1.0 } else { x } })
  one("sqrt", fn(x) { x.sqrt() })
  one("cbrt", fn(x) { if x < 0.0 { -@dmath.pow(-x, 1.0 / 3.0) } else { @dmath.pow(x, 1.0 / 3.0) } })
  one("sin", @dmath.sin)
  one("cos", @dmath.cos)
  one("tan", @dmath.tan)
  one("asin", @dmath.asin)
  one("acos", @dmath.acos)
  one("atan", @dmath.atan)
  one("exp", @dmath.exp)
  one("expm1", @dmath.expm1)
  one("log", @dmath.ln)
  one("log1p", @dmath.ln_1p)
  one("log10", @dmath.log10)
  one("log2", @dmath.log2)
  one("fround", fn(x) { Float::from_double(x).to_double() })
  r.method(m, "atan2", fn(_, args, r) { N(@dmath.atan2(r.to_number(arg(args, 0)), r.to_number(arg(args, 1)))) })
  r.method(m, "pow", fn(_, args, r) { N(@dmath.pow(r.to_number(arg(args, 0)), r.to_number(arg(args, 1)))) })
  r.method(m, "hypot", fn(_, args, r) {
    let mut s = 0.0
    for a in args {
      let x = r.to_number(a)
      s += x * x
    }
    N(s.sqrt())
  })
  r.method(m, "max", fn(_, args, r) {
    let mut best = -1.0 / 0.0
    for a in args {
      let x = r.to_number(a)
      if x.is_nan() {
        return N(x)
      }
      if x > best {
        best = x
      }
    }
    N(best)
  })
  r.method(m, "min", fn(_, args, r) {
    let mut best = 1.0 / 0.0
    for a in args {
      let x = r.to_number(a)
      if x.is_nan() {
        return N(x)
      }
      if x < best {
        best = x
      }
    }
    N(best)
  })
  // a pseudo-random sequence of its own, the same every run (a widget drawn twice is drawn the same)
  let seed = Ref(0x2545F4914F6CDD1DL)
  r.method(m, "random", fn(_, _, _) {
    let mut x = seed.val
    x = x ^ (x << 13)
    x = x ^ (x.reinterpret_as_uint64() >> 7).reinterpret_as_int64()
    x = x ^ (x << 17)
    seed.val = x
    N((x.reinterpret_as_uint64() >> 11).to_double() / 9007199254740992.0)
  })
}

// ── errors ───────────────────────────────────────────────────────────

///|
fn install_errors(r : Realm) -> Unit {
  let make = fn(name : String, proto : Obj) {
    proto.props["name"] = Data(S(name))
    proto.hidden["name"] = true
    proto.props["message"] = Data(S(""))
    proto.hidden["message"] = true
    r.errors[name] = proto
    r.ctor(name, proto, fn(this, args, r) {
      let o = match this {
        O(t) if t.kind is Ordinary && t.proto is Some(p) && p.id == proto.id => t
        O(t) if t.kind is Ordinary && r.binary("instanceof", this, r.get(O(r.global_obj), name)).truthy() => t
        _ => r.new_obj(proto=Some(proto))
      }
      o.kind = Error
      if !(arg(args, 0) is Undefined) {
        o.props["message"] = Data(S(r.to_string(arg(args, 0))))
        o.hidden["message"] = true
      }
      O(o)
    })
    |> ignore
  }
  make("Error", r.error_proto)
  r.method(r.error_proto, "toString", fn(this, _, r) { S(r.to_display(this)) })
  for name in ["TypeError", "RangeError", "SyntaxError", "ReferenceError", "EvalError", "URIError"] {
    make(name, r.new_obj(proto=Some(r.error_proto)))
  }
}

// ── console ──────────────────────────────────────────────────────────

///|
fn install_console(r : Realm) -> Unit {
  let c = r.new_obj()
  r.define_global("console", O(c))
  for name in ["log", "info", "warn", "error", "debug"] {
    r.method(c, name, fn(_, args, r) {
      r.log.push(name + ": " + args.map(fn(a) { r.to_display(a) }).join(" "))
      Undefined
    })
  }
}
