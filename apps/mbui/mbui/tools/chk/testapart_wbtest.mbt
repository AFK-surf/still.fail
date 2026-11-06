///|
let every_test : String =
  #|   1. mbui/view wraps_test.mbt:44 index=0 name="wraps: one"
  #|   2. mbui/view wraps_test.mbt:59 index=1 name="wraps: two"
  #|   3. mbui/view stopped_run_test.mbt:6 index=0 name="panic: stopped"
  #|   4. mbui/view stopped_run_test.mbt:20 index=1 name="after it"
  #|   5. mbui/view painted_test.mbt:10 index=0 name="painted: a"
  #|   6. mbui/view painted_test.mbt:20 index=1 name="painted: b"
  #|   7. mbui/view painted_test.mbt:65 index=2 name="panic: a read said Painted"
  #|   8. mbui/view painted_test.mbt:70 index=3 name="panic: and again"
  #|   9. mbui/view painted_test.mbt:80 index=4 name="painted: c"
  #|  10. mbui/ui last_test.mbt:3 index=0 name="panic: first"
  #|  11. mbui/ui last_test.mbt:9 index=1 name="it, after"
  #|  12. mbui/ui wide_test.mbt:3 index=0 name="a panic said in its name, not first"
  #|  13. mbui root_test.mbt:3 index=0 name="the module's own"
  #|  14. mbui/x/y y_test.mbt:3 index=0 name="another module's"

///|
let two_modules : Array[(String, String)] = [("mbui", "src"), ("mbui/x", "x/src")]

///|
test "tests apart: a file with none that aborts runs with the others, each that aborts alone, a stopped_ file whole" {
  assert_eq(
    apart(every_test, every_test, two_modules),
    Ok([
      (5, "src/view/wraps_test.mbt src/ui/wide_test.mbt src/root_test.mbt x/src/y/y_test.mbt"),
      (2, "src/view/stopped_run_test.mbt"),
      (2, "src/view/painted_test.mbt -i 0-2"),
      (1, "src/view/painted_test.mbt -i 2"),
      (1, "src/view/painted_test.mbt -i 3"),
      (1, "src/view/painted_test.mbt -i 4-5"),
      (1, "src/ui/last_test.mbt -i 0"),
      (1, "src/ui/last_test.mbt -i 1-2"),
    ]),
  )
}

///|
test "tests apart: some of a file's selected (-i, --filter), only they run, by their index, a stopped_ file's in runs" {
  let selected =
    #|   1. mbui/view wraps_test.mbt:59 index=1 name="wraps: two"
    #|   2. mbui/view stopped_run_test.mbt:20 index=1 name="after it"
    #|   3. mbui/view painted_test.mbt:20 index=1 name="painted: b"
    #|   4. mbui/view painted_test.mbt:70 index=3 name="panic: and again"
    #|   5. mbui/view painted_test.mbt:80 index=4 name="painted: c"
    #|   6. mbui/ui wide_test.mbt:3 index=0 name="a panic said in its name, not first"
  assert_eq(
    apart(selected, every_test, two_modules),
    Ok([
      (1, "src/ui/wide_test.mbt"),
      (1, "src/view/wraps_test.mbt -i 1-2"),
      (1, "src/view/stopped_run_test.mbt -i 1-2"),
      (1, "src/view/painted_test.mbt -i 1-2"),
      (1, "src/view/painted_test.mbt -i 3"),
      (1, "src/view/painted_test.mbt -i 4-5"),
    ]),
  )
  // (a stopped_ file's consecutive ones together, aborting or not)
  let stopped =
    #|   1. mbui/view stopped_run_test.mbt:6 index=0 name="panic: stopped"
    #|   2. mbui/view stopped_run_test.mbt:20 index=1 name="after it"
  let three =
    #|   1. mbui/view stopped_run_test.mbt:6 index=0 name="panic: stopped"
    #|   2. mbui/view stopped_run_test.mbt:20 index=1 name="after it"
    #|   3. mbui/view stopped_run_test.mbt:30 index=2 name="and after"
  assert_eq(apart(stopped, three, two_modules), Ok([(2, "src/view/stopped_run_test.mbt -i 0-2")]))
}

///|
test "tests apart: no test, a line not a test's or not in turn, a file's tests out of order, one not in the whole, said" {
  let here = [("mbui", "src")]
  assert_eq(apart("\n", every_test, here), Err("no test in the outline"))
  assert_eq(
    apart("  1. other/ui a_test.mbt:3 index=0 name=\"x\"\n", every_test, here),
    Err("other/ui: a package of no module here"),
  )
  // (a line moon's outline would not say, or one of it lost: no file's tests left out unsaid)
  assert_eq(
    apart("  1. mbui/ui a_test.mbt:3 index=0 name=\"x\"\nWarning: something\n", every_test, here),
    Err("line 2 of the outline, not test 2's: Warning: something"),
  )
  assert_eq(
    apart("  1. mbui/ui a_test.mbt:3 index=0 name=\"x\"\n  3. mbui/ui a_test.mbt:9 index=1 name=\"y\"\n", every_test, here),
    Err("line 2 of the outline, not test 2's:   3. mbui/ui a_test.mbt:9 index=1 name=\"y\""),
  )
  assert_eq(
    apart("  1. mbui/ui a_test.mbt:3 index=0 name=\"x\"\n  2. mbui/ui a_test.mbt:3 a_test name=\"x\"\n", every_test, here),
    Err("line 2 of the outline, not test 2's:   2. mbui/ui a_test.mbt:3 a_test name=\"x\""),
  )
  assert_eq(
    apart(
      "  1. mbui/ui a_test.mbt:3 index=2 name=\"x\"\n  2. mbui/ui a_test.mbt:9 index=1 name=\"y\"\n",
      every_test,
      here,
    ),
    Err("src/ui/a_test.mbt: its test 1 after 2"),
  )
  assert_eq(
    apart("  1. mbui/ui last_test.mbt:3 index=2 name=\"x\"\n", every_test, here),
    Err("src/ui/last_test.mbt: its test 2, not in the whole outline"),
  )
  assert_eq(
    apart("  1. mbui/ui a_test.mbt:3 index=0 name=\"x\"\n", every_test, here),
    Err("src/ui/a_test.mbt: none of its tests in the whole outline"),
  )
}
