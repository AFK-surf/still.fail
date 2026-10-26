// The notifications' contract (scripts/host_contract.sh linux notices): on a real host, MBUI_NOTICECHECK=1: one
// notification shown once it has drawn (`NOTICECHECK shown` on the log), then what the one clicked opens (clicked on
// the desktop, or by the run's script: MBUI_DRIVE's `notice 通知检查`, which the host takes as the desktop's click) as
// `NOTICECHECK opened <opens>`, and the run's end.

///|
let notice_check_shown : Ref[Bool] = Ref(false)

///|
/// what the one clicked opens, once read (a frame built again reads none: it is said once the frame's builds are over)
let notice_check_opened : Ref[String] = Ref("")

///|
pub fn notice_check_run(c : @ui.Ctx) -> Unit {
  if !notice_check_shown.val {
    notice_check_shown.val = true
    c.after_build("notice-check-show", fn() {
      @ui.notice_show(
        channel="检查",
        tag="notice-check",
        title="通知检查",
        body="点开这条通知",
        opens="noticecheck://opened",
      )
      @hostapi.log("NOTICECHECK shown")
    })
  }
  let opened = @ui.notice_opened()
  if opened != "" {
    notice_check_opened.val = opened
  }
  if notice_check_opened.val != "" {
    c.after_build("notice-check-opened", fn() {
      @hostapi.log("NOTICECHECK opened " + notice_check_opened.val)
      @hostapi.exit(0)
    })
  }
  c.text("notice check") |> ignore
}
