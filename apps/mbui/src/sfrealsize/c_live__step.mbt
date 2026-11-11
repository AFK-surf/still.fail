// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `live` as `step`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"live","station":"ws/maple","key":"k-maple-0"}
  let messages =
    #|[{"value":{"activity":{"now":{"key":"call-160","text":"运行","mono":true,"important":null}}}}]
  put_changes(asked, "step", messages)
}
