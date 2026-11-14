// Whether the core was given mermaid is each run's own (viz_mermaid.mbt's init, mbui's on_reset): a run's core is a
// core started anew, which has none till it is given it. A run whose core was given it left that said for the next,
// whose core was never given it and was asked a chart first (failed before this: mermaid_given still true).

///|
test "a run begins with its core given no mermaid, whatever the run before gave the one it had" {
  @ui.Tester::new(fn(_c) {  }, w=200.0, h=100.0) |> ignore
  mermaid_given.val = true
  @ui.Tester::new(fn(_c) {  }, w=200.0, h=100.0) |> ignore
  assert_false(mermaid_given.val)
}
