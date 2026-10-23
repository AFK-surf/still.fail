// The marks' contract (docs/determinism.md, "What is compared, and where"; scripts/host_contract.sh HOST marks): on a
// real host, MBUI_MARKS=<the marks' JSON, base64> MBUI_MARKS_IMAGE=<the picture's bytes, base64> (test/marks/): the
// marks drawn onto the picture by the host (@hostapi.draw_marks), the PNG it made written on the log in base64 (`MARKS
// png <part>` lines, then `MARKS done N bytes`), then the app's end. `MARKS none` where the host draws none (Windows,
// the web), `MARKS failed` where it could not: the app ends with 1. The host asks for a frame once the PNG is made:
// each frame's build only asks whether it is.

///|
/// The drawing asked for (once, in the first frame's build), while the host draws it.
let marks_job : Ref[@hostapi.MarkedImage?] = Ref(None)

///|
let marks_started : Ref[Bool] = Ref(false)

///|
/// MBUI_MARKS: the drawing asked for, then, once the host has made it, the PNG on the log and the app's end.
pub fn marks_run(c : @ui.Ctx, marks : String, image : String) -> Unit {
  if !marks_started.val {
    marks_started.val = true
    match @hostapi.draw_marks(@codec.from_base64(image), @hostapi.from_base64(marks)) {
      Some(job) => marks_job.val = Some(job)
      None => {
        @hostapi.log("MARKS none: this host draws no marks")
        @hostapi.exit(1)
      }
    }
  }
  match marks_job.val {
    Some(job) =>
      match job.made() {
        Some(png) => {
          marks_job.val = None
          if png.length() == 0 {
            @hostapi.log("MARKS failed: the host could not draw them")
            @hostapi.exit(1)
          } else {
            // in parts (a log line of a few kB: logcat's, the simulator's stderr)
            let text = @codec.base64(png)
            let part = 3000
            let mut at = 0
            while at < text.length() {
              let end = if at + part < text.length() { at + part } else { text.length() }
              @hostapi.log("MARKS png " + text.view(start_offset=at, end_offset=end).to_owned())
              at = end
            }
            @hostapi.log("MARKS done \{png.length()} bytes")
            @hostapi.exit(0)
          }
        }
        None => ()
      }
    None => ()
  }
  c.text("MARKS") |> ignore
}
