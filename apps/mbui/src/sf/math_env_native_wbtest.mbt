///|
fn math_evidence() -> String {
  @env.get_env_var("MATH_EVIDENCE").unwrap_or("")
}
