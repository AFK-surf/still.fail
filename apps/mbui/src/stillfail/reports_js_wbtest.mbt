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
  assert_eq(params.get("message"), Some(Json::string("reporting-test-fault")))
}
