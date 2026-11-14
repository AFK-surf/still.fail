// What a test leaves is no later test's start (app.mbt reset_by_hand, fresh_app): the two run in this order in one
// process, the first leaving the app changed and making no Tester, the second's Tester starting from the app as at
// the start all the same.

///|
test "a test that makes no Tester puts the app back by hand and changes it after: left as it is" {
  fresh_app()
  files_cornered.val = true
}

///|
test "the next Tester starts from the app as at the start, whatever the test before it left" {
  let _t = @ui.Tester::new(fn(_c) { () })
  assert_false(files_cornered.val, msg="the app as the test before left it")
}
