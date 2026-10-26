// The clipboard's secrets' contract (scripts/host_contract.sh windows secret): on a real host, MBUI_SECRETCHECK=kept|
// left|end: once the first frame is built, a secret copied (`SECRETCHECK put <how>` on the log) and the app's end, for
// the run to read the clipboard after it: kept, a secret to stay (clear_ms 0); left, one to be taken off in a minute,
// other words copied right after it (what is to stay); end, one to be taken off in a minute, the app ending first.

///|
let secret_check_put : Ref[Bool] = Ref(false)

///|
pub fn secret_check_run(c : @ui.Ctx, how : String) -> Unit {
  if !secret_check_put.val {
    secret_check_put.val = true
    c.after_build("secret-check", fn() {
      match how {
        "kept" => @hostapi.clipboard_set_secret("SECRETCHECK kept", clear_ms=0.0)
        "left" => {
          @hostapi.clipboard_set_secret("SECRETCHECK left", clear_ms=60000.0)
          @hostapi.clipboard_set("SECRETCHECK other")
        }
        _ => @hostapi.clipboard_set_secret("SECRETCHECK end", clear_ms=60000.0)
      }
      @hostapi.log("SECRETCHECK put \{how}")
      @hostapi.exit(0)
    })
  }
  c.text("secret check") |> ignore
}
