// The page's shell's own turning, in Node, with the page's timers in the test's hands: `setTimeout`, `clearTimeout`
// and `queueMicrotask` are the test's while it runs (put back before anything is asserted), so nothing here waits on
// real time, and the runtime's clock is the test's own. What needs iroh or a page's storage is not reached: that
// is held by a page in a browser, outside this repository (AGENTS.md).

///|
#external
priv type Hands

///|
/// The page's timers taken: every timer asked from now on is kept, not set, and every microtask kept, not queued.
extern "js" fn hands_take() -> Hands =
  #|() => {
  #|  const hands = { was: [globalThis.setTimeout, globalThis.clearTimeout, globalThis.queueMicrotask], timers: [], soon: [] };
  #|  globalThis.setTimeout = (turn, ms) => hands.timers.push({ turn, ms });
  #|  globalThis.clearTimeout = () => {};
  #|  globalThis.queueMicrotask = (turn) => void hands.soon.push(turn);
  #|  return hands;
  #|}

///|
extern "js" fn hands_back(hands : Hands) -> Unit =
  #|(hands) => {
  #|  [globalThis.setTimeout, globalThis.clearTimeout, globalThis.queueMicrotask] = hands.was;
  #|}

///|
/// The microtasks kept are run, those they queue too: how many.
extern "js" fn hands_soon(hands : Hands) -> Int =
  #|(hands) => {
  #|  let ran = 0;
  #|  for (let turn = hands.soon.shift(); turn !== undefined; turn = hands.soon.shift(), ran++) turn();
  #|  return ran;
  #|}

///|
/// How many timers were asked so far, and the delay the last was asked with.
extern "js" fn hands_timers(hands : Hands) -> Int =
  #|(hands) => hands.timers.length

///|
extern "js" fn hands_delay(hands : Hands) -> Double =
  #|(hands) => hands.timers[hands.timers.length - 1].ms

///|
/// The last timer asked comes due.
extern "js" fn hands_fire(hands : Hands) -> Unit =
  #|(hands) => hands.timers[hands.timers.length - 1].turn()

///|
test "a wake further off than a browser's timer takes is asked as the most it takes, not as none" {
  let hands = hands_take()
  let made = page_start("t", "", (_, _, _, _) => ())
  page_wake(made, 1000.0, () => ())
  let near = hands_delay(hands)
  // 2^31 ms: a browser's setTimeout takes it for 0, and what waits for it runs at once, again and again
  page_wake(made, 2147483648.0, () => ())
  let far = hands_delay(hands)
  page_wake(made, 3.0e12, () => ())
  let further = hands_delay(hands)
  page_wake(made, -1.0, () => ())
  let asked = hands_timers(hands)
  hands_back(hands)
  assert_eq(near, 1000.0)
  assert_eq(far, 2147483647.0)
  assert_eq(further, 2147483647.0)
  // (a negative one asks none)
  assert_eq(asked, 3)
}

///|
test "a timer that comes before its time asks again for what is left, by the runtime's clock, and wakes nothing early" {
  let hands = hands_take()
  let clock = Ref(1_000L)
  let rt = @effect.Runtime::live(() => clock.val)
  ignore(Shell::start(rt, "t", iroh=""))
  let woke = Ref(false)
  ignore(
    rt.fork(() => {
      @effect.sleep(5_000)
      woke.val = true
    }),
  )
  // The fork asked a turn; the turn ran the fiber to its sleep and asked the page's timer for it.
  let turns = hands_soon(hands)
  let first = (hands_timers(hands), hands_delay(hands))
  // The timer comes with the clock where it was (as one cut to the most a browser takes does): nothing is due.
  hands_fire(hands)
  ignore(hands_soon(hands))
  let early = (hands_timers(hands), hands_delay(hands), woke.val)
  // And 2 s on, still early: asked for the 3 s left.
  clock.val = 3_000L
  hands_fire(hands)
  ignore(hands_soon(hands))
  let later = (hands_timers(hands), hands_delay(hands), woke.val)
  // At its time the fiber wakes, and no timer is asked after: the runtime has none.
  clock.val = 6_000L
  hands_fire(hands)
  ignore(hands_soon(hands))
  let due = (hands_timers(hands), woke.val)
  hands_back(hands)
  assert_eq(turns, 1)
  assert_eq(first, (1, 5000.0))
  assert_eq(early, (2, 5000.0, false))
  assert_eq(later, (3, 3000.0, false))
  assert_eq(due, (3, true))
}
