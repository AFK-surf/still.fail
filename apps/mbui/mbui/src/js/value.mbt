// A script's values and objects: the primitives, and objects as property maps in their order with a prototype, of a
// kind (an ordinary object, an array with its elements, a function its code and scope or a native one, a date, a
// regular expression, an error, a host's object by its number), properties data or accessors.

///|
pub(all) enum Value {
  Undefined
  Null
  B(Bool)
  N(Double)
  S(String)
  O(Obj)
}

///|
pub(all) enum Slot {
  Data(Value)
  /// getter, setter (functions)
  Accessor(Value, Value)
}

///|
/// A native function: what `this` is, its arguments, the realm.
pub type NativeFn = (Value, Array[Value], Realm) -> Value raise Throw

///|
pub(all) enum Kind {
  Ordinary
  Arr(Array[Value])
  Closure(Closure)
  Native(String, NativeFn)
  Bound(Value, Value, Array[Value])
  Date(Double)
  RegExp(String, String)
  Error
  /// a host's object, by its number (what made it keeps what it is)
  Host(Int)
  Boxed(Value)
}

///|
pub(all) struct Obj {
  id : Int
  mut proto : Obj?
  props : Map[String, Slot]
  /// properties not enumerable (methods of builtins and classes)
  hidden : Map[String, Bool]
  mut kind : Kind
}

///|
pub fn Obj::op_equal(self : Obj, other : Obj) -> Bool {
  self.id == other.id
}

///|
pub(all) struct Closure {
  func : Func
  env : Env
  /// the class a method or constructor is of (super's home), its constructor's own fields
  home : Obj?
  /// a class's constructor: its fields, set on each instance as it is made; whether it derives
  fields : Array[(PropKey, Expr)]
  derived : Bool
  is_class : Bool
}

///|
pub suberror Throw {
  Throw(Value)
}

///|
pub(all) struct Env {
  vars : Map[String, Ref[Value]]
  consts : Map[String, Bool]
  parent : Env?
  /// a function's own scope: its this, its arguments, the class it is of (super), the function itself (new.target)
  mut this_val : Value?
  mut home : Obj?
  mut fn_scope : Bool
}

///|
pub fn Env::new(parent : Env?, fn_scope? : Bool = false) -> Env {
  { vars: {}, consts: {}, parent, this_val: None, home: None, fn_scope }
}

///|
fn Env::lookup(self : Env, name : String) -> Ref[Value]? {
  let mut e : Env? = Some(self)
  while e is Some(x) {
    match x.vars.get(name) {
      Some(r) => return Some(r)
      None => e = x.parent
    }
  }
  None
}

///|
fn Env::put_var(self : Env, name : String, v : Value, is_const? : Bool = false) -> Unit {
  match self.vars.get(name) {
    Some(r) => r.val = v
    None => self.vars[name] = Ref(v)
  }
  if is_const {
    self.consts[name] = true
  }
}

///|
fn Env::is_const(self : Env, name : String) -> Bool {
  let mut e : Env? = Some(self)
  while e is Some(x) {
    if x.vars.contains(name) {
      return x.consts.contains(name)
    }
    e = x.parent
  }
  false
}

///|
/// The nearest function scope's `this`.
fn Env::this_of(self : Env) -> Value {
  let mut e : Env? = Some(self)
  while e is Some(x) {
    if x.this_val is Some(t) {
      return t
    }
    e = x.parent
  }
  Undefined
}

///|
fn Env::home_of(self : Env) -> Obj? {
  let mut e : Env? = Some(self)
  while e is Some(x) {
    if x.home is Some(h) {
      return Some(h)
    }
    e = x.parent
  }
  None
}

///|
/// The var scope: the nearest function's (or the global one).
fn Env::var_scope(self : Env) -> Env {
  let mut e = self
  while !e.fn_scope && e.parent is Some(p) {
    e = p
  }
  e
}

// ── conversions ──────────────────────────────────────────────────────

///|
pub fn Value::truthy(self : Value) -> Bool {
  match self {
    Undefined | Null => false
    B(b) => b
    N(n) => !(n == 0.0 || n.is_nan())
    S(s) => s != ""
    O(_) => true
  }
}

///|
pub fn Value::type_of(self : Value) -> String {
  match self {
    Undefined => "undefined"
    Null => "object"
    B(_) => "boolean"
    N(_) => "number"
    S(_) => "string"
    O(o) =>
      match o.kind {
        Closure(_) | Native(_, _) | Bound(_, _, _) => "function"
        _ => "object"
      }
  }
}

///|
pub fn Value::is_callable(self : Value) -> Bool {
  self.type_of() == "function"
}

///|
/// A string as a number (ToNumber of a string): its trimmed text, hex, Infinity; NaN where it is none.
pub fn string_to_number(s : String) -> Double {
  let t = s.trim(chars=" \t\n\r\u{b}\u{c}\u{a0}\u{feff}").to_string()
  if t == "" {
    return 0.0
  }
  if t.has_prefix("0x") || t.has_prefix("0X") {
    let mut v = 0.0
    for i in 2..<t.length() {
      let d = digit_value(t.code_unit_at(i).to_int())
      if d < 0 || d >= 16 {
        return 0.0 / 0.0
      }
      v = v * 16.0 + d.to_double()
    }
    return v
  }
  match parse_number_text(t) {
    Some(v) => v
    None => 0.0 / 0.0
  }
}

///|
pub fn same_value_zero(a : Value, b : Value) -> Bool {
  match (a, b) {
    (N(x), N(y)) => x == y || (x.is_nan() && y.is_nan())
    _ => strict_equal(a, b)
  }
}

///|
pub fn strict_equal(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Undefined, Undefined) | (Null, Null) => true
    (B(x), B(y)) => x == y
    (N(x), N(y)) => x == y
    (S(x), S(y)) => x == y
    (O(x), O(y)) => x.id == y.id
    _ => false
  }
}

///|
pub fn int32(n : Double) -> Int {
  if n.is_nan() || n.is_inf() {
    return 0
  }
  let t = if n < 0.0 { -(-n).floor() } else { n.floor() }
  let m = t % 4294967296.0
  let u = if m < 0.0 { m + 4294967296.0 } else { m }
  if u >= 2147483648.0 {
    (u - 4294967296.0).to_int()
  } else {
    u.to_int()
  }
}

///|
pub fn uint32(n : Double) -> Double {
  let i = int32(n)
  if i < 0 {
    i.to_double() + 4294967296.0
  } else {
    i.to_double()
  }
}

///|
/// Whether `key` is an array index, and which.
fn index_of_key(key : String) -> Int? {
  let n = key.length()
  if n == 0 || n > 9 {
    return None
  }
  if n > 1 && key.code_unit_at(0).to_int() == '0'.to_int() {
    return None
  }
  let mut v = 0
  for i in 0..<n {
    let c = key.code_unit_at(i).to_int()
    if c < '0'.to_int() || c > '9'.to_int() {
      return None
    }
    v = v * 10 + (c - '0'.to_int())
  }
  Some(v)
}
