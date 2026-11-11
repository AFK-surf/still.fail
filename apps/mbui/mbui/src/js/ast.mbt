// A script's syntax tree: the statements and expressions of the ECMAScript a widget is written in (functions, arrows,
// classes, let/const and destructuring, template literals, spread, optional chaining), as the parser reads them.

///|
pub(all) enum Pat {
  PId(String)
  /// properties (key, the pattern it binds, its default), the rest's name
  PObj(Array[(PropKey, Pat, Expr?)], String?)
  /// elements (None: a hole), each with its default, the rest
  PArr(Array[(Pat, Expr?)?], Pat?)
  /// a target that is not a name (in an assignment: a member)
  PExpr(Expr)
}

///|
pub(all) enum PropKey {
  KName(String)
  KComputed(Expr)
}

///|
pub(all) struct Func {
  name : String
  params : Array[(Pat, Expr?)]
  rest : Pat?
  body : Array[Stmt]
  /// an arrow (its this and arguments its holder's)
  arrow : Bool
  /// an arrow whose body is one expression (body is its return)
  is_expr : Bool
}

///|
pub(all) enum PropDef {
  /// key, value; whether it is a getter, a setter, or a plain property
  Prop(PropKey, Expr, Int)
  Spread(Expr)
}

///|
pub(all) struct ClassDef {
  name : String
  extends : Expr?
  ctor : Func?
  /// methods and fields: key, value (a function for a method), static, kind (0 method/field, 1 getter, 2 setter),
  /// whether it is a field
  members : Array[(PropKey, Expr, Bool, Int, Bool)]
}

///|
pub(all) enum Expr {
  Num(Double)
  Str(String)
  Tmpl(Array[String], Array[Expr])
  TaggedTmpl(Expr, Array[String], Array[Expr])
  RegexLit(String, String)
  Id(String)
  This
  Super
  Undef
  Null
  Bool(Bool)
  /// elements (None a hole; a spread marked)
  ArrayLit(Array[(Expr, Bool)?])
  ObjectLit(Array[PropDef])
  Fn(Func)
  Class(ClassDef)
  /// object, property, optional (?.), computed
  Member(Expr, Expr, Bool, Bool)
  /// callee, arguments (spread marked), optional call
  Call(Expr, Array[(Expr, Bool)], Bool)
  New(Expr, Array[(Expr, Bool)])
  Unary(String, Expr)
  /// ++/--: the op, prefix, target
  Update(String, Bool, Expr)
  Binary(String, Expr, Expr)
  Logical(String, Expr, Expr)
  Cond(Expr, Expr, Expr)
  /// op (=, +=...), target, value
  Assign(String, Pat, Expr)
  Seq(Array[Expr])
  /// the end of an optional chain: what short-circuits stops here
  Chain(Expr)
  Await(Expr)
}

///|
pub(all) enum Stmt {
  ExprS(Expr)
  /// kind (var, let, const), each binding and its value
  Decl(String, Array[(Pat, Expr?)])
  FnDecl(Func)
  ClassDecl(ClassDef)
  Return(Expr?)
  If(Expr, Stmt, Stmt?)
  Block(Array[Stmt])
  /// init, test, update, body
  For(Stmt?, Expr?, Expr?, Stmt)
  /// kind (var/let/const, "" an existing target), the target, of (true) or in, the value, body
  ForInOf(String, Pat, Bool, Expr, Stmt)
  While(Expr, Stmt)
  DoWhile(Stmt, Expr)
  Break(String?)
  Continue(String?)
  Throw(Expr)
  /// body, catch's binding and body, finally
  Try(Array[Stmt], (Pat?, Array[Stmt])?, Array[Stmt]?)
  /// discriminant, cases (test None: default) and their statements
  Switch(Expr, Array[(Expr?, Array[Stmt])])
  Labeled(String, Stmt)
  Empty
}
