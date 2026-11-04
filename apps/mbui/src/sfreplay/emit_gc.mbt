///|
/// Where a flow's steps go as a scripted run's (FLOW_EMIT, scripts/rerecord.sh): "" when nothing asks for them.
fn emit_path() -> String {
  @env.get_env_var("FLOW_EMIT").unwrap_or("")
}

///|
fn write_file(path : String, text : String) -> Unit {
  @runfs.write(path, @utf8.encode(text)) |> ignore
}
