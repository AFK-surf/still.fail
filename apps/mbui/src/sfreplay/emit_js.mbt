///|
/// Where a flow's steps go as a scripted run's (FLOW_EMIT, scripts/rerecord.sh): "" when nothing asks for them.
extern "js" fn emit_path() -> String =
  #|() => (typeof process !== "undefined" && process.env.FLOW_EMIT) || ""

///|
extern "js" fn write_file(path : String, text : String) -> Unit =
  #|(path, text) => require("fs").writeFileSync(path, text)
