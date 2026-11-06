///|
extern "js" fn capture_fault_calls() -> Unit =
  #|() => { globalThis.__faultTestPreviousCore = globalThis.__mbcore; globalThis.__faultTestCalls = []; globalThis.__mbcore = { send: (json) => globalThis.__faultTestCalls.push(JSON.parse(json)) }; }

///|
extern "js" fn captured_fault_calls() -> String =
  #|() => JSON.stringify(globalThis.__faultTestCalls)

///|
extern "js" fn restore_fault_core() -> Unit =
  #|() => { globalThis.__mbcore = globalThis.__faultTestPreviousCore; delete globalThis.__faultTestPreviousCore; delete globalThis.__faultTestCalls; }

///|
struct FaultLogHost {
  logs : Array[String]
}

///|
impl @hostapi.Host for FaultLogHost with log(self, said) {
  self.logs.push(said)
}

///|
test "layout faults report fixed kinds without their dynamic details" {
  let previous = @view.fault_told.val
  let stopped = @view.faults_stop.val
  let host = @hostapi.host()
  let captured = FaultLogHost::{ logs: [] }
  @hostapi.set_host(captured)
  @core.client.reset()
  capture_fault_calls()
  defer {
    @view.fault_told.val = previous
    @view.faults_stop.val = stopped
    @hostapi.set_host(host)
    @core.client.reset()
    restore_fault_core()
  }
  reports_start()
  @view.faults_stop.val = false
  @view.fault("view: marked in its own layout, after it was laid out: /sentinel-layout/secret.txt")
  @view.fault("view: 64 layout passes in one, each telling what marks another; told otherwise in the last: /sentinel-layout/secret.txt")
  @view.fault("layout_box node /sentinel-layout/secret.txt: children changed after they were measured")
  let names = ["layout marked during layout", "layout pass limit", "layout box fault"]
  assert_eq(captured.logs, names.map(fn(s) { "ui fault: " + s }))
  let calls = captured_fault_calls()
  assert_true(!calls.contains("sentinel-layout") && !calls.contains("secret.txt"))
  let parsed = @json.parse(calls) catch { _ => Json::null() }
  guard parsed is Array(a) else { fail("expected a list of core calls") }
  assert_eq(a.length(), names.length())
  for i in 0..<names.length() {
    guard a[i] is Object(call) else { fail("expected a core call") }
    guard call.get("params") is Some(Object(params)) else { fail("expected call parameters") }
    assert_eq(params.get("source"), Some(Json::string("ui_fault")))
    assert_eq(params.get("message"), Some(Json::string(names[i])))
  }
}

///|
test "UI fault reporting uses fixed categories even for unknown text" {
  assert_eq(ui_fault_category("Ctx::editor: a Field given to C:\\private\\file that a field of the window's tree holds"), "editor field already in tree")
  assert_eq(ui_fault_category("field: one Field given to two fields of the tree's: a Field is one editor's"), "tree field reused")
  assert_eq(ui_fault_category("scene: a frame put together round layers drawn again where they were not kept: private"), "scene layer conflict")
  assert_eq(ui_fault_category("presented beside a node of the tree, drawn by the old frame: a kind of panel panel_node does not take yet"), "panel cannot be presented")
  assert_eq(ui_fault_category("unknown /private/secret.txt"), "UI fault")
}

///|
test "a UI fault on a host without its own reporter reaches the core once" {
  let previous = @view.fault_told.val
  let stopped = @view.faults_stop.val
  @core.client.reset()
  capture_fault_calls()
  defer {
    @view.fault_told.val = previous
    @view.faults_stop.val = stopped
    @core.client.reset()
    restore_fault_core()
  }
  reports_start()
  @view.faults_stop.val = false
  @view.fault("reporting-test-fault")
  @view.fault("reporting-test-fault")
  let calls = @json.parse(captured_fault_calls()) catch { _ => Json::null() }
  guard calls is Array(a) else { fail("expected a list of core calls") }
  assert_eq(a.length(), 1)
  guard a[0] is Object(call) else { fail("expected a core call") }
  assert_eq(call.get("call"), Some(Json::string("client.error")))
  guard call.get("params") is Some(Object(params)) else { fail("expected call parameters") }
  assert_eq(params.get("source"), Some(Json::string("ui_fault")))
  assert_eq(params.get("message"), Some(Json::string("UI fault")))
}

///|
test "a Field conflict reports its kind without editor paths or filenames" {
  let previous = @view.fault_told.val
  let stopped = @view.faults_stop.val
  let host = @hostapi.host()
  @core.client.reset()
  capture_fault_calls()
  defer {
    @view.fault_told.val = previous
    @view.faults_stop.val = stopped
    @core.client.reset()
    restore_fault_core()
  }
  reports_start()
  @view.faults_stop.val = false
  let field = @ui.Field::new()
  let t = @ui.Tester::new(
    fn(c) {
      c.editor("files/row/sentinel-private-folder/first-secret.txt", font_size=10.0, field~) |> ignore
      c.editor("files/row/sentinel-private-folder/second-secret.txt", font_size=10.0, field~) |> ignore
    },
    w=300.0,
    h=100.0,
    time=1000.0,
  )
  defer t.end_run(host)
  let film = t.film("exit", draw=fn(_) { true }, put=fn(_) { true })
  let log = film.logs.join("\n")
  assert_true(log.contains("ui fault:"), msg="the fault reached the host log")
  let calls = captured_fault_calls()
  assert_eq(
    (log.contains("sentinel-private-folder") || log.contains("secret.txt"), calls.contains("sentinel-private-folder") || calls.contains("secret.txt")),
    (false, false),
  )
  let parsed = @json.parse(calls) catch { _ => Json::null() }
  guard parsed is Array(a) else { fail("expected a list of core calls") }
  assert_eq(a.length(), 1)
  guard a[0] is Object(call) else { fail("expected a core call") }
  guard call.get("params") is Some(Object(params)) else { fail("expected call parameters") }
  assert_eq(params.get("source"), Some(Json::string("ui_fault")))
  assert_eq(params.get("message"), Some(Json::string("editor field reused")))
}
