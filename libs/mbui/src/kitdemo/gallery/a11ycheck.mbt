// The accessibility's contract (scripts/host_contract.sh windows a11y): on a real host, MBUI_A11YCHECK=1: a field
// ("A11YCHECK field"), a button ("A11YCHECK press") and a checkbox ("A11YCHECK check", off) for the system's
// accessibility to read out and write in; the button activated as a reader asks it (UI Automation's Invoke) says so on
// the log with the field's words (`A11YCHECK activated <words>`), and the app ends.

///|
let a11y_check_box : Ref[@ui.Check] = Ref(Off)

///|
let a11y_check_field : @ui.Field = @ui.Field::new()

///|
pub fn a11y_check_run(c : @ui.Ctx) -> Unit {
  c.editor("a11y-field", placeholder="A11YCHECK field", field=a11y_check_field) |> ignore
  if @kit.button(c, "A11YCHECK press", key="a11y-press").clicked {
    c.tell("a11y-check", fn() {
      @hostapi.log("A11YCHECK activated \{a11y_check_field.text()}")
      @hostapi.exit(0)
    })
  }
  a11y_check_box.val = @kit.checkbox(c, "a11y-check", a11y_check_box.val, label="A11YCHECK check").value
}
