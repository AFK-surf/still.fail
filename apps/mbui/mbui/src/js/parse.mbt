// The parser: tokens (lex.mbt) into the syntax tree (ast.mbt), by recursive descent with ECMAScript's precedence,
// semicolons put in where a line ends as ASI says, an arrow's parameters read as the parenthesised expression they
// look like and turned into patterns.

///|
priv struct Parser {
  toks : Array[Token]
  mut i : Int
  mut no_in : Bool
}

///|
/// The script `src`'s statements.
pub fn parse_script(src : String) -> Array[Stmt] raise SyntaxError {
  let p : Parser = { toks: tokenize(src), i: 0, no_in: false }
  let out = []
  while !(p.peek() is EOF) {
    out.push(p.statement())
  }
  out
}

///|
fn Parser::peek(self : Parser) -> Tok {
  self.toks[self.i].tok
}

///|
fn Parser::peek_at(self : Parser, k : Int) -> Tok {
  let j = self.i + k
  if j < self.toks.length() {
    self.toks[j].tok
  } else {
    EOF
  }
}

///|
fn Parser::next(self : Parser) -> Tok {
  let t = self.toks[self.i].tok
  if self.i < self.toks.length() - 1 {
    self.i += 1
  }
  t
}

///|
fn Parser::is_p(self : Parser, p : String) -> Bool {
  self.peek() == Punct(p)
}

///|
fn Parser::is_k(self : Parser, k : String) -> Bool {
  self.peek() == Keyword(k)
}

///|
fn Parser::eat_p(self : Parser, p : String) -> Bool {
  if self.is_p(p) {
    self.i += 1
    true
  } else {
    false
  }
}

///|
fn Parser::eat_k(self : Parser, k : String) -> Bool {
  if self.is_k(k) {
    self.i += 1
    true
  } else {
    false
  }
}

///|
fn Parser::fail(self : Parser, what : String) -> SyntaxError {
  SyntaxError("\{what} at \{self.toks[self.i].pos} (\{self.peek()})")
}

///|
fn Parser::expect_p(self : Parser, p : String) -> Unit raise SyntaxError {
  if !self.eat_p(p) {
    raise self.fail("expected " + p)
  }
}

///|
/// A semicolon, or where ASI puts one: before }, at the end, after a line end.
fn Parser::semi(self : Parser) -> Unit raise SyntaxError {
  if self.eat_p(";") {
    return
  }
  if self.is_p("}") || self.peek() is EOF || self.toks[self.i].nl {
    return
  }
  raise self.fail("expected ;")
}

///|
/// An identifier, or a word that is only a keyword where it is used as one (let, of, get, set, static, async...).
fn Parser::ident(self : Parser) -> String raise SyntaxError {
  match self.next() {
    Ident(s) => s
    Keyword(k) if !reserved.contains(k) => k
    _ => {
      self.i -= 1
      raise self.fail("expected a name")
    }
  }
}

///|
fn Parser::is_ident(self : Parser) -> Bool {
  match self.peek() {
    Ident(_) => true
    Keyword(k) => !reserved.contains(k)
    _ => false
  }
}

///|
fn Parser::statement(self : Parser) -> Stmt raise SyntaxError {
  match self.peek() {
    Punct("{") => Block(self.block())
    Punct(";") => {
      self.i += 1
      Empty
    }
    Keyword("var") | Keyword("const") => {
      let s = self.declaration()
      self.semi()
      s
    }
    Keyword("let") if self.peek_at(1) is Ident(_) || self.peek_at(1) == Punct("[") || self.peek_at(1) == Punct("{") || (self.peek_at(1) is Keyword(k) && !reserved.contains(k)) => {
      let s = self.declaration()
      self.semi()
      s
    }
    Keyword("function") => FnDecl(self.function(false))
    Keyword("async") if self.peek_at(1) == Keyword("function") => {
      self.i += 1
      FnDecl(self.function(false))
    }
    Keyword("class") => ClassDecl(self.class())
    Keyword("return") => {
      self.i += 1
      if self.is_p(";") || self.is_p("}") || self.peek() is EOF || self.toks[self.i].nl {
        self.semi()
        Return(None)
      } else {
        let e = self.expression()
        self.semi()
        Return(Some(e))
      }
    }
    Keyword("if") => {
      self.i += 1
      self.expect_p("(")
      let cond = self.expression()
      self.expect_p(")")
      let then = self.statement()
      let els = if self.eat_k("else") { Some(self.statement()) } else { None }
      If(cond, then, els)
    }
    Keyword("for") => self.for_statement()
    Keyword("while") => {
      self.i += 1
      self.expect_p("(")
      let cond = self.expression()
      self.expect_p(")")
      While(cond, self.statement())
    }
    Keyword("do") => {
      self.i += 1
      let body = self.statement()
      if !self.eat_k("while") {
        raise self.fail("expected while")
      }
      self.expect_p("(")
      let cond = self.expression()
      self.expect_p(")")
      self.eat_p(";") |> ignore
      DoWhile(body, cond)
    }
    Keyword("break") | Keyword("continue") => {
      let k = self.next()
      let label = if self.is_ident() && !self.toks[self.i].nl { Some(self.ident()) } else { None }
      self.semi()
      if k == Keyword("break") {
        Break(label)
      } else {
        Continue(label)
      }
    }
    Keyword("throw") => {
      self.i += 1
      let e = self.expression()
      self.semi()
      Throw(e)
    }
    Keyword("try") => {
      self.i += 1
      let body = self.block()
      let catcher = if self.eat_k("catch") {
        let param = if self.eat_p("(") {
          let pat = self.binding_pattern()
          self.expect_p(")")
          Some(pat)
        } else {
          None
        }
        Some((param, self.block()))
      } else {
        None
      }
      let fin = if self.eat_k("finally") { Some(self.block()) } else { None }
      Try(body, catcher, fin)
    }
    Keyword("switch") => {
      self.i += 1
      self.expect_p("(")
      let d = self.expression()
      self.expect_p(")")
      self.expect_p("{")
      let cases = []
      while !self.eat_p("}") {
        let cond = if self.eat_k("default") {
          None
        } else if self.eat_k("case") {
          Some(self.expression())
        } else {
          raise self.fail("expected case")
        }
        self.expect_p(":")
        let body = []
        while !self.is_k("case") && !self.is_k("default") && !self.is_p("}") {
          body.push(self.statement())
        }
        cases.push((cond, body))
      }
      Switch(d, cases)
    }
    Ident(name) if self.peek_at(1) == Punct(":") => {
      self.i += 2
      Labeled(name, self.statement())
    }
    Keyword("import") | Keyword("export") => raise self.fail("modules are not read")
    _ => {
      let e = self.expression()
      self.semi()
      ExprS(e)
    }
  }
}

///|
fn Parser::block(self : Parser) -> Array[Stmt] raise SyntaxError {
  self.expect_p("{")
  let out = []
  while !self.eat_p("}") {
    if self.peek() is EOF {
      raise self.fail("unclosed block")
    }
    out.push(self.statement())
  }
  out
}

///|
fn Parser::declaration(self : Parser) -> Stmt raise SyntaxError {
  let kind = match self.next() {
    Keyword(k) => k
    _ => "var"
  }
  let decls = []
  while true {
    let pat = self.binding_pattern()
    let init = if self.eat_p("=") { Some(self.assignment()) } else { None }
    decls.push((pat, init))
    if !self.eat_p(",") {
      break
    }
  }
  Decl(kind, decls)
}

///|
fn Parser::for_statement(self : Parser) -> Stmt raise SyntaxError {
  self.i += 1
  self.eat_k("await") |> ignore
  self.expect_p("(")
  // for (decl of/in ...) or for (target of/in ...)
  let kind = match self.peek() {
    Keyword("var") | Keyword("let") | Keyword("const") =>
      match self.peek() {
        Keyword(k) => k
        _ => ""
      }
    _ => ""
  }
  if kind != "" {
    let save = self.i
    self.i += 1
    let pat = self.binding_pattern()
    if self.is_k("of") || self.is_k("in") {
      let of = self.next() == Keyword("of")
      let v = if of { self.assignment() } else { self.expression() }
      self.expect_p(")")
      return ForInOf(kind, pat, of, v, self.statement())
    }
    self.i = save
  }
  let init = if self.is_p(";") {
    None
  } else if kind != "" {
    self.no_in = true
    let d = self.declaration()
    self.no_in = false
    Some(d)
  } else {
    self.no_in = true
    let e = self.expression()
    self.no_in = false
    if self.is_k("of") || self.is_k("in") {
      let of = self.next() == Keyword("of")
      let v = if of { self.assignment() } else { self.expression() }
      self.expect_p(")")
      return ForInOf("", to_pattern(e), of, v, self.statement())
    }
    Some(ExprS(e))
  }
  self.expect_p(";")
  let cond = if self.is_p(";") { None } else { Some(self.expression()) }
  self.expect_p(";")
  let update = if self.is_p(")") { None } else { Some(self.expression()) }
  self.expect_p(")")
  For(init, cond, update, self.statement())
}

///|
fn Parser::binding_pattern(self : Parser) -> Pat raise SyntaxError {
  if self.is_p("[") || self.is_p("{") {
    to_pattern(self.primary())
  } else {
    PId(self.ident())
  }
}

///|
/// An expression read where a pattern may be (an assignment's target, an arrow's parameters) as that pattern.
fn to_pattern(e : Expr) -> Pat raise SyntaxError {
  match e {
    Id(n) => PId(n)
    Member(_, _, _, _) => PExpr(e)
    ArrayLit(items) => {
      let out = []
      let mut rest = None
      for it in items {
        match it {
          None => out.push(None)
          Some((x, true)) => rest = Some(to_pattern(x))
          Some((Assign("=", p, d), false)) => out.push(Some((p, Some(d))))
          Some((x, false)) => out.push(Some((to_pattern(x), None)))
        }
      }
      PArr(out, rest)
    }
    ObjectLit(props) => {
      let out = []
      let mut rest = None
      for p in props {
        match p {
          Spread(Id(n)) => rest = Some(n)
          Prop(k, Assign("=", pat, d), 0) => out.push((k, pat, Some(d)))
          Prop(k, v, 0) => out.push((k, to_pattern(v), None))
          _ => raise SyntaxError("not a pattern")
        }
      }
      PObj(out, rest)
    }
    Assign("=", p, _) => p
    _ => raise SyntaxError("not a pattern")
  }
}

///|
fn Parser::function(self : Parser, is_expr : Bool) -> Func raise SyntaxError {
  ignore(is_expr)
  self.i += 1
  self.eat_p("*") |> ignore
  let name = if self.is_ident() { self.ident() } else { "" }
  let (params, rest) = self.params()
  let body = self.block()
  { name, params, rest, body, arrow: false, is_expr: false }
}

///|
fn Parser::params(self : Parser) -> (Array[(Pat, Expr?)], Pat?) raise SyntaxError {
  self.expect_p("(")
  let params = []
  let mut rest = None
  while !self.eat_p(")") {
    if self.eat_p("...") {
      rest = Some(self.binding_pattern())
    } else {
      let p = self.binding_pattern()
      let d = if self.eat_p("=") { Some(self.assignment()) } else { None }
      params.push((p, d))
    }
    if !self.is_p(")") {
      self.expect_p(",")
    }
  }
  (params, rest)
}

///|
fn Parser::class(self : Parser) -> ClassDef raise SyntaxError {
  self.i += 1
  let name = if self.is_ident() { self.ident() } else { "" }
  let extends = if self.eat_k("extends") { Some(self.left_hand()) } else { None }
  self.expect_p("{")
  let mut ctor = None
  let members = []
  while !self.eat_p("}") {
    if self.eat_p(";") {
      continue
    }
    let mut is_static = false
    if self.is_k("static") && self.peek_at(1) != Punct("(") && self.peek_at(1) != Punct("=") {
      self.i += 1
      is_static = true
    }
    self.eat_k("async") |> ignore
    self.eat_p("*") |> ignore
    let mut kind = 0
    if (self.is_k("get") || self.is_k("set")) && self.peek_at(1) != Punct("(") && self.peek_at(1) != Punct("=") && self.peek_at(1) != Punct(";") {
      kind = if self.next() == Keyword("get") { 1 } else { 2 }
    }
    self.eat_p("#") |> ignore
    let key = self.prop_key()
    if self.is_p("(") {
      let (params, rest) = self.params()
      let body = self.block()
      let f : Func = { name: "", params, rest, body, arrow: false, is_expr: false }
      if key is KName("constructor") && !is_static {
        ctor = Some(f)
      } else {
        members.push((key, Fn(f), is_static, kind, false))
      }
    } else {
      let v = if self.eat_p("=") { self.assignment() } else { Undef }
      self.semi()
      members.push((key, v, is_static, 0, true))
    }
  }
  { name, extends, ctor, members }
}

///|
fn Parser::prop_key(self : Parser) -> PropKey raise SyntaxError {
  match self.next() {
    Ident(s) | Keyword(s) | StrLit(s) => KName(s)
    NumLit(n) => KName(number_to_string(n))
    Punct("[") => {
      let e = self.assignment()
      self.expect_p("]")
      KComputed(e)
    }
    _ => {
      self.i -= 1
      raise self.fail("expected a property name")
    }
  }
}

///|
fn Parser::expression(self : Parser) -> Expr raise SyntaxError {
  let first = self.assignment()
  if !self.is_p(",") {
    return first
  }
  let all = [first]
  while self.eat_p(",") {
    all.push(self.assignment())
  }
  Seq(all)
}

///|
/// Whether the tokens from here are an arrow function's head (a name then =>, or parentheses then =>).
fn Parser::arrow_ahead(self : Parser) -> Bool {
  if self.is_ident() && self.peek_at(1) == Punct("=>") {
    return true
  }
  if !self.is_p("(") {
    return false
  }
  let mut depth = 0
  let mut j = self.i
  while j < self.toks.length() {
    match self.toks[j].tok {
      Punct("(") | Punct("[") | Punct("{") => depth += 1
      Punct(")") | Punct("]") | Punct("}") => {
        depth -= 1
        if depth == 0 {
          return j + 1 < self.toks.length() && self.toks[j + 1].tok == Punct("=>") && !self.toks[j + 1].nl
        }
      }
      EOF => return false
      _ => ()
    }
    j += 1
  }
  false
}

///|
fn Parser::assignment(self : Parser) -> Expr raise SyntaxError {
  // async arrows
  if self.is_k("async") && !self.toks[self.i + 1].nl {
    let save = self.i
    self.i += 1
    if self.arrow_ahead() {
      return self.arrow()
    }
    self.i = save
  }
  if self.arrow_ahead() {
    return self.arrow()
  }
  if self.is_k("yield") {
    raise self.fail("generators are not read")
  }
  let left = self.conditional()
  match self.peek() {
    Punct("=") | Punct("+=") | Punct("-=") | Punct("*=") | Punct("/=") | Punct("%=") | Punct("**=") | Punct("<<=") | Punct(">>=") | Punct(">>>=") | Punct("&=") | Punct("|=") | Punct("^=") | Punct("&&=") | Punct("||=") | Punct("??=") => {
      let op = match self.next() {
        Punct(o) => o
        _ => "="
      }
      let target = if op == "=" { to_pattern(left) } else { PExpr(left) }
      Assign(op, target, self.assignment())
    }
    _ => left
  }
}

///|
fn Parser::arrow(self : Parser) -> Expr raise SyntaxError {
  let (params, rest) = if self.is_ident() {
    ([(PId(self.ident()), None)], None)
  } else {
    self.params()
  }
  self.expect_p("=>")
  if self.is_p("{") {
    let body = self.block()
    Fn({ name: "", params, rest, body, arrow: true, is_expr: false })
  } else {
    let save = self.no_in
    self.no_in = false
    let e = self.assignment()
    self.no_in = save
    Fn({ name: "", params, rest, body: [Return(Some(e))], arrow: true, is_expr: true })
  }
}

///|
fn Parser::conditional(self : Parser) -> Expr raise SyntaxError {
  let cond = self.binary(0)
  if !self.eat_p("?") {
    return cond
  }
  let save = self.no_in
  self.no_in = false
  let a = self.assignment()
  self.no_in = save
  self.expect_p(":")
  let b = self.assignment()
  Cond(cond, a, b)
}

///|
fn precedence(t : Tok, no_in : Bool) -> Int {
  match t {
    Punct("??") => 1
    Punct("||") => 2
    Punct("&&") => 3
    Punct("|") => 4
    Punct("^") => 5
    Punct("&") => 6
    Punct("==") | Punct("!=") | Punct("===") | Punct("!==") => 7
    Punct("<") | Punct(">") | Punct("<=") | Punct(">=") | Keyword("instanceof") => 8
    Keyword("in") => if no_in { -1 } else { 8 }
    Punct("<<") | Punct(">>") | Punct(">>>") => 9
    Punct("+") | Punct("-") => 10
    Punct("*") | Punct("/") | Punct("%") => 11
    Punct("**") => 12
    _ => -1
  }
}

///|
fn Parser::binary(self : Parser, min : Int) -> Expr raise SyntaxError {
  let mut left = self.unary()
  while true {
    let t = self.peek()
    let p = precedence(t, self.no_in)
    if p < 0 || p <= min && !(p == 12 && min == 12) {
      break
    }
    if p <= min {
      break
    }
    self.i += 1
    let op = match t {
      Punct(o) | Keyword(o) => o
      _ => ""
    }
    // ** is right-associative
    let right = if op == "**" { self.binary(p - 1) } else { self.binary(p) }
    left = if op == "&&" || op == "||" || op == "??" { Logical(op, left, right) } else { Binary(op, left, right) }
  }
  left
}

///|
fn Parser::unary(self : Parser) -> Expr raise SyntaxError {
  match self.peek() {
    Punct("!") | Punct("-") | Punct("+") | Punct("~") | Keyword("typeof") | Keyword("void") | Keyword("delete") => {
      let op = match self.next() {
        Punct(o) | Keyword(o) => o
        _ => ""
      }
      Unary(op, self.unary())
    }
    Punct("++") | Punct("--") => {
      let op = match self.next() {
        Punct(o) => o
        _ => ""
      }
      Update(op, true, self.unary())
    }
    Keyword("await") => {
      self.i += 1
      Await(self.unary())
    }
    _ => {
      let e = self.postfix()
      if self.is_p("**") {
        // (handled by binary)
        e
      } else {
        e
      }
    }
  }
}

///|
fn Parser::postfix(self : Parser) -> Expr raise SyntaxError {
  let e = self.left_hand()
  if (self.is_p("++") || self.is_p("--")) && !self.toks[self.i].nl {
    let op = match self.next() {
      Punct(o) => o
      _ => ""
    }
    return Update(op, false, e)
  }
  e
}

///|
fn Parser::args(self : Parser) -> Array[(Expr, Bool)] raise SyntaxError {
  self.expect_p("(")
  let out = []
  while !self.eat_p(")") {
    if self.eat_p("...") {
      out.push((self.assignment(), true))
    } else {
      out.push((self.assignment(), false))
    }
    if !self.is_p(")") {
      self.expect_p(",")
    }
  }
  out
}

///|
fn Parser::left_hand(self : Parser) -> Expr raise SyntaxError {
  let mut e = if self.is_k("new") {
    self.i += 1
    if self.eat_p(".") {
      // new.target
      self.ident() |> ignore
      Undef
    } else {
      let callee = self.member_only()
      let args = if self.is_p("(") { self.args() } else { [] }
      New(callee, args)
    }
  } else {
    self.primary()
  }
  let mut chained = false
  while true {
    match self.peek() {
      Punct(".") => {
        self.i += 1
        self.eat_p("#") |> ignore
        let name = match self.next() {
          Ident(s) | Keyword(s) => s
          _ => raise self.fail("expected a property")
        }
        e = Member(e, Str(name), false, false)
      }
      Punct("?.") => {
        self.i += 1
        chained = true
        if self.is_p("(") {
          e = Call(e, self.args(), true)
        } else if self.eat_p("[") {
          let k = self.expression()
          self.expect_p("]")
          e = Member(e, k, true, true)
        } else {
          let name = match self.next() {
            Ident(s) | Keyword(s) => s
            _ => raise self.fail("expected a property")
          }
          e = Member(e, Str(name), true, false)
        }
      }
      Punct("[") => {
        self.i += 1
        let k = self.expression()
        self.expect_p("]")
        e = Member(e, k, false, true)
      }
      Punct("(") => e = Call(e, self.args(), false)
      Template(parts, exprs) => {
        self.i += 1
        e = TaggedTmpl(e, parts, self.template_exprs(exprs))
      }
      _ => break
    }
  }
  if chained {
    Chain(e)
  } else {
    e
  }
}

///|
/// What `new` is applied to: a member expression without a call.
fn Parser::member_only(self : Parser) -> Expr raise SyntaxError {
  let mut e = if self.is_k("new") {
    self.i += 1
    let c = self.member_only()
    let args = if self.is_p("(") { self.args() } else { [] }
    New(c, args)
  } else {
    self.primary()
  }
  while true {
    if self.eat_p(".") {
      let name = match self.next() {
        Ident(s) | Keyword(s) => s
        _ => raise self.fail("expected a property")
      }
      e = Member(e, Str(name), false, false)
    } else if self.eat_p("[") {
      let k = self.expression()
      self.expect_p("]")
      e = Member(e, k, false, true)
    } else {
      break
    }
  }
  e
}

///|
fn Parser::template_exprs(self : Parser, srcs : Array[String]) -> Array[Expr] raise SyntaxError {
  ignore(self)
  srcs.map(fn(src) raise SyntaxError {
    let p : Parser = { toks: tokenize(src), i: 0, no_in: false }
    p.expression()
  })
}

///|
fn Parser::primary(self : Parser) -> Expr raise SyntaxError {
  match self.next() {
    NumLit(n) => Num(n)
    StrLit(s) => Str(s)
    Template(parts, exprs) => Tmpl(parts, self.template_exprs(exprs))
    Regex(src, flags) => RegexLit(src, flags)
    Ident(n) => Id(n)
    Keyword("this") => This
    Keyword("super") => Super
    Keyword("null") => Null
    Keyword("true") => Bool(true)
    Keyword("false") => Bool(false)
    Keyword("function") => {
      self.i -= 1
      Fn(self.function(true))
    }
    Keyword("async") if self.is_k("function") => Fn(self.function(true))
    Keyword("class") => {
      self.i -= 1
      Class(self.class())
    }
    Keyword(k) if !reserved.contains(k) => Id(k)
    Punct("(") => {
      let save = self.no_in
      self.no_in = false
      let e = self.expression()
      self.no_in = save
      self.expect_p(")")
      e
    }
    Punct("[") => {
      let items = []
      while !self.eat_p("]") {
        if self.is_p(",") {
          self.i += 1
          items.push(None)
          continue
        }
        if self.eat_p("...") {
          items.push(Some((self.assignment(), true)))
        } else {
          items.push(Some((self.assignment(), false)))
        }
        if !self.is_p("]") {
          self.expect_p(",")
        }
      }
      ArrayLit(items)
    }
    Punct("{") => {
      let props = []
      while !self.eat_p("}") {
        if self.eat_p("...") {
          props.push(Spread(self.assignment()))
        } else {
          self.eat_k("async") |> ignore
          self.eat_p("*") |> ignore
          let mut kind = 0
          if (self.is_k("get") || self.is_k("set")) && !(self.peek_at(1) == Punct(",") || self.peek_at(1) == Punct(":") || self.peek_at(1) == Punct("(") || self.peek_at(1) == Punct("}")) {
            kind = if self.next() == Keyword("get") { 1 } else { 2 }
          }
          let shorthand = match self.peek() {
            Ident(n) => Some(n)
            Keyword(k) if !reserved.contains(k) => Some(k)
            _ => None
          }
          let key = self.prop_key()
          if self.is_p("(") {
            let (params, rest) = self.params()
            let body = self.block()
            props.push(Prop(key, Fn({ name: "", params, rest, body, arrow: false, is_expr: false }), kind))
          } else if self.eat_p(":") {
            props.push(Prop(key, self.assignment(), 0))
          } else {
            match shorthand {
              Some(n) =>
                if self.eat_p("=") {
                  // a pattern's default ({a = 1} = o)
                  props.push(Prop(key, Assign("=", PId(n), self.assignment()), 0))
                } else {
                  props.push(Prop(key, Id(n), 0))
                }
              None => raise self.fail("expected :")
            }
          }
        }
        if !self.is_p("}") {
          self.expect_p(",")
        }
      }
      ObjectLit(props)
    }
    _ => {
      self.i -= 1
      raise self.fail("unexpected token")
    }
  }
}
