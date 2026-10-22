// The splitter on made-up C: each kind of item, the stable names, what each unit declares, moonbit_init's pieces,
// each refusal. (scripts/mbc_test.sh builds programs with it.)

///|
let prelude_src : String =
  #|#include <stdint.h>
  #|#include <stdio.h>
  #|#ifdef __cplusplus
  #|extern "C" {
  #|#endif
  #|static inline int32_t helper(int32_t x) { return x + 1; }
  #|#define TWICE(x) ((x) * 2)
  #|#ifndef HAS_NO_SUCH_BUILTIN
  #|/* the prelude's own definitions that are not static (as its software clz without the builtins): data.c's */
  #|int32_t pre_twice(int32_t x) {
  #|  return x * 2;
  #|}
  #|const int32_t pre_tab[2] = {5, 6};
  #|#endif
  #|#ifdef __cplusplus
  #|}
  #|#endif
  #|

///|
let items_src : String =
  #|struct _M0TP1a1T;
  #|
  #|struct _M0TP1a1T {
  #|  int32_t x;
  #|  /* a comment with a } in it */
  #|  int32_t y;
  #|};
  #|
  #|typedef struct _M0TP1a1T _M0TP1a1Alias;
  #|
  #|int32_t _M0FP1a3add(
  #|  int32_t,
  #|  int32_t
  #|);
  #|
  #|#ifndef Moonbit_thing
  #|#define Moonbit_thing _M0FP1a3add
  #|#endif
  #|
  #|#define _M0FP1a3ffi puts
  #|
  #|int _M0FP1a3ffi(const char*);
  #|
  #|struct { int32_t rc; uint32_t meta; uint16_t const data[3]; } const _M0S1 =
  #|  { 1, 2, {104, 105, 0} };
  #|
  #|struct _M0TP1a1T _M0G1 = { 3, 4 };
  #|
  #|int32_t _M0G2;
  #|
  #|const char _M0G3[] = "a ; string } with { braces";
  #|
  #|static int32_t _M0FP1a6hidden(int32_t x) {
  #|  return x * 3;
  #|}
  #|
  #|int32_t _M0FP1a3add(int32_t a, int32_t b) {
  #|  #line 3 "/some/where/main.mbt"
  #|  if (a > b) {
  #|    return a - b + _M0FP1a6hidden(1);
  #|  }
  #|  return a + b + helper(0) - 1;
  #|}
  #|
  #|int32_t _M0FP1a3get() {
  #|  return _M0G1.x + _M0G2 + (int32_t)_M0S1.data[0] + TWICE(1) + Moonbit_thing(0, 0) + (_M0G3[0] == 'a')
  #|    + pre_twice(1) + pre_tab[1];
  #|}
  #|
  #|void moonbit_init() {
  #|  _M0G2 = _M0FP1a3add(1, 2);
  #|  goto join_2;
  #|  _M0G2 = -100;
  #|  join_2:;
  #|}
  #|
  #|int main(int argc, char** argv) {
  #|  moonbit_init();
  #|  printf("%d\n", _M0FP1a3get());
  #|  return 0;
  #|}
  #|

///|
/// The split's files (name: text) and what it made
fn sp(src : String, unit_bytes? : Int = 0) -> (Map[String, String], Split) raise SplitError {
  let dir = tmp_path("t")
  makedirs(dir)
  let s = try split(utf8(src), dir, unit_bytes~) catch {
    e => {
      rmtree(dir)
      raise e
    }
  }
  let out = {}
  for f in s.files {
    out[str(f.0)] = str(read_file(path_join(dir, f.0)).unwrap())
  }
  rmtree(dir)
  (out, s)
}

///|
fn occurs(hay : String, needle : String) -> Int {
  count(utf8(hay), utf8(needle))
}

///|
fn has(hay : String, needle : String) -> Bool {
  occurs(hay, needle) > 0
}

///|
fn stat_of(s : Split, name : String) -> Int {
  for x in s.stats {
    if x.0 == name {
      return x.1
    }
  }
  -1
}

///|
/// The functions' units (not decls.h, externs.h, data.c, init.c nor moonbit_init's)
fn fn_units(files : Map[String, String]) -> Array[String] {
  let out = []
  for n, _ in files {
    if n.has_suffix(".c") && !n.has_prefix("data") && !n.has_prefix("init.") {
      out.push(n)
    }
  }
  out.sort()
  out
}

///|
test "kinds" {
  let (files, m) = sp(prelude_src + "\n" + items_src)
  assert_eq(m.functions, 5)
  assert_eq(m.globals, 4)
  assert_eq(stat_of(m, "types"), 3)
  assert_eq(stat_of(m, "statics_dropped"), 1)
  assert_eq(stat_of(m, "prelude_definitions"), 2)
  let decls = files["decls.h"]
  assert_true(has(decls, "#ifdef CSPLIT_DEFS\n/* the prelude"))
  assert_true(
    has(
      decls, "  return x * 2;\n}\n#else\nint32_t pre_twice(int32_t x);\n#endif",
    ),
  )
  assert_true(has(decls, "#else\nextern const int32_t pre_tab[2];\n#endif"))
  let data = files["data.c"]
  assert_true(has(data, "#define CSPLIT_DEFS"))
  // (each global in a data unit of its own kind: none in data.c, none twice)
  assert_false(has(data, "_M0G1"))
  let globals = one_data(files)
  for g in ["_M0G1 =", "_M0G2;", "_M0G3[] =", "const _M0S1 ="] {
    assert_eq(occurs(globals, g), 1)
  }
  assert_true(m.made_global.contains(b"_M0FP1a6hidden"))
  assert_true(has(decls, "#define _M0FP1a3ffi puts"))
  assert_true(has(decls, "static inline int32_t helper"))
  let externs = files["externs.h"]
  assert_true(
    has(
      externs, "extern struct { int32_t rc; uint32_t meta; uint16_t const data[3]; } const _M0S1;",
    ),
  )
  assert_true(has(externs, "extern int32_t _M0G2;"))
  assert_true(has(externs, "extern const char _M0G3[];"))
  assert_true(has(files["init.c"], "void moonbit_init()"))
  // every function in exactly one unit, and static no more
  let body = fn_units(files).map(fn(n) { files[n] }).fold(init="", fn(a, b) { a + b })
  for name in ["_M0FP1a3add(int32_t a", "_M0FP1a3get() {", "int main("] {
    assert_eq(occurs(body, name), 1)
  }
  assert_false(has(body, "static int32_t"))
  assert_true(has(body, "CSPLIT_INTERNAL int32_t _Mz"))
  assert_true(
    has(
      decls, "#define CSPLIT_INTERNAL __attribute__((visibility(\"hidden\")))",
    ),
  )
  // a prototype for the function moonc defined without one
  assert_true(has(decls, "void moonbit_init();"))
  assert_false(has(decls + externs, "_M0G1 = {"))
}

///|
fn prog_stable(n : Int, extra : String) -> String {
  let n1 = n + 1
  let n7 = n + 7
  prelude_src +
  "\n" +
  (
    $|struct _M0TP11a1T;
    $|
    $|struct _M0TP11a1T {
    $|  int32_t x;
    $|};
    $|
    $|struct _M0TP11b1U {
    $|  int32_t y;
    $|};
    $|
    $|static struct { int32_t rc; uint16_t const data[2]; } const moonbit_string_literal_\{n} =
    $|  { 1, {104, 0} };
    $|
    $|int32_t _M0FP11a3add(int32_t, int32_t);
    $|
    $|static int32_t _M0FP11a4callC\{n}l9(int32_t);
    $|
    $|static int32_t _M0FP11b4only(int32_t);
    $|
    $|#define _M0FP11b3ffi b_real
    $|
    $|#ifndef Moonbit_unused
    $|#define Moonbit_unused _M0FP11c3zzz
    $|#endif
    $|
    $|int32_t b_real(int32_t);
    $|
    $|\{extra}
    $|static int32_t _M0FP11a4callC\{n}l9(int32_t _M0L1xS\{n}) {
    $|  int32_t _M0L6_2atmpS\{n1} = _M0L1xS\{n} + (int32_t)moonbit_string_literal_\{n}.data[0];
    $|  goto joinlet_\{n};
    $|  joinlet_\{n}:
    $|  return _M0L6_2atmpS\{n1};
    $|}
    $|
    $|int32_t _M0FP11a3add(int32_t a, int32_t b) {
    $|  struct _M0TP11a1T t = { .x = a };
    $|  return t.x + b + _M0FP11a4callC\{n}l9(0);
    $|}
    $|
    $|static int32_t _M0FP11b4only(int32_t _M0L1yS\{n7}) {
    $|  struct _M0TP11b1U u = { _M0L1yS\{n7} };
    $|  return u.y + _M0FP11b3ffi(0);
    $|}
    $|
    $|void moonbit_init() {
    $|}
    $|
    $|int main(int argc, char** argv) {
    $|  moonbit_init();
    $|  printf("%d", _M0FP11a3add(1, 2) + _M0FP11b4only(3));
    $|  return 0;
    $|}
    $|
  )
}

///|
test "stable" {
  // moonc's made-up numbers (locals, labels, anonymous functions, string literals) another build numbers otherwise
  // give the same units; a package's functions in its unit, with only what they use
  let (one, m) = sp(prog_stable(12, ""))
  let (two, _) = sp(prog_stable(345, "int32_t _M0FP11c5otherC9l9(int32_t);\n"))
  let units = fn_units(one)
  assert_eq(units, ["s0.c"]) // (two small packages: together)
  for n in units {
    assert_eq(one[n], two[n])
  }
  let u = one["s0.c"]
  assert_false(has(u, "S12"))
  assert_false(has(u, "joinlet_12"))
  assert_false(has(u, "moonbit_string_literal_12"))
  assert_true(has(u, "t.x")) // a member stays
  assert_true(has(u, "int32_t _M0FP11a3add(int32_t a")) // not static: its name kept
  assert_true(stat_of(m, "renamed") > 0)
  // a unit has what it uses only (a's functions over half a unit: a unit of its own; b's under: with the small ones)
  let (apart, _) = sp(prog_stable(12, ""), unit_bytes=600)
  assert_eq(fn_units(apart), ["a.c", "s0.c"])
  assert_true(has(apart["s0.c"], "int32_t y;"))
  assert_false(has(apart["s0.c"], "int32_t x;"))
  assert_true(has(apart["a.c"], "int32_t x;"))
  assert_false(has(apart["a.c"], "int32_t y;"))
  assert_true(has(apart["s0.c"], "int32_t b_real(int32_t);")) // what an FFI name stands for
  // a directive group in the units that use what it defines only (the test driver's FFI name is each program's)
  assert_true(has(apart["s0.c"], "#define _M0FP11b3ffi b_real"))
  assert_false(has(apart["a.c"], "#define _M0FP11b3ffi"))
  assert_false(has(apart["a.c"] + apart["s0.c"], "Moonbit_unused"))
}

///|
let by_content_src : String =
  #|struct _M0TP11a1T;
  #|
  #|static struct { int32_t rc; uint16_t const data[2]; } const moonbit_string_literal_3 = { 1, {104, 0} };
  #|
  #|static struct { int32_t rc; uint16_t const data[2]; } const moonbit_string_literal_9 = { 1, {105, 0} };
  #|
  #|static uint32_t const moonbit_layout_table_data[7] = { 1, 0, 2, 1, 2, 1, 0 };
  #|
  #|int32_t _M0FP11a3add(int32_t, int32_t);
  #|
  #|int32_t _M0FP11a3add(int32_t a, int32_t b) {
  #|  uint32_t x = Moonbit_make_regular_object_header(MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED, 0, 0);
  #|  uint32_t y = Moonbit_make_regular_object_header(MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED, 2, 0);
  #|  uint32_t z = Moonbit_make_regular_object_header(MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED, 5, 0);
  #|  return (int32_t)(x + y + z) + moonbit_string_literal_3.data[0] + moonbit_string_literal_9.data[0];
  #|}
  #|
  #|void moonbit_init() {
  #|}
  #|
  #|int main(int argc, char** argv) {
  #|  moonbit_init();
  #|  return _M0FP11a3add(1, 2);
  #|}
  #|

///|
/// (the layouts' names in the order they come, the literals' names sorted, data.c)
fn layout_names_in(files : Map[String, String]) -> (Array[String], Array[String], String) {
  let u = fn_units(files).map(fn(n) { files[n] }).fold(init="", fn(a, b) { a + b })
  let ub = utf8(u)
  let lay = []
  let mut p = 0
  while true {
    let k = find(ub, b"INDEXED, ", p)
    if k < 0 {
      break
    }
    let e = ident_end(ub, k + 9)
    lay.push(str(ub[k + 9:e]))
    p = e
  }
  let lit = BSet::new()
  p = 0
  while true {
    let k = find(ub, b"_Ms", p)
    if k < 0 {
      break
    }
    let e = ident_end(ub, k)
    if starts_at(ub, e, b".data") {
      lit.add(sub(ub, k, e))
    }
    p = e
  }
  (lay, lit.sorted().map(fn(b) { str(b) }), files["data_layout.c"])
}

///|
test "by content, apart" {
  // string literals and layouts named by their content: two contents whose hashes are the same named apart, the
  // same each time; two layouts the same, one name (and the first's offset)
  let src = prelude_src + "\n" + by_content_src
  let (lay, lit, data) = layout_names_in(sp(src).0)
  assert_eq(lay[0], lay[2]) // offsets 0 and 5: the same words
  assert_true(lay[0] != lay[1])
  assert_eq(lit.length(), 2)
  assert_true(has(data, "const uint32_t \{lay[0]} = 0;")) // (the first of the two)
  same_hash.val = true
  let apart = try {
    let r = [layout_names_in(sp(src).0), layout_names_in(sp(src).0)]
    same_hash.val = false
    r
  } catch {
    e => {
      same_hash.val = false
      raise e
    }
  }
  for x in apart {
    let (lay2, lit2, data2) = x
    assert_eq(lay2[0], lay2[2])
    assert_true(lay2[0] != lay2[1])
    let first2 = [lay2[0], lay2[1]]
    first2.sort()
    assert_eq(first2, ["csplit_layout_0", "csplit_layout_0_1"])
    assert_eq(lit2, ["_Ms0", "_Ms0_1"])
    assert_true(has(data2, "const uint32_t \{lay2[1]} = 2;"))
  }
}

///|
fn init_text(n : Int, b_value : Int) -> String {
  let n1 = n + 1
  let n2 = n + 2
  let n3 = n + 3
  $|void moonbit_init() {
  $|  moonbit_layout_table = moonbit_layout_table_data;
  $|  int32_t _M0L6_2atmpS\{n};
  $|  int32_t _M0L6_2atmpS\{n1};
  $|  int32_t _M0L1iS\{n2};
  $|  struct _M0TP11a1T _M0L6_2atmpS\{n3};
  $|  _M0L6_2atmpS\{n} = 7;
  $|  _M0FP11a1x = _M0L6_2atmpS\{n} + 1;
  $|  moonbit_decref(_M0L6_2atmpS\{n});
  $|  _M0L6_2atmpS\{n3} = (struct _M0TP11a1T){
  $|    .x = 1
  $|  };
  $|  Moonbit_object_header(_M0FP11a1y)->meta = _M0L6_2atmpS\{n3}.x;
  $|  _M0L1iS\{n2} = 0;
  $|  while (1) {
  $|    if (_M0L1iS\{n2} < 3) {
  $|      _M0FP11b1z[_M0L1iS\{n2}] = \{b_value};
  $|    } else {
  $|      break;
  $|    }
  $|    _M0L1iS\{n2} += 1;
  $|  }
  $|  _M0FP11b1w = 0;
  $|  do {
  $|    _M0FP11b1w += 1;
  $|  } while (_M0FP11b1w < 2);
  $|  _M0L6_2atmpS\{n1} = 5;
  $|  _M0FP11a1v = _M0L6_2atmpS\{n1};
  $|  _M0FP11b1u = _M0L6_2atmpS\{n1};
  $|  _M0FP11c1t = 1;
  $|}
  $|
}

///|
/// The init program of scripts/mbc_test.sh too (it prints 8 5 4 2 5 1 1)
fn prog_init(n : Int, b_value : Int) -> String {
  prelude_src +
  "\n" +
  (
    #|struct _M0TP11a1T;
    #|
    #|struct _M0TP11a1T {
    #|  int32_t x;
    #|};
    #|
    #|static uint32_t const moonbit_layout_table_data[1] = { 0 };
    #|
    #|uint32_t const* moonbit_layout_table;
    #|
    #|int32_t _M0FP11a1x;
    #|
    #|int32_t _M0FP11a1v;
    #|
    #|int32_t _M0FP11b1z[3];
    #|
    #|int32_t _M0FP11b1w;
    #|
    #|int32_t _M0FP11b1u;
    #|
    #|int32_t _M0FP11c1t;
    #|
    #|struct { uint32_t meta; } _M0FP11a1y_obj;
    #|
    #|#define Moonbit_object_header(p) (&_M0FP11a1y_obj)
    #|#define _M0FP11a1y 0
    #|#define moonbit_decref(x) ((void)(x))
    #|
    #|
  ) +
  init_text(n, b_value) +
  (
    #|
    #|int main(int argc, char** argv) {
    #|  moonbit_init();
    #|  printf("%d %d %d %d %d %d %u\n", _M0FP11a1x, _M0FP11a1v, _M0FP11b1z[2], _M0FP11b1w, _M0FP11b1u,
    #|         _M0FP11c1t, _M0FP11a1y_obj.meta);
    #|  return 0;
    #|}
    #|
  )
}

///|
test "init jumps stay after the values they use" {
  let src =
    #|void moonbit_init() {
    #|  int32_t value_1;
    #|  value_1 = 7;
    #|  goto join_2;
    #|  value_1 = -100;
    #|  join_2:;
    #|  _M0FP11a1x = value_1;
    #|}
  let pieces = init_pieces(utf8(src)).unwrap()
  assert_eq(pieces.length(), 1)
  assert_eq(str(strip(pieces[0].1)), "int32_t value_1;")
  assert_true(has(str(pieces[0].2), "value_1 = 7;\n  goto join_2;"))
  assert_true(init_decl(b"goto join_2;") is None)
  assert_true(init_decl(b"return value_1;") is None)
}

///|
test "init pieces" {
  // moonbit_init in its packages' pieces: a global's temporaries and what lets them go with it, a local two share
  // keeping them one, blocks whole; package b changed, package a's unit the same
  let pieces = init_pieces(utf8(init_text(10, 4))).unwrap()
  assert_eq(pieces.map(fn(p) { str(p.0) }), ["a", "b", "a", "c"])
  let a = pieces[0]
  let b = pieces[1]
  let ab = pieces[2]
  let c = pieces[3]
  assert_true(str(lstrip(a.2)).has_prefix("moonbit_layout_table ="))
  assert_true(has(str(a.2), "moonbit_decref(_M0L6_2atmpS10)")) // (with the global its temporary was for)
  assert_true(has(str(a.1), "int32_t _M0L6_2atmpS10;"))
  assert_true(has(str(a.1), "struct _M0TP11a1T _M0L6_2atmpS13;"))
  assert_true(has(str(b.2), "_M0L1iS12 = 0;")) // (before the global it is for)
  assert_true(has(str(b.2), "} else {"))
  assert_true(has(str(b.2), "} while (_M0FP11b1w < 2);"))
  assert_true(has(str(ab.2), "_M0FP11b1u =")) // a local two packages' globals share: one piece, the first's
  assert_eq(str(strip(c.2)), "_M0FP11c1t = 1;")
  assert_true(init_pieces(b"void moonbit_init() {\n  if (x) {\n}\n") is None)
  let (one, m) = sp(prog_init(10, 4))
  assert_eq(stat_of(m, "init_pieces"), 4)
  let inits = []
  for n, _ in one {
    if n.has_prefix("init.") && n != "init.c" {
      inits.push(n)
    }
  }
  assert_eq(inits, ["init.s0.c"]) // (small: together)
  init_small.val = 0
  let (x, y) = try {
    let r = (sp(prog_init(10, 4)).0, sp(prog_init(90, 6)).0)
    init_small.val = 16 * 1024
    r
  } catch {
    e => {
      init_small.val = 16 * 1024
      raise e
    }
  }
  let xi = []
  for n, _ in x {
    if n.has_prefix("init.") && n != "init.c" {
      xi.push(n)
    }
  }
  xi.sort()
  assert_eq(xi, ["init.a.c", "init.b.c", "init.c.c"])
  assert_eq(x["init.a.c"], y["init.a.c"]) // (its locals numbered apart from moonc's)
  assert_eq(x["init.c.c"], y["init.c.c"])
  assert_true(x["init.b.c"] != y["init.b.c"])
  assert_eq(x["init.c"], y["init.c"])
}

///|
fn prog_declared(members : String, fn_name : String) -> String {
  prelude_src +
  "\n" +
  (
    $|struct _M0TP11a3Big;
    $|
    $|struct \{fn_name};
    $|
    $|struct _M0TP11a3Big {
    $|  \{members}
    $|};
    $|
    $|struct \{fn_name} {
    $|  int32_t(* code)(struct \{fn_name}*, int32_t);
    $|};
    $|
    $|int32_t _M0FP11a3get(struct _M0TP11a3Big*);
    $|
    $|int32_t _M0FP11b4pass(struct _M0TP11a3Big*, struct \{fn_name}*);
    $|
    $|int32_t _M0FP11a3get(struct _M0TP11a3Big* _M0L1bS3) {
    $|  return _M0L1bS3->$0;
    $|}
    $|
    $|int32_t _M0FP11b4pass(struct _M0TP11a3Big* _M0L1bS5, struct \{fn_name}* _M0L1fS6) {
    $|  return _M0FP11a3get(_M0L1bS5) + _M0L1fS6->code(_M0L1fS6, 1);
    $|}
    $|
    $|void moonbit_init() {
    $|}
    $|
    $|int main(int argc, char** argv) {
    $|  moonbit_init();
    $|  return 0;
    $|}
    $|
  )
}

///|
fn unit_named(files : Map[String, String], p : String) -> String {
  for n, t in files {
    if n == p + ".c" || (n.has_prefix(p + "_") && n.has_suffix(".c")) {
      return t
    }
  }
  abort("no unit \{p}")
}

///|
test "declared only" {
  // a struct a unit only passes by pointer is declared there, not defined: its members changed, that unit is the
  // same; a function type is named by its definition, not by the name moonc gave it
  let (one, _) = sp(prog_declared("int32_t $0;", "_M0TWuEu"), unit_bytes=2)
  let (two, _) = sp(
    prog_declared("int32_t $0;\n  int32_t $1;", "_M0TWiEu"),
    unit_bytes=2,
  )
  let a = unit_named(one, "a")
  let b = unit_named(one, "b")
  assert_true(has(a, "int32_t $0;")) // (a reaches a member: defined)
  assert_false(has(b, "int32_t $0;")) // (b passes it on: declared)
  assert_true(has(b, "struct _Mz0__M0TP0a0Big;"))
  assert_true(has(b, "(* code)")) // (b calls through the function type: defined)
  assert_false(has(b, "TWuEu"))
  assert_eq(b, unit_named(two, "b"))
  assert_true(a != unit_named(two, "a"))
}

///|
fn refused(src : String, words : String) -> Unit raise {
  let said = try {
    let _ = sp(src)
    "(not refused)"
  } catch {
    SplitError(e) => e
  }
  assert_true(has(said, words), msg="\{said}: not \{words}")
}

///|
test "refusals" {
  let p = prelude_src
  let i = items_src
  refused("int x;\n", "not the file moonc generates")
  refused(
    p + i.replace(old="void moonbit_init() {", new="void moonbit_init2() {"),
    "moonbit_init",
  )
  refused(p + i + "#define LATE 1\n", "after the first function definition")
  refused(
    p + i.replace(old="int32_t _M0G2;", new="#if X\nint32_t _M0G2;\n#endif"),
    "inside a #if",
  )
  refused(
    p + i.replace(old="int32_t _M0G2;", new="int32_t _M0G2, _M0G4;"),
    "more than one declarator",
  )
  refused(
    p + i.replace(old="int32_t _M0G2;", new="int32_t _M0G2; int32_t _M0G4;"),
    "does not end its line",
  )
  refused(p + i + "int32_t _M0G1 = 2;\n", "defined twice")
  refused(p + i + "int32_t f() {\n", "ends inside an item")
}

///|
/// The data units' texts together (data_*.c)
fn one_data(files : Map[String, String]) -> String {
  let names = []
  for n, _ in files {
    if n.has_prefix("data_") {
      names.push(n)
    }
  }
  names.sort()
  names.map(fn(n) { files[n] }).fold(init="", fn(a, b) { a + b })
}
