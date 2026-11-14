// The dock's number's contract (scripts/host_contract.sh linux badge): on a real host, MBUI_BADGECHECK=<n>: the number
// on the app's icon set to n once the first frame is built (`BADGECHECK set <n>` on the log), the app left running for
// the run to ask the desktop's side what it was told.

///|
let badge_check_set : Ref[Bool] = Ref(false)

///|
pub fn badge_check_run(c : @ui.Ctx, n : String) -> Unit {
  if !badge_check_set.val {
    badge_check_set.val = true
    let mut count = 0
    for ch in n {
      if ch >= '0' && ch <= '9' {
        count = count * 10 + (ch.to_int() - '0'.to_int())
      }
    }
    c.after_build("badge-check", fn() {
      @hostapi.set_badge(count)
      @hostapi.log("BADGECHECK set \{count}")
    })
  }
  c.text("badge check") |> ignore
}
