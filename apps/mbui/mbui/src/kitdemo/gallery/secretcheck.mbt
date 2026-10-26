// The clipboard's secrets' contract (scripts/host_contract.sh windows secret): on a real host, MBUI_SECRETCHECK=kept|
// taken|left|end: once the first frame is built, a secret copied (`SECRETCHECK put <how>` on the log), then the app's
// end, for the run to read the clipboard after it: kept, a secret to stay (clear_ms 0); taken, one to be taken off 300
// ms later, the app ending after that on its clock; left, one to be taken off in a minute, other words copied right
// after it (what is to stay); end, one to be taken off in a minute, the app ending first.

///|
let secret_check_put : Ref[Bool] = Ref(false)

///|
pub fn secret_check_run(c : @ui.Ctx, how : String) -> Unit {
  if !secret_check_put.val {
    secret_check_put.val = true
    c.after_build("secret-check", fn() {
      match how {
        "kept" => c.copy_secret("SECRETCHECK kept", clear_ms=0.0)
        "taken" => c.copy_secret("SECRETCHECK taken", clear_ms=300.0)
        "left" => {
          c.copy_secret("SECRETCHECK left", clear_ms=60000.0)
          c.copy_text("SECRETCHECK other")
        }
        _ => c.copy_secret("SECRETCHECK end", clear_ms=60000.0)
      }
      @hostapi.log("SECRETCHECK put \{how}")
      // (taken: after its taking off, on the same clock)
      if how == "taken" {
        @ui.runtime().after(301, fn() { @hostapi.exit(0) })
      } else {
        @hostapi.exit(0)
      }
    })
  }
  c.text("secret check") |> ignore
}
