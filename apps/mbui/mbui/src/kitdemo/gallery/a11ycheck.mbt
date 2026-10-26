// The accessibility's contract (scripts/host_contract.sh windows a11y): on a real host, MBUI_A11YCHECK=1: a button
// ("A11YCHECK press") and a checkbox ("A11YCHECK check", off) for the system's accessibility to read out; the button
// activated as a reader asks it (UI Automation's Invoke) says so on the log (`A11YCHECK activated`), and the app ends.

///|
let a11y_check_box : Ref[@ui.Check] = Ref(Off)

///|
pub fn a11y_check_run(c : @ui.Ctx) -> Unit {
  if @kit.button(c, "A11YCHECK press", key="a11y-press").clicked {
    c.after_build("a11y-check", fn() {
      @hostapi.log("A11YCHECK activated")
      @hostapi.exit(0)
    })
  }
  a11y_check_box.val = @kit.checkbox(c, "a11y-check", a11y_check_box.val, label="A11YCHECK check").value
}
