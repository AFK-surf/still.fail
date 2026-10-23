///|
/// The process's environment (scripts/screens-dump.sh: MBUI_SCREEN_DUMP).
fn dump_env(name : String) -> String {
  @env.get_env_var(name).unwrap_or("")
}
