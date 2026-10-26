///|
fn put_file(top : Bytes, rel : String, text : String) -> Unit {
  let p = path_join(top, utf8(rel))
  makedirs(dirname(p))
  let _ = write_file(p, utf8(text))

}

///|
fn copied(top : Bytes, rel : String) -> Bytes {
  read_file(path_join(top, utf8(rel))).unwrap()
}

///|
test "a native stub is written anew when a file it includes, or one that includes, changes; else not" {
  let top = tmp_path("mirror")
  let stage = path_join(top, b"stage")
  let copy = path_join(top, b"copy")
  // the app's stub, including another package's C (as still.fail's win_engine.c its src/host/win_core.c), which
  // includes a header beside it; a stub that includes nothing; a header alone
  put_file(stage, "src/app/stub.c", "#include \"../host/core.c\"\nint stub;\n")
  put_file(stage, "src/host/core.c", "  #  include \"core.h\"\n#include <stdio.h>\nint core;\n")
  put_file(stage, "src/host/core.h", "int header;\n")
  put_file(stage, "src/host/plain.c", "int plain;")
  cmd_mirror([str(stage), str(copy)])
  let stub = copied(copy, "src/app/stub.c")
  assert_true(starts(stub, b"#include \"../host/core.c\"\nint stub;\n// mbc mirror: what it includes, by content: "))
  assert_eq(copied(copy, "src/host/plain.c"), b"int plain;")
  assert_eq(copied(copy, "src/host/core.h"), b"int header;\n")
  // nothing changed: written as it was
  cmd_mirror([str(stage), str(copy)])
  assert_eq(copied(copy, "src/app/stub.c"), stub)
  // the header two includes away changed: the stub, and the C that includes it, written anew
  let core = copied(copy, "src/host/core.c")
  put_file(stage, "src/host/core.h", "int header2;\n")
  cmd_mirror([str(stage), str(copy)])
  assert_true(copied(copy, "src/app/stub.c") != stub)
  assert_true(copied(copy, "src/host/core.c") != core)
  assert_true(starts(copied(copy, "src/app/stub.c"), b"#include \"../host/core.c\"\nint stub;\n"))
  assert_eq(copied(copy, "src/host/plain.c"), b"int plain;")
  rmtree(top)
}

///|
test "what the #include and #import lines of a C source name" {
  let names = include_names(
    b"#include \"a.h\"\n  # import <Foundation/Foundation.h>\n#define X \"b.h\"\n// #include \"c.h\"\n#include<d.h>\n#includes \"e.h\"",
  )
  assert_eq(names, [
    (b"a.h", true),
    (b"Foundation/Foundation.h", false),
    (b"d.h", false),
  ])
}
