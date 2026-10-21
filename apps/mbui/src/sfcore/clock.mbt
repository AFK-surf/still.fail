// The core's timers in a run on a clock of its own (@ui.own_clock: a settled screenshot run, Android's shot_at, the
// web's) on the app's runtime (@core.own_clock): the host's clock the runtime runs on (read by the core's client, which
// tells the core it), a fiber's sleep for each wait (let go by interrupting it, its timer with it), its outside for the
// core running what is due.

///|
fn own_core_clock() -> Unit {
  if !@ui.own_clock() {
    return
  }
  let rt = @ui.runtime()
  // (from the first frame on: the host's clock is the run's own from there, not before its window runs)
  rt.fork(
    async fn() {
      @effect.next_frame()
      take_core_clock(rt)
    },
    name="core: its clock",
  )
  |> ignore
}

///|
fn take_core_clock(rt : @effect.Runtime) -> Unit {
  @core.own_clock({
    now: @ui.now,
    wait: fn(ms, later, then) {
      let f = rt.fork(
        async fn() {
          @effect.sleep(ms, later~)
          then()
        },
        name=if later { "core: timers (later)" } else { "core: timers" },
      )
      fn() { f.interrupt() }
    },
    start: what => rt.outside_start(what),
    end: t => rt.outside_end(t),
    log: if @ui.env("MB_CORE_TRACE") == "1" {
      Some(fn(s) { @hostapi.log(s) })
    } else {
      None
    },
  })
}
