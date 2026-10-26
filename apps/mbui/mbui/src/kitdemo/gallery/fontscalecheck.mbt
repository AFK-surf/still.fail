// The size of words' contract (scripts/host_contract.sh windows fontscale): on a real host, MBUI_FONTSCALECHECK=1: the
// system's setting for the size of words as the host gives it (`FONTSCALE <times>` on the log), once the first frame
// is built, and the app's end.

///|
let font_scale_said : Ref[Bool] = Ref(false)

///|
pub fn font_scale_check_run(c : @ui.Ctx) -> Unit {
  if !font_scale_said.val {
    font_scale_said.val = true
    c.after_build("font-scale-check", fn() {
      @hostapi.log("FONTSCALE \{@ui.font_scale()}")
      @hostapi.exit(0)
    })
  }
  c.text("font scale check") |> ignore
}
