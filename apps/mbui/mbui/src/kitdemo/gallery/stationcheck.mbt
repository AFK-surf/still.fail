// This machine's station's contract (scripts/host_contract.sh linux station): on a real host, MBUI_STATIONCHECK=read:
// the station as the host says it (@ui.local_station: whether it runs and by what, its release, its workspace, its
// data) on the log (`STATIONCHECK read <json>`), then the app's end; =stop: the same, then it stopped
// (local_station_act stop) and, once nothing is being done to it, said again (`STATIONCHECK after <json>`). The host
// asks for a frame as what it does ends: each frame's work only asks whether it has.

///|
let station_check_stopped : Ref[Bool] = Ref(false)

///|
fn station_check_step(how : String) -> Unit {
  let now = @ui.local_station()
  if !station_check_stopped.val {
    @hostapi.log("STATIONCHECK read " + now)
    if how != "stop" {
      @hostapi.exit(0)
      return
    }
    station_check_stopped.val = true
    @ui.local_station_act("stop")
    return
  }
  if !now.contains("\"doing\"") {
    @hostapi.log("STATIONCHECK after " + now)
    @hostapi.exit(0)
  }
}

///|
pub fn station_check_run(c : @ui.Ctx, how : String) -> Unit {
  c.after_build("station-check", fn() { station_check_step(how) })
  c.text("station check") |> ignore
}
