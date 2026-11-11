// A realm: the global scope and the builtins' prototypes a script runs among, its objects numbered as they are made,
// how many steps it may take (a script that runs on is stopped, not the app), its timers (run by what hosts it at the
// moments it says: the widget's clock), what it logged.

///|
pub(all) struct Timer {
  id : Int
  at : Double
  every : Double
  f : Value
  args : Array[Value]
  /// an animation frame's (given the moment it is drawn at)
  frame : Bool
}

///|
pub(all) struct Realm {
  mut next_id : Int
  global : Env
  global_obj : Obj
  object_proto : Obj
  function_proto : Obj
  array_proto : Obj
  string_proto : Obj
  number_proto : Obj
  boolean_proto : Obj
  error_proto : Obj
  date_proto : Obj
  regexp_proto : Obj
  /// the steps it may take before it is stopped, and those taken
  mut budget : Int
  mut steps : Int
  /// what the host says the time is (Date.now, performance.now), in ms
  mut now : Double
  timers : Array[Timer]
  mut next_timer : Int
  log : Array[String]
  /// what is made of an error thrown by the realm itself, by its name
  errors : Map[String, Obj]
  /// the labels of the loop about to run (a labelled statement's), taken by it as it starts
  mut labels : Array[String]
  /// a host object's own properties, worked out by its host as they are read (None: as an ordinary object's) and
  /// written (false: as an ordinary object's)
  mut host_get : (Int, String) -> Value? raise Throw
  mut host_set : (Int, String, Value) -> Bool raise Throw
}

///|
pub fn Realm::new_obj(self : Realm, proto? : Obj? = Some(self.object_proto), kind? : Kind = Ordinary) -> Obj {
  self.next_id += 1
  { id: self.next_id, proto, props: {}, hidden: {}, kind }
}

///|
fn bare_obj(id : Int) -> Obj {
  { id, proto: None, props: {}, hidden: {}, kind: Ordinary }
}

///|
/// A realm with the builtins (builtins.mbt), `budget` steps a run.
pub fn Realm::new(budget? : Int = 5_000_000) -> Realm {
  let object_proto = bare_obj(1)
  let mk = fn(id : Int) -> Obj { { ..bare_obj(id), proto: Some(object_proto) } }
  let global_obj = mk(2)
  let r : Realm = {
    next_id: 20,
    global: Env::new(None, fn_scope=true),
    global_obj,
    object_proto,
    function_proto: mk(3),
    array_proto: { ..mk(4), kind: Arr([]) },
    string_proto: mk(5),
    number_proto: mk(6),
    boolean_proto: mk(7),
    error_proto: mk(8),
    date_proto: mk(9),
    regexp_proto: mk(10),
    budget,
    steps: 0,
    now: 0.0,
    timers: [],
    next_timer: 1,
    log: [],
    errors: {},
    labels: [],
    host_get: fn(_, _) { None },
    host_set: fn(_, _, _) { false },
  }
  r.global.this_val = Some(Undefined)
  install_builtins(r)
  r
}

///|
pub fn Realm::step(self : Realm) -> Unit raise Throw {
  self.steps += 1
  if self.steps > self.budget {
    raise Throw(S("RangeError: the script ran too long"))
  }
}

///|
/// An error of `name` (TypeError, RangeError...) with `message`, thrown.
pub fn Realm::error(self : Realm, name : String, message : String) -> Throw {
  let proto = match self.errors.get(name) {
    Some(p) => p
    None => self.error_proto
  }
  let o = self.new_obj(proto=Some(proto), kind=Error)
  o.props["message"] = Data(S(message))
  o.hidden["message"] = true
  Throw(O(o))
}

///|
/// A native function named `name` of `arity` arguments.
pub fn Realm::native(self : Realm, name : String, f : NativeFn, arity? : Int = 0) -> Value {
  let o = self.new_obj(proto=Some(self.function_proto), kind=Native(name, f))
  o.props["name"] = Data(S(name))
  o.hidden["name"] = true
  o.props["length"] = Data(N(arity.to_double()))
  o.hidden["length"] = true
  O(o)
}

///|
/// `f` as a method `name` of `o`, not enumerable.
pub fn Realm::method(self : Realm, o : Obj, name : String, f : NativeFn, arity? : Int = 0) -> Unit {
  o.props[name] = Data(self.native(name, f, arity~))
  o.hidden[name] = true
}

///|
/// An accessor `name` of `o`: what reading it gives, what writing it does (None: read only).
pub fn Realm::accessor(self : Realm, o : Obj, name : String, get : NativeFn, set? : NativeFn? = None) -> Unit {
  let s = match set {
    Some(f) => self.native("set " + name, f)
    None => Undefined
  }
  o.props[name] = Accessor(self.native("get " + name, get), s)
  o.hidden[name] = true
}

///|
pub fn Realm::define_global(self : Realm, name : String, v : Value) -> Unit {
  self.global.put_var(name, v)
  self.global_obj.props[name] = Data(v)
  self.global_obj.hidden[name] = true
}

///|
pub fn Realm::array(self : Realm, items : Array[Value]) -> Value {
  O(self.new_obj(proto=Some(self.array_proto), kind=Arr(items)))
}

///|
pub fn Realm::object(self : Realm, props : Array[(String, Value)]) -> Value {
  let o = self.new_obj()
  for p in props {
    o.props[p.0] = Data(p.1)
  }
  O(o)
}

// ── properties ───────────────────────────────────────────────────────

///|
fn Realm::find_slot(self : Realm, o : Obj, key : String) -> Slot? {
  ignore(self)
  let mut cur : Obj? = Some(o)
  let mut depth = 0
  while cur is Some(c) && depth < 1000 {
    match c.kind {
      Arr(items) =>
        match index_of_key(key) {
          Some(i) => return if i < items.length() { Some(Data(items[i])) } else { None }
          None => if key == "length" { return Some(Data(N(items.length().to_double()))) }
        }
      Boxed(S(s)) =>
        match index_of_key(key) {
          Some(i) if i < s.length() => return Some(Data(S(s.view(start_offset=i, end_offset=i + 1).to_owned())))
          _ => if key == "length" { return Some(Data(N(s.length().to_double()))) }
        }
      _ => ()
    }
    match c.props.get(key) {
      Some(s) => return Some(s)
      None => ()
    }
    cur = c.proto
    depth += 1
  }
  None
}

///|
/// `key` of value `v` (its prototype's for a primitive), `this` the value read from.
pub fn Realm::get(self : Realm, v : Value, key : String) -> Value raise Throw {
  let o = match v {
    O(o) => o
    S(s) => {
      if key == "length" {
        return N(s.length().to_double())
      }
      match index_of_key(key) {
        Some(i) => return if i < s.length() { S(s.view(start_offset=i, end_offset=i + 1).to_owned()) } else { Undefined }
        None => self.string_proto
      }
    }
    N(_) => self.number_proto
    B(_) => self.boolean_proto
    Undefined | Null => raise self.error("TypeError", "Cannot read properties of \{self.to_display(v)} (reading '\{key}')")
  }
  if o.kind is Host(id) && !o.props.contains(key) {
    match (self.host_get)(id, key) {
      Some(x) => return x
      None => ()
    }
  }
  match self.find_slot(o, key) {
    Some(Data(x)) => x
    Some(Accessor(g, _)) => if g is Undefined { Undefined } else { self.call(g, v, []) }
    None => Undefined
  }
}

///|
pub fn Realm::set(self : Realm, v : Value, key : String, value : Value) -> Unit raise Throw {
  let o = match v {
    O(o) => o
    Undefined | Null => raise self.error("TypeError", "Cannot set properties of \{self.to_display(v)} (setting '\{key}')")
    _ => return
  }
  if o.kind is Host(id) && !o.props.contains(key) && (self.host_set)(id, key, value) {
    return
  }
  match o.kind {
    Arr(items) => {
      match index_of_key(key) {
        Some(i) => {
          while items.length() <= i {
            items.push(Undefined)
          }
          items[i] = value
          return
        }
        None => ()
      }
      if key == "length" {
        let n = self.to_number(value).to_int()
        while items.length() > n {
          items.pop() |> ignore
        }
        while items.length() < n {
          items.push(Undefined)
        }
        return
      }
    }
    _ => ()
  }
  // a setter on it or its prototypes
  match o.props.get(key) {
    Some(Data(_)) => {
      o.props[key] = Data(value)
      return
    }
    _ => ()
  }
  match self.find_slot(o, key) {
    Some(Accessor(_, s)) => {
      if !(s is Undefined) {
        self.call(s, v, [value]) |> ignore
      }
      return
    }
    _ => ()
  }
  o.props[key] = Data(value)
}

///|
pub fn Realm::has(self : Realm, o : Obj, key : String) -> Bool {
  self.find_slot(o, key) is Some(_)
}

///|
/// Its own enumerable keys, in order (an array's indexes first).
pub fn Realm::own_keys(self : Realm, o : Obj) -> Array[String] {
  ignore(self)
  let out = []
  match o.kind {
    Arr(items) => for i in 0..<items.length() { out.push(i.to_string()) }
    Boxed(S(s)) => for i in 0..<s.length() { out.push(i.to_string()) }
    _ => ()
  }
  o.props.each(fn(k, _) { if !o.hidden.contains(k) { out.push(k) } })
  out
}

///|
pub fn Realm::key_of(self : Realm, v : Value) -> String raise Throw {
  match v {
    S(s) => s
    N(n) => number_to_string(n)
    _ => self.to_string(v)
  }
}

// ── conversions that may call ────────────────────────────────────────

///|
pub fn Realm::to_primitive(self : Realm, v : Value, hint? : String = "default") -> Value raise Throw {
  match v {
    O(o) => {
      if o.kind is Date(t) && hint != "number" {
        return S(date_string(t))
      }
      let order = if hint == "string" { ["toString", "valueOf"] } else { ["valueOf", "toString"] }
      for name in order {
        let f = self.get(v, name)
        if f.is_callable() {
          let r = self.call(f, v, [])
          if !(r is O(_)) {
            return r
          }
        }
      }
      raise self.error("TypeError", "Cannot convert object to primitive value")
    }
    _ => v
  }
}

///|
pub fn Realm::to_number(self : Realm, v : Value) -> Double raise Throw {
  match v {
    Undefined => 0.0 / 0.0
    Null => 0.0
    B(b) => if b { 1.0 } else { 0.0 }
    N(n) => n
    S(s) => string_to_number(s)
    O(_) => self.to_number(self.to_primitive(v, hint="number"))
  }
}

///|
pub fn Realm::to_string(self : Realm, v : Value) -> String raise Throw {
  match v {
    Undefined => "undefined"
    Null => "null"
    B(b) => if b { "true" } else { "false" }
    N(n) => number_to_string(n)
    S(s) => s
    O(_) => self.to_string(self.to_primitive(v, hint="string"))
  }
}

///|
/// A value as an error's message or console names it, calling nothing.
pub fn Realm::to_display(self : Realm, v : Value) -> String {
  match v {
    O(o) =>
      match o.kind {
        Arr(items) => {
          let parts = items.map(fn(x) { self.to_display(x) })
          parts.join(",")
        }
        Error => {
          let name = match self.find_slot(o, "name") {
            Some(Data(S(n))) => n
            _ => "Error"
          }
          let msg = match o.props.get("message") {
            Some(Data(S(m))) => m
            _ => ""
          }
          if msg == "" {
            name
          } else {
            name + ": " + msg
          }
        }
        Closure(_) | Native(_, _) | Bound(_, _, _) => "function"
        _ => "[object Object]"
      }
    _ => self.to_string(v) catch { _ => "?" }
  }
}

///|
pub fn Realm::to_object(self : Realm, v : Value) -> Obj raise Throw {
  match v {
    O(o) => o
    S(_) => self.new_obj(proto=Some(self.string_proto), kind=Boxed(v))
    N(_) => self.new_obj(proto=Some(self.number_proto), kind=Boxed(v))
    B(_) => self.new_obj(proto=Some(self.boolean_proto), kind=Boxed(v))
    _ => raise self.error("TypeError", "Cannot convert undefined or null to object")
  }
}

///|
pub fn Realm::loose_equal(self : Realm, a : Value, b : Value) -> Bool raise Throw {
  match (a, b) {
    (Undefined | Null, Undefined | Null) => true
    (Undefined | Null, _) | (_, Undefined | Null) => false
    (N(_), S(_)) | (S(_), N(_)) | (B(_), _) | (_, B(_)) =>
      if a is O(_) || b is O(_) {
        self.loose_equal(self.to_primitive(a), self.to_primitive(b))
      } else {
        self.to_number(a) == self.to_number(b)
      }
    (O(_), O(_)) => strict_equal(a, b)
    (O(_), _) => self.loose_equal(self.to_primitive(a), b)
    (_, O(_)) => self.loose_equal(a, self.to_primitive(b))
    _ => strict_equal(a, b)
  }
}
