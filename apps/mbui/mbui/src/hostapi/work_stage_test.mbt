///|
struct WorkHost {
  mut stage : Int
  seen : Array[Int]
}

///|
impl @hostapi.Host for WorkHost with work_stage(self, stage) {
  let previous = self.stage
  self.stage = stage
  self.seen.push(stage)
  previous
}

///|
test "the host sees work before it completes, and nested work restores the outer phase" {
  let host : WorkHost = { stage: 0, seen: [] }
  @hostapi.set_host(host)
  let during : Array[Int] = []
  let result = @hostapi.work_during(@hostapi.work_layout, fn() {
    during.push(host.stage)
    @hostapi.work_during(@hostapi.work_screen_open, fn() { during.push(host.stage) })
    during.push(host.stage)
    42
  })
  assert_eq(result, 42)
  assert_eq(during, [5, 21, 5])
  assert_eq(host.stage, 0)
  assert_eq(host.seen, [5, 21, 5, 0])
}
