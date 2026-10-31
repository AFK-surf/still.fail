// The update's contract (scripts/host_contract.sh mac update, linux update): on a real host, the app a bundle signed as
// the build it is handed (Linux: a folder installed as an app, its VERSION beside it),
// MBUI_UPDATECHECK=<url>|<sha256>|<size>|<name>: that build handed to the host to make ready (@hostapi.update_fetch,
// as still.fail's app hands it what the core found) and, once ready, put in this one's place (update_apply), this
// build's version on the log
// (`UPDATECHECK version N`), then how it goes each time that changes (`UPDATECHECK state {…}`). Once the new build
// is in place the host quits this app and opens that one; one it does not take is `failed`, and why, on the log, and
// the run ends.

///|
let update_check_asked : Ref[Bool] = Ref(false)

///|
let update_check_said : Ref[String] = Ref("")

///|
pub fn update_check_run(c : @ui.Ctx, asked : String) -> Unit {
  if !update_check_asked.val {
    update_check_asked.val = true
    match asked.split("|").map(fn(s) { s.to_string() }).to_array() {
      [url, sha256, size, name] => {
        @hostapi.log("UPDATECHECK version \{@hostapi.app_version()}")
        let size = @string.parse_int(size) catch { _ => 0 }
        @ui.update_fetch(url, sha256, size.to_double(), name, true)
      }
      _ => @hostapi.log("UPDATECHECK MBUI_UPDATECHECK is url|sha256|size|name")
    }
  }
  // (how it goes: each change of it brings a frame of its own, ui's outside_update)
  let st = @ui.update_state()
  if st != update_check_said.val {
    update_check_said.val = st
    @hostapi.log("UPDATECHECK state " + st)
    // one the host would not take: the run ends here (taken, the host ends it)
    let v = @json.parse(st) catch { _ => Json::null() }
    if v is Object(o) && o.get("phase") is Some(String("failed")) {
      c.after_build("update-check-end", fn() { @hostapi.exit(0) })
    }
    // ready: put in place (the host ends this run)
    if v is Object(o) && o.get("phase") is Some(String("ready")) {
      @ui.update_apply("")
    }
  }
  c.text("update check") |> ignore
}
