// The native host's calls (`extern "C"` declarations) made Wasm's, for a program of an app run in classic Wasm by a
// native shell that links the host as it is (the user, 2026-11-03: no C compiled for an app in development):
//
//  wasmhost gen THUNKS.c FILE.mbt… beside each FILE, its Wasm side: each call the
//                                         same function, an import of the shell's ("mbhost", its C name); and
//  THUNKS.c, the shell's side: each import read off the Wasm program's memory
//                                         and made the C call the native program makes
//  wasmhost check THUNKS.c FILE.mbt… the Wasm sides as they are made, nothing written: what differs said, exit 1
//
// Classic Wasm's imports take numbers and function references alone. What is not a number crosses as where it lies in
// the program's memory (mbui/wasmrt's *_addr): there it is laid out as the native program has it, [rc][length] and
// then what it holds, so the shell gives the C host that very place (a borrowed argument) or a copy made in the native
// heap (an owned one, which the C side lets go of itself). A string or bytes the C side answers is kept by the shell,
// its length answered; the program then makes one that long and has the shell copy it in (wasmrt's take_*). A function
// the C side is given to call later (a FuncRef) is the program's own: the shell keeps it and gives the C side a
// function of its own, a trampoline a parameter, that calls it with what it is called with (a string made in the
// program's memory by its export mbw_string).

///|
priv struct Param {
  name : String
  ty : String
}

///|
priv struct Decl {
  name : String
  params : Array[Param]
  ret : String
  sym : String
  borrowed : Array[String]
}

///|
fn[T] fail(why : String) -> T {
  @sys.eprintln("wasmhost: " + why)
  @sys.exit(2)
  panic()
}

///|
fn trim(s : String) -> String {
  s.trim(chars=" \t\r\n").to_owned()
}

///|
/// `s` cut at the commas outside any brackets or parentheses.
fn split_top(s : String) -> Array[String] {
  let out : Array[String] = []
  let cur = StringBuilder()
  let mut depth = 0
  for c in s {
    if c == '(' || c == '[' {
      depth += 1
    } else if c == ')' || c == ']' {
      depth -= 1
    }
    if c == ',' && depth == 0 {
      out.push(trim(cur.to_string()))
      cur.reset()
    } else {
      cur.write_char(c)
    }
  }
  let last = trim(cur.to_string())
  if last != "" {
    out.push(last)
  }
  out
}

///|
/// A file's text: as it is, or a declaration.
priv enum Piece {
  Text(String)
  Ext(Decl)
}

///|
/// The declarations of `text`, in their order.
fn decls(text : String) -> Array[Decl] {
  pieces(text).filter_map(fn(p) {
    match p {
      Ext(d) => Some(d)
      Text(_) => None
    }
  })
}

///|
/// `text` cut into its lines and its declarations (a declaration's #borrow line its own).
fn pieces(text : String) -> Array[Piece] {
  let out : Array[Piece] = []
  let lines = text.split("\n").map(fn(l) { l.to_owned() }).to_array()
  let mut i = 0
  while i < lines.length() {
    let line = trim(lines[i])
    let mut borrowed : Array[String] = []
    if line.has_prefix("#borrow(") && i + 1 < lines.length() &&
      trim(lines[i + 1]).has_prefix("extern \"C\" fn ") {
      let inner = line.exact_view(start=8, end=line.length() - 1).to_owned()
      borrowed = split_top(inner)
      i += 1
    } else if !line.has_prefix("extern \"C\" fn ") {
      out.push(Text(lines[i]))
      i += 1
      continue
    }
    // the whole declaration, to its `= "sym"`
    let whole = StringBuilder()
    while i < lines.length() {
      whole.write_string(trim(lines[i]))
      whole.write_char(' ')
      if lines[i].contains("= \"") {
        break
      }
      i += 1
    }
    i += 1
    let d = whole.to_string()
    let rest = d.exact_view(start="extern \"C\" fn ".length()).to_owned()
    guard rest.find("(") is Some(open) else { fail("no parameters: \{d}") }
    let name = trim(rest.exact_view(end=open).to_owned())
    // the parameters' closing parenthesis
    let mut depth = 0
    let mut close = -1
    let cs = rest.to_array()
    for k in open..<cs.length() {
      if cs[k] == '(' {
        depth += 1
      } else if cs[k] == ')' {
        depth -= 1
        if depth == 0 {
          close = k
          break
        }
      }
    }
    guard close > 0 else { fail("unclosed parameters: \{d}") }
    let params = split_top(rest.exact_view(start=open + 1, end=close).to_owned()).map(fn(p) {
      guard p.find(":") is Some(c) else { fail("a parameter without a type: \{d}") }
      { name: trim(p.exact_view(end=c).to_owned()), ty: trim(p.exact_view(start=c + 1).to_owned()) }
    })
    let after = rest.exact_view(start=close + 1).to_owned()
    guard after.find("= \"") is Some(eq) else { fail("no C name: \{d}") }
    let head = trim(after.exact_view(end=eq).to_owned())
    let ret = if head.has_prefix("->") { trim(head.exact_view(start=2).to_owned()) } else { "Unit" }
    let tail = after.exact_view(start=eq + 3).to_owned()
    guard tail.find("\"") is Some(q) else { fail("unclosed C name: \{d}") }
    out.push(Ext({ name, params, ret, sym: tail.exact_view(end=q).to_owned(), borrowed }))
  }
  out
}

///|
fn is_scalar(ty : String) -> Bool {
  ty == "Int" || ty == "Double" || ty == "Unit" || ty == "Bool" || ty == "Int64" || ty == "UInt" || ty == "Byte"
}

///|
fn is_func(ty : String) -> Bool {
  ty.has_prefix("FuncRef[")
}

///|
/// What mbui/wasmrt gives a value of `ty`'s place by.
fn addr_of(ty : String) -> String {
  match ty {
    "String" => "string_addr"
    "Bytes" => "bytes_addr"
    "FixedArray[Double]" => "doubles_addr"
    "FixedArray[Byte]" => "byte_array_addr"
    "FixedArray[Int]" => "ints_addr"
    _ => fail("no Wasm way for \{ty}")
  }
}

///|
/// A function reference the shell can take as it is: one of numbers alone.
fn plain_func(ty : String) -> Bool {
  let (ps, r) = func_sig(ty)
  is_scalar(r) && ps.iter().all(is_scalar)
}

///|
fn plain(d : Decl) -> Bool {
  is_scalar(d.ret) && d.params.iter().all(fn(p) { is_scalar(p.ty) || (is_func(p.ty) && plain_func(p.ty)) })
}

///|
/// A function reference of strings or bytes as the shell takes it: of numbers, a string or bytes where it lies.
fn func_plain(ty : String) -> String {
  let (ps, r) = func_sig(ty)
  let ps = ps.map(fn(t) { if is_scalar(t) { t } else { "Int" } })
  "FuncRef[(\{ps.join(", ")}) -> \{r}]"
}

///|
fn moon_params(d : Decl) -> String {
  d.params.map(fn(p) { "\{p.name} : \{p.ty}" }).join(", ")
}

///|
fn moon_ret(ty : String) -> String {
  if ty == "Unit" {
    ""
  } else {
    " -> \{ty}"
  }
}

///|
/// The Wasm side of a file: the file as it is, each declaration the shell's import.
fn moon_file(from : String, ps : Array[Piece]) -> String {
  let out = StringBuilder()
  out.write_string(
    "// Generated by mbui's scripts/wasmhost from \{from}: the file on classic Wasm, its C calls the native shell's\n" +
    "// imports (mbui/tools/wasmhost/main.mbt says how). Not to be edited: change \{from} and run scripts/wasmhost.\n",
  )
  let mut first = true
  for p in ps {
    match p {
      Text(line) => {
        if !first {
          out.write_char('\n')
        }
        out.write_string(line)
        first = false
      }
      Ext(d) => {
        if !first {
          out.write_char('\n')
        }
        out.write_string(moon_decl(d))
        first = false
      }
    }
  }
  out.write_char('\n')
  out.to_string()
}

///|
/// One declaration on Wasm: the import itself, or the import and the function that gives it what it takes.
fn moon_decl(d : Decl) -> String {
  let out = StringBuilder()
  if plain(d) {
    out.write_string("fn \{d.name}(\{moon_params(d)})\{moon_ret(d.ret)} = \"mbhost\" \"\{d.sym}\"")
    return out.to_string()
  }
  {
    // a function reference of strings or bytes: kept here, the shell given one of numbers that calls it
    for i, p in d.params {
      if !is_func(p.ty) || plain_func(p.ty) {
        continue
      }
      let (fps, fret) = func_sig(p.ty)
      let slot = "mbw_cb_\{d.sym}_\{i}"
      let ins = fps.mapi(fn(k, t) { if is_scalar(t) { "a\{k} : \{t}" } else { "a\{k} : Int" } })
      let outs = fps.mapi(fn(k, t) {
        match t {
          "String" => "@wasmrt.string_at(a\{k})"
          "Bytes" => "@wasmrt.bytes_at(a\{k})"
          t if is_scalar(t) => "a\{k}"
          t => fail("no Wasm way for a \{t} given to \{d.name}")
        }
      })
      // called with no function kept, it says so before it stops (mbui/halt, which the package imports)
      out.write_string(
        "let \{slot} : Ref[\{p.ty}?] = Ref(None)\n\n///|\n" +
        "fn \{slot}_in(\{ins.join(", ")}) -> \{fret} {\n" +
        "  match \{slot}.val {\n    Some(f) => f(\{outs.join(", ")})\n    None => @halt.saying(\"\{d.sym}: no function\")\n  }\n}\n\n///|\n",
      )
    }
    let wparams = d.params.map(fn(p) {
      if is_scalar(p.ty) {
        "\{p.name} : \{p.ty}"
      } else if is_func(p.ty) {
        "\{p.name} : \{func_plain(p.ty)}"
      } else {
        "\{p.name} : Int"
      }
    })
    let wret = if is_scalar(d.ret) { d.ret } else { "Int" }
    out.write_string(
      "fn mbw_\{d.sym}(\{wparams.join(", ")})\{moon_ret(wret)} = \"mbhost\" \"\{d.sym}\"\n\n///|\n",
    )
    let keeps = StringBuilder()
    let args = d.params.mapi(fn(i, p) {
      if is_scalar(p.ty) || (is_func(p.ty) && plain_func(p.ty)) {
        p.name
      } else if is_func(p.ty) {
        keeps.write_string("  mbw_cb_\{d.sym}_\{i}.val = Some(\{p.name})\n")
        let n = func_sig(p.ty).0.length()
        let xs = Array::makei(n, fn(k) { "a\{k}" }).join(", ")
        "fn(\{xs}) { mbw_cb_\{d.sym}_\{i}_in(\{xs}) }"
      } else {
        "@wasmrt.\{addr_of(p.ty)}(\{p.name})"
      }
    })
    let call = "mbw_\{d.sym}(\{args.join(", ")})"
    let body = match d.ret {
      "String" => "@wasmrt.take_string(\{call})"
      "Bytes" => "@wasmrt.take_bytes(\{call})"
      ty if is_scalar(ty) => call
      ty => fail("no Wasm way to answer \{ty}: \{d.name}")
    }
    out.write_string("fn \{d.name}(\{moon_params(d)}) -> \{d.ret} {\n\{keeps.to_string()}  \{body}\n}")
  }
  out.to_string()
}

///|
/// A MoonBit type as the C host has it.
fn c_type(ty : String) -> String {
  match ty {
    "Int" => "int32_t"
    "Bool" => "int32_t"
    "Byte" => "int32_t"
    "UInt" => "uint32_t"
    "Int64" => "int64_t"
    "Double" => "double"
    "Unit" => "void"
    "String" => "moonbit_string_t"
    "Bytes" => "moonbit_bytes_t"
    "FixedArray[Double]" => "double *"
    "FixedArray[Byte]" => "uint8_t *"
    "FixedArray[Int]" => "int32_t *"
    ty if is_func(ty) => "void *"
    ty => fail("no C type for \{ty}")
  }
}

///|
/// A Wasm value kind of the C API's for `ty` (as it crosses: a place is an i32).
fn w_kind(ty : String) -> String {
  match ty {
    "Double" => "WASM_F64"
    "Int64" => "WASM_I64"
    ty if is_func(ty) => "WASM_FUNCREF"
    _ => "WASM_I32"
  }
}

///|
/// A FuncRef's parameters and result.
fn func_sig(ty : String) -> (Array[String], String) {
  // FuncRef[(A, B) -> R]
  let inner = ty.exact_view(start=8, end=ty.length() - 1).to_owned()
  guard inner.find("->") is Some(arrow) else { fail("not a function type: \{ty}") }
  let lhs = trim(inner.exact_view(end=arrow).to_owned())
  let ret = trim(inner.exact_view(start=arrow + 2).to_owned())
  let ps = split_top(lhs.exact_view(start=1, end=lhs.length() - 1).to_owned())
  (ps, ret)
}

///|
fn c_file(ds : Array[Decl]) -> String {
  let out = StringBuilder()
  out.write_string(
    "// Generated by mbui's scripts/wasmhost from the native host's declarations: the Wasm program's imports (\"mbhost\")\n" +
    "// made the C calls the native program makes (mbui/tools/wasmhost/main.mbt says how). Not to be edited.\n" +
    "#include \"wasmhost.h\"\n\n",
  )
  // the C host's own functions, as the native program calls them
  for d in ds {
    let ps = if d.params.is_empty() { "void" } else { d.params.map(fn(p) { c_type(p.ty) }).join(", ") }
    out.write_string("\{c_type(d.ret)} \{d.sym}(\{ps});\n")
  }
  out.write_string("\n")
  // the trampolines: a FuncRef parameter's function kept, called as the C side calls its own
  for d in ds {
    for i, p in d.params {
      if !is_func(p.ty) {
        continue
      }
      let (fps, fret) = func_sig(p.ty)
      let slot = "cb_\{d.sym}_\{i}"
      out.write_string("static wasmtime_func_t \{slot};\n")
      let cps = fps.mapi(fn(k, t) { "\{c_type(t)} a\{k}" })
      out.write_string(
        "static \{c_type(fret)} \{slot}_call(\{if cps.is_empty() { "void" } else { cps.join(", ") }}) {\n",
      )
      out.write_string("  wasmtime_val_t args[\{fps.length().max(1)}], res[1];\n")
      for k, t in fps {
        match t {
          "Double" => out.write_string("  args[\{k}].kind = WASMTIME_F64; args[\{k}].of.f64 = a\{k};\n")
          "Int64" => out.write_string("  args[\{k}].kind = WASMTIME_I64; args[\{k}].of.i64 = a\{k};\n")
          "String" =>
            out.write_string(
              "  args[\{k}].kind = WASMTIME_I32; args[\{k}].of.i32 = mbw_give_string(a\{k});\n",
            )
          "Bytes" =>
            out.write_string("  args[\{k}].kind = WASMTIME_I32; args[\{k}].of.i32 = mbw_give_bytes(a\{k});\n")
          t if is_scalar(t) =>
            out.write_string("  args[\{k}].kind = WASMTIME_I32; args[\{k}].of.i32 = (int32_t)a\{k};\n")
          t => fail("no trampoline for a \{t} in \{d.sym}")
        }
      }
      out.write_string(
        "  mbw_call(&\{slot}, args, \{fps.length()}, res, \{if fret == "Unit" { 0 } else { 1 }});\n",
      )
      match fret {
        "Unit" => ()
        "Double" => out.write_string("  return res[0].of.f64;\n")
        "Int64" => out.write_string("  return res[0].of.i64;\n")
        t if is_scalar(t) => out.write_string("  return (\{c_type(t)})res[0].of.i32;\n")
        t => fail("no trampoline answer \{t} in \{d.sym}")
      }
      out.write_string("}\n")
    }
  }
  out.write_string("\n")
  // the imports
  for d in ds {
    out.write_string(
      "static wasm_trap_t *t_\{d.sym}(void *env, wasmtime_caller_t *caller, const wasmtime_val_t *a, size_t na,\n" +
      "    wasmtime_val_t *r, size_t nr) {\n" +
      "  (void)env; (void)na; (void)nr;\n" +
      "  uint8_t *m = mbw_memory(caller);\n" +
      "  (void)m;\n",
    )
    let args = d.params.mapi(fn(i, p) {
      let borrowed = d.borrowed.contains(p.name)
      match p.ty {
        "Double" => "a[\{i}].of.f64"
        "Int64" => "a[\{i}].of.i64"
        "String" =>
          if borrowed {
            "(moonbit_string_t)(m + a[\{i}].of.i32)"
          } else {
            "mbw_copy_string(m, a[\{i}].of.i32)"
          }
        "Bytes" =>
          if borrowed {
            "(moonbit_bytes_t)(m + a[\{i}].of.i32)"
          } else {
            "mbw_copy_bytes(m, a[\{i}].of.i32)"
          }
        "FixedArray[Double]" => "(double *)(m + a[\{i}].of.i32)"
        "FixedArray[Byte]" => "(uint8_t *)(m + a[\{i}].of.i32)"
        "FixedArray[Int]" => "(int32_t *)(m + a[\{i}].of.i32)"
        t if is_func(t) => "mbw_keep(&cb_\{d.sym}_\{i}, &a[\{i}]) ? (void *)cb_\{d.sym}_\{i}_call : NULL"
        "UInt" => "(uint32_t)a[\{i}].of.i32"
        _ => "a[\{i}].of.i32"
      }
    })
    let call = "\{d.sym}(\{args.join(", ")})"
    match d.ret {
      "Unit" => out.write_string("  \{call};\n")
      "Double" => out.write_string("  r[0].kind = WASMTIME_F64; r[0].of.f64 = \{call};\n")
      "Int64" => out.write_string("  r[0].kind = WASMTIME_I64; r[0].of.i64 = \{call};\n")
      "String" => out.write_string("  r[0].kind = WASMTIME_I32; r[0].of.i32 = mbw_keep_string(\{call});\n")
      "Bytes" => out.write_string("  r[0].kind = WASMTIME_I32; r[0].of.i32 = mbw_keep_bytes(\{call});\n")
      _ => out.write_string("  r[0].kind = WASMTIME_I32; r[0].of.i32 = (int32_t)\{call};\n")
    }
    out.write_string("  return NULL;\n}\n")
  }
  // the table the shell defines them by
  out.write_string("\nconst mbw_import mbw_imports[] = {\n")
  for d in ds {
    let ps = d.params.map(fn(p) { w_kind(p.ty) })
    let rs = if d.ret == "Unit" { [] } else { [w_kind(d.ret)] }
    // (an empty list's {0}: MSVC's C takes no empty initializer)
    let kinds = fn(ks : Array[String]) { if ks.is_empty() { "0" } else { ks.join(", ") } }
    out.write_string(
      "  {\"\{d.sym}\", t_\{d.sym}, \{ps.length()}, {\{kinds(ps)}}, \{rs.length()}, {\{kinds(rs)}}},\n",
    )
  }
  out.write_string("  {NULL, NULL, 0, {0}, 0, {0}},\n};\n")
  out.to_string()
}

///|
/// Where FILE's Wasm side goes: x_native.mbt's beside it as x_wasm.mbt, x.mbt's as x_wasm.mbt.
fn wasm_path(file : String) -> String {
  let base = if file.has_suffix("_native.mbt") {
    file.exact_view(end=file.length() - "_native.mbt".length()).to_owned()
  } else {
    file.exact_view(end=file.length() - ".mbt".length()).to_owned()
  }
  base + "_wasm.mbt"
}

///|
fn run(args : Array[String], write : Bool) -> Int {
  if args.length() < 2 {
    fail("gen|check THUNKS.c FILE.mbt…")
  }
  let wanted : Array[(String, String)] = []
  let all : Array[Decl] = []
  let seen : Map[String, Bool] = Map([])
  for file in args[1:] {
    guard @sys.read_text(file) is Some(text) else { fail("no \{file}") }
    let ps = pieces(text)
    let ds = decls(text)
    for d in ds {
      // (a C function declared in more than one file is one import)
      if !seen.contains(d.sym) {
        seen[d.sym] = true
        all.push(d)
      }
    }
    wanted.push((wasm_path(file), moon_file(@sys.basename(file), ps)))
  }
  // (the shell's side is made as the shell is built: what is kept in the repository is the program's side alone)
  if write {
    wanted.push((args[0], c_file(all)))
  }
  let mut differ = 0
  for w in wanted {
    let (path, text) = w
    if @sys.read_text(path) == Some(text) {
      continue
    }
    if write {
      if !@sys.write_text(path, text) {
        fail("\{path}: not written")
      }
      @sys.println_out("wasmhost: \{path}")
    } else {
      @sys.eprintln("wasmhost: \{path} is not what the declarations make: scripts/wasmhost")
      differ += 1
    }
  }
  if differ > 0 {
    1
  } else {
    0
  }
}

///|
fn main {
  let argv = @env.args()
  let args = argv[1:].to_owned()
  let code = match args {
    ["gen", .. rest] => run(rest.to_owned(), true)
    ["check", .. rest] => run(rest.to_owned(), false)
    _ => fail("gen|check THUNKS.c FILE.mbt…")
  }
  @sys.exit(code)
}
