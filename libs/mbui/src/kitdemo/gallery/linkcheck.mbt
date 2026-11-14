// The links' contract (scripts/host_contract.sh mac links, linux links): on a real host, the app a bundle whose
// Info.plist names a scheme of its own (Linux: a program with an identity and schemes of its own, MBUI_APP_ID and
// MBUI_SCHEMES), MBUI_LINKCHECK=1: `LINKCHECK ready` on the log once it has drawn, then the first link the system opens
// it with (the host's `link` on the system channel: mac_app.m application:openURLs:, linux_life.h) as
// `LINKCHECK link <url>`, and the run's end.

///|
let link_check_ready : Ref[Bool] = Ref(false)

///|
pub fn link_check_run(c : @ui.Ctx) -> Unit {
  if !link_check_ready.val {
    link_check_ready.val = true
    c.after_build("link-check-ready", fn() { @hostapi.log("LINKCHECK ready") })
  }
  c.text("link check") |> ignore
}

///|
/// What the system said (MBUI_LINKCHECK's handler of the system channel): a link said, and the run ends.
pub fn link_check_said(json : String) -> Unit {
  for s in @hostapi.system_said(json) {
    if s is Link(url) {
      @hostapi.log("LINKCHECK link " + url)
      @hostapi.exit(0)
    }
  }
}
