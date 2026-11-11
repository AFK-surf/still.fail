// Date (its time the host's: the realm's `now`, UTC as a widget is drawn), Map and Set, iterators over lists, Promise
// (settled as its work is done; then-callbacks as microtasks the host drains after each run), timers.

///|
fn days_from_civil(y0 : Int, m : Int, d : Int) -> Int {
  let y = if m <= 2 { y0 - 1 } else { y0 }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400
  let mp = (m + 9) % 12
  let doy = (153 * mp + 2) / 5 + d - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146097 + doe - 719468
}

///|
/// A time's year, month (1-12), day, hours, minutes, seconds, ms, weekday (0 Sunday), in UTC.
fn civil(t : Double) -> (Int, Int, Int, Int, Int, Int, Int, Int) {
  let ms_day = 86400000.0
  let days = (t / ms_day).floor()
  let rest = (t - days * ms_day).to_int()
  let z = days.to_int() + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  let y = yoe + era * 400 + (if m <= 2 { 1 } else { 0 })
  let wd = ((days.to_int() % 7) + 11) % 7
  (y, m, d, rest / 3600000, rest / 60000 % 60, rest / 1000 % 60, rest % 1000, wd)
}

///|
fn pad2(n : Int) -> String {
  if n < 10 {
    "0" + n.to_string()
  } else {
    n.to_string()
  }
}

///|
fn date_string(t : Double) -> String {
  if t.is_nan() {
    return "Invalid Date"
  }
  let (y, m, d, h, mi, s, _, wd) = civil(t)
  let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  "\{days[wd]} \{months[m - 1]} \{pad2(d)} \{y} \{pad2(h)}:\{pad2(mi)}:\{pad2(s)} GMT+0000 (Coordinated Universal Time)"
}

///|
fn iso_string(t : Double) -> String {
  let (y, m, d, h, mi, s, ms, _) = civil(t)
  let msd = if ms < 10 { "00" + ms.to_string() } else if ms < 100 { "0" + ms.to_string() } else { ms.to_string() }
  "\{y}-\{pad2(m)}-\{pad2(d)}T\{pad2(h)}:\{pad2(mi)}:\{pad2(s)}.\{msd}Z"
}

///|
/// A date's text as Date.parse reads it: ISO dates and times (UTC where no zone is said: as drawn here).
fn parse_date(s : String) -> Double {
  let t = s.trim(chars=" ").to_string()
  let num = fn(a : Int, b : Int) -> Int? {
    if b > t.length() {
      return None
    }
    let mut v = 0
    for i in a..<b {
      let c = t.code_unit_at(i).to_int()
      if c < '0'.to_int() || c > '9'.to_int() {
        return None
      }
      v = v * 10 + (c - '0'.to_int())
    }
    Some(v)
  }
  match (num(0, 4), num(5, 7), num(8, 10)) {
    (Some(y), Some(m), Some(d)) => {
      let mut ms = days_from_civil(y, m, d).to_double() * 86400000.0
      if t.length() >= 16 {
        match (num(11, 13), num(14, 16)) {
          (Some(h), Some(mi)) => {
            ms += (h * 3600000 + mi * 60000).to_double()
            match num(17, 19) {
              Some(sec) => ms += (sec * 1000).to_double()
              None => ()
            }
          }
          _ => ()
        }
      }
      ms
    }
    (Some(y), Some(m), None) => days_from_civil(y, m, 1).to_double() * 86400000.0
    _ => 0.0 / 0.0
  }
}

///|
fn install_date(r : Realm) -> Unit {
  let d = r.ctor("Date", r.date_proto, fn(this, args, r) {
    let t = match args {
      [] => r.now
      [N(n)] => n
      [S(s)] => parse_date(s)
      [O({ kind: Date(t), .. })] => t
      [y, m, ..] => {
        let num = fn(i : Int, dflt : Double) raise Throw { if i < args.length() { r.to_number(args[i]) } else { dflt } }
        let yy = r.to_number(y).to_int()
        let mm = r.to_number(m).to_int()
        let base = days_from_civil(yy + mm / 12, mm % 12 + 1, 1).to_double() * 86400000.0
        base + (num(2, 1.0) - 1.0) * 86400000.0 + num(3, 0.0) * 3600000.0 + num(4, 0.0) * 60000.0 + num(5, 0.0) * 1000.0 + num(6, 0.0)
      }
      [x] => r.to_number(x)
    }
    match this {
      // called as a function: its text
      Undefined => S(date_string(r.now))
      O(o) if o.kind is Ordinary => {
        o.kind = Date(t)
        O(o)
      }
      _ => O(r.new_obj(proto=Some(r.date_proto), kind=Date(t)))
    }
  })
  r.method(d, "now", fn(_, _, r) { N(r.now) })
  r.method(d, "parse", fn(_, args, r) { N(parse_date(r.to_string(arg(args, 0)))) })
  r.method(d, "UTC", fn(_, args, r) {
    let num = fn(i : Int, dflt : Double) raise Throw { if i < args.length() { r.to_number(args[i]) } else { dflt } }
    let yy = num(0, 1970.0).to_int()
    let mm = num(1, 0.0).to_int()
    N(days_from_civil(yy + mm / 12, mm % 12 + 1, 1).to_double() * 86400000.0 + (num(2, 1.0) - 1.0) * 86400000.0 + num(3, 0.0) * 3600000.0 + num(4, 0.0) * 60000.0 + num(5, 0.0) * 1000.0)
  })
  let p = r.date_proto
  let time = fn(this : Value) {
    match this {
      O({ kind: Date(t), .. }) => t
      _ => 0.0 / 0.0
    }
  }
  r.method(p, "getTime", fn(this, _, _) { N(time(this)) })
  r.method(p, "valueOf", fn(this, _, _) { N(time(this)) })
  r.method(p, "toISOString", fn(this, _, _) { S(iso_string(time(this))) })
  r.method(p, "toJSON", fn(this, _, _) { S(iso_string(time(this))) })
  r.method(p, "toString", fn(this, _, _) { S(date_string(time(this))) })
  let part = fn(name : String, f : ((Int, Int, Int, Int, Int, Int, Int, Int)) -> Int) {
    r.method(p, name, fn(this, _, _) {
      let t = time(this)
      if t.is_nan() {
        N(t)
      } else {
        N(f(civil(t)).to_double())
      }
    })
  }
  for pre in ["get", "getUTC"] {
    part(pre + "FullYear", fn(c) { c.0 })
    part(pre + "Month", fn(c) { c.1 - 1 })
    part(pre + "Date", fn(c) { c.2 })
    part(pre + "Hours", fn(c) { c.3 })
    part(pre + "Minutes", fn(c) { c.4 })
    part(pre + "Seconds", fn(c) { c.5 })
    part(pre + "Milliseconds", fn(c) { c.6 })
    part(pre + "Day", fn(c) { c.7 })
  }
  r.method(p, "getTimezoneOffset", fn(_, _, _) { N(0.0) })
  r.method(p, "setTime", fn(this, args, r) {
    let t = r.to_number(arg(args, 0))
    match this {
      O(o) => o.kind = Date(t)
      _ => ()
    }
    N(t)
  })
  r.method(p, "toLocaleDateString", fn(this, _, _) {
    let (y, m, d, _, _, _, _, _) = civil(time(this))
    S("\{m}/\{d}/\{y}")
  })
  r.method(p, "toLocaleTimeString", fn(this, _, _) {
    let (_, _, _, h, mi, s, _, _) = civil(time(this))
    let h12 = if h % 12 == 0 { 12 } else { h % 12 }
    S("\{h12}:\{pad2(mi)}:\{pad2(s)} \{if h < 12 { "AM" } else { "PM" }}")
  })
  r.method(p, "toLocaleString", fn(this, _, _) {
    let (y, m, d, h, mi, s, _, _) = civil(time(this))
    let h12 = if h % 12 == 0 { 12 } else { h % 12 }
    S("\{m}/\{d}/\{y}, \{h12}:\{pad2(mi)}:\{pad2(s)} \{if h < 12 { "AM" } else { "PM" }}")
  })
  let perf = r.new_obj()
  r.method(perf, "now", fn(_, _, r) { N(r.now) })
  r.define_global("performance", O(perf))
  install_regexp(r)
}

// ── iterators, Map, Set ──────────────────────────────────────────────

///|
/// An iterator over `items` (and iterable itself: what for-of and spread take).
pub fn Realm::list_iterator(self : Realm, items : Array[Value]) -> Value {
  let it = self.new_obj()
  it.props["@@items"] = Data(self.array(items))
  it.hidden["@@items"] = true
  let at = Ref(0)
  self.method(it, "next", fn(_, _, r) {
    if at.val < items.length() {
      at.val += 1
      r.object([("value", items[at.val - 1]), ("done", B(false))])
    } else {
      r.object([("value", Undefined), ("done", B(true))])
    }
  })
  O(it)
}

///|
/// A Map's or Set's entries: keys and values in order.
priv struct Entries {
  keys : Array[Value]
  values : Array[Value]
}

///|
fn Entries::find(self : Entries, k : Value) -> Int? {
  for i, x in self.keys {
    if same_value_zero(x, k) {
      return Some(i)
    }
  }
  None
}

///|
fn install_collections(r : Realm) -> Unit {
  let stores : Map[Int, Entries] = {}
  let store_of = fn(this : Value, r : Realm) raise Throw {
    match this {
      O(o) =>
        match stores.get(o.id) {
          Some(s) => s
          None => raise r.error("TypeError", "not a Map or Set")
        }
      _ => raise r.error("TypeError", "not a Map or Set")
    }
  }
  for set in [false, true] {
    let proto = r.new_obj()
    let name = if set { "Set" } else { "Map" }
    r.ctor(name, proto, fn(this, args, r) {
      let o = match this {
        O(x) if x.kind is Ordinary => x
        _ => r.new_obj(proto=Some(proto))
      }
      let e : Entries = { keys: [], values: [] }
      stores[o.id] = e
      if !(arg(args, 0) is Undefined || arg(args, 0) is Null) {
        for item in r.iterate(arg(args, 0)) {
          let (k, v) = if set { (item, item) } else { (r.get(item, "0"), r.get(item, "1")) }
          match e.find(k) {
            Some(i) => e.values[i] = v
            None => {
              e.keys.push(k)
              e.values.push(v)
            }
          }
        }
      }
      O(o)
    })
    |> ignore
    r.accessor(proto, "size", fn(this, _, r) { N(store_of(this, r).keys.length().to_double()) })
    if set {
      r.method(proto, "add", fn(this, args, r) {
        let e = store_of(this, r)
        if e.find(arg(args, 0)) is None {
          e.keys.push(arg(args, 0))
          e.values.push(arg(args, 0))
        }
        this
      })
    } else {
      r.method(proto, "set", fn(this, args, r) {
        let e = store_of(this, r)
        match e.find(arg(args, 0)) {
          Some(i) => e.values[i] = arg(args, 1)
          None => {
            e.keys.push(arg(args, 0))
            e.values.push(arg(args, 1))
          }
        }
        this
      })
      r.method(proto, "get", fn(this, args, r) {
        let e = store_of(this, r)
        match e.find(arg(args, 0)) {
          Some(i) => e.values[i]
          None => Undefined
        }
      })
    }
    r.method(proto, "has", fn(this, args, r) { B(store_of(this, r).find(arg(args, 0)) is Some(_)) })
    r.method(proto, "delete", fn(this, args, r) {
      let e = store_of(this, r)
      match e.find(arg(args, 0)) {
        Some(i) => {
          e.keys.remove(i) |> ignore
          e.values.remove(i) |> ignore
          B(true)
        }
        None => B(false)
      }
    })
    r.method(proto, "clear", fn(this, _, r) {
      let e = store_of(this, r)
      e.keys.clear()
      e.values.clear()
      Undefined
    })
    r.method(proto, "forEach", fn(this, args, r) {
      let e = store_of(this, r)
      let f = r.callback(arg(args, 0))
      for i, k in e.keys.copy() {
        r.call(f, arg(args, 1), [e.values[i], k, this]) |> ignore
      }
      Undefined
    })
    r.method(proto, "keys", fn(this, _, r) { r.list_iterator(store_of(this, r).keys.copy()) })
    r.method(proto, "values", fn(this, _, r) { r.list_iterator(store_of(this, r).values.copy()) })
    let entries : NativeFn = fn(this, _, r) {
      let e = store_of(this, r)
      if set {
        r.list_iterator(e.keys.map(fn(k) { r.array([k, k]) }))
      } else {
        r.list_iterator(e.keys.mapi(fn(i, k) { r.array([k, e.values[i]]) }))
      }
    }
    r.method(proto, "entries", entries)
    r.method(proto, "@@iterator", if set { fn(this, _, r) { r.list_iterator(store_of(this, r).keys.copy()) } } else { entries })
  }
  install_promise(r)
}

// ── Promise ──────────────────────────────────────────────────────────

///|
/// Callbacks waiting to run once the current run ends (promise reactions, queueMicrotask).
// kept across runs: the realm's own (made with it)
let jobs : Array[(Realm, () -> Unit raise Throw)] = []

///|
/// Runs what waits to run (promise reactions), until none is left; what they threw logged.
pub fn Realm::drain(self : Realm) -> Unit {
  let mut rounds = 0
  while true {
    let mine = jobs.search_by(fn(j) { physical_equal(j.0, self) })
    match mine {
      Some(i) => {
        let (_, job) = jobs.remove(i)
        job() catch {
          Throw(v) => self.log.push("error: " + self.to_display(v))
        }
      }
      None => break
    }
    rounds += 1
    if rounds > 100000 {
      break
    }
  }
}

///|
fn Realm::settle(self : Realm, p : Obj, state : String, v : Value) -> Unit {
  match p.props.get("@@state") {
    Some(Data(S("pending"))) => ()
    _ => return
  }
  p.props["@@state"] = Data(S(state))
  p.props["@@value"] = Data(v)
  let waiting = match p.props.get("@@then") {
    Some(Data(O({ kind: Arr(items), .. }))) => items.copy()
    _ => []
  }
  for w in waiting {
    match w {
      O(cb) =>
        match cb.kind {
          Native(_, f) => jobs.push((self, fn() raise Throw { f(Undefined, [], self) |> ignore }))
          _ => ()
        }
      _ => ()
    }
  }
}

///|
fn Realm::new_promise(self : Realm, proto : Obj) -> Obj {
  let p = self.new_obj(proto=Some(proto))
  p.props["@@state"] = Data(S("pending"))
  p.hidden["@@state"] = true
  p.props["@@value"] = Data(Undefined)
  p.hidden["@@value"] = true
  p.props["@@then"] = Data(self.array([]))
  p.hidden["@@then"] = true
  p
}

///|
/// `p` resolved with `v`: a promise (or thenable) followed, else fulfilled.
fn Realm::resolve_with(self : Realm, p : Obj, v : Value) -> Unit {
  match v {
    O(o) if o.props.contains("@@state") => {
      let follow = fn() {
        match (o.props.get("@@state"), o.props.get("@@value")) {
          (Some(Data(S(st))), Some(Data(x))) => self.settle(p, st, x)
          _ => ()
        }
      }
      match o.props.get("@@state") {
        Some(Data(S("pending"))) =>
          match o.props.get("@@then") {
            Some(Data(O({ kind: Arr(items), .. }))) => items.push(self.native("follow", fn(_, _, _) { follow(); Undefined }))
            _ => ()
          }
        _ => follow()
      }
    }
    _ => self.settle(p, "fulfilled", v)
  }
}

///|
fn install_promise(r : Realm) -> Unit {
  let proto = r.new_obj()
  let pctor = r.ctor("Promise", proto, fn(_, args, r) {
    let p = r.new_promise(proto)
    let exec = r.callback(arg(args, 0))
    let res = r.native("resolve", fn(_, a, r) { r.resolve_with(p, arg(a, 0)); Undefined })
    let rej = r.native("reject", fn(_, a, r) { r.settle(p, "rejected", arg(a, 0)); Undefined })
    let _ = r.call(exec, Undefined, [res, rej]) catch {
      Throw(v) => {
        r.settle(p, "rejected", v)
        Undefined
      }
    }
    O(p)
  })
  r.method(pctor, "resolve", fn(_, args, r) {
    match arg(args, 0) {
      O(o) if o.props.contains("@@state") => O(o)
      v => {
        let p = r.new_promise(proto)
        r.resolve_with(p, v)
        O(p)
      }
    }
  })
  r.method(pctor, "reject", fn(_, args, r) {
    let p = r.new_promise(proto)
    r.settle(p, "rejected", arg(args, 0))
    O(p)
  })
  r.method(pctor, "all", fn(_, args, r) {
    let p = r.new_promise(proto)
    let items = r.iterate(arg(args, 0))
    let results = Array::make(items.length(), Undefined)
    let left = Ref(items.length())
    if items.is_empty() {
      r.settle(p, "fulfilled", r.array([]))
    }
    for i, it in items {
      let each = r.call(r.get(O(pctor), "resolve"), O(pctor), [it])
      r.call(r.get(each, "then"), each, [
        r.native("ok", fn(_, a, r) {
          results[i] = arg(a, 0)
          left.val -= 1
          if left.val == 0 {
            r.settle(p, "fulfilled", r.array(results))
          }
          Undefined
        }),
        r.native("no", fn(_, a, r) { r.settle(p, "rejected", arg(a, 0)); Undefined }),
      ]) |> ignore
    }
    O(p)
  })
  let then : NativeFn = fn(this, args, r) {
    let src = match this {
      O(o) => o
      _ => raise r.error("TypeError", "not a promise")
    }
    let out = r.new_promise(proto)
    let on_ok = arg(args, 0)
    let on_err = arg(args, 1)
    let react = fn() raise Throw {
      match (src.props.get("@@state"), src.props.get("@@value")) {
        (Some(Data(S("fulfilled"))), Some(Data(v))) =>
          if on_ok.is_callable() {
            let res : Result[Value, Value] = try { Ok(r.call(on_ok, Undefined, [v])) } catch { Throw(e) => Err(e) }
            match res {
              Ok(x) => r.resolve_with(out, x)
              Err(e) => r.settle(out, "rejected", e)
            }
          } else {
            r.settle(out, "fulfilled", v)
          }
        (Some(Data(S("rejected"))), Some(Data(v))) =>
          if on_err.is_callable() {
            let res : Result[Value, Value] = try { Ok(r.call(on_err, Undefined, [v])) } catch { Throw(e) => Err(e) }
            match res {
              Ok(x) => r.resolve_with(out, x)
              Err(e) => r.settle(out, "rejected", e)
            }
          } else {
            r.settle(out, "rejected", v)
          }
        _ => ()
      }
    }
    match src.props.get("@@state") {
      Some(Data(S("pending"))) =>
        match src.props.get("@@then") {
          Some(Data(O({ kind: Arr(items), .. }))) => items.push(r.native("react", fn(_, _, _) { react(); Undefined }))
          _ => ()
        }
      _ => jobs.push((r, react))
    }
    O(out)
  }
  r.method(proto, "then", then)
  r.method(proto, "catch", fn(this, args, r) { then(this, [Undefined, arg(args, 0)], r) })
  r.method(proto, "finally", fn(this, args, r) {
    let f = arg(args, 0)
    let pass = r.native("finally", fn(_, a, r) {
      if f.is_callable() {
        r.call(f, Undefined, []) |> ignore
      }
      arg(a, 0)
    })
    then(this, [pass, r.native("finally", fn(_, a, r) {
      if f.is_callable() {
        r.call(f, Undefined, []) |> ignore
      }
      raise Throw(arg(a, 0))
    })], r)
  })
  r.define_global("queueMicrotask", r.native("queueMicrotask", fn(_, args, r) {
    let f = r.callback(arg(args, 0))
    jobs.push((r, fn() raise Throw { r.call(f, Undefined, []) |> ignore }))
    Undefined
  }))
}

// ── timers ───────────────────────────────────────────────────────────

///|
fn install_timers(r : Realm) -> Unit {
  let add = fn(r : Realm, args : Array[Value], every : Bool, frame : Bool) raise Throw {
    let f = r.callback(arg(args, 0))
    let ms = if frame { 0.0 } else { let x = r.to_number(arg(args, 1)); if x.is_nan() || x < 0.0 { 0.0 } else { x } }
    let id = r.next_timer
    r.next_timer += 1
    r.timers.push({ id, at: r.now + ms, every: if every { if ms < 1.0 { 1.0 } else { ms } } else { -1.0 }, f, args: if args.length() > 2 { args[2:].to_array() } else { [] }, frame })
    N(id.to_double())
  }
  let clear : NativeFn = fn(_, args, r) {
    let id = r.to_number(arg(args, 0)).to_int()
    match r.timers.search_by(fn(t) { t.id == id }) {
      Some(i) => r.timers.remove(i) |> ignore
      None => ()
    }
    Undefined
  }
  r.define_global("setTimeout", r.native("setTimeout", fn(_, args, r) { add(r, args, false, false) }))
  r.define_global("setInterval", r.native("setInterval", fn(_, args, r) { add(r, args, true, false) }))
  r.define_global("requestAnimationFrame", r.native("requestAnimationFrame", fn(_, args, r) { add(r, args, false, true) }))
  r.define_global("clearTimeout", r.native("clearTimeout", clear))
  r.define_global("clearInterval", r.native("clearInterval", clear))
  r.define_global("cancelAnimationFrame", r.native("cancelAnimationFrame", clear))
}

///|
/// The moment the next timer is due (None: none waits).
pub fn Realm::next_due(self : Realm) -> Double? {
  let mut best : Double? = None
  for t in self.timers {
    match best {
      Some(b) if b <= t.at => ()
      _ => best = Some(t.at)
    }
  }
  best
}

///|
/// The time now `now`: the timers due by then run, in the order they are due (an animation frame given `now`), each
/// run's microtasks after it; what they threw logged.
pub fn Realm::advance(self : Realm, now : Double) -> Unit {
  let mut rounds = 0
  while rounds < 10000 {
    rounds += 1
    let mut pick = -1
    for i, t in self.timers {
      if t.at <= now && (pick < 0 || t.at < self.timers[pick].at) {
        pick = i
      }
    }
    if pick < 0 {
      break
    }
    let t = self.timers[pick]
    self.now = if t.at > self.now { t.at } else { self.now }
    if t.every > 0.0 {
      self.timers[pick] = { ..t, at: t.at + t.every }
    } else {
      self.timers.remove(pick) |> ignore
    }
    self.steps = 0
    let args = if t.frame { [N(self.now)] } else { t.args }
    let _ = self.call(t.f, Undefined, args) catch {
      Throw(v) => {
        self.log.push("error: " + self.to_display(v))
        Undefined
      }
    }
    self.drain()
  }
  self.now = now
}
