// How signing in stands told as it changes (sign_in_now, changed): what reads it is told each time a sign-in ends,
// with what it ended as.

///|
test "how signing in stands, followed: told as a sign-in ends, failed, given up and done, each as it ended" {
  let seen : Array[(Bool, String)] = []
  let stop = @signals.effect(fn() {
    let s = sign_in_now()
    seen.push((s.busy, s.failed))
  })
  state.busy = true
  told()
  ended(Err("no network"))
  ended(Err("cancelled"))
  ended(Ok("lin@example.com"))
  stop()
  assert_eq(seen, [(false, ""), (true, ""), (false, "no network"), (false, ""), (false, "")])
}

///|
test "the browser opens sign-in once only when the initial account list is empty" {
  state.web_auto = true
  assert_true(web_sign_in_needed([]))
  assert_false(web_sign_in_needed([]))
  state.web_auto = true
  assert_false(web_sign_in_needed([{ "sub": "one" }]))
  assert_false(web_sign_in_needed([]))
}
