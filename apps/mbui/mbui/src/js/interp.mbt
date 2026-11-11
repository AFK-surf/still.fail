// The interpreter: statements and expressions evaluated over environments, as ECMAScript's semantics say for what a
// widget's script uses (hoisting of var and function declarations, block scope, closures, this as called, classes with
// fields, super and extends, destructuring, spread, getters and setters, labelled break and continue, try/finally).

///|
priv enum Flow {
  Normal
  Ret(Value)
  Brk(String?)
  Cont(String?)
}

///|
/// Runs script `src` in the realm's global scope; what it threw (a syntax error as a SyntaxError) raised.
pub fn Realm::run(self : Realm, src : String) -> Value raise Throw {
  let prog = parse_script(src) catch {
    SyntaxError(m) => raise self.error("SyntaxError", m)
  }
  self.steps = 0
  self.hoist(prog, self.global)
  // (the value of the last expression statement: what an attribute's handler compiles to)
  let mut last = Undefined
  for s in prog {
    match s {
      ExprS(e) => last = self.eval(e, self.global)
      _ =>
        match self.exec(s, self.global) {
          Ret(v) => last = v
          _ => ()
        }
    }
  }
  last
}

///|
/// Declarations made before a body runs: functions with their code, var names undefined.
fn Realm::hoist(self : Realm, body : Array[Stmt], env : Env) -> Unit {
  let vs = env.var_scope()
  fn vars(s : Stmt) -> Unit {
    match s {
      Decl("var", ds) => for d in ds { names_of(d.0).each(fn(n) { if !vs.vars.contains(n) { vs.put_var(n, Undefined) } }) }
      If(_, a, b) => {
        vars(a)
        match b {
          Some(x) => vars(x)
          None => ()
        }
      }
      Block(xs) => for x in xs { vars(x) }
      For(init, _, _, body) => {
        match init {
          Some(i) => vars(i)
          None => ()
        }
        vars(body)
      }
      ForInOf("var", p, _, _, body) => {
        names_of(p).each(fn(n) { if !vs.vars.contains(n) { vs.put_var(n, Undefined) } })
        vars(body)
      }
      ForInOf(_, _, _, _, body) | While(_, body) | DoWhile(body, _) | Labeled(_, body) => vars(body)
      Try(a, c, f) => {
        for x in a {
          vars(x)
        }
        match c {
          Some((_, xs)) => for x in xs { vars(x) }
          None => ()
        }
        match f {
          Some(xs) => for x in xs { vars(x) }
          None => ()
        }
      }
      Switch(_, cases) => for c in cases { for x in c.1 { vars(x) } }
      _ => ()
    }
  }

  for s in body {
    vars(s)
  }
  for s in body {
    match s {
      FnDecl(f) => env.put_var(f.name, self.make_fn(f, env))
      _ => ()
    }
  }
}

///|
fn names_of(p : Pat) -> Array[String] {
  let out = []
  fn go(p : Pat) {
    match p {
      PId(n) => out.push(n)
      PObj(ps, rest) => {
        for x in ps {
          go(x.1)
        }
        match rest {
          Some(r) => out.push(r)
          None => ()
        }
      }
      PArr(xs, rest) => {
        for x in xs {
          match x {
            Some((q, _)) => go(q)
            None => ()
          }
        }
        match rest {
          Some(r) => go(r)
          None => ()
        }
      }
      PExpr(_) => ()
    }
  }

  go(p)
  out
}

///|
fn Realm::make_fn(self : Realm, f : Func, env : Env, home? : Obj? = None) -> Value {
  let o = self.new_obj(proto=Some(self.function_proto), kind=Closure({ func: f, env, home, fields: [], derived: false, is_class: false }))
  o.props["name"] = Data(S(f.name))
  o.hidden["name"] = true
  o.props["length"] = Data(N(f.params.length().to_double()))
  o.hidden["length"] = true
  if !f.arrow {
    let proto = self.new_obj()
    proto.props["constructor"] = Data(O(o))
    proto.hidden["constructor"] = true
    o.props["prototype"] = Data(O(proto))
    o.hidden["prototype"] = true
  }
  O(o)
}

///|
fn Realm::block(self : Realm, body : Array[Stmt], env : Env) -> Flow raise Throw {
  let inner = Env::new(Some(env))
  for s in body {
    if s is FnDecl(f) {
      inner.put_var(f.name, self.make_fn(f, inner))
    }
  }
  for s in body {
    match self.exec(s, inner) {
      Normal => ()
      other => return other
    }
  }
  Normal
}

///|
fn Realm::exec(self : Realm, s : Stmt, env : Env) -> Flow raise Throw {
  self.step()
  match s {
    ExprS(e) => {
      self.eval(e, env) |> ignore
      Normal
    }
    Decl(kind, ds) => {
      for d in ds {
        let v = match d.1 {
          Some(e) => self.eval_named(e, env, d.0)
          None => if kind == "var" { continue } else { Undefined }
        }
        self.bind(d.0, v, env, kind)
      }
      Normal
    }
    FnDecl(_) => Normal
    ClassDecl(c) => {
      let v = self.class_value(c, env)
      env.put_var(c.name, v)
      Normal
    }
    Return(e) =>
      Ret(
        match e {
          Some(x) => self.eval(x, env)
          None => Undefined
        },
      )
    If(c, a, b) =>
      if self.eval(c, env).truthy() {
        self.exec_scoped(a, env)
      } else {
        match b {
          Some(x) => self.exec_scoped(x, env)
          None => Normal
        }
      }
    Block(body) => self.block(body, env)
    For(init, cond, update, body) => {
      let labels = self.labels
      self.labels = []
      let loop_env = Env::new(Some(env))
      match init {
        Some(i) => self.exec(i, loop_env) |> ignore
        None => ()
      }
      let lets = match init {
        Some(Decl("let", ds)) => ds.map(fn(d) { names_of(d.0) }).fold(init=[], fn(a, b) { a + b })
        _ => []
      }
      while true {
        match cond {
          Some(c) => if !self.eval(c, loop_env).truthy() { break }
          None => ()
        }
        // each turn its own copy of the let bindings (closures made in it keep that turn's)
        let turn = Env::new(Some(loop_env))
        for n in lets {
          match loop_env.vars.get(n) {
            Some(r) => turn.vars[n] = Ref(r.val)
            None => ()
          }
        }
        let flow = self.exec_scoped(body, turn)
        for n in lets {
          match (turn.vars.get(n), loop_env.vars.get(n)) {
            (Some(t), Some(r)) => r.val = t.val
            _ => ()
          }
        }
        match flow {
          Brk(None) => break
          Brk(Some(l)) if labels.contains(l) => break
          Cont(None) => ()
          Cont(Some(l)) if labels.contains(l) => ()
          Normal => ()
          other => return other
        }
        match update {
          Some(u) => self.eval(u, loop_env) |> ignore
          None => ()
        }
      }
      Normal
    }
    ForInOf(kind, pat, of, value, body) => {
      let labels = self.labels
      self.labels = []
      let v = self.eval(value, env)
      let items = if of { self.iterate(v) } else { self.keys_for_in(v) }
      for item in items {
        let turn = Env::new(Some(env))
        if kind == "" {
          self.assign_pattern(pat, item, turn)
        } else {
          self.bind(pat, item, turn, kind)
        }
        match self.exec_scoped(body, turn) {
          Brk(None) => break
          Brk(Some(l)) if labels.contains(l) => break
          Cont(None) => continue
          Cont(Some(l)) if labels.contains(l) => continue
          Normal => ()
          other => return other
        }
      }
      Normal
    }
    While(c, body) => {
      let labels = self.labels
      self.labels = []
      while self.eval(c, env).truthy() {
        match self.exec_scoped(body, env) {
          Brk(None) => break
          Brk(Some(l)) if labels.contains(l) => break
          Cont(None) => continue
          Cont(Some(l)) if labels.contains(l) => continue
          Normal => ()
          other => return other
        }
      }
      Normal
    }
    DoWhile(body, c) => {
      let labels = self.labels
      self.labels = []
      while true {
        match self.exec_scoped(body, env) {
          Brk(None) => break
          Brk(Some(l)) if labels.contains(l) => break
          Cont(None) => ()
          Cont(Some(l)) if labels.contains(l) => ()
          Normal => ()
          other => return other
        }
        if !self.eval(c, env).truthy() {
          break
        }
      }
      Normal
    }
    Break(l) => Brk(l)
    Continue(l) => Cont(l)
    Throw(e) => raise Throw(self.eval(e, env))
    Try(body, catcher, fin) => {
      let result = try {
        Ok(self.block(body, env))
      } catch {
        Throw(v) => Err(v)
      }
      let after = match (result, catcher) {
        (Err(v), Some((param, cbody))) => {
          let cenv = Env::new(Some(env))
          match param {
            Some(p) => self.bind(p, v, cenv, "let")
            None => ()
          }
          match fin {
            Some(_) => try { Ok(self.block(cbody, cenv)) } catch { Throw(x) => Err(x) }
            None => Ok(self.block(cbody, cenv))
          }
        }
        (r, _) => r
      }
      match fin {
        Some(f) =>
          match self.block(f, env) {
            Normal => ()
            other => return other
          }
        None => ()
      }
      match after {
        Ok(flow) => flow
        Err(v) => raise Throw(v)
      }
    }
    Switch(d, cases) => {
      let v = self.eval(d, env)
      let senv = Env::new(Some(env))
      let mut matched = -1
      for i, c in cases {
        match c.0 {
          Some(t) => if strict_equal(v, self.eval(t, senv)) { matched = i; break }
          None => ()
        }
      }
      if matched < 0 {
        for i, c in cases {
          if c.0 is None {
            matched = i
          }
        }
      }
      if matched < 0 {
        return Normal
      }
      for i in matched..<cases.length() {
        for st in cases[i].1 {
          match self.exec(st, senv) {
            Normal => ()
            Brk(None) => return Normal
            other => return other
          }
        }
      }
      Normal
    }
    Labeled(l, body) => {
      self.labels = [..self.labels, l]
      let flow = self.exec(body, env)
      self.labels = []
      match flow {
        Brk(Some(x)) if x == l => Normal
        Cont(Some(x)) if x == l => Normal
        other => other
      }
    }
    Empty => Normal
  }
}

///|
fn Realm::exec_scoped(self : Realm, s : Stmt, env : Env) -> Flow raise Throw {
  match s {
    Block(body) => self.block(body, env)
    Decl(_, _) | ClassDecl(_) => self.exec(s, Env::new(Some(env)))
    _ => self.exec(s, env)
  }
}

///|
/// What a for-of goes through: an array's elements, a string's characters, a Map's or Set's entries, an iterator's.
pub fn Realm::iterate(self : Realm, v : Value) -> Array[Value] raise Throw {
  match v {
    S(s) => {
      let out = []
      for c in s {
        out.push(S(c.to_string()))
      }
      out
    }
    O(o) =>
      match o.kind {
        Arr(items) => items.copy()
        _ => {
          // an object with values() / an iterator protocol of its own (Map, Set: builtins.mbt)
          let it = self.get(v, "@@items")
          match it {
            O({ kind: Arr(items), .. }) => items.copy()
            _ => {
              let f = self.get(v, "@@iterator")
              if f.is_callable() {
                let iter = self.call(f, v, [])
                let out = []
                let next = self.get(iter, "next")
                while true {
                  let r = self.call(next, iter, [])
                  if self.get(r, "done").truthy() {
                    break
                  }
                  out.push(self.get(r, "value"))
                  if out.length() > 1_000_000 {
                    break
                  }
                }
                out
              } else {
                raise self.error("TypeError", "\{self.to_display(v)} is not iterable")
              }
            }
          }
        }
      }
    _ => raise self.error("TypeError", "\{self.to_display(v)} is not iterable")
  }
}

///|
fn Realm::keys_for_in(self : Realm, v : Value) -> Array[Value] {
  match v {
    O(o) => {
      let out = []
      let seen : Map[String, Bool] = {}
      let mut cur : Obj? = Some(o)
      while cur is Some(c) {
        for k in self.own_keys(c) {
          if !seen.contains(k) {
            seen[k] = true
            out.push(S(k))
          }
        }
        cur = c.proto
      }
      out
    }
    S(s) => Array::makei(s.length(), fn(i) { S(i.to_string()) })
    _ => []
  }
}

///|
/// `v` bound to pattern `p` in `env` as declared (`kind`: var, let, const).
fn Realm::bind(self : Realm, p : Pat, v : Value, env : Env, kind : String) -> Unit raise Throw {
  let target = if kind == "var" { env.var_scope() } else { env }
  match p {
    PId(n) =>
      if kind == "var" {
        match env.lookup(n) {
          Some(r) => r.val = v
          None => target.put_var(n, v)
        }
      } else {
        target.put_var(n, v, is_const=kind == "const")
      }
    _ => self.destructure(p, v, fn(name, x) raise Throw { self.bind(PId(name), x, env, kind) }, env)
  }
}

///|
/// A pattern taken apart, each name it binds given its value by `put`.
fn Realm::destructure(self : Realm, p : Pat, v : Value, put : (String, Value) -> Unit raise Throw, env : Env) -> Unit raise Throw {
  match p {
    PId(n) => put(n, v)
    PExpr(e) => self.assign_to(e, v, env)
    PObj(props, rest) => {
      if v is Undefined || v is Null {
        raise self.error("TypeError", "Cannot destructure '\{self.to_display(v)}'")
      }
      let used = []
      for pr in props {
        let key = match pr.0 {
          KName(k) => k
          KComputed(e) => self.key_of(self.eval(e, env))
        }
        used.push(key)
        let mut x = self.get(v, key)
        if x is Undefined {
          match pr.2 {
            Some(d) => x = self.eval(d, env)
            None => ()
          }
        }
        self.destructure(pr.1, x, put, env)
      }
      match rest {
        Some(r) => {
          let o = self.new_obj()
          match v {
            O(src) => for k in self.own_keys(src) { if !used.contains(k) { o.props[k] = Data(self.get(v, k)) } }
            _ => ()
          }
          put(r, O(o))
        }
        None => ()
      }
    }
    PArr(items, rest) => {
      let all = self.iterate(v)
      for i, it in items {
        match it {
          Some((q, d)) => {
            let mut x = all.get(i).unwrap_or(Undefined)
            if x is Undefined {
              match d {
                Some(e) => x = self.eval(e, env)
                None => ()
              }
            }
            self.destructure(q, x, put, env)
          }
          None => ()
        }
      }
      match rest {
        Some(r) => {
          let tail = if items.length() < all.length() { all[items.length():].to_array() } else { [] }
          self.destructure(r, self.array(tail), put, env)
        }
        None => ()
      }
    }
  }
}

///|
/// An assignment's target given `v`.
fn Realm::assign_pattern(self : Realm, p : Pat, v : Value, env : Env) -> Unit raise Throw {
  self.destructure(p, v, fn(name, x) raise Throw { self.assign_name(name, x, env) }, env)
}

///|
fn Realm::assign_name(self : Realm, name : String, v : Value, env : Env) -> Unit raise Throw {
  match env.lookup(name) {
    Some(r) => {
      if env.is_const(name) {
        raise self.error("TypeError", "Assignment to constant variable.")
      }
      r.val = v
    }
    None => {
      // a name never declared: a global's
      self.global.put_var(name, v)
    }
  }
}

///|
fn Realm::assign_to(self : Realm, target : Expr, v : Value, env : Env) -> Unit raise Throw {
  match target {
    Id(n) => self.assign_name(n, v, env)
    Member(o, k, _, _) => {
      let ov = self.eval(o, env)
      let key = self.key_of(self.eval(k, env))
      self.set(ov, key, v)
    }
    _ => raise self.error("SyntaxError", "Invalid assignment target")
  }
}

///|
/// An expression's value; a function or class given the name of what it is bound to.
fn Realm::eval_named(self : Realm, e : Expr, env : Env, p : Pat) -> Value raise Throw {
  let v = self.eval(e, env)
  match (p, v) {
    (PId(n), O(o)) if (e is Fn(_) || e is Class(_)) =>
      match o.props.get("name") {
        Some(Data(S(""))) => o.props["name"] = Data(S(n))
        _ => ()
      }
    _ => ()
  }
  v
}

///|
fn Realm::args_of(self : Realm, args : Array[(Expr, Bool)], env : Env) -> Array[Value] raise Throw {
  let out = []
  for a in args {
    if a.1 {
      for x in self.iterate(self.eval(a.0, env)) {
        out.push(x)
      }
    } else {
      out.push(self.eval(a.0, env))
    }
  }
  out
}

///|
priv suberror Short {
  Short
}

///|
pub fn Realm::eval(self : Realm, e : Expr, env : Env) -> Value raise Throw {
  match e {
    Chain(inner) =>
      try {
        self.eval_chain(inner, env)
      } catch {
        Short => Undefined
        Throw(v) => raise Throw(v)
        other => raise Throw(S(other.to_string()))
      }
    _ =>
      self.eval_chain(e, env) catch {
        Short => Undefined
        Throw(v) => raise Throw(v)
        other => raise Throw(S(other.to_string()))
      }
  }
}

///|
fn Realm::eval_chain(self : Realm, e : Expr, env : Env) -> Value raise {
  self.step()
  match e {
    Chain(inner) => self.eval(inner, env)
    Num(n) => N(n)
    Str(s) => S(s)
    Bool(b) => B(b)
    Null => Null
    Undef => Undefined
    Tmpl(parts, exprs) => {
      let b = StringBuilder()
      for i, p in parts {
        b.write_string(p)
        if i < exprs.length() {
          b.write_string(self.to_string(self.eval(exprs[i], env)))
        }
      }
      S(b.to_string())
    }
    TaggedTmpl(tag, parts, exprs) => {
      let f = self.eval(tag, env)
      let strings = self.array(parts.map(fn(p) { S(p) }))
      match strings {
        O(o) => o.props["raw"] = Data(self.array(parts.map(fn(p) { S(p) })))
        _ => ()
      }
      let args = [strings]
      for x in exprs {
        args.push(self.eval(x, env))
      }
      self.call(f, Undefined, args)
    }
    RegexLit(src, flags) => self.regexp(src, flags)
    Id("undefined") => Undefined
    Id(n) =>
      match env.lookup(n) {
        Some(r) => r.val
        None =>
          match self.global_obj.props.get(n) {
            Some(Data(v)) => v
            _ => raise self.error("ReferenceError", "\{n} is not defined")
          }
      }
    This => env.this_of()
    Super => raise self.error("SyntaxError", "'super' keyword unexpected here")
    ArrayLit(items) => {
      let out = []
      for it in items {
        match it {
          None => out.push(Undefined)
          Some((x, true)) => for y in self.iterate(self.eval(x, env)) { out.push(y) }
          Some((x, false)) => out.push(self.eval(x, env))
        }
      }
      self.array(out)
    }
    ObjectLit(props) => {
      let o = self.new_obj()
      for p in props {
        match p {
          Spread(x) => {
            let v = self.eval(x, env)
            match v {
              O(src) => for k in self.own_keys(src) { o.props[k] = Data(self.get(v, k)) }
              S(s) => for i in 0..<s.length() { o.props[i.to_string()] = Data(S(s.view(start_offset=i, end_offset=i + 1).to_owned())) }
              _ => ()
            }
          }
          Prop(k, v, kind) => {
            let key = match k {
              KName(n) => n
              KComputed(x) => self.key_of(self.eval(x, env))
            }
            let value = match v {
              Fn(f) => {
                let fv = self.make_fn(f, env, home=Some(o))
                match fv {
                  O(fo) => if f.name == "" { fo.props["name"] = Data(S(key)) }
                  _ => ()
                }
                fv
              }
              _ => self.eval(v, env)
            }
            match kind {
              1 =>
                o.props[key] = match o.props.get(key) {
                  Some(Accessor(_, s)) => Accessor(value, s)
                  _ => Accessor(value, Undefined)
                }
              2 =>
                o.props[key] = match o.props.get(key) {
                  Some(Accessor(g, _)) => Accessor(g, value)
                  _ => Accessor(Undefined, value)
                }
              _ => o.props[key] = Data(value)
            }
          }
        }
      }
      O(o)
    }
    Fn(f) => {
      let v = self.make_fn(f, env)
      // a named function expression sees its own name
      if f.name != "" && !f.arrow {
        let inner = Env::new(Some(env))
        inner.put_var(f.name, v)
        match v {
          O({ kind: Closure(c), .. } as o) => o.kind = Closure({ ..c, env: inner })
          _ => ()
        }
      }
      v
    }
    Class(c) => self.class_value(c, env)
    Member(Super, k, _, _) => {
      let key = self.key_of(self.eval(k, env))
      match env.home_of() {
        Some(h) =>
          match h.proto {
            Some(p) =>
              match self.find_slot(p, key) {
                Some(Data(v)) => v
                Some(Accessor(g, _)) => self.call(g, env.this_of(), [])
                None => Undefined
              }
            None => Undefined
          }
        None => Undefined
      }
    }
    Member(o, k, optional, _) => {
      let ov = self.eval_chain(o, env)
      if optional && (ov is Undefined || ov is Null) {
        raise Short
      }
      let key = self.key_of(self.eval(k, env))
      self.get(ov, key)
    }
    Call(Super, args, _) => {
      // the parent class's constructor on this
      let this = env.this_of()
      match env.home_of() {
        Some(h) =>
          match h.proto {
            Some(parent) => {
              let ctor = self.get(O(parent), "constructor")
              self.construct_into(ctor, this, self.args_of(args, env)) |> ignore
            }
            None => ()
          }
        None => ()
      }
      // the fields of the class whose constructor called super
      self.init_fields_from(env, this)
      Undefined
    }
    Call(callee, args, optional) => {
      let (f, this) = match callee {
        Member(Super, k, _, _) => {
          let key = self.key_of(self.eval(k, env))
          let m = match env.home_of() {
            Some(h) =>
              match h.proto {
                Some(p) => self.get(O(p), key)
                None => Undefined
              }
            None => Undefined
          }
          (m, env.this_of())
        }
        Member(o, k, opt_member, _) => {
          let ov = self.eval_chain(o, env)
          if opt_member && (ov is Undefined || ov is Null) {
            raise Short
          }
          let key = self.key_of(self.eval(k, env))
          (self.get(ov, key), ov)
        }
        _ => (self.eval_chain(callee, env), Undefined)
      }
      if optional && (f is Undefined || f is Null) {
        raise Short
      }
      if !f.is_callable() {
        raise self.error("TypeError", "\{callee_name(callee)} is not a function")
      }
      self.call(f, this, self.args_of(args, env))
    }
    New(callee, args) => {
      let f = self.eval(callee, env)
      self.construct(f, self.args_of(args, env))
    }
    Unary("typeof", Id(n)) =>
      match env.lookup(n) {
        Some(r) => S(r.val.type_of())
        None =>
          match self.global_obj.props.get(n) {
            Some(Data(v)) => S(v.type_of())
            _ => S("undefined")
          }
      }
    Unary("delete", Member(o, k, _, _)) => {
      let ov = self.eval(o, env)
      let key = self.key_of(self.eval(k, env))
      match ov {
        O(obj) => {
          obj.props.remove(key)
          match obj.kind {
            Arr(items) =>
              match index_of_key(key) {
                Some(i) if i < items.length() => items[i] = Undefined
                _ => ()
              }
            _ => ()
          }
        }
        _ => ()
      }
      B(true)
    }
    Unary(op, x) => {
      let v = self.eval(x, env)
      match op {
        "!" => B(!v.truthy())
        "-" => N(-self.to_number(v))
        "+" => N(self.to_number(v))
        "~" => N((int32(self.to_number(v)) ^ -1).to_double())
        "typeof" => S(v.type_of())
        "void" => Undefined
        "delete" => B(true)
        _ => raise self.error("SyntaxError", "unknown operator " + op)
      }
    }
    Update(op, prefix, target) => {
      let old = self.to_number(self.eval(target, env))
      let now = if op == "++" { old + 1.0 } else { old - 1.0 }
      self.assign_to(target, N(now), env)
      N(if prefix { now } else { old })
    }
    Binary(op, a, b) => {
      let x = self.eval(a, env)
      let y = self.eval(b, env)
      self.binary(op, x, y)
    }
    Logical(op, a, b) => {
      let x = self.eval(a, env)
      match op {
        "&&" => if x.truthy() { self.eval(b, env) } else { x }
        "||" => if x.truthy() { x } else { self.eval(b, env) }
        _ => if x is Undefined || x is Null { self.eval(b, env) } else { x }
      }
    }
    Cond(c, a, b) => if self.eval(c, env).truthy() { self.eval(a, env) } else { self.eval(b, env) }
    Assign(op, target, value) =>
      match op {
        "=" => {
          let v = match target {
            PId(_) => self.eval_named(value, env, target)
            _ => self.eval(value, env)
          }
          self.assign_pattern(target, v, env)
          v
        }
        _ => {
          let te = match target {
            PExpr(x) => x
            PId(n) => Id(n)
            _ => raise self.error("SyntaxError", "Invalid assignment target")
          }
          // the target read once: its object and key
          let (get, put) = match te {
            Member(o, k, _, _) => {
              let ov = self.eval(o, env)
              let key = self.key_of(self.eval(k, env))
              (fn() raise Throw { self.get(ov, key) }, fn(v : Value) raise Throw { self.set(ov, key, v) })
            }
            Id(n) => (fn() raise Throw { self.eval(Id(n), env) }, fn(v : Value) raise Throw { self.assign_name(n, v, env) })
            _ => raise self.error("SyntaxError", "Invalid assignment target")
          }
          let old = get()
          let v = match op {
            "&&=" => if old.truthy() { self.eval(value, env) } else { return old }
            "||=" => if old.truthy() { return old } else { self.eval(value, env) }
            "??=" => if old is Undefined || old is Null { self.eval(value, env) } else { return old }
            _ => self.binary(op.view(end_offset=op.length() - 1).to_owned(), old, self.eval(value, env))
          }
          put(v)
          v
        }
      }
    Seq(xs) => {
      let mut last = Undefined
      for x in xs {
        last = self.eval(x, env)
      }
      last
    }
    Await(x) => self.await_value(self.eval(x, env))
  }
}

///|
fn callee_name(e : Expr) -> String {
  match e {
    Id(n) => n
    Member(o, Str(k), _, _) => callee_name(o) + "." + k
    _ => "expression"
  }
}

///|
pub fn Realm::binary(self : Realm, op : String, x : Value, y : Value) -> Value raise Throw {
  match op {
    "+" => {
      let a = self.to_primitive(x)
      let b = self.to_primitive(y)
      if a is S(_) || b is S(_) {
        S(self.to_string(a) + self.to_string(b))
      } else {
        N(self.to_number(a) + self.to_number(b))
      }
    }
    "-" => N(self.to_number(x) - self.to_number(y))
    "*" => N(self.to_number(x) * self.to_number(y))
    "/" => N(self.to_number(x) / self.to_number(y))
    "%" => {
      let a = self.to_number(x)
      let b = self.to_number(y)
      if b == 0.0 || a.is_nan() || b.is_nan() || a.is_inf() {
        N(0.0 / 0.0)
      } else if b.is_inf() {
        N(a)
      } else {
        N(a - b * (if a / b < 0.0 { -(-(a / b)).floor() } else { (a / b).floor() }))
      }
    }
    "**" => N(@dmath.pow(self.to_number(x), self.to_number(y)))
    "==" => B(self.loose_equal(x, y))
    "!=" => B(!self.loose_equal(x, y))
    "===" => B(strict_equal(x, y))
    "!==" => B(!strict_equal(x, y))
    "<" | ">" | "<=" | ">=" => {
      let a = self.to_primitive(x, hint="number")
      let b = self.to_primitive(y, hint="number")
      match (a, b) {
        (S(p), S(q)) =>
          B(
            match op {
              "<" => p < q
              ">" => p > q
              "<=" => p <= q
              _ => p >= q
            },
          )
        _ => {
          let p = self.to_number(a)
          let q = self.to_number(b)
          B(
            match op {
              "<" => p < q
              ">" => p > q
              "<=" => p <= q
              _ => p >= q
            },
          )
        }
      }
    }
    "&" => N((int32(self.to_number(x)) & int32(self.to_number(y))).to_double())
    "|" => N((int32(self.to_number(x)) | int32(self.to_number(y))).to_double())
    "^" => N((int32(self.to_number(x)) ^ int32(self.to_number(y))).to_double())
    "<<" => N((int32(self.to_number(x)) << (int32(self.to_number(y)) & 31)).to_double())
    ">>" => N((int32(self.to_number(x)) >> (int32(self.to_number(y)) & 31)).to_double())
    ">>>" => {
      let a = uint32(self.to_number(x))
      let s = int32(self.to_number(y)) & 31
      N((a / @dmath.pow(2.0, s.to_double())).floor())
    }
    "instanceof" => {
      if !y.is_callable() {
        raise self.error("TypeError", "Right-hand side of 'instanceof' is not callable")
      }
      match x {
        O(o) => {
          let proto = self.get(y, "prototype")
          let mut cur = o.proto
          while cur is Some(c) {
            if proto is O(p) && p.id == c.id {
              return B(true)
            }
            cur = c.proto
          }
          B(false)
        }
        _ => B(false)
      }
    }
    "in" =>
      match y {
        O(o) => B(self.has(o, self.key_of(x)))
        _ => raise self.error("TypeError", "Cannot use 'in' operator")
      }
    _ => raise self.error("SyntaxError", "unknown operator " + op)
  }
}

// ── calls ────────────────────────────────────────────────────────────

///|
/// `f` called with `this` and `args`.
pub fn Realm::call(self : Realm, f : Value, this : Value, args : Array[Value]) -> Value raise Throw {
  match f {
    O(o) =>
      match o.kind {
        Native(_, nf) => nf(this, args, self)
        Bound(target, bthis, bargs) => self.call(target, bthis, bargs + args)
        Closure(c) => {
          if c.is_class {
            raise self.error("TypeError", "Class constructor cannot be invoked without 'new'")
          }
          self.invoke(c, this, args, O(o))
        }
        _ => raise self.error("TypeError", "\{self.to_display(f)} is not a function")
      }
    _ => raise self.error("TypeError", "\{self.to_display(f)} is not a function")
  }
}

///|
fn Realm::invoke(self : Realm, c : Closure, this : Value, args : Array[Value], callee : Value) -> Value raise Throw {
  ignore(callee)
  let f = c.func
  let env = Env::new(Some(c.env), fn_scope=!f.arrow)
  if !f.arrow {
    env.this_val = Some(this)
    env.home = c.home
    env.put_var("arguments", self.array(args))
  }
  for i, p in f.params {
    let mut v = args.get(i).unwrap_or(Undefined)
    if v is Undefined {
      match p.1 {
        Some(d) => v = self.eval(d, env)
        None => ()
      }
    }
    self.bind(p.0, v, env, "let")
  }
  match f.rest {
    Some(r) => {
      let rest = if args.length() > f.params.length() { args[f.params.length():].to_array() } else { [] }
      self.bind(r, self.array(rest), env, "let")
    }
    None => ()
  }
  self.hoist(f.body, env)
  for s in f.body {
    match self.exec(s, env) {
      Ret(v) => return v
      Normal => ()
      _ => ()
    }
  }
  Undefined
}

///|
/// `new f(...args)`.
pub fn Realm::construct(self : Realm, f : Value, args : Array[Value]) -> Value raise Throw {
  match f {
    O(fo) => {
      match fo.kind {
        Native(_, nf) =>
          // a native constructor makes what it makes (it is told it is constructing by `this` being undefined)
          return nf(O(self.new_obj(proto=match self.get(f, "prototype") { O(p) => Some(p); _ => Some(self.object_proto) })), args, self)
        Bound(target, _, bargs) => return self.construct(target, bargs + args)
        Closure(c) if c.func.arrow => raise self.error("TypeError", "\{self.to_display(f)} is not a constructor")
        Closure(_) => ()
        _ => raise self.error("TypeError", "\{self.to_display(f)} is not a constructor")
      }
      let proto = match self.get(f, "prototype") {
        O(p) => Some(p)
        _ => Some(self.object_proto)
      }
      let this = O(self.new_obj(proto~))
      let r = self.construct_into(f, this, args)
      match r {
        O(_) => r
        _ => this
      }
    }
    _ => raise self.error("TypeError", "\{self.to_display(f)} is not a constructor")
  }
}

///|
/// A constructor run on an object already made (the base's, as a derived class's super() runs it), its fields set
/// first where it derives from nothing.
fn Realm::construct_into(self : Realm, f : Value, this : Value, args : Array[Value]) -> Value raise Throw {
  match f {
    O(fo) =>
      match fo.kind {
        Closure(c) => {
          if !c.derived {
            self.init_fields(c, this)
          }
          if c.is_class && c.func.body.is_empty() && c.derived {
            // a derived class without a constructor of its own: its parent's with the same arguments, then its fields
            match c.home {
              Some(h) =>
                match h.proto {
                  Some(parent) => self.construct_into(self.get(O(parent), "constructor"), this, args) |> ignore
                  None => ()
                }
              None => ()
            }
            self.init_fields(c, this)
            return this
          }
          self.invoke(c, this, args, f)
        }
        Native(_, nf) => {
          // a builtin base (Error, Array...): what it makes, its own properties put on this
          let made = nf(this, args, self)
          match (made, this) {
            (O(m), O(t)) if m.id != t.id => {
              m.props.each(fn(k, v) { t.props[k] = v })
              m.hidden.each(fn(k, v) { t.hidden[k] = v })
              if m.kind is Error {
                t.kind = Error
              }
            }
            _ => ()
          }
          this
        }
        _ => this
      }
    _ => this
  }
}

///|
fn Realm::init_fields(self : Realm, c : Closure, this : Value) -> Unit raise Throw {
  if c.fields.is_empty() {
    return
  }
  let env = Env::new(Some(c.env), fn_scope=true)
  env.this_val = Some(this)
  env.home = c.home
  for fd in c.fields {
    let key = match fd.0 {
      KName(k) => k
      KComputed(e) => self.key_of(self.eval(e, env))
    }
    self.set(this, key, self.eval(fd.1, env))
  }
}

///|
/// After super(): the fields of the class whose constructor is running.
fn Realm::init_fields_from(self : Realm, env : Env, this : Value) -> Unit raise Throw {
  match env.home_of() {
    Some(h) =>
      match h.props.get("constructor") {
        Some(Data(O({ kind: Closure(c), .. }))) => self.init_fields(c, this)
        _ => ()
      }
    None => ()
  }
}

///|
fn Realm::class_value(self : Realm, c : ClassDef, env : Env) -> Value raise Throw {
  let parent = match c.extends {
    Some(e) => Some(self.eval(e, env))
    None => None
  }
  let proto_parent = match parent {
    Some(Null) => None
    Some(p) =>
      match self.get(p, "prototype") {
        O(pp) => Some(pp)
        _ => Some(self.object_proto)
      }
    None => Some(self.object_proto)
  }
  let proto = self.new_obj(proto=proto_parent)
  let cenv = Env::new(Some(env))
  let fields = []
  let statics = []
  let ctor_func : Func = match c.ctor {
    Some(f) => { ..f, name: c.name }
    None => { name: c.name, params: [], rest: None, body: [], arrow: false, is_expr: false }
  }
  let ctor = self.new_obj(
    proto=match parent {
      Some(O(p)) => Some(p)
      _ => Some(self.function_proto)
    },
    kind=Closure({ func: ctor_func, env: cenv, home: Some(proto), fields: [], derived: parent is Some(_), is_class: true }),
  )
  if c.name != "" {
    cenv.put_var(c.name, O(ctor))
  }
  ctor.props["prototype"] = Data(O(proto))
  ctor.hidden["prototype"] = true
  ctor.props["name"] = Data(S(c.name))
  ctor.hidden["name"] = true
  proto.props["constructor"] = Data(O(ctor))
  proto.hidden["constructor"] = true
  for m in c.members {
    let (key, value, is_static, kind, is_field) = m
    let target = if is_static { ctor } else { proto }
    if is_field {
      if is_static {
        statics.push((key, value))
      } else {
        fields.push((key, value))
      }
      continue
    }
    let k = match key {
      KName(n) => n
      KComputed(e) => self.key_of(self.eval(e, cenv))
    }
    let fv = match value {
      Fn(f) => self.make_fn(f, cenv, home=Some(target))
      _ => self.eval(value, cenv)
    }
    match kind {
      1 =>
        target.props[k] = match target.props.get(k) {
          Some(Accessor(_, s)) => Accessor(fv, s)
          _ => Accessor(fv, Undefined)
        }
      2 =>
        target.props[k] = match target.props.get(k) {
          Some(Accessor(g, _)) => Accessor(g, fv)
          _ => Accessor(Undefined, fv)
        }
      _ => target.props[k] = Data(fv)
    }
    target.hidden[k] = true
  }
  match ctor.kind {
    Closure(cl) => ctor.kind = Closure({ ..cl, fields })
    _ => ()
  }
  // static fields, this the class
  let senv = Env::new(Some(cenv), fn_scope=true)
  senv.this_val = Some(O(ctor))
  senv.home = Some(ctor)
  for s in statics {
    let k = match s.0 {
      KName(n) => n
      KComputed(e) => self.key_of(self.eval(e, senv))
    }
    ctor.props[k] = Data(self.eval(s.1, senv))
  }
  O(ctor)
}

///|
/// `await`: a value as it is, a promise settled now as what it settled to (the realm's promises settle as their
/// work is done: builtins.mbt), one still waiting a TypeError (the script needs a browser).
fn Realm::await_value(self : Realm, v : Value) -> Value raise Throw {
  match v {
    O(o) =>
      match o.props.get("@@state") {
        Some(Data(S("fulfilled"))) =>
          match o.props.get("@@value") {
            Some(Data(x)) => x
            _ => Undefined
          }
        Some(Data(S("rejected"))) =>
          match o.props.get("@@value") {
            Some(Data(x)) => raise Throw(x)
            _ => raise Throw(Undefined)
          }
        Some(_) => raise self.error("TypeError", "await of a promise that has not settled")
        None => v
      }
    _ => v
  }
}
